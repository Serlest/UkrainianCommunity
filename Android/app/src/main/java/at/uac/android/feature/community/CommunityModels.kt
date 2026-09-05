package at.uac.android.feature.community

import at.uac.android.feature.auth.AuthSession
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.browse.Fields
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.browse.string
import java.time.Instant

data class CommunitySession(
    val uid: String,
    val revision: Long,
    val ready: Boolean,
    val role: String,
)

fun AuthSession.communityScope(): CommunitySession? =
    identity
        ?.takeUnless { it.anonymous }
        ?.let {
            CommunitySession(
                it.uid,
                revision,
                readyForActions && profile?.active == true,
                profile?.globalRole.orEmpty(),
            )
        }

data class CommunityTarget(val kind: ContentKind, val id: String) {
    init {
        require(communityId(id, 512))
    }

    // Event participation permits 512 units; the existing create-comment API permits only 256.
    val acceptsNewComments: Boolean
        get() = id.length <= 256

    val type: String
        get() =
            when (kind) {
                ContentKind.NEWS -> "news"
                ContentKind.EVENTS -> "event"
                ContentKind.ORGANIZATIONS -> "organization"
            }

    val path
        get() = "${kind.collection}/$id"
}

fun communityId(value: String, maximum: Int = 512): Boolean =
    value.isNotBlank() &&
        value == value.trim() &&
        value.length <= maximum &&
        value.toByteArray(Charsets.UTF_8).size <= 1_500 &&
        value !in setOf(".", "..") &&
        '/' !in value &&
        value.none(Char::isISOControl)

enum class CommunityFailure {
    SIGN_IN,
    NOT_READY,
    OFFLINE,
    DENIED,
    MISSING,
    INVALID,
    FULL,
    PAST,
    CANCELLED,
    NOT_REQUIRED,
    NOT_APPROVED,
    REJECTED_TEXT,
    EMPTY_TEXT,
    TEXT_TOO_LONG,
    UNCONFIRMED,
    UNKNOWN,
}

class CommunityException(val failure: CommunityFailure, cause: Throwable? = null) :
    Exception(failure.name, cause)

data class RegistrationReceipt(
    val eventId: String,
    val registered: Boolean,
    val count: Long,
    val didChange: Boolean,
)

data class EventParticipation(
    val eventId: String,
    val registered: Boolean,
    val count: Long,
    val capacity: Long?,
    val start: Instant,
    val cancelled: Boolean,
    val approved: Boolean,
    val required: Boolean,
) {
    fun unavailable(now: Instant): CommunityFailure? =
        when {
            registered -> null // Existing attendance can always be cancelled through the server.
            cancelled -> CommunityFailure.CANCELLED
            !approved -> CommunityFailure.NOT_APPROVED
            !start.isAfter(now) -> CommunityFailure.PAST
            !required -> CommunityFailure.NOT_REQUIRED
            capacity != null && count >= capacity -> CommunityFailure.FULL
            else -> null
        }
}

data class CommunityComment(
    val id: String,
    val target: CommunityTarget,
    val authorId: String?,
    val authorName: String,
    val text: String,
    val createdAt: Instant,
    val updatedAt: Instant?,
)

data class CommentPage(
    val comments: List<CommunityComment>,
    val cached: Boolean,
    val withheld: Int = 0,
)

object CommunityContract {
    const val MAX_COMMENT_LENGTH =
        1_000 // Kotlin length, like JavaScript/iOS, counts UTF-16 code units.

    fun text(value: String): String =
        value.trim().also {
            if (it.isEmpty()) throw CommunityException(CommunityFailure.EMPTY_TEXT)
            if (it.length > MAX_COMMENT_LENGTH)
                throw CommunityException(CommunityFailure.TEXT_TOO_LONG)
        }

    fun count(value: Any?, defaultZero: Boolean = false): Long {
        if (value == null && defaultZero) return 0
        val number = value as? Number ?: invalid()
        val double = number.toDouble()
        if (
            !double.isFinite() ||
                double < 0 ||
                double > 9_007_199_254_740_991.0 ||
                double != number.toLong().toDouble()
        )
            invalid()
        return number.toLong()
    }

    fun receipt(value: Any?, eventId: String): RegistrationReceipt {
        val f = value as? Map<*, *> ?: invalid()
        if (f["eventId"] != eventId || f["didChange"] !is Boolean) invalid()
        val registered =
            when (f["registrationState"]) {
                "registered" -> true
                "notRegistered" -> false
                else -> invalid()
            }
        return RegistrationReceipt(
            eventId,
            registered,
            count(f["registeredCount"]),
            f["didChange"] as Boolean,
        )
    }

    fun registrationId(eventId: String, uid: String): String {
        if (!communityId(eventId) || !communityId(uid, 128)) invalid()
        return "event_${eventId}_$uid".also { if (!communityId(it, 1_500)) invalid() }
    }

    fun participation(event: RawDocument, marker: RawDocument?, uid: String): EventParticipation {
        val id = event.id
        if (
            marker != null &&
                (marker.id != registrationId(id, uid) ||
                    marker.fields["id"] != marker.id ||
                    marker.fields["eventId"] != id ||
                    marker.fields["userId"] != uid ||
                    marker.fields["registeredAt"] !is Instant)
        )
            invalid()
        val f = event.fields
        val start = f["startDate"] as? Instant ?: invalid()
        val capacity =
            f["capacity"]?.let { count(it).also { amount -> if (amount == 0L) invalid() } }
        return EventParticipation(
            id,
            marker != null,
            count(f["registeredCount"], true),
            capacity,
            start,
            f["cancellationState"] == "cancelled",
            f["moderationStatus"] == "approved",
            f["requiresRegistration"] == true,
        )
    }

    /**
     * Legacy optional parent/author fields are contextual; present mismatches are never accepted.
     */
    fun comment(
        target: CommunityTarget,
        document: RawDocument,
        response: Boolean = false,
    ): CommunityComment? {
        val f = document.fields
        if (
            !communityId(document.id) ||
                f["id"] != document.id ||
                (f.containsKey("parentId") && f["parentId"] != target.id) ||
                (f.containsKey("parentType") && f["parentType"] != target.type)
        )
            invalid()
        if (
            response &&
                (f["parentId"] != target.id ||
                    f["parentType"] != target.type ||
                    f["isDeleted"] != false)
        )
            invalid()
        if (f["isDeleted"] == true) return null
        if (f["isDeleted"] != null && f["isDeleted"] !is Boolean) invalid()
        when (f["moderationStatus"]) {
            null,
            "approved" -> Unit
            "pendingReview",
            "rejected",
            "hidden",
            "draft" -> return null
            else -> invalid()
        }
        if (response && f["moderationStatus"] != "approved") invalid()
        val author = f["authorId"]?.let { it as? String ?: invalid() }
        if (author != null && !communityId(author, 128)) invalid()
        val rawName = f["authorName"] as? String ?: invalid()
        val name =
            rawName
                .filterNot {
                    it.isISOControl() || it in '\u202A'..'\u202E' || it in '\u2066'..'\u2069'
                }
                .trim()
                .take(160)
                .ifBlank { "User" }
        val body =
            (f["text"] as? String)?.takeIf { it.isNotBlank() } ?: f["body"] as? String ?: invalid()
        val created = instant(f["createdAt"]) ?: invalid()
        val updated = f["updatedAt"]?.let { instant(it) ?: invalid() }
        return CommunityComment(document.id, target, author, name, text(body), created, updated)
    }

    fun canModerate(
        target: CommunityTarget,
        parent: Fields,
        organization: Fields?,
        session: CommunitySession?,
    ): Boolean {
        if (session?.ready != true) return false
        if (session.role in setOf("owner", "admin")) return true
        val org =
            if (target.kind == ContentKind.ORGANIZATIONS) parent
            else {
                if (
                    parent.string("sourceType") != "organization" ||
                        !communityId(parent.string("organizationId"))
                )
                    return false
                organization ?: return false
            }
        return org["ownerId"] == session.uid ||
            listOf("adminIds", "moderatorIds").any { key ->
                (org[key] as? List<*>)?.contains(session.uid) == true
            }
    }

    private fun instant(value: Any?): Instant? =
        when (value) {
            is Instant -> value
            is String -> runCatching { Instant.parse(value) }.getOrNull()
            else -> null
        }

    private fun invalid(): Nothing = throw CommunityException(CommunityFailure.INVALID)
}
