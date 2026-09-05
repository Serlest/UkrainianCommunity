package at.uac.android

import at.uac.android.core.LocalEnvironment
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.history.*
import com.google.firebase.firestore.Source
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

/** Cleanup proves absence, never retries a possibly completed delete or trusts HTTP 200 alone. */
internal suspend fun confirmHistoryFixtureAbsent(
    delete: suspend () -> Unit,
    absent: suspend () -> Boolean,
    reconciled: (Exception) -> Unit,
) {
    val failure =
        try {
            delete()
            null
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            error
        }
    val missing =
        try {
            absent()
        } catch (error: Exception) {
            failure?.let(error::addSuppressed)
            throw error
        }
    if (!missing) throw failure ?: IllegalStateException("Owned history fixture still exists")
    failure?.let(reconciled)
}

/** Only unique synthetic paths registered by this fixture; no list/delete-collection capability. */
internal class HistoryDeviceFixtures(val uid: String) {
    private val prefix = "history-${UUID.randomUUID()}"
    val targets = HistoryType.entries.map { HistoryTarget(it, "$prefix-${it.wire}") }
    val time: Instant = Instant.parse("2026-09-03T10:00:00Z")
    private val owned = linkedSetOf<String>()

    init {
        AccountDeletionFixtures.requireLocalAvd()
        require(uid.matches(Regex("[A-Za-z0-9_-]{1,128}")))
    }

    fun path(section: HistorySection, id: String): String {
        require(
            id.isNotBlank() &&
                '/' !in id &&
                (id.startsWith("news_${prefix}") ||
                    id.startsWith("event_${prefix}") ||
                    id.startsWith("organization_${prefix}") ||
                    id.startsWith(prefix) ||
                    runCatching { UUID.fromString(id) }.isSuccess)
        )
        return "users/$uid/${section.collection}/$id".also { owned += it }
    }

    fun marker(target: HistoryTarget): String {
        require(target in targets && target.type != HistoryType.ORGANIZATION)
        return "users/$uid/${target.type.wire}Views/${target.id}".also { owned += it }
    }

    fun bookmark(target: HistoryTarget): String {
        require(target in targets)
        return "users/$uid/${target.type.wire}Bookmarks/${target.id}".also { owned += it }
    }

    /**
     * Main creates UUIDs internally; register only this unique test account's bounded matching
     * receipts for cleanup.
     */
    suspend fun captureActivityReceipts() {
        AccountDeletionFixtures.requireLocalAvd()
        check(LocalFirebase.auth(AccountDeletionFixtures.context).currentUser?.uid == uid)
        val rows =
            LocalFirebase.firestore(AccountDeletionFixtures.context)
                .collection("users/$uid/activityLog")
                .limit(101)
                .get(Source.SERVER)
                .await()
        check(rows.size() <= 100)
        rows.documents.forEach { row ->
            check(
                row.getString("targetId") in targets.map { it.id } &&
                    row.getString("id") == row.id &&
                    runCatching { UUID.fromString(row.id) }.isSuccess
            )
            path(HistorySection.ACTIVITY, row.id)
        }
    }

    suspend fun seedTargets() {
        for (target in targets) {
            owned += target.path
            patch(
                target.path,
                mapOf(
                    "id" to target.id,
                    "sourceType" to "organization",
                    "organizationId" to targets.last().id,
                    "moderationStatus" to "approved",
                    "title" to "Synthetic history ${target.type.wire}",
                    "name" to "Synthetic history organization",
                    "body" to "Synthetic body",
                    "summary" to "Synthetic summary",
                    "details" to "Synthetic details",
                    "description" to "Synthetic description",
                    "city" to "Wien",
                    "createdAt" to time,
                    "updatedAt" to time,
                    "startDate" to time.plusSeconds(3600),
                    "endDate" to time.plusSeconds(7200),
                    "viewCount" to 7L,
                    "ownerId" to uid,
                ),
            )
        }
    }

    suspend fun seedWindow(section: HistorySection, count: Int) {
        require(count in 1..105)
        repeat(count) { index ->
            val target = targets.first()
            val id =
                if (section == HistorySection.ACTIVITY)
                    "$prefix-activity-${index.toString().padStart(3, '0')}"
                else "news_${prefix}-window-${index.toString().padStart(3, '0')}"
            val reference =
                if (section == HistorySection.RECENT)
                    HistoryTarget(HistoryType.NEWS, id.removePrefix("news_"))
                else target
            patch(
                path(section, id),
                HistoryContract.fields(
                    reference,
                    if (section == HistorySection.ACTIVITY) HistoryAction.SAVE_NEWS else null,
                    "Synthetic private history $index",
                    null,
                    null,
                    id,
                    time.minusSeconds(index.toLong()),
                ),
            )
        }
    }

    suspend fun patch(path: String, fields: Map<String, Any?>, merge: Boolean = false) {
        require(path in owned || path == "users/$uid")
        val mask =
            if (merge) fields.keys.joinToString("&", "?") { "updateMask.fieldPaths=$it" } else ""
        request(path, "PATCH", fields, mask)
    }

    suspend fun read(path: String): JSONObject? {
        require(path in owned)
        return request(path, "GET")
    }

    suspend fun cleanup(previous: Throwable?) {
        var failure = previous
        for (path in owned.toList().asReversed()) {
            try {
                confirmHistoryFixtureAbsent(
                    delete = {
                        request(path, "DELETE")
                        Unit
                    },
                    absent = { request(path, "GET") == null },
                    reconciled = {
                        println("HISTORY_CLEANUP_ABSENCE_CONFIRMED_AFTER_ERROR ${it.message}")
                    },
                )
            } catch (error: Throwable) {
                if (failure == null) failure = error else failure.addSuppressed(error)
            }
        }
        if (previous == null && failure != null) throw failure
    }

    private suspend fun request(
        path: String,
        method: String,
        fields: Map<String, Any?>? = null,
        mask: String = "",
    ): JSONObject? =
        withContext(Dispatchers.IO) {
            AccountDeletionFixtures.requireLocalAvd()
            require(path in owned || path == "users/$uid")
            val connection =
                URL(
                        "http://${LocalEnvironment.HOST}:8088${AuthEmulatorFixtures.documentPath(path)}$mask"
                    )
                    .openConnection() as HttpURLConnection
            try {
                connection.instanceFollowRedirects = false
                connection.connectTimeout = 5000
                connection.readTimeout = 5000
                connection.requestMethod = method
                connection.setRequestProperty("Authorization", "Bearer owner")
                if (fields != null) {
                    connection.doOutput = true
                    connection.setRequestProperty("Content-Type", "application/json")
                    connection.outputStream.use {
                        it.write(
                            JSONObject()
                                .put("fields", JSONObject(fields.mapValues { value(it.value) }))
                                .toString()
                                .toByteArray()
                        )
                    }
                }
                val status = connection.responseCode
                if (status == 404 && method in setOf("GET", "DELETE")) return@withContext null
                check(status in 200..299) {
                    val detail = runCatching {
                        val body =
                            connection.errorStream
                                ?.bufferedReader()
                                ?.use {
                                    val bounded = CharArray(2048)
                                    val size = it.read(bounded)
                                    if (size > 0) String(bounded, 0, size) else ""
                                }
                                .orEmpty()
                        val error = JSONObject(body).optJSONObject("error")
                        error?.optString("status").orEmpty() +
                            ": " +
                            error
                                ?.optString("message")
                                .orEmpty()
                                .replace(uid, "[fixture-user]")
                                .replace(prefix, "[fixture]")
                                .take(400)
                    }
                        .getOrDefault("unavailable")
                    "Scoped history fixture $method HTTP $status: $detail"
                }
                val body = connection.inputStream.bufferedReader().use { it.readText() }
                check(method != "GET" || body.isNotBlank()) {
                    "Empty history fixture GET response is not proof of absence"
                }
                if (body.isBlank()) null else JSONObject(body)
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
            else -> error("Unsupported synthetic history value")
        }
}
