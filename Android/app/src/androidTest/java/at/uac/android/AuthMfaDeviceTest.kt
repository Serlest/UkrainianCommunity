package at.uac.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalCallableFailure
import at.uac.android.core.LocalFirebase
import at.uac.android.core.LocalFunctions
import at.uac.android.feature.auth.*
import com.google.firebase.firestore.Source
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Actual local SDK/handler denial evidence, never a real TOTP enrollment proof. */
@RunWith(AndroidJUnit4::class)
class AuthMfaDeviceTest {
    @Test
    fun unverifiedThenVerifiedWithoutTotpCannotActivateProtection() = runBlocking {
        val args = InstrumentationRegistry.getArguments()
        if (
            args.getString("expectEmulator") != "true" ||
                args.getString("expectFunctions") != "true"
        ) {
            // Explicit disabled-runtime branch, not a positive SDK/server proof.
            assertFalse(AuthSession(AuthStage.MFA_CHALLENGE).readyForActions)
            return@runBlocking
        }
        AuthEmulatorFixtures.seedLegalReference()
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val auth = LocalFirebase.auth(context)
        val database = LocalFirebase.firestore(context)
        val backend = FirebaseAuthBackend(auth)
        val profiles = FirestoreAuthProfiles(database)
        val callables = LocalFunctions.instance(context)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        val email = "authmfa-${UUID.randomUUID()}@example.invalid"
        val password = "Synthetic-MFA-Negative-Password1"
        var uid: String? = null
        try {
            backend.signOut()
            val identity = backend.create(email, password, "Synthetic MFA denial")
            uid = identity.uid
            profiles.create(
                identity.uid,
                AuthRegistration(email, "Synthetic MFA denial", "wien", "", true, true, true),
            )
            assertEquals(
                AuthProblem.VERIFICATION_PENDING,
                runCatching {
                        backend.security.factors(identity.uid)
                    }
                    .exceptionOrNull()
                    ?.let(::authProblem),
            )
            assertEquals(
                AuthProblem.VERIFICATION_PENDING,
                runCatching {
                        backend.security.beginEnrollment(identity.uid)
                    }
                    .exceptionOrNull()
                    ?.let(::authProblem),
            )
            backend.sendVerification("de")
            backend.verifyEmailCode(AuthEmulatorFixtures.actionCode(email, "VERIFY_EMAIL"))
            backend.reload()
            assertFalse(backend.refreshToken())
            assertTrue(backend.security.factors(identity.uid).isEmpty())
            backend.security.reauthenticate(identity.uid, password)
            assertFalse(backend.refreshToken())
            // Test fixture only: same synthetic user's live role is made admin.
            // No token claim is injected and no real second factor is simulated.
            withContext(Dispatchers.IO) {
                AuthEmulatorFixtures.adminRequest(
                    8088,
                    AuthEmulatorFixtures.documentPath("users/${identity.uid}") +
                        "?updateMask.fieldPaths=globalRole",
                    "PATCH",
                    mapOf("globalRole" to "admin"),
                )
            }
            val store =
                AuthStore(
                    backend,
                    profiles,
                    scope,
                    mfaActivator = LocalAuthMfaActivator(auth, database, callables),
                )
            withContext(Dispatchers.Main) { store.restore() }.join()
            assertEquals(AuthGate.MFA_REQUIRED, store.state.value.gate)
            withContext(Dispatchers.Main) { store.activateMfaProtection()!! }.join()
            assertEquals(AuthProblem.SECOND_FACTOR_REQUIRED, store.state.value.error)
            assertFalse(store.state.value.readyForActions)
            val serverFailure =
                runCatching {
                    callables
                        .getHttpsCallable("activatePrivilegedMFAProtection")
                        .call(emptyMap<String, Any>())
                        .await()
                }
                    .exceptionOrNull()
                    ?: throw AssertionError(
                        "Server must reject activation without an actual TOTP sign-in"
                    )
            assertEquals(
                LocalCallableFailure.FAILED_PRECONDITION,
                (serverFailure as LocalCallableException).code,
            )
            val profile =
                database.collection("users").document(identity.uid).get(Source.SERVER).await()
            assertNotEquals(true, profile.getBoolean("requiresMultiFactorAuth"))
            assertNull(profile.getTimestamp("multiFactorAuthRequiredAt"))
        } finally {
            scope.cancel()
            val ownUid = uid
            if (ownUid != null && backend.current?.uid == ownUid) backend.deleteCreatedUser(ownUid)
            backend.signOut()
            if (ownUid != null)
                withContext(Dispatchers.IO) {
                    listOf("users/$ownUid", "publicProfiles/$ownUid").forEach { path ->
                        AuthEmulatorFixtures.adminRequest(
                            8088,
                            AuthEmulatorFixtures.documentPath(path),
                            "DELETE",
                        )
                    }
                }
        }
    }
}
