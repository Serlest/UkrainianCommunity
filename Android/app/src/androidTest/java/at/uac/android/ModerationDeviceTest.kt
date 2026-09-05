package at.uac.android

import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.AuthRegistration
import at.uac.android.feature.auth.registeredProfileFields
import at.uac.android.feature.moderation.*
import com.google.firebase.auth.FirebaseUser
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.Query
import com.google.firebase.firestore.Source
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Actual local SDK/Rules negatives only. Never inject TOTP claims or bypass the application Auth
 * gate.
 */
@RunWith(AndroidJUnit4::class)
class ModerationDeviceTest {
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private val online
        get() = InstrumentationRegistry.getArguments().getString("expectEmulator") == "true"

    private fun guard() {
        check(context.packageName == "at.uac.android.local")
        check(Build.HARDWARE in setOf("ranchu", "goldfish") && Build.MODEL.startsWith("sdk_gphone"))
    }

    private suspend fun expect(failure: ModerationFailure, action: suspend () -> Any?) {
        try {
            action()
            fail("Expected moderation rejection")
        } catch (error: ModerationException) {
            assertEquals(failure, error.failure)
        }
    }

    private suspend fun rulesDeny(action: suspend () -> Any?) {
        try {
            action()
            fail("Expected Rules rejection")
        } catch (error: FirebaseFirestoreException) {
            assertEquals(FirebaseFirestoreException.Code.PERMISSION_DENIED, error.code)
        }
    }

    @Test
    fun guestBoundaryDoesNotInitializeDefaultAppOrAuthorizeRead() = runBlocking {
        guard()
        val source = localModerationSource(context)
        assertEquals("demo-uac-android", LocalFirebase.auth(context).app.options.projectId)
        expect(ModerationFailure.SIGN_IN) {
            ModerationRepository(source, { null }).head(ModerationKind.NEWS)
        }
        assertFalse(
            com.google.firebase.FirebaseApp.getApps(context).any {
                it.name == com.google.firebase.FirebaseApp.DEFAULT_APP_NAME
            }
        )
    }

    @Test
    fun actualSdkRejectsForgedRoleAndMissingTotpBeforePrivateQueue() = runBlocking {
        if (!online) return@runBlocking
        guard()
        val auth = LocalFirebase.auth(context)
        val db = LocalFirebase.firestore(context)
        val source = localModerationSource(context)
        val email = "moderation-a01-${UUID.randomUUID()}@example.invalid"
        var user: FirebaseUser? = null
        var primary: Throwable? = null
        auth.signOut()
        try {
            val created =
                auth
                    .createUserWithEmailAndPassword(email, "Synthetic-moderation-only!")
                    .await()
                    .user!!
            user = created
            db.document("users/${created.uid}")
                .set(
                    registeredProfileFields(
                        created.uid,
                        AuthRegistration(
                            email,
                            "Synthetic moderation actor",
                            "wien",
                            acceptedTerms = true,
                            acceptedPrivacy = true,
                            minimumAgeConfirmed = true,
                        ),
                        FieldValue.serverTimestamp(),
                    )
                )
                .await()
            val forged = ModerationSession(created.uid, 1, "admin", true)
            expect(ModerationFailure.NOT_READY) { source.head(forged, ModerationKind.NEWS) }
            created.sendEmailVerification().await()
            auth.applyActionCode(AuthEmulatorFixtures.actionCode(email, "VERIFY_EMAIL")).await()
            created.reload().await()
            created.getIdToken(true).await()
            expect(ModerationFailure.DENIED) { source.head(forged, ModerationKind.NEWS) }
            rulesDeny {
                db.collection("news")
                    .whereEqualTo("moderationStatus", "pendingReview")
                    .orderBy("createdAt", Query.Direction.DESCENDING)
                    .limit(100)
                    .get(Source.SERVER)
                    .await()
            }
            withContext(Dispatchers.IO) {
                AuthEmulatorFixtures.adminRequest(
                    8088,
                    AuthEmulatorFixtures.documentPath("users/${created.uid}") +
                        "?updateMask.fieldPaths=globalRole&updateMask.fieldPaths=requiresMultiFactorAuth",
                    "PATCH",
                    mapOf("globalRole" to "admin", "requiresMultiFactorAuth" to false),
                )
            }
            // The backend migration condition is permissive without activation; the Android source
            // is intentionally not.
            expect(ModerationFailure.NOT_READY) { source.head(forged, ModerationKind.EVENT) }
            withContext(Dispatchers.IO) {
                AuthEmulatorFixtures.adminRequest(
                    8088,
                    AuthEmulatorFixtures.documentPath("users/${created.uid}") +
                        "?updateMask.fieldPaths=requiresMultiFactorAuth",
                    "PATCH",
                    mapOf("requiresMultiFactorAuth" to true),
                )
            }
            expect(ModerationFailure.NOT_READY) { source.head(forged, ModerationKind.ORGANIZATION) }
            rulesDeny {
                db.collection("organizations")
                    .whereEqualTo("moderationStatus", "pendingReview")
                    .orderBy("createdAt", Query.Direction.DESCENDING)
                    .limit(100)
                    .get(Source.SERVER)
                    .await()
            }
            assertNotEquals(
                "totp",
                (created.getIdToken(false).await().claims["firebase"] as? Map<*, *>)?.get(
                    "sign_in_second_factor"
                ),
            )
        } catch (error: Throwable) {
            primary = error
            throw error
        } finally {
            val failures = mutableListOf<Throwable>()
            val owned = user
            if (owned != null) {
                try {
                    check(auth.currentUser?.uid == owned.uid)
                    owned.delete().await()
                } catch (error: Throwable) {
                    failures += error
                }
                for (path in listOf("users/${owned.uid}", "publicProfiles/${owned.uid}")) {
                    try {
                        withContext(Dispatchers.IO) {
                            AuthEmulatorFixtures.adminRequest(
                                8088,
                                AuthEmulatorFixtures.documentPath(path),
                                "DELETE",
                            )
                        }
                    } catch (error: Throwable) {
                        failures += error
                    }
                }
            }
            auth.signOut()
            if (failures.isNotEmpty()) {
                val cleanup = AssertionError("Scoped moderation fixture cleanup failed")
                failures.forEach(cleanup::addSuppressed)
                if (primary != null) primary.addSuppressed(cleanup) else throw cleanup
            }
        }
    }
}
