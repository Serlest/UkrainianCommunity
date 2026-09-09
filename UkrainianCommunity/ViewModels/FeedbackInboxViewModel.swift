import Combine
import FirebaseFirestore
import Foundation

@MainActor
final class FeedbackInboxViewModel: ObservableObject {
    @Published private(set) var items: [FeedbackItem] = []
    @Published private(set) var messagesByFeedbackID: [String: [FeedbackMessage]] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = false
    @Published private(set) var loadingMessageFeedbackIDs = Set<String>()
    @Published private(set) var loadingMoreMessageFeedbackIDs = Set<String>()
    @Published private(set) var messageErrorsByFeedbackID: [String: AppError] = [:]
    @Published private(set) var error: AppError?
    @Published private(set) var actionError: AppError?
    @Published private(set) var updatingFeedbackIDs = Set<String>()
    @Published private(set) var deletingFeedbackIDs = Set<String>()
    @Published private(set) var isClearingInbox = false

    private let repository: FeedbackRepository
    private let notificationInboxRepository: NotificationInboxRepository?
    private let listenerBag = RealtimeListenerBag()
    private static let feedbackPageSize = 100
    private static let messagePageSize = 100
    private var nextCursor: FeedbackPageCursor?
    private var messageCursors: [String: FeedbackPageCursor] = [:]
    private var moreMessages: [String: Bool] = [:]
    private var pendingOperations = PendingFeedbackOperationBuffer()
    private var pendingDsaDecisionAttempts: [String: (operationID: String, expectedRevision: String)] = [:]
    private var activeActorID: String?

    init(
        repository: FeedbackRepository,
        notificationInboxRepository: NotificationInboxRepository? = nil
    ) {
        self.repository = repository
        self.notificationInboxRepository = notificationInboxRepository
    }

    func loadIfNeeded(actorID: String) async {
        if activeActorID != actorID { reset(for: actorID) }
        guard items.isEmpty else { _ = startListeningInbox(); return }
        await refresh(actorID: actorID)
    }

    func refresh(actorID: String) async {
        if activeActorID != actorID { reset(for: actorID) }
        _ = startListeningInbox()
        isLoading = true
        error = nil
        await fetchInboxOnce(actorID: actorID)
        if activeActorID == actorID { isLoading = false }
    }

    private func fetchInboxOnce(actorID: String) async {
        do {
            let page = try await RefreshRequest.run { [self] in
                try await repository.fetchFeedbackPage(userID: nil, after: nil, limit: Self.feedbackPageSize)
            }
            guard activeActorID == actorID else { return }
            items = page.items
            nextCursor = page.nextCursor
            hasMore = page.hasMore
            error = nil
        } catch let appError as AppError {
            if activeActorID == actorID { error = appError }
        } catch {
            if activeActorID == actorID { self.error = .unknown }
        }
    }

    func loadMore(actorID: String) async {
        guard activeActorID == actorID, hasMore, !isLoadingMore, let cursor = nextCursor else { return }
        isLoadingMore = true
        defer { if activeActorID == actorID { isLoadingMore = false } }
        do {
            let page = try await repository.fetchFeedbackPage(userID: nil, after: cursor, limit: Self.feedbackPageSize)
            guard activeActorID == actorID else { return }
            mergeFeedback(page.items)
            nextCursor = page.nextCursor
            hasMore = page.hasMore
            error = nil
        } catch let appError as AppError {
            if activeActorID == actorID { error = appError }
        } catch {
            if activeActorID == actorID { self.error = .unknown }
        }
    }

    func feedback(id: String, actorID: String) async -> FeedbackItem? {
        guard activeActorID == actorID else { return nil }
        if let item = items.first(where: { $0.id == id }) { return item }
        do {
            let item = try await repository.fetchFeedback(id: id)
            guard activeActorID == actorID else { return nil }
            mergeFeedback([item])
            return item
        } catch let appError as AppError { error = appError }
        catch { self.error = .unknown }
        return nil
    }

    func acknowledgeRead(_ item: FeedbackItem, actorID: String) async {
        guard activeActorID == actorID, item.unreadForOwner else { return }
        do {
            try await repository.acknowledgeFeedbackReadByOwner(id: item.id)
            let updated = try await repository.fetchFeedback(id: item.id)
            if activeActorID == actorID { mergeFeedback([updated]) }
        }
        catch let appError as AppError {
            if activeActorID == actorID { actionError = appError }
        } catch {
            if activeActorID == actorID { actionError = .unknown }
        }
    }

    private func reset(for actorID: String) {
        listenerBag.removeAll()
        items = []; messagesByFeedbackID = [:]; messageErrorsByFeedbackID = [:]
        loadingMessageFeedbackIDs = []; loadingMoreMessageFeedbackIDs = []
        updatingFeedbackIDs = []; deletingFeedbackIDs = []; isClearingInbox = false
        isLoading = false; isLoadingMore = false; hasMore = false
        nextCursor = nil; messageCursors = [:]; moreMessages = [:]
        pendingOperations.removeAll()
        pendingDsaDecisionAttempts.removeAll()
        error = nil; actionError = nil; activeActorID = actorID
    }

    func reset() {
        reset(for: "")
        activeActorID = nil
    }

    func markReviewed(_ item: FeedbackItem) async {
        await update(item, status: .answered)
    }

    func archive(_ item: FeedbackItem, owner: AppUser) async {
        await close(item, owner: owner)
    }

    @discardableResult
    func delete(_ item: FeedbackItem) async -> Bool {
        guard !deletingFeedbackIDs.contains(item.id) else { return false }
        deletingFeedbackIDs.insert(item.id)
        actionError = nil
        defer { deletingFeedbackIDs.remove(item.id) }

        do {
            try await repository.deleteFeedback(id: item.id)
            items.removeAll { $0.id == item.id }
            messagesByFeedbackID[item.id] = nil
            listenerBag.remove("feedbackMessages:\(item.id)")
            return true
        } catch let appError as AppError {
            actionError = appError
        } catch {
            actionError = .unknown
        }
        return false
    }

    @discardableResult
    func clearInbox() async -> Bool {
        guard !isClearingInbox else { return false }
        isClearingInbox = true
        actionError = nil
        defer { isClearingInbox = false }

        do {
            let actorID = activeActorID
            try await repository.clearFeedbackInbox()
            guard activeActorID == actorID else { return true }
            // The backend retains protected DSA cases. Read back the remaining inbox.
            messagesByFeedbackID = [:]
            listenerBag.removeAll()
            if let actorID { await refresh(actorID: actorID) }
            return true
        } catch let appError as AppError {
            actionError = appError
        } catch {
            actionError = .unknown
        }
        return false
    }

    func sendReply(_ reply: String, to item: FeedbackItem, owner: AppUser) async -> Bool {
        let trimmedReply = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReply.isEmpty else {
            actionError = .validationFailed
            return false
        }

        guard trimmedReply.count <= 2000 else {
            actionError = .validationFailed
            return false
        }

        guard activeActorID == owner.id, !updatingFeedbackIDs.contains(item.id) else { return false }
        updatingFeedbackIDs.insert(item.id)
        actionError = nil
        defer { updatingFeedbackIDs.remove(item.id) }

        let operation = pendingOperations.attempt(
            feedbackID: item.id,
            kind: .ownerReply,
            text: trimmedReply,
            actorID: owner.id,
            actorDisplayName: owner.preferredDisplayName
        )

        do {
            try await repository.performFeedbackOperation(operation)
            pendingOperations.complete(operation)
            guard activeActorID == owner.id else { return false }
            if repository is FeedbackRealtimeRepository {
                _ = startListeningInbox()
            } else if let actorID = activeActorID {
                await refresh(actorID: actorID)
            }
            let itemForMessages = items.first(where: { $0.id == item.id }) ?? item
            await loadMessages(for: itemForMessages)
            actionError = nil
            return true
        } catch let appError as AppError {
            actionError = appError
            return false
        } catch {
            actionError = .unknown
            return false
        }
    }

    func decideDsaCase(_ request: DsaDecisionFunctionRequest, item: FeedbackItem) async -> Bool {
        guard !updatingFeedbackIDs.contains(item.id) else { return false }
        updatingFeedbackIDs.insert(item.id)
        actionError = nil
        defer { updatingFeedbackIDs.remove(item.id) }
        let attempt = dsaAttempt(for: item, kind: "decision")
        let request = DsaDecisionFunctionRequest(
            reportId: request.reportId,
            outcome: request.outcome,
            factsAndCircumstances: request.factsAndCircumstances,
            legalBasis: request.legalBasis,
            termsBasis: request.termsBasis,
            territorialScope: request.territorialScope,
            duration: request.duration,
            redressInformation: request.redressInformation,
            humanReviewConfirmed: request.humanReviewConfirmed,
            operationId: attempt.operationID,
            expectedRevision: attempt.expectedRevision
        )
        do {
            try await repository.decideDsaCase(request)
            pendingDsaDecisionAttempts["decision:\(item.id)"] = nil
            if let actorID = activeActorID { await refresh(actorID: actorID) }
            return true
        } catch let appError as AppError {
            actionError = appError
        } catch {
            actionError = .unknown
        }
        return false
    }

    func decideDsaAppeal(_ request: DsaAppealDecisionFunctionRequest, item: FeedbackItem) async -> Bool {
        guard !updatingFeedbackIDs.contains(item.id) else { return false }
        updatingFeedbackIDs.insert(item.id)
        actionError = nil
        defer { updatingFeedbackIDs.remove(item.id) }
        let attempt = dsaAttempt(for: item, kind: "appealDecision")
        let request = DsaAppealDecisionFunctionRequest(
            reportId: request.reportId,
            outcome: request.outcome,
            reason: request.reason,
            humanReviewConfirmed: request.humanReviewConfirmed,
            operationId: attempt.operationID,
            expectedRevision: attempt.expectedRevision
        )
        do {
            try await repository.decideDsaAppeal(request)
            pendingDsaDecisionAttempts["appealDecision:\(item.id)"] = nil
            if let actorID = activeActorID { await refresh(actorID: actorID) }
            return true
        } catch let appError as AppError {
            actionError = appError
        } catch {
            actionError = .unknown
        }
        return false
    }

    @discardableResult
    func close(_ item: FeedbackItem, owner: AppUser) async -> Bool {
        guard activeActorID == owner.id, !updatingFeedbackIDs.contains(item.id) else { return false }
        updatingFeedbackIDs.insert(item.id)
        actionError = nil
        defer { updatingFeedbackIDs.remove(item.id) }

        let operation = pendingOperations.attempt(
            feedbackID: item.id,
            kind: .close,
            text: AppStrings.Feedback.closedSystemMessage,
            actorID: owner.id,
            actorDisplayName: AppStrings.Feedback.ownerSender
        )

        do {
            try await repository.performFeedbackOperation(operation)
            pendingOperations.complete(operation)
            guard activeActorID == owner.id else { return false }
            items = items.map { current in
                guard current.id == item.id else { return current }
                return current.updating(status: .closed)
            }
            actionError = nil
            return true
        } catch let appError as AppError {
            actionError = appError
        } catch {
            actionError = .unknown
        }
        return false
    }

    func messages(for item: FeedbackItem) -> [FeedbackMessage] {
        messagesByFeedbackID[item.id] ?? item.legacyMessages
    }

    private func dsaAttempt(for item: FeedbackItem, kind: String) -> (operationID: String, expectedRevision: String) {
        let key = "\(kind):\(item.id)"
        let timestamp = Timestamp(date: item.updatedAt)
        let expectedRevision = "\(timestamp.seconds):\(timestamp.nanoseconds)"
        if let attempt = pendingDsaDecisionAttempts[key], attempt.expectedRevision == expectedRevision { return attempt }
        let attempt = (operationID: UUID().uuidString, expectedRevision: expectedRevision)
        pendingDsaDecisionAttempts[key] = attempt
        return attempt
    }

    func hasMoreMessages(for feedbackID: String) -> Bool {
        moreMessages[feedbackID] ?? false
    }

    func loadMessages(for item: FeedbackItem) async {
        let expectedActorID = activeActorID
        guard expectedActorID != nil else { return }
        guard !loadingMessageFeedbackIDs.contains(item.id) else { return }
        loadingMessageFeedbackIDs.insert(item.id)
        messageErrorsByFeedbackID[item.id] = nil
        defer { loadingMessageFeedbackIDs.remove(item.id) }
        do {
            let page = try await repository.fetchFeedbackMessagesPage(feedback: item, after: nil, limit: Self.messagePageSize)
            guard activeActorID == expectedActorID else { return }
            mergeMessages(item.legacyMessages + page.items, feedbackID: item.id)
            messageCursors[item.id] = page.nextCursor
            moreMessages[item.id] = page.hasMore
            _ = startListeningMessages(for: item)
        } catch let appError as AppError {
            if activeActorID == expectedActorID { messageErrorsByFeedbackID[item.id] = appError }
        } catch {
            if activeActorID == expectedActorID { messageErrorsByFeedbackID[item.id] = .unknown }
        }
    }

    func loadMoreMessages(for item: FeedbackItem) async {
        let expectedActorID = activeActorID
        guard expectedActorID != nil else { return }
        guard hasMoreMessages(for: item.id), !loadingMoreMessageFeedbackIDs.contains(item.id), let cursor = messageCursors[item.id] else { return }
        loadingMoreMessageFeedbackIDs.insert(item.id)
        defer { loadingMoreMessageFeedbackIDs.remove(item.id) }
        do {
            let page = try await repository.fetchFeedbackMessagesPage(feedback: item, after: cursor, limit: Self.messagePageSize)
            guard activeActorID == expectedActorID else { return }
            mergeMessages(page.items, feedbackID: item.id)
            messageCursors[item.id] = page.nextCursor
            moreMessages[item.id] = page.hasMore
            messageErrorsByFeedbackID[item.id] = nil
        } catch let appError as AppError {
            if activeActorID == expectedActorID { messageErrorsByFeedbackID[item.id] = appError }
        } catch {
            if activeActorID == expectedActorID { messageErrorsByFeedbackID[item.id] = .unknown }
        }
    }

    func stopListeningMessages(for feedbackID: String) {
        listenerBag.remove("feedbackMessages:\(feedbackID)")
    }

    private func startListeningInbox() -> Bool {
        let key = "feedbackInbox"
        guard let realtimeRepository = repository as? FeedbackRealtimeRepository else { return false }
        guard !listenerBag.contains(key) else { return true }

        listenerBag.set(realtimeRepository.listenOwnerFeedbackInbox { [weak self] items in
            guard let self, self.activeActorID != nil else { return }
            self.mergeFeedback(items)
            self.isLoading = false
            self.error = nil
        } onError: { [weak self] appError in
            self?.listenerBag.remove(key)
            self?.isLoading = false
            self?.error = appError
            #if DEBUG
            print("Realtime listener failed: purpose=feedbackInbox key=\(key) error=\(appError)")
            #endif
        }, for: key)
        return true
    }

    private func startListeningMessages(for item: FeedbackItem) -> Bool {
        let key = "feedbackMessages:\(item.id)"
        let expectedActorID = activeActorID
        guard expectedActorID != nil else { return false }
        guard let realtimeRepository = repository as? FeedbackRealtimeRepository else { return false }
        guard !listenerBag.contains(key) else { return true }

        listenerBag.set(realtimeRepository.listenFeedbackMessages(feedback: item) { [weak self] messages in
            guard let self, self.activeActorID == expectedActorID else { return }
            self.mergeMessages(messages, feedbackID: item.id)
            self.loadingMessageFeedbackIDs.remove(item.id)
            self.messageErrorsByFeedbackID[item.id] = nil
        } onError: { [weak self] appError in
            guard let self, self.activeActorID == expectedActorID else { return }
            self.listenerBag.remove(key)
            self.loadingMessageFeedbackIDs.remove(item.id)
            self.messageErrorsByFeedbackID[item.id] = appError
            #if DEBUG
            print("Realtime listener failed: purpose=feedbackMessages key=\(key) error=\(appError)")
            #endif
        }, for: key)
        loadingMessageFeedbackIDs.insert(item.id)
        return true
    }

    private func update(_ item: FeedbackItem, status: FeedbackStatus) async {
        guard !updatingFeedbackIDs.contains(item.id) else { return }
        updatingFeedbackIDs.insert(item.id)
        defer { updatingFeedbackIDs.remove(item.id) }

        do {
            try await repository.updateFeedbackStatus(id: item.id, status: status)
            items = items.map { current in
                guard current.id == item.id else { return current }
                return current.updating(status: status)
            }
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    private func mergeFeedback(_ newItems: [FeedbackItem]) {
        var byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        newItems.forEach { byID[$0.id] = $0 }
        items = byID.values.sorted { $0.createdAt == $1.createdAt ? $0.id > $1.id : $0.createdAt > $1.createdAt }
    }

    private func mergeMessages(_ newItems: [FeedbackMessage], feedbackID: String) {
        var byID = Dictionary(uniqueKeysWithValues: (messagesByFeedbackID[feedbackID] ?? []).map { ($0.id, $0) })
        newItems.forEach { byID[$0.id] = $0 }
        messagesByFeedbackID[feedbackID] = byID.values.sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt }
    }
}

private extension FeedbackItem {
    func updating(status: FeedbackStatus) -> FeedbackItem {
        FeedbackItem(
            id: id,
            type: type,
            subject: subject,
            message: message,
            status: status,
            createdAt: createdAt,
            updatedAt: .now,
            userId: userId,
            userDisplayName: userDisplayName,
            ownerReply: ownerReply,
            repliedAt: repliedAt,
            repliedByUserId: repliedByUserId,
            lastMessageText: lastMessageText,
            lastMessageAt: lastMessageAt,
            lastMessageByUserId: lastMessageByUserId,
            lastMessageByRole: lastMessageByRole,
            unreadForOwner: unreadForOwner,
            unreadForUser: unreadForUser,
            dsaCase: dsaCase
        )
    }
}
