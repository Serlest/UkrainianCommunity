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
    private static let messagePageSize = 100
    @Published private(set) var counts: [String: Int] = [:]
    @Published private(set) var detailItems: [String: FeedbackItem] = [:]
    private var query = FeedbackInboxQuery()
    private var generation = UUID()
    private var session = UUID()
    private var watchedIDs: [String] = []
    private var recordListenerKeys: [String] = []
    private var inboxRefreshTask: Task<Void, Never>?
    private var nextCursor: FeedbackInboxCursor?
    private var messageCursors: [String: FeedbackPageCursor] = [:]
    private var moreMessages: [String: Bool] = [:]
    private var pendingOperations = PendingFeedbackOperationBuffer()
    private var pendingDsaDecisionAttempts: [String: (operationID: String, expectedRevision: String)] = [:]
    private var activeActorID: String?
    private var inboxLoad: (id: UUID, session: UUID, query: FeedbackInboxQuery, task: Task<FeedbackInboxPage, Error>)?

    init(
        repository: FeedbackRepository,
        notificationInboxRepository: NotificationInboxRepository? = nil
    ) {
        self.repository = repository
        self.notificationInboxRepository = notificationInboxRepository
    }

    func configure(actorID: String, filter: String, search: String, oldest: Bool) async {
        if activeActorID != actorID { reset(for: actorID) }
        let next = FeedbackInboxQuery(filter: filter, search: search, oldest: oldest, principalID: actorID)
        guard next != query || items.isEmpty else { return }
        if next != query { items = []; nextCursor = nil; hasMore = false; counts = [:] }
        query = next
        await refresh(actorID: actorID)
    }
    func loadIfNeeded(actorID: String) async {
        if activeActorID != actorID { reset(for: actorID) }
        query.principalID = actorID
        guard items.isEmpty else { _ = startListeningInbox(); return }
        await refresh(actorID: actorID)
    }
    func refresh(actorID: String) async {
        if activeActorID != actorID { reset(for: actorID) }
        query.principalID = actorID
        if let load = inboxLoad, load.session == session, load.query == query {
            _ = await load.task.result
            return
        }
        inboxLoad?.task.cancel()
        generation = UUID(); let expected = generation
        isLoading = true; isLoadingMore = false; error = nil
        let request = query
        let loadID = UUID()
        let task = Task { [repository] in try await repository.fetchOwnerInbox(query: request, after: nil) }
        inboxLoad = (loadID, session, request, task)
        defer { if inboxLoad?.id == loadID { inboxLoad = nil } }
        do {
            let page = try await task.value
            guard generation == expected, activeActorID == actorID else { return }
            items = page.items; page.items.forEach { detailItems[$0.id] = $0 }
            nextCursor = page.cursor; hasMore = page.cursor != nil; counts = page.counts
            _ = startListeningInbox()
            watchLoadedRecords()
        } catch {
            guard generation == expected, activeActorID == actorID else { return }
            self.error = (error as? AppError) ?? .unknown
        }
        if generation == expected { isLoading = false }
    }
    func loadMore(actorID: String) async {
        guard activeActorID == actorID, !isLoading, hasMore, !isLoadingMore, let cursor = nextCursor else { return }
        let expected = generation; let request = query
        isLoadingMore = true
        defer { if generation == expected { isLoadingMore = false } }
        do {
            let page = try await repository.fetchOwnerInbox(query: request, after: cursor)
            guard generation == expected, activeActorID == actorID else { return }
            mergeFeedback(page.items); watchLoadedRecords(); nextCursor = page.cursor; hasMore = page.cursor != nil; counts = page.counts
            error = nil
        } catch {
            if generation == expected, activeActorID == actorID { self.error = (error as? AppError) ?? .unknown }
        }
    }

    func feedback(id: String, actorID: String) async -> FeedbackItem? {
        let expectedSession = session
        guard activeActorID == actorID, session == expectedSession else { return nil }
        if let item = detailItems[id] ?? items.first(where: { $0.id == id }) { return item }
        do {
            let item = try await repository.fetchFeedback(id: id)
            guard activeActorID == actorID, session == expectedSession else { return nil }
            detailItems[item.id] = item
            return item
        } catch let appError as AppError { if session == expectedSession { error = appError } }
        catch { if session == expectedSession { self.error = .unknown } }
        return nil
    }

    func acknowledgeRead(_ item: FeedbackItem, actorID: String) async {
        let expectedSession = session
        guard activeActorID == actorID, session == expectedSession, item.unreadForOwner else { return }
        do {
            try await repository.acknowledgeFeedbackReadByOwner(id: item.id)
            let updated = try await repository.fetchFeedback(id: item.id)
            if activeActorID == actorID, session == expectedSession {
                detailItems[item.id] = updated
                items = items.map { $0.id == item.id ? updated : $0 }
            }
        }
        catch let appError as AppError {
            if activeActorID == actorID, session == expectedSession { actionError = appError }
        } catch {
            if activeActorID == actorID, session == expectedSession { actionError = .unknown }
        }
    }

    private func reset(for actorID: String) {
        session = UUID(); generation = UUID(); inboxRefreshTask?.cancel(); inboxRefreshTask = nil
        inboxLoad?.task.cancel(); inboxLoad = nil
        listenerBag.removeAll()
        watchedIDs = []; recordListenerKeys = []
        counts = [:]; detailItems = [:]; query = FeedbackInboxQuery(principalID: actorID)
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
        await update(item, status: .reviewed)
    }

    func setStatus(_ status: FeedbackStatus, for item: FeedbackItem) async {
        await update(item, status: status)
    }

    func archive(_ item: FeedbackItem, owner: AppUser) async {
        await close(item, owner: owner)
    }

    @discardableResult
    func delete(_ item: FeedbackItem) async -> Bool {
        guard let actorID = activeActorID else { return false }
        let expectedSession = session
        guard !deletingFeedbackIDs.contains(item.id) else { return false }
        deletingFeedbackIDs.insert(item.id)
        actionError = nil
        defer { if session == expectedSession { deletingFeedbackIDs.remove(item.id) } }

        do {
            try await repository.deleteFeedback(id: item.id)
            guard activeActorID == actorID, session == expectedSession else { return false }
            items.removeAll { $0.id == item.id }
            messagesByFeedbackID[item.id] = nil
            listenerBag.remove("feedbackMessages:\(item.id)")
            detailItems[item.id] = nil
            await refresh(actorID: actorID)
            return true
        } catch let appError as AppError {
            if session == expectedSession { actionError = appError }
        } catch {
            if session == expectedSession { actionError = .unknown }
        }
        return false
    }

    @discardableResult
    func clearInbox() async -> Bool {
        let expectedSession = session
        guard !isClearingInbox else { return false }
        isClearingInbox = true
        actionError = nil
        defer { if session == expectedSession { isClearingInbox = false } }

        do {
            let actorID = activeActorID
            try await repository.clearFeedbackInbox()
            guard activeActorID == actorID, session == expectedSession else { return true }
            // The backend retains protected DSA cases. Read back the remaining inbox.
            messagesByFeedbackID = [:]
            listenerBag.removeAll(); watchedIDs = []; recordListenerKeys = []
            if let actorID { await refresh(actorID: actorID) }
            return true
        } catch let appError as AppError {
            if session == expectedSession { actionError = appError }
        } catch {
            if session == expectedSession { actionError = .unknown }
        }
        return false
    }

    func sendReply(_ reply: String, to item: FeedbackItem, owner: AppUser) async -> Bool {
        let expectedSession = session
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
        defer { if session == expectedSession { updatingFeedbackIDs.remove(item.id) } }

        let operation = pendingOperations.attempt(
            feedbackID: item.id,
            kind: .ownerReply,
            text: trimmedReply,
            actorID: owner.id,
            actorDisplayName: owner.preferredDisplayName
        )

        do {
            try await repository.performFeedbackOperation(operation)
            guard activeActorID == owner.id, session == expectedSession else { return false }
            let updated = try await repository.fetchFeedback(id: item.id)
            guard activeActorID == owner.id, session == expectedSession else { return false }
            pendingOperations.complete(operation)
            detailItems[item.id] = updated
            await refresh(actorID: owner.id)
            let itemForMessages = updated
            await loadMessages(for: itemForMessages)
            actionError = nil
            return true
        } catch let appError as AppError {
            if session == expectedSession { actionError = appError }
            return false
        } catch {
            if session == expectedSession { actionError = .unknown }
            return false
        }
    }

    func decideDsaCase(_ request: DsaDecisionFunctionRequest, item: FeedbackItem) async -> Bool {
        guard let actorID = activeActorID else { return false }
        let expectedSession = session
        guard !updatingFeedbackIDs.contains(item.id) else { return false }
        updatingFeedbackIDs.insert(item.id)
        actionError = nil
        defer { if session == expectedSession { updatingFeedbackIDs.remove(item.id) } }
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
            expectedRevision: attempt.expectedRevision,
            revisionFormat: item.revision == nil ? nil : "exact", principalId: activeActorID
        )
        do {
            try await repository.decideDsaCase(request)
            guard activeActorID == actorID, session == expectedSession else { return false }
            pendingDsaDecisionAttempts["decision:\(item.id)"] = nil
            if let actorID = activeActorID { await refresh(actorID: actorID) }
            return true
        } catch let appError as AppError {
            if session == expectedSession { actionError = appError }
        } catch {
            if session == expectedSession { actionError = .unknown }
        }
        return false
    }

    func decideDsaAppeal(_ request: DsaAppealDecisionFunctionRequest, item: FeedbackItem) async -> Bool {
        guard let actorID = activeActorID else { return false }
        let expectedSession = session
        guard !updatingFeedbackIDs.contains(item.id) else { return false }
        updatingFeedbackIDs.insert(item.id)
        actionError = nil
        defer { if session == expectedSession { updatingFeedbackIDs.remove(item.id) } }
        let attempt = dsaAttempt(for: item, kind: "appealDecision")
        let request = DsaAppealDecisionFunctionRequest(
            reportId: request.reportId,
            outcome: request.outcome,
            reason: request.reason,
            humanReviewConfirmed: request.humanReviewConfirmed,
            operationId: attempt.operationID,
            expectedRevision: attempt.expectedRevision,
            revisionFormat: item.revision == nil ? nil : "exact", principalId: activeActorID
        )
        do {
            try await repository.decideDsaAppeal(request)
            guard activeActorID == actorID, session == expectedSession else { return false }
            pendingDsaDecisionAttempts["appealDecision:\(item.id)"] = nil
            if let actorID = activeActorID { await refresh(actorID: actorID) }
            return true
        } catch let appError as AppError {
            if session == expectedSession { actionError = appError }
        } catch {
            if session == expectedSession { actionError = .unknown }
        }
        return false
    }

    @discardableResult
    func close(_ item: FeedbackItem, owner: AppUser) async -> Bool {
        let expectedSession = session
        guard activeActorID == owner.id, !updatingFeedbackIDs.contains(item.id) else { return false }
        updatingFeedbackIDs.insert(item.id)
        actionError = nil
        defer { if session == expectedSession { updatingFeedbackIDs.remove(item.id) } }

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
            guard activeActorID == owner.id, session == expectedSession else { return false }
            items = items.map { current in
                guard current.id == item.id else { return current }
                return current.updating(status: .closed)
            }
            await refresh(actorID: owner.id)
            actionError = nil
            return true
        } catch let appError as AppError {
            if session == expectedSession { actionError = appError }
        } catch {
            if session == expectedSession { actionError = .unknown }
        }
        return false
    }

    func messages(for item: FeedbackItem) -> [FeedbackMessage] {
        messagesByFeedbackID[item.id] ?? item.legacyMessages
    }

    private func dsaAttempt(for item: FeedbackItem, kind: String) -> (operationID: String, expectedRevision: String) {
        let key = "\(kind):\(item.id)"
        let timestamp = Timestamp(date: item.updatedAt)
        let expectedRevision = item.revision ?? "\(timestamp.seconds):\(timestamp.nanoseconds)"
        if let attempt = pendingDsaDecisionAttempts[key], attempt.expectedRevision == expectedRevision { return attempt }
        let attempt = (operationID: UUID().uuidString, expectedRevision: expectedRevision)
        pendingDsaDecisionAttempts[key] = attempt
        return attempt
    }

    func hasMoreMessages(for feedbackID: String) -> Bool {
        moreMessages[feedbackID] ?? false
    }

    func loadMessages(for item: FeedbackItem) async {
        let expectedSession = session
        let expectedActorID = activeActorID
        guard expectedActorID != nil else { return }
        guard !loadingMessageFeedbackIDs.contains(item.id) else { return }
        loadingMessageFeedbackIDs.insert(item.id)
        messageErrorsByFeedbackID[item.id] = nil
        defer { if session == expectedSession { loadingMessageFeedbackIDs.remove(item.id) } }
        do {
            let page = try await repository.fetchFeedbackMessagesPage(feedback: item, after: nil, limit: Self.messagePageSize)
            guard activeActorID == expectedActorID, session == expectedSession else { return }
            mergeMessages(item.legacyMessages + page.items, feedbackID: item.id)
            messageCursors[item.id] = page.nextCursor
            moreMessages[item.id] = page.hasMore
            _ = startListeningMessages(for: item)
        } catch let appError as AppError {
            if activeActorID == expectedActorID, session == expectedSession { messageErrorsByFeedbackID[item.id] = appError }
        } catch {
            if activeActorID == expectedActorID, session == expectedSession { messageErrorsByFeedbackID[item.id] = .unknown }
        }
    }

    func loadMoreMessages(for item: FeedbackItem) async {
        let expectedSession = session
        let expectedActorID = activeActorID
        guard expectedActorID != nil else { return }
        guard hasMoreMessages(for: item.id), !loadingMoreMessageFeedbackIDs.contains(item.id), let cursor = messageCursors[item.id] else { return }
        loadingMoreMessageFeedbackIDs.insert(item.id)
        defer { if session == expectedSession { loadingMoreMessageFeedbackIDs.remove(item.id) } }
        do {
            let page = try await repository.fetchFeedbackMessagesPage(feedback: item, after: cursor, limit: Self.messagePageSize)
            guard activeActorID == expectedActorID, session == expectedSession else { return }
            mergeMessages(page.items, feedbackID: item.id)
            messageCursors[item.id] = page.nextCursor
            moreMessages[item.id] = page.hasMore
            messageErrorsByFeedbackID[item.id] = nil
        } catch let appError as AppError {
            if activeActorID == expectedActorID, session == expectedSession { messageErrorsByFeedbackID[item.id] = appError }
        } catch {
            if activeActorID == expectedActorID, session == expectedSession { messageErrorsByFeedbackID[item.id] = .unknown }
        }
    }

    func stopListeningMessages(for feedbackID: String) {
        listenerBag.remove("feedbackMessages:\(feedbackID)")
    }

    private func startListeningInbox() -> Bool {
        let key = "feedbackInbox"
        guard let realtime = repository as? FeedbackRealtimeRepository, let actorID = activeActorID else { return false }
        guard !listenerBag.contains(key) else { return true }
        let expectedSession = session
        listenerBag.set(realtime.listenOwnerFeedbackInbox { [weak self] fresh in
            guard let self, self.session == expectedSession, self.activeActorID == actorID else { return }
            // The snapshot invalidates the server query, including removals. Never merge
            // an incomplete top-page snapshot into a globally filtered/paginated list.
            fresh.forEach { self.detailItems[$0.id] = $0 }
            self.inboxRefreshTask?.cancel()
            self.inboxRefreshTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self, self.session == expectedSession else { return }
                await self.refresh(actorID: actorID)
            }
        } onError: { [weak self] error in
            guard let self, self.session == expectedSession else { return }
            self.listenerBag.remove(key); self.error = error
        }, for: key)
        return true
    }

    private func watchLoadedRecords() {
        guard let realtime = repository as? FeedbackRecordsRealtimeRepository, let actorID = activeActorID else { return }
        let ids = items.map(\.id).sorted()
        guard ids != watchedIDs else { return }
        recordListenerKeys.forEach { listenerBag.remove($0) }; recordListenerKeys = []; watchedIDs = ids
        let expectedSession = session
        for start in stride(from: 0, to: ids.count, by: 30) {
            let batch = Array(ids[start..<min(start + 30, ids.count)])
            let key = "feedbackRecords:\(start)"; recordListenerKeys.append(key)
            var receivedInitialSnapshot = false
            listenerBag.set(realtime.listenFeedbackRecords(ids: batch) { [weak self] fresh in
                guard let self, self.session == expectedSession else { return }
                let received = Set(fresh.map(\.id))
                let removed = Set(batch).subtracting(received)
                // Derived search fields change without updating the source revision.
                // Subsequent snapshots must invalidate the query even when the DTO is identical.
                let changed = receivedInitialSnapshot || !removed.isEmpty || fresh.contains { self.detailItems[$0.id]?.revision != $0.revision }
                receivedInitialSnapshot = true
                guard changed else { return }
                removed.forEach { self.detailItems[$0] = nil }
                self.items.removeAll { removed.contains($0.id) }
                fresh.forEach { self.detailItems[$0.id] = $0 }
                self.inboxRefreshTask?.cancel()
                self.inboxRefreshTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled, let self, self.session == expectedSession else { return }
                    await self.refresh(actorID: actorID)
                }
            } onError: { [weak self] error in
                guard let self, self.session == expectedSession else { return }
                self.actionError = error
            }, for: key)
        }
    }

    private func startListeningMessages(for item: FeedbackItem) -> Bool {
        let expectedSession = session
        let key = "feedbackMessages:\(item.id)"
        let expectedActorID = activeActorID
        guard expectedActorID != nil else { return false }
        guard let realtimeRepository = repository as? FeedbackRealtimeRepository else { return false }
        guard !listenerBag.contains(key) else { return true }

        listenerBag.set(realtimeRepository.listenFeedbackMessages(feedback: item) { [weak self] messages in
            guard let self, self.activeActorID == expectedActorID, self.session == expectedSession else { return }
            self.mergeMessages(messages, feedbackID: item.id)
            self.loadingMessageFeedbackIDs.remove(item.id)
            self.messageErrorsByFeedbackID[item.id] = nil
        } onError: { [weak self] appError in
            guard let self, self.activeActorID == expectedActorID, self.session == expectedSession else { return }
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
        guard let actorID = activeActorID, !updatingFeedbackIDs.contains(item.id) else { return }
        let expectedSession = session
        updatingFeedbackIDs.insert(item.id); actionError = nil
        defer { if session == expectedSession { updatingFeedbackIDs.remove(item.id) } }
        do {
            try await repository.updateFeedbackStatus(id: item.id, status: status)
            let updated = try await repository.fetchFeedback(id: item.id)
            guard activeActorID == actorID, session == expectedSession else { return }
            detailItems[item.id] = updated
            await refresh(actorID: actorID)
        } catch {
            if session == expectedSession { actionError = (error as? AppError) ?? .unknown }
        }
    }

    private func mergeFeedback(_ newItems: [FeedbackItem]) {
        var byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        newItems.forEach { byID[$0.id] = $0; detailItems[$0.id] = $0 }
        items = byID.values.sorted {
            let left = $0.lastMessageAt ?? $0.updatedAt, right = $1.lastMessageAt ?? $1.updatedAt
            return left == right ? (query.oldest ? $0.id < $1.id : $0.id > $1.id) : (query.oldest ? left < right : left > right)
        }
    }

    private func mergeMessages(_ newItems: [FeedbackMessage], feedbackID: String) {
        messagesByFeedbackID[feedbackID] = FeedbackMessageHistory.merge(messagesByFeedbackID[feedbackID] ?? [], newItems)
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
            reportContext: reportContext,
            occurrenceCount: occurrenceCount,
            dsaCase: dsaCase,
            revision: revision
        )
    }
}
