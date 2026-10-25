import Foundation
import Testing
@testable import UkrainianCommunity

@Suite(.serialized) @MainActor struct ManagedUserAuditStoreTests {
    private func item(_ id: String) -> ManagedUserAuditItem {
        .init(id: id, actionType: "userWarned", reason: "Review reason", performedBy: "owner", previousValue: [:], newValue: [:], createdAt: Date(timeIntervalSince1970: 1000))
    }
    @Test func refreshFailureRetainsConfirmedHistoryAndRecovers() async {
        var fails = false
        let model = ManagedUserAuditStore { _, _ in
            if fails { throw AppError.network }
            return .init(items: [item("saved")], cursor: nil, hasMore: false)
        }
        let owner = MockContentBuilder.ownerUser()
        await model.ensure(userID: "target", actor: owner, refreshToken: "first")
        fails = true
        await model.ensure(userID: "target", actor: owner, refreshToken: "refresh")
        #expect(model.failed); #expect(model.items.map(\.id) == ["saved"])
        fails = false
        await model.retry(userID: "target")
        #expect(!model.failed); #expect(model.hasLoaded)
    }
    @Test func refreshDuringPendingReadStartsReplacementAndIgnoresOldResponse() async {
        var calls = 0; let gate = AuditReadGate()
        let model = ManagedUserAuditStore { _, _ in
            calls += 1
            if calls == 1 { return await gate.wait() }
            return .init(items: [item("new")], cursor: nil, hasMore: false)
        }
        let owner = MockContentBuilder.ownerUser()
        let pending = Task { await model.ensure(userID: "target", actor: owner, refreshToken: "old") }
        while !gate.started { await Task.yield() }
        await model.ensure(userID: "target", actor: owner, refreshToken: "new")
        gate.finish(.init(items: [item("old")], cursor: nil, hasMore: false))
        await pending.value
        #expect(calls == 2); #expect(model.items.map(\.id) == ["new"])
    }
    @Test func duplicateOpenSharesReadAndReturnKeepsConfirmedHistory() async {
        var calls = 0; let gate = AuditReadGate()
        let model = ManagedUserAuditStore { _, _ in calls += 1; return await gate.wait() }
        let owner = MockContentBuilder.ownerUser()
        let first = Task { await model.ensure(userID: "target", actor: owner, refreshToken: "same") }
        while !gate.started { await Task.yield() }
        let second = Task { await model.ensure(userID: "target", actor: owner, refreshToken: "same") }
        for _ in 0..<20 { await Task.yield() }
        #expect(calls == 1)
        gate.finish(.init(items: [item("confirmed")], cursor: nil, hasMore: false))
        await first.value; await second.value
        await model.ensure(userID: "target", actor: owner, refreshToken: "same")
        #expect(calls == 1); #expect(model.items.map(\.id) == ["confirmed"])
    }
    @Test func failedNextPageRetriesExactCursorAndKeepsEarlierHistory() async {
        let next = ManagedUserAuditCursor(seconds: 100, nanoseconds: 123, id: "first")
        var fails = true; var requested: [ManagedUserAuditCursor?] = []
        let model = ManagedUserAuditStore { _, cursor in
            requested.append(cursor)
            if cursor == nil { return .init(items: [item("first")], cursor: next, hasMore: true) }
            if fails { throw AppError.network }
            return .init(items: [item("first"), item("second")], cursor: nil, hasMore: false)
        }
        await model.ensure(userID: "target", actor: MockContentBuilder.ownerUser(), refreshToken: "first")
        await model.more(userID: "target")
        #expect(model.failed); #expect(model.items.map(\.id) == ["first"])
        fails = false
        await model.retry(userID: "target")
        #expect(requested == [nil, next, next]); #expect(model.items.map(\.id) == ["first", "second"])
        #expect(!model.hasMore)
        await model.more(userID: "other")
        #expect(requested.count == 3)
    }
    @Test func accountChangeClearsHistoryAndRejectsLateResult() async {
        let gate = AuditReadGate()
        let model = ManagedUserAuditStore { _, _ in await gate.wait() }
        let first = Task { await model.ensure(userID: "target", actor: MockContentBuilder.ownerUser(), refreshToken: "same") }
        while !gate.started { await Task.yield() }
        await model.ensure(userID: "target", actor: nil, refreshToken: "same")
        gate.finish(.init(items: [item("private")], cursor: nil, hasMore: false))
        await first.value
        #expect(model.items.isEmpty); #expect(!model.isLoading); #expect(!model.hasLoaded)
    }
}
@MainActor private final class AuditReadGate {
    var started = false
    private var continuation: CheckedContinuation<ManagedUserAuditPage, Never>?
    func wait() async -> ManagedUserAuditPage { started = true; return await withCheckedContinuation { continuation = $0 } }
    func finish(_ value: ManagedUserAuditPage) { continuation?.resume(returning: value); continuation = nil }
}
