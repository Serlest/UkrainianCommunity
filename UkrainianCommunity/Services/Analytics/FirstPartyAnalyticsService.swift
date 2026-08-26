import CryptoKit
import Foundation

#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

#if canImport(UIKit)
import UIKit
#endif

final class FirstPartyAnalyticsService: AnalyticsTracking {
    private struct PendingConsentWithdrawal: Codable {
        let principalBinding: String
        let consentID: String
    }

    #if canImport(FirebaseAuth)
    private nonisolated final class AuthStateHandleBox: @unchecked Sendable {
        let value: NSObjectProtocol

        init(_ value: NSObjectProtocol) {
            self.value = value
        }
    }
    #endif

    #if canImport(UIKit)
    private nonisolated final class NotificationHandleBox: @unchecked Sendable {
        let value: NSObjectProtocol

        init(_ value: NSObjectProtocol) {
            self.value = value
        }
    }
    #endif

    private struct AuthContext: Equatable {
        let principalID: String?
        let aggregationPrincipalID: String?

        static let signedOut = AuthContext(principalID: nil, aggregationPrincipalID: nil)
    }

    private let consentService: AnalyticsConsentProviding
    private var authContext: AuthContext
    private let pendingWithdrawalStorageKey = "analyticsPendingConsentWithdrawal.v1"
    private static let isDebugLoggingEnabled = false

    #if canImport(FirebaseAuth)
    private var authStateHandle: AuthStateHandleBox?
    #endif

    #if canImport(UIKit)
    private var foregroundObserver: NotificationHandleBox?
    #endif

    #if canImport(FirebaseFunctions)
    private let deliveryAuthorization: AnalyticsDeliveryAuthorization
    private let aggregateOutbox: AnalyticsAggregationOutbox
    private var deliverySession: AnalyticsDeliverySession
    #endif

    init(consentService: AnalyticsConsentProviding = AnalyticsConsentService()) {
        self.consentService = consentService

        #if canImport(FirebaseAuth)
        let initialAuthContext = Self.currentAuthContext()
        self.authContext = initialAuthContext
        self.authStateHandle = nil
        #else
        let initialAuthContext = AuthContext.signedOut
        self.authContext = initialAuthContext
        #endif
        #if canImport(UIKit)
        self.foregroundObserver = nil
        #endif

        let analyticsConsentID = Self.authorizedConsentID(
            for: initialAuthContext,
            consentService: consentService
        )
        let isAnalyticsEnabled = analyticsConsentID != nil

        #if canImport(FirebaseFunctions)
        let authorization = AnalyticsDeliveryAuthorization()
        let session = authorization.transition(
            principalID: initialAuthContext.aggregationPrincipalID,
            // Existing local opt-ins must be journaled server-side before any
            // queued aggregate is eligible for delivery.
            consentID: nil
        )
        self.deliveryAuthorization = authorization
        self.deliverySession = session
        self.aggregateOutbox = AnalyticsAggregationOutbox(
            delivery: FirebaseFunctionsAnalyticsAggregationDelivery(
                region: "europe-west3",
                authorization: authorization
            ),
            authorization: authorization
        )
        #endif

        Self.debugLog(
            "analytics consent loaded for current principal: \(isAnalyticsEnabled)"
        )
        synchronizeCurrentConsent()

        #if canImport(FirebaseAuth)
        authStateHandle = AuthStateHandleBox(
            Auth.auth().addStateDidChangeListener { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.refreshAuthContextIfNeeded()
                }
            }
        )
        #endif

        #if canImport(UIKit)
        foregroundObserver = NotificationHandleBox(
            NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.resumeAggregateDelivery()
                    self?.synchronizePendingWithdrawal()
                }
            }
        )
        #endif
    }

    deinit {
        #if canImport(FirebaseAuth)
        if let authStateHandle {
            Auth.auth().removeStateDidChangeListener(authStateHandle.value)
        }
        #endif
        #if canImport(UIKit)
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver.value)
        }
        #endif
    }

    var isCollectionAvailable: Bool {
        refreshAuthContextIfNeeded()
        return authContext.aggregationPrincipalID != nil
    }

    var isCollectionEnabled: Bool {
        refreshAuthContextIfNeeded()
        return authorizedConsentID(for: authContext) != nil
    }

    var collectionScopeID: String? {
        refreshAuthContextIfNeeded()
        #if canImport(FirebaseFunctions)
        guard deliveryAuthorization.allowsDelivery(for: deliverySession),
              let consentID = deliverySession.consentID else {
            return nil
        }
        return Self.collectionScopeID(
            consentID: consentID,
            deliveryGeneration: deliverySession.generation
        )
        #else
        return nil
        #endif
    }

    func actionCapture(for event: AppAnalyticsEvent) -> AnalyticsActionCapture? {
        refreshAuthContextIfNeeded()
        #if canImport(FirebaseFunctions)
        guard let uid = authContext.aggregationPrincipalID,
              let consentID = deliverySession.consentID,
              deliveryAuthorization.allowsDelivery(for: deliverySession),
              Self.isImmutableActionEvent(event.name),
              let contentID = event.parameters[.contentID]?.stringValue else {
            return nil
        }
        let proofID = UUID().uuidString.lowercased()
        return AnalyticsActionCapture(
            proofID: proofID,
            eventName: event.name.rawValue,
            contentID: contentID,
            actorBinding: Self.digest(parts: ["actor", uid, proofID]),
            sessionBinding: Self.digest(parts: ["session", consentID, proofID])
        )
        #else
        return nil
        #endif
    }

    func track(_ event: AppAnalyticsEvent, actionCapture: AnalyticsActionCapture?) {
        refreshAuthContextIfNeeded()
        Self.debugLog("track(event) called: \(event.name.rawValue)")
        guard authorizedConsentID(for: authContext) != nil else {
            Self.debugLog("event skipped due to consent: \(event.name.rawValue)")
            return
        }

        trackAggregateEventIfNeeded(event, actionCapture: actionCapture)
    }

    func setCollectionEnabled(_ isEnabled: Bool) {
        refreshAuthContextIfNeeded()
        let principalID = authContext.principalID
        let canCollect = authContext.aggregationPrincipalID != nil
        let previousConsentID = authorizedConsentID(for: authContext)
        consentService.setAnalyticsEnabled(isEnabled && canCollect, for: principalID)
        let analyticsConsentID = authorizedConsentID(for: authContext)
        Self.debugLog("analytics consent saved for current principal: \(analyticsConsentID != nil)")
        // Consent delivery is fail-closed: collection starts only after the
        // server journal confirms the exact consent generation.
        transitionAggregateDelivery(analyticsConsentID: nil)
        if let analyticsConsentID {
            synchronizeConsent(enabled: true, consentID: analyticsConsentID)
        } else if let previousConsentID, let principalID {
            persistPendingWithdrawal(principalID: principalID, consentID: previousConsentID)
            synchronizeConsent(enabled: false, consentID: previousConsentID)
        }
    }

    private func refreshAuthContextIfNeeded() {
        #if canImport(FirebaseAuth)
        let latestContext = Self.currentAuthContext()
        guard latestContext != authContext else { return }

        authContext = latestContext
        // Always close the delivery fence across auth changes. The new
        // principal's local opt-in is revalidated with the server below.
        transitionAggregateDelivery(analyticsConsentID: nil)
        synchronizeCurrentConsent()
        #endif
    }

    private func transitionAggregateDelivery(analyticsConsentID: String?) {
        #if canImport(FirebaseFunctions)
        let session = deliveryAuthorization.transition(
            principalID: authContext.aggregationPrincipalID,
            consentID: analyticsConsentID
        )
        deliverySession = session
        Task(priority: .utility) { [aggregateOutbox] in
            await aggregateOutbox.transition(to: session)
        }
        #endif
    }

    private func resumeAggregateDelivery() {
        refreshAuthContextIfNeeded()
        #if canImport(FirebaseFunctions)
        let session = deliverySession
        Task(priority: .utility) { [aggregateOutbox] in
            await aggregateOutbox.transition(to: session)
        }
        #endif
    }

    private func authorizedConsentID(for context: AuthContext) -> String? {
        Self.authorizedConsentID(for: context, consentService: consentService)
    }

    private static func authorizedConsentID(
        for context: AuthContext,
        consentService: AnalyticsConsentProviding
    ) -> String? {
        guard context.aggregationPrincipalID != nil else { return nil }
        return consentService.analyticsConsentID(for: context.principalID)
    }

    private func trackAggregateEventIfNeeded(
        _ event: AppAnalyticsEvent,
        actionCapture: AnalyticsActionCapture?
    ) {
        guard shouldForwardToAggregation(event.name) else {
            Self.debugLog("callable trackAnalyticsEvent not sent for event: \(event.name.rawValue)")
            return
        }

        #if canImport(FirebaseFunctions)
        let session = deliverySession
        guard deliveryAuthorization.allowsDelivery(for: session),
              let consentID = session.consentID,
              let request = AnalyticsAggregationRequest(
                event: event,
                consentID: consentID,
                actionProof: actionCapture
              ) else {
            Self.debugLog("callable trackAnalyticsEvent skipped without an authorized delivery session")
            return
        }
        Self.debugLog("callable trackAnalyticsEvent queued: \(event.name.rawValue)")
        Task(priority: .utility) { [aggregateOutbox] in
            await aggregateOutbox.enqueue(request, session: session)
        }
        #else
        Self.debugLog("FirebaseFunctions unavailable; callable trackAnalyticsEvent not sent: \(event.name.rawValue)")
        #endif
    }

    private func synchronizeCurrentConsent() {
        synchronizePendingWithdrawal()
        guard let consentID = authorizedConsentID(for: authContext) else { return }
        synchronizeConsent(enabled: true, consentID: consentID)
    }

    private func synchronizeConsent(enabled: Bool, consentID: String) {
        #if canImport(FirebaseFunctions)
        guard let principalID = authContext.principalID else { return }
        let principalBinding = Self.principalBinding(principalID)
        // Registration consent may be synchronized only after email verification.
        // Record the language of the original disclosure, not a later UI language.
        let locale = consentService.analyticsConsentLocale(for: principalID)
            ?? LocalizationStore.language.rawValue
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await Functions.functions(region: "europe-west3")
                    .httpsCallable("updateAnalyticsConsent")
                    .call([
                        "enabled": enabled,
                        "consentID": consentID,
                        "locale": locale,
                        "appVersion": appVersion ?? "unknown"
                    ])
                guard self.authContext.principalID.map(Self.principalBinding) == principalBinding else {
                    return
                }
                if enabled,
                   self.authorizedConsentID(for: self.authContext) == consentID {
                    self.transitionAggregateDelivery(analyticsConsentID: consentID)
                } else if !enabled {
                    self.clearPendingWithdrawal(principalBinding: principalBinding, consentID: consentID)
                }
            } catch {
                guard enabled,
                      self.authContext.principalID.map(Self.principalBinding) == principalBinding,
                      self.authorizedConsentID(for: self.authContext) == consentID else { return }
                self.consentService.setAnalyticsEnabled(false, for: self.authContext.principalID)
                self.transitionAggregateDelivery(analyticsConsentID: nil)
            }
        }
        #endif
    }

    private func synchronizePendingWithdrawal() {
        guard let principalID = authContext.principalID,
              let pending = pendingWithdrawal(),
              pending.principalBinding == Self.principalBinding(principalID) else { return }
        synchronizeConsent(enabled: false, consentID: pending.consentID)
    }

    private func persistPendingWithdrawal(principalID: String, consentID: String) {
        let pending = PendingConsentWithdrawal(
            principalBinding: Self.principalBinding(principalID),
            consentID: consentID
        )
        guard let data = try? JSONEncoder().encode(pending) else { return }
        UserDefaults.standard.set(data, forKey: pendingWithdrawalStorageKey)
    }

    private func pendingWithdrawal() -> PendingConsentWithdrawal? {
        guard let data = UserDefaults.standard.data(forKey: pendingWithdrawalStorageKey) else {
            return nil
        }
        return try? JSONDecoder().decode(PendingConsentWithdrawal.self, from: data)
    }

    private func clearPendingWithdrawal(principalBinding: String, consentID: String) {
        guard let pending = pendingWithdrawal(),
              pending.principalBinding == principalBinding,
              pending.consentID == consentID else { return }
        UserDefaults.standard.removeObject(forKey: pendingWithdrawalStorageKey)
    }

    private func shouldForwardToAggregation(_ eventName: AnalyticsEventName) -> Bool {
        switch eventName {
        case .newsView,
             .newsLike,
             .newsBookmark,
             .eventView,
             .eventRegister,
             .eventBookmark,
             .organizationView,
             .organizationFollow,
             .organizationBookmark:
            true
        case .eventCancelRegistration,
             .organizationUnfollow,
             .searchUsed,
             .filterUsed,
             .languageChanged,
             .themeChanged,
             .analyticsConsentChanged:
            false
        }
    }

    #if canImport(FirebaseAuth)
    private static func currentAuthContext() -> AuthContext {
        guard let user = Auth.auth().currentUser else { return .signedOut }
        let aggregationPrincipalID = !user.isAnonymous && user.isEmailVerified
            ? user.uid
            : nil
        return AuthContext(
            principalID: user.uid,
            aggregationPrincipalID: aggregationPrincipalID
        )
    }
    #endif

    private static func debugLog(_ message: String) {
        #if DEBUG
        guard isDebugLoggingEnabled else { return }
        debugPrint("[Analytics] \(message)")
        #endif
    }

    private static func collectionScopeID(
        consentID: String,
        deliveryGeneration: UInt64
    ) -> String {
        let material = "analytics-view-scope:\(consentID):\(deliveryGeneration)"
        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func isImmutableActionEvent(_ eventName: AnalyticsEventName) -> Bool {
        switch eventName {
        case .newsLike, .newsBookmark, .eventRegister, .eventBookmark,
             .organizationFollow, .organizationBookmark:
            true
        default:
            false
        }
    }

    private static func principalBinding(_ principalID: String) -> String {
        digest(parts: ["principal", principalID])
    }

    private static func digest(parts: [String]) -> String {
        let digest = SHA256.hash(data: Data(parts.joined(separator: "\0").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

nonisolated struct AnalyticsAggregationRequest: Codable, Equatable, Sendable {
    let name: String
    let parameters: [String: String]
    let consentID: String
    let actionProof: AnalyticsActionCapture?
    let occurredAtMilliseconds: Int64?

    init?(
        event: AppAnalyticsEvent,
        consentID: String,
        actionProof: AnalyticsActionCapture? = nil,
        occurredAt: Date = Date()
    ) {
        let parameters = event.parameters.reduce(into: [String: String]()) { result, item in
            guard Self.allowedParameterNames.contains(item.key),
                  let value = item.value.stringValue else {
                return
            }

            result[item.key.rawValue] = value
        }

        guard parameters[AnalyticsParameterName.contentID.rawValue] != nil else {
            return nil
        }

        self.name = event.name.rawValue
        self.parameters = parameters
        self.consentID = consentID
        self.actionProof = actionProof
        self.occurredAtMilliseconds = Int64(occurredAt.timeIntervalSince1970 * 1_000)
    }

    // The callable resolves all display metadata from Firestore. Keeping only
    // the stable identifier minimizes both the on-device outbox and payload.
    private static let allowedParameterNames: Set<AnalyticsParameterName> = [
        .contentID
    ]
}

nonisolated struct AnalyticsAggregationResponse: Codable, Equatable, Sendable {
    let tracked: Bool
}

private extension AnalyticsParameterValue {
    nonisolated var stringValue: String? {
        switch self {
        case .string(let value):
            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedValue.isEmpty ? nil : trimmedValue
        case .int(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        }
    }
}
