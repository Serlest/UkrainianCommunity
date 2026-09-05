package at.uac.android

import at.uac.android.feature.auth.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

class AuthForegroundPolicyTest {
    @Test
    fun resultBeforeResumePreservesExactlyOneMatchingReturn() {
        val policy = AuthForegroundPolicy()
        val token = policy.begin("own", 7)!!
        policy.onHostPause()
        policy.finish(token)
        assertTrue(policy.consumeResume("own", 7, true))
        assertFalse(policy.consumeResume("own", 7, true))
    }

    @Test
    fun resultAfterResumeCannotExemptAnotherFutureReturn() {
        val policy = AuthForegroundPolicy()
        val token = policy.begin("own", 7)!!
        policy.onHostPause()
        assertTrue(policy.consumeResume("own", 7, true))
        policy.finish(token)
        policy.onHostPause()
        assertFalse(policy.consumeResume("own", 7, true))
    }

    @Test
    fun noActualHostPauseDoesNotSuppressForegroundValidation() {
        val policy = AuthForegroundPolicy()
        policy.begin("own", 7)
        assertFalse(policy.consumeResume("own", 7, true))
        val synchronous = policy.begin("own", 7)!!
        policy.finish(synchronous)
        policy.onHostPause()
        assertFalse(policy.consumeResume("own", 7, true))
    }

    @Test
    fun anotherAccountRevisionOrClosedGateCannotUseTheToken() {
        for ((uid, revision, ready) in
            listOf(Triple("other", 7L, true), Triple("own", 8L, true), Triple("own", 7L, false))) {
            val policy = AuthForegroundPolicy()
            policy.begin("own", 7)
            policy.onHostPause()
            assertFalse(policy.consumeResume(uid, revision, ready))
            assertFalse(policy.consumeResume("own", 7, true))
        }
    }

    @Test
    fun cancelledLaunchAndIdentityTransitionClearTheExemption() {
        val policy = AuthForegroundPolicy()
        val token = policy.begin("own", 7)!!
        policy.cancel(token)
        policy.onHostPause()
        assertFalse(policy.consumeResume("own", 7, true))
        policy.begin("own", 7)
        policy.onHostPause()
        policy.invalidate()
        assertFalse(policy.consumeResume("own", 7, true))
    }

    @Test
    fun staleCallbackCannotCancelANewerPickerAndDuplicateBeginIsDenied() {
        val policy = AuthForegroundPolicy()
        val old = policy.begin("own", 7)!!
        assertNull(policy.begin("own", 7))
        policy.invalidate()
        policy.begin("own", 8)
        policy.onHostPause()
        policy.cancel(old)
        policy.finish(old)
        assertTrue(policy.consumeResume("own", 8, true))
        assertFalse(old.toString().contains("own"))
    }

    @Test
    fun actualStoreKeepsRevisionAndProfileForItsOwnPickerOnly() = runTest {
        val f = Fixture(backgroundScope)
        f.store.restore().join()
        val before = f.store.state.value
        val token = f.store.beginExternalPicker("own", before.revision)!!
        f.store.onHostPause()
        f.store.finishExternalPicker(token)
        assertNull(f.store.onForeground())
        assertEquals(before, f.store.state.value)
        assertEquals(1, f.profiles.reads)
        f.store.onHostPause()
        f.store.onForeground()!!.join()
        assertTrue(f.store.state.value.revision > before.revision)
        assertEquals(2, f.profiles.reads)
    }

    @Test
    fun actualStoreRejectsStaleOrForeignLaunchAndLogoutInvalidatesPendingReturn() = runTest {
        val f = Fixture(backgroundScope)
        f.store.restore().join()
        val revision = f.store.state.value.revision
        assertNull(f.store.beginExternalPicker("foreign", revision))
        assertNull(f.store.beginExternalPicker("own", revision - 1))
        val token = f.store.beginExternalPicker("own", revision)!!
        f.store.onHostPause()
        f.store.signOut().join()
        f.store.finishExternalPicker(token)
        assertNull(f.store.onForeground())
        assertEquals(AuthStage.GUEST, f.store.state.value.stage)
        assertNull(f.store.beginExternalPicker("own", revision))
    }

    private class Fixture(scope: CoroutineScope) {
        val profiles = Profiles()
        val backend = Backend()
        val store = AuthStore(backend, profiles, scope)
    }

    private class Profiles : AuthProfiles {
        var reads = 0

        override suspend fun fetch(uid: String): AuthProfile {
            reads++
            return AuthProfile(
                uid,
                "own@example.invalid",
                "Own",
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
        override var current: AuthIdentity? = AuthIdentity("own", "own@example.invalid", true)

        override suspend fun reload() = current ?: throw AuthException(AuthProblem.SESSION_CHANGED)

        override suspend fun refreshToken() = false

        override suspend fun signOut() {
            current = null
        }

        override suspend fun signIn(email: String, password: String) = error("Unused")

        override suspend fun create(email: String, password: String, displayName: String) =
            error("Unused")

        override suspend fun deleteCreatedUser(uid: String) = Unit

        override suspend fun sendVerification(language: String) = Unit

        override suspend fun sendPasswordReset(email: String, language: String) = Unit

        override suspend fun verifyEmailCode(code: String) = Unit

        override suspend fun resetPasswordCode(code: String, password: String) = Unit
    }
}
