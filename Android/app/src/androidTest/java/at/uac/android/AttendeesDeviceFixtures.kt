package at.uac.android

import at.uac.android.core.LocalEnvironment
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

/**
 * Registered new synthetic paths only. This helper cannot query or clear a collection or target a
 * physical phone.
 */
internal class AttendeesDeviceFixtures(private val prefix: String, private val managerUid: String) {
    init {
        AccountDeletionFixtures.requireLocalAvd()
        require(prefix.matches(Regex("attendees-[a-f0-9-]{36}")))
        require(managerUid.matches(Regex("[A-Za-z0-9_-]{1,128}")))
    }

    val eventId = "$prefix-event"
    val organizationId = "$prefix-org"
    val time: Instant = Instant.parse("2026-09-03T10:00:00Z")
    private val seeded = linkedSetOf<String>()

    fun personId(index: Int): String {
        require(index in 0..99)
        return "$prefix-person-${index.toString().padStart(2, '0')}"
    }

    fun registrationPath(index: Int) = "registrations/event_${eventId}_${personId(index)}"

    private fun allowed(path: String): Boolean =
        path in setOf("events/$eventId", "organizations/$organizationId", "users/$managerUid") ||
            (0..99).any {
                path in
                    setOf(
                        registrationPath(it),
                        "publicProfiles/${personId(it)}",
                        "users/${personId(it)}",
                    )
            }

    suspend fun seedEventAndOrganization(count: Int) {
        seed(
            "organizations/$organizationId",
            mapOf(
                "id" to organizationId,
                "ownerId" to managerUid,
                "moderationStatus" to "approved",
                "name" to "Synthetic attendee organization",
                "adminIds" to emptyList<String>(),
                "moderatorIds" to emptyList<String>(),
                "description" to "Synthetic managed organization",
                "city" to "Wien",
                "createdAt" to time,
                "updatedAt" to time,
            ),
        )
        seed(
            "events/$eventId",
            mapOf(
                "id" to eventId,
                "sourceType" to "organization",
                "organizationId" to organizationId,
                "moderationStatus" to "approved",
                "requiresRegistration" to true,
                "registeredCount" to count,
                "capacity" to 100,
                "title" to "Synthetic managed event",
                "localizations" to
                    mapOf(
                        "de" to mapOf("title" to "Synthetic managed event"),
                        "uk" to mapOf("title" to "Тестова подія"),
                    ),
                "summary" to "Synthetic attendee management proof",
                "details" to "Synthetic managed event details",
                "city" to "Wien",
                "createdAt" to time,
                "updatedAt" to time,
                "startDate" to time,
                "endDate" to time.plusSeconds(3600),
            ),
        )
    }

    suspend fun seedPerson(index: Int, dated: Boolean = true, publicProfile: Boolean = true) {
        val path = registrationPath(index)
        seed(
            path,
            mapOf(
                "id" to path.substringAfter('/'),
                "eventId" to eventId,
                "userId" to personId(index),
            ) + if (dated) mapOf("registeredAt" to time) else emptyMap(),
        )
        if (publicProfile)
            seed(
                "publicProfiles/${personId(index)}",
                mapOf(
                    "id" to personId(index),
                    "displayName" to
                        "Synthetic public attendee ${index.toString().padStart(2, '0')}",
                ),
            )
        if (index == 0)
            seed(
                "users/${personId(index)}",
                mapOf(
                    "email" to "private-attendee@example.invalid",
                    "bio" to "Private fixture biography",
                    "displayName" to "Never use private name",
                ),
            )
    }

    private suspend fun seed(path: String, fields: Map<String, Any?>) {
        require(allowed(path))
        seeded += path
        request(path, "PATCH", fields)
    }

    suspend fun patch(path: String, fields: Map<String, Any?>) {
        require(allowed(path) && fields.keys.all { it.matches(Regex("[A-Za-z]+")) })
        val mask = fields.keys.joinToString("&", "?") { "updateMask.fieldPaths=$it" }
        request(path, "PATCH", fields, mask)
    }

    suspend fun read(path: String): JSONObject {
        require(allowed(path))
        return request(path, "GET")
    }

    suspend fun cleanup(previousFailure: Throwable? = null) {
        var failure = previousFailure
        for (path in seeded.toList().asReversed()) {
            try {
                require(allowed(path))
                request(path, "DELETE")
            } catch (error: Throwable) {
                if (failure == null) failure = error else failure.addSuppressed(error)
            }
        }
        if (previousFailure == null && failure != null) throw failure
    }

    private suspend fun request(
        path: String,
        method: String,
        fields: Map<String, Any?>? = null,
        mask: String = "",
    ): JSONObject =
        withContext(Dispatchers.IO) {
            AccountDeletionFixtures.requireLocalAvd()
            require(allowed(path))
            val connection =
                URL(
                        "http://${LocalEnvironment.HOST}:8088${AuthEmulatorFixtures.documentPath(path)}$mask"
                    )
                    .openConnection() as HttpURLConnection
            try {
                connection.connectTimeout = 5_000
                connection.readTimeout = 5_000
                connection.instanceFollowRedirects = false
                connection.requestMethod = method
                connection.setRequestProperty("Authorization", "Bearer owner")
                if (fields != null) {
                    connection.doOutput = true
                    connection.setRequestProperty("Content-Type", "application/json")
                    val body =
                        JSONObject()
                            .put("fields", JSONObject(fields.mapValues { value(it.value) }))
                            .toString()
                    connection.outputStream.use { it.write(body.toByteArray()) }
                }
                val status = connection.responseCode
                if (method == "DELETE" && status == 404) return@withContext JSONObject()
                check(status in 200..299) { "Scoped attendee fixture HTTP $status" }
                val body = connection.inputStream.bufferedReader().use { it.readText() }
                if (body.isBlank()) JSONObject() else JSONObject(body)
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
            else -> error("Unsupported attendee fixture type")
        }
}
