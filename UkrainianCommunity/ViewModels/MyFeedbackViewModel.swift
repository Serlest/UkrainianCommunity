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

    private static let feedbackPageSize = 50
    private static let messagePageSize = 100
    private let repository: FeedbackRepository
    private let listenerBag = RealtimeListenerBag()
    private var nextCursor: FeedbackPageCursor?
    private var messageCursors: [String: FeedbackPageCursor] = [:]
    private var moreMessages: [String: Bool] = [:]
    private var pendingOperations = PendingFeedbackOperationBuffer()
    private var pendingDsaAppealAttempts: [String: (operationID: String, expectedRevision: String)] = [:]
    private var activeUserID: String?

    init(repository: FeedbackRepository) { self.repository = repository }

    func loadIfNeeded(userID: String) async {
        if activeUserID != userID { reset(for: userID) }
        guard items.isEmpty else { _ = startListeningMyFeedback(userID: userID); return }
        await refresh(userID: userID)
    }

    func refresh(userID: String) async {
        if activeUserID != userID { reset(for: userID) }
        isLoading = true
        error = nil
        do {
            let page = try await RefreshRequest.run { [self] in
                try await repository.fetchFeedbackPage(userID: userID, after: nil, limit: Self.feedbackPageSize)
            }
            guard activeUserID == userID else { return }
            items = page.items
            nextCursor = page.nextCursor
            hasMore = page.hasMore
            _ = startListeningMyFeedback(userID: userID)
        } catch let appError as AppError {
            if activeUserID == userID { error = appError }
        } catch {
            if activeUserID == userID { self.error = .unknown }
        }
        if activeUserID == userID { isLoading = false }
    }

    func loadMore(userID: String) async {
        guard activeUserID == userID, hasMore, !isLoadingMore, let cursor = nextCursor else { return }
        isLoadingMore = true
        defer { if activeUserID == userID { isLoadingMore = false } }
        do {
            let page = try await repository.fetchFeedbackPage(userID: userID, after: cursor, limit: Self.feedbackPageSize)
            guard activeUserID == userID else { return }
            mergeFeedback(page.items)
            nextCursor = page.nextCursor
            hasMore = page.hasMore
            error = nil
        } catch let appError as AppError {
            if activeUserID == userID { error = appError }
        } catch {
            if activeUserID == userID { self.error = .unknown }
        }
    }

    func feedback(id: String, userID: String) async -> FeedbackItem? {
        guard activeUserID == userID else { return nil }
        if let item = items.first(where: { $0.id == id }) { return item }
        do {
            let item = try await repository.fetchFeedback(id: id)
            guard activeUserID == userID, item.userId == userID else { return nil }
            mergeFeedback([item])
            return item
        } catch let appError as AppError {
            if activeUserID == userID { error = appError }
        } catch {
            if activeUserID == userID { self.error = .unknown }
        }
        return nil
    }

    func acknowledgeRead(_ item: FeedbackItem, userID: String) async {
        guard activeUserID == userID, item.userId == userID, item.unreadForUser else { return }
        do {
            try await repository.acknowledgeFeedbackReadByUser(id: item.id, userID: userID)
            let updated = try await repository.fetchFeedback(id: item.id)
            if activeUserID == userID { mergeFeedback([updated]) }
        } catch let appError as AppError {
            if activeUserID == userID { actionError = appError }
        } catch {
            if activeUserID == userID { actionError = .unknown }
        }
    }

    func reset() { reset(for: nil) }

    private func reset(for userID: String?) {
        listenerBag.removeAll()
        items = []; messagesByFeedbackID = [:]; messageErrorsByFeedbackID = [:]
        loadingMessageFeedbackIDs = []; loadingMoreMessageFeedbackIDs = []; sendingMessageFeedbackIDs = []
        isLoading = false; isLoadingMore = false; hasMore = false; nextCursor = nil
        messageCursors = [:]; moreMessages = [:]; error = nil; actionError = nil
        pendingOperations.removeAll()
        pendingDsaAppealAttempts.removeAll()
        activeUserID = userID
    }

    func messages(for item: FeedbackItem) -> [FeedbackMessage] { messagesByFeedbackID[item.id] ?? item.legacyMessages }
    func hasMoreMessages(for feedbackID: String) -> Bool { moreMessages[feedbackID] ?? false }

    func loadMessages(for item: FeedbackItem) async {
        let expectedUserID = activeUserID
        guard expectedUserID != nil else { return }
        guard !loadingMessageFeedbackIDs.contains(item.id) else { return }
        loadingMessageFeedbackIDs.insert(item.id)
        messageErrorsByFeedbackID[item.id] = nil
        defer { loadingMessageFeedbackIDs.remove(item.id) }
        do {
            let page = try await repository.fetchFeedbackMessagesPage(feedback: item, after: nil, limit: Self.messagePageSize)
            guard activeUserID == expectedUserID else { return }
            mergeMessages(item.legacyMessages + page.items, feedbackID: item.id)
            messageCursors[item.id] = page.nextCursor
            moreMessages[item.id] = page.hasMore
            _ = startListeningMessages(for: item)
        } catch let appError as AppError {
            if activeUserID == expectedUserID { messageErrorsByFeedbackID[item.id] = appError }
        } catch {
            if activeUserID == expectedUserID { messageErrorsByFeedbackID[item.id] = .unknown }
        }
    }

    func loadMoreMessages(for item: FeedbackItem) async {
        let expectedUserID = activeUserID
        guard expectedUserID != nil else { return }
        guard hasMoreMessages(for: item.id), !loadingMoreMessageFeedbackIDs.contains(item.id), let cursor = messageCursors[item.id] else { return }
        loadingMoreMessageFeedbackIDs.insert(item.id)
        defer { loadingMoreMessageFeedbackIDs.remove(item.id) }
        do {
            let page = try await repository.fetchFeedbackMessagesPage(feedback: item, after: cursor, limit: Self.messagePageSize)
            guard activeUserID == expectedUserID else { return }
            mergeMessages(page.items, feedbackID: item.id)
            messageCursors[item.id] = page.nextCursor
            moreMessages[item.id] = page.hasMore
            messageErrorsByFeedbackID[item.id] = nil
        } catch let appError as AppError {
            if activeUserID == expectedUserID { messageErrorsByFeedbackID[item.id] = appError }
        } catch {
            if activeUserID == expectedUserID { messageErrorsByFeedbackID[item.id] = .unknown }
        }
    }

    func stopListeningMessages(for feedbackID: String) { listenerBag.remove("feedbackMessages:\(feedbackID)") }

    private func startListeningMyFeedback(userID: String) -> Bool {
        let key = "myFeedback:\(userID)"
        listenerBag.removeAll(except: key, matchingPrefix: "myFeedback:")
        guard let realtime = repository as? FeedbackRealtimeRepository else { return false }
        guard !listenerBag.contains(key) else { return true }
        listenerBag.set(realtime.listenMyFeedback(userID: userID) { [weak self] fresh in
            guard let self, self.activeUserID == userID else { return }
            self.mergeFeedback(fresh); self.isLoading = false; self.error = nil
        } onError: { [weak self] appError in
            guard let self, self.activeUserID == userID else { return }
            self.listenerBag.remove(key); self.error = appError
        }, for: key)
        return true
    }

    private func startListeningMessages(for item: FeedbackItem) -> Bool {
        let key = "feedbackMessages:\(item.id)"
        let expectedUserID = activeUserID
        guard expectedUserID != nil else { return false }
        guard let realtime = repository as? FeedbackRealtimeRepository else { return false }
        guard !listenerBag.contains(key) else { return true }
        listenerBag.set(realtime.listenFeedbackMessages(feedback: item) { [weak self] fresh in
            guard let self, self.activeUserID == expectedUserID else { return }
            self.mergeMessages(fresh, feedbackID: item.id); self.messageErrorsByFeedbackID[item.id] = nil
        } onError: { [weak self] appError in
            guard let self, self.activeUserID == expectedUserID else { return }
            self.listenerBag.remove(key); self.messageErrorsByFeedbackID[item.id] = appError
        }, for: key)
        return true
    }

    func sendMessage(_ text: String, feedback: FeedbackItem, user: AppUser) async -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard activeUserID == user.id, !text.isEmpty, text.count <= 2000, !feedback.status.isClosed else { actionError = .validationFailed; return false }
        guard !sendingMessageFeedbackIDs.contains(feedback.id) else { return false }
        sendingMessageFeedbackIDs.insert(feedback.id)
        defer { sendingMessageFeedbackIDs.remove(feedback.id) }
        let operation = pendingOperations.attempt(
            feedbackID: feedback.id,
            kind: .userMessage,
            text: text,
            actorID: user.id,
            actorDisplayName: user.preferredDisplayName
        )
        do {
            try await repository.performFeedbackOperation(operation)
            pendingOperations.complete(operation)
            guard activeUserID == user.id else { return false }
            await loadMessages(for: feedback); actionError = nil; return true
        } catch let appError as AppError {
            if activeUserID == user.id { actionError = appError }
        } catch {
            if activeUserID == user.id { actionError = .unknown }
        }
        return false
    }

    func clearActionError() { actionError = nil }

    func submitDsaAppeal(reason: String, feedback: FeedbackItem, userID: String) async -> Bool {
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard activeUserID == userID, reason.count >= 20, reason.count <= 5_000 else { actionError = .validationFailed; return false }
        guard !sendingMessageFeedbackIDs.contains(feedback.id) else { return false }
        sendingMessageFeedbackIDs.insert(feedback.id)
        defer { sendingMessageFeedbackIDs.remove(feedback.id) }
        let attempt: (operationID: String, expectedRevision: String)
        let timestamp = Timestamp(date: feedback.updatedAt)
        let expectedRevision = "\(timestamp.seconds):\(timestamp.nanoseconds)"
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
                expectedRevision: attempt.expectedRevision
            ))
            pendingDsaAppealAttempts[feedback.id] = nil
            guard activeUserID == userID else { return false }
            await refresh(userID: userID); return true
        } catch let appError as AppError {
            if activeUserID == userID { actionError = appError }
        } catch {
            if activeUserID == userID { actionError = .unknown }
        }
        return false
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
