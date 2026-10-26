import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct AnnouncementManagementTests {
    @Test func oldReceiptCannotAuthorizeFeedbackNavigationForAnotherAccount() async {
        let repository = ControlledAnnouncementRepository()
        let suite = "NotificationActionFence.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = AnnouncementCoordinator(repository: repository, defaults: defaults)
        coordinator.configure(userID: "first", available: true)
        coordinator.requestedFeedback = repository.item("previous-action")
        let receipt = Task { await coordinator.mark(repository.item("private"), event: "action") }
        while repository.receiptContinuation == nil { await Task.yield() }
        #expect(coordinator.isProcessing(repository.item("private")))
        #expect(await coordinator.mark(repository.item("private"), event: "action") == false)
        #expect(repository.receiptRequests == 1)
        coordinator.configure(userID: "second", available: true)
        repository.receiptContinuation?.resume(returning: AnnouncementResponse())
        #expect(await receipt.value == false)
        #expect(coordinator.requestedFeedback == nil); #expect(coordinator.error == nil)
    }
    @Test func identicalFeedRefreshWaitsForTheSameFreshSnapshotBeforeRouting() async {
        let repository = ControlledAnnouncementRepository(); repository.holdActive = true
        let coordinator = AnnouncementCoordinator(repository: repository)
        coordinator.configure(userID: "first", available: true)
        let first = Task { await coordinator.refresh() }
        while repository.activeContinuation == nil { await Task.yield() }
        var secondFinished = false
        let second = Task { await coordinator.refresh(); secondFinished = true }
        for _ in 0..<20 { await Task.yield() }
        #expect(!secondFinished); #expect(repository.feeds.count == 1)
        repository.activeContinuation?.resume(returning: AnnouncementResponse(items: [repository.item("fresh")]))
        await first.value; await second.value
        #expect(coordinator.items.map(\.id) == ["fresh"])
    }
    @Test func failedHistoryPageRetryKeepsTheReviewedHistoryAndCursor() async {
        let repository = ControlledAnnouncementRepository()
        let coordinator = AnnouncementCoordinator(repository: repository)
        coordinator.configure(userID: "first", available: true); await coordinator.refresh()
        let first = Task { await coordinator.loadHistory(reset: true) }; await repository.waitForHistory()
        repository.history?.resume(returning: AnnouncementResponse(items: [repository.item("older")], cursor: "next")); await first.value
        let more = Task { await coordinator.loadHistory() }; await repository.waitForHistory()
        repository.history?.resume(throwing: AppError.network); await more.value
        #expect(Set(coordinator.items.map(\.id)) == ["live", "older"])
        let retry = Task { await coordinator.retryHistory() }; await repository.waitForHistory()
        repository.history?.resume(returning: AnnouncementResponse(items: [repository.item("oldest")])); await retry.value
        #expect(repository.historyCursors == [nil, "next", "next"])
        #expect(Set(coordinator.items.map(\.id)) == ["live", "older", "oldest"])
    }
    @Test func deliveryDoesNotReopenAcknowledgedMessageButExplicitTapDoes() {
        var intent = AnnouncementPushIntent()
        intent.receive(id: "message", userID: "first", userInitiated: false)
        #expect(intent.consume(userID: "first") == nil)
        intent.receive(id: "message", userID: "first", userInitiated: true)
        #expect(intent.consume(userID: "first") == "message")
        #expect(intent.consume(userID: "first") == nil)
    }
    @Test func pendingTapWaitsForProfileButNeverCrossesAccountsOrSignOut() {
        var intent = AnnouncementPushIntent()
        intent.receive(id: "message", userID: "first", userInitiated: true)
        intent.configure(userID: nil)
        #expect(intent.consume(userID: "second") == nil)
        intent.configure(userID: "first")
        #expect(intent.consume(userID: "first") == "message")
        intent.receive(id: "message", userID: "first", userInitiated: true)
        intent.configure(userID: "second")
        #expect(intent.id == nil)
        intent.receive(id: "message", userID: "second", userInitiated: true)
        intent.clear()
        #expect(intent.consume(userID: "second") == nil)
        intent.receive(id: "message", userID: nil, userInitiated: true)
        #expect(intent.id == nil)
    }
    @Test func saveRetryIdentityTracksTheReviewedPayloadAndRevision() {
        var attempts = AnnouncementSaveAttempts(), value = UserAnnouncement()
        value.title = .init(uk: "Текст", de: "Text")
        let first = attempts.operationID(for: value)
        #expect(attempts.operationID(for: value) == first)
        var changed = value; changed.body.uk = "Інший зміст"
        #expect(attempts.operationID(for: changed) != first)
        let changedID = attempts.operationID(for: changed)
        changed.revision += 1
        #expect(attempts.operationID(for: changed) != changedID)
    }

    @Test func reviewSnapshotIgnoresDeliveryMetadataButDetectsEveryBusinessChange() {
        var value = UserAnnouncement()
        value.title = .init(uk: "Текст", de: "Text")
        var stored = value; stored.revision = 2; stored.status = "published"; stored.presentedAt = 1
        #expect(stored.reviewedContent == value.reviewedContent)
        stored.body.de = "Updated text"
        #expect(stored.reviewedContent != value.reviewedContent)
        stored = value; stored.userIds = ["different-person"]
        #expect(stored.reviewedContent != value.reviewedContent)
        stored = value; stored.startsAt += 60_000
        #expect(stored.reviewedContent != value.reviewedContent)
    }

    @Test func failedRecipientPageRetryKeepsTheLoadedPeopleAndExactCursor() async {
        let repo = RetryingRecipientRepository()
        let model = AnnouncementRecipientSearch(repository: repo)
        await model.search(""); await model.more()
        #expect(model.failedMore); #expect(model.items.map(\.id) == ["first"])
        await model.retry()
        #expect(model.items.map(\.id) == ["first", "second"])
        #expect(repo.cursors == ["first-page", "next", "next"])
        #expect(model.error == nil)
    }

    @Test func staleHistoryCannotUndoTheNewerActiveFeedCancellation() async {
        let repo = ControlledAnnouncementRepository()
        let defaults = UserDefaults(suiteName: "AnnouncementHistoryRace.\(UUID().uuidString)")!
        let model = AnnouncementCoordinator(repository: repo, defaults: defaults)
        model.configure(userID: "user", available: true); await model.refresh()
        let task = Task { await model.loadHistory(reset: true) }
        await repo.waitForHistory()
        repo.activeOverride = []
        var cancelled = repo.item("live"); cancelled.status = "cancelled"; cancelled.presentedAt = 1
        repo.nextHistoryResponse = AnnouncementResponse(items: [cancelled])
        await model.refresh()
        repo.history?.resume(returning: AnnouncementResponse(items: [repo.item("live")]))
        await task.value
        #expect(model.items.first(where: { $0.id == "live" })?.status == "cancelled")
        #expect(repo.historyRequests == 2)
    }
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
    var holdActive = false
    var activeContinuation: CheckedContinuation<AnnouncementResponse, Error>?
    var historyCursors: [String?] = []
    var receiptContinuation: CheckedContinuation<AnnouncementResponse, Error>?
    var receiptRequests = 0
    var activeOverride: [UserAnnouncement]?
    var nextHistoryResponse: AnnouncementResponse?
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
        if endpoint == "acknowledgeAnnouncement" { receiptRequests += 1; return try await withCheckedThrowingContinuation { receiptContinuation = $0 } }
        if request.feedMode == "active" {
            feeds.append("active")
            if holdActive { return try await withCheckedThrowingContinuation { activeContinuation = $0 } }
            return AnnouncementResponse(items: activeOverride ?? [item("live")])
        }
        historyCursors.append(request.cursor)
        if let nextHistoryResponse { historyRequests += 1; return nextHistoryResponse }
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

@MainActor private final class RetryingRecipientRepository: AnnouncementRepository {
    var cursors: [String] = []
    var failed = false
    func call(_ endpoint: String, _ request: AnnouncementRequest) async throws -> AnnouncementResponse { .init() }
    func users(cursor: String?) async throws -> (items: [AnnouncementUser], cursor: String?) {
        cursors.append(cursor ?? "first-page")
        if cursor == nil { return ([.init(id: "first", name: "First", region: nil)], "next") }
        if !failed { failed = true; throw AppError.network }
        return ([.init(id: "second", name: "Second", region: nil)], nil)
    }
}
