package at.uac.android

import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.AuthRegistration
import at.uac.android.feature.auth.FirebaseAuthBackend
import at.uac.android.feature.auth.FirestoreAuthProfiles
import java.net.HttpURLConnection
import java.net.Proxy
import java.net.URL
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

/** Test APK only: only this instance's newly created synthetic users may be read or mutated. */
internal class AccountStatusFixtures(private val prefix: String) {
    val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    val password = "Synthetic-status-only-Password1!"
    private val users = linkedMapOf<String, User>()

    data class User(val uid: String, val email: String)

    init {
        requireLocal()
        check(prefix.matches(Regex("status-[a-z-]{1,24}")))
    }

    private fun requireLocal() {
        AccountDeletionFixtures.requireLocalAvd()
        check(InstrumentationRegistry.getArguments().getString("expectEmulator") == "true")
        check(LocalEnvironment.PROJECT_ID == "demo-uac-android")
    }

    private fun own(user: User) {
        requireLocal()
        check(users[user.uid] == user && user.email.startsWith("$prefix-"))
        check(user.email.endsWith("@example.invalid"))
    }

    suspend fun create(verified: Boolean = true): User {
        requireLocal()
        AuthEmulatorFixtures.seedLegalReference()
        val auth = LocalFirebase.auth(context)
        val backend = FirebaseAuthBackend(auth)
        backend.signOut()
        val email = "$prefix-${UUID.randomUUID()}@example.invalid"
        try {
            val identity = backend.create(email, password, "Synthetic status account")
            val user = User(identity.uid, email)
            users[user.uid] = user
            FirestoreAuthProfiles(LocalFirebase.firestore(context))
                .create(
                    user.uid,
                    AuthRegistration(
                        email,
                        "Synthetic status account",
                        "wien",
                        "",
                        true,
                        true,
                        true,
                    ),
                )
            if (verified) {
                backend.sendVerification("de")
                backend.verifyEmailCode(AuthEmulatorFixtures.actionCode(email, "VERIFY_EMAIL"))
                backend.reload()
                backend.refreshToken()
            }
            return user
        } finally {
            // A partially completed SDK create must still leave an exact cleanup target.
            auth.currentUser
                ?.takeIf { it.email == email }
                ?.let {
                    users[it.uid] = User(it.uid, email)
                }
        }
    }

    suspend fun status(
        user: User,
        status: String,
        block: String = "active",
        updatedAt: Instant = Instant.now().minusSeconds(2),
        reason: String? = null,
        message: String? = null,
        expiresAt: Instant? = null,
    ) {
        check(
            status in setOf("active", "warned", "suspendedUntil", "bannedPermanent", "deactivated")
        )
        check(
            block in
                setOf(
                    "active",
                    "warned",
                    "suspendedUntil",
                    "bannedPermanent",
                    "deactivated",
                    "blocked",
                )
        )
        patch(
            user,
            mapOf(
                "accountStatus" to status,
                "blockState" to block,
                "statusUpdatedAt" to updatedAt,
                "statusAcknowledgedAt" to null,
                "statusReason" to reason,
                "statusMessage" to message,
                "banExpiresAt" to expiresAt,
            ),
        )
    }

    /** Exact small fixture fields only; never an arbitrary collection, UID or field path. */
    suspend fun patch(user: User, fields: Map<String, Any?>) {
        own(user)
        check(fields.isNotEmpty() && fields.keys.all { it in PATCH_FIELDS })
        request(
            8088,
            documentPath(user.uid) +
                "?" +
                fields.keys.joinToString("&") { "updateMask.fieldPaths=$it" },
            "PATCH",
            JSONObject().put("fields", JSONObject(fields.mapValues { value(it.value) })),
        )
    }

    suspend fun document(user: User): JSONObject? {
        own(user)
        return request(8088, documentPath(user.uid), "GET", absentAllowed = true)
    }

    /** Compare complete Firestore fields without depending on JSON response key order. */
    suspend fun fingerprint(user: User): String {
        val fields = requireNotNull(document(user)).getJSONObject("fields")
        val digest =
            java.security.MessageDigest.getInstance("SHA-256")
                .digest(canonical(fields).toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it.toInt() and 255) }
    }

    private fun canonical(value: Any?): String =
        when (value) {
            is JSONObject ->
                value.keys().asSequence().toList().sorted().joinToString(",", "{", "}") {
                    JSONObject.quote(it) + ":" + canonical(value.get(it))
                }
            is JSONArray ->
                (0 until value.length()).joinToString(",", "[", "]") { canonical(value.get(it)) }
            is String -> JSONObject.quote(value)
            null,
            JSONObject.NULL -> "null"
            else -> value.toString()
        }

    suspend fun cleanup(previousFailure: Throwable? = null) {
        requireLocal()
        val steps = mutableListOf<suspend () -> Unit>()
        for (user in users.values.toList()) {
            for (collection in listOf("users", "publicProfiles")) steps += suspend {
                own(user)
                val path = documentPath(user.uid, collection)
                request(8088, path, "DELETE", absentAllowed = true)
                check(request(8088, path, "GET", absentAllowed = true) == null) {
                    "Exact synthetic status document cleanup was not confirmed"
                }
            }
            steps += suspend {
                own(user)
                val account = JSONObject().put("localId", JSONArray().put(user.uid))
                val existing =
                    request(9098, AUTH_ROOT + "accounts:lookup", "POST", account)
                        ?.optJSONArray("users")
                if (existing != null && existing.length() != 0) {
                    check(
                        existing.length() == 1 &&
                            existing.getJSONObject(0).getString("localId") == user.uid
                    )
                    request(
                        9098,
                        AUTH_ROOT + "accounts:delete",
                        "POST",
                        JSONObject().put("localId", user.uid),
                    )
                }
                val after =
                    request(9098, AUTH_ROOT + "accounts:lookup", "POST", account)
                        ?.optJSONArray("users")
                check(after == null || after.length() == 0) {
                    "Exact synthetic status identity cleanup was not confirmed"
                }
            }
        }
        steps += suspend {
            val auth = LocalFirebase.auth(context)
            if (auth.currentUser?.uid in users.keys) auth.signOut()
        }
        cleanupEveryOwnedFixtureItem(steps, previousFailure) { it() }
    }

    private fun documentPath(uid: String, collection: String = "users"): String {
        check(uid in users && collection in setOf("users", "publicProfiles"))
        return "/v1/projects/demo-uac-android/databases/(default)/documents/$collection/$uid"
    }

    private suspend fun request(
        port: Int,
        path: String,
        method: String,
        payload: JSONObject? = null,
        absentAllowed: Boolean = false,
    ): JSONObject? =
        withContext(Dispatchers.IO) {
            requireLocal()
            check(port in setOf(8088, 9098) && path.contains("/demo-uac-android/"))
            check(method in setOf("GET", "PATCH", "DELETE", "POST"))
            val connection =
                URL("http://10.0.2.2:$port$path").openConnection(Proxy.NO_PROXY)
                    as HttpURLConnection
            try {
                connection.requestMethod = method
                connection.connectTimeout = 5_000
                connection.readTimeout = 5_000
                connection.instanceFollowRedirects = false
                connection.setRequestProperty("Authorization", "Bearer owner")
                if (payload != null) {
                    val bytes = payload.toString().toByteArray(Charsets.UTF_8)
                    check(bytes.size <= 64 * 1024)
                    connection.doOutput = true
                    connection.setRequestProperty("Content-Type", "application/json")
                    connection.setFixedLengthStreamingMode(bytes.size)
                    connection.outputStream.use { it.write(bytes) }
                }
                val code = connection.responseCode
                if (code == 404 && absentAllowed) return@withContext null
                check(code in 200..299) { "Scoped synthetic status fixture HTTP $code" }
                val bytes =
                    connection.inputStream.use { input ->
                        val output = java.io.ByteArrayOutputStream()
                        val buffer = ByteArray(4096)
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            check(output.size() + count <= 1024 * 1024)
                            output.write(buffer, 0, count)
                        }
                        output.toByteArray()
                    }
                if (bytes.isEmpty()) JSONObject() else JSONObject(bytes.toString(Charsets.UTF_8))
            } finally {
                connection.disconnect()
            }
        }

    private fun value(item: Any?): JSONObject =
        when (item) {
            null -> JSONObject().put("nullValue", JSONObject.NULL)
            is String -> JSONObject().put("stringValue", item)
            is Boolean -> JSONObject().put("booleanValue", item)
            is Instant -> JSONObject().put("timestampValue", item.toString())
            else -> error("Unsupported synthetic status fixture value")
        }

    private companion object {
        const val AUTH_ROOT = "/identitytoolkit.googleapis.com/v1/projects/demo-uac-android/"
        val PATCH_FIELDS =
            setOf(
                "accountStatus",
                "blockState",
                "statusUpdatedAt",
                "statusAcknowledgedAt",
                "statusReason",
                "statusMessage",
                "banExpiresAt",
                "id",
                "acceptedTermsVersion",
                "acceptedPrivacyVersion",
            )
    }
}
