import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
@Suite("Auth session consistency")
struct AuthSessionConsistencyTests {
    @Test
    func failedProfileLoadAfterSignInRollsBackFirebaseSession() async {
        let state = AuthState()
        state.setGuestSession()
        let firebaseUser = FakeAuthSessionUser(uid: "user-a", email: "a@example.com", isEmailVerified: true)
        let backend = FakeAuthBackend(signInUser: firebaseUser)
        let profiles = FakeAuthProfileProvider(fetchError: AppError.network)
        let service = makeService(state: state, backend: backend, profiles: profiles)

        do {
            _ = try await service.signIn(email: "a@example.com", password: "password")
            Issue.record("Expected profile loading to fail")
        } catch {}

        #expect(backend.currentSessionUser?.uid == nil)
        #expect(backend.signOutCallCount == 1)
        #expect(state.sessionState == .guest)
        #expect(state.user == nil)
        #expect(state.pendingSessionUserID == nil)
    }

    @Test
    func unverifiedEmailRetainsFirebaseSessionAsVerificationPending() async {
        let state = AuthState()
        state.setGuestSession()
        let firebaseUser = FakeAuthSessionUser(uid: "user-a", email: "a@example.com", isEmailVerified: false)
        let backend = FakeAuthBackend(signInUser: firebaseUser)
        let profiles = FakeAuthProfileProvider()
        let service = makeService(state: state, backend: backend, profiles: profiles)

        do {
            _ = try await service.signIn(email: "a@example.com", password: "password")
            Issue.record("Expected email verification to remain pending")
        } catch AuthVerificationError.emailNotVerified {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(backend.currentSessionUser?.uid == "user-a")
        #expect(backend.signOutCallCount == 0)
        #expect(profiles.fetchCallCount == 0)
        #expect(state.sessionState == .verificationPending)
        #expect(state.pendingSessionUserID == "user-a")
        #expect(state.pendingVerificationEmail == "a@example.com")
        #expect(state.presentedAuthFlow == .emailVerification)
        #expect(state.user == nil)
    }

    @Test
    func failedPostLoginVerificationRollsBackFirebaseSession() async {
        let state = AuthState()
        state.setGuestSession()
        let firebaseUser = FakeAuthSessionUser(uid: "user-a", email: "a@example.com", isEmailVerified: true)
        firebaseUser.tokenRefreshError = FakeAuthError.expected
        let backend = FakeAuthBackend(signInUser: firebaseUser)
        let service = makeService(state: state, backend: backend, profiles: FakeAuthProfileProvider())

        do {
            _ = try await service.signIn(email: "a@example.com", password: "password")
            Issue.record("Expected token refresh to fail")
        } catch {}

        #expect(backend.currentSessionUser?.uid == nil)
        #expect(backend.signOutCallCount == 1)
        #expect(state.sessionState == .guest)
        #expect(state.user == nil)
    }

    @Test
    func restoreNetworkFailureRetainsFirebaseSessionInBlockedRecoveryState() async {
        let state = AuthState()
        let firebaseUser = FakeAuthSessionUser(uid: "user-a", email: "a@example.com", isEmailVerified: true)
        let backend = FakeAuthBackend(currentUser: firebaseUser)
        let profiles = FakeAuthProfileProvider(fetchError: AppError.network)
        let service = makeService(state: state, backend: backend, profiles: profiles)

        await service.restoreSession()

        #expect(backend.currentSessionUser?.uid == "user-a")
        #expect(backend.signOutCallCount == 0)
        #expect(state.sessionState == .sessionUnavailable)
        #expect(state.isGuest == false)
        #expect(state.isAuthenticated == false)
        #expect(state.pendingSessionUserID == "user-a")
        #expect(state.user == nil)
        #expect(state.presentedAuthFlow == .sessionRecovery)
    }

    @Test
    func failedAnonymousCleanupDuringRestoreDoesNotPublishFalseGuest() async {
        let state = AuthState()
        let firebaseUser = FakeAuthSessionUser(
            uid: "anonymous-user",
            email: nil,
            isAnonymous: true,
            isEmailVerified: false
        )
        let backend = FakeAuthBackend(currentUser: firebaseUser)
        backend.signOutError = FakeAuthError.expected
        let service = makeService(
            state: state,
            backend: backend,
            profiles: FakeAuthProfileProvider()
        )

        await service.restoreSession()

        #expect(backend.currentSessionUser?.uid == firebaseUser.uid)
        #expect(state.sessionState == .sessionUnavailable)
        #expect(state.isGuest == false)
        #expect(state.pendingSessionUserID == firebaseUser.uid)
        #expect(state.presentedAuthFlow == .sessionRecovery)
    }

    @Test
    func failedRollbackNeverPublishesGuestWhileFirebaseUserRemains() async {
        let state = AuthState()
        state.setGuestSession()
        let firebaseUser = FakeAuthSessionUser(uid: "user-a", email: "a@example.com", isEmailVerified: true)
        let backend = FakeAuthBackend(signInUser: firebaseUser)
        backend.signOutError = FakeAuthError.expected
        let profiles = FakeAuthProfileProvider(fetchError: AppError.network)
        let service = makeService(state: state, backend: backend, profiles: profiles)

        do {
            _ = try await service.signIn(email: "a@example.com", password: "password")
            Issue.record("Expected profile loading to fail")
        } catch {}

        #expect(backend.currentSessionUser?.uid == "user-a")
        #expect(state.sessionState == .sessionUnavailable)
        #expect(state.isGuest == false)
        #expect(state.pendingSessionUserID == "user-a")
        #expect(state.presentedAuthFlow == .sessionRecovery)
    }

    @Test
    func logoutClearsBackendAndPublishedUserAtomically() async {
        let appUser = makeUser(id: "user-a")
        let state = AuthState()
        state.setAuthenticatedSession(user: appUser)
        let firebaseUser = FakeAuthSessionUser(uid: appUser.id, email: appUser.email, isEmailVerified: true)
        let backend = FakeAuthBackend(currentUser: firebaseUser)
        let notifications = FakeAuthNotificationRegistration()
        let service = makeService(
            state: state,
            backend: backend,
            profiles: FakeAuthProfileProvider(profiles: [appUser.id: appUser]),
            notifications: notifications
        )

        let didSignOut = await service.signOut()

        #expect(didSignOut)
        #expect(backend.currentSessionUser?.uid == nil)
        #expect(state.sessionState == .guest)
        #expect(state.user == nil)
        #expect(notifications.prepareCallCount == 1)
        #expect(notifications.completeCallCount == 1)
        #expect(notifications.resumeCallCount == 0)
    }

    @Test
    func accountDeletionSignOutWaitsForSuspendedSignInBeforeClearingBackend() async {
        let state = AuthState()
        state.setGuestSession()
        let firebaseUser = FakeAuthSessionUser(
            uid: "user-a",
            email: "a@example.com",
            isEmailVerified: true
        )
        let suspendedBackendSignIn = SuspensionGate()
        let backend = FakeAuthBackend()
        backend.signInHandler = { _, _ in
            await suspendedBackendSignIn.suspend()
            return firebaseUser
        }
        let notifications = FakeAuthNotificationRegistration()
        let service = makeService(
            state: state,
            backend: backend,
            profiles: FakeAuthProfileProvider(),
            notifications: notifications
        )

        let staleSignIn = Task { @MainActor in
            do {
                _ = try await service.signIn(email: "a@example.com", password: "password")
            } catch {}
        }
        await suspendedBackendSignIn.waitUntilSuspended()

        let releaseBackendSignIn = Task { @MainActor in
            await Task.yield()
            await suspendedBackendSignIn.resume()
        }
        let didSignOut = await service.completeAccountDeletionSignOut()
        await releaseBackendSignIn.value
        await staleSignIn.value

        #expect(didSignOut)
        #expect(backend.currentSessionUser == nil)
        #expect(backend.signOutCallCount == 1)
        #expect(state.sessionState == .guest)
        #expect(state.user == nil)
        #expect(notifications.completeCallCount == 1)
    }

    @Test
    func accountSwitchPublishesOnlyNewUserAndRejectsStaleRefresh() async throws {
        let oldAppUser = makeUser(id: "user-a")
        let newAppUser = makeUser(id: "user-b")
        let state = AuthState()
        state.setAuthenticatedSession(user: oldAppUser)

        let oldFirebaseUser = FakeAuthSessionUser(uid: oldAppUser.id, email: oldAppUser.email, isEmailVerified: true)
        let newFirebaseUser = FakeAuthSessionUser(uid: newAppUser.id, email: newAppUser.email, isEmailVerified: true)
        let backend = FakeAuthBackend(currentUser: oldFirebaseUser, signInUser: newFirebaseUser)
        let notifications = FakeAuthNotificationRegistration()
        let profiles = FakeAuthProfileProvider(profiles: [newAppUser.id: newAppUser])
        let service = makeService(
            state: state,
            backend: backend,
            profiles: profiles,
            notifications: notifications
        )

        let signedInUser = try await service.signIn(email: newAppUser.email, password: "password")
        let acceptedStaleRefresh = state.updateAuthenticatedUser(oldAppUser)

        #expect(signedInUser.id == newAppUser.id)
        #expect(backend.currentSessionUser?.uid == newAppUser.id)
        #expect(state.sessionState == .authenticated)
        #expect(state.user?.id == newAppUser.id)
        #expect(acceptedStaleRefresh == false)
        #expect(notifications.prepareCallCount == 1)
        #expect(notifications.completeCallCount == 1)
    }

    @Test
    func staleRestoreCompletionDoesNotOverwriteNewerAuthenticatedSession() async throws {
        let oldAppUser = makeUser(id: "user-a")
        let newAppUser = makeUser(id: "user-b")
        let oldFirebaseUser = FakeAuthSessionUser(
            uid: oldAppUser.id,
            email: oldAppUser.email,
            isEmailVerified: true
        )
        let newFirebaseUser = FakeAuthSessionUser(
            uid: newAppUser.id,
            email: newAppUser.email,
            isEmailVerified: true
        )
        let state = AuthState()
        let backend = FakeAuthBackend(currentUser: oldFirebaseUser, signInUser: newFirebaseUser)
        let oldProfileFetch = SuspensionGate()
        let profiles = FakeAuthProfileProvider(profiles: [
            oldAppUser.id: oldAppUser,
            newAppUser.id: newAppUser
        ])
        profiles.fetchHandler = { uid in
            if uid == oldAppUser.id {
                await oldProfileFetch.suspend()
            }
            guard let profile = profiles.profiles[uid] else { throw AppError.notFound }
            return profile
        }
        let service = makeService(state: state, backend: backend, profiles: profiles)

        let staleRestore = Task { @MainActor in
            await service.restoreSession()
        }
        await oldProfileFetch.waitUntilSuspended()

        let signedInUser = try await service.signIn(
            email: newAppUser.email,
            password: "password"
        )
        #expect(signedInUser.id == newAppUser.id)
        #expect(state.sessionState == .authenticated)

        await oldProfileFetch.resume()
        await staleRestore.value

        #expect(backend.currentSessionUser?.uid == newAppUser.id)
        #expect(backend.signOutCallCount == 1)
        #expect(state.sessionState == .authenticated)
        #expect(state.user?.id == newAppUser.id)
        #expect(state.presentedAuthFlow == nil)
    }

    @Test
    func staleSignInCompletionDoesNotOverwriteNewerAuthenticatedSession() async throws {
        let oldAppUser = makeUser(id: "user-a")
        let newAppUser = makeUser(id: "user-b")
        let oldFirebaseUser = FakeAuthSessionUser(
            uid: oldAppUser.id,
            email: oldAppUser.email,
            isEmailVerified: true
        )
        let newFirebaseUser = FakeAuthSessionUser(
            uid: newAppUser.id,
            email: newAppUser.email,
            isEmailVerified: true
        )
        let state = AuthState()
        state.setGuestSession()
        let backend = FakeAuthBackend(signInUser: oldFirebaseUser)
        let oldProfileFetch = SuspensionGate()
        let profiles = FakeAuthProfileProvider(profiles: [
            oldAppUser.id: oldAppUser,
            newAppUser.id: newAppUser
        ])
        profiles.fetchHandler = { uid in
            if uid == oldAppUser.id {
                await oldProfileFetch.suspend()
            }
            guard let profile = profiles.profiles[uid] else { throw AppError.notFound }
            return profile
        }
        let service = makeService(state: state, backend: backend, profiles: profiles)

        let staleSignIn = Task { @MainActor in
            do {
                _ = try await service.signIn(email: oldAppUser.email, password: "password")
            } catch {}
        }
        await oldProfileFetch.waitUntilSuspended()

        backend.signInUser = newFirebaseUser
        let signedInUser = try await service.signIn(
            email: newAppUser.email,
            password: "password"
        )
        #expect(signedInUser.id == newAppUser.id)
        #expect(state.sessionState == .authenticated)

        await oldProfileFetch.resume()
        await staleSignIn.value

        #expect(backend.currentSessionUser?.uid == newAppUser.id)
        #expect(backend.signOutCallCount == 1)
        #expect(state.sessionState == .authenticated)
        #expect(state.user?.id == newAppUser.id)
        #expect(state.presentedAuthFlow == nil)
    }

    @Test
    func staleSameUserFailureDoesNotSignOutNewerSession() async throws {
        let appUser = makeUser(id: "user-a")
        let oldFirebaseUser = FakeAuthSessionUser(
            uid: appUser.id,
            email: appUser.email,
            isEmailVerified: true
        )
        let newFirebaseUser = FakeAuthSessionUser(
            uid: appUser.id,
            email: appUser.email,
            isEmailVerified: true
        )
        let state = AuthState()
        state.setGuestSession()
        let backend = FakeAuthBackend(signInUser: oldFirebaseUser)
        let oldProfileFetch = SuspensionGate()
        let fetchSequence = SameUserProfileFetchSequence(
            firstFetchGate: oldProfileFetch,
            succeedingProfile: appUser,
            succeedingProfileID: appUser.id
        )
        let profiles = FakeAuthProfileProvider()
        profiles.fetchHandler = { uid in
            try await fetchSequence.fetch(uid: uid)
        }
        let service = makeService(state: state, backend: backend, profiles: profiles)

        let staleSignIn = Task { @MainActor in
            do {
                _ = try await service.signIn(email: appUser.email, password: "password")
            } catch {}
        }
        await oldProfileFetch.waitUntilSuspended()

        backend.signInUser = newFirebaseUser
        let signedInUser = try await service.signIn(
            email: appUser.email,
            password: "password"
        )
        #expect(signedInUser.id == appUser.id)
        #expect(backend.signOutCallCount == 1)

        await oldProfileFetch.resume()
        await staleSignIn.value

        #expect(backend.currentSessionUser?.uid == appUser.id)
        #expect(backend.signOutCallCount == 1)
        #expect(state.sessionState == .authenticated)
        #expect(state.user?.id == appUser.id)
        #expect(state.presentedAuthFlow == nil)
    }

    @Test
    func failedAuthenticatedProfileRefreshKeepsExistingUser() async {
        let appUser = makeUser(id: "user-a")
        let state = AuthState(userProfileLoader: { _ in throw AppError.network })
        state.setAuthenticatedSession(user: appUser)

        await state.loadUser(uid: appUser.id)

        #expect(state.sessionState == .authenticated)
        #expect(state.user?.id == appUser.id)
        #expect(state.errorMessage == AppStrings.Auth.loadUserProfileFailed)
    }

    @Test
    func failedRegistrationProfileCreationRollsBackCreatedAccountSession() async {
        let state = AuthState()
        state.setGuestSession()
        let firebaseUser = FakeAuthSessionUser(
            uid: "new-user",
            email: "new@example.com",
            isEmailVerified: false
        )
        let backend = FakeAuthBackend()
        backend.createUserResult = firebaseUser
        let profiles = FakeAuthProfileProvider(createError: AppError.network)
        let service = makeService(state: state, backend: backend, profiles: profiles)

        do {
            try await service.register(draft: makeDraft(), password: "password")
            Issue.record("Expected profile creation to fail")
        } catch RegistrationError.profileNetwork {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(firebaseUser.deletedAccountCount == 1)
        #expect(backend.signOutCallCount == 1)
        #expect(backend.currentSessionUser?.uid == nil)
        #expect(state.sessionState == .guest)
        #expect(state.user == nil)
    }

    @Test
    func staleRegistrationDeletionCannotClearNewerAuthenticatedSession() async throws {
        let newAppUser = makeUser(id: "user-b")
        let registrationUser = FakeAuthSessionUser(
            uid: "new-user",
            email: "new@example.com",
            isEmailVerified: false
        )
        let authenticatedUser = FakeAuthSessionUser(
            uid: newAppUser.id,
            email: newAppUser.email,
            isEmailVerified: true
        )
        let state = AuthState()
        state.setGuestSession()
        let backend = FakeAuthBackend()
        backend.createUserResult = registrationUser
        let suspendedDeletion = SuspensionGate()
        registrationUser.deleteHandler = {
            await suspendedDeletion.suspend()
            backend.currentSessionUser = nil
        }
        let profiles = FakeAuthProfileProvider(
            profiles: [newAppUser.id: newAppUser],
            createError: AppError.network
        )
        let service = makeService(state: state, backend: backend, profiles: profiles)

        let staleRegistration = Task { @MainActor in
            do {
                try await service.register(draft: makeDraft(), password: "password")
            } catch {}
        }
        await suspendedDeletion.waitUntilSuspended()

        backend.signInUser = authenticatedUser
        let newerSignIn = Task { @MainActor in
            try await service.signIn(email: newAppUser.email, password: "password")
        }
        let releaseDeletion = Task { @MainActor in
            await Task.yield()
            await suspendedDeletion.resume()
        }

        let signedInUser = try await newerSignIn.value
        await releaseDeletion.value
        await staleRegistration.value

        #expect(signedInUser.id == newAppUser.id)
        #expect(registrationUser.deletedAccountCount == 1)
        #expect(backend.currentSessionUser?.uid == newAppUser.id)
        #expect(backend.signOutCallCount == 1)
        #expect(state.sessionState == .authenticated)
        #expect(state.user?.id == newAppUser.id)
        #expect(state.presentedAuthFlow == nil)
    }

    @Test
    func failedRegistrationVerificationEmailKeepsPendingFirebaseSession() async throws {
        let state = AuthState()
        state.setGuestSession()
        let firebaseUser = FakeAuthSessionUser(
            uid: "new-user",
            email: "new@example.com",
            isEmailVerified: false
        )
        firebaseUser.verificationEmailError = FakeAuthError.expected
        let backend = FakeAuthBackend()
        backend.createUserResult = firebaseUser
        let profiles = FakeAuthProfileProvider()
        let service = makeService(state: state, backend: backend, profiles: profiles)

        try await service.register(draft: makeDraft(), password: "password")

        #expect(backend.currentSessionUser?.uid == firebaseUser.uid)
        #expect(backend.signOutCallCount == 0)
        #expect(profiles.createCallCount == 1)
        #expect(state.sessionState == .verificationPending)
        #expect(state.pendingSessionUserID == firebaseUser.uid)
        #expect(state.presentedAuthFlow == .emailVerification)
        #expect(state.errorMessage == AppStrings.Auth.emailVerificationResendFailed)
    }

    private func makeService(
        state: AuthState,
        backend: FakeAuthBackend,
        profiles: FakeAuthProfileProvider,
        notifications: FakeAuthNotificationRegistration? = nil
    ) -> AuthService {
        let resolvedNotifications: FakeAuthNotificationRegistration
        if let notifications {
            resolvedNotifications = notifications
        } else {
            resolvedNotifications = FakeAuthNotificationRegistration()
        }

        return AuthService(
            authState: state,
            backend: backend,
            profileProvider: profiles,
            notificationRegistration: resolvedNotifications
        )
    }

    private func makeUser(id: String) -> AppUser {
        AppUser(
            id: id,
            fullName: "Test User",
            displayName: "Test User",
            city: "Vienna",
            email: "\(id)@example.com",
            bio: "",
            role: .user,
            blockState: .active,
            createdAt: .now,
            updatedAt: .now
        )
    }

    private func makeDraft() -> RegistrationProfileDraft {
        RegistrationProfileDraft(
            email: "new@example.com",
            displayName: "New User",
            telegramUsername: nil,
            selectedFederalState: .tirol,
            acceptedTermsAt: .now,
            acceptedPrivacyAt: .now,
            termsVersion: AuthService.currentTermsVersion,
            privacyVersion: AuthService.currentPrivacyVersion
        )
    }
}

private enum FakeAuthError: Error {
    case expected
}

private final class FakeAuthSessionUser: AuthSessionUserProviding {
    let uid: String
    let email: String?
    let isAnonymous: Bool
    var isEmailVerified: Bool
    var reloadError: Error?
    var tokenRefreshError: Error?
    var verificationEmailError: Error?
    var displayNameError: Error?
    var deleteError: Error?
    var deleteHandler: (() async throws -> Void)?
    private(set) var sentVerificationEmailCount = 0
    private(set) var deletedAccountCount = 0

    init(
        uid: String,
        email: String?,
        isAnonymous: Bool = false,
        isEmailVerified: Bool
    ) {
        self.uid = uid
        self.email = email
        self.isAnonymous = isAnonymous
        self.isEmailVerified = isEmailVerified
    }

    func reload() async throws {
        if let reloadError { throw reloadError }
    }

    func refreshIDToken() async throws {
        if let tokenRefreshError { throw tokenRefreshError }
    }

    func sendVerificationEmail() async throws {
        if let verificationEmailError { throw verificationEmailError }
        sentVerificationEmailCount += 1
    }

    func updateDisplayName(_ displayName: String) async throws {
        if let displayNameError { throw displayNameError }
    }

    func deleteAccount() async throws {
        if let deleteError { throw deleteError }
        if let deleteHandler {
            try await deleteHandler()
        }
        deletedAccountCount += 1
    }
}

private final class FakeAuthBackend: AuthBackendProviding {
    var currentSessionUser: (any AuthSessionUserProviding)?
    var signInUser: (any AuthSessionUserProviding)?
    var createUserResult: (any AuthSessionUserProviding)?
    var anonymousUser: (any AuthSessionUserProviding)?
    var signInHandler: ((String, String) async throws -> any AuthSessionUserProviding)?
    var signInError: Error?
    var createUserError: Error?
    var anonymousSignInError: Error?
    var passwordResetError: Error?
    var signOutError: Error?
    private(set) var signOutCallCount = 0

    init(
        currentUser: (any AuthSessionUserProviding)? = nil,
        signInUser: (any AuthSessionUserProviding)? = nil
    ) {
        currentSessionUser = currentUser
        self.signInUser = signInUser
    }

    func signIn(email: String, password: String) async throws -> any AuthSessionUserProviding {
        if let signInError { throw signInError }
        let resolvedUser: any AuthSessionUserProviding
        if let signInHandler {
            resolvedUser = try await signInHandler(email, password)
        } else {
            guard let signInUser else { throw FakeAuthError.expected }
            resolvedUser = signInUser
        }
        currentSessionUser = resolvedUser
        return resolvedUser
    }

    func createUser(email: String, password: String) async throws -> any AuthSessionUserProviding {
        if let createUserError { throw createUserError }
        guard let createUserResult else { throw FakeAuthError.expected }
        currentSessionUser = createUserResult
        return createUserResult
    }

    func signInAnonymously() async throws -> any AuthSessionUserProviding {
        if let anonymousSignInError { throw anonymousSignInError }
        guard let anonymousUser else { throw FakeAuthError.expected }
        currentSessionUser = anonymousUser
        return anonymousUser
    }

    func sendPasswordReset(email: String) async throws {
        if let passwordResetError { throw passwordResetError }
    }

    func signOut() throws {
        signOutCallCount += 1
        if let signOutError { throw signOutError }
        currentSessionUser = nil
    }
}

private final class FakeAuthProfileProvider: AuthProfileProviding {
    var profiles: [String: AppUser]
    var fetchError: Error?
    var createError: Error?
    var fetchHandler: ((String) async throws -> AppUser)?
    private(set) var fetchCallCount = 0
    private(set) var createCallCount = 0

    init(
        profiles: [String: AppUser] = [:],
        fetchError: Error? = nil,
        createError: Error? = nil
    ) {
        self.profiles = profiles
        self.fetchError = fetchError
        self.createError = createError
    }

    func createRegisteredUserDocument(for uid: String, draft: RegistrationProfileDraft) async throws {
        createCallCount += 1
        if let createError { throw createError }
    }

    func fetchExistingUserProfile(uid: String) async throws -> AppUser {
        fetchCallCount += 1
        if let fetchHandler {
            return try await fetchHandler(uid)
        }
        if let fetchError { throw fetchError }
        guard let profile = profiles[uid] else { throw AppError.notFound }
        return profile
    }
}

private actor SuspensionGate {
    private var suspendedContinuation: CheckedContinuation<Void, Never>?
    private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []

    func suspend() async {
        await withCheckedContinuation { continuation in
            precondition(suspendedContinuation == nil)
            suspendedContinuation = continuation

            let waiters = suspensionWaiters
            suspensionWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }
    }

    func waitUntilSuspended() async {
        guard suspendedContinuation == nil else { return }
        await withCheckedContinuation { continuation in
            suspensionWaiters.append(continuation)
        }
    }

    func resume() {
        guard let continuation = suspendedContinuation else {
            preconditionFailure("Expected a suspended operation")
        }
        suspendedContinuation = nil
        continuation.resume()
    }
}

private actor SameUserProfileFetchSequence {
    private let firstFetchGate: SuspensionGate
    private let succeedingProfile: AppUser
    private let succeedingProfileID: String
    private var fetchCount = 0

    init(
        firstFetchGate: SuspensionGate,
        succeedingProfile: AppUser,
        succeedingProfileID: String
    ) {
        self.firstFetchGate = firstFetchGate
        self.succeedingProfile = succeedingProfile
        self.succeedingProfileID = succeedingProfileID
    }

    func fetch(uid: String) async throws -> AppUser {
        fetchCount += 1
        if fetchCount == 1 {
            await firstFetchGate.suspend()
            throw FakeAuthError.expected
        }

        guard succeedingProfileID == uid else { throw AppError.notFound }
        return succeedingProfile
    }
}

@MainActor
private final class FakeAuthNotificationRegistration: AuthNotificationRegistrationProviding {
    var prepareError: Error?
    private(set) var prepareCallCount = 0
    private(set) var completeCallCount = 0
    private(set) var resumeCallCount = 0

    func prepareForSignOut() async throws {
        prepareCallCount += 1
        if let prepareError { throw prepareError }
    }

    func completeSignOut() {
        completeCallCount += 1
    }

    func resumeAfterFailedSignOut() async {
        resumeCallCount += 1
    }
}
