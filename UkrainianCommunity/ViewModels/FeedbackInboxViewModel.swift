import Combine
import Foundation

@MainActor
final class FeedbackInboxViewModel: ObservableObject {
    @Published private(set) var items: [FeedbackItem] = []
    @Published private(set) var messagesByFeedbackID: [String: [FeedbackMessage]] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var loadingMessageFeedbackIDs = Set<String>()
    @Published private(set) var error: AppError?
    @Published private(set) var actionError: AppError?
    @Published private(set) var updatingFeedbackIDs = Set<String>()
    @Published private(set) var deletingFeedbackIDs = Set<String>()
    @Published private(set) var isClearingInbox = false

    private let repository: FeedbackRepository
    private let notificationInboxRepository: NotificationInboxRepository?
    private let listenerBag = RealtimeListenerBag()
    private var hasLoaded = false

    init(
        repository: FeedbackRepository,
        notificationInboxRepository: NotificationInboxRepository? = nil
    ) {
        self.repository = repository
        self.notificationInboxRepository = notificationInboxRepository
    }

    func loadIfNeeded() async {
        if startListeningInbox() {
            if !hasLoaded && items.isEmpty {
                isLoading = true
            }
            return
        }
        guard !hasLoaded else { return }
        await refresh()
    }

    func refresh() async {
        _ = startListeningInbox()
        isLoading = true
        error = nil
        defer {
            isLoading = false
            hasLoaded = true
        }

        await fetchInboxOnce()
    }

    private func fetchInboxOnce() async {
        do {
            items = try await repository.fetchFeedback()
            hasLoaded = true
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    func markReviewed(_ item: FeedbackItem) async {
        await update(item, status: .answered)
    }

    func archive(_ item: FeedbackItem) async {
        await close(item)
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
            try await repository.clearFeedbackInbox()
            items = []
            messagesByFeedbackID = [:]
            listenerBag.removeAll()
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

        guard !updatingFeedbackIDs.contains(item.id) else { return false }
        updatingFeedbackIDs.insert(item.id)
        actionError = nil
        defer { updatingFeedbackIDs.remove(item.id) }

        do {
            try await repository.sendOwnerFeedbackReply(feedback: item, text: trimmedReply, owner: owner)
            if repository is FeedbackRealtimeRepository {
                _ = startListeningInbox()
            } else {
                await refresh()
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
        do {
            try await repository.decideDsaCase(request)
            await refresh()
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
        do {
            try await repository.decideDsaAppeal(request)
            await refresh()
            return true
        } catch let appError as AppError {
            actionError = appError
        } catch {
            actionError = .unknown
        }
        return false
    }

    @discardableResult
    func close(_ item: FeedbackItem) async -> Bool {
        guard !updatingFeedbackIDs.contains(item.id) else { return false }
        updatingFeedbackIDs.insert(item.id)
        actionError = nil
        defer { updatingFeedbackIDs.remove(item.id) }

        do {
            try await repository.closeFeedback(id: item.id)
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

    func loadMessages(for item: FeedbackItem) async {
        if startListeningMessages(for: item) {
            return
        }
        guard !loadingMessageFeedbackIDs.contains(item.id) else { return }
        loadingMessageFeedbackIDs.insert(item.id)
        defer { loadingMessageFeedbackIDs.remove(item.id) }

        await fetchMessagesOnce(for: item)
    }

    private func fetchMessagesOnce(for item: FeedbackItem) async {
        do {
            messagesByFeedbackID[item.id] = try await repository.fetchFeedbackMessages(feedback: item)
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
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
            self?.items = items
            self?.hasLoaded = true
            self?.isLoading = false
            self?.error = nil
        } onError: { [weak self] appError in
            self?.listenerBag.remove(key)
            self?.isLoading = false
            self?.error = appError
            Task { await self?.fetchInboxOnce() }
            #if DEBUG
            print("Realtime listener failed: purpose=feedbackInbox key=\(key) error=\(appError)")
            #endif
        }, for: key)
        return true
    }

    private func startListeningMessages(for item: FeedbackItem) -> Bool {
        let key = "feedbackMessages:\(item.id)"
        guard let realtimeRepository = repository as? FeedbackRealtimeRepository else { return false }
        guard !listenerBag.contains(key) else { return true }

        listenerBag.set(realtimeRepository.listenFeedbackMessages(feedback: item) { [weak self] messages in
            self?.messagesByFeedbackID[item.id] = messages
            self?.loadingMessageFeedbackIDs.remove(item.id)
            self?.error = nil
        } onError: { [weak self] appError in
            self?.listenerBag.remove(key)
            self?.loadingMessageFeedbackIDs.remove(item.id)
            self?.error = appError
            Task { await self?.fetchMessagesOnce(for: item) }
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
