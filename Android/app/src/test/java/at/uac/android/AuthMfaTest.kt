package at.uac.android

import at.uac.android.feature.auth.*
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class AuthMfaTest {
    private val identity = AuthIdentity("mfa-user", "mfa-user@example.invalid", true)
    private val factor = AuthTotpFactor("factor-1", "Test authenticator")

    private fun profile() =
        AuthProfile(
            identity.uid,
            identity.email,
            "MFA test",
            acceptedTermsVersion = "a",
            acceptedPrivacyVersion = "b",
        )

    @Test
    fun codeValidationRejectsLettersUnicodeDigitsAndWrongLength() {
        assertEquals("123456", totpCode(" 123 456 "))
        listOf("", "12345", "1234567", "１２３４５６", "123a56", "12\n3456").forEach {
            assertEquals(
                AuthProblem.MFA_CODE_INVALID,
                runCatching { totpCode(it) }.exceptionOrNull()?.let(::authProblem),
            )
        }
        assertEquals("12345678", totpCode("12345678", 8))
    }

    @Test
    fun setupRedactsSeedAndOnlyLocalOtpSchemeCanOpen() {
        val setup =
            AuthTotpSetup("SYNTHETIC-SEED", "otpauth://totp/UAC:test?secret=SYNTHETIC", 300_000)
        assertFalse(setup.toString().contains("SYNTHETIC"))
        assertFalse(AuthMfaState(setup = setup).toString().contains("SYNTHETIC"))
        assertTrue(safeOtpAuthUri(setup.otpAuthUri))
        listOf(
                "https://example.invalid/qr",
                "otpauth://other/key",
                "otpauth://user@totp/key",
                "otpauth://totp/key#fragment",
            )
            .forEach {
                assertFalse(safeOtpAuthUri(it))
            }
    }

    @Test
    fun lastActivatedPrivilegedFactorIsProtected() {
        val admin = profile().copy(globalRole = "admin", requiresMultiFactorAuth = true)
        assertFalse(canRemoveTotp(admin, listOf(factor), factor.id))
        assertFalse(canRemoveTotp(profile(), listOf(factor), "foreign"))
        assertTrue(canRemoveTotp(profile(), listOf(factor), factor.id))
        assertTrue(canRemoveTotp(admin, listOf(factor, factor.copy(id = "backup")), factor.id))
    }

    @Test
    fun activationReceiptMustBeServerBooleanAndValidTimestamp() {
        requireMfaActivationResponse(
            mapOf("required" to true, "activatedAt" to "2026-09-02T00:00:00Z")
        )
        listOf(
                null,
                emptyMap<String, Any>(),
                mapOf("required" to "true", "activatedAt" to "2026-09-02T00:00:00Z"),
                mapOf("required" to true, "activatedAt" to "today"),
            )
            .forEach {
                assertEquals(
                    AuthProblem.MFA_UNCONFIRMED,
                    runCatching { requireMfaActivationResponse(it) }
                        .exceptionOrNull()
                        ?.let(::authProblem),
                )
            }
    }

    @Test
    fun signInChallengeIsNeitherGuestNorAuthenticatedAndSurvivesForegroundRefresh() = runTest {
        val f = Fixture(backgroundScope)
        f.store.signIn(identity.email, "password")!!.join()
        val revision = f.store.state.value.revision
        assertEquals(AuthStage.MFA_CHALLENGE, f.store.state.value.stage)
        assertFalse(f.store.state.value.readyForActions)
        f.store.refresh().join()
        assertEquals(revision, f.store.state.value.revision)
        assertEquals(0, f.backend.challenge.calls)
        f.store.completeMfaChallenge(factor.id, "123456")!!.join()
        assertTrue(f.store.state.value.readyForActions)
        assertTrue(f.store.state.value.totpAuthenticated)
        assertEquals(AuthNotice.MFA_VERIFIED, f.store.state.value.notice)
    }

    @Test
    fun incorrectCodeRetainsResolverForExplicitRetry() = runTest {
        val f = Fixture(backgroundScope)
        f.store.signIn(identity.email, "password")!!.join()
        f.backend.challenge.problem = AuthProblem.MFA_CODE_INVALID
        f.store.completeMfaChallenge(factor.id, "123456")!!.join()
        assertEquals(AuthProblem.MFA_CODE_INVALID, f.store.state.value.error)
        assertEquals(AuthStage.MFA_CHALLENGE, f.store.state.value.stage)
        f.backend.challenge.problem = null
        f.store.completeMfaChallenge(factor.id, "654321")!!.join()
        assertEquals(2, f.backend.challenge.calls)
        assertTrue(f.store.state.value.readyForActions)
    }

    @Test
    fun unsupportedFactorAndInvalidCodeNeverCallResolver() = runTest {
        val f = Fixture(backgroundScope)
        f.store.signIn(identity.email, "password")!!.join()
        assertNull(f.store.completeMfaChallenge("foreign", "123456"))
        assertEquals(AuthProblem.MFA_UNSUPPORTED, f.store.state.value.error)
        assertNull(f.store.completeMfaChallenge(factor.id, "12"))
        assertEquals(0, f.backend.challenge.calls)
    }

    @Test
    fun challengeCancellationClearsSessionAndOpaqueHandle() = runTest {
        val f = Fixture(backgroundScope)
        f.store.signIn(identity.email, "password")!!.join()
        f.store.cancelMfa().join()
        assertEquals(AuthStage.GUEST, f.store.state.value.stage)
        assertNull(f.store.completeMfaChallenge(factor.id, "123456"))
        assertFalse(f.store.state.value.mfa.interactive)
    }

    @Test
    fun resolverSuccessWithoutActualTotpClaimDoesNotOpenSession() = runTest {
        val f = Fixture(backgroundScope)
        f.backend.claimAfterResolve = false
        f.store.signIn(identity.email, "password")!!.join()
        f.store.completeMfaChallenge(factor.id, "123456")!!.join()
        assertEquals(AuthStage.GUEST, f.store.state.value.stage)
        assertEquals(AuthProblem.MFA_UNCONFIRMED, f.store.state.value.error)
        assertNull(f.store.completeMfaChallenge(factor.id, "123456"))
        assertFalse(f.store.state.value.readyForActions)
        f.store.refresh().join()
        assertEquals(AuthStage.GUEST, f.store.state.value.stage)
        assertNull(f.backend.current)
    }

    @Test
    fun resolverReturningAnotherAccountIsSignedOut() = runTest {
        val f = Fixture(backgroundScope)
        f.backend.challenge.result =
            identity.copy(uid = "foreign", email = "foreign@example.invalid")
        f.store.signIn(identity.email, "password")!!.join()
        f.store.completeMfaChallenge(factor.id, "123456")!!.join()
        assertNull(f.backend.current)
        assertEquals(AuthStage.GUEST, f.store.state.value.stage)
        assertEquals(AuthProblem.SESSION_CHANGED, f.store.state.value.error)
    }

    @Test
    fun logoutDuringResolverWaitsForActualSdkCompletionButHidesOldUiImmediately() = runTest {
        val f = Fixture(backgroundScope)
        f.store.signIn(identity.email, "password")!!.join()
        val finish = CompletableDeferred<Unit>()
        f.backend.challenge.wait = finish
        val resolving = f.store.completeMfaChallenge(factor.id, "123456")!!
        runCurrent()
        val logout = f.store.signOut()
        assertFalse(f.store.state.value.mfa.interactive)
        assertNull(f.store.state.value.profile)
        runCurrent()
        assertFalse(logout.isCompleted)
        finish.complete(Unit)
        resolving.join()
        logout.join()
        assertNull(f.backend.current)
        assertEquals(AuthStage.GUEST, f.store.state.value.stage)
    }

    @Test
    fun enrollmentSurvivesForegroundButNotExplicitCancel() = runTest {
        val f = Fixture(backgroundScope)
        f.store.restore().join()
        f.store.beginTotpEnrollment("password")!!.join()
        val setup = f.store.state.value.mfa.setup
        assertNotNull(setup)
        assertFalse(f.store.state.value.readyForActions)
        f.store.refresh().join()
        assertSame(setup, f.store.state.value.mfa.setup)
        f.store.cancelMfa().join()
        assertNull(f.store.state.value.mfa.setup)
        assertNull(f.store.completeTotpEnrollment("123456"))
        assertEquals(0, f.backend.security.enrollmentCalls)
    }

    @Test
    fun enrollmentDoesNotFabricateTotpSignInOrActivateAdminProtection() = runTest {
        val f = Fixture(backgroundScope, profile().copy(globalRole = "admin"))
        f.store.restore().join()
        f.store.beginTotpEnrollment("password")!!.join()
        f.store.completeTotpEnrollment("123456")!!.join()
        assertEquals(AuthNotice.MFA_ENROLLED, f.store.state.value.notice)
        assertFalse(f.store.state.value.totpAuthenticated)
        assertEquals(AuthGate.MFA_REQUIRED, f.store.state.value.gate)
        f.store.activateMfaProtection()!!.join()
        assertEquals(AuthProblem.SECOND_FACTOR_REQUIRED, f.store.state.value.error)
        assertEquals(0, f.activationCalls)
    }

    @Test
    fun invalidEnrollmentCodeKeepsSecretForRetryButExpiredSecretCannotEnroll() = runTest {
        val f = Fixture(backgroundScope)
        f.store.restore().join()
        f.store.beginTotpEnrollment("password")!!.join()
        f.backend.security.enrollmentProblem = AuthProblem.MFA_CODE_INVALID
        f.store.completeTotpEnrollment("123456")!!.join()
        assertNotNull(f.store.state.value.mfa.setup)
        f.now = 300_001
        f.store.completeTotpEnrollment("123456")!!.join()
        assertEquals(AuthProblem.MFA_EXPIRED, f.store.state.value.error)
        assertNull(f.store.state.value.mfa.setup)
        assertEquals(1, f.backend.security.enrollmentCalls)
    }

    @Test
    fun uncertainEnrollmentDropsSecretAndRequiresReadBackBeforeRetry() = runTest {
        val f = Fixture(backgroundScope)
        f.store.restore().join()
        f.store.beginTotpEnrollment("password")!!.join()
        f.backend.security.enrollmentProblem = AuthProblem.MFA_UNCONFIRMED
        f.backend.security.commitBeforeFailure = true
        f.store.completeTotpEnrollment("123456")!!.join()
        assertNull(f.store.state.value.mfa.setup)
        assertTrue(f.store.state.value.mfa.unconfirmed)
        assertFalse(f.store.state.value.readyForActions)
        f.store.refresh().join()
        assertTrue(f.store.state.value.mfa.unconfirmed)
        assertNull(f.store.beginTotpEnrollment("password"))
        f.store.loadMfa()!!.join()
        assertFalse(f.store.state.value.mfa.unconfirmed)
        assertEquals(listOf(factor), f.store.state.value.mfa.factors)
        assertEquals(1, f.backend.security.enrollmentCalls)
    }

    @Test
    fun lastActivatedFactorCannotReachReauthOrRemovalBackend() = runTest {
        val f =
            Fixture(
                backgroundScope,
                profile().copy(globalRole = "owner", requiresMultiFactorAuth = true),
            )
        f.backend.security.currentFactors = listOf(factor)
        f.store.restore().join()
        f.store.removeTotpFactor(factor.id, "password")!!.join()
        assertEquals(AuthProblem.MFA_LAST_FACTOR, f.store.state.value.error)
        assertEquals(0, f.backend.security.reauthCalls)
        assertEquals(0, f.backend.security.removeCalls)
    }

    @Test
    fun regularFactorRemovalUsesReauthAndServerFactorReadBack() = runTest {
        val f = Fixture(backgroundScope)
        f.backend.security.currentFactors = listOf(factor)
        f.store.restore().join()
        f.store.removeTotpFactor(factor.id, "password")!!.join()
        assertEquals(1, f.backend.security.reauthCalls)
        assertEquals(1, f.backend.security.removeCalls)
        assertEquals(AuthNotice.MFA_REMOVED, f.store.state.value.notice)
        assertTrue(f.store.state.value.mfa.factors.isEmpty())
    }

    @Test
    fun reauthenticationChallengePreservesRemoveIntentButNeverThePassword() = runTest {
        val f = Fixture(backgroundScope)
        f.backend.security.currentFactors = listOf(factor)
        f.backend.security.needsChallenge = true
        f.store.restore().join()
        f.store.removeTotpFactor(factor.id, "password")!!.join()
        assertEquals(AuthStage.MFA_CHALLENGE, f.store.state.value.stage)
        f.store.refresh().join()
        f.store.completeMfaChallenge(factor.id, "123456")!!.join()
        assertEquals(AuthNotice.MFA_REMOVED, f.store.state.value.notice)
        assertEquals(1, f.backend.security.removeCalls)
    }

    @Test
    fun serverBanAfterSetupStopsEnrollmentMutation() = runTest {
        val f = Fixture(backgroundScope)
        f.store.restore().join()
        f.store.beginTotpEnrollment("password")!!.join()
        f.profiles.result = f.profiles.result.copy(accountStatus = "banned")
        f.store.completeTotpEnrollment("123456")!!.join()
        assertEquals(AuthProblem.PERMISSION_DENIED, f.store.state.value.error)
        assertEquals(0, f.backend.security.enrollmentCalls)
    }

    @Test
    fun activationRequiresFreshTotpAndLivePrivilegedProfile() = runTest {
        val f = Fixture(backgroundScope, profile().copy(globalRole = "admin"))
        f.backend.totp = true
        f.store.restore().join()
        f.store.activateMfaProtection()!!.join()
        assertEquals(1, f.activationCalls)
        assertEquals(AuthNotice.MFA_ACTIVATED, f.store.state.value.notice)
        assertTrue(f.store.state.value.profile!!.requiresMultiFactorAuth)
        assertTrue(f.store.state.value.readyForActions)
    }

    @Test
    fun roleRevocationBeforeActivationNeverReachesCallable() = runTest {
        val f = Fixture(backgroundScope, profile().copy(globalRole = "admin"))
        f.backend.totp = true
        f.store.restore().join()
        f.profiles.result = f.profiles.result.copy(globalRole = "user")
        f.store.activateMfaProtection()!!.join()
        assertEquals(AuthProblem.PERMISSION_DENIED, f.store.state.value.error)
        assertEquals(0, f.activationCalls)
    }

    @Test
    fun invalidatedAuthDuringUnenrollSignsOutWithoutSuccessNotice() = runTest {
        val f = Fixture(backgroundScope)
        f.backend.security.currentFactors = listOf(factor)
        f.backend.security.removeProblem = AuthProblem.SESSION_CHANGED
        f.store.restore().join()
        f.store.removeTotpFactor(factor.id, "password")!!.join()
        assertEquals(AuthStage.GUEST, f.store.state.value.stage)
        assertNull(f.store.state.value.notice)
        assertEquals(AuthProblem.SESSION_CHANGED, f.store.state.value.error)
    }

    @Test
    fun resolverNetworkOrExpiryFailureKeepsExplicitRetryAndCancelAvailable() = runTest {
        val f = Fixture(backgroundScope)
        f.store.signIn(identity.email, "password")!!.join()
        for (problem in listOf(AuthProblem.NETWORK, AuthProblem.MFA_EXPIRED)) {
            f.backend.challenge.problem = problem
            f.store.completeMfaChallenge(factor.id, "123456")!!.join()
            assertEquals(AuthStage.MFA_CHALLENGE, f.store.state.value.stage)
            assertEquals(problem, f.store.state.value.error)
            assertTrue(f.store.state.value.mfa.challenge)
            assertFalse(f.store.state.value.busy)
        }
        f.store.cancelMfa().join()
        assertEquals(AuthStage.GUEST, f.store.state.value.stage)
    }

    @Test
    fun logoutDuringEnrollmentHidesSecretAndWaitsForTheActualMutation() = runTest {
        val f = Fixture(backgroundScope)
        f.store.restore().join()
        f.store.beginTotpEnrollment("password")!!.join()
        val finish = CompletableDeferred<Unit>()
        f.backend.security.enrollmentWait = finish
        val enrolling = f.store.completeTotpEnrollment("123456")!!
        runCurrent()
        assertNull(f.store.completeTotpEnrollment("654321"))
        val logout = f.store.signOut()
        assertNull(f.store.state.value.mfa.setup)
        runCurrent()
        assertFalse(logout.isCompleted)
        finish.complete(Unit)
        enrolling.join()
        logout.join()
        assertEquals(1, f.backend.security.enrollmentCalls)
        assertNull(f.backend.current)
        assertNull(f.store.state.value.notice)
        assertEquals(AuthStage.GUEST, f.store.state.value.stage)
    }

    private inner class Fixture(scope: CoroutineScope, initialProfile: AuthProfile = profile()) {
        var now = 100L
        val profiles = Profiles(initialProfile)
        val backend = Backend()
        var activationCalls = 0
        val store =
            AuthStore(
                backend,
                profiles,
                scope,
                mfaActivator =
                    object : AuthMfaActivator {
                        override suspend fun activate(uid: String) {
                            assertEquals(identity.uid, uid)
                            activationCalls++
                            profiles.result = profiles.result.copy(requiresMultiFactorAuth = true)
                        }
                    },
                clock = { now },
            )
    }

    private inner class Profiles(var result: AuthProfile) : AuthProfiles {
        val events = MutableSharedFlow<Result<AuthProfile>>(extraBufferCapacity = 2)

        override suspend fun fetch(uid: String) = result

        override suspend fun legalDocuments() =
            listOf(
                AuthLegalDocument(
                    "terms",
                    "a",
                    true,
                    mapOf("de" to "Terms"),
                    mapOf("de" to "text"),
                ),
                AuthLegalDocument(
                    "privacy",
                    "b",
                    true,
                    mapOf("de" to "Privacy"),
                    mapOf("de" to "text"),
                ),
            )

        override suspend fun create(uid: String, draft: AuthRegistration) = Unit

        override suspend fun ensurePublicProfile(profile: AuthProfile) = Unit

        override fun observe(uid: String) = events
    }

    private inner class Backend : AuthBackend {
        override var current: AuthIdentity? = identity
        override val security = Security(this)
        val challenge = Challenge(this)
        var totp = false
        var claimAfterResolve = true

        override suspend fun signIn(email: String, password: String): AuthIdentity =
            throw AuthMfaChallengeRequired(challenge)

        override suspend fun reload() = current ?: throw AuthException(AuthProblem.SESSION_CHANGED)

        override suspend fun refreshToken() = totp

        override suspend fun signOut() {
            current = null
        }

        override suspend fun create(email: String, password: String, displayName: String) =
            error("Unused")

        override suspend fun deleteCreatedUser(uid: String) = Unit

        override suspend fun sendVerification(language: String) = Unit

        override suspend fun sendPasswordReset(email: String, language: String) = Unit

        override suspend fun verifyEmailCode(code: String) = Unit

        override suspend fun resetPasswordCode(code: String, password: String) = Unit
    }

    private inner class Challenge(private val backend: Backend) : AuthMfaChallenge {
        override val factors = listOf(factor)
        var calls = 0
        var problem: AuthProblem? = null
        var result = identity
        var wait: CompletableDeferred<Unit>? = null

        override suspend fun resolve(factorId: String, code: String): AuthIdentity =
            withContext(NonCancellable) {
                calls++
                wait?.await()
                problem?.let { throw AuthException(it) }
                backend.current = result
                backend.totp = backend.claimAfterResolve
                result
            }
    }

    private inner class Security(private val backend: Backend) : AuthSecurityBackend {
        var currentFactors = emptyList<AuthTotpFactor>()
        var reauthCalls = 0
        var removeCalls = 0
        var enrollmentCalls = 0
        var needsChallenge = false
        var enrollmentProblem: AuthProblem? = null
        var removeProblem: AuthProblem? = null
        var commitBeforeFailure = false
        var enrollmentWait: CompletableDeferred<Unit>? = null

        override suspend fun factors(uid: String) = currentFactors

        override suspend fun reauthenticate(uid: String, password: String) {
            reauthCalls++
            if (needsChallenge) throw AuthMfaChallengeRequired(backend.challenge)
        }

        override suspend fun beginEnrollment(uid: String): AuthTotpEnrollment =
            object : AuthTotpEnrollment {
                override val setup =
                    AuthTotpSetup("SYNTHETIC", "otpauth://totp/UAC:test?secret=SYNTHETIC", 300_000)

                override suspend fun complete(code: String) {
                    withContext(NonCancellable) {
                        enrollmentCalls++
                        enrollmentWait?.await()
                        if (enrollmentProblem == null || commitBeforeFailure)
                            currentFactors = listOf(factor)
                        enrollmentProblem?.let { throw AuthException(it) }
                    }
                }
            }

        override suspend fun unenroll(uid: String, factorId: String) {
            removeCalls++
            removeProblem?.let { throw AuthException(it) }
            currentFactors = currentFactors.filterNot { it.id == factorId }
        }
    }
}
