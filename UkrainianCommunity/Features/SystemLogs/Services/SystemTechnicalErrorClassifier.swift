import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage
import Foundation

struct SystemTechnicalErrorClassification: Equatable {
    let severity: SystemLogSeverity
    let errorCode: String
    let technicalMessage: String
    let metadata: [String: String]
}

enum SystemTechnicalErrorClassifier {
    static func classify(
        _ error: Error,
        context: SystemTechnicalErrorContext
    ) -> SystemTechnicalErrorClassification {
        if let decodingError = error as? DecodingError {
            return classification(
                severity: .warning,
                errorCode: "parsing.decodingFailed",
                technicalMessage: "Decoding or parsing failed.",
                error: decodingError,
                context: context
            )
        }

        let nsError = error as NSError

        if let appError = error as? AppError {
            return classifyAppError(appError, nsError: nsError, context: context)
        }

        if nsError.domain == FirestoreErrorDomain {
            return classifyFirestoreError(nsError, context: context)
        }

        if nsError.domain == StorageErrorDomain {
            return classifyStorageError(nsError, context: context)
        }

        if nsError.domain == FunctionsErrorDomain {
            return classifyCloudFunctionsError(nsError, context: context)
        }

        if nsError.domain == AuthErrorDomain {
            return classifyAuthError(nsError, context: context)
        }

        if nsError.domain == NSURLErrorDomain {
            return classifyNetworkError(nsError, context: context)
        }

        return classification(
            severity: .error,
            errorCode: stableFallbackCode(for: nsError),
            technicalMessage: "Unexpected technical error.",
            error: error,
            context: context
        )
    }

    private static func classifyAppError(
        _ appError: AppError,
        nsError: NSError,
        context: SystemTechnicalErrorContext
    ) -> SystemTechnicalErrorClassification {
        switch appError {
        case .permissionDenied:
            return classification(
                severity: .error,
                errorCode: "app.permissionDenied",
                technicalMessage: "Application permission check failed.",
                error: appError,
                context: context
            )
        case .network:
            return classification(
                severity: .warning,
                errorCode: "app.networkUnavailable",
                technicalMessage: "Network request failed or timed out.",
                error: appError,
                context: context
            )
        default:
            return classification(
                severity: context.isDestructiveAccountOperation ? .critical : .error,
                errorCode: stableFallbackCode(for: nsError),
                technicalMessage: context.isDestructiveAccountOperation ? "Destructive account operation failed." : "Application operation failed.",
                error: appError,
                context: context
            )
        }
    }

    private static func classifyFirestoreError(
        _ error: NSError,
        context: SystemTechnicalErrorContext
    ) -> SystemTechnicalErrorClassification {
        let code = FirestoreErrorCode.Code(rawValue: error.code)
        switch code {
        case .permissionDenied:
            return classification(severity: .error, errorCode: "firestore.permissionDenied", technicalMessage: "Firestore permission denied.", error: error, context: context)
        case .unavailable:
            return classification(severity: .warning, errorCode: "firestore.unavailable", technicalMessage: "Firestore is temporarily unavailable.", error: error, context: context)
        case .deadlineExceeded:
            return classification(severity: .warning, errorCode: "firestore.deadlineExceeded", technicalMessage: "Firestore request timed out.", error: error, context: context)
        case .internal:
            return classification(severity: .error, errorCode: "firestore.internal", technicalMessage: "Firestore internal error.", error: error, context: context)
        case .dataLoss:
            return classification(severity: .error, errorCode: "firestore.dataLoss", technicalMessage: "Firestore reported data loss.", error: error, context: context)
        case .unknown:
            return classification(severity: .error, errorCode: "firestore.unknown", technicalMessage: "Firestore returned an unknown error.", error: error, context: context)
        default:
            return classification(severity: .error, errorCode: "firestore.\(error.code)", technicalMessage: "Firestore operation failed.", error: error, context: context)
        }
    }

    private static func classifyStorageError(
        _ error: NSError,
        context: SystemTechnicalErrorContext
    ) -> SystemTechnicalErrorClassification {
        let code = StorageErrorCode(rawValue: error.code)
        switch code {
        case .unauthorized:
            return classification(severity: .error, errorCode: "storage.unauthorized", technicalMessage: "Storage operation was not authorized.", error: error, context: context)
        case .quotaExceeded:
            return classification(severity: .error, errorCode: "storage.quotaExceeded", technicalMessage: "Storage quota was exceeded.", error: error, context: context)
        case .retryLimitExceeded:
            return classification(severity: .error, errorCode: "storage.retryLimitExceeded", technicalMessage: "Storage retry limit was exceeded.", error: error, context: context)
        case .cancelled:
            return classification(severity: .warning, errorCode: "storage.cancelled", technicalMessage: "Storage operation was cancelled.", error: error, context: context)
        default:
            return classification(severity: .error, errorCode: "storage.\(error.code)", technicalMessage: "Storage operation failed.", error: error, context: context)
        }
    }

    private static func classifyCloudFunctionsError(
        _ error: NSError,
        context: SystemTechnicalErrorContext
    ) -> SystemTechnicalErrorClassification {
        let code = FunctionsErrorCode(rawValue: error.code)
        switch code {
        case .unavailable:
            return classification(severity: .warning, errorCode: "cloudFunctions.unavailable", technicalMessage: "Cloud Function is temporarily unavailable.", error: error, context: context)
        case .deadlineExceeded:
            return classification(severity: .warning, errorCode: "cloudFunctions.deadlineExceeded", technicalMessage: "Cloud Function request timed out.", error: error, context: context)
        case .permissionDenied:
            return classification(severity: .error, errorCode: "cloudFunctions.permissionDenied", technicalMessage: "Cloud Function permission denied.", error: error, context: context)
        case .unauthenticated:
            return classification(severity: .error, errorCode: "cloudFunctions.unauthenticated", technicalMessage: "Cloud Function request was unauthenticated.", error: error, context: context)
        default:
            return classification(severity: .error, errorCode: "cloudFunctions.\(error.code)", technicalMessage: "Cloud Function call failed.", error: error, context: context)
        }
    }

    private static func classifyAuthError(
        _ error: NSError,
        context: SystemTechnicalErrorContext
    ) -> SystemTechnicalErrorClassification {
        let code = AuthErrorCode(rawValue: error.code)
        if context.isDestructiveAccountOperation {
            return classification(
                severity: .critical,
                errorCode: code.map { "auth.\($0.rawValue)" } ?? "auth.\(error.code)",
                technicalMessage: "Destructive account operation failed.",
                error: error,
                context: context
            )
        }

        return classification(
            severity: .error,
            errorCode: code.map { "auth.\($0.rawValue)" } ?? "auth.\(error.code)",
            technicalMessage: "Authentication operation failed.",
            error: error,
            context: context
        )
    }

    private static func classifyNetworkError(
        _ error: NSError,
        context: SystemTechnicalErrorContext
    ) -> SystemTechnicalErrorClassification {
        switch error.code {
        case NSURLErrorNotConnectedToInternet:
            return classification(severity: .warning, errorCode: "network.notConnectedToInternet", technicalMessage: "Network is unavailable.", error: error, context: context)
        case NSURLErrorTimedOut:
            return classification(severity: .warning, errorCode: "network.timedOut", technicalMessage: "Network request timed out.", error: error, context: context)
        case NSURLErrorNetworkConnectionLost:
            return classification(severity: .warning, errorCode: "network.connectionLost", technicalMessage: "Network connection was lost.", error: error, context: context)
        default:
            return classification(severity: .error, errorCode: "network.\(error.code)", technicalMessage: "Network request failed.", error: error, context: context)
        }
    }

    private static func classification(
        severity: SystemLogSeverity,
        errorCode: String,
        technicalMessage: String,
        error: Error,
        context: SystemTechnicalErrorContext
    ) -> SystemTechnicalErrorClassification {
        let nsError = error as NSError
        var metadata = context.metadata
        metadata["errorDomain"] = safeMetadataValue(nsError.domain)
        metadata["errorNumber"] = "\(nsError.code)"
        metadata["classification"] = errorCode
        metadata["targetType"] = context.targetType.rawValue

        return SystemTechnicalErrorClassification(
            severity: severity,
            errorCode: errorCode,
            technicalMessage: technicalMessage,
            metadata: metadata
        )
    }

    private static func stableFallbackCode(for error: NSError) -> String {
        let domain = error.domain
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return "\(domain).\(error.code)"
    }

    private static func safeMetadataValue(_ value: String) -> String {
        String(value.prefix(120))
    }
}
