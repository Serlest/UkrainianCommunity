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
    func actionCapture(for event: AppAnalyticsEvent) -> AnalyticsActionCapture?
    func track(_ event: AppAnalyticsEvent)
    func track(_ event: AppAnalyticsEvent, actionCapture: AnalyticsActionCapture?)
    func setCollectionEnabled(_ isEnabled: Bool)
}

extension AnalyticsTracking {
    func track(_ event: AppAnalyticsEvent) {
        track(event, actionCapture: nil)
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
