import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct PullToRefreshTests {
    @Test func viewReevaluationDoesNotAbortRefreshButLeavingScreenDoes() async {
        let deadline = ManualRefreshDeadline()
        defer { deadline.cancel() }
        let coordinator = AppRefreshCoordinator()
        let gate = ReadGate<Int>()
        var result: Int?
        let pull = Task { await coordinator.perform {
            result = try? await RefreshRequest.run(deadline: deadline.sleep) { await gate.wait() }
        } }
        await gate.waitUntilStarted()
        pull.cancel() // SwiftUI replaces the transient handler after a state publication.
        gate.complete(42)
        await pull.value
        #expect(result == 42)

        let leavingGate = ReadGate<Int>()
        result = nil
        let nextPull = Task { await coordinator.perform {
            result = try? await RefreshRequest.run(deadline: deadline.sleep) { await leavingGate.wait() }
        } }
        await leavingGate.waitUntilStarted()
        coordinator.cancel()
        await nextPull.value
        #expect(result == nil)
        leavingGate.complete(99)
    }

    @Test func repeatedGestureSharesPendingRefresh() async {
        let coordinator = AppRefreshCoordinator()
        let gate = ReadGate<Int>()
        var calls = 0
        let first = Task { await coordinator.perform { calls += 1; _ = await gate.wait() } }
        await gate.waitUntilStarted()
        let second = Task { await coordinator.perform { calls += 1 } }
        for _ in 0..<10 { await Task.yield() }
        #expect(calls == 1)
        gate.complete(0)
        await first.value; await second.value
        #expect(calls == 1)
    }

    @Test func deadlineFinishesEvenWhenSDKIgnoresCancellation() async throws {
        let deadline = ManualRefreshDeadline()
        defer { deadline.cancel() }
        let gate = ReadGate<Int>()
        let read = Task { try await RefreshRequest.run(timeout: .milliseconds(25), deadline: deadline.sleep) { await gate.wait() } }
        await gate.waitUntilStarted()
        await deadline.waitUntilScheduled()
        #expect(deadline.durations == [.milliseconds(25)])
        deadline.expire()
        do { _ = try await read.value; Issue.record("Expected timeout") }
        catch { #expect(error as? AppError == .network) }
        // A late SDK callback must not resume the refresh twice or publish its data.
        gate.complete(42)
        for _ in 0..<10 { await Task.yield() }
    }

    @Test func cancelledReadFinishesWithoutWaitingForSDK() async {
        let deadline = ManualRefreshDeadline()
        defer { deadline.cancel() }
        let gate = ReadGate<Int>()
        let read = Task { try await RefreshRequest.run(deadline: deadline.sleep) { await gate.wait() } }
        await gate.waitUntilStarted()
        read.cancel()
        do { _ = try await read.value; Issue.record("Expected cancellation") }
        catch { #expect(error is CancellationError) }
        gate.complete(42)
    }

    @Test func successfulReadAndOriginalFailurePropagate() async throws {
        #expect(try await RefreshRequest.run { 42 } == 42)
        do { _ = try await RefreshRequest.run { () -> Int in throw AppError.permissionDenied } }
        catch { #expect(error as? AppError == .permissionDenied) }
    }

    @Test func productionClockStillExpiresAnUnresponsiveRead() async {
        let gate = ReadGate<Int>()
        defer { gate.complete(42) }
        do {
            _ = try await RefreshRequest.run(timeout: .zero) { await gate.wait() }
            Issue.record("The continuous deadline must reject an unresponsive read")
        } catch {
            #expect(error as? AppError == .network)
        }
    }

    @Test func detailRefreshRetainsListAndPaginationAndAwaitsNewUser() async {
        let fixture = ManagementReadFixture()
        let model = UserManagementViewModel(reads: fixture.reads)
        let actor = MockContentBuilder.ownerUser()
        await model.load(actor: actor)
        let original = model.users
        fixture.userGate = ReadGate<AppUser?>()
        let refresh = Task { await model.refreshDetail(userID: original[0].id, actor: actor) }
        await fixture.userGate?.waitUntilStarted()
        #expect(model.users.map(\.id) == original.map(\.id))
        #expect(model.canLoadMore)
        #expect(fixture.pageReads == 1)
        #expect(!model.isLoading)
        let updated = AppUser(id: original[0].id, fullName: original[0].fullName, displayName: "Updated remotely", city: original[0].city, email: original[0].email, bio: "", role: .user, blockState: .active, createdAt: original[0].createdAt, updatedAt: .now)
        fixture.userGate?.complete(updated)
        await refresh.value
        #expect(model.users.map(\.id) == original.map(\.id))
        #expect(model.user(withID: updated.id)?.displayName == "Updated remotely")
        #expect(model.canLoadMore)
        #expect(fixture.pageReads == 1)
        #expect(model.error == nil)
    }

    @Test func failedListRefreshRetainsContentAndCanRetry() async {
        let fixture = ManagementReadFixture()
        let model = UserManagementViewModel(reads: fixture.reads)
        let actor = MockContentBuilder.ownerUser()
        await model.load(actor: actor)
        let original = model.users
        fixture.fail = true
        await model.refresh(actor: actor)
        #expect(model.users.map(\.id) == original.map(\.id))
        #expect(model.error != nil)
        #expect(!model.isLoading)
        fixture.fail = false
        await model.refresh(actor: actor)
        #expect(model.error == nil)
        #expect(!model.isLoading)
    }

    @Test func pendingDetailCannotRestoreDataAfterPermissionLoss() async {
        let fixture = ManagementReadFixture()
        let model = UserManagementViewModel(reads: fixture.reads)
        let actor = MockContentBuilder.ownerUser()
        await model.load(actor: actor)
        fixture.userGate = ReadGate<AppUser?>()
        let refresh = Task { await model.refreshDetail(userID: fixture.member.id, actor: actor) }
        await fixture.userGate?.waitUntilStarted()
        await model.refresh(actor: nil)
        fixture.userGate?.complete(fixture.member)
        await refresh.value
        #expect(model.users.isEmpty)
        #expect(model.organizations.isEmpty)
        #expect(model.securityMetadata(for: fixture.member.id) == nil)
    }

    @Test func presenceCoalescesPollAndPullAndPublishesBeforeBothFinish() async {
        let deadline = ManualRefreshDeadline()
        defer { deadline.cancel() }
        let gate = ReadGate<ManagedUserPresenceSnapshot>()
        let coalesced = ReadGate<Void>()
        var count = 0
        let model = ManagedUserPresenceViewModel(
            load: { _ in count += 1; return await gate.wait() },
            readDeadline: deadline.sleep,
            onRequestCoalesced: { coalesced.complete(()) }
        )
        let actor = MockContentBuilder.ownerUser()
        let poll = Task { await model.refresh(userID: "member", actor: actor) }
        await gate.waitUntilStarted()
        let pull = Task { await model.refresh(userID: "member", actor: actor) }
        let didCoalesce = await coalesced.waitForCompletion(timeout: .seconds(5))
        #expect(didCoalesce, "The pull refresh did not join the pending presence request")
        #expect(count == 1)
        #expect(model.isRefreshing)
        gate.complete(Self.presence(online: true))
        await pull.value
        #expect(model.snapshot?.isOnline() == true)
        #expect(!model.isRefreshing)
        await poll.value
        #expect(count == 1)
    }

    @Test func presenceRefreshShowsOfflineAndRecoversAfterFailure() async {
        var fail = false
        var online = true
        let model = ManagedUserPresenceViewModel(load: { _ in
            if fail { throw AppError.network }
            return Self.presence(online: online)
        })
        let actor = MockContentBuilder.ownerUser()
        await model.refresh(userID: "member", actor: actor)
        #expect(model.snapshot?.isOnline() == true)
        fail = true
        await model.refresh(userID: "member", actor: actor)
        #expect(model.failed)
        #expect(model.snapshot != nil)
        #expect(!model.isRefreshing)
        fail = false; online = false
        await model.refresh(userID: "member", actor: actor)
        #expect(!model.failed)
        #expect(model.snapshot?.isOnline() == false)
        #expect(model.snapshot?.lastSeenAt != nil)
        await model.refresh(userID: "member", actor: nil)
        #expect(model.snapshot == nil)
    }

    private static func presence(online: Bool) -> ManagedUserPresenceSnapshot {
        let now = Date().timeIntervalSince1970 * 1_000
        return ManagedUserPresenceSnapshot(response: ManagedUserPresenceResponse(targetUserId: "member",
            lastSeenAt: now, onlineUntil: online ? now + 60_000 : nil, serverTime: now), requestStartedAt: .now)
    }
}

@MainActor
private final class ReadGate<Value> {
    private enum State {
        case pending
        case completed(Value)
    }

    private var continuations: [CheckedContinuation<Value, Never>] = []
    private var state = State.pending
    private var hasStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func wait() async -> Value {
        hasStarted = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        if case .completed(let value) = state {
            return value
        }
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func complete(_ value: Value) {
        guard case .pending = state else { return }
        state = .completed(value)
        let waiters = continuations
        continuations.removeAll()
        waiters.forEach { $0.resume(returning: value) }
    }

    func waitUntilStarted() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }
}

private extension ReadGate where Value == Void {
    func waitForCompletion(timeout: Duration) async -> Bool {
        do {
            _ = try await RefreshRequest.run(timeout: timeout) { await self.wait() }
            return true
        } catch {
            complete(())
            return false
        }
    }
}

@MainActor
private final class ManagementReadFixture {
    var pageReads = 0
    var fail = false
    var userGate: ReadGate<AppUser?>?
    let member = MockContentBuilder.currentUser()
    var reads: UserManagementReads {
        UserManagementReads(users: { [self] _ in
            pageReads += 1
            if fail { throw AppError.network }
            return .init(users: [member, MockContentBuilder.ownerUser()], cursor: nil, hasMore: true)
        }, user: { [self] _ in
            if let userGate { return await userGate.wait() }
            if fail { throw AppError.network }
            return member
        }, organizations: { [self] in
            if fail { throw AppError.network }
            return []
        }, securityMetadata: { id in
            ManagedUserSecurityMetadata(response: .init(targetUserId: id, emailVerified: true,
                authDisabled: false, creationTime: nil, lastSignInTime: nil, providerIds: ["password"]))
        })
    }
}
