import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct RecentViewsTests {
    private func item(_ id: String, time: Date = Date()) -> RecentViewItem {
        RecentViewItem(itemId: id, itemType: .news, title: id, subtitle: nil, imageURL: nil, viewedAt: time)
    }

    @Test func newViewsDeduplicateAndRemainBounded() async {
        let repo = RecentHistoryRepository()
        let model = RecentViewsViewModel(repository: repo)
        await model.loadIfNeeded(userID: "a")
        for n in 0..<70 { model.applyRecordedView(item("\(n)", time: Date(timeIntervalSince1970: Double(n))), userID: "a") }
        #expect(model.items.count == 30)
        model.applyRecordedView(item("50", time: Date(timeIntervalSince1970: 100)), userID: "a")
        #expect(model.items.first?.itemId == "50")
        #expect(model.items.count == 30)
        model.applyRecordedView(item("wrong"), userID: "b")
        #expect(!model.items.contains { $0.itemId == "wrong" })
    }

    @Test func oldAccountLoadCannotPopulateNewAccount() async {
        let repo = RecentHistoryRepository()
        var pending: CheckedContinuation<[RecentViewItem], Error>?
        repo.fetch = { _ in try await withCheckedThrowingContinuation { pending = $0 } }
        let model = RecentViewsViewModel(repository: repo)
        let old = Task { await model.refresh(userID: "a") }
        while pending == nil { await Task.yield() }
        repo.fetch = { _ in [] }
        await model.refresh(userID: "b")
        pending?.resume(returning: [item("old")])
        await old.value
        #expect(model.items.isEmpty)
        #expect(!model.isLoading)
        #expect(repo.readUsers == ["a", "b"])
    }

    @Test func completedNewViewSurvivesOlderRefresh() async {
        let repo = RecentHistoryRepository()
        let model = RecentViewsViewModel(repository: repo)
        await model.loadIfNeeded(userID: "a")
        var pending: CheckedContinuation<[RecentViewItem], Error>?
        repo.fetch = { _ in try await withCheckedThrowingContinuation { pending = $0 } }
        let load = Task { await model.refresh() }
        while pending == nil { await Task.yield() }
        let newest = item("same")
        model.applyRecordedView(newest, userID: "a")
        pending?.resume(returning: [item("same", time: .distantPast)])
        await load.value
        #expect(model.items == [newest])
    }

    @Test func refreshAndDeleteCannotOverlap() async {
        let repo = RecentHistoryRepository()
        let model = RecentViewsViewModel(repository: repo)
        await model.loadIfNeeded(userID: "a")
        var pending: CheckedContinuation<[RecentViewItem], Error>?
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
        let repo = RecentHistoryRepository()
        let row = item("one")
        repo.fetch = { _ in [row] }
        repo.remove = { throw URLError(.notConnectedToInternet) }
        let model = RecentViewsViewModel(repository: repo)
        await model.loadIfNeeded(userID: "a")
        #expect(await model.delete(row) == false)
        #expect(model.items == [row])
        #expect(model.error == .network)
        #expect(!model.isMutating)
    }

    @Test func deletedRowCannotReturnFromLateRecording() async {
        let repo = RecentHistoryRepository()
        let row = item("one", time: .distantPast)
        repo.fetch = { _ in [row] }
        let model = RecentViewsViewModel(repository: repo)
        await model.loadIfNeeded(userID: "a")
        #expect(await model.delete(row))
        model.applyRecordedView(row, userID: "a")
        #expect(model.items.isEmpty)
        model.applyRecordedView(item("one", time: .distantFuture), userID: "a")
        #expect(model.items.count == 1)
        #expect(repo.deletedUsers == ["a"])
    }

    @Test func clearPreservesNewViewsAndRejectsLateOldSignals() async {
        let repo = RecentHistoryRepository()
        let model = RecentViewsViewModel(repository: repo)
        await model.loadIfNeeded(userID: "a")
        model.applyRecordedView(item("old", time: .distantPast), userID: "a")
        var pending: CheckedContinuation<Void, Error>?
        repo.clear = { try await withCheckedThrowingContinuation { pending = $0 } }
        let clearing = Task { await model.clearHistory() }
        while pending == nil { await Task.yield() }
        await model.refresh()
        #expect(repo.readUsers.count == 1)
        let new = item("new", time: .distantFuture)
        model.applyRecordedView(new, userID: "a")
        pending?.resume()
        #expect(await clearing.value)
        model.applyRecordedView(item("old", time: .distantPast), userID: "a")
        #expect(model.items == [new])
        #expect(repo.clearedUsers == ["a"])
    }

    @Test func oldAccountDeleteCannotChangeNewHistory() async {
        let repo = RecentHistoryRepository()
        let model = RecentViewsViewModel(repository: repo)
        await model.loadIfNeeded(userID: "a")
        var pending: CheckedContinuation<Void, Error>?
        repo.remove = { try await withCheckedThrowingContinuation { pending = $0 } }
        let removing = Task { await model.delete(item("same")) }
        while pending == nil { await Task.yield() }
        let current = item("same")
        repo.fetch = { _ in [current] }
        await model.refresh(userID: "b")
        pending?.resume()
        #expect(await removing.value == false)
        #expect(model.items == [current])
        #expect(!model.isMutating)
    }
}

@MainActor
private final class RecentHistoryRepository: RecentViewsRepository {
    var fetch: (String) async throws -> [RecentViewItem] = { _ in [] }
    var remove: () async throws -> Void = {}
    var clear: () async throws -> Void = {}
    var readUsers: [String] = []
    var deletedUsers: [String] = []
    var clearedUsers: [String] = []
    func fetchRecentViews(userID: String, limit: Int) async throws -> [RecentViewItem] {
        readUsers.append(userID)
        return try await fetch(userID)
    }
    func recordRecentView(_ item: RecentViewItem, userID: String) async throws {}
    func deleteRecentView(id: String, userID: String, through: Date) async throws {
        deletedUsers.append(userID)
        try await remove()
    }
    func clearRecentViews(userID: String, through: Date) async throws {
        clearedUsers.append(userID)
        try await clear()
    }
}
