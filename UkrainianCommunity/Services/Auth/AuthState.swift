import Foundation
import Combine

enum AuthSessionState: Equatable {
    case restoring
    case authenticating
    case guest
    case authenticated
    case verificationPending
    /// Firebase still owns a non-anonymous session, but the app cannot safely
    /// construct an `AppUser` yet. This state deliberately fails closed instead
    /// of presenting an authenticated Firebase client as an app guest.
    case sessionUnavailable
}

enum AuthFlowDestination: String, Identifiable {
    case landing
    case login
    case register
    case passwordReset
    case emailVerification
    case sessionRecovery
    case multiFactorChallenge
    case privilegedMultiFactorRequirement

    var id: String { rawValue }
}

final class AuthState: ObservableObject {
    typealias UserProfileLoader = (String) async throws -> AppUser

    @Published private(set) var user: AppUser?
    @Published private(set) var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published private(set) var pendingVerificationEmail: String?
    @Published private(set) var pendingSessionUserID: String?
    @Published private(set) var sessionState: AuthSessionState = .restoring
    @Published var presentedAuthFlow: AuthFlowDestination?

    private let userProfileLoader: UserProfileLoader
    let appLock: AppLockService
    private var userLoadGeneration = 0
    private var accessObservation: AnyCancellable?

    init(
        appLock: AppLockService? = nil,
        userProfileLoader: @escaping UserProfileLoader = {
            try await UserProfileService.shared.fetchExistingUserProfile(uid: $0)
        }
    ) {
        self.appLock = appLock ?? AppLockService()
        self.userProfileLoader = userProfileLoader
        accessObservation = OrganizationAccessStore.shared.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

    var isGuest: Bool {
        sessionState == .guest
    }

    var isAuthenticated: Bool {
        sessionState == .authenticated
    }

    var isAuthenticating: Bool {
        sessionState == .authenticating
    }

    var isVerificationPending: Bool {
        sessionState == .verificationPending
    }

    var isRestoring: Bool {
        sessionState == .restoring
    }

    var isSessionUnavailable: Bool {
        sessionState == .sessionUnavailable
    }

    @MainActor
    func beginRestoringSession() {
        appLock.lock()
        invalidateUserLoad()
        user = nil
        pendingVerificationEmail = nil
        pendingSessionUserID = nil
        sessionState = .restoring
        errorMessage = nil
    }

    @MainActor
    func beginAuthenticatingSession(userID: String? = nil, email: String? = nil) {
        invalidateUserLoad()
        user = nil
        pendingVerificationEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingSessionUserID = userID
        sessionState = .authenticating
        errorMessage = nil
    }

    @MainActor
    func setGuestSession() {
        OrganizationAccessStore.shared.transition(to: nil)
        LocalReminderSession.shared.transition(to: nil)
        appLock.updateSession(userID: nil)
        invalidateUserLoad()
        user = nil
        pendingVerificationEmail = nil
        pendingSessionUserID = nil
        sessionState = .guest
        errorMessage = nil
    }

    @MainActor
    func setAuthenticatedSession(user: AppUser, passwordAuthenticated: Bool = false) {
        OrganizationAccessStore.shared.transition(to: user.id)
        LocalReminderSession.shared.transition(to: user.id)
        appLock.updateSession(userID: user.id, passwordAuthenticated: passwordAuthenticated)
        invalidateUserLoad()
        self.user = user
        pendingVerificationEmail = nil
        pendingSessionUserID = user.id
        sessionState = .authenticated
        errorMessage = nil
    }

    @MainActor
    @discardableResult
    func updateAuthenticatedUser(_ updatedUser: AppUser) -> Bool {
        guard sessionState == .authenticated,
              let currentUser = user,
              currentUser.id == updatedUser.id else {
            return false
        }

        user = updatedUser
        return true
    }

    @MainActor
    func setVerificationPendingSession(userID: String, email: String?) {
        OrganizationAccessStore.shared.transition(to: userID)
        LocalReminderSession.shared.transition(to: userID)
        appLock.updateSession(userID: userID)
        invalidateUserLoad()
        user = nil
        pendingSessionUserID = userID
        pendingVerificationEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines)
        sessionState = .verificationPending
        errorMessage = nil
    }

    @MainActor
    func setSessionUnavailable(
        userID: String,
        email: String?,
        errorMessage: String
    ) {
        OrganizationAccessStore.shared.transition(to: userID)
        LocalReminderSession.shared.transition(to: userID)
        appLock.updateSession(userID: userID)
        invalidateUserLoad()
        user = nil
        pendingSessionUserID = userID
        pendingVerificationEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines)
        sessionState = .sessionUnavailable
        self.errorMessage = errorMessage
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
        guard sessionState == .authenticated,
              let currentUser = user,
              currentUser.id == uid else {
            return
        }

        userLoadGeneration &+= 1
        let loadGeneration = userLoadGeneration
        isLoading = true
        errorMessage = nil
        defer {
            if userLoadGeneration == loadGeneration {
                isLoading = false
            }
        }

        do {
            let result = try await userProfileLoader(uid)
            guard userLoadGeneration == loadGeneration,
                  sessionState == .authenticated,
                  user?.id == uid,
                  result.id == uid else {
                return
            }
            _ = updateAuthenticatedUser(result)
        } catch {
            guard userLoadGeneration == loadGeneration,
                  sessionState == .authenticated,
                  user?.id == uid else {
                return
            }
            errorMessage = AppStrings.Auth.loadUserProfileFailed
        }
    }

    @MainActor
    private func invalidateUserLoad() {
        userLoadGeneration &+= 1
        isLoading = false
    }
}
