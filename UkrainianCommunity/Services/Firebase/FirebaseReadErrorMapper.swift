import FirebaseFirestore
import Foundation

enum FirebaseReadErrorMapper {
    static func map(_ error: Error) -> AppError {
        if let appError = error as? AppError {
            return appError
        }

        let error = error as NSError
        if error.domain == NSURLErrorDomain {
            return .network
        }

        guard error.domain == FirestoreErrorDomain else {
            return .unknown
        }

        switch error.code {
        case FirestoreErrorCode.unauthenticated.rawValue,
             FirestoreErrorCode.permissionDenied.rawValue:
            return .permissionDenied
        case FirestoreErrorCode.cancelled.rawValue,
             FirestoreErrorCode.deadlineExceeded.rawValue,
             FirestoreErrorCode.resourceExhausted.rawValue,
             FirestoreErrorCode.aborted.rawValue,
             FirestoreErrorCode.unavailable.rawValue:
            return .network
        case FirestoreErrorCode.notFound.rawValue:
            return .notFound
        case FirestoreErrorCode.invalidArgument.rawValue,
             FirestoreErrorCode.failedPrecondition.rawValue,
             FirestoreErrorCode.dataLoss.rawValue:
            return .validationFailed
        default:
            return .unknown
        }
    }
}
