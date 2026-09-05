package at.uac.android

import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalEnvironment
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.contentlifecycle.ContentLifecycleTarget
import at.uac.android.feature.contentmedia.ContentCoverTarget
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.Proxy
import java.net.URL
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject

/**
 * Test APK only. All GET/seed/delete paths belong to fresh identities and individually registered
 * UUID content.
 */
internal class ContentLifecycleFixtures(prefix: String) {
    val media = ContentCoverFixtures(prefix)
    val data
        get() = media.data

    val password
        get() = media.password

    val organizationId
        get() = media.organizationId

    private val targets = linkedSetOf<ContentLifecycleTarget>()
    private val related = linkedSetOf<String>()
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    enum class Reference {
        COMMENT,
        LIKE,
        BOOKMARK,
        VIEW,
        RECENT,
        HISTORY,
        INBOX,
        REGISTRATION,
        CANCEL_NOTICE,
        BANNER,
    }

    fun register(kind: ContentKind, foreign: Boolean = false): ContentLifecycleTarget =
        media.register(kind, foreign).let {
            ContentLifecycleTarget(it.organizationId, it.kind, it.contentId).also(targets::add)
        }

    fun cover(target: ContentLifecycleTarget): ContentCoverTarget {
        require(target in targets)
        return ContentCoverTarget(target.organizationId, target.kind, target.contentId)
    }

    fun reference(target: ContentLifecycleTarget, uid: String, type: Reference): String {
        require(target in targets && uid in data.uids)
        val id = target.contentId
        val event = target.kind == ContentKind.EVENTS
        val stem = if (event) "event" else "news"
        val path =
            when (type) {
                Reference.COMMENT -> "${target.kind.collection}/$id/comments/lifecycle-comment-$uid"
                Reference.LIKE -> "likes/${stem}_${id}_$uid"
                Reference.BOOKMARK -> "users/$uid/${stem}Bookmarks/$id"
                Reference.VIEW -> "users/$uid/${stem}Views/$id"
                Reference.RECENT -> "users/$uid/recentViews/${stem}_$id"
                Reference.HISTORY -> "users/$uid/activityLog/${stem}_$id"
                Reference.INBOX -> "users/$uid/notificationInbox/lifecycle_${stem}_$id"
                Reference.REGISTRATION -> {
                    require(event)
                    "registrations/event_${id}_$uid"
                }
                Reference.CANCEL_NOTICE -> {
                    require(event)
                    "users/$uid/notificationInbox/eventCancelled_${id}_$uid"
                }
                Reference.BANNER -> "featuredBanners/lifecycle_${stem}_$id"
            }
        related += path
        return path
    }

    suspend fun seed(path: String, fields: Map<String, Any?>) {
        require(path in related)
        LocalEmulatorFixtures(context).seed(path, fields)
    }

    suspend fun fields(path: String): JSONObject? = request(path, "GET")

    suspend fun exists(target: ContentLifecycleTarget): Boolean {
        require(target in targets)
        return fields("${target.kind.collection}/${target.contentId}") != null
    }

    suspend fun cleanup(previous: Throwable?) {
        var failure = previous
        for (path in related.toList().reversed()) {
            try {
                request(path, "DELETE")
            } catch (error: Throwable) {
                if (failure == null) failure = error else failure.addSuppressed(error)
            }
        }
        try {
            media.cleanup(failure)
        } catch (error: Throwable) {
            if (failure == null) failure = error else failure.addSuppressed(error)
        }
        if (previous == null && failure != null) throw failure
    }

    private suspend fun request(path: String, method: String): JSONObject? =
        withContext(Dispatchers.IO) {
            LocalEnvironment.requireSafe()
            check(context.packageName == "at.uac.android.local" && method in setOf("GET", "DELETE"))
            require(
                path in related || targets.any { path == "${it.kind.collection}/${it.contentId}" }
            )
            val connection =
                URL(
                        "http://10.0.2.2:8088/v1/projects/demo-uac-android/databases/(default)/documents/$path"
                    )
                    .openConnection(Proxy.NO_PROXY) as HttpURLConnection
            try {
                connection.connectTimeout = 5_000
                connection.readTimeout = 5_000
                connection.instanceFollowRedirects = false
                connection.requestMethod = method
                connection.setRequestProperty("Authorization", "Bearer owner")
                val status = connection.responseCode
                if (status == 404) return@withContext null
                check(status in 200..299) { "Scoped lifecycle fixture HTTP $status" }
                if (method == "DELETE") return@withContext null
                val bytes =
                    connection.inputStream.use { input ->
                        ByteArrayOutputStream().use { output ->
                            val buffer = ByteArray(8192)
                            while (output.size() <= 262_144) {
                                val count =
                                    input.read(
                                        buffer,
                                        0,
                                        minOf(buffer.size, 262_145 - output.size()),
                                    )
                                if (count < 0) break
                                output.write(buffer, 0, count)
                            }
                            output.toByteArray()
                        }
                    }
                check(bytes.size <= 262_144) { "Scoped lifecycle fixture response too large" }
                JSONObject(bytes.toString(Charsets.UTF_8)).getJSONObject("fields")
            } finally {
                connection.disconnect()
            }
        }

    fun existingCancellation(
        target: ContentLifecycleTarget,
        uid: String,
        at: Instant,
    ): Map<String, Any?> {
        val id = reference(target, uid, Reference.CANCEL_NOTICE).substringAfterLast('/')
        val metadata =
            mapOf(
                "eventId" to target.contentId,
                "route" to "openEvent",
                "routeTargetId" to target.contentId,
                "pushDelivery" to "central",
            )
        return mapOf(
            "id" to id,
            "userId" to uid,
            "recipientUserId" to uid,
            "type" to "eventCancelled",
            "title" to "Earlier synthetic cancellation",
            "message" to "Existing deterministic receipt",
            "severity" to "warning",
            "actionType" to "openEvent",
            "actionTargetId" to target.contentId,
            "requiresPopup" to false,
            "popupPresentedAt" to null,
            "expiresAt" to null,
            "archivedAt" to null,
            "deletedAt" to null,
            "readAt" to null,
            "metadata" to metadata,
            "payload" to metadata,
            "isRead" to false,
            "sourceType" to "event",
            "sourceId" to target.contentId,
            "createdAt" to at,
            "dedupeKey" to "eventCancelled:${target.contentId}",
        )
    }
}
