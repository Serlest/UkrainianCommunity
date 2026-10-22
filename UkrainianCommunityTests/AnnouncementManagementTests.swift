import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct AnnouncementManagementTests {
    @Test func lateRecipientSearchCannotReplaceCurrentResults() async {
        let repository = ControlledAnnouncementRepository()
        let search = AnnouncementRecipientSearch(repository: repository)
        let first = Task { await search.search("old") }
        await repository.waitForSearch("old")
        let second = Task { await search.search("new") }
        await repository.waitForSearch("new")
        repository.resolve("new", name: "New person"); await second.value
        repository.resolve("old", name: "Old person"); await first.value
        #expect(search.items.map(\.name) == ["New person"])
        #expect(!search.loading)
    }
    @Test func recipientSearchContinuesAfterEmptyCandidatePage() async {
        let repository = PagedAnnouncementRepository()
        let search = AnnouncementRecipientSearch(repository: repository)
        await search.search("needle qzz")
        #expect(repository.requestedCursors == ["first", "next"])
        #expect(search.items.map(\.name) == ["Matching person"])
        #expect(search.cursor == nil)
        #expect(search.error == nil)
    }
    @Test func backgroundRefreshDoesNotReloadAllHistoryAndAccountSwitchDiscardsPendingPage() async {
        let repository = ControlledAnnouncementRepository()
        let defaults = UserDefaults(suiteName: "AnnouncementManagementTests.\(UUID().uuidString)")!
        let coordinator = AnnouncementCoordinator(repository: repository, defaults: defaults)
        coordinator.configure(userID: "first", available: true)
        await coordinator.refresh()
        #expect(repository.feeds == ["active"])
        #expect(coordinator.items.count == 1)
        let history = Task { await coordinator.loadHistory(reset: true) }
        await repository.waitForHistory()
        coordinator.configure(userID: "second", available: true)
        repository.history?.resume(returning: AnnouncementResponse(items: [repository.item("private-old")], cursor: "next"))
        await history.value
        #expect(coordinator.items.isEmpty)
        #expect(coordinator.historyCursor == nil)
        #expect(!coordinator.isHistoryLoading)
    }
    @Test func historyPagesKeepActiveAnnouncementsAndDoNotProduceDuplicates() async {
        let repository = ControlledAnnouncementRepository()
        let defaults = UserDefaults(suiteName: "AnnouncementManagementTests.\(UUID().uuidString)")!
        let coordinator = AnnouncementCoordinator(repository: repository, defaults: defaults)
        coordinator.configure(userID: "user", available: true); await coordinator.refresh()
        let page = Task { await coordinator.loadHistory(reset: true) }; await repository.waitForHistory()
        repository.history?.resume(returning: AnnouncementResponse(items: [repository.item("live"), repository.item("older")], cursor: "next")); await page.value
        let more = Task { await coordinator.loadHistory() }; await repository.waitForHistory()
        repository.history?.resume(returning: AnnouncementResponse(items: [repository.item("older"), repository.item("oldest")])); await more.value
        #expect(Set(coordinator.items.map(\.id)) == ["live", "older", "oldest"])
        #expect(coordinator.items.count == 3)
        #expect(coordinator.historyCursor == nil)
    }
}

@MainActor
private final class ControlledAnnouncementRepository: AnnouncementRepository {
    typealias Page = (items: [AnnouncementUser], cursor: String?)
    var pending: [String: CheckedContinuation<Page, Error>] = [:]
    var waiters: [String: CheckedContinuation<Void, Never>] = [:]
    var feeds: [String] = []
    var history: CheckedContinuation<AnnouncementResponse, Error>?
    var historyRequests = 0
    var historyObserved = 0
    var historyWaiter: CheckedContinuation<Void, Never>?
    func item(_ id: String) -> UserAnnouncement { var value = UserAnnouncement(); value.id = id; value.status = "published"; value.startsAt -= 1000; return value }
    func call(_ endpoint: String, _ request: AnnouncementRequest) async throws -> AnnouncementResponse {
        if request.feedMode == "active" { feeds.append("active"); return AnnouncementResponse(items: [item("live")]) }
        return try await withCheckedThrowingContinuation { continuation in
            historyRequests += 1; history = continuation; historyWaiter?.resume(); historyWaiter = nil
        }
    }
    func users(cursor: String?) async throws -> Page { ([], nil) }
    func users(query: String, cursor: String?) async throws -> Page {
        try await withCheckedThrowingContinuation { continuation in
            pending[query] = continuation; waiters.removeValue(forKey: query)?.resume()
        }
    }
    func waitForSearch(_ query: String) async {
        if pending[query] != nil { return }
        await withCheckedContinuation { waiters[query] = $0 }
    }
    func resolve(_ query: String, name: String) { pending.removeValue(forKey: query)?.resume(returning: ([AnnouncementUser(id: query, name: name, region: nil)], nil)) }
    func waitForHistory() async {
        if historyRequests > historyObserved { historyObserved = historyRequests; return }
        await withCheckedContinuation { historyWaiter = $0 }
        historyObserved = historyRequests
    }
}

@MainActor
private final class PagedAnnouncementRepository: AnnouncementRepository {
    var requestedCursors: [String] = []
    func call(_ endpoint: String, _ request: AnnouncementRequest) async throws -> AnnouncementResponse { AnnouncementResponse() }
    func users(cursor: String?) async throws -> (items: [AnnouncementUser], cursor: String?) { try await users(query: "", cursor: cursor) }
    func users(query: String, cursor: String?) async throws -> (items: [AnnouncementUser], cursor: String?) {
        requestedCursors.append(cursor ?? "first")
        return cursor == nil ? ([], "next") : ([AnnouncementUser(id: "found", name: "Matching person", region: nil)], nil)
    }
}
