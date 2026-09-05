package at.uac.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalCallableFailure
import at.uac.android.core.LocalFirebase
import at.uac.android.core.LocalFunctions
import at.uac.android.feature.auth.AuthRegistration
import at.uac.android.feature.auth.registeredProfileFields
import at.uac.android.feature.moderation.ModerationSession
import at.uac.android.feature.usermanagement.*
import com.google.firebase.FirebaseApp
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
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Real named demo SDK/Rules denial proof only; no manufactured TOTP token or privileged success.
 */
@RunWith(AndroidJUnit4::class)
class ManagedUsersDeviceTest {
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private val online
        get() =
            InstrumentationRegistry.getArguments().let {
                it.getString("expectEmulator") == "true" &&
                    it.getString("expectFunctions") == "true"
            }

    private suspend fun fails(expected: ManagedUsersFailure, operation: suspend () -> Any?) {
        try {
            operation()
            fail("Expected protected read rejection")
        } catch (error: ManagedUsersException) {
            assertEquals(expected, error.failure)
        }
    }

    @Test
    fun namedBackendRejectsUnreadyInputWithoutDefaultFirebase() = runBlocking {
        AccountDeletionFixtures.requireLocalAvd()
        val source = localManagedUsersSource(context)
        fails(ManagedUsersFailure.NOT_READY) {
            source.page(ModerationSession("synthetic-unready", 1, "admin", false), null)
        }
        assertEquals("demo-uac-android", LocalFirebase.auth(context).app.options.projectId)
        assertFalse(FirebaseApp.getApps(context).any { it.name == FirebaseApp.DEFAULT_APP_NAME })
    }

    @Test
    fun verifiedOrdinaryAndActivatedManagerWithoutTotpCannotReadManagedUsers() = runBlocking {
        assumeTrue("Requires the explicit named demo Auth/Firestore/Functions runtime", online)
        AccountDeletionFixtures.requireLocalAvd()
        val auth = LocalFirebase.auth(context)
        val db = LocalFirebase.firestore(context)
        val functions = LocalFunctions.instance(context)
        val source = localManagedUsersSource(context)
        val email = "a02-${UUID.randomUUID()}@example.invalid"
        var owned: FirebaseUser? = null
        var primary: Throwable? = null
        auth.signOut()
        try {
            val user =
                auth
                    .createUserWithEmailAndPassword(email, "Synthetic-A02-Negatives-Only1!")
                    .await()
                    .user!!
            owned = user
            db.document("users/${user.uid}")
                .set(
                    registeredProfileFields(
                        user.uid,
                        AuthRegistration(
                            email,
                            "Synthetic managed-users denial",
                            "wien",
                            acceptedTerms = true,
                            acceptedPrivacy = true,
                            minimumAgeConfirmed = true,
                        ),
                        FieldValue.serverTimestamp(),
                    )
                )
                .await()
            val forged = ModerationSession(user.uid, 1, "admin", true)
            fails(ManagedUsersFailure.NOT_READY) { source.page(forged, null) }
            user.sendEmailVerification().await()
            auth.applyActionCode(AuthEmulatorFixtures.actionCode(email, "VERIFY_EMAIL")).await()
            user.reload().await()
            user.getIdToken(true).await()
            fails(ManagedUsersFailure.DENIED) { source.page(forged, null) }
            val denied = runCatching {
                db.collection("users")
                    .orderBy("createdAt", Query.Direction.DESCENDING)
                    .limit(40)
                    .get(Source.SERVER)
                    .await()
            }
                .exceptionOrNull()
            assertEquals(
                FirebaseFirestoreException.Code.PERMISSION_DENIED,
                (denied as? FirebaseFirestoreException)?.code,
            )
            for ((name, data) in
                listOf(
                    "searchManagedUsers" to mapOf("query" to "synthetic a02", "limit" to 100),
                    "getManagedUserSecurityMetadata" to mapOf("targetUserId" to user.uid),
                )) {
                val error = runCatching {
                    functions.getHttpsCallable(name).call(data).await()
                }
                    .exceptionOrNull()
                assertEquals(
                    LocalCallableFailure.PERMISSION_DENIED,
                    (error as? LocalCallableException)?.code,
                )
            }
            withContext(Dispatchers.IO) {
                AuthEmulatorFixtures.adminRequest(
                    8088,
                    AuthEmulatorFixtures.documentPath("users/${user.uid}") +
                        "?updateMask.fieldPaths=globalRole&updateMask.fieldPaths=requiresMultiFactorAuth",
                    "PATCH",
                    mapOf("globalRole" to "admin", "requiresMultiFactorAuth" to true),
                )
            }
            val before = db.document("users/${user.uid}").get(Source.SERVER).await().data
            fails(ManagedUsersFailure.NOT_READY) { source.page(forged, null) }
            fails(ManagedUsersFailure.NOT_READY) {
                source.search(forged, ManagedUsersQuery.from("synthetic a02"))
            }
            fails(ManagedUsersFailure.NOT_READY) { source.security(forged, user.uid) }
            val functionFailure = runCatching {
                functions
                    .getHttpsCallable("getManagedUserSecurityMetadata")
                    .call(mapOf("targetUserId" to user.uid))
                    .await()
            }
                .exceptionOrNull()
            assertEquals(
                LocalCallableFailure.FAILED_PRECONDITION,
                (functionFailure as? LocalCallableException)?.code,
            )
            assertNotEquals(
                "totp",
                (user.getIdToken(false).await().claims["firebase"] as? Map<*, *>)?.get(
                    "sign_in_second_factor"
                ),
            )
            assertEquals(before, db.document("users/${user.uid}").get(Source.SERVER).await().data)
        } catch (error: Throwable) {
            primary = error
            throw error
        } finally {
            val failures = mutableListOf<Throwable>()
            owned?.let { user ->
                try {
                    check(auth.currentUser?.uid == user.uid)
                    user.delete().await()
                } catch (error: Throwable) {
                    failures += error
                }
                for (path in listOf("users/${user.uid}", "publicProfiles/${user.uid}")) try {
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
            auth.signOut()
            if (failures.isNotEmpty()) {
                val cleanup = AssertionError("Scoped A02 fixture cleanup failed")
                failures.forEach(cleanup::addSuppressed)
                if (primary != null) primary.addSuppressed(cleanup) else throw cleanup
            }
        }
    }
}
