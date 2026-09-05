package at.uac.android.feature.feedbackdeletion

import at.uac.android.core.LocalCallableProtocol
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.feedback.FeedbackAudience
import at.uac.android.feature.feedback.FeedbackContract
import at.uac.android.feature.feedback.FeedbackException
import at.uac.android.feature.feedback.FeedbackStatus
import at.uac.android.feature.feedback.FeedbackType
import at.uac.android.feature.moderation.ModerationSession
import java.time.Instant

enum class FeedbackDeletionFailure {
    ACCESS,
    INVALID,
    MISSING,
    STALE,
    JOURNAL,
    PENDING,
    OFFLINE,
    UNCONFIRMED,
}

class FeedbackDeletionException(val failure: FeedbackDeletionFailure, cause: Throwable? = null) :
    Exception(failure.name, cause)

/** Private, memory-only review labels. This projection is NOT a raw version or SDK authority. */
data class FeedbackDeletionTarget(
    val feedbackId: String,
    val authorId: String,
    val authorName: String,
    val subject: String?,
    val type: FeedbackType?,
    val status: FeedbackStatus,
    val createdAt: Instant,
    val hasDsaCase: Boolean,
    val caseNumber: String?,
) {
    override fun toString() = "FeedbackDeletionTarget([redacted])"
}

/** Parsed wire data only. The server echoes neither target ID nor operation ID/version. */
data class FeedbackDeletionResponse(val deletedCount: Int) {
    override fun toString() = "FeedbackDeletionResponse([redacted])"
}

/**
 * Single-record owner deletion only. No own-user deletion or whole-inbox clear belongs here. No
 * callable is enabled by this pure policy. Actual identity/profile/TOTP, durable dispatch and
 * operation-bound settlement must be supplied by the separately verified repository/SDK layer.
 */
object FeedbackDeletionContract {
    const val CALLABLE = "deleteFeedback"
    const val MAXIMUM_TIMEOUT_MILLIS = 300_000L

    fun fail(failure: FeedbackDeletionFailure): Nothing = throw FeedbackDeletionException(failure)

    // Server validates JS string.length <=200 before trim. A selected canonical path is never
    // silently normalized to a different target, even if the server would accept the alias.
    fun id(value: String): Boolean = canonicalSegment(value, 200)

    fun requireSession(session: ModerationSession) {
        if (
            !session.ready ||
                session.role != "owner" ||
                session.revision < 0 ||
                !canonicalSegment(session.uid, 128)
        )
            fail(FeedbackDeletionFailure.ACCESS)
    }

    fun requireTarget(
        session: ModerationSession,
        audience: FeedbackAudience,
        target: FeedbackDeletionTarget,
    ) {
        requireSession(session)
        if (audience != FeedbackAudience.MANAGEMENT) fail(FeedbackDeletionFailure.ACCESS)
        if (!id(target.feedbackId) || !canonicalSegment(target.authorId, 128))
            fail(FeedbackDeletionFailure.INVALID)
        // A feedback record is not a user account: owner-authored, closed and DSA-linked records
        // have no special deletion veto in the reviewed server/iOS contract. This does not close
        // a legal case or delete the separately retained case/statement/evidence.
    }

    fun target(row: RawDocument): FeedbackDeletionTarget {
        if (!id(row.id)) fail(FeedbackDeletionFailure.INVALID)
        val item =
            try {
                FeedbackContract.item(row)
            } catch (error: FeedbackException) {
                throw FeedbackDeletionException(FeedbackDeletionFailure.INVALID, error)
            }
        if (!canonicalSegment(item.uid, 128)) fail(FeedbackDeletionFailure.INVALID)
        return FeedbackDeletionTarget(
            row.id,
            item.uid,
            item.name,
            item.subject,
            item.type,
            item.status,
            item.createdAt,
            item.hasDsaCase,
            item.caseNumber,
        )
    }

    /** Exact existing payload. No invented reason, reviewedVersion, requestId or message IDs. */
    fun payload(feedbackId: String): Map<String, String> {
        if (!id(feedbackId)) fail(FeedbackDeletionFailure.INVALID)
        val value = mapOf("feedbackId" to feedbackId)
        try {
            LocalCallableProtocol.request(value)
        } catch (error: Exception) {
            throw FeedbackDeletionException(FeedbackDeletionFailure.INVALID, error)
        }
        return value
    }

    /** Call only on the actual successful awaited Task; a missing document is NOT this response. */
    fun response(data: Any?): FeedbackDeletionResponse {
        val map = data as? Map<*, *> ?: fail(FeedbackDeletionFailure.UNCONFIRMED)
        if (map.keys != setOf("deletedCount")) fail(FeedbackDeletionFailure.UNCONFIRMED)
        val count = map["deletedCount"]
        val one =
            when (count) {
                is Byte,
                is Short,
                is Int,
                is Long -> (count as Number).toLong() == 1L
                is Float,
                is Double -> (count as Number).toDouble() == 1.0
                else -> false
            }
        if (!one) fail(FeedbackDeletionFailure.UNCONFIRMED)
        // This count is the server's thread count, not message/notification counts, an atomic
        // cascade proof, audit success, an echoed target, or an idempotency receipt.
        return FeedbackDeletionResponse(1)
    }

    private fun canonicalSegment(value: String, maximum: Int): Boolean {
        if (
            value.length !in 1..maximum ||
                value in setOf(".", "..") ||
                (value.startsWith("__") && value.endsWith("__")) ||
                value.any { it == '/' || it.isISOControl() } ||
                value.trim(::serverWhitespace) != value
        )
            return false
        var index = 0
        while (index < value.length) {
            val character = value[index++]
            if (character.isHighSurrogate()) {
                if (index >= value.length || !value[index++].isLowSurrogate()) return false
            } else if (character.isLowSurrogate()) return false
        }
        return true
    }

    private fun serverWhitespace(value: Char): Boolean =
        value in " \t\n\r\u000B\u000C\u00A0\u1680\u2028\u2029\u202F\u205F\u3000\uFEFF" ||
            value in '\u2000'..'\u200A'
}
