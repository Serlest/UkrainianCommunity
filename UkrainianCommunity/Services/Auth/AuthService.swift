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
    let minimumAgeConfirmedAt: Date
    let minimumAgeVersion: String
    var analyticsConsentEnabled = false
    var appLockAuthorization: RegistrationAppLockAuthorization? = nil
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

enum AuthSessionTransitionError: Error {
    case backendSessionChanged
    case signOutFailed
}

protocol AuthSessionUserProviding: AnyObject {
    var uid: String { get }
    var email: String? { get }
    var isAnonymous: Bool { get }
    var isEmailVerified: Bool { get }

    func reload() async throws
    func refreshIDToken() async throws
    func sendVerificationEmail() async throws
    func updateDisplayName(_ displayName: String) async throws
    func deleteAccount() async throws
}

protocol AuthBackendProviding: AnyObject {
    var currentSessionUser: (any AuthSessionUserProviding)? { get }

    func multiFactorSignInChallenge(
        from error: Error
    ) -> (any AuthMultiFactorSignInChallengeProviding)?
    func isCurrentSessionTOTPAuthenticated() async throws -> Bool
    func signIn(email: String, password: String) async throws -> any AuthSessionUserProviding
    func createUser(email: String, password: String) async throws -> any AuthSessionUserProviding
    func signInAnonymously() async throws -> any AuthSessionUserProviding
    func sendPasswordReset(email: String) async throws
    func signOut() throws
}

protocol AuthProfileProviding: AnyObject {
    func createRegisteredUserDocument(for uid: String, draft: RegistrationProfileDraft) async throws
    func fetchExistingUserProfile(uid: String) async throws -> AppUser
    func ensurePublicProfile(for user: AppUser) async throws
}

@MainActor
protocol AuthNotificationRegistrationProviding: AnyObject {
    func prepareForSignOut() async throws
    func completeSignOut()
    func resumeAfterFailedSignOut() async
}

extension User: AuthSessionUserProviding {
    func refreshIDToken() async throws {
        _ = try await getIDTokenResult(forcingRefresh: true)
    }

    func sendVerificationEmail() async throws {
        try await sendEmailVerification()
    }

    func updateDisplayName(_ displayName: String) async throws {
        let request = createProfileChangeRequest()
        request.displayName = displayName
        try await request.commitChanges()
    }

    func deleteAccount() async throws {
        try await delete()
    }
}

extension UserProfileService: AuthProfileProviding {}
extension RemoteNotificationRegistrationService: AuthNotificationRegistrationProviding {}

final class FirebaseAuthBackend: AuthBackendProviding {
    var currentSessionUser: (any AuthSessionUserProviding)? {
        Auth.auth().currentUser
    }

    func signIn(email: String, password: String) async throws -> any AuthSessionUserProviding {
        (try await Auth.auth().signIn(withEmail: email, password: password)).user
    }

    func isCurrentSessionTOTPAuthenticated() async throws -> Bool {
        guard let user = Auth.auth().currentUser, user.isEmailVerified else { return false }
        let token = try await user.getIDTokenResult()
        return AuthMultiFactorService.claimsContainTOTPSignIn(token.claims)
    }

    func createUser(email: String, password: String) async throws -> any AuthSessionUserProviding {
        (try await Auth.auth().createUser(withEmail: email, password: password)).user
    }

    func signInAnonymously() async throws -> any AuthSessionUserProviding {
        (try await Auth.auth().signInAnonymously()).user
    }

    func sendPasswordReset(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }
}

final class AuthService {
    static let shared: AuthService = {
#if DEBUG && targetEnvironment(simulator)
        if let backend = UITestOwnerAuthBackend.makeIfRequested() {
            return AuthService(authState: AuthState(), backend: backend, profileProvider: UserProfileService.shared)
        }
#endif
        return AuthService(authState: AuthState(), backend: FirebaseAuthBackend(), profileProvider: UserProfileService.shared)
    }()
    nonisolated static let currentTermsVersion = "2026.10"
    nonisolated static let currentPrivacyVersion = "2026.13"
    nonisolated static let currentOrganizationRulesVersion = "2026.10"
    nonisolated static let currentMinimumAgeVersion = "14+"

    let authState: AuthState
    let multiFactorSignIn = AuthMultiFactorSignInCoordinator()

    private let backend: any AuthBackendProviding
    private let profileProvider: any AuthProfileProviding
    private let notificationRegistration: (any AuthNotificationRegistrationProviding)?
    private let analyticsConsent: any AnalyticsConsentProviding
    @MainActor private var transitionGeneration: UInt = 0
    @MainActor private var pendingMultiFactorSignIn: PendingMultiFactorSignIn?
    // Firebase user and session calls cannot be cancelled once started.
    // Serializing them lets a newer transition replace any stale backend result
    // before it publishes app state.
    @MainActor private var isBackendSessionAccessInFlight = false
    @MainActor private var backendSessionAccessWaiters: [CheckedContinuation<Void, Never>] = []

    private struct PendingMultiFactorSignIn {
        let transition: UInt
        let challenge: any AuthMultiFactorSignInChallengeProviding
    }

    var currentUser: User? { Auth.auth().currentUser }
    var isAuthenticated: Bool { authState.isAuthenticated }

    init(
        authState: AuthState,
        backend: any AuthBackendProviding,
        profileProvider: any AuthProfileProviding,
        notificationRegistration: (any AuthNotificationRegistrationProviding)? = nil,
        analyticsConsent: (any AnalyticsConsentProviding)? = nil
    ) {
        self.authState = authState
        self.backend = backend
        self.profileProvider = profileProvider
        self.notificationRegistration = notificationRegistration
        self.analyticsConsent = analyticsConsent ?? AnalyticsConsentService()
    }

    @MainActor
    func restoreSession() async {
        let transition = beginTransition()
        await restoreSession(transition: transition)
    }

    @MainActor
    private func restoreSession(transition: UInt) async {
        guard isCurrentTransition(transition) else { return }
        authState.beginRestoringSession()

        let currentSessionUser: (any AuthSessionUserProviding)?
        do {
            currentSessionUser = try await synchronizedCurrentSessionUser(transition: transition)
        } catch {
            return
        }

        guard let sessionUser = currentSessionUser else {
            authState.setGuestSession()
            authState.dismissAuthFlow()
            return
        }

        guard !sessionUser.isAnonymous else {
            do {
                try await performSynchronizedBackendSessionOperation(transition: transition) {
                    try backend.signOut()
                }
                authState.setGuestSession()
                authState.dismissAuthFlow()
            } catch {
                guard isCurrentTransition(transition) else { return }
                #if DEBUG
                print("Anonymous sign-out error: \(error.localizedDescription)")
                #endif
                authState.setSessionUnavailable(
                    userID: sessionUser.uid,
                    email: sessionUser.email,
                    errorMessage: AppStrings.Auth.loadUserProfileFailed
                )
                authState.presentAuthFlow(.sessionRecovery)
            }
            return
        }

        do {
            let isEmailVerified = try await isCurrentUserEmailVerified(
                sessionUser,
                transition: transition
            )
            try validateCurrentBackendUser(sessionUser, transition: transition)

            if !isEmailVerified {
                authState.setVerificationPendingSession(userID: sessionUser.uid, email: sessionUser.email)
                authState.presentAuthFlow(.emailVerification)
                return
            }

            let user = try await loadExistingUserProfile(uid: sessionUser.uid)
            try validateAuthenticatedProfile(
                user,
                sessionUser: sessionUser,
                transition: transition
            )
            await publishAuthenticatedSession(user: user)
        } catch {
            guard isCurrentTransition(transition) else { return }

            if isMissingProfileError(error) {
                let didRollback = await rollbackSessionToGuest(
                    sessionUser,
                    fallbackMessage: AppStrings.Auth.loadUserProfileFailed,
                    transition: transition
                )
                if didRollback {
                    authState.dismissAuthFlow()
                }
                return
            }

            publishUnavailableSession(sessionUser, error: error, transition: transition)
        }
    }

    @MainActor
    func signInAnonymously() async {
        let transition = beginTransition()

        let currentSessionUser: (any AuthSessionUserProviding)?
        do {
            currentSessionUser = try await synchronizedCurrentSessionUser(transition: transition)
        } catch {
            return
        }

        if let sessionUser = currentSessionUser {
            if sessionUser.isAnonymous {
                authState.setGuestSession()
            } else {
                await restoreSession(transition: transition)
            }
            return
        }

        do {
            _ = try await performSynchronizedBackendSessionOperation(transition: transition) {
                try await backend.signInAnonymously()
            }
            authState.setGuestSession()
        } catch {
            guard isCurrentTransition(transition) else { return }
            #if DEBUG
            print("Auth error: \(error.localizedDescription)")
            #endif
        }
    }

    @MainActor
    @discardableResult
    func signOut() async -> Bool {
        let transition = beginTransition()
        let notificationRegistration = resolvedNotificationRegistration

        // Push cleanup is a privacy safeguard, but it must never trap a user in
        // an authenticated session when the device is offline. The local push
        // identity is invalidated by `completeSignOut`; server cleanup remains
        // best-effort while the original Firebase session is still available.
        do {
            _ = try await synchronizedCurrentSessionUser(transition: transition)
        } catch {
            guard isCurrentTransition(transition) else { return false }
            reconcileAfterFailedSignOut(error, transition: transition)
            #if DEBUG
            print("Sign out session check error: \(error.localizedDescription)")
            #endif
            return false
        }

        do {
            try await notificationRegistration.prepareForSignOut()
        } catch {
            guard isCurrentTransition(transition) else { return false }
            #if DEBUG
            print("Push registration cleanup before sign out was deferred: \(error.localizedDescription)")
            #endif
        }

        guard isCurrentTransition(transition) else {
            await notificationRegistration.resumeAfterFailedSignOut()
            return false
        }

        do {
            try await performSynchronizedBackendSessionOperation(transition: transition) {
                try backend.signOut()
            }
            notificationRegistration.completeSignOut()
            authState.setGuestSession()
            authState.dismissAuthFlow()
            return true
        } catch {
            guard isCurrentTransition(transition) else { return false }
            await notificationRegistration.resumeAfterFailedSignOut()
            guard isCurrentTransition(transition) else { return false }
            reconcileAfterFailedSignOut(error, transition: transition)
            #if DEBUG
            print("Sign out error: \(error.localizedDescription)")
            #endif
            return false
        }
    }

    @MainActor
    @discardableResult
    func completeAccountDeletionSignOut() async -> Bool {
        let transition = beginTransition()
        let notificationRegistration = resolvedNotificationRegistration

        do {
            try await performSynchronizedBackendSessionOperation(transition: transition) {
                try backend.signOut()
            }
            notificationRegistration.completeSignOut()
            authState.setGuestSession()
            authState.dismissAuthFlow()
            return true
        } catch {
            guard isCurrentTransition(transition) else { return false }
            notificationRegistration.completeSignOut()
            reconcileAfterFailedSignOut(error, transition: transition)
            #if DEBUG
            print("Post-deletion sign out error: \(error.localizedDescription)")
            #endif
            return false
        }
    }

    @MainActor
    @discardableResult
    func completeRestrictedAccountSignOut() async -> Bool {
        let transition = beginTransition()
        let notificationRegistration = resolvedNotificationRegistration

        do {
            try await performSynchronizedBackendSessionOperation(transition: transition) {
                try backend.signOut()
            }
            notificationRegistration.completeSignOut()
            authState.setGuestSession()
            authState.dismissAuthFlow()
            return true
        } catch {
            guard isCurrentTransition(transition) else { return false }
            notificationRegistration.completeSignOut()
            reconcileAfterFailedSignOut(error, transition: transition)
            #if DEBUG
            print("Restricted account sign out error: \(error.localizedDescription)")
            #endif
            return false
        }
    }

    @MainActor
    func signIn(email: String, password: String) async throws -> AppUser {
        let transition = beginTransition()
        try await prepareForInteractiveAuthentication(transition: transition)

        let sessionUser: any AuthSessionUserProviding
        do {
            sessionUser = try await performSynchronizedBackendSessionOperation(transition: transition) {
                try await backend.signIn(email: email, password: password)
            }
            authState.beginAuthenticatingSession(userID: sessionUser.uid, email: sessionUser.email)
        } catch {
            guard isCurrentTransition(transition) else { throw error }

            if let challenge = backend.multiFactorSignInChallenge(from: error) {
                pendingMultiFactorSignIn = PendingMultiFactorSignIn(
                    transition: transition,
                    challenge: challenge
                )
                multiFactorSignIn.begin(factors: challenge.factors)
                authState.beginAuthenticatingSession(email: email)
                authState.presentAuthFlow(.multiFactorChallenge)
                throw AuthMultiFactorFlowError.secondFactorRequired
            }

            reconcileAfterFailedAuthenticationStart(error, transition: transition)
            throw error
        }

        return try await finishInteractiveSignIn(
            sessionUser,
            transition: transition
        )
    }

    @MainActor
    func resolveMultiFactorSignIn(
        oneTimeCode: String,
        factorID: String
    ) async throws -> AppUser {
        guard let pending = pendingMultiFactorSignIn,
              pending.transition == transitionGeneration else {
            throw AuthMultiFactorFlowError.challengeUnavailable
        }

        let code = AuthMultiFactorService.normalizedCode(oneTimeCode)
        guard AuthMultiFactorService.isValidCode(code) else {
            multiFactorSignIn.fail(message: AppStrings.Auth.multiFactorInvalidCode)
            throw AuthMultiFactorFlowError.invalidCode
        }

        multiFactorSignIn.beginResolving()

        let sessionUser: any AuthSessionUserProviding
        do {
            sessionUser = try await performSynchronizedBackendSessionOperation(
                transition: pending.transition
            ) {
                try await pending.challenge.resolve(
                    factorID: factorID,
                    oneTimeCode: code
                )
            }
        } catch {
            guard isCurrentTransition(pending.transition) else { throw error }

            if isRecoverableMultiFactorCodeError(error) {
                multiFactorSignIn.fail(message: AppStrings.Auth.multiFactorInvalidCode)
                throw AuthMultiFactorFlowError.invalidCode
            }

            if isExpiredMultiFactorChallenge(error) {
                clearPendingMultiFactorSignIn()
                authState.setGuestSession()
                authState.presentAuthFlow(.login)
                throw AuthMultiFactorFlowError.challengeUnavailable
            }

            multiFactorSignIn.fail(message: AppStrings.Auth.multiFactorResolveFailed)
            throw error
        }

        clearPendingMultiFactorSignIn()
        authState.beginAuthenticatingSession(userID: sessionUser.uid, email: sessionUser.email)
        return try await finishInteractiveSignIn(
            sessionUser,
            transition: pending.transition
        )
    }

    @MainActor
    func cancelMultiFactorSignIn() async {
        let transition = beginTransition()

        do {
            if backend.currentSessionUser != nil {
                try await performSynchronizedBackendSessionOperation(transition: transition) {
                    try backend.signOut()
                }
            }
            authState.setGuestSession()
            authState.dismissAuthFlow()
        } catch {
            guard isCurrentTransition(transition) else { return }
            reconcileAfterFailedSignOut(error, transition: transition)
        }
    }

    @MainActor
    func refreshPrivilegedMultiFactorRequirement() async {
        guard authState.isAuthenticated, let user = authState.user else { return }
        await updatePrivilegedMultiFactorPresentation(
            for: user,
            dismissResolvedAuthFlow: false
        )
    }

    @MainActor
    private func publishAuthenticatedSession(
        user: AppUser,
        passwordAuthenticated: Bool = false
    ) async {
        authState.setAuthenticatedSession(
            user: user,
            passwordAuthenticated: passwordAuthenticated
        )
        await updatePrivilegedMultiFactorPresentation(
            for: user,
            dismissResolvedAuthFlow: true
        )
    }

    @MainActor
    private func updatePrivilegedMultiFactorPresentation(
        for user: AppUser,
        dismissResolvedAuthFlow: Bool
    ) async {
        guard AuthSecurityPolicy.requiresProtectedSession(user) else {
            if dismissResolvedAuthFlow
                || authState.presentedAuthFlow == .privilegedMultiFactorRequirement {
                authState.dismissAuthFlow()
            }
            return
        }

        let isTOTPAuthenticated = (try? await backend.isCurrentSessionTOTPAuthenticated()) == true
        if AuthSecurityPolicy.protectedSessionIsReady(
            user: user,
            isTOTPAuthenticated: isTOTPAuthenticated
        ) {
            if dismissResolvedAuthFlow
                || authState.presentedAuthFlow == .privilegedMultiFactorRequirement {
                authState.dismissAuthFlow()
            }
        } else {
            authState.presentAuthFlow(.privilegedMultiFactorRequirement)
        }
    }

    @MainActor
    private func finishInteractiveSignIn(
        _ sessionUser: any AuthSessionUserProviding,
        transition: UInt
    ) async throws -> AppUser {
        do {
            let isEmailVerified = try await isCurrentUserEmailVerified(
                sessionUser,
                transition: transition
            )
            try validateCurrentBackendUser(sessionUser, transition: transition)

            guard isEmailVerified else {
                authState.setVerificationPendingSession(userID: sessionUser.uid, email: sessionUser.email)
                authState.presentAuthFlow(.emailVerification)
                throw AuthVerificationError.emailNotVerified
            }

            let user = try await loadExistingUserProfile(uid: sessionUser.uid)
            try validateAuthenticatedProfile(
                user,
                sessionUser: sessionUser,
                transition: transition
            )
            await publishAuthenticatedSession(user: user, passwordAuthenticated: true)
            return user
        } catch AuthVerificationError.emailNotVerified {
            throw AuthVerificationError.emailNotVerified
        } catch {
            guard isCurrentTransition(transition) else { throw error }
            _ = await rollbackSessionToGuest(
                sessionUser,
                fallbackMessage: readableSessionFailure(error),
                transition: transition
            )
            throw error
        }
    }

    @MainActor
    func register(draft: RegistrationProfileDraft, password: String) async throws {
        let transition = beginTransition()
        try await prepareForInteractiveAuthentication(transition: transition)

        let sessionUser: any AuthSessionUserProviding

        do {
            sessionUser = try await performSynchronizedBackendSessionOperation(transition: transition) {
                try await backend.createUser(email: draft.email, password: password)
            }
            authState.beginAuthenticatingSession(userID: sessionUser.uid, email: sessionUser.email ?? draft.email)
        } catch {
            guard isCurrentTransition(transition) else {
                throw mapAuthRegistrationError(error)
            }
            reconcileAfterFailedAuthenticationStart(error, transition: transition)
            #if DEBUG
            print("Registration auth creation failed: \(error.localizedDescription)")
            #endif
            throw mapAuthRegistrationError(error)
        }

        do {
            try await performSynchronizedBackendSessionOperation(transition: transition) {
                try await sessionUser.updateDisplayName(draft.displayName)
            }
            try validateCurrentBackendUser(sessionUser, transition: transition)
            try await profileProvider.createRegisteredUserDocument(for: sessionUser.uid, draft: draft)
            try validateCurrentBackendUser(sessionUser, transition: transition)
        } catch {
            let mappedError = mapProfileCreationError(error)
            guard isCurrentTransition(transition) else { throw mappedError }
            #if DEBUG
            print("Registration profile creation failed: \(error.localizedDescription)")
            #endif

            do {
                try await performSynchronizedBackendSessionOperation(transition: transition) {
                    try await sessionUser.deleteAccount()
                }
            } catch {
                #if DEBUG
                print("Registration cleanup error: \(error.localizedDescription)")
                #endif
            }

            guard isCurrentTransition(transition) else { throw mappedError }
            _ = await rollbackSessionToGuest(
                sessionUser,
                fallbackMessage: readableSessionFailure(error),
                transition: transition
            )
            throw mappedError
        }

        try validateCurrentBackendUser(sessionUser, transition: transition)
        // Persist only a successful registration's explicit choice, scoped to its UID.
        // FirstPartyAnalyticsService still requires verified email and a server receipt
        // before authorizing any analytics delivery, including after an app restart.
        analyticsConsent.setAnalyticsEnabled(draft.analyticsConsentEnabled, for: sessionUser.uid)
        if let authorization = draft.appLockAuthorization {
            authState.appLock.enableAfterRegistration(authorization, userID: sessionUser.uid)
        }
        authState.setVerificationPendingSession(
            userID: sessionUser.uid,
            email: sessionUser.email ?? draft.email
        )
        authState.presentAuthFlow(.emailVerification)

        do {
            try await sendEmailVerification(to: sessionUser, transition: transition)
            guard isCurrentTransition(transition) else { return }
            guard backend.currentSessionUser?.uid == sessionUser.uid else {
                publishUnavailableSession(
                    sessionUser,
                    error: AuthSessionTransitionError.backendSessionChanged,
                    transition: transition
                )
                return
            }
            guard authState.isVerificationPending,
                  authState.pendingSessionUserID == sessionUser.uid else {
                return
            }
            authState.errorMessage = nil
        } catch {
            guard isCurrentTransition(transition) else { return }
            guard backend.currentSessionUser?.uid == sessionUser.uid else {
                publishUnavailableSession(sessionUser, error: error, transition: transition)
                return
            }
            guard authState.isVerificationPending,
                  authState.pendingSessionUserID == sessionUser.uid else {
                return
            }
            authState.errorMessage = mapVerificationFlowMessage(for: error)
        }
    }

    func sendPasswordReset(email: String) async throws {
        try await backend.sendPasswordReset(email: email)
    }

    @MainActor
    func sendEmailVerification() async throws {
        let transition = transitionGeneration
        let currentSessionUser = try await synchronizedCurrentSessionUser(transition: transition)
        guard let sessionUser = currentSessionUser else {
            throw AuthVerificationError.noCurrentUser
        }

        try await sendEmailVerification(to: sessionUser, transition: transition)
    }

    @MainActor
    private func sendEmailVerification(
        to sessionUser: any AuthSessionUserProviding,
        transition: UInt
    ) async throws {

        do {
            if try await isCurrentUserEmailVerifiedForResend(
                sessionUser,
                transition: transition
            ) {
                throw AuthVerificationError.alreadyVerified
            }

            try ensureCurrentTransition(transition)
            try await performSynchronizedBackendSessionOperation(transition: transition) {
                try await sessionUser.sendVerificationEmail()
            }
        } catch let error as AuthVerificationError {
            throw error
        } catch {
            throw mapAuthVerificationError(error)
        }
    }

    @MainActor
    func verifyEmailAndAuthenticate() async throws -> AppUser {
        let transition = beginTransition()
        let currentSessionUser = try await synchronizedCurrentSessionUser(transition: transition)
        guard let sessionUser = currentSessionUser else {
            authState.setGuestSession()
            throw AuthVerificationError.noCurrentUser
        }

        var verifiedEmail = false
        do {
            let isEmailVerified = try await isCurrentUserEmailVerified(
                sessionUser,
                transition: transition
            )
            try validateCurrentBackendUser(sessionUser, transition: transition)

            guard isEmailVerified else {
                throw AuthVerificationError.emailNotVerified
            }
            verifiedEmail = true

            let user = try await loadExistingUserProfile(uid: sessionUser.uid)
            try validateAuthenticatedProfile(
                user,
                sessionUser: sessionUser,
                transition: transition
            )
            await publishAuthenticatedSession(user: user)
            return user
        } catch {
            guard isCurrentTransition(transition) else { throw error }

            if isMissingProfileError(error) {
                _ = await rollbackSessionToGuest(
                    sessionUser,
                    fallbackMessage: AppStrings.Auth.loadUserProfileFailed,
                    transition: transition
                )
                throw AuthVerificationError.checkFailed
            }

            if verifiedEmail {
                publishUnavailableSession(sessionUser, error: error, transition: transition)
            } else if backend.currentSessionUser?.uid != sessionUser.uid {
                publishUnavailableSession(sessionUser, error: error, transition: transition)
            } else {
                authState.setVerificationPendingSession(userID: sessionUser.uid, email: sessionUser.email)
                authState.errorMessage = mapVerificationFlowMessage(for: error)
                authState.presentAuthFlow(.emailVerification)
            }

            throw error
        }
    }

    private func loadExistingUserProfile(uid: String) async throws -> AppUser {
        let user = try await profileProvider.fetchExistingUserProfile(uid: uid)

        // A public profile is a recoverable projection of the private account.
        // It must only be synchronized after Firebase has refreshed a verified
        // session token. A transient projection failure must not lock the user
        // out of their account; the provider records it and every later verified
        // authentication path retries the repair.
        try? await profileProvider.ensurePublicProfile(for: user)
        return user
    }

    @MainActor
    private func isCurrentUserEmailVerified(
        _ user: any AuthSessionUserProviding,
        transition: UInt
    ) async throws -> Bool {
        do {
            try await performSynchronizedBackendSessionOperation(transition: transition) {
                try await user.reload()
            }
            guard user.isEmailVerified else {
                return false
            }

            do {
                try await performSynchronizedBackendSessionOperation(transition: transition) {
                    try await user.refreshIDToken()
                }
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
    private func isCurrentUserEmailVerifiedForResend(
        _ user: any AuthSessionUserProviding,
        transition: UInt
    ) async throws -> Bool {
        do {
            try await performSynchronizedBackendSessionOperation(transition: transition) {
                try await user.reload()
            }
            return user.isEmailVerified
        } catch {
            throw mapAuthVerificationError(error)
        }
    }

    @MainActor
    func retryUnavailableSession() async {
        guard authState.isSessionUnavailable else { return }
        let transition = beginTransition()
        await restoreSession(transition: transition)
    }

    @MainActor
    private var resolvedNotificationRegistration: any AuthNotificationRegistrationProviding {
        notificationRegistration ?? RemoteNotificationRegistrationService.shared
    }

    @MainActor
    private func prepareForInteractiveAuthentication(transition: UInt) async throws {
        try ensureCurrentTransition(transition)

        let hasBackendSession = try await synchronizedCurrentSessionUser(
            transition: transition
        ) != nil
        let hasPublishedBackendSession = authState.isAuthenticated
            || authState.isVerificationPending
            || authState.isSessionUnavailable
            || authState.isAuthenticating

        guard hasBackendSession || hasPublishedBackendSession else {
            authState.beginAuthenticatingSession()
            return
        }

        let notificationRegistration = resolvedNotificationRegistration
        do {
            try await notificationRegistration.prepareForSignOut()
            guard isCurrentTransition(transition) else {
                await notificationRegistration.resumeAfterFailedSignOut()
                throw AuthSessionTransitionError.backendSessionChanged
            }

            try await performSynchronizedBackendSessionOperation(transition: transition) {
                try backend.signOut()
            }
            notificationRegistration.completeSignOut()
            authState.setGuestSession()
            authState.beginAuthenticatingSession()
        } catch {
            guard isCurrentTransition(transition) else { throw error }
            await notificationRegistration.resumeAfterFailedSignOut()
            guard isCurrentTransition(transition) else { throw error }
            reconcileAfterFailedSignOut(error, transition: transition)
            throw AuthSessionTransitionError.signOutFailed
        }
    }

    @MainActor
    @discardableResult
    private func rollbackSessionToGuest(
        _ attemptedUser: any AuthSessionUserProviding,
        fallbackMessage: String,
        transition: UInt
    ) async -> Bool {
        guard isCurrentTransition(transition) else { return false }

        guard let currentUser = backend.currentSessionUser else {
            authState.setGuestSession()
            return true
        }

        guard !currentUser.isAnonymous else {
            authState.setGuestSession()
            return true
        }

        guard currentUser.uid == attemptedUser.uid else {
            authState.setSessionUnavailable(
                userID: currentUser.uid,
                email: currentUser.email,
                errorMessage: fallbackMessage
            )
            authState.presentAuthFlow(.sessionRecovery)
            return false
        }

        do {
            try await performSynchronizedBackendSessionOperation(transition: transition) {
                try backend.signOut()
            }
            authState.setGuestSession()
            return true
        } catch {
            guard isCurrentTransition(transition) else { return false }
            authState.setSessionUnavailable(
                userID: currentUser.uid,
                email: currentUser.email,
                errorMessage: fallbackMessage
            )
            authState.presentAuthFlow(.sessionRecovery)
            return false
        }
    }

    @MainActor
    private func publishUnavailableSession(
        _ sessionUser: any AuthSessionUserProviding,
        error: Error,
        transition: UInt
    ) {
        guard isCurrentTransition(transition) else { return }

        guard let currentUser = backend.currentSessionUser, !currentUser.isAnonymous else {
            authState.setGuestSession()
            authState.dismissAuthFlow()
            return
        }

        let userToPublish = currentUser.uid == sessionUser.uid ? sessionUser : currentUser
        authState.setSessionUnavailable(
            userID: userToPublish.uid,
            email: userToPublish.email,
            errorMessage: readableSessionFailure(error)
        )
        authState.presentAuthFlow(.sessionRecovery)
    }

    @MainActor
    private func reconcileAfterFailedAuthenticationStart(_ error: Error, transition: UInt) {
        guard isCurrentTransition(transition) else { return }

        guard let currentUser = backend.currentSessionUser, !currentUser.isAnonymous else {
            authState.setGuestSession()
            return
        }

        authState.setSessionUnavailable(
            userID: currentUser.uid,
            email: currentUser.email,
            errorMessage: readableSessionFailure(error)
        )
        authState.presentAuthFlow(.sessionRecovery)
    }

    @MainActor
    private func reconcileAfterFailedSignOut(_ error: Error, transition: UInt) {
        guard isCurrentTransition(transition) else { return }

        guard let currentUser = backend.currentSessionUser, !currentUser.isAnonymous else {
            authState.setGuestSession()
            authState.dismissAuthFlow()
            return
        }

        let stateAlreadyMatchesBackend = (
            authState.isAuthenticated && authState.user?.id == currentUser.uid
        ) || (
            (authState.isVerificationPending || authState.isSessionUnavailable)
                && authState.pendingSessionUserID == currentUser.uid
        )

        guard !stateAlreadyMatchesBackend else { return }

        authState.setSessionUnavailable(
            userID: currentUser.uid,
            email: currentUser.email,
            errorMessage: readableSessionFailure(error)
        )
        authState.presentAuthFlow(.sessionRecovery)
    }

    @MainActor
    private func validateCurrentBackendUser(
        _ expectedUser: any AuthSessionUserProviding,
        transition: UInt
    ) throws {
        try ensureCurrentTransition(transition)
        guard backend.currentSessionUser?.uid == expectedUser.uid else {
            throw AuthSessionTransitionError.backendSessionChanged
        }
    }

    @MainActor
    private func validateAuthenticatedProfile(
        _ user: AppUser,
        sessionUser: any AuthSessionUserProviding,
        transition: UInt
    ) throws {
        try validateCurrentBackendUser(sessionUser, transition: transition)
        guard user.id == sessionUser.uid else {
            throw AuthSessionTransitionError.backendSessionChanged
        }
    }

    @MainActor
    private func synchronizedCurrentSessionUser(
        transition: UInt
    ) async throws -> (any AuthSessionUserProviding)? {
        try await performSynchronizedBackendSessionOperation(transition: transition) {
            backend.currentSessionUser
        }
    }

    @MainActor
    private func performSynchronizedBackendSessionOperation<Result>(
        transition: UInt,
        operation: () async throws -> Result
    ) async throws -> Result {
        try await acquireBackendSessionAccess(transition: transition)
        defer { releaseBackendSessionAccess() }

        try ensureCurrentTransition(transition)
        let result = try await operation()
        try ensureCurrentTransition(transition)
        return result
    }

    @MainActor
    private func acquireBackendSessionAccess(transition: UInt) async throws {
        try ensureCurrentTransition(transition)

        while isBackendSessionAccessInFlight {
            await withCheckedContinuation { continuation in
                backendSessionAccessWaiters.append(continuation)
            }
            try ensureCurrentTransition(transition)
        }

        isBackendSessionAccessInFlight = true
    }

    @MainActor
    private func releaseBackendSessionAccess() {
        isBackendSessionAccessInFlight = false

        let waiters = backendSessionAccessWaiters
        backendSessionAccessWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    @MainActor
    private func beginTransition() -> UInt {
        clearPendingMultiFactorSignIn()
        transitionGeneration &+= 1
        return transitionGeneration
    }

    @MainActor
    private func clearPendingMultiFactorSignIn() {
        pendingMultiFactorSignIn = nil
        multiFactorSignIn.reset()
    }

    @MainActor
    private func isCurrentTransition(_ transition: UInt) -> Bool {
        transitionGeneration == transition
    }

    @MainActor
    private func ensureCurrentTransition(_ transition: UInt) throws {
        guard isCurrentTransition(transition) else {
            throw AuthSessionTransitionError.backendSessionChanged
        }
    }

    private func isRecoverableMultiFactorCodeError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard let code = AuthErrorCode(rawValue: nsError.code) else { return false }
        return code == .invalidVerificationCode || code == .missingVerificationCode
    }

    private func isExpiredMultiFactorChallenge(_ error: Error) -> Bool {
        let nsError = error as NSError
        return AuthErrorCode(rawValue: nsError.code) == .sessionExpired
    }

    private func readableSessionFailure(_ error: Error) -> String {
        if error is AuthVerificationError {
            return mapVerificationFlowMessage(for: error)
        }

        return AppStrings.Auth.loadUserProfileFailed
    }

    private func isMissingProfileError(_ error: Error) -> Bool {
        guard let appError = error as? AppError else { return false }
        return appError == .notFound
    }

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
