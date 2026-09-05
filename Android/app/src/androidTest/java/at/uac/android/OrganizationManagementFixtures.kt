package at.uac.android

import android.os.Build
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalEnvironment
import at.uac.android.feature.organization.OrganizationContract
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

/** Owned synthetic identities and documents only; shared by actual SDK and Main journey tests. */
internal class OrganizationManagementFixtures(
    private val prefix: String,
    private val organizationId: String,
) {
    init {
        LocalEnvironment.requireSafe()
        check(
            prefix.startsWith("org4b") &&
                OrganizationContract.id(prefix) &&
                organizationId == "$prefix-org"
        )
        check(
            InstrumentationRegistry.getInstrumentation().targetContext.packageName ==
                "at.uac.android.local"
        )
        check(
            (Build.HARDWARE in setOf("ranchu", "goldfish") &&
                Build.MODEL.startsWith("sdk_gphone")) || isExplicitApi26CompatibilityAvd()
        )
    }

    val uids = linkedSetOf<String>()
    private val paths = linkedSetOf<String>()

    private fun allowed(path: String) =
        path == "organizations/$organizationId" ||
            path in
                uids.flatMap {
                    listOf(
                        "users/$it",
                        "publicProfiles/$it",
                        "likes/organization_follow_${organizationId}_$it",
                    )
                } ||
            uids.any {
                path.startsWith("users/$it/notificationInbox/") && path.split('/').size == 4
            }

    suspend fun seed(path: String, fields: Map<String, Any?>) {
        require(allowed(path))
        paths += path
        request(
            8088,
            document(path),
            "PATCH",
            JSONObject().put("fields", JSONObject(fields.mapValues { value(it.value) })),
        )
    }

    suspend fun patch(path: String, fields: Map<String, Any?>) {
        require(allowed(path))
        require(fields.keys.all { it.matches(Regex("[A-Za-z]+")) })
        val mask = fields.keys.joinToString("&") { "updateMask.fieldPaths=$it" }
        request(
            8088,
            document(path) + "?$mask",
            "PATCH",
            JSONObject().put("fields", JSONObject(fields.mapValues { value(it.value) })),
        )
    }

    suspend fun delete(path: String) {
        require(allowed(path))
        request(8088, document(path), "DELETE")
    }

    suspend fun authAccount(
        uid: String,
        operation: String,
        fields: Map<String, Any?> = emptyMap(),
    ) {
        require(
            uid in uids &&
                operation in setOf("update", "delete") &&
                fields.keys.all { it == "disableUser" }
        )
        request(
            9098,
            "/identitytoolkit.googleapis.com/v1/projects/demo-uac-android/accounts:$operation",
            "POST",
            JSONObject(fields + ("localId" to uid)),
        )
    }

    suspend fun roleAuditIds(actorId: String): List<String> {
        require(actorId in uids)
        val query =
            JSONObject()
                .put(
                    "structuredQuery",
                    JSONObject()
                        .put("from", JSONArray().put(JSONObject().put("collectionId", "auditLogs")))
                        .put(
                            "where",
                            JSONObject()
                                .put(
                                    "fieldFilter",
                                    JSONObject()
                                        .put("field", JSONObject().put("fieldPath", "performedBy"))
                                        .put("op", "EQUAL")
                                        .put("value", value(actorId)),
                                ),
                        )
                        .put("limit", 100),
                )
        val raw =
            request(
                8088,
                "/v1/projects/demo-uac-android/databases/(default)/documents:runQuery",
                "POST",
                query,
            )
        val rows = JSONArray(raw)
        return (0 until rows.length())
            .mapNotNull { rows.getJSONObject(it).optJSONObject("document") }
            .map { document ->
                val fields = document.getJSONObject("fields")
                check(fields.getJSONObject("performedBy").getString("stringValue") == actorId)
                check(
                    fields
                        .getJSONObject("newValue")
                        .getJSONObject("mapValue")
                        .getJSONObject("fields")
                        .getJSONObject("organizationId")
                        .getString("stringValue") == organizationId
                )
                document.getString("name").substringAfter("/documents/").also {
                    check(it.startsWith("auditLogs/") && it.split('/').size == 2)
                }
            }
            .also { check(it.size < 100) }
    }

    suspend fun cleanup(previousFailure: Throwable? = null) {
        try {
            cleanupOwned()
        } catch (cleanupFailure: Throwable) {
            if (previousFailure == null) throw cleanupFailure
            previousFailure.addSuppressed(cleanupFailure)
        }
    }

    private suspend fun cleanupOwned() {
        // Only auto-ID receipts under these newly created identities / this exact organization are
        // removed.
        for (uid in uids) {
            for (path in roleAuditIds(uid)) request(8088, document(path), "DELETE")
            val data =
                JSONObject(
                    request(8088, document("users/$uid/notificationInbox") + "?pageSize=100", "GET")
                )
            val notices = data.optJSONArray("documents") ?: JSONArray()
            check(notices.length() < 100 && !data.has("nextPageToken"))
            for (index in 0 until notices.length()) {
                val notice = notices.getJSONObject(index)
                val fields = notice.getJSONObject("fields")
                check(fields.getJSONObject("sourceId").getString("stringValue") == organizationId)
                delete(notice.getString("name").substringAfter("/documents/"))
            }
        }
        storageDelete()
        for (path in paths.toList().asReversed()) delete(path)
        for (uid in uids) {
            delete("users/$uid")
            delete("publicProfiles/$uid")
            authAccount(uid, "delete")
        }
    }

    private suspend fun storageDelete() {
        check(organizationId.startsWith(prefix) && OrganizationContract.id(organizationId))
        request(
            9198,
            "/v0/b/demo-uac-android.appspot.com/o/organizations%2F$organizationId%2Flogo.jpg",
            "DELETE",
        )
    }

    private fun document(path: String) =
        "/v1/projects/demo-uac-android/databases/(default)/documents/$path"

    private suspend fun request(
        port: Int,
        path: String,
        method: String,
        data: JSONObject? = null,
    ): String =
        withContext(Dispatchers.IO) {
            LocalEnvironment.requireSafe()
            check(
                port in setOf(8088, 9098, 9198) &&
                    (path.contains("/demo-uac-android/") ||
                        path.contains("/demo-uac-android.appspot.com/"))
            )
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
                if (method == "DELETE" && connection.responseCode == 404) return@withContext "{}"
                check(connection.responseCode in 200..299) {
                    "Scoped organization management fixture HTTP ${connection.responseCode}"
                }
                connection.inputStream.bufferedReader().use { it.readText() }.ifBlank { "{}" }
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
            else -> error("Unsupported synthetic fixture field")
        }
}
