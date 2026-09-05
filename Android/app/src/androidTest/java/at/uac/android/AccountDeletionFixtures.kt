package at.uac.android

import android.os.Build
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.*
import at.uac.android.feature.auth.*
import com.google.firebase.auth.FirebaseAuthException
import com.google.firebase.auth.FirebaseUser
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.json.JSONObject
import org.junit.Assert.*

/**
 * Destructive test fixtures fail closed on physical devices and cannot target a cloud host/project.
 */
internal object AccountDeletionFixtures {
    const val PASSWORD = "Synthetic-deletion-only-Password1!"
    val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    data class User(val uid: String, val email: String, val captured: FirebaseUser)

    fun requireLocalAvd() {
        LocalEnvironment.requireSafe()
        check(context.packageName == "at.uac.android.local")
        check(
            (Build.HARDWARE in setOf("ranchu", "goldfish") &&
                Build.MODEL.startsWith("sdk_gphone")) || isExplicitApi26CompatibilityAvd()
        ) {
            "Fixtures require a local SDK-phone emulator or the explicitly opted-in API26 compatibility AVD, never a physical device."
        }
    }

    fun online(): Boolean =
        InstrumentationRegistry.getArguments().let {
            it.getString("expectEmulator") == "true" && it.getString("expectFunctions") == "true"
        }

    suspend fun create(prefix: String, verified: Boolean = true): User {
        requireLocalAvd()
        check(prefix.matches(Regex("[a-z-]{1,30}")))
        val auth = LocalFirebase.auth(context)
        auth.signOut()
        val email = "$prefix-${UUID.randomUUID()}@example.invalid"
        val backend = FirebaseAuthBackend(auth)
        val identity = backend.create(email, PASSWORD, "Synthetic deletion account")
        FirestoreAuthProfiles(LocalFirebase.firestore(context))
            .create(
                identity.uid,
                AuthRegistration(email, "Synthetic deletion account", "wien", "", true, true, true),
            )
        if (verified) {
            backend.sendVerification("de")
            backend.verifyEmailCode(AuthEmulatorFixtures.actionCode(email, "VERIFY_EMAIL"))
            backend.reload()
            backend.refreshToken()
        }
        return User(identity.uid, email, auth.currentUser!!)
    }

    suspend fun patch(path: String, fields: Map<String, Any>, merge: Boolean = false) =
        withContext(Dispatchers.IO) {
            requireLocalAvd()
            val masks =
                if (merge) fields.keys.joinToString("&", "?") { "updateMask.fieldPaths=$it" }
                else ""
            AuthEmulatorFixtures.adminRequest(
                8088,
                AuthEmulatorFixtures.documentPath(path) + masks,
                "PATCH",
                fields,
            )
        }

    suspend fun remove(path: String) =
        withContext(Dispatchers.IO) {
            requireLocalAvd()
            AuthEmulatorFixtures.adminRequest(
                8088,
                AuthEmulatorFixtures.documentPath(path),
                "DELETE",
            )
        }

    suspend fun document(path: String): JSONObject? =
        withContext(Dispatchers.IO) {
            requireLocalAvd()
            check(
                path.split('/').size % 2 == 0 &&
                    path.split('/').all { it.isNotBlank() && it != "." && it != ".." }
            )
            val url =
                "http://${LocalEnvironment.HOST}:8088${AuthEmulatorFixtures.documentPath(path)}"
            val connection = URL(url).openConnection() as HttpURLConnection
            try {
                connection.requestMethod = "GET"
                connection.connectTimeout = 5000
                connection.readTimeout = 5000
                connection.instanceFollowRedirects = false
                connection.setRequestProperty("Authorization", "Bearer owner")
                when (val status = connection.responseCode) {
                    404 -> null
                    200 -> JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
                    else -> error("Synthetic read-back HTTP $status")
                }
            } finally {
                connection.disconnect()
            }
        }

    fun field(document: JSONObject, field: String): String? =
        document.optJSONObject("fields")?.optJSONObject(field)?.optString("stringValue")

    suspend fun assertAuthAbsent(user: User) {
        requireLocalAvd()
        try {
            user.captured.reload().await()
            fail("Deleted Auth identity must not reload")
        } catch (error: FirebaseAuthException) {
            assertEquals("ERROR_USER_NOT_FOUND", error.errorCode)
        }
    }

    suspend fun clean(user: User, paths: List<String> = emptyList()) {
        requireLocalAvd()
        check(user.email.endsWith("@example.invalid") && user.email.startsWith("deletion-"))
        val auth = LocalFirebase.auth(context)
        if (auth.currentUser?.uid == user.uid) {
            // Test cleanup only. Production implementation never uses client cascades or Auth
            // delete.
            try {
                auth.currentUser!!.delete().await()
            } catch (error: FirebaseAuthException) {
                check(
                    error.errorCode in
                        setOf(
                            "ERROR_USER_NOT_FOUND",
                            "ERROR_USER_TOKEN_EXPIRED",
                            "ERROR_INVALID_USER_TOKEN",
                        )
                )
            }
            auth.signOut()
        }
        for (path in paths + listOf("users/${user.uid}", "publicProfiles/${user.uid}")) remove(path)
    }
}
