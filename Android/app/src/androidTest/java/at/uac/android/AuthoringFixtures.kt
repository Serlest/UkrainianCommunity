package at.uac.android

import android.os.Build
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalEnvironment
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.organization.OrganizationContract
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

/**
 * Test APK only. Exact new identities, new organizations and registered content IDs; never a
 * recursive delete.
 */
internal class AuthoringFixtures(private val prefix: String) {
    init {
        LocalEnvironment.requireSafe()
        check(prefix.startsWith("author4c") && OrganizationContract.id(prefix))
        check(
            InstrumentationRegistry.getInstrumentation().targetContext.packageName ==
                "at.uac.android.local"
        )
        check(
            (Build.HARDWARE in setOf("ranchu", "goldfish") &&
                Build.MODEL.startsWith("sdk_gphone")) || isExplicitApi26CompatibilityAvd()
        )
    }

    val organizationId = "$prefix-org"
    val foreignOrganizationId = "$prefix-foreign"
    val uids = linkedSetOf<String>()
    private val content = linkedSetOf<String>()
    private val seeded = linkedSetOf<String>()

    fun ownContent(kind: ContentKind, id: String) {
        require(kind in setOf(ContentKind.NEWS, ContentKind.EVENTS) && OrganizationContract.id(id))
        content += "${kind.collection}/$id"
    }

    private fun allowed(path: String) =
        path.split('/').size == 2 &&
            (path in content ||
                path in
                    setOf(
                        "organizations/$organizationId",
                        "organizations/$foreignOrganizationId",
                    ) ||
                path in uids.flatMap { listOf("users/$it", "publicProfiles/$it") })

    suspend fun seed(path: String, fields: Map<String, Any?>) {
        require(allowed(path))
        seeded += path
        request(
            8088,
            document(path),
            "PATCH",
            JSONObject().put("fields", JSONObject(fields.mapValues { value(it.value) })),
        )
    }

    /**
     * Re-register only a known synthetic path from a validated cold-process marker; performs no
     * network write.
     */
    fun rememberExisting(path: String) {
        require(allowed(path))
        seeded += path
    }

    suspend fun patch(path: String, fields: Map<String, Any?>) {
        require(allowed(path) && fields.keys.all { it.matches(Regex("[A-Za-z]+")) })
        request(
            8088,
            document(path) + "?" + fields.keys.joinToString("&") { "updateMask.fieldPaths=$it" },
            "PATCH",
            JSONObject().put("fields", JSONObject(fields.mapValues { value(it.value) })),
        )
    }

    suspend fun cleanup(previousFailure: Throwable? = null) {
        val steps = mutableListOf<suspend () -> Unit>()
        for (path in (content + seeded).toList().reversed()) steps += suspend {
            require(allowed(path))
            request(8088, document(path), "DELETE")
        }
        for (uid in uids.toList()) {
            for (path in listOf("users/$uid", "publicProfiles/$uid")) steps += suspend {
                require(allowed(path))
                request(8088, document(path), "DELETE")
            }
            steps += suspend {
                require(uid in uids)
                request(
                    9098,
                    "/identitytoolkit.googleapis.com/v1/projects/demo-uac-android/accounts:delete",
                    "POST",
                    JSONObject().put("localId", uid),
                )
            }
        }
        cleanupEveryOwnedFixtureItem(steps, previousFailure) { it() }
    }

    private fun document(path: String) =
        "/v1/projects/demo-uac-android/databases/(default)/documents/$path"

    private suspend fun request(
        port: Int,
        path: String,
        method: String,
        data: JSONObject? = null,
    ): Unit =
        withContext(Dispatchers.IO) {
            LocalEnvironment.requireSafe()
            check(port in setOf(8088, 9098) && path.contains("/demo-uac-android/"))
            val connection = URL("http://10.0.2.2:$port$path").openConnection() as HttpURLConnection
            try {
                connection.connectTimeout = 5_000
                connection.readTimeout = 5_000
                connection.instanceFollowRedirects = false
                connection.requestMethod = method
                connection.setRequestProperty("Authorization", "Bearer owner")
                if (data != null) {
                    connection.doOutput = true
                    connection.setRequestProperty("Content-Type", "application/json")
                    connection.outputStream.use { it.write(data.toString().toByteArray()) }
                }
                if (method == "DELETE" && connection.responseCode == 404) return@withContext
                check(connection.responseCode in 200..299) {
                    "Scoped authoring fixture HTTP ${connection.responseCode}"
                }
            } finally {
                connection.disconnect()
            }
        }

    private fun value(item: Any?): JSONObject =
        when (item) {
            null -> JSONObject().put("nullValue", JSONObject.NULL)
            is String -> JSONObject().put("stringValue", item)
            is Boolean -> JSONObject().put("booleanValue", item)
            is Int,
            is Long -> JSONObject().put("integerValue", item.toString())
            is Float,
            is Double ->
                JSONObject()
                    .put("doubleValue", (item as Number).toDouble().also { check(it.isFinite()) })
            is Instant -> JSONObject().put("timestampValue", item.toString())
            is Map<*, *> ->
                JSONObject()
                    .put(
                        "mapValue",
                        JSONObject()
                            .put(
                                "fields",
                                JSONObject(
                                    item.entries.associate { it.key.toString() to value(it.value) }
                                ),
                            ),
                    )
            is List<*> ->
                JSONObject()
                    .put("arrayValue", JSONObject().put("values", JSONArray(item.map(::value))))
            else -> error("Unsupported authoring fixture field")
        }
}

/**
 * Continue through every exact owned target; preserve the original test failure and all cleanup
 * errors.
 */
internal suspend fun <T> cleanupEveryOwnedFixtureItem(
    items: Iterable<T>,
    previousFailure: Throwable? = null,
    action: suspend (T) -> Unit,
): Unit =
    withContext(NonCancellable) {
        var failure = previousFailure
        for (item in items) {
            try {
                action(item)
            } catch (error: Throwable) {
                if (failure == null) failure = error
                else if (failure !== error) failure.addSuppressed(error)
            }
        }
        if (previousFailure == null) failure?.let { throw it }
    }
