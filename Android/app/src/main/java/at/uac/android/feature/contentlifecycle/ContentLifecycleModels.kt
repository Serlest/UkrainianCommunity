package at.uac.android.feature.contentlifecycle

import at.uac.android.feature.authoring.AuthoringContract
import at.uac.android.feature.authoring.AuthoringItem
import at.uac.android.feature.authoring.AuthoringStatus
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.organization.OrganizationAuthority
import at.uac.android.feature.organization.OrganizationContract
import at.uac.android.feature.organization.OrganizationRecord
import at.uac.android.feature.organization.OrganizationSession
import java.time.Instant
import java.time.temporal.ChronoUnit

enum class ContentLifecycleFailure {
    SIGN_IN,
    NOT_READY,
    DENIED,
    INVALID,
    MISSING,
    READ_ONLY,
    STALE,
    OFFLINE,
    INDEX,
    UNCONFIRMED,
    UNKNOWN,
}

class ContentLifecycleException(val reason: ContentLifecycleFailure, cause: Throwable? = null) :
    Exception(reason.name, cause)

data class ContentLifecycleTarget(
    val organizationId: String,
    val kind: ContentKind,
    val contentId: String,
) {
    init {
        require(
            AuthoringContract.id(organizationId) &&
                AuthoringContract.id(contentId) &&
                kind in AuthoringContract.kinds
        )
    }
}

/**
 * A null item means absent from the authorized organization scope, never proof of cascade
 * completion.
 */
data class ContentLifecycleSnapshot(
    val target: ContentLifecycleTarget,
    val organization: OrganizationRecord,
    val item: AuthoringItem?,
)

data class ContentLifecycleIntent(val snapshot: ContentLifecycleSnapshot)

sealed interface ContentLifecycleReceipt {
    val target: ContentLifecycleTarget
    val completedAt: Instant

    data class Deleted(
        override val target: ContentLifecycleTarget,
        override val completedAt: Instant,
        val alreadyDeleted: Boolean = false,
    ) : ContentLifecycleReceipt

    data class Cancelled(
        override val target: ContentLifecycleTarget,
        override val completedAt: Instant,
        val recipientCount: Long,
        val notificationCount: Long,
    ) : ContentLifecycleReceipt
}

data class ContentLifecycleConfirmation(
    val snapshot: ContentLifecycleSnapshot,
    val receipt: ContentLifecycleReceipt,
)

enum class ContentLifecycleObserved {
    UNCHANGED,
    UNAVAILABLE_CLEANUP_UNCONFIRMED,
    CANCELLED_NOTICES_UNCONFIRMED,
    DIFFERENT,
}

data class ContentLifecycleRecovery(
    val snapshot: ContentLifecycleSnapshot,
    val observed: ContentLifecycleObserved,
)

object ContentLifecycleContract {
    private val cancellationFields =
        setOf(
            "moderationStatus",
            "cancellationState",
            "cancelledAt",
            "cancelledBy",
            "cancellationReason",
            "updatedAt",
        )

    fun authority(record: OrganizationRecord, session: OrganizationSession): OrganizationRecord {
        if (!session.ready) fail(ContentLifecycleFailure.NOT_READY)
        val actual = OrganizationContract.record(RawDocument(record.id, record.fields), session)
        // This is the scoped build65 UI permission, not the broader server app-owner override.
        if (
            actual.id == "ukrainian-community" ||
                actual.status != "approved" ||
                actual.authority !in
                    setOf(OrganizationAuthority.OWNER, OrganizationAuthority.PLATFORM_OWNER)
        )
            fail(ContentLifecycleFailure.DENIED)
        return actual
    }

    fun permitted(record: OrganizationRecord?, session: OrganizationSession?): Boolean =
        record != null && session != null && runCatching { authority(record, session) }.isSuccess

    fun validate(
        snapshot: ContentLifecycleSnapshot,
        target: ContentLifecycleTarget,
        session: OrganizationSession,
    ) {
        if (snapshot.target != target || snapshot.organization.id != target.organizationId)
            fail(ContentLifecycleFailure.INVALID)
        authority(snapshot.organization, session)
        snapshot.item?.let { item ->
            if (
                item.id != target.contentId ||
                    item.kind != target.kind ||
                    item.organizationId != target.organizationId
            )
                fail(ContentLifecycleFailure.INVALID)
            val parsed =
                AuthoringContract.item(
                    item.kind,
                    RawDocument(item.id, item.fields),
                    target.organizationId,
                    item.status,
                    session,
                )
            if (parsed != item) fail(ContentLifecycleFailure.INVALID)
        }
    }

    fun actionable(snapshot: ContentLifecycleSnapshot, session: OrganizationSession): Boolean =
        runCatching { validate(snapshot, snapshot.target, session) }.isSuccess &&
            snapshot.item?.let {
                it.status != AuthoringStatus.SCHEDULED &&
                    it.fields["scheduledAt"] == null &&
                    it.fields["cancellationState"] != "cancelled"
            } == true

    fun unchanged(before: ContentLifecycleSnapshot, after: ContentLifecycleSnapshot) {
        if (
            before.target != after.target ||
                before.organization.fields != after.organization.fields ||
                before.item?.fields != after.item?.fields
        )
            fail(ContentLifecycleFailure.STALE)
    }

    fun receipt(value: Any?, target: ContentLifecycleTarget): ContentLifecycleReceipt {
        val fields = value as? Map<*, *> ?: fail(ContentLifecycleFailure.UNCONFIRMED)
        fun instant(key: String): Instant =
            (fields[key] as? String)
                ?.let { runCatching { Instant.parse(it) }.getOrNull() }
                ?.takeIf { it >= Instant.EPOCH && it < Instant.parse("9999-01-01T00:00:00Z") }
                ?: fail(ContentLifecycleFailure.UNCONFIRMED)
        fun count(key: String): Long {
            val value =
                (fields[key] as? Number)?.toDouble() ?: fail(ContentLifecycleFailure.UNCONFIRMED)
            if (
                !value.isFinite() ||
                    value < 0 ||
                    value > Int.MAX_VALUE ||
                    value != value.toLong().toDouble()
            )
                fail(ContentLifecycleFailure.UNCONFIRMED)
            return value.toLong()
        }
        if (target.kind == ContentKind.NEWS) {
            if (
                fields.keys != setOf("status", "deletedAt") ||
                    fields["status"] !in setOf("deleted", "alreadyDeleted")
            )
                fail(ContentLifecycleFailure.UNCONFIRMED)
            return ContentLifecycleReceipt.Deleted(
                target,
                instant("deletedAt"),
                fields["status"] == "alreadyDeleted",
            )
        }
        if (
            fields.keys !=
                setOf(
                    "eventId",
                    "status",
                    "recipientCount",
                    "notificationCount",
                    "pushRecipientCount",
                    "cancelledAt",
                ) ||
                fields["eventId"] != target.contentId ||
                fields["status"] !in setOf("deleted", "cancelled")
        )
            fail(ContentLifecycleFailure.UNCONFIRMED)
        val recipients = count("recipientCount")
        val notices = count("notificationCount")
        val pushes = count("pushRecipientCount")
        if (notices > recipients || pushes != 0L) fail(ContentLifecycleFailure.UNCONFIRMED)
        val time = instant("cancelledAt")
        if (fields["status"] == "deleted") {
            if (recipients != 0L || notices != 0L) fail(ContentLifecycleFailure.UNCONFIRMED)
            return ContentLifecycleReceipt.Deleted(target, time)
        }
        return ContentLifecycleReceipt.Cancelled(target, time, recipients, notices)
    }

    fun cancelled(
        before: ContentLifecycleSnapshot,
        after: ContentLifecycleSnapshot,
        session: OrganizationSession,
        at: Instant? = null,
    ): Boolean {
        val original = before.item ?: return false
        val actual = after.item ?: return false
        val fields = actual.fields
        val cancelledAt = fields["cancelledAt"] as? Instant ?: return false
        return before.target == after.target &&
            before.target.kind == ContentKind.EVENTS &&
            actual.status == AuthoringStatus.ARCHIVED &&
            fields["cancellationState"] == "cancelled" &&
            fields["cancelledBy"] == session.uid &&
            "cancellationReason" !in fields &&
            fields["updatedAt"] == cancelledAt &&
            (at == null || cancelledAt.truncatedTo(ChronoUnit.MILLIS) == at) &&
            original.fields.filterKeys { it !in cancellationFields } ==
                fields.filterKeys { it !in cancellationFields }
    }

    fun confirmed(
        before: ContentLifecycleSnapshot,
        after: ContentLifecycleSnapshot,
        receipt: ContentLifecycleReceipt,
        session: OrganizationSession,
    ): Boolean =
        receipt.target == before.target &&
            after.target == before.target &&
            when (receipt) {
                is ContentLifecycleReceipt.Deleted -> after.item == null
                is ContentLifecycleReceipt.Cancelled ->
                    cancelled(before, after, session, receipt.completedAt)
            }

    fun observed(
        before: ContentLifecycleSnapshot,
        after: ContentLifecycleSnapshot,
        session: OrganizationSession,
    ) =
        when {
            after.item == null -> ContentLifecycleObserved.UNAVAILABLE_CLEANUP_UNCONFIRMED
            cancelled(before, after, session) ->
                ContentLifecycleObserved.CANCELLED_NOTICES_UNCONFIRMED
            before.target == after.target && before.item?.fields == after.item.fields ->
                ContentLifecycleObserved.UNCHANGED
            else -> ContentLifecycleObserved.DIFFERENT
        }

    fun fail(reason: ContentLifecycleFailure): Nothing = throw ContentLifecycleException(reason)
}
