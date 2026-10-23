import AuthenticationServices
import FirebaseAuth
import FirebaseFunctions
import Foundation

enum AuthFailureMessage {
    static func isCancellation(_ error: Error) -> Bool {
        let value = error as NSError
        return error is CancellationError
            || (value.domain == ASAuthorizationError.errorDomain && value.code == ASAuthorizationError.canceled.rawValue)
            || (value.domain == "com.google.GIDSignIn" && value.code == -5)
    }

    static func text(for error: Error, fallback: String) -> String {
        if FirebaseReadErrorMapper.map(error) == .network { return AppStrings.Startup.connectionMessage }
        let value = error as NSError
        if value.domain == AuthErrorDomain {
            switch AuthErrorCode(rawValue: value.code) {
            case .networkError: return AppStrings.Startup.connectionMessage
            case .tooManyRequests: return AppStrings.Auth.emailVerificationTooManyRequests
            case .accountExistsWithDifferentCredential: return AppStrings.Auth.accountUsesAnotherSignInMethod
            case .userDisabled: return AppStrings.Auth.accountUnavailable
            default: break
            }
        }
        if value.domain == FunctionsErrorDomain {
            switch FunctionsErrorCode(rawValue: value.code) {
            case .unavailable, .deadlineExceeded: return AppStrings.Startup.connectionMessage
            case .resourceExhausted: return AppStrings.Auth.emailVerificationTooManyRequests
            case .permissionDenied: return AppStrings.Auth.accountUnavailable
            case .failedPrecondition: return AppStrings.Auth.signInExpired
            default: break
            }
        }
        return fallback
    }
}
