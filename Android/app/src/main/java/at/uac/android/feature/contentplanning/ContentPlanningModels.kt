package at.uac.android.feature.contentplanning

import java.net.URI
import java.time.Instant

enum class ContentPlanningKind(val collection: String) {
    NEWS("news"),
    EVENT("events"),
}

enum class ContentPlanningState(val wire: String) {
    READY("readyForReview"),
    ATTENTION("needsAttention"),
    SCHEDULED("scheduled"),
    PUBLISHING("publishing"),
    FAILED("failed"),
    COMPLETED("completed"),
    ARCHIVED("archived");

    companion object {
        fun parse(value: String) = entries.singleOrNull { it.wire == value }
    }
}

enum class ContentPlanningSection(val states: Set<ContentPlanningState>) {
    DRAFTS(setOf(ContentPlanningState.READY, ContentPlanningState.PUBLISHING)),
    SCHEDULED(setOf(ContentPlanningState.SCHEDULED)),
    ATTENTION(setOf(ContentPlanningState.ATTENTION, ContentPlanningState.FAILED)),
    HISTORY(setOf(ContentPlanningState.COMPLETED, ContentPlanningState.ARCHIVED));

    val ascending: Boolean
        get() = this == SCHEDULED

    val sortField: String
        get() = if (ascending) "scheduledAt" else "updatedAt"
}

enum class ContentPlanningOutcome(val wire: String) {
    APPROVED("approved"),
    PENDING_REVIEW("pendingReview"),
    SCHEDULED("scheduled"),
    ARCHIVED("archived"),
    UNRESOLVED("unresolved");

    companion object {
        fun parse(value: String?) = entries.singleOrNull { it.wire == value }
    }
}

data class ContentPlanningSource(
    val url: String,
    val title: String?,
    val primary: Boolean,
    val checkedAt: Instant?,
)

data class ContentPlanningDraft(
    val id: String,
    val schemaVersion: Int,
    val ownerUserId: String,
    val kind: ContentPlanningKind,
    val state: ContentPlanningState,
    val title: String,
    val payload: Map<String, Any?>,
    val sources: List<ContentPlanningSource>,
    val verificationNotes: List<String>,
    val missingFields: List<String>,
    val createdAt: Instant,
    val updatedAt: Instant,
    val scheduledAt: Instant?,
    val completedAt: Instant?,
    val archivedAt: Instant?,
    val failureMessage: String?,
    val leaseExpiresAt: Instant?,
    val publishedContentId: String?,
    val publishedKind: ContentPlanningKind?,
    val publishedOrganizationId: String?,
    val publishedOrganizationName: String?,
    val outcome: ContentPlanningOutcome?,
) {
    val section: ContentPlanningSection
        get() = ContentPlanningSection.entries.single { state in it.states }

    val expiredLease: Boolean
        get() =
            state == ContentPlanningState.PUBLISHING &&
                leaseExpiresAt?.isBefore(Instant.now()) != false

    val canPublish: Boolean
        get() =
            state in
                setOf(
                    ContentPlanningState.READY,
                    ContentPlanningState.ATTENTION,
                    ContentPlanningState.FAILED,
                ) || expiredLease

    val canArchive: Boolean
        get() =
            state in
                setOf(
                    ContentPlanningState.READY,
                    ContentPlanningState.ATTENTION,
                    ContentPlanningState.FAILED,
                ) && publishedContentId == null

    val canDelete: Boolean
        get() =
            state in
                setOf(
                    ContentPlanningState.READY,
                    ContentPlanningState.ATTENTION,
                    ContentPlanningState.FAILED,
                    ContentPlanningState.ARCHIVED,
                ) && publishedContentId == null

    override fun toString() = "ContentPlanningDraft(kind=$kind, state=$state, [redacted])"
}

data class ContentPlanningCursor(val sortDate: Instant, val documentId: String)

data class ContentPlanningPage(
    val items: List<ContentPlanningDraft>,
    val cursor: ContentPlanningCursor?,
    val hasMore: Boolean,
)

data class ContentPlanningLease(
    val draftId: String,
    val kind: ContentPlanningKind,
    val contentId: String,
    val leaseId: String,
    val expiresAt: Instant,
    val contentAlreadyExists: Boolean,
    val existingModerationStatus: String?,
    val existingScheduledAt: Instant?,
)

data class ContentPlanningPublication(
    val kind: ContentPlanningKind,
    val contentId: String,
    val scheduledAt: Instant?,
)

data class ContentPlanningOrganization(val id: String, val name: String)

enum class ContentPlanningFailure {
    SIGN_IN,
    NOT_READY,
    DENIED,
    OFFLINE,
    INDEX,
    INVALID,
    MISSING,
    CONFLICT,
    UNCONFIRMED,
    UNKNOWN,
}

class ContentPlanningException(
    val failure: ContentPlanningFailure,
    cause: Throwable? = null,
) : Exception(failure.name, cause)

object ContentPlanningContract {
    const val PAGE_SIZE = 15
    const val BEGIN = "beginOwnerContentDraftPublication"
    const val FINALIZE = "finalizeOwnerContentDraftPublication"
    const val FAIL = "failOwnerContentDraftPublication"
    const val ARCHIVE = "archiveOwnerContentDraft"
    const val DELETE = "deleteOwnerContentDraft"
    private val draftId = Regex("[a-f0-9]{40}")
    private val opaqueId = Regex("[A-Za-z0-9_-]{1,160}")
    private val attemptId = Regex("[A-Za-z0-9_-]{16,80}")
    private val moderation = setOf("draft", "pendingReview", "approved")

    fun validDraftId(value: String) = draftId.matches(value)

    fun reservedContentId(draftId: String): String {
        if (!validDraftId(draftId)) invalid()
        return "planning-$draftId"
    }

    fun requireOwner(uid: String, role: String, ready: Boolean) {
        if (uid.isBlank()) fail(ContentPlanningFailure.SIGN_IN)
        if (!ready) fail(ContentPlanningFailure.NOT_READY)
        if (role != "owner") fail(ContentPlanningFailure.DENIED)
    }

    fun beginPayload(draftId: String, attemptId: String): Map<String, Any?> {
        if (!validDraftId(draftId) || !this.attemptId.matches(attemptId)) invalid()
        return mapOf("draftId" to draftId, "attemptId" to attemptId)
    }

    fun finalizePayload(
        draft: ContentPlanningDraft,
        lease: ContentPlanningLease,
    ): Map<String, Any?> {
        if (
            lease.draftId != draft.id ||
                lease.kind != draft.kind ||
                !opaqueId.matches(lease.contentId) ||
                !opaqueId.matches(lease.leaseId)
        )
            invalid()
        return mapOf(
            "draftId" to draft.id,
            "leaseId" to lease.leaseId,
            "contentId" to lease.contentId,
            "kind" to lease.kind.name.lowercase(),
        )
    }

    fun failPayload(draftId: String, leaseId: String, message: String): Map<String, Any?> {
        val resolved = message.trim().take(500)
        if (!validDraftId(draftId) || !opaqueId.matches(leaseId) || resolved.isEmpty()) invalid()
        return mapOf("draftId" to draftId, "leaseId" to leaseId, "message" to resolved)
    }

    fun draftPayload(draftId: String): Map<String, Any?> {
        if (!validDraftId(draftId)) invalid()
        return mapOf("draftId" to draftId)
    }

    fun lease(raw: Any?, expectedDraftId: String): ContentPlanningLease {
        val data = raw.record()
        val kind = kind(data.string("kind"))
        val already = data.boolean("contentAlreadyExists")
        val status = data.optionalString("existingModerationStatus")
        if (status != null && status !in moderation) invalid()
        val existingScheduledAt = data.optionalInstant("existingScheduledAt")
        if (!already && (status != null || existingScheduledAt != null)) invalid()
        return ContentPlanningLease(
            data.string("draftId").also { if (it != expectedDraftId) invalid() },
            kind,
            data.string("contentId").also { if (!opaqueId.matches(it)) invalid() },
            data.string("leaseId").also { if (!opaqueId.matches(it)) invalid() },
            data.instant("expiresAt"),
            already,
            status,
            existingScheduledAt,
        )
    }

    fun finalized(raw: Any?, expected: ContentPlanningLease): ContentPlanningState {
        val data = raw.record()
        if (data["finalized"] != true) invalid()
        return when (data.string("state")) {
            "scheduled" -> ContentPlanningState.SCHEDULED
            "completed" -> ContentPlanningState.COMPLETED
            else -> invalid()
        }
    }

    fun acknowledged(raw: Any?, field: String): Boolean {
        val data = raw.record()
        return (data[field] as? Boolean) ?: invalid()
    }

    fun validateDraft(draft: ContentPlanningDraft, expectedOwner: String) {
        if (
            !validDraftId(draft.id) ||
                draft.ownerUserId != expectedOwner ||
                draft.schemaVersion !in 1..3
        )
            invalid()
        if (draft.title.isBlank() || draft.title.length > 120 || draft.sources.size !in 1..10)
            invalid()
        if (draft.sources.count { it.primary } != 1 || draft.sources.any { !webUrl(it.url) })
            invalid()
        if (
            draft.verificationNotes.size > 30 ||
                draft.verificationNotes.any { it.isBlank() || it.length > 500 }
        )
            invalid()
        if (
            draft.missingFields.size > 30 ||
                draft.missingFields.any { it.isBlank() || it.length > 100 }
        )
            invalid()
        if (draft.state == ContentPlanningState.ATTENTION && draft.missingFields.isEmpty())
            invalid()
        if (draft.state == ContentPlanningState.READY && draft.missingFields.isNotEmpty()) invalid()
        if (draft.kind == ContentPlanningKind.NEWS) {
            requiredText(draft.payload, "title", 120)
            requiredText(draft.payload, "summary", 200)
            requiredText(draft.payload, "body", 10_000)
            requiredText(draft.payload, "sourceInput", 2_048)
        } else {
            requiredText(draft.payload, "title", 120)
            requiredText(draft.payload, "summary", 200)
            requiredText(draft.payload, "details", 2_000)
            requiredText(draft.payload, "city", 120)
            requiredText(draft.payload, "federalState", 80)
            if (
                (draft.payload["venue"] as? String).isNullOrBlank() &&
                    (draft.payload["address"] as? String).isNullOrBlank()
            )
                invalid()
            if (draft.payload["startDate"] !is Instant || draft.payload["endDate"] !is Instant)
                invalid()
        }
        if (draft.state == ContentPlanningState.PUBLISHING && draft.leaseExpiresAt == null)
            invalid()
        if (
            draft.state in setOf(ContentPlanningState.SCHEDULED, ContentPlanningState.COMPLETED) &&
                (draft.publishedContentId == null || draft.publishedKind != draft.kind)
        )
            invalid()
        if (draft.state == ContentPlanningState.SCHEDULED && draft.scheduledAt == null) invalid()
    }

    private fun requiredText(payload: Map<String, Any?>, key: String, maximum: Int) {
        val value = payload[key] as? String ?: invalid()
        if (value.isBlank() || value.length > maximum) invalid()
    }

    private fun webUrl(value: String): Boolean = runCatching {
        val parsed = URI(value)
        parsed.scheme in setOf("http", "https") &&
            !parsed.host.isNullOrBlank() &&
            parsed.userInfo == null
    }
        .getOrDefault(false)

    internal fun kind(value: String) =
        when (value) {
            "news" -> ContentPlanningKind.NEWS
            "event" -> ContentPlanningKind.EVENT
            else -> invalid()
        }

    internal fun invalid(): Nothing = fail(ContentPlanningFailure.INVALID)

    internal fun fail(failure: ContentPlanningFailure, cause: Throwable? = null): Nothing =
        throw ContentPlanningException(failure, cause)
}

internal fun Any?.record(): Map<String, Any?> =
    (this as? Map<*, *>)?.entries?.associate { (key, value) ->
        (key as? String ?: ContentPlanningContract.invalid()) to value
    } ?: ContentPlanningContract.invalid()

internal fun Map<String, Any?>.string(key: String) =
    this[key] as? String ?: ContentPlanningContract.invalid()

internal fun Map<String, Any?>.optionalString(key: String) =
    this[key]?.let { it as? String ?: ContentPlanningContract.invalid() }

internal fun Map<String, Any?>.boolean(key: String) =
    this[key] as? Boolean ?: ContentPlanningContract.invalid()

internal fun Map<String, Any?>.instant(key: String) = runCatching {
    Instant.parse(string(key))
}
    .getOrElse { ContentPlanningContract.invalid() }

internal fun Map<String, Any?>.optionalInstant(key: String) =
    optionalString(key)?.let {
        runCatching { Instant.parse(it) }.getOrElse { ContentPlanningContract.invalid() }
    }
