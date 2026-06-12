import Foundation
import Combine

enum AuthSessionState: Equatable {
    case restoring
    case guest
    case authenticated
    case verificationPending
}

enum AuthFlowDestination: String, Identifiable {
    case landing
    case login
    case register
    case passwordReset
    case emailVerification

    var id: String { rawValue }
}

final class AuthState: ObservableObject {
    @Published var user: AppUser?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var pendingVerificationEmail: String?
    @Published private(set) var sessionState: AuthSessionState = .restoring
    @Published var presentedAuthFlow: AuthFlowDestination?

    var isGuest: Bool {
        sessionState == .guest
    }

    var isAuthenticated: Bool {
        sessionState == .authenticated
    }

    var isVerificationPending: Bool {
        sessionState == .verificationPending
    }

    var isRestoring: Bool {
        sessionState == .restoring
    }

    @MainActor
    func beginRestoringSession() {
        sessionState = .restoring
        errorMessage = nil
    }

    @MainActor
    func setGuestSession() {
        user = nil
        pendingVerificationEmail = nil
        sessionState = .guest
        errorMessage = nil
    }

    @MainActor
    func setAuthenticatedSession() {
        pendingVerificationEmail = nil
        sessionState = .authenticated
    }

    @MainActor
    func setVerificationPendingSession(email: String?) {
        user = nil
        pendingVerificationEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines)
        sessionState = .verificationPending
        errorMessage = nil
    }

    @MainActor
    func presentAuthFlow(_ destination: AuthFlowDestination = .landing) {
        presentedAuthFlow = destination
    }

    @MainActor
    func dismissAuthFlow() {
        presentedAuthFlow = nil
    }

    @MainActor
    func loadUser(uid: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let result = await UserProfileService.shared.fetchUserProfile(uid: uid)
        user = result

        if result == nil {
            errorMessage = AppStrings.Auth.loadUserProfileFailed
        }
    }
}
