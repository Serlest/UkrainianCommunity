import FirebaseAuth
import FirebaseFirestore

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
            let user = try await loadExistingUserProfile(uid: currentUser.uid)
            authState.user = user
            authState.setAuthenticatedSession()
        } catch {
            do {
                try Auth.auth().signOut()
            } catch {
                print("Session cleanup error: \(error.localizedDescription)")
            }

            authState.setGuestSession()
        }
    }

    @MainActor
    func signInAnonymously() async {
        if let currentUser {
            await ensureUserProfileExists(for: currentUser.uid)
            return
        }

        do {
            let result = try await Auth.auth().signInAnonymously()
            let uid = result.user.uid
            await ensureUserProfileExists(for: uid)
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
            let user = try await loadExistingUserProfile(uid: firebaseUser.uid)
            authState.user = user
            authState.setAuthenticatedSession()
            authState.dismissAuthFlow()
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

    @MainActor
    private func ensureUserProfileExists(for uid: String) async {
        await UserProfileService.shared.ensureUserDocumentExists(for: uid)
        if let user = await UserProfileService.shared.fetchUserProfile(uid: uid) {
            authState.user = user
        } else {
            authState.user = nil
        }
        authState.setAuthenticatedSession()
    }

    private func loadExistingUserProfile(uid: String) async throws -> AppUser {
        guard let user = await UserProfileService.shared.fetchUserProfile(uid: uid) else {
            throw AppError.notFound
        }

        return user
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
}
