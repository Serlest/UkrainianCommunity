import FirebaseAuth
import FirebaseFirestore

enum AuthVerificationError: Error {
    case noCurrentUser
    case alreadyVerified
    case emailNotVerified
    case checkFailed
    case tooManyRequests
    case unknown
}

struct RegistrationProfileDraft {
    let email: String
    let displayName: String
    let telegramUsername: String?
    let selectedFederalState: AustrianFederalState
    let acceptedTermsAt: Date
    let acceptedPrivacyAt: Date
    let termsVersion: String
    let privacyVersion: String
}

enum RegistrationError: Error {
    case invalidEmail
    case emailAlreadyInUse
    case weakPassword
    case network
    case operationNotAllowed
    case unknownAuth
    case profilePermission
    case profileNetwork
    case profileUnknown
}

final class AuthService {
    static let shared = AuthService()
    static let currentTermsVersion = "2026.1"
    static let currentPrivacyVersion = "2026.1"

    let authState = AuthState()

    var currentUser: User? { Auth.auth().currentUser }
    var isAuthenticated: Bool { authState.isAuthenticated }

    @MainActor
    func restoreSession() async {
        authState.beginRestoringSession()

        guard let currentUser else {
            authState.setGuestSession()
            return
        }

        guard !currentUser.isAnonymous else {
            do {
                try Auth.auth().signOut()
            } catch {
                print("Anonymous sign-out error: \(error.localizedDescription)")
            }

            authState.setGuestSession()
            return
        }

        do {
            let isEmailVerified = try await isCurrentUserEmailVerified()

            if !isEmailVerified {
                authState.setVerificationPendingSession(email: currentUser.email)
                authState.presentAuthFlow(.emailVerification)
                return
            }

            let user = try await loadExistingUserProfile(uid: currentUser.uid)
            authState.user = user
            authState.setAuthenticatedSession()
        } catch {
            if isMissingProfileError(error) {
                do {
                    try Auth.auth().signOut()
                } catch {
                    print("Missing profile sign-out error: \(error.localizedDescription)")
                }

                authState.setGuestSession()
                return
            }

            authState.setGuestSession()
            if let verificationError = error as? AuthVerificationError {
                authState.errorMessage = mapVerificationFlowMessage(for: verificationError)
            } else {
                authState.errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    func signInAnonymously() async {
        if let currentUser {
            if currentUser.isAnonymous {
                authState.setGuestSession()
            }
            return
        }

        do {
            _ = try await Auth.auth().signInAnonymously()
            authState.setGuestSession()
        } catch {
            print("Auth error: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func signOut() -> Bool {
        do {
            try Auth.auth().signOut()
            Task { @MainActor in
                authState.setGuestSession()
            }
            return true
        } catch {
            print("Sign out error: \(error.localizedDescription)")
            return false
        }
    }

    @MainActor
    func signIn(email: String, password: String) async throws -> AppUser {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        let isEmailVerified = try await isCurrentUserEmailVerified(result.user)

        guard isEmailVerified else {
            authState.setVerificationPendingSession(email: result.user.email)
            authState.presentAuthFlow(.emailVerification)
            throw AuthVerificationError.emailNotVerified
        }

        let user = try await loadExistingUserProfile(uid: result.user.uid)
        authState.user = user
        authState.setAuthenticatedSession()
        authState.dismissAuthFlow()
        return user
    }

    @MainActor
    func register(draft: RegistrationProfileDraft, password: String) async throws -> AppUser {
        let firebaseUser: User

        do {
            let result = try await Auth.auth().createUser(withEmail: draft.email, password: password)
            firebaseUser = result.user
        } catch {
            #if DEBUG
            print("Registration auth creation failed: \(error.localizedDescription)")
            #endif
            throw mapAuthRegistrationError(error)
        }

        do {
            let request = firebaseUser.createProfileChangeRequest()
            request.displayName = draft.displayName
            try await request.commitChanges()

            try await UserProfileService.shared.createRegisteredUserDocument(for: firebaseUser.uid, draft: draft)

            do {
                try await sendEmailVerification(to: firebaseUser)
                authState.errorMessage = nil
            } catch {
                authState.errorMessage = mapVerificationFlowMessage(for: error)
            }

            let user = try await loadExistingUserProfile(uid: firebaseUser.uid)
            authState.setVerificationPendingSession(email: user.email)
            authState.presentAuthFlow(.emailVerification)
            return user
        } catch {
            let mappedError = mapProfileCreationError(error)
            #if DEBUG
            print("Registration profile creation failed: \(error.localizedDescription)")
            #endif

            do {
                try await firebaseUser.delete()
            } catch {
                #if DEBUG
                print("Registration cleanup error: \(error.localizedDescription)")
                #endif
            }

            try? Auth.auth().signOut()
            authState.setGuestSession()
            throw mappedError
        }
    }

    func sendPasswordReset(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }

    func sendEmailVerification(to user: User? = nil) async throws {
        let currentUser = user ?? self.currentUser
        guard let currentUser else { throw AuthVerificationError.noCurrentUser }

        do {
            if try await isCurrentUserEmailVerifiedForResend(currentUser) {
                throw AuthVerificationError.alreadyVerified
            }

            try await currentUser.sendEmailVerification()
        } catch let error as AuthVerificationError {
            throw error
        } catch {
            throw mapAuthVerificationError(error)
        }
    }

    @MainActor
    func verifyEmailAndAuthenticate() async throws -> AppUser {
        guard let currentUser = currentUser else {
            throw AuthVerificationError.noCurrentUser
        }

        do {
            let isEmailVerified = try await isCurrentUserEmailVerified(currentUser)

            guard isEmailVerified else {
                throw AuthVerificationError.emailNotVerified
            }

            let user = try await loadExistingUserProfile(uid: currentUser.uid)
            authState.user = user
            authState.setAuthenticatedSession()
            authState.dismissAuthFlow()
            return user
        } catch {
            if isMissingProfileError(error) {
                throw AuthVerificationError.checkFailed
            }

            throw error
        }
    }

    private func loadExistingUserProfile(uid: String) async throws -> AppUser {
        try await UserProfileService.shared.fetchExistingUserProfile(uid: uid)
    }

    @MainActor
    private func isCurrentUserEmailVerified(_ user: User) async throws -> Bool {
        do {
            try await user.reload()
            guard user.isEmailVerified else {
                return false
            }

            do {
                _ = try await user.getIDTokenResult(forcingRefresh: true)
            } catch {
                throw AuthVerificationError.checkFailed
            }

            return true
        } catch let error as AuthVerificationError {
            throw error
        } catch {
            throw mapAuthVerificationError(error)
        }
    }

    @MainActor
    private func isCurrentUserEmailVerifiedForResend(_ user: User) async throws -> Bool {
        do {
            try await user.reload()
            return user.isEmailVerified
        } catch {
            throw mapAuthVerificationError(error)
        }
    }

    @MainActor
    private func isCurrentUserEmailVerified() async throws -> Bool {
        guard let currentUser else { throw AuthVerificationError.noCurrentUser }
        return try await isCurrentUserEmailVerified(currentUser)
    }

    private func isMissingProfileError(_ error: Error) -> Bool {
        guard let appError = error as? AppError else { return false }
        return appError == .notFound
    }

    private init() {}

    private func mapAuthRegistrationError(_ error: Error) -> RegistrationError {
        guard let nsError = error as NSError?,
              let code = AuthErrorCode(rawValue: nsError.code) else {
            return .unknownAuth
        }

        switch code {
        case .invalidEmail:
            return .invalidEmail
        case .emailAlreadyInUse:
            return .emailAlreadyInUse
        case .weakPassword:
            return .weakPassword
        case .networkError:
            return .network
        case .operationNotAllowed:
            return .operationNotAllowed
        default:
            return .unknownAuth
        }
    }

    private func mapProfileCreationError(_ error: Error) -> RegistrationError {
        if let appError = error as? AppError {
            switch appError {
            case .permissionDenied:
                return .profilePermission
            case .network:
                return .profileNetwork
            default:
                return .profileUnknown
            }
        }

        guard let nsError = error as NSError? else {
            return .profileUnknown
        }

        if nsError.domain == FirestoreErrorDomain {
            switch nsError.code {
            case FirestoreErrorCode.permissionDenied.rawValue:
                return .profilePermission
            case FirestoreErrorCode.unavailable.rawValue, FirestoreErrorCode.deadlineExceeded.rawValue:
                return .profileNetwork
            default:
                return .profileUnknown
            }
        }

        return .profileUnknown
    }

    private func mapAuthVerificationError(_ error: Error) -> AuthVerificationError {
        guard let nsError = error as NSError?, let code = AuthErrorCode(rawValue: nsError.code) else {
            return .unknown
        }

        switch code {
        case .tooManyRequests:
            return .tooManyRequests
        case .userNotFound:
            return .checkFailed
        case .networkError:
            return .checkFailed
        case .userDisabled:
            return .checkFailed
        default:
            return .unknown
        }
    }

    private func mapVerificationFlowMessage(for error: Error) -> String {
        if let verificationError = error as? AuthVerificationError {
            return switch verificationError {
            case .alreadyVerified:
                AppStrings.Auth.emailVerificationAlreadyVerified
            case .emailNotVerified:
                AppStrings.Auth.emailVerificationStillPending
            case .checkFailed:
                AppStrings.Auth.emailVerificationCheckFailed
            case .tooManyRequests:
                AppStrings.Auth.emailVerificationTooManyRequests
            case .noCurrentUser, .unknown:
                AppStrings.Auth.emailVerificationResendFailed
            }
        }

        guard let nsError = error as NSError?, let code = AuthErrorCode(rawValue: nsError.code) else {
            return AppStrings.Auth.emailVerificationResendFailed
        }

        switch code {
        case .tooManyRequests:
            return AppStrings.Auth.emailVerificationTooManyRequests
        case .userNotFound, .networkError, .userDisabled:
            return AppStrings.Auth.emailVerificationCheckFailed
        default:
            return AppStrings.Auth.emailVerificationResendFailed
        }
    }
}
