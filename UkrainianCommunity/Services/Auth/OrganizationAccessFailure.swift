import Foundation
import FirebaseFunctions

struct OrganizationAccessFailure: LocalizedError {
    let reason: String
    let correlationID: String?

    init(reason: String, correlationID: String? = nil) {
        self.reason = reason
        self.correlationID = correlationID
    }

    init(_ error: Error) {
        if let existing = error as? Self { self = existing; return }
        let failure = error as NSError
        let details = failure.userInfo[FunctionsErrorDetailsKey] as? [String: Any]
        correlationID = (details?["correlationId"] as? String).flatMap { UUID(uuidString: $0)?.uuidString }
        if let value = details?["reasonCode"] as? String { reason = value; return }
        if failure.domain == FunctionsErrorDomain {
            reason = switch FunctionsErrorCode(rawValue: failure.code) {
            case .unauthenticated: "sign_in_required"
            case .permissionDenied: "role_missing"
            case .notFound: "object_missing"
            case .aborted: "object_changed"
            case .invalidArgument: "invalid_request"
            case .resourceExhausted: "limit_reached"
            case .unavailable: "network_unavailable"
            default: "outcome_unknown"
            }
        } else { reason = failure.domain == NSURLErrorDomain ? "network_unavailable" : "outcome_unknown" }
    }

    var errorDescription: String? {
        AppStrings.AccessFailure.message(reason)
    }

    /// Kept separate from product copy; support can correlate logs without exposing identifiers in every alert.
    var diagnosticMetadata: [String: String] {
        var result = ["reasonCode": reason]
        if let correlationID { result["correlationId"] = correlationID }
        return result
    }
}
