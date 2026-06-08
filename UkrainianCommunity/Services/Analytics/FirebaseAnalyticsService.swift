import Foundation

#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
#endif

#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

final class FirebaseAnalyticsService: AnalyticsTracking {
    private let consentService: AnalyticsConsentProviding
    private static let isDebugLoggingEnabled = false

    #if canImport(FirebaseFunctions)
    private let functions: Functions
    #endif

    init(consentService: AnalyticsConsentProviding = AnalyticsConsentService()) {
        self.consentService = consentService
        let isAnalyticsEnabled = consentService.isAnalyticsEnabled
        Self.debugLog("analytics consent loaded value: \(isAnalyticsEnabled)")
        #if canImport(FirebaseFunctions)
        self.functions = Functions.functions(region: "europe-west3")
        #endif
        #if canImport(FirebaseAnalytics)
        Analytics.setAnalyticsCollectionEnabled(isAnalyticsEnabled)
        Self.debugLog("analytics collection set enabled: \(isAnalyticsEnabled)")
        #else
        Self.debugLog("FirebaseAnalytics unavailable; collection flag not applied")
        #endif
    }

    func track(_ event: AppAnalyticsEvent) {
        Self.debugLog("track(event) called: \(event.name.rawValue)")
        guard consentService.isAnalyticsEnabled else {
            Self.debugLog("event skipped due to consent: \(event.name.rawValue)")
            return
        }

        #if canImport(FirebaseAnalytics)
        let parameters = event.parameters.reduce(into: [String: Any]()) { result, item in
            result[item.key.rawValue] = item.value.firebaseValue
        }

        Analytics.logEvent(event.name.rawValue, parameters: parameters)
        #endif

        trackAggregateEventIfNeeded(event)
    }

    func setCollectionEnabled(_ isEnabled: Bool) {
        consentService.setAnalyticsEnabled(isEnabled)
        Self.debugLog("analytics consent saved value: \(isEnabled)")
        #if canImport(FirebaseAnalytics)
        Analytics.setAnalyticsCollectionEnabled(isEnabled)
        Self.debugLog("analytics collection set enabled: \(isEnabled)")
        #else
        Self.debugLog("FirebaseAnalytics unavailable; collection flag not applied")
        #endif
    }

    private func trackAggregateEventIfNeeded(_ event: AppAnalyticsEvent) {
        guard shouldForwardToAggregation(event.name) else {
            Self.debugLog("callable trackAnalyticsEvent not sent for event: \(event.name.rawValue)")
            return
        }

        guard let request = AnalyticsAggregationRequest(event: event) else {
            Self.debugLog("callable trackAnalyticsEvent request unavailable for event: \(event.name.rawValue)")
            return
        }

        #if canImport(FirebaseFunctions)
        Self.debugLog("callable trackAnalyticsEvent sent: \(event.name.rawValue)")
        Task(priority: .utility) { [functions] in
            do {
                let callable: Callable<AnalyticsAggregationRequest, AnalyticsAggregationResponse> =
                    functions.httpsCallable("trackAnalyticsEvent")
                _ = try await callable.call(request)
                Self.debugLog("callable trackAnalyticsEvent success: \(request.name)")
            } catch {
                Self.debugLog("callable trackAnalyticsEvent failure: \(request.name) \(error.localizedDescription)")
            }
        }
        #else
        Self.debugLog("FirebaseFunctions unavailable; callable trackAnalyticsEvent not sent: \(event.name.rawValue)")
        #endif
    }

    private func shouldForwardToAggregation(_ eventName: AnalyticsEventName) -> Bool {
        switch eventName {
        case .newsView,
             .newsLike,
             .newsBookmark,
             .eventView,
             .eventRegister,
             .eventCancelRegistration,
             .eventBookmark,
             .organizationView,
             .organizationFollow,
             .organizationUnfollow,
             .organizationBookmark,
             .guideArticleView:
            true
        case .searchUsed,
             .filterUsed,
             .languageChanged,
             .themeChanged,
             .analyticsConsentChanged:
            false
        }
    }

    private static func debugLog(_ message: String) {
        #if DEBUG
        guard isDebugLoggingEnabled else { return }
        debugPrint("[Analytics] \(message)")
        #endif
    }
}

private struct AnalyticsAggregationRequest: Encodable {
    let name: String
    let parameters: [String: String]

    init?(event: AppAnalyticsEvent) {
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
    }

    private static let allowedParameterNames: Set<AnalyticsParameterName> = [
        .contentID,
        .contentTitle,
        .contentType,
        .category,
        .federalState,
        .regionScope,
        .organizationID,
        .organizationName,
        .isGuest,
        .accountState
    ]
}

private struct AnalyticsAggregationResponse: Decodable {
    let tracked: Bool
}

private extension AnalyticsParameterValue {
    var stringValue: String? {
        switch self {
        case .string(let value):
            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedValue.isEmpty ? nil : trimmedValue
        case .int,
             .double,
             .bool:
            return nil
        }
    }
}
