package at.uac.android

import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.CallableCall
import at.uac.android.core.backend.CallableGateway
import at.uac.android.feature.moderation.ModerationSession
import at.uac.android.feature.userstatusmanagement.*
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseAuth
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/** Actual SDK negative authorization. No manufactured TOTP claim or privileged positive fixture. */
@RunWith(AndroidJUnit4::class)
class UserStatusDeviceTest {
    private val instrumentation
        get() = InstrumentationRegistry.getInstrumentation()

    private val context
        get() = instrumentation.targetContext

    private val reason = "Synthetic account-status reason"
    private val targetId = "synthetic-user-status-target"

    @Before
    fun exactLocalAvd() {
        LocalEnvironment.requireSafe()
        check(context.packageName == "at.uac.android.local")
        check(InstrumentationRegistry.getArguments().getString("expectEmulator") == "true")
        fun property(name: String) =
            ParcelFileDescriptor.AutoCloseInputStream(
                    instrumentation.uiAutomation.executeShellCommand("getprop $name")
                )
                .bufferedReader()
                .use { it.readLine()?.trim() }
        val primary =
            Build.VERSION.SDK_INT == 37 &&
                Build.HARDWARE == "ranchu" &&
                Build.MODEL.startsWith("sdk_gphone") &&
                property("ro.kernel.qemu") == "1" &&
                property("ro.boot.qemu.avd_name") == "UAC_API_37_Play_ARM64"
        check(primary || isExplicitApi26CompatibilityAvd())
    }

    private fun entry(session: ModerationSession, action: UserStatusAction, until: Instant?) =
        UserStatusContract.prepared(
                session,
                UserStatusContract.snapshot(
                    targetId,
                    mapOf(
                        "globalRole" to "user",
                        "accountStatus" to
                            if (action == UserStatusAction.RESTORE) "bannedPermanent" else "active",
                        "blockState" to
                            if (action == UserStatusAction.RESTORE) "bannedPermanent" else "active",
                        "warningCount" to 2L,
                    ),
                ),
                action,
                reason,
                until,
                UUID.randomUUID().toString(),
            )
            .copy(phase = UserStatusPhase.DISPATCHED)

    @Test
    fun actualSdkBindingIsRequiredBeforeAnyCallableCanBeCreated() {
        val auth = AppBackend.auth(context)
        val db = AppBackend.firestore(context)
        FirebaseUserStatusSource(db, auth, AppBackend.callables(context))
        var created = 0
        val rejected =
            object : CallableGateway {
                override fun requireBoundTo(auth: FirebaseAuth) {
                    throw IllegalArgumentException("Synthetic binding mismatch")
                }

                override fun getHttpsCallable(name: String): CallableCall {
                    created++
                    error("A rejected gateway cannot be used")
                }
            }
        assertTrue(
            runCatching { FirebaseUserStatusSource(db, auth, rejected) }.exceptionOrNull()
                is IllegalArgumentException
        )
        assertEquals(0, created)
        assertFalse(FirebaseApp.getApps(context).any { it.name == FirebaseApp.DEFAULT_APP_NAME })
    }

    @Test
    fun realUnverifiedOrdinaryUnactivatedAndNoTotpCannotReadReconcileOrSendAnyAction() =
        runBlocking {
            val fixtures = AccountStatusFixtures("status-user-actions")
            var primary: Throwable? = null
            try {
                val user = fixtures.create(verified = false)
                val auth = AppBackend.auth(context)
                val real = AppBackend.callables(context)
                var calls = 0
                var dispatchVetoes = 0
                val gateway =
                    object : CallableGateway {
                        override fun requireBoundTo(auth: FirebaseAuth) = real.requireBoundTo(auth)

                        override fun getHttpsCallable(name: String): CallableCall {
                            calls++
                            return real.getHttpsCallable(name)
                        }
                    }
                val source = FirebaseUserStatusSource(AppBackend.firestore(context), auth, gateway)
                val session = ModerationSession(user.uid, 1, "admin", true)
                suspend fun accessDenied(action: suspend () -> Any?) {
                    try {
                        action()
                        fail("Actual SDK authorization must reject this session")
                    } catch (error: UserStatusException) {
                        assertEquals(UserStatusFailure.ACCESS, error.failure)
                    }
                }
                suspend fun deniedStage() {
                    accessDenied { source.read(session, targetId) }
                    for (action in UserStatusAction.entries) {
                        val until =
                            if (action == UserStatusAction.SUSPEND)
                                Instant.now().plusSeconds(86_400).let {
                                    Instant.ofEpochMilli(it.toEpochMilli())
                                }
                            else null
                        val pending = entry(session, action, until)
                        accessDenied { source.reconcile(session, pending) }
                        accessDenied {
                            source.send(session, pending, reason, until) {
                                dispatchVetoes++
                                true
                            }
                        }
                    }
                    assertEquals(0, calls)
                    assertEquals(0, dispatchVetoes)
                }
                deniedStage()
                val actual = checkNotNull(auth.currentUser)
                actual.sendEmailVerification().await()
                auth
                    .applyActionCode(AuthEmulatorFixtures.actionCode(user.email, "VERIFY_EMAIL"))
                    .await()
                actual.reload().await()
                actual.getIdToken(true).await()
                deniedStage()
                suspend fun activateProfile(activated: Boolean) {
                    check(
                        user.email.startsWith("status-user-actions-") &&
                            user.email.endsWith("@example.invalid")
                    )
                    check(fixtures.document(user) != null)
                    withContext(Dispatchers.IO) {
                        AuthEmulatorFixtures.adminRequest(
                            8088,
                            AuthEmulatorFixtures.documentPath("users/${user.uid}") +
                                "?updateMask.fieldPaths=globalRole&updateMask.fieldPaths=requiresMultiFactorAuth",
                            "PATCH",
                            mapOf("globalRole" to "admin", "requiresMultiFactorAuth" to activated),
                        )
                    }
                    val fields = checkNotNull(fixtures.document(user)).getJSONObject("fields")
                    check(fields.getJSONObject("globalRole").getString("stringValue") == "admin")
                    check(
                        fields
                            .getJSONObject("requiresMultiFactorAuth")
                            .getBoolean("booleanValue") == activated
                    )
                }
                activateProfile(false)
                deniedStage()
                activateProfile(true)
                deniedStage()
                assertNotEquals(
                    "totp",
                    (actual.getIdToken(false).await().claims["firebase"] as? Map<*, *>)?.get(
                        "sign_in_second_factor"
                    ),
                )
                // Changed SDK identity is cancellation, not an offline or uncertain-mutation
                // result.
                auth.signOut()
                try {
                    source.read(session, targetId)
                    fail("A signed-out SDK identity cannot read")
                } catch (_: CancellationException) {
                    assertEquals(0, calls)
                }
            } catch (error: Throwable) {
                primary = error
                throw error
            } finally {
                fixtures.cleanup(primary)
            }
        }
}
