import Foundation

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

protocol AnalyticsTracking {
    /// Principal-scoped preflight for callers that reserve a view deduplication key.
    var isCollectionAvailable: Bool { get }
    var isCollectionEnabled: Bool { get }
    /// Opaque identifier for the currently authorized opt-in generation.
    /// It changes across opt-out/re-opt-in and never contains a principal ID.
    var collectionScopeID: String? { get }
    /// Includes an initial signal and later authorization changes. A visible
    /// detail can retry after consent sync without collecting before consent.
    func collectionChanges() -> AsyncStream<Void>
    /// Emits only when the consent API permanently rejects the current local
    /// opt-in. Auth changes, external opt-out and transient failures stay silent.
    func consentFailures() -> AsyncStream<AnalyticsConsentFailure>
    func isCurrentConsentFailure(_ failure: AnalyticsConsentFailure) -> Bool
    func actionCapture(for event: AppAnalyticsEvent) -> AnalyticsActionCapture?
    func track(_ event: AppAnalyticsEvent)
    func track(_ event: AppAnalyticsEvent, actionCapture: AnalyticsActionCapture?)
    func setCollectionEnabled(_ isEnabled: Bool)
}

extension AnalyticsTracking {
    func collectionChanges() -> AsyncStream<Void> {
        AsyncStream { continuation in
            continuation.yield(())
            continuation.finish()
        }
    }

    func consentFailures() -> AsyncStream<AnalyticsConsentFailure> {
        AsyncStream { $0.finish() }
    }

    func isCurrentConsentFailure(_ failure: AnalyticsConsentFailure) -> Bool { false }

    func observeVisibleView(_ track: () -> Void) async {
        for await _ in collectionChanges() {
            guard !Task.isCancelled else { return }
            track()
        }
    }

    func track(_ event: AppAnalyticsEvent) {
        track(event, actionCapture: nil)
    }
}

struct AnalyticsConsentFailure: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case permanentRejection
    }

    let kind: Kind
    let principalBinding: String
    let consentID: String
}

@MainActor
final class AnalyticsCollectionChanges {
    private var observers: [UUID: AsyncStream<Void>.Continuation] = [:]

    func stream() -> AsyncStream<Void> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            observers[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in self?.observers.removeValue(forKey: id) }
            }
            continuation.yield(())
        }
    }

    func notify() {
        for observer in observers.values { observer.yield(()) }
    }
}

@MainActor
final class AnalyticsConsentFailures {
    private var observers: [UUID: AsyncStream<AnalyticsConsentFailure>.Continuation] = [:]

    func stream() -> AsyncStream<AnalyticsConsentFailure> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            observers[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in self?.observers.removeValue(forKey: id) }
            }
        }
    }

    func notify(_ failure: AnalyticsConsentFailure) {
        for observer in observers.values { observer.yield(failure) }
    }
}

nonisolated struct AnalyticsActionCapture: Codable, Equatable, Sendable {
    let proofID: String
    let eventName: String
    let contentID: String
    let actorBinding: String
    let sessionBinding: String

    #if canImport(FirebaseFirestore)
    var firestoreData: [String: Any] {
        [
            "proofId": proofID,
            "eventName": eventName,
            "contentId": contentID,
            "actorBinding": actorBinding,
            "sessionBinding": sessionBinding,
            "createdAt": FieldValue.serverTimestamp(),
            "expiresAt": Timestamp(date: Date().addingTimeInterval(48 * 60 * 60))
        ]
    }
    #endif
}
