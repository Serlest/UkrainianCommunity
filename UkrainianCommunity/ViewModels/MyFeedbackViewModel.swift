import Combine
import Foundation

@MainActor
final class MyFeedbackViewModel: ObservableObject {
    @Published private(set) var items: [FeedbackItem] = []
    @Published private(set) var messagesByFeedbackID: [String: [FeedbackMessage]] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var loadingMessageFeedbackIDs = Set<String>()
    @Published private(set) var sendingMessageFeedbackIDs = Set<String>()
    @Published private(set) var isClearing = false
    @Published private(set) var error: AppError?
    @Published private(set) var actionError: AppError?

    private let repository: FeedbackRepository
    private let listenerBag = RealtimeListenerBag()
    private var loadedUserID: String?

    init(repository: FeedbackRepository) {
        self.repository = repository
    }

    func loadIfNeeded(userID: String) async {
        if startListeningMyFeedback(userID: userID) {
            if loadedUserID != userID && items.isEmpty {
                isLoading = true
            }
            return
        }
        guard loadedUserID != userID || items.isEmpty else { return }
        await refresh(userID: userID)
    }

    func refresh(userID: String) async {
        _ = startListeningMyFeedback(userID: userID)
        isLoading = true
        error = nil
        defer {
            isLoading = false
            loadedUserID = userID
        }

        await fetchMyFeedbackOnce(userID: userID)
    }

    private func fetchMyFeedbackOnce(userID: String) async {
        do {
            items = try await repository.fetchFeedback(userID: userID)
            loadedUserID = userID
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    func reset() {
        items = []
        messagesByFeedbackID = [:]
        isLoading = false
        loadingMessageFeedbackIDs = []
        sendingMessageFeedbackIDs = []
        isClearing = false
        listenerBag.removeAll()
        error = nil
        actionError = nil
        loadedUserID = nil
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
            actionError = nil
        } catch let appError as AppError {
            actionError = appError
        } catch {
            actionError = .unknown
        }
    }

    func stopListeningMessages(for feedbackID: String) {
        listenerBag.remove("feedbackMessages:\(feedbackID)")
    }

    private func startListeningMyFeedback(userID: String) -> Bool {
        let key = "myFeedback:\(userID)"
        listenerBag.removeAll(except: key, matchingPrefix: "myFeedback:")
        guard let realtimeRepository = repository as? FeedbackRealtimeRepository else { return false }
        guard !listenerBag.contains(key) else { return true }

        listenerBag.set(realtimeRepository.listenMyFeedback(userID: userID) { [weak self] items in
            self?.items = items
            self?.loadedUserID = userID
            self?.isLoading = false
            self?.error = nil
        } onError: { [weak self] appError in
            self?.listenerBag.remove(key)
            self?.isLoading = false
            self?.error = appError
            Task { await self?.fetchMyFeedbackOnce(userID: userID) }
            #if DEBUG
            print("Realtime listener failed: purpose=myFeedback key=\(key) error=\(appError)")
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
            self?.actionError = nil
        } onError: { [weak self] appError in
            self?.listenerBag.remove(key)
            self?.loadingMessageFeedbackIDs.remove(item.id)
            self?.actionError = appError
            Task { await self?.fetchMessagesOnce(for: item) }
            #if DEBUG
            print("Realtime listener failed: purpose=feedbackMessages key=\(key) error=\(appError)")
            #endif
        }, for: key)
        loadingMessageFeedbackIDs.insert(item.id)
        return true
    }

    func sendMessage(_ text: String, feedback: FeedbackItem, user: AppUser) async -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, trimmedText.count <= 2000, !feedback.status.isClosed else {
            actionError = .validationFailed
            return false
        }

        guard !sendingMessageFeedbackIDs.contains(feedback.id) else { return false }
        sendingMessageFeedbackIDs.insert(feedback.id)
        defer { sendingMessageFeedbackIDs.remove(feedback.id) }

        do {
            try await repository.sendUserFeedbackMessage(feedback: feedback, text: trimmedText, user: user)
            if repository is FeedbackRealtimeRepository {
                _ = startListeningMyFeedback(userID: user.id)
            } else {
                await refresh(userID: user.id)
            }
            let itemForMessages = items.first(where: { $0.id == feedback.id }) ?? feedback
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

    func clearActionError() {
        actionError = nil
    }

    @discardableResult
    func clearMyFeedback() async -> Bool {
        guard !isClearing else { return false }
        isClearing = true
        actionError = nil
        defer { isClearing = false }

        do {
            try await repository.clearMyFeedback()
            items = []
            messagesByFeedbackID = [:]
            listenerBag.removeAll()
            error = nil
            return true
        } catch let appError as AppError {
            actionError = appError
        } catch {
            actionError = .unknown
        }
        return false
    }
}
