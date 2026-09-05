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
import at.uac.android.feature.platformrolemanagement.*
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseAuth
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/** Actual SDK negative authorization. No manufactured TOTP claim or privileged positive fixture. */
@RunWith(AndroidJUnit4::class)
class PlatformRoleDeviceTest {
    private val instrumentation
        get() = InstrumentationRegistry.getInstrumentation()

    private val context
        get() = instrumentation.targetContext

    private val reason = "Synthetic platform-role reason"
    private val targetId = "synthetic-platform-role-target"

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

    private fun entry(session: ModerationSession, action: PlatformRoleAction) =
        PlatformRoleRecovery.prepared(
                session,
                PlatformRoleRecovery.snapshot(
                    targetId,
                    mapOf(
                        "globalRole" to action.previousRole,
                        "accountStatus" to "active",
                        "blockState" to "active",
                    ),
                ),
                action,
                reason,
                PlatformRoleTargetAuth(targetId, true, false),
                UUID.randomUUID().toString(),
            )
            .copy(phase = PlatformRolePhase.DISPATCHED)

    @Test
    fun actualSdkBindingIsRequiredBeforeAnyCallableCanBeCreated() {
        val auth = AppBackend.auth(context)
        val db = AppBackend.firestore(context)
        FirebasePlatformRoleSource(db, auth, AppBackend.callables(context))
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
            runCatching { FirebasePlatformRoleSource(db, auth, rejected) }.exceptionOrNull()
                is IllegalArgumentException
        )
        assertEquals(0, created)
        assertFalse(FirebaseApp.getApps(context).any { it.name == FirebaseApp.DEFAULT_APP_NAME })
    }

    @Test
    fun realUnverifiedOrdinaryUnactivatedAndNoTotpCannotReadReconcileOrSendAnyAction() =
        runBlocking {
            val fixtures = AccountStatusFixtures("status-platform-roles")
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
                val source =
                    FirebasePlatformRoleSource(AppBackend.firestore(context), auth, gateway)
                val session = ModerationSession(user.uid, 1, "owner", true)
                suspend fun accessDenied(action: suspend () -> Any?) {
                    try {
                        action()
                        fail("Actual SDK authorization must reject this session")
                    } catch (error: PlatformRoleException) {
                        assertEquals(PlatformRoleFailure.ACCESS, error.failure)
                    }
                }
                suspend fun deniedStage() {
                    accessDenied { source.read(session, targetId) }
                    accessDenied { source.targetAuth(session, targetId) }
                    accessDenied { source.changes(session, targetId).first() }
                    for (action in PlatformRoleAction.entries) {
                        val pending = entry(session, action)
                        accessDenied { source.reconcile(session, pending) }
                        accessDenied {
                            source.send(session, pending, reason) {
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
                suspend fun activateProfile(activated: Boolean, role: String = "owner") {
                    check(
                        user.email.startsWith("status-platform-roles-") &&
                            user.email.endsWith("@example.invalid")
                    )
                    check(fixtures.document(user) != null)
                    withContext(Dispatchers.IO) {
                        AuthEmulatorFixtures.adminRequest(
                            8088,
                            AuthEmulatorFixtures.documentPath("users/${user.uid}") +
                                "?updateMask.fieldPaths=globalRole&updateMask.fieldPaths=requiresMultiFactorAuth",
                            "PATCH",
                            mapOf("globalRole" to role, "requiresMultiFactorAuth" to activated),
                        )
                    }
                    val fields = checkNotNull(fixtures.document(user)).getJSONObject("fields")
                    check(fields.getJSONObject("globalRole").getString("stringValue") == role)
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
                activateProfile(true, "admin")
                deniedStage()
                val appAdmin = session.copy(role = "admin")
                accessDenied { source.read(appAdmin, targetId) }
                accessDenied { source.targetAuth(appAdmin, targetId) }
                accessDenied { source.changes(appAdmin, targetId).first() }
                for (action in PlatformRoleAction.entries) {
                    val ownerPending = entry(session, action)
                    accessDenied { source.reconcile(appAdmin, ownerPending) }
                    accessDenied {
                        source.send(appAdmin, ownerPending, reason) {
                            dispatchVetoes++
                            true
                        }
                    }
                }
                assertEquals(0, calls)
                assertEquals(0, dispatchVetoes)
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
