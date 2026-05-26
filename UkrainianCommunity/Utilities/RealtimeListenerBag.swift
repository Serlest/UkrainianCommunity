import Foundation
import FirebaseFirestore

protocol AppRealtimeListener {
    func cancel()
}

final class FirebaseRealtimeListener: AppRealtimeListener {
    private var registration: ListenerRegistration?

    init(_ registration: ListenerRegistration) {
        self.registration = registration
    }

    func cancel() {
        registration?.remove()
        registration = nil
    }

    deinit {
        cancel()
    }
}

@MainActor
final class RealtimeListenerBag {
    private var listeners: [String: AppRealtimeListener] = [:]

    func set(_ listener: AppRealtimeListener, for key: String) {
        listeners[key]?.cancel()
        listeners[key] = listener
    }

    func remove(_ key: String) {
        listeners[key]?.cancel()
        listeners[key] = nil
    }

    func removeAll() {
        listeners.values.forEach { $0.cancel() }
        listeners.removeAll()
    }

    func removeAll(matchingPrefix prefix: String) {
        for key in Array(listeners.keys) where key.hasPrefix(prefix) {
            remove(key)
        }
    }

    func removeAll(except preservedKey: String, matchingPrefix prefix: String) {
        for key in Array(listeners.keys) where key.hasPrefix(prefix) && key != preservedKey {
            remove(key)
        }
    }

    func contains(_ key: String) -> Bool {
        listeners[key] != nil
    }

    deinit {
        MainActor.assumeIsolated {
            removeAll()
        }
    }

}

protocol FeedbackRealtimeRepository {
    func listenMyFeedback(
        userID: String,
        onChange: @escaping @MainActor ([FeedbackItem]) -> Void,
        onError: @escaping @MainActor (AppError) -> Void
    ) -> AppRealtimeListener

    func listenOwnerFeedbackInbox(
        onChange: @escaping @MainActor ([FeedbackItem]) -> Void,
        onError: @escaping @MainActor (AppError) -> Void
    ) -> AppRealtimeListener

    func listenFeedbackMessages(
        feedback: FeedbackItem,
        onChange: @escaping @MainActor ([FeedbackMessage]) -> Void,
        onError: @escaping @MainActor (AppError) -> Void
    ) -> AppRealtimeListener
}

protocol NewsRealtimeRepository {
    func listenNewsComments(
        newsID: String,
        onChange: @escaping @MainActor ([Comment]) -> Void,
        onError: @escaping @MainActor (AppError) -> Void
    ) -> AppRealtimeListener
}

protocol EventRealtimeRepository {
    func listenEventComments(
        eventID: String,
        onChange: @escaping @MainActor ([Comment]) -> Void,
        onError: @escaping @MainActor (AppError) -> Void
    ) -> AppRealtimeListener
}

protocol OrganizationRealtimeRepository {
    func listenOrganizationComments(
        organizationID: String,
        onChange: @escaping @MainActor ([Comment]) -> Void,
        onError: @escaping @MainActor (AppError) -> Void
    ) -> AppRealtimeListener

    func listenSubmittedOrganizationRequests(
        userID: String,
        onChange: @escaping @MainActor ([Organization]) -> Void,
        onError: @escaping @MainActor (AppError) -> Void
    ) -> AppRealtimeListener

    func listenPendingOrganizationRequestsForOwner(
        onChange: @escaping @MainActor ([Organization]) -> Void,
        onError: @escaping @MainActor (AppError) -> Void
    ) -> AppRealtimeListener
}
