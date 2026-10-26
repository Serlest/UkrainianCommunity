import Foundation
import Testing
@testable import UkrainianCommunity

@Suite(.serialized) @MainActor
struct FeedbackAuditStateTests {
    @Test func simultaneousInboxOpenSharesOneRequest() async {
        let repo = FeedbackStateProbe(); repo.blockInbox = true
        let model = FeedbackInboxViewModel(repository: repo)
        let first = Task { await model.loadIfNeeded(actorID: "owner") }
        await settle()
        let second = Task { await model.loadIfNeeded(actorID: "owner") }
        await settle()
        let count = repo.inboxCalls
        repo.resumeInbox()
        await first.value; await second.value
        #expect(count == 1)
        #expect(!model.isLoading)
    }

    @Test func replyRetryAfterReadbackFailureKeepsCommittedOperationID() async {
        let repo = FeedbackStateProbe()
        let model = FeedbackInboxViewModel(repository: repo)
        await model.loadIfNeeded(actorID: AppUser.placeholder.id)
        repo.failNextDetail = true
        let item = feedbackProbeItem("request")
        #expect(await model.sendReply("Verified response", to: item, owner: .placeholder) == false)
        #expect(await model.sendReply("Verified response", to: item, owner: .placeholder))
        #expect(repo.operations.count == 2)
        #expect(Set(repo.operations.map(\.id)).count == 1)
    }

    @Test func oldPersonalListenerCannotPublishAfterLeavingAndReturningToSameAccount() async {
        let repo = FeedbackStateProbe()
        let model = MyFeedbackViewModel(repository: repo)
        await model.loadIfNeeded(userID: "A")
        let callback = repo.personalCallbacks[0]
        await model.loadIfNeeded(userID: "B")
        repo.personalRows = [feedbackProbeItem("current", userID: "A")]
        await model.loadIfNeeded(userID: "A")
        callback([feedbackProbeItem("stale", userID: "A")])
        #expect(model.items.map(\.id) == ["current"])
    }

    @Test func simultaneousPersonalOpenSharesOneRequest() async {
        let repo = FeedbackStateProbe(); repo.blockPersonal = true
        let model = MyFeedbackViewModel(repository: repo)
        let first = Task { await model.loadIfNeeded(userID: "A") }
        await settle()
        let second = Task { await model.loadIfNeeded(userID: "A") }
        await settle()
        let count = repo.personalCalls
        repo.resumePersonal()
        await first.value; await second.value
        #expect(count == 1)
    }

    @Test func oldNextPageCannotAppendAfterFirstPageRefresh() async {
        let repo = FeedbackStateProbe()
        let model = MyFeedbackViewModel(repository: repo)
        repo.personalRows = [feedbackProbeItem("before", userID: "A")]
        repo.moreAvailable = true
        await model.loadIfNeeded(userID: "A")
        repo.blockNextPage = true
        let more = Task { await model.loadMore(userID: "A") }
        await settle()
        repo.personalRows = [feedbackProbeItem("after", userID: "A")]
        repo.moreAvailable = false
        await model.refresh(userID: "A")
        repo.resumePersonal()
        await more.value
        #expect(model.items.map(\.id) == ["after"])
        #expect(!model.hasMore)
        #expect(!model.isLoadingMore)
    }

    @Test func oldPersonalReadCannotPublishAfterAccountABA() async {
        let repo = FeedbackStateProbe(); repo.blockPersonal = true
        let model = MyFeedbackViewModel(repository: repo)
        let old = Task { await model.loadIfNeeded(userID: "A") }
        await settle()
        repo.blockPersonal = false
        await model.loadIfNeeded(userID: "B")
        repo.personalRows = [feedbackProbeItem("current", userID: "A")]
        await model.loadIfNeeded(userID: "A")
        repo.resumePersonal()
        await old.value
        #expect(model.items.map(\.id) == ["current"])
    }

    @Test func detailErrorMustBeRetriedBeforeActionsBecomeAvailable() async {
        let repo = FeedbackStateProbe()
        let model = FeedbackInboxViewModel(repository: repo)
        await model.loadIfNeeded(actorID: "owner")
        repo.failNextDetail = true
        #expect(await model.prepareDetail(id: "request", actorID: "owner") == nil)
        #expect(model.detailStates["request"]?.isReady == false)
        #expect(await model.prepareDetail(id: "request", actorID: "owner") != nil)
        #expect(model.detailStates["request"]?.isReady == true)
    }

    @Test func personalDetailRejectsAnotherSubmitterEvenIfAdapterReturnsIt() async {
        let repo = FeedbackStateProbe()
        let model = MyFeedbackViewModel(repository: repo)
        await model.loadIfNeeded(userID: "A")
        #expect(await model.prepareDetail(id: "request", userID: "A") == nil)
        #expect(model.detailStates["request"]?.isReady == false)
    }

    private func settle() async { for _ in 0..<60 { await Task.yield() } }
}

@MainActor private final class FeedbackStateProbe: FeedbackRepository, FeedbackRealtimeRepository {
    var inboxCalls = 0
    var personalCalls = 0
    var blockInbox = false
    var blockPersonal = false
    var blockNextPage = false
    var moreAvailable = false
    var personalRows = [feedbackProbeItem("request", userID: "A")]
    var operations: [FeedbackOperationAttempt] = []
    var failNextDetail = false
    var personalCallbacks: [@MainActor ([FeedbackItem]) -> Void] = []
    private var inboxWaiters: [CheckedContinuation<FeedbackInboxPage, Never>] = []
    private var personalWaiters: [(FeedbackPage, CheckedContinuation<FeedbackPage, Never>)] = []

    func fetchOwnerInbox(query: FeedbackInboxQuery, after: FeedbackInboxCursor?) async throws -> FeedbackInboxPage {
        inboxCalls += 1
        if blockInbox { return await withCheckedContinuation { inboxWaiters.append($0) } }
        return .init(items: [feedbackProbeItem("request")], counts: ["open": 1], cursor: nil)
    }
    func resumeInbox() {
        let waits = inboxWaiters; inboxWaiters = []
        waits.forEach { $0.resume(returning: .init(items: [feedbackProbeItem("request")], counts: ["open": 1], cursor: nil)) }
    }
    func fetchFeedbackPage(userID: String?, after cursor: FeedbackPageCursor?, limit: Int) async throws -> FeedbackPage {
        personalCalls += 1
        let rows = cursor == nil ? personalRows : [feedbackProbeItem("old-page", userID: userID ?? "A")]
        let page = FeedbackPage(items: rows, nextCursor: rows.last.map { .init(createdAt: $0.createdAt, id: $0.id) }, hasMore: moreAvailable)
        if blockPersonal || (blockNextPage && cursor != nil) {
            return await withCheckedContinuation { personalWaiters.append((page, $0)) }
        }
        return page
    }
    func resumePersonal() { let waits = personalWaiters; personalWaiters = []; waits.forEach { $0.1.resume(returning: $0.0) } }
    func fetchFeedback() async throws -> [FeedbackItem] { personalRows }
    func fetchFeedback(id: String) async throws -> FeedbackItem {
        if failNextDetail { failNextDetail = false; throw AppError.network }
        return feedbackProbeItem(id)
    }
    func fetchFeedbackMessages(feedback: FeedbackItem) async throws -> [FeedbackMessage] { [] }
    func submitFeedback(_ feedback: FeedbackItem) async throws {}
    func updateFeedbackStatus(id: String, status: FeedbackStatus) async throws {}
    func performFeedbackOperation(_ operation: FeedbackOperationAttempt) async throws { operations.append(operation) }
    func listenMyFeedback(userID: String, onChange: @escaping @MainActor ([FeedbackItem]) -> Void, onError: @escaping @MainActor (AppError) -> Void) -> AppRealtimeListener { personalCallbacks.append(onChange); return FeedbackProbeListener() }
    func listenOwnerFeedbackInbox(onChange: @escaping @MainActor ([FeedbackItem]) -> Void, onError: @escaping @MainActor (AppError) -> Void) -> AppRealtimeListener { FeedbackProbeListener() }
    func listenFeedbackMessages(feedback: FeedbackItem, onChange: @escaping @MainActor ([FeedbackMessage]) -> Void, onError: @escaping @MainActor (AppError) -> Void) -> AppRealtimeListener { FeedbackProbeListener() }
}
private final class FeedbackProbeListener: AppRealtimeListener { func cancel() {} }
@MainActor private func feedbackProbeItem(_ id: String, userID: String = "user") -> FeedbackItem {
    .init(id: id, type: .question, subject: "Directory question", message: "Initial request", status: .open,
          createdAt: Date(timeIntervalSince1970: 1000), updatedAt: Date(timeIntervalSince1970: 1000), userId: userID,
          userDisplayName: "Test user", ownerReply: nil, repliedAt: nil, repliedByUserId: nil, lastMessageText: nil,
          lastMessageAt: nil, lastMessageByUserId: nil, lastMessageByRole: nil, unreadForOwner: false, unreadForUser: false)
}
