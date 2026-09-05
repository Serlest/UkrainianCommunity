package at.uac.android

import at.uac.android.feature.auth.*
import com.google.firebase.FirebaseException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class AuthSessionTest {
    private val terms =
        AuthLegalDocument(
            "terms",
            AuthRegistration.TERMS_VERSION,
            true,
            mapOf("de" to "Terms"),
            mapOf("de" to "Complete text"),
        )
    private val privacy =
        AuthLegalDocument(
            "privacy",
            AuthRegistration.PRIVACY_VERSION,
            false,
            mapOf("de" to "Privacy"),
            mapOf("de" to "Complete text"),
        )

    private fun identity(uid: String = "a", verified: Boolean = true) =
        AuthIdentity(uid, "$uid@example.invalid", verified)

    private fun profile(uid: String = "a") =
        AuthProfile(
            uid,
            "$uid@example.invalid",
            "Test $uid",
            region = "wien",
            acceptedTermsVersion = AuthRegistration.TERMS_VERSION,
            acceptedPrivacyVersion = AuthRegistration.PRIVACY_VERSION,
        )

    private fun draft() =
        AuthRegistration(
            "new@example.invalid",
            "Test Person",
            "tirol",
            "@test_user",
            true,
            true,
            true,
        )

    @Test
    fun validationKeepsPasswordAgeRegionAndExplicitConsentPolicy() {
        assertNull(AuthValidation.registration(draft(), "1234567890", "1234567890"))
        assertEquals(AuthProblem.WEAK_PASSWORD, AuthValidation.password("123456789"))
        assertEquals(AuthProblem.WEAK_PASSWORD, AuthValidation.password("a".repeat(129)))
        assertEquals(
            AuthProblem.PASSWORD_MISMATCH,
            AuthValidation.registration(draft(), "1234567890", "1234567891"),
        )
        assertEquals(
            AuthProblem.CONSENT_REQUIRED,
            AuthValidation.registration(
                draft().copy(minimumAgeConfirmed = false),
                "1234567890",
                "1234567890",
            ),
        )
        assertEquals(
            AuthProblem.REGION_REQUIRED,
            AuthValidation.registration(
                draft().copy(region = "unknown"),
                "1234567890",
                "1234567890",
            ),
        )
        assertEquals(AuthProblem.INVALID_EMAIL, AuthValidation.email("a@example invalid"))
        assertEquals(
            AuthProblem.NAME_REQUIRED,
            AuthValidation.registration(
                draft().copy(displayName = " "),
                "1234567890",
                "1234567890",
            ),
        )
    }

    @Test
    fun registrationMapMatchesRulesAndNeverGrantsRoleOrConsentSdkAuthority() {
        val timestamp = Any()
        val fields = registeredProfileFields("a", draft().copy(analyticsOptIn = true), timestamp)
        assertEquals(24, fields.size)
        assertEquals("user", fields["globalRole"])
        assertEquals("active", fields["accountStatus"])
        assertEquals("14+", fields["minimumAgeVersion"])
        assertEquals("test_user", fields["telegramUsername"])
        for (key in
            listOf(
                "createdAt",
                "updatedAt",
                "minimumAgeConfirmedAt",
                "acceptedTermsAt",
                "acceptedPrivacyAt",
            )) assertSame(timestamp, fields[key])
        for (forbidden in
            listOf(
                "role",
                "requiresMultiFactorAuth",
                "analyticsConsentEnabled",
                "password",
                "token",
            )) assertFalse(fields.containsKey(forbidden))
    }

    @Test
    fun profileDecoderIgnoresLegacyRolesAndRejectsForeignIdentity() {
        val fields = registeredProfileFields("a", draft(), Any()).toMutableMap()
        fields["role"] = "owner"
        fields["globalRole"] = "topAdmin"
        val decoded = decodeProfile("a", fields)
        assertEquals("user", decoded.globalRole)
        assertFalse(decoded.privileged)
        assertThrows(AuthException::class.java) { decodeProfile("foreign", fields) }
        assertFalse(decoded.copy(accountStatus = "unknown").active)
        assertFalse(decoded.copy(blockState = "blocked").active)
    }

    @Test
    fun actionCodeRejectsOtherHostDuplicateModeAndWrongOperation() {
        assertEquals("abc_def-123", LocalAuthActionCode.parse("abc_def-123", "verifyEmail"))
        assertEquals(
            "abc123",
            LocalAuthActionCode.parse(
                "http://127.0.0.1:9098/emulator/action?mode=verifyEmail&oobCode=abc123",
                "verifyEmail",
            ),
        )
        for (url in
            listOf(
                "https://evil.invalid/?mode=verifyEmail&oobCode=abc123",
                "http://127.0.0.1:9098/?mode=resetPassword&oobCode=abc123",
                "http://127.0.0.1:9098/?mode=verifyEmail&oobCode=abc123&oobCode=other123",
                "http://user@127.0.0.1:9098/?mode=verifyEmail&oobCode=abc123",
            )) {
            assertThrows(AuthException::class.java) {
                LocalAuthActionCode.parse(url, "verifyEmail")
            }
        }
    }

    @Test
    fun knownEmulatorConnectionRefusalIsNetworkWithoutHidingUnrelatedInternalErrors() {
        assertTrue(
            isLocalAuthConnectionRefusal(
                FirebaseException::class.java,
                "An internal error has occurred. [ Failed to connect to /10.0.2.2:9098 ]",
            )
        )
        assertFalse(
            isLocalAuthConnectionRefusal(
                FirebaseException::class.java,
                "An internal error has occurred. [ Failed to connect to /other.invalid:443 ]",
            )
        )
        assertFalse(
            isLocalAuthConnectionRefusal(
                FirebaseException::class.java,
                "An internal error has occurred.",
            )
        )
        assertFalse(
            isLocalAuthConnectionRefusal(
                IllegalStateException::class.java,
                "An internal error has occurred. [ Failed to connect to /10.0.2.2:9098 ]",
            )
        )
    }

    @Test
    fun legalAndPrivilegeGatesFailClosedWithoutInventedReceipts() {
        val user = profile()
        assertEquals(AuthGate.READY, gateFor(user, false, listOf(terms, privacy)))
        assertEquals(
            AuthGate.LEGAL_REQUIRED,
            gateFor(user.copy(acceptedTermsVersion = "old"), false, listOf(terms, privacy)),
        )
        assertEquals(AuthGate.LEGAL_UNAVAILABLE, gateFor(user, false, null))
        assertEquals(AuthGate.LEGAL_UNAVAILABLE, gateFor(user, false, listOf(terms)))
        assertEquals(
            AuthGate.RESTRICTED,
            gateFor(user.copy(accountStatus = "suspendedUntil"), true, listOf(terms, privacy)),
        )
        assertEquals(
            AuthGate.MFA_REQUIRED,
            gateFor(user.copy(globalRole = "owner"), true, listOf(terms, privacy)),
        )
        assertEquals(
            AuthGate.MFA_REQUIRED,
            gateFor(
                user.copy(globalRole = "admin", requiresMultiFactorAuth = true),
                false,
                listOf(terms, privacy),
            ),
        )
        assertEquals(
            AuthGate.READY,
            gateFor(
                user.copy(globalRole = "admin", requiresMultiFactorAuth = true),
                true,
                listOf(terms, privacy),
            ),
        )
    }

    @Test
    fun guestRestoreNeverCreatesAnonymousAccount() = runTest {
        val backend = FakeBackend()
        val store = AuthStore(backend, FakeProfiles(), backgroundScope)
        store.restore().join()
        assertEquals(AuthStage.GUEST, store.state.value.stage)
        assertEquals(0, backend.createCount)
    }

    @Test
    fun unverifiedSessionDoesNotReadPrivateProfileOrOpenActions() = runTest {
        val backend = FakeBackend(identity(verified = false))
        val profiles = FakeProfiles()
        val store = AuthStore(backend, profiles, backgroundScope)
        store.restore().join()
        assertEquals(AuthStage.VERIFICATION_PENDING, store.state.value.stage)
        assertEquals(0, profiles.fetchCount)
        assertFalse(store.state.value.readyForActions)
        assertNotNull(backend.current)
    }

    @Test
    fun refreshTokenMustSucceedBeforeVerifiedProfileCanPublish() = runTest {
        val backend = FakeBackend(identity()).apply { tokenProblem = AuthProblem.NETWORK }
        val profiles = FakeProfiles()
        val store = AuthStore(backend, profiles, backgroundScope)
        store.restore().join()
        assertEquals(AuthStage.SESSION_UNAVAILABLE, store.state.value.stage)
        assertEquals(0, profiles.fetchCount)
        assertNotNull(backend.current)
        backend.tokenProblem = null
        store.retryUnavailable().join()
        assertTrue(store.state.value.readyForActions)
    }

    @Test
    fun offlineProfileIsUnavailableNotGuestAndRetryRestoresSameUid() = runTest {
        val backend = FakeBackend(identity())
        val profiles = FakeProfiles().apply { problem = AuthProblem.NETWORK }
        val store = AuthStore(backend, profiles, backgroundScope)
        store.restore().join()
        assertEquals(AuthStage.SESSION_UNAVAILABLE, store.state.value.stage)
        assertEquals("a", store.state.value.identity?.uid)
        assertNull(store.state.value.profile)
        profiles.problem = null
        store.retryUnavailable().join()
        assertTrue(store.state.value.readyForActions)
    }

    @Test
    fun missingProfileIsNotRecreatedDuringLogin() = runTest {
        val backend = FakeBackend(identity())
        val profiles = FakeProfiles().apply { problem = AuthProblem.PROFILE_MISSING }
        val store = AuthStore(backend, profiles, backgroundScope)
        store.restore().join()
        assertEquals(AuthStage.GUEST, store.state.value.stage)
        assertNull(backend.current)
        assertEquals(0, profiles.createCount)
    }

    @Test
    fun foreignProfileAndUnknownLegalStatusCannotPublishReadySession() = runTest {
        val profiles = FakeProfiles().apply { result = profile("foreign") }
        val store = AuthStore(FakeBackend(identity()), profiles, backgroundScope)
        store.restore().join()
        assertEquals(AuthStage.SESSION_UNAVAILABLE, store.state.value.stage)
        profiles.result = profile()
        profiles.legalProblem = true
        store.retryUnavailable().join()
        assertEquals(AuthGate.LEGAL_UNAVAILABLE, store.state.value.gate)
        assertFalse(store.state.value.readyForActions)
    }

    @Test
    fun newerLoginWinsAndOldProtectedDataClearsImmediately() = runTest {
        val blocker = CompletableDeferred<Unit>()
        val backend =
            FakeBackend(identity()).apply {
                beforeSignIn = { if (it.startsWith("b@")) blocker.await() }
            }
        val profiles = FakeProfiles().apply { useRequestedUid = true }
        val store = AuthStore(backend, profiles, backgroundScope)
        store.restore().join()
        assertTrue(store.state.value.readyForActions)
        store.signIn("b@example.invalid", "1234567890")
        assertNull(store.state.value.profile)
        runCurrent()
        val newest = store.signIn("c@example.invalid", "1234567890")!!
        blocker.complete(Unit)
        newest.join()
        assertEquals("c", backend.current?.uid)
        assertEquals("c", store.state.value.profile?.uid)
        assertTrue(store.state.value.readyForActions)
    }

    @Test
    fun logoutSupersedesInFlightLoginWithoutGhostSession() = runTest {
        val blocker = CompletableDeferred<Unit>()
        val backend = FakeBackend().apply { beforeSignIn = { blocker.await() } }
        val store = AuthStore(backend, FakeProfiles(), backgroundScope)
        store.restore().join()
        store.signIn("a@example.invalid", "1234567890")
        runCurrent()
        val out = store.signOut()
        blocker.complete(Unit)
        out.join()
        assertEquals(AuthStage.GUEST, store.state.value.stage)
        assertNull(backend.current)
    }

    @Test
    fun cancelledRegistrationCleansOnlyItsNewIdentityBeforeNextTransition() = runTest {
        val blocker = CompletableDeferred<Unit>()
        val backend = FakeBackend().apply { beforeCreate = { blocker.await() } }
        val profiles = FakeProfiles()
        val store = AuthStore(backend, profiles, backgroundScope)
        store.register(draft(), "1234567890", "1234567890", "de")
        runCurrent()
        val out = store.signOut()
        blocker.complete(Unit)
        out.join()
        assertEquals(listOf("new"), backend.deleted)
        assertEquals(0, profiles.createCount)
        assertEquals(AuthStage.GUEST, store.state.value.stage)
    }

    @Test
    fun serializedPersonalMutationKeepsOldIdentityUntilActualSdkCompletion() = runTest {
        val blocker = CompletableDeferred<Unit>()
        val backend = FakeBackend(identity())
        val store = AuthStore(backend, FakeProfiles(), backgroundScope)
        store.restore().join()
        val captured = store.state.value
        var actorAtCompletion: String? = null
        val mutation = backgroundScope.async {
            runCatching {
                store.withReadySession("a", captured.revision) {
                    blocker.await()
                    actorAtCompletion = backend.current?.uid
                }
            }
        }
        runCurrent()
        val logout = store.signOut()
        assertNull(store.state.value.profile)
        runCurrent()
        assertEquals("a", backend.current?.uid)
        blocker.complete(Unit)
        logout.join()
        assertEquals("a", actorAtCompletion)
        assertEquals(
            AuthProblem.SESSION_CHANGED,
            (mutation.await().exceptionOrNull() as AuthException).problem,
        )
        assertNull(backend.current)
    }

    @Test
    fun failedLogoutNeverPretendsBackendSessionIsGuest() = runTest {
        val backend = FakeBackend(identity()).apply { signOutProblem = AuthProblem.UNKNOWN }
        val store = AuthStore(backend, FakeProfiles(), backgroundScope)
        store.signOut().join()
        assertEquals(AuthStage.SESSION_UNAVAILABLE, store.state.value.stage)
        assertEquals("a", store.state.value.identity?.uid)
        assertFalse(store.state.value.readyForActions)
    }

    @Test
    fun narrowInboxGateAllowsRestrictedAndUnverifiedButNotGuestOrUnavailable() = runTest {
        for (verified in listOf(false, true)) {
            val profiles =
                FakeProfiles().apply { result = profile().copy(accountStatus = "bannedPermanent") }
            val store =
                AuthStore(FakeBackend(identity(verified = verified)), profiles, backgroundScope)
            store.restore().join()
            assertFalse(store.state.value.readyForActions)
            assertEquals(
                "own-notice",
                store.withInboxSession("a", store.state.value.revision) { "own-notice" },
            )
            val rejected = runCatching {
                store.withReadySession("a", store.state.value.revision) {
                    fail("No general mutation")
                }
            }
            assertEquals(
                AuthProblem.PERMISSION_DENIED,
                (rejected.exceptionOrNull() as AuthException).problem,
            )
        }
        val backend = FakeBackend(identity()).apply { tokenProblem = AuthProblem.NETWORK }
        val store = AuthStore(backend, FakeProfiles(), backgroundScope)
        store.restore().join()
        assertEquals(AuthStage.SESSION_UNAVAILABLE, store.state.value.stage)
        assertEquals(
            AuthProblem.PERMISSION_DENIED,
            (runCatching {
                    store.withInboxSession("a", store.state.value.revision) { fail("Unavailable") }
                }
                    .exceptionOrNull() as AuthException)
                .problem,
        )
        store.signOut().join()
        assertEquals(
            AuthProblem.SESSION_CHANGED,
            (runCatching {
                    store.withInboxSession("a", store.state.value.revision) { fail("Guest") }
                }
                    .exceptionOrNull() as AuthException)
                .problem,
        )
    }

    @Test
    fun inboxMutationAlsoKeepsIdentityUntilActualCompletionAndRejectsStaleRevision() = runTest {
        val blocker = CompletableDeferred<Unit>()
        val backend = FakeBackend(identity(verified = false))
        val store = AuthStore(backend, FakeProfiles(), backgroundScope)
        store.restore().join()
        val revision = store.state.value.revision
        var actor: String? = null
        val mutation = backgroundScope.async {
            runCatching {
                store.withInboxSession("a", revision) {
                    blocker.await()
                    actor = backend.current?.uid
                }
            }
        }
        runCurrent()
        val logout = store.signOut()
        runCurrent()
        assertEquals("a", backend.current?.uid)
        blocker.complete(Unit)
        logout.join()
        assertEquals("a", actor)
        assertEquals(
            AuthProblem.SESSION_CHANGED,
            (mutation.await().exceptionOrNull() as AuthException).problem,
        )
        assertNull(backend.current)
    }

    @Test
    fun readyGateCancelledConsumerWaitsForSdkCompletionBeforeQueuedLogin() =
        cancelledMutationRetainsIdentity(inbox = false, sdkFails = false)

    @Test
    fun readyGateCancelledConsumerDoesNotLeakLateSdkFailure() =
        cancelledMutationRetainsIdentity(inbox = false, sdkFails = true)

    @Test
    fun inboxGateCancelledConsumerWaitsForSdkCompletionBeforeQueuedLogin() =
        cancelledMutationRetainsIdentity(inbox = true, sdkFails = false)

    @Test
    fun inboxGateCancelledConsumerDoesNotLeakLateSdkFailure() =
        cancelledMutationRetainsIdentity(inbox = true, sdkFails = true)

    private fun cancelledMutationRetainsIdentity(inbox: Boolean, sdkFails: Boolean) = runTest {
        val backend = FakeBackend(identity(verified = !inbox))
        val profiles = FakeProfiles().apply { useRequestedUid = true }
        val store = AuthStore(backend, profiles, backgroundScope)
        store.restore().join()
        val revision = store.state.value.revision
        val sdkCompletion = CompletableDeferred<Unit>()
        var actualCompletionUid: String? = null
        var delivered = false
        var completionFailure: Throwable? = null
        val operation: suspend () -> Unit = {
            sdkCompletion.await()
            actualCompletionUid = backend.current?.uid
            if (sdkFails) throw AuthException(AuthProblem.NETWORK)
        }
        // This is a real child of the test scope: a late non-cancellation error
        // must fail this regression instead of being swallowed by runCatching.
        val mutation = async {
            if (inbox) store.withInboxSession("a", revision, operation)
            else store.withReadySession("a", revision, operation)
            delivered = true
        }
        mutation.invokeOnCompletion { completionFailure = it }
        runCurrent()
        mutation.cancel()
        val nextLogin = store.signIn("b@example.invalid", "password")!!
        runCurrent()
        assertEquals("a", backend.current?.uid)
        assertNull(actualCompletionUid)
        assertFalse(mutation.isCompleted)
        assertFalse(nextLogin.isCompleted)

        sdkCompletion.complete(Unit)
        mutation.join()
        nextLogin.join()
        assertEquals("a", actualCompletionUid)
        assertTrue(mutation.isCancelled)
        assertTrue(completionFailure is CancellationException)
        assertFalse(delivered)
        assertEquals("b", backend.current?.uid)
        assertEquals("b", store.state.value.identity?.uid)
        assertTrue(store.state.value.readyForActions)
    }

    @Test
    fun registrationEmailFailureRetainsPendingSessionAndSupportsResend() = runTest {
        var now = 100L
        val backend = FakeBackend().apply { sendProblem = AuthProblem.NETWORK }
        val profiles = FakeProfiles()
        val store = AuthStore(backend, profiles, backgroundScope) { now }
        store.register(draft(), "1234567890", "1234567890", "uk")!!.join()
        assertEquals(AuthStage.VERIFICATION_PENDING, store.state.value.stage)
        assertEquals(AuthProblem.NETWORK, store.state.value.error)
        assertEquals(1, profiles.createCount)
        backend.sendProblem = null
        store.resendVerification("uk")!!.join()
        assertEquals(AuthNotice.VERIFICATION_SENT, store.state.value.notice)
        assertNull(store.resendVerification("uk"))
        assertEquals(AuthProblem.RATE_LIMITED, store.state.value.error)
        now += 60_001
        store.resendVerification("de")!!.join()
        assertEquals(AuthNotice.VERIFICATION_SENT, store.state.value.notice)
    }

    @Test
    fun failedRegistrationWithConfirmedMissingProfileDeletesOnlyCreatedIdentity() = runTest {
        val backend = FakeBackend()
        val profiles =
            FakeProfiles().apply {
                createProblem = AuthProblem.PERMISSION_DENIED
                problem = AuthProblem.PROFILE_MISSING
            }
        val store = AuthStore(backend, profiles, backgroundScope)
        store.register(draft(), "1234567890", "1234567890", "de")!!.join()
        assertEquals(listOf("new"), backend.deleted)
        assertEquals(AuthStage.GUEST, store.state.value.stage)
    }

    @Test
    fun serverProfileRestrictionImmediatelyRevokesActions() = runTest {
        val events = MutableSharedFlow<Result<AuthProfile>>(extraBufferCapacity = 1)
        val profiles = FakeProfiles().apply { changes = events }
        val store = AuthStore(FakeBackend(identity()), profiles, backgroundScope)
        store.restore().join()
        runCurrent()
        assertTrue(store.state.value.readyForActions)
        events.emit(Result.success(profile().copy(accountStatus = "bannedPermanent")))
        runCurrent()
        assertEquals(AuthGate.RESTRICTED, store.state.value.gate)
        assertFalse(store.state.value.readyForActions)
    }

    @Test
    fun resetResponsesDoNotDiscloseMissingAccountAndResetClearsSession() = runTest {
        val backend = FakeBackend().apply { resetProblem = AuthProblem.INVALID_CREDENTIALS }
        val store = AuthStore(backend, FakeProfiles(), backgroundScope)
        store.restore().join()
        store.sendPasswordReset("missing@example.invalid", "uk")!!.join()
        assertEquals(AuthNotice.RESET_SENT, store.state.value.notice)
        assertNull(store.state.value.error)
        backend.current = identity()
        store.restore().join()
        store.confirmPasswordReset("test-code", "newpassword1", "newpassword1")!!.join()
        assertEquals(AuthStage.GUEST, store.state.value.stage)
        assertNull(backend.current)
        assertEquals(AuthNotice.PASSWORD_CHANGED, store.state.value.notice)
    }

    private inner class FakeProfiles : AuthProfiles {
        var result = profile()
        var problem: AuthProblem? = null
        var createProblem: AuthProblem? = null
        var legalProblem = false
        var fetchCount = 0
        var createCount = 0
        var useRequestedUid = false
        var changes: Flow<Result<AuthProfile>> = emptyFlow()

        override suspend fun create(uid: String, draft: AuthRegistration) {
            createCount++
            createProblem?.let { throw AuthException(it) }
        }

        override suspend fun fetch(uid: String): AuthProfile {
            fetchCount++
            problem?.let { throw AuthException(it) }
            return if (useRequestedUid) profile(uid) else result
        }

        override suspend fun legalDocuments(): List<AuthLegalDocument> {
            if (legalProblem) throw AuthException(AuthProblem.NETWORK)
            return listOf(terms, privacy)
        }

        override suspend fun ensurePublicProfile(profile: AuthProfile) = Unit

        override fun observe(uid: String) = changes
    }

    private inner class FakeBackend(override var current: AuthIdentity? = null) : AuthBackend {
        var tokenProblem: AuthProblem? = null
        var sendProblem: AuthProblem? = null
        var resetProblem: AuthProblem? = null
        var signOutProblem: AuthProblem? = null
        var createCount = 0
        val deleted = mutableListOf<String>()
        var beforeSignIn: suspend (String) -> Unit = {}
        var beforeCreate: suspend () -> Unit = {}

        override suspend fun signIn(email: String, password: String): AuthIdentity {
            beforeSignIn(email)
            return identity(email.substringBefore('@')).also { current = it }
        }

        override suspend fun create(
            email: String,
            password: String,
            displayName: String,
        ): AuthIdentity {
            beforeCreate()
            createCount++
            return AuthIdentity("new", email, false).also { current = it }
        }

        override suspend fun reload() = current ?: throw AuthException(AuthProblem.SESSION_CHANGED)

        override suspend fun refreshToken(): Boolean {
            tokenProblem?.let { throw AuthException(it) }
            return false
        }

        override suspend fun signOut() {
            signOutProblem?.let { throw AuthException(it) }
            current = null
        }

        override suspend fun deleteCreatedUser(uid: String) {
            assertEquals(uid, current?.uid)
            deleted += uid
            current = null
        }

        override suspend fun sendVerification(language: String) {
            sendProblem?.let { throw AuthException(it) }
        }

        override suspend fun sendPasswordReset(email: String, language: String) {
            resetProblem?.let { throw AuthException(it) }
        }

        override suspend fun verifyEmailCode(code: String) {
            current = current?.copy(emailVerified = true)
        }

        override suspend fun resetPasswordCode(code: String, password: String) = Unit
    }
}
