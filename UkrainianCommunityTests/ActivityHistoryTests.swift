import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct ActivityHistoryTests {
    private func item(_ id: String, time: Date = Date()) -> ActivityLogItem {
        ActivityLogItem(id: id, actionType: .savedNews, targetId: id, targetType: .news, title: id, subtitle: nil, imageURL: nil, createdAt: time)
    }

    @Test func pendingWriteAcknowledgementDoesNotDelayReadableHistory() async {
        let repo = ActivityHistoryRepository()
        let row = item("available")
        repo.fetch = { _ in [row] }
        var pending: CheckedContinuation<AppError?, Never>?
        let model = ActivityLogViewModel(repository: repo, synchronizePending: { _ in
            await withCheckedContinuation { pending = $0 }
        })
        let refresh = Task { await model.loadIfNeeded(userID: "a") }
        for _ in 0..<200 { if pending != nil { break }; await Task.yield() }
        #expect(pending != nil)
        #expect(model.items == [row])
        #expect(!model.isLoading)
        // A delayed acknowledgement is still shown as an error when received.
        pending?.resume(returning: .network)
        await refresh.value
        #expect(model.items == [row] && model.error == .network)
    }

    @Test func newViewsDeduplicateAndRemainBounded() async {
        let repo = ActivityHistoryRepository()
        let model = ActivityLogViewModel(repository: repo, synchronizePending: { _ in nil })
        await model.loadIfNeeded(userID: "a")
        for n in 0..<170 { model.applyRecorded(item("\(n)", time: Date(timeIntervalSince1970: Double(n))), userID: "a") }
        #expect(model.items.count == 100)
        model.applyRecorded(item("50", time: Date(timeIntervalSince1970: 500)), userID: "a")
        #expect(model.items.first?.id == "50")
        #expect(model.items.count == 100)
        model.applyRecorded(item("wrong"), userID: "b")
        #expect(!model.items.contains { $0.id == "wrong" })
    }

    @Test func oldAccountLoadCannotPopulateNewAccount() async {
        let repo = ActivityHistoryRepository()
        var pending: CheckedContinuation<[ActivityLogItem], Error>?
        repo.fetch = { _ in try await withCheckedThrowingContinuation { pending = $0 } }
        let model = ActivityLogViewModel(repository: repo, synchronizePending: { _ in nil })
        let old = Task { await model.loadIfNeeded(userID: "a") }
        while pending == nil { await Task.yield() }
        repo.fetch = { _ in [] }
        await model.loadIfNeeded(userID: "b")
        pending?.resume(returning: [item("old")])
        await old.value
        #expect(model.items.isEmpty)
        #expect(!model.isLoading)
        #expect(repo.readUsers == ["a", "b"])
    }

    @Test func completedNewViewSurvivesOlderRefresh() async {
        let repo = ActivityHistoryRepository()
        let model = ActivityLogViewModel(repository: repo, synchronizePending: { _ in nil })
        await model.loadIfNeeded(userID: "a")
        var pending: CheckedContinuation<[ActivityLogItem], Error>?
        repo.fetch = { _ in try await withCheckedThrowingContinuation { pending = $0 } }
        let load = Task { await model.refresh() }
        while pending == nil { await Task.yield() }
        let newest = item("same")
        model.applyRecorded(newest, userID: "a")
        pending?.resume(returning: [item("same", time: .distantPast)])
        await load.value
        #expect(model.items == [newest])
    }

    @Test func refreshAndDeleteCannotOverlap() async {
        let repo = ActivityHistoryRepository()
        let model = ActivityLogViewModel(repository: repo, synchronizePending: { _ in nil })
        await model.loadIfNeeded(userID: "a")
        var pending: CheckedContinuation<[ActivityLogItem], Error>?
        repo.fetch = { _ in try await withCheckedThrowingContinuation { pending = $0 } }
        let load = Task { await model.refresh() }
        while pending == nil { await Task.yield() }
        #expect(await model.delete(item("one")) == false)
        #expect(await model.clearHistory() == false)
        #expect(repo.deletedUsers.isEmpty)
        pending?.resume(returning: [])
        await load.value
    }

    @Test func failedDeleteKeepsRowAndReportsNetworkError() async {
        let repo = ActivityHistoryRepository()
        let row = item("one")
        repo.fetch = { _ in [row] }
        repo.remove = { throw URLError(.notConnectedToInternet) }
        let model = ActivityLogViewModel(repository: repo, synchronizePending: { _ in nil })
        await model.loadIfNeeded(userID: "a")
        #expect(await model.delete(row) == false)
        #expect(model.items == [row])
        #expect(model.error == .network)
        #expect(!model.isMutating)
    }

    @Test func deletedRowCannotReturnFromLateRecording() async {
        let repo = ActivityHistoryRepository()
        let row = item("one", time: .distantPast)
        repo.fetch = { _ in [row] }
        let model = ActivityLogViewModel(repository: repo, synchronizePending: { _ in nil })
        await model.loadIfNeeded(userID: "a")
        #expect(await model.delete(row))
        model.applyRecorded(row, userID: "a")
        #expect(model.items.isEmpty)
        model.applyRecorded(item("new-action", time: .distantFuture), userID: "a")
        #expect(model.items.count == 1)
        #expect(repo.deletedUsers == ["a"])
    }

    @Test func clearPreservesNewViewsAndRejectsLateOldSignals() async {
        let repo = ActivityHistoryRepository()
        let model = ActivityLogViewModel(repository: repo, synchronizePending: { _ in nil })
        await model.loadIfNeeded(userID: "a")
        model.applyRecorded(item("old", time: .distantPast), userID: "a")
        var pending: CheckedContinuation<Void, Error>?
        repo.clear = { try await withCheckedThrowingContinuation { pending = $0 } }
        let clearing = Task { await model.clearHistory() }
        while pending == nil { await Task.yield() }
        await model.refresh()
        #expect(repo.readUsers.count == 1)
        let new = item("new", time: .distantFuture)
        model.applyRecorded(new, userID: "a")
        pending?.resume()
        #expect(await clearing.value)
        model.applyRecorded(item("old", time: .distantPast), userID: "a")
        #expect(model.items == [new])
        #expect(repo.clearedUsers == ["a"])
    }

    @Test func pendingActionsSurviveRestartAndClearIsAccountScoped() async throws {
        let suite = "ActivityHistoryTests-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PendingActivityLogStore(suiteName: suite)
        let row = item("retry-me", time: .distantPast)
        await store.enqueue(row, userID: "a")
        await store.enqueue(item("other"), userID: "b")
        let restored = PendingActivityLogStore(suiteName: suite)
        #expect(await restored.items(userID: "a") == [row])
        await restored.removeAll(userID: "a", through: Date())
        let cleared = PendingActivityLogStore(suiteName: suite)
        #expect(await cleared.items(userID: "a").isEmpty)
        #expect(await cleared.items(userID: "b").count == 1)
        await restored.enqueue(row, userID: "a")
        #expect(await restored.items(userID: "a").isEmpty)
    }

    @Test func serializedWritesAndClearKeepTheirOrder() async throws {
        let queue = ActivityLogWriteQueue()
        var sequence: [String] = []
        var pending: CheckedContinuation<Void, Never>?
        let write = Task {
            try await queue.run(userID: "queue") {
                sequence.append("write-start")
                await withCheckedContinuation { pending = $0 }
                sequence.append("write-end")
            }
        }
        while pending == nil { await Task.yield() }
        let clear = Task { try await queue.run(userID: "queue") { sequence.append("clear") } }
        await Task.yield()
        #expect(sequence == ["write-start"])
        pending?.resume()
        try await write.value
        try await clear.value
        #expect(sequence == ["write-start", "write-end", "clear"])
    }

    @Test func oldAccountDeleteCannotChangeNewHistory() async {
        let repo = ActivityHistoryRepository()
        let model = ActivityLogViewModel(repository: repo, synchronizePending: { _ in nil })
        await model.loadIfNeeded(userID: "a")
        var pending: CheckedContinuation<Void, Error>?
        repo.remove = { try await withCheckedThrowingContinuation { pending = $0 } }
        let removing = Task { await model.delete(item("same")) }
        while pending == nil { await Task.yield() }
        let current = item("same")
        repo.fetch = { _ in [current] }
        await model.loadIfNeeded(userID: "b")
        pending?.resume()
        #expect(await removing.value == false)
        #expect(model.items == [current])
        #expect(!model.isMutating)
    }
}

@MainActor
private final class ActivityHistoryRepository: ActivityLogRepository {
    var fetch: (String) async throws -> [ActivityLogItem] = { _ in [] }
    var remove: () async throws -> Void = {}
    var clear: () async throws -> Void = {}
    var readUsers: [String] = []
    var deletedUsers: [String] = []
    var clearedUsers: [String] = []
    func fetchActivityLog(userID: String, limit: Int) async throws -> [ActivityLogItem] {
        readUsers.append(userID)
        return try await fetch(userID)
    }
    func recordActivity(_ item: ActivityLogItem, userID: String) async throws {}
    func deleteActivity(id: String, userID: String) async throws {
        deletedUsers.append(userID)
        try await remove()
    }
    func clearActivityLog(userID: String, through: Date) async throws {
        clearedUsers.append(userID)
        try await clear()
    }
}
