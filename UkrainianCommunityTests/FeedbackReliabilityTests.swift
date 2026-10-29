import Foundation
import FirebaseFirestore
import Testing
@testable import UkrainianCommunity

@Suite(.serialized) @MainActor
struct FeedbackReliabilityTests {
    @Test func confirmedEmptyInboxDoesNotReloadOnRepeatedAppearanceButRefreshStillReads() async {
        let repo = FeedbackAuditRepository(items: [])
        let model = FeedbackInboxViewModel(repository: repo)
        await model.configure(actorID: "owner", filter: "all", search: "", oldest: false)
        let first = repo.fetchCalls
        await model.configure(actorID: "owner", filter: "all", search: "", oldest: false)
        await model.loadIfNeeded(actorID: "owner")
        #expect(first > 0); #expect(repo.fetchCalls == first)
        await model.refresh(actorID: "owner")
        #expect(repo.fetchCalls == first + 1)
        await model.loadIfNeeded(actorID: "different-owner")
        #expect(repo.fetchCalls == first + 2)
    }
    private func item(_ id: String = "case", status: FeedbackStatus = .open, context: Bool = false) -> FeedbackItem {
        let time = Timestamp(seconds: 1792670000, nanoseconds: 123456000).dateValue()
        return FeedbackItem(id: id, type: .report, subject: "Subject", message: "Request", status: status,
            createdAt: time, updatedAt: time, userId: "user", userDisplayName: "Olena", ownerReply: "Reply", repliedAt: time,
            repliedByUserId: "owner", lastMessageText: "Reply", lastMessageAt: time, lastMessageByUserId: "owner", lastMessageByRole: .owner,
            unreadForOwner: false, unreadForUser: true,
            reportContext: context ? .init(targetType: .news, targetId: "news", parentType: nil, parentId: nil, targetAuthorId: "author",
                targetTitle: "Reported news", targetExcerpt: "Full excerpt", reason: .spam, isUrgent: false, slaDueAt: time) : nil,
            occurrenceCount: 4, revision: "1792670000:123456000")
    }
    @Test func legacyReplyIsReplacedByStoredMessageButLegitimateRepeatedRepliesSurvive() {
        let feedback = item()
        let reply = FeedbackMessage(id: "stored", feedbackId: feedback.id, senderId: "owner", senderDisplayName: "Support", senderRole: .owner,
            text: "Reply", createdAt: feedback.updatedAt, isSystem: false)
        let repeated = FeedbackMessage(id: "later", feedbackId: feedback.id, senderId: "owner", senderDisplayName: "Support", senderRole: .owner,
            text: "Reply", createdAt: feedback.updatedAt.addingTimeInterval(10), isSystem: false)
        let result = FeedbackMessageHistory.merge(feedback.legacyMessages, [reply, repeated])
        #expect(result.count == 3); #expect(result.filter { $0.text == "Reply" }.count == 2)
        #expect(!result.contains { $0.id.hasSuffix("_legacy_owner_reply") })
    }
    @Test func inboxAndUserHistoryBothEliminateSyntheticReply() async {
        let repo = FeedbackAuditRepository(items: [item()])
        let model = FeedbackInboxViewModel(repository: repo)
        await model.loadIfNeeded(actorID: "owner"); await model.loadMessages(for: repo.records[0])
        #expect(model.messages(for: repo.records[0]).filter { $0.text == "Reply" }.count == 1)
        let mine = MyFeedbackViewModel(repository: repo)
        await mine.loadIfNeeded(userID: "user"); await mine.loadMessages(for: repo.records[0])
        #expect(mine.messages(for: repo.records[0]).filter { $0.text == "Reply" }.count == 1)
    }
    @Test func decisionsCarryOriginalNanosecondsAndReuseOperationAfterLostResponse() async {
        let sample = item(); let repo = FeedbackAuditRepository(items: [sample]); repo.failDecision = true
        let model = FeedbackInboxViewModel(repository: repo); await model.loadIfNeeded(actorID: "owner")
        let request = DsaDecisionFunctionRequest(reportId: sample.id, outcome: "noAction", factsAndCircumstances: "Human verified facts and circumstances",
            legalBasis: "Terms", termsBasis: nil, territorialScope: "Austria", duration: "Permanent", redressInformation: "Appeal", humanReviewConfirmed: true)
        #expect(await model.decideDsaCase(request, item: sample) == false)
        repo.failDecision = false; #expect(await model.decideDsaCase(request, item: sample))
        #expect(repo.decisions.count == 2); #expect(repo.decisions[0].operationId == repo.decisions[1].operationId)
        #expect(repo.decisions[0].expectedRevision == "1792670000:123456000"); #expect(repo.decisions[0].revisionFormat == "exact")
        #expect(repo.decisions[0].principalId == "owner")
    }
    @Test func globalFilterAndCountsCoverMoreThan100AndSubjectSearch() async {
        let repo = FeedbackAuditRepository(items: (0..<137).map { item("row-\($0)", status: $0 < 110 ? .closed : .open) })
        let model = FeedbackInboxViewModel(repository: repo); await model.loadIfNeeded(actorID: "owner")
        #expect(model.items.count == 27); #expect(model.counts["closed"] == 110)
        await model.configure(actorID: "owner", filter: "closed", search: "Subject", oldest: false)
        #expect(model.items.count == 30); #expect(model.counts["closed"] == 110)
        while model.hasMore { await model.loadMore(actorID: "owner") }
        #expect(model.items.count == 110); #expect(Set(model.items.map(\.id)).count == 110)
    }
    @Test func statusRefreshPreservesComplaintContextAndFailureIsVisible() async {
        let repo = FeedbackAuditRepository(items: [item(context: true)])
        let model = FeedbackInboxViewModel(repository: repo); await model.loadIfNeeded(actorID: "owner")
        await model.setStatus(.inProgress, for: repo.records[0])
        #expect(model.items.first?.reportContext?.targetId == "news"); #expect(model.items.first?.occurrenceCount == 4)
        repo.failDelete = true; #expect(await model.delete(repo.records[0]) == false); #expect(model.actionError == .network)
    }
    @Test func delayedOldQueryCannotReplaceNewFilterOrCursor() async {
        let repo = FeedbackAuditRepository(items: [item("old")]); repo.fetchDelay = .milliseconds(100)
        let model = FeedbackInboxViewModel(repository: repo)
        let pending = Task { await model.loadIfNeeded(actorID: "owner") }
        await Task.yield(); repo.fetchDelay = .zero; repo.records = [item("new", status: .closed)]
        await model.configure(actorID: "owner", filter: "closed", search: "", oldest: false)
        await pending.value
        #expect(model.items.map(\.id) == ["new"]); #expect(!model.hasMore); #expect(!model.isLoading)
    }
    @Test func initialRealtimeSnapshotDoesNotReloadConfirmedInbox() async throws {
        let repo = FeedbackAuditRepository(items: [item()])
        let model = FeedbackInboxViewModel(repository: repo)
        await model.loadIfNeeded(actorID: "owner")
        let callback = try #require(repo.inboxCallbacks.first)
        let before = repo.fetchCalls
        callback(repo.records)
        try await Task.sleep(for: .milliseconds(350))
        #expect(repo.fetchCalls == before)
    }

    @Test func realtimeUpdateRetainsLoadedInboxRange() async throws {
        let repo = FeedbackAuditRepository(items: (0..<137).map { item("request-\($0)") })
        let model = FeedbackInboxViewModel(repository: repo)
        await model.loadIfNeeded(actorID: "owner")
        await model.loadMore(actorID: "owner")
        #expect(model.items.count == 60)
        let callback = try #require(repo.inboxCallbacks.first)
        callback(repo.records)
        callback(Array(repo.records.dropFirst()))
        try await Task.sleep(for: .milliseconds(350))
        #expect(model.items.count == 60)
    }

    @Test func callbackQueuedBeforeAccountSwitchCannotLeakIntoNextAccount() async throws {
        let repo = FeedbackAuditRepository(items: [item("first")])
        let model = FeedbackInboxViewModel(repository: repo); await model.loadIfNeeded(actorID: "owner-A")
        let oldCallback = try #require(repo.inboxCallbacks.first)
        repo.records = [item("second")]; await model.loadIfNeeded(actorID: "owner-B")
        oldCallback([item("first")]); try await Task.sleep(for: .milliseconds(300))
        #expect(model.items.map(\.id) == ["second"]); #expect(model.detailItems["first"] == nil)
    }

    @Test func indexOnlyRealtimeChangeRefreshesQueryAndRemoteDeletionRemovesRow() async throws {
        let sample = item(); let repo = FeedbackAuditRepository(items: [sample])
        let model = FeedbackInboxViewModel(repository: repo); await model.loadIfNeeded(actorID: "owner")
        let callback = try #require(repo.recordCallbacks.first)
        callback([sample]) // Initial matching snapshot must not reset loaded pagination.
        #expect(model.items.count == 1)
        repo.records = []
        callback([sample]) // Index-only update: source revision and DTO stay identical.
        try await Task.sleep(for: .milliseconds(350))
        #expect(model.items.isEmpty); #expect(model.counts["open"] == nil)
        repo.records = [sample]; await model.refresh(actorID: "owner")
        let deletion = try #require(repo.recordCallbacks.last)
        repo.records = []; deletion([])
        #expect(model.items.isEmpty)
    }

}

@MainActor private final class FeedbackAuditRepository: FeedbackRepository, FeedbackRealtimeRepository, FeedbackRecordsRealtimeRepository {
    var records: [FeedbackItem]; var decisions: [DsaDecisionFunctionRequest] = []; var failDecision = false; var failDelete = false
    init(items: [FeedbackItem]) { records = items }
    func submitFeedback(_ feedback: FeedbackItem) async throws { records.append(feedback) }
    var fetchDelay: Duration = .zero
    var fetchCalls = 0
    var recordCallbacks: [@MainActor ([FeedbackItem]) -> Void] = []
    var inboxCallbacks: [@MainActor ([FeedbackItem]) -> Void] = []
    func fetchFeedback() async throws -> [FeedbackItem] {
        fetchCalls += 1
        let saved = records, delay = fetchDelay
        if delay != .zero { try await Task.sleep(for: delay) }
        return saved
    }
    func listenFeedbackRecords(ids: [String], onChange: @escaping @MainActor ([FeedbackItem]) -> Void, onError: @escaping @MainActor (AppError) -> Void) -> AppRealtimeListener {
        recordCallbacks.append(onChange); return FeedbackAuditListener()
    }
    func listenOwnerFeedbackInbox(onChange: @escaping @MainActor ([FeedbackItem]) -> Void, onError: @escaping @MainActor (AppError) -> Void) -> AppRealtimeListener {
        inboxCallbacks.append(onChange); return FeedbackAuditListener()
    }
    func listenMyFeedback(userID: String, onChange: @escaping @MainActor ([FeedbackItem]) -> Void, onError: @escaping @MainActor (AppError) -> Void) -> AppRealtimeListener { FeedbackAuditListener() }
    func listenFeedbackMessages(feedback: FeedbackItem, onChange: @escaping @MainActor ([FeedbackMessage]) -> Void, onError: @escaping @MainActor (AppError) -> Void) -> AppRealtimeListener { FeedbackAuditListener() }
    func updateFeedbackStatus(id: String, status: FeedbackStatus) async throws {
        // The source record preserves context; the model must use the authoritative read-back.
    }
    func fetchFeedbackMessages(feedback: FeedbackItem) async throws -> [FeedbackMessage] {
        [.init(id: "stored", feedbackId: feedback.id, senderId: "owner", senderDisplayName: "Support", senderRole: .owner,
               text: "Reply", createdAt: feedback.updatedAt, isSystem: false)]
    }
    func decideDsaCase(_ request: DsaDecisionFunctionRequest) async throws {
        decisions.append(request); if failDecision { throw AppError.network }
    }
    func deleteFeedback(id: String) async throws { if failDelete { throw AppError.network }; records.removeAll { $0.id == id } }
}

private final class FeedbackAuditListener: AppRealtimeListener { func cancel() {} }
