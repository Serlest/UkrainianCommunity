import Combine
import FirebaseFirestore
import Foundation

@MainActor
final class MyFeedbackViewModel: ObservableObject {
    @Published private(set) var items: [FeedbackItem] = []
    @Published private(set) var messagesByFeedbackID: [String: [FeedbackMessage]] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = false
    @Published private(set) var loadingMessageFeedbackIDs = Set<String>()
    @Published private(set) var loadingMoreMessageFeedbackIDs = Set<String>()
    @Published private(set) var sendingMessageFeedbackIDs = Set<String>()
    @Published private(set) var messageErrorsByFeedbackID: [String: AppError] = [:]
    @Published private(set) var error: AppError?
    @Published private(set) var actionError: AppError?
    @Published private(set) var failedLoadMore = false
    private var actionErrorRecordID: String?

    func actionError(for feedbackID: String) -> AppError? {
        actionErrorRecordID == feedbackID ? actionError : nil
    }
    private func setActionError(_ error: AppError, for feedbackID: String?) {
        actionErrorRecordID = feedbackID; actionError = error
    }

    private static let feedbackPageSize = 50
    private static let messagePageSize = 100
    @Published private(set) var detailStates: [String: FeedbackRecordState] = [:]
    private var detailReadTokens: [String: UUID] = [:]

    private let repository: FeedbackRepository
    private let listenerBag = RealtimeListenerBag()
    private var nextCursor: FeedbackPageCursor?
    private var messageCursors: [String: FeedbackPageCursor] = [:]
    private var moreMessages: [String: Bool] = [:]
    private var pendingOperations = PendingFeedbackOperationBuffer()
    private var pendingDsaAppealAttempts: [String: (operationID: String, expectedRevision: String)] = [:]
    private var activeUserID: String?
    private var session = UUID()
    private var generation = UUID()
    private var firstPageLoad: (id: UUID, session: UUID, task: Task<FeedbackPage, Error>)?
    @Published private(set) var hasLoaded = false

    init(repository: FeedbackRepository) { self.repository = repository }

    func loadIfNeeded(userID: String) async {
        if activeUserID != userID { reset(for: userID) }
        guard !hasLoaded else { _ = startListeningMyFeedback(userID: userID); return }
        await refresh(userID: userID)
    }

    func refresh(userID: String) async {
        if activeUserID != userID { reset(for: userID) }
        if let load = firstPageLoad, load.session == session {
            _ = await load.task.result
            return
        }
        let expectedSession = session
        generation = UUID(); let expectedGeneration = generation
        isLoading = true; isLoadingMore = false; failedLoadMore = false
        error = nil
        let loadID = UUID()
        let task = Task { [repository] in
            try await RefreshRequest.run { try await repository.fetchFeedbackPage(userID: userID, after: nil, limit: Self.feedbackPageSize) }
        }
        firstPageLoad = (loadID, session, task)
        defer { if firstPageLoad?.id == loadID { firstPageLoad = nil } }
        do {
            let page = try await task.value
            guard activeUserID == userID, session == expectedSession, generation == expectedGeneration else { return }
            items = page.items
            nextCursor = page.nextCursor
            hasMore = page.hasMore
            hasLoaded = true
            _ = startListeningMyFeedback(userID: userID)
        } catch let appError as AppError {
            if activeUserID == userID, session == expectedSession { error = appError }
        } catch {
            if activeUserID == userID, session == expectedSession { self.error = .unknown }
        }
        if activeUserID == userID, session == expectedSession { isLoading = false }
    }

    func loadMore(userID: String) async {
        let expectedSession = session
        let expectedGeneration = generation
        guard activeUserID == userID, !isLoading, hasMore, !isLoadingMore, let cursor = nextCursor else { return }
        isLoadingMore = true
        defer { if activeUserID == userID, session == expectedSession, generation == expectedGeneration { isLoadingMore = false } }
        do {
            let page = try await RefreshRequest.run { [repository] in try await repository.fetchFeedbackPage(userID: userID, after: cursor, limit: Self.feedbackPageSize) }
            guard activeUserID == userID, session == expectedSession, generation == expectedGeneration else { return }
            mergeFeedback(page.items)
            nextCursor = page.nextCursor
            hasMore = page.hasMore
            error = nil; failedLoadMore = false
        } catch let appError as AppError {
            if activeUserID == userID, session == expectedSession, generation == expectedGeneration { error = appError; failedLoadMore = true }
        } catch {
            if activeUserID == userID, session == expectedSession, generation == expectedGeneration { self.error = .unknown; failedLoadMore = true }
        }
    }

    func retry(userID: String) async {
        if failedLoadMore { await loadMore(userID: userID) }
        else { await refresh(userID: userID) }
    }

    func feedback(id: String, userID: String) async -> FeedbackItem? {
        let expectedSession = session
        guard activeUserID == userID else { return nil }
        if let item = items.first(where: { $0.id == id }) { return item }
        do {
            let item = try await RefreshRequest.run { [repository] in try await repository.fetchFeedback(id: id) }
            guard activeUserID == userID, session == expectedSession, item.userId == userID else { return nil }
            mergeFeedback([item])
            return item
        } catch let appError as AppError {
            if activeUserID == userID, session == expectedSession { error = appError }
        } catch {
            if activeUserID == userID, session == expectedSession { self.error = .unknown }
        }
        return nil
    }

    func invalidateDetail(id: String) { detailStates[id] = nil; detailReadTokens[id] = nil }

    func prepareDetail(id: String, userID: String) async -> FeedbackItem? {
        guard activeUserID == userID, detailReadTokens[id] == nil else { return nil }
        let expectedSession = session
        let token = UUID()
        detailReadTokens[id] = token; detailStates[id] = .loading
        defer { if detailReadTokens[id] == token { detailReadTokens[id] = nil } }
        do {
            let fresh = try await RefreshRequest.run { [repository] in try await repository.fetchFeedback(id: id) }
            guard activeUserID == userID, session == expectedSession, detailReadTokens[id] == token else { return nil }
            guard fresh.userId == userID else { detailStates[id] = .unavailable; return nil }
            mergeFeedback([fresh])
            detailStates[id] = .ready
            return fresh
        } catch {
            guard activeUserID == userID, session == expectedSession, detailReadTokens[id] == token else { return nil }
            let failure = (error as? AppError) ?? .unknown
            detailStates[id] = failure == .notFound || failure == .permissionDenied ? .unavailable : .failed(failure)
        }
        return nil
    }

    func acknowledgeRead(_ item: FeedbackItem, userID: String) async {
        let expectedSession = session
        guard activeUserID == userID, item.userId == userID, item.unreadForUser else { return }
        do {
            try await repository.acknowledgeFeedbackReadByUser(id: item.id, userID: userID)
            let updated = try await RefreshRequest.run { [repository] in try await repository.fetchFeedback(id: item.id) }
            if activeUserID == userID, session == expectedSession { mergeFeedback([updated]) }
        } catch let appError as AppError {
            if activeUserID == userID, session == expectedSession { setActionError(appError, for: item.id) }
        } catch {
            if activeUserID == userID, session == expectedSession { setActionError(.unknown, for: item.id) }
        }
    }

    func reset() { reset(for: nil) }

    private func reset(for userID: String?) {
        session = UUID(); generation = UUID()
        firstPageLoad?.task.cancel(); firstPageLoad = nil
        detailStates = [:]; detailReadTokens = [:]
        listenerBag.removeAll()
        items = []; messagesByFeedbackID = [:]; messageErrorsByFeedbackID = [:]
        loadingMessageFeedbackIDs = []; loadingMoreMessageFeedbackIDs = []; sendingMessageFeedbackIDs = []
        isLoading = false; isLoadingMore = false; hasMore = false; nextCursor = nil; hasLoaded = false
        messageCursors = [:]; moreMessages = [:]; error = nil; actionError = nil
        failedLoadMore = false; actionErrorRecordID = nil
        pendingOperations.removeAll()
        pendingDsaAppealAttempts.removeAll()
        activeUserID = userID
    }

    func messages(for item: FeedbackItem) -> [FeedbackMessage] { messagesByFeedbackID[item.id] ?? item.legacyMessages }
    func hasMoreMessages(for feedbackID: String) -> Bool { moreMessages[feedbackID] ?? false }

    func loadMessages(for item: FeedbackItem) async {
        let expectedSession = session
        let expectedUserID = activeUserID
        guard expectedUserID != nil else { return }
        guard !loadingMessageFeedbackIDs.contains(item.id) else { return }
        loadingMessageFeedbackIDs.insert(item.id)
        messageErrorsByFeedbackID[item.id] = nil
        defer { if session == expectedSession { loadingMessageFeedbackIDs.remove(item.id) } }
        do {
            let page = try await RefreshRequest.run { [repository] in try await repository.fetchFeedbackMessagesPage(feedback: item, after: nil, limit: Self.messagePageSize) }
            guard activeUserID == expectedUserID, session == expectedSession else { return }
            mergeMessages(item.legacyMessages + page.items, feedbackID: item.id)
            messageCursors[item.id] = page.nextCursor
            moreMessages[item.id] = page.hasMore
            _ = startListeningMessages(for: item)
        } catch let appError as AppError {
            if activeUserID == expectedUserID, session == expectedSession { messageErrorsByFeedbackID[item.id] = appError }
        } catch {
            if activeUserID == expectedUserID, session == expectedSession { messageErrorsByFeedbackID[item.id] = .unknown }
        }
    }

    func loadMoreMessages(for item: FeedbackItem) async {
        let expectedSession = session
        let expectedUserID = activeUserID
        guard expectedUserID != nil else { return }
        guard hasMoreMessages(for: item.id), !loadingMoreMessageFeedbackIDs.contains(item.id), let cursor = messageCursors[item.id] else { return }
        loadingMoreMessageFeedbackIDs.insert(item.id)
        defer { if session == expectedSession { loadingMoreMessageFeedbackIDs.remove(item.id) } }
        do {
            let page = try await RefreshRequest.run { [repository] in try await repository.fetchFeedbackMessagesPage(feedback: item, after: cursor, limit: Self.messagePageSize) }
            guard activeUserID == expectedUserID, session == expectedSession else { return }
            mergeMessages(page.items, feedbackID: item.id)
            messageCursors[item.id] = page.nextCursor
            moreMessages[item.id] = page.hasMore
            messageErrorsByFeedbackID[item.id] = nil
        } catch let appError as AppError {
            if activeUserID == expectedUserID, session == expectedSession { messageErrorsByFeedbackID[item.id] = appError }
        } catch {
            if activeUserID == expectedUserID, session == expectedSession { messageErrorsByFeedbackID[item.id] = .unknown }
        }
    }

    func stopListeningMessages(for feedbackID: String) { listenerBag.remove("feedbackMessages:\(feedbackID)") }

    private func startListeningMyFeedback(userID: String) -> Bool {
        let expectedSession = session
        let key = "myFeedback:\(userID)"
        listenerBag.removeAll(except: key, matchingPrefix: "myFeedback:")
        guard let realtime = repository as? FeedbackRealtimeRepository else { return false }
        guard !listenerBag.contains(key) else { return true }
        listenerBag.set(realtime.listenMyFeedback(userID: userID) { [weak self] fresh in
            guard let self, self.activeUserID == userID, self.session == expectedSession else { return }
            self.mergeFeedback(fresh); self.isLoading = false; self.error = nil
        } onError: { [weak self] appError in
            guard let self, self.activeUserID == userID, self.session == expectedSession else { return }
            self.listenerBag.remove(key); self.error = appError
        }, for: key)
        return true
    }

    private func startListeningMessages(for item: FeedbackItem) -> Bool {
        let key = "feedbackMessages:\(item.id)"
        let expectedSession = session
        let expectedUserID = activeUserID
        guard expectedUserID != nil else { return false }
        guard let realtime = repository as? FeedbackRealtimeRepository else { return false }
        guard !listenerBag.contains(key) else { return true }
        listenerBag.set(realtime.listenFeedbackMessages(feedback: item) { [weak self] fresh in
            guard let self, self.activeUserID == expectedUserID, self.session == expectedSession else { return }
            self.mergeMessages(fresh, feedbackID: item.id); self.messageErrorsByFeedbackID[item.id] = nil
        } onError: { [weak self] appError in
            guard let self, self.activeUserID == expectedUserID, self.session == expectedSession else { return }
            self.listenerBag.remove(key); self.messageErrorsByFeedbackID[item.id] = appError
        }, for: key)
        return true
    }

    func sendMessage(_ text: String, feedback: FeedbackItem, user: AppUser) async -> Bool {
        let expectedSession = session
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard activeUserID == user.id, !text.isEmpty, text.count <= 2000, !feedback.status.isClosed else { actionError = .validationFailed; return false }
        guard !sendingMessageFeedbackIDs.contains(feedback.id) else { return false }
        sendingMessageFeedbackIDs.insert(feedback.id)
        defer { if session == expectedSession { sendingMessageFeedbackIDs.remove(feedback.id) } }
        let operation = pendingOperations.attempt(
            feedbackID: feedback.id,
            kind: .userMessage,
            text: text,
            actorID: user.id,
            actorDisplayName: user.preferredDisplayName
        )
        do {
            try await repository.performFeedbackOperation(operation)
            guard activeUserID == user.id, session == expectedSession else { return false }
            pendingOperations.complete(operation)
            await loadMessages(for: feedback); actionError = nil; return true
        } catch let appError as AppError {
            if activeUserID == user.id, session == expectedSession { setActionError(appError, for: feedback.id) }
        } catch {
            if activeUserID == user.id, session == expectedSession { setActionError(.unknown, for: feedback.id) }
        }
        return false
    }

    func clearActionError() { actionError = nil; actionErrorRecordID = nil }

    func submitDsaAppeal(reason: String, feedback: FeedbackItem, userID: String) async -> Bool {
        let expectedSession = session
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard activeUserID == userID, reason.count >= 20, reason.count <= 5_000 else { actionError = .validationFailed; return false }
        guard !sendingMessageFeedbackIDs.contains(feedback.id) else { return false }
        sendingMessageFeedbackIDs.insert(feedback.id)
        defer { if session == expectedSession { sendingMessageFeedbackIDs.remove(feedback.id) } }
        let attempt: (operationID: String, expectedRevision: String)
        let timestamp = Timestamp(date: feedback.updatedAt)
        let expectedRevision = feedback.revision ?? "\(timestamp.seconds):\(timestamp.nanoseconds)"
        if let existing = pendingDsaAppealAttempts[feedback.id], existing.expectedRevision == expectedRevision {
            attempt = existing
        } else {
            attempt = (operationID: UUID().uuidString, expectedRevision: expectedRevision)
            pendingDsaAppealAttempts[feedback.id] = attempt
        }
        do {
            try await repository.submitDsaAppeal(.init(
                reportId: feedback.id,
                reason: reason,
                operationId: attempt.operationID,
                expectedRevision: attempt.expectedRevision,
                revisionFormat: feedback.revision == nil ? nil : "exact", principalId: userID
            ))
            guard activeUserID == userID, session == expectedSession else { return false }
            pendingDsaAppealAttempts[feedback.id] = nil
            await refresh(userID: userID); return true
        } catch let appError as AppError {
            if activeUserID == userID, session == expectedSession { setActionError(appError, for: feedback.id) }
        } catch {
            if activeUserID == userID, session == expectedSession { setActionError(.unknown, for: feedback.id) }
        }
        return false
    }

    private func mergeFeedback(_ newItems: [FeedbackItem]) {
        var byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        newItems.forEach { byID[$0.id] = $0 }
        items = byID.values.sorted { $0.createdAt == $1.createdAt ? $0.id > $1.id : $0.createdAt > $1.createdAt }
    }

    private func mergeMessages(_ newItems: [FeedbackMessage], feedbackID: String) {
        messagesByFeedbackID[feedbackID] = FeedbackMessageHistory.merge(messagesByFeedbackID[feedbackID] ?? [], newItems)
    }
}
