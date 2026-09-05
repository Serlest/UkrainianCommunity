package at.uac.android

import at.uac.android.feature.applock.*
import at.uac.android.feature.auth.*
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.test.*
import kotlinx.coroutines.withContext
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class AppLockTest {
    private val alice = AppLockSession("synthetic-lock-alice", 1)
    private val bob = AppLockSession("synthetic-lock-bob", 2)

    @Before
    fun setup() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @After
    fun finish() {
        Dispatchers.resetMain()
    }

    private class Preferences : AppLockPreferences {
        val values = mutableMapOf<String, Boolean>()
        var writes = 0
        var failRead = false
        var failWrite = false

        override fun enabled(uid: String): Boolean {
            if (failRead) throw AppLockException(AppLockProblem.STORAGE)
            return values[uid] == true
        }

        override fun setEnabled(uid: String, enabled: Boolean) {
            writes++
            if (failWrite) throw AppLockException(AppLockProblem.STORAGE)
            values[uid] = enabled
        }
    }

    private class Authenticator : AppLockAuthenticating {
        var available = AppLockAvailability(true, true)
        var result = AppLockResult.ACCEPTED
        var waiting: CompletableDeferred<AppLockResult>? = null
        val attempts = mutableListOf<AppLockAttempt>()
        val cancelled = mutableListOf<AppLockAttempt>()

        override fun availability() = available

        override suspend fun authenticate(
            attempt: AppLockAttempt,
            language: String,
        ): AppLockResult {
            attempts += attempt
            return waiting?.let { withContext(NonCancellable) { it.await() } } ?: result
        }

        override fun cancel(attempt: AppLockAttempt) {
            cancelled += attempt
        }
    }

    @Test
    fun preferenceKeysAreDeterministicHashedAndAccountSpecific() {
        val key = appLockPreferenceKey(alice.uid)
        assertTrue(key.matches(Regex("appLock\\.enabledAccounts\\.v1\\.[a-f0-9]{64}")))
        assertFalse(key.contains(alice.uid))
        assertEquals(key, appLockPreferenceKey(alice.uid))
        assertNotEquals(key, appLockPreferenceKey(bob.uid))
        assertTrue(runCatching { appLockPreferenceKey("nested/path") }.isFailure)
    }

    @Test
    fun defaultOffAndGuestCannotEnableOrAuthenticate() = runTest {
        val prefs = Preferences()
        val auth = Authenticator()
        val model = AppLockViewModel(prefs, auth, backgroundScope)
        model.enterForeground()
        assertNull(model.setEnabled(true, "uk"))
        assertNull(model.unlock("uk"))
        model.bind(alice)
        assertFalse(model.state.value.enabled)
        assertFalse(model.state.value.locked)
        assertTrue(auth.attempts.isEmpty())
        assertEquals(0, prefs.writes)
    }

    @Test
    fun enablingWaitsForSystemResultAndRejectsDuplicateRequests() = runTest {
        val prefs = Preferences()
        val auth = Authenticator().apply { waiting = CompletableDeferred() }
        val model = AppLockViewModel(prefs, auth, backgroundScope)
        model.bind(alice)
        model.enterForeground()
        val job = model.setEnabled(true, "de")!!
        runCurrent()
        assertTrue(model.state.value.authenticating)
        assertFalse(model.state.value.enabled)
        assertEquals(0, prefs.writes)
        assertNull(model.setEnabled(true, "de"))
        auth.waiting!!.complete(AppLockResult.ACCEPTED)
        job.join()
        assertTrue(model.state.value.enabled)
        assertTrue(model.state.value.unlocked)
        assertEquals(1, prefs.writes)
        assertEquals(1, auth.attempts.size)
    }

    @Test
    fun rejectedAndCancelledEnableDoNotPersistPreference() = runTest {
        for (result in
            listOf(AppLockResult.REJECTED, AppLockResult.CANCELLED, AppLockResult.ERROR)) {
            val prefs = Preferences()
            val auth = Authenticator().apply { this.result = result }
            val model = AppLockViewModel(prefs, auth, backgroundScope)
            model.bind(alice)
            model.enterForeground()
            model.setEnabled(true, "de")!!.join()
            assertFalse(model.state.value.enabled)
            assertEquals(0, prefs.writes)
            assertFalse(model.state.value.authenticating)
            if (result == AppLockResult.CANCELLED) assertNull(model.state.value.error)
            else assertEquals(AppLockProblem.FAILED, model.state.value.error)
        }
    }

    @Test
    fun disablingAlsoRequiresSystemAuthenticationAndFailureKeepsLock() = runTest {
        val prefs = Preferences().apply { values[alice.uid] = true }
        val auth = Authenticator().apply { result = AppLockResult.REJECTED }
        val model = AppLockViewModel(prefs, auth, backgroundScope)
        model.bind(alice)
        model.enterForeground()
        model.setEnabled(false, "de")!!.join()
        assertTrue(model.state.value.locked)
        assertTrue(prefs.enabled(alice.uid))
        assertEquals(0, prefs.writes)
        auth.result = AppLockResult.ACCEPTED
        model.setEnabled(false, "de")!!.join()
        assertFalse(model.state.value.enabled)
        assertFalse(prefs.enabled(alice.uid))
        assertEquals(2, auth.attempts.size)
    }

    @Test
    fun coldRestoreLocksOnlyTheAccountWhosePreferenceWasEnabled() = runTest {
        val prefs = Preferences()
        val auth = Authenticator()
        val first = AppLockViewModel(prefs, auth, backgroundScope)
        first.bind(alice)
        first.enterForeground()
        first.setEnabled(true, "de")!!.join()
        val restored = AppLockViewModel(prefs, auth, backgroundScope)
        restored.bind(alice)
        assertTrue(restored.state.value.locked)
        restored.bind(bob)
        assertFalse(restored.state.value.enabled)
        restored.bind(null)
        assertFalse(restored.state.value.needsPrivacyShield)
        restored.bind(alice)
        assertTrue(restored.state.value.locked)
    }

    @Test
    fun backgroundRelocksAndForegroundDoesNotAutomaticallyPrompt() = runTest {
        val prefs = Preferences().apply { values[alice.uid] = true }
        val auth = Authenticator()
        val model = AppLockViewModel(prefs, auth, backgroundScope)
        model.bind(alice)
        model.enterForeground()
        model.unlock("de")!!.join()
        assertTrue(model.state.value.canRoute)
        model.enterBackground()
        assertTrue(model.state.value.locked)
        assertFalse(model.state.value.canRoute)
        model.enterForeground()
        assertTrue(model.state.value.locked)
        assertEquals(1, auth.attempts.size)
    }

    @Test
    fun lateSuccessAfterRealBackgroundCannotUnlock() = runTest {
        val prefs = Preferences().apply { values[alice.uid] = true }
        val auth = Authenticator().apply { waiting = CompletableDeferred() }
        val model = AppLockViewModel(prefs, auth, backgroundScope)
        model.bind(alice)
        model.enterForeground()
        val job = model.unlock("de")!!
        runCurrent()
        model.enterBackground()
        auth.waiting!!.complete(AppLockResult.ACCEPTED)
        job.join()
        model.enterForeground()
        assertTrue(model.state.value.locked)
        assertFalse(model.state.value.authenticating)
        assertEquals(1, auth.cancelled.size)
    }

    @Test
    fun lateSuccessAfterAccountOrRevisionChangeCannotEnableNewScope() = runTest {
        for (next in listOf(bob, alice.copy(revision = 3))) {
            val prefs = Preferences()
            val auth = Authenticator().apply { waiting = CompletableDeferred() }
            val model = AppLockViewModel(prefs, auth, backgroundScope)
            model.bind(alice)
            model.enterForeground()
            val job = model.setEnabled(true, "uk")!!
            runCurrent()
            model.bind(next)
            auth.waiting!!.complete(AppLockResult.ACCEPTED)
            job.join()
            assertFalse(model.state.value.enabled)
            assertEquals(0, prefs.writes)
            assertEquals(next, model.state.value.session)
        }
    }

    @Test
    fun exactLegacyCredentialAttemptMaySurviveItsOwnBackgroundOnly() = runTest {
        val prefs = Preferences().apply { values[alice.uid] = true }
        val auth = Authenticator().apply { waiting = CompletableDeferred() }
        val model = AppLockViewModel(prefs, auth, backgroundScope)
        model.bind(alice)
        model.enterForeground()
        val job = model.unlock("de")!!
        runCurrent()
        model.enterBackground(auth.attempts.single())
        assertTrue(model.state.value.locked)
        assertTrue(model.state.value.authenticating)
        assertTrue(auth.cancelled.isEmpty())
        model.enterForeground()
        auth.waiting!!.complete(AppLockResult.ACCEPTED)
        job.join()
        assertFalse(model.state.value.locked)
    }

    @Test
    fun forgedOrOldCredentialLeaseCannotKeepNewRequestAlive() = runTest {
        val prefs = Preferences().apply { values[alice.uid] = true }
        val auth = Authenticator().apply { waiting = CompletableDeferred() }
        val model = AppLockViewModel(prefs, auth, backgroundScope)
        model.bind(alice)
        model.enterForeground()
        val job = model.unlock("de")!!
        runCurrent()
        model.enterBackground(AppLockAttempt(alice, 1))
        auth.waiting!!.complete(AppLockResult.ACCEPTED)
        job.join()
        model.enterForeground()
        assertTrue(model.state.value.locked)
        assertEquals(1, auth.cancelled.size)
    }

    @Test
    fun acceptedResultWhileStillInBackgroundIsNotDeferredIntoUnlock() = runTest {
        val prefs = Preferences().apply { values[alice.uid] = true }
        val auth = Authenticator().apply { waiting = CompletableDeferred() }
        val model = AppLockViewModel(prefs, auth, backgroundScope)
        model.bind(alice)
        model.enterForeground()
        val job = model.unlock("de")!!
        runCurrent()
        model.enterBackground(auth.attempts.single())
        auth.waiting!!.complete(AppLockResult.ACCEPTED)
        job.join()
        model.enterForeground()
        assertTrue(model.state.value.locked)
    }

    @Test
    fun preferenceReadFailureFailsClosedUntilConfirmedDeviceOperation() = runTest {
        val prefs = Preferences().apply { failRead = true }
        val auth = Authenticator()
        val model = AppLockViewModel(prefs, auth, backgroundScope)
        model.bind(alice)
        model.enterForeground()
        assertTrue(model.state.value.locked)
        assertEquals(AppLockProblem.STORAGE, model.state.value.error)
        model.unlock("uk")!!.join()
        assertFalse(model.state.value.locked)
    }

    @Test
    fun unconfirmedPreferenceWriteNeverDisablesProtection() = runTest {
        for (enabledBefore in listOf(true, false)) {
            val prefs =
                Preferences().apply {
                    values[alice.uid] = enabledBefore
                    failWrite = true
                }
            val model = AppLockViewModel(prefs, Authenticator(), backgroundScope)
            model.bind(alice)
            model.enterForeground()
            model.setEnabled(!enabledBefore, "de")!!.join()
            assertTrue(model.state.value.locked)
            assertTrue(model.state.value.enabled)
            assertEquals(AppLockProblem.STORAGE, model.state.value.error)
        }
    }

    @Test
    fun sameUidForegroundRefreshKeepsUnlockedEditorButMasksOldFrameUntilBind() = runTest {
        val prefs = Preferences().apply { values[alice.uid] = true }
        val model = AppLockViewModel(prefs, Authenticator(), backgroundScope)
        model.bind(alice)
        model.enterForeground()
        model.unlock("de")!!.join()
        val next = alice.copy(revision = 2)
        assertTrue(model.state.value.forSession(next).locked)
        model.bind(next)
        assertFalse(model.state.value.locked)
        model.bind(bob)
        assertFalse(model.state.value.unlocked)
    }

    @Test
    fun sameUidRefreshCannotKeepUnlockedStateWhenPreferenceReadFails() = runTest {
        val prefs = Preferences().apply { values[alice.uid] = true }
        val model = AppLockViewModel(prefs, Authenticator(), backgroundScope)
        model.bind(alice)
        model.enterForeground()
        model.unlock("de")!!.join()
        assertFalse(model.state.value.locked)
        prefs.failRead = true
        model.bind(alice.copy(revision = 2))
        assertTrue(model.state.value.locked)
        assertTrue(model.state.value.blocksInteraction)
        assertEquals(AppLockProblem.STORAGE, model.state.value.error)
    }

    @Test
    fun unavailableAuthenticatorDoesNotPromptOrChangePreference() = runTest {
        val auth = Authenticator().apply { available = AppLockAvailability() }
        val prefs = Preferences()
        val model = AppLockViewModel(prefs, auth, backgroundScope)
        model.bind(alice)
        model.enterForeground()
        assertNull(model.setEnabled(true, "de"))
        assertTrue(auth.attempts.isEmpty())
        assertEquals(0, prefs.writes)
        assertEquals(AppLockProblem.UNAVAILABLE, model.state.value.error)
    }

    @Test
    fun deviceCodeOnlyRemainsAvailableWithoutClaimingBiometric() = runTest {
        val auth =
            Authenticator().apply { available = AppLockAvailability(deviceCredential = true) }
        val model = AppLockViewModel(Preferences(), auth, backgroundScope)
        model.bind(alice)
        model.enterForeground()
        model.setEnabled(true, "uk")!!.join()
        assertTrue(model.state.value.enabled)
        assertFalse(model.state.value.availability.strongBiometric)
    }

    @Test
    fun sdkPolicyNeverUsesUnsupportedStrongCredentialCombinationOnLegacy() {
        for (sdk in 26..29) {
            assertEquals(
                AppLockPromptPolicy.STRONG_WITH_LEGACY_CREDENTIAL,
                appLockPromptPolicy(sdk, AppLockAvailability(true, true)),
            )
            assertEquals(
                AppLockPromptPolicy.LEGACY_CREDENTIAL,
                appLockPromptPolicy(sdk, AppLockAvailability(false, true)),
            )
            assertEquals(
                AppLockPromptPolicy.STRONG_ONLY,
                appLockPromptPolicy(sdk, AppLockAvailability(true, false)),
            )
        }
        for (sdk in 30..37) assertEquals(
            AppLockPromptPolicy.STRONG_OR_CREDENTIAL,
            appLockPromptPolicy(sdk, AppLockAvailability(false, true)),
        )
        assertEquals(
            AppLockPromptPolicy.UNAVAILABLE,
            appLockPromptPolicy(25, AppLockAvailability(true, true)),
        )
        assertEquals(
            AppLockPromptPolicy.UNAVAILABLE,
            appLockPromptPolicy(37, AppLockAvailability()),
        )
    }

    @Test
    fun passwordProofIsExactSingleUseAndRedacted() = runTest {
        val prefs = Preferences().apply { values[alice.uid] = true }
        val model = AppLockViewModel(prefs, Authenticator(), backgroundScope)
        model.bind(alice)
        model.enterForeground()
        val proof = AuthPasswordProof(alice.uid, alice.revision)
        assertFalse(proof.toString().contains(alice.uid))
        assertFalse(AppLockAttempt(alice, 9).toString().contains(alice.uid))
        model.bind(alice, AuthPasswordProof(bob.uid, alice.revision))
        assertTrue(model.state.value.locked)
        model.bind(alice, AuthPasswordProof(alice.uid, 99))
        assertTrue(model.state.value.locked)
        model.bind(alice, proof)
        assertFalse(model.state.value.locked)
        model.lock()
        model.bind(alice, proof)
        assertTrue(model.state.value.locked)
    }

    @Test
    fun backgroundPasswordProofIsConsumedWithoutUnlockingOnReturn() = runTest {
        val prefs = Preferences().apply { values[alice.uid] = true }
        val model = AppLockViewModel(prefs, Authenticator(), backgroundScope)
        val proof = AuthPasswordProof(alice.uid, alice.revision)
        model.bind(alice, proof)
        model.enterForeground()
        model.bind(alice, proof)
        assertTrue(model.state.value.locked)
    }

    @Test
    fun protectionCallbackObservesNewStateSynchronously() = runTest {
        val prefs = Preferences().apply { values[alice.uid] = true }
        val model = AppLockViewModel(prefs, Authenticator(), backgroundScope)
        val observed = mutableListOf<AppLockState>()
        model.protectionChanged = { observed += model.state.value }
        model.bind(alice)
        assertTrue(observed.last().locked)
        model.enterForeground()
        model.unlock("de")!!.join()
        assertFalse(observed.last().locked)
        model.enterBackground()
        assertTrue(observed.last().locked)
        assertFalse(observed.last().foreground)
        model.signOutFailed()
        assertTrue(model.state.value.locked)
        assertEquals(AppLockProblem.SIGN_OUT, observed.last().error)
    }

    @Test
    fun onlyActualPasswordSignInIssuesProofAndOrdinaryRestoreDoesNot() = runTest {
        val backend = Backend()
        val store = AuthStore(backend, Profiles(), backgroundScope)
        backend.current = backend.identity
        store.restore().join()
        assertTrue(store.state.value.readyForActions)
        assertNull(store.state.value.localPasswordProof)
        store.signIn(backend.identity.email, "password")!!.join()
        val proof = store.state.value.localPasswordProof!!
        assertTrue(proof.consume(backend.identity.uid, store.state.value.revision))
        assertFalse(proof.consume(backend.identity.uid, store.state.value.revision))
        store.refresh().join()
        assertNull(store.state.value.localPasswordProof)
    }

    @Test
    fun failedSignInOrMissingProfileCannotIssueLocalPasswordProof() = runTest {
        val backend = Backend().apply { invalidPassword = true }
        val profiles = Profiles()
        val store = AuthStore(backend, profiles, backgroundScope)
        store.signIn(backend.identity.email, "password")!!.join()
        assertNull(store.state.value.localPasswordProof)
        backend.invalidPassword = false
        profiles.fail = true
        store.signIn(backend.identity.email, "password")!!.join()
        assertNull(store.state.value.localPasswordProof)
    }

    @Test
    fun mfaSignInIssuesPasswordProofOnlyAfterActualResolverAndClaim() = runTest {
        for (claim in listOf(false, true)) {
            val backend =
                Backend().apply {
                    challengeRequired = true
                    claimAfterResolve = claim
                }
            val store = AuthStore(backend, Profiles(), backgroundScope)
            store.signIn(backend.identity.email, "password")!!.join()
            assertEquals(AuthStage.MFA_CHALLENGE, store.state.value.stage)
            assertNull(store.state.value.localPasswordProof)
            store.completeMfaChallenge("factor", "123456")!!.join()
            assertEquals(claim, store.state.value.localPasswordProof != null)
        }
    }

    private class Profiles : AuthProfiles {
        var fail = false

        override suspend fun fetch(uid: String): AuthProfile {
            if (fail) throw AuthException(AuthProblem.PROFILE_MISSING)
            return AuthProfile(
                uid,
                "proof@example.invalid",
                "Proof test",
                acceptedTermsVersion = "a",
                acceptedPrivacyVersion = "b",
            )
        }

        override suspend fun legalDocuments() =
            listOf(
                AuthLegalDocument("terms", "a", true, emptyMap(), mapOf("de" to "text")),
                AuthLegalDocument("privacy", "b", true, emptyMap(), mapOf("de" to "text")),
            )

        override fun observe(uid: String) = emptyFlow<Result<AuthProfile>>()

        override suspend fun create(uid: String, draft: AuthRegistration) = Unit

        override suspend fun ensurePublicProfile(profile: AuthProfile) = Unit
    }

    private class Backend : AuthBackend {
        val identity = AuthIdentity("synthetic-password-proof", "proof@example.invalid", true)
        override var current: AuthIdentity? = null
        var invalidPassword = false
        var challengeRequired = false
        var claimAfterResolve = false
        private var claim = false

        override suspend fun signIn(email: String, password: String): AuthIdentity {
            if (invalidPassword) throw AuthException(AuthProblem.INVALID_CREDENTIALS)
            if (challengeRequired)
                throw AuthMfaChallengeRequired(
                    object : AuthMfaChallenge {
                        override val factors = listOf(AuthTotpFactor("factor", "Synthetic"))

                        override suspend fun resolve(factorId: String, code: String): AuthIdentity {
                            claim = claimAfterResolve
                            current = identity
                            return identity
                        }
                    }
                )
            current = identity
            return identity
        }

        override suspend fun reload() = current ?: throw AuthException(AuthProblem.SESSION_CHANGED)

        override suspend fun refreshToken() = claim

        override suspend fun signOut() {
            current = null
            claim = false
        }

        override suspend fun create(email: String, password: String, displayName: String) =
            error("Unused")

        override suspend fun deleteCreatedUser(uid: String) = Unit

        override suspend fun sendVerification(language: String) = Unit

        override suspend fun sendPasswordReset(email: String, language: String) = Unit

        override suspend fun verifyEmailCode(code: String) = Unit

        override suspend fun resetPasswordCode(code: String, password: String) = Unit
    }
}
