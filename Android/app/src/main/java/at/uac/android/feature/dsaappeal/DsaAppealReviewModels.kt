package at.uac.android.feature.dsaappeal

import at.uac.android.feature.feedback.FeedbackCaseContext
import java.time.Instant

data class DsaAppealSession(
    val uid: String,
    val revision: Long,
    val backend: String,
    val ready: Boolean,
) {
    override fun toString() = "DsaAppealSession(<redacted>)"
}

enum class DsaAppealReviewFailure {
    ACCESS,
    INVALID,
    MISSING,
    INELIGIBLE,
    EXPIRED,
    OFFLINE,
    STALE,
    UNKNOWN,
}

class DsaAppealReviewException(val failure: DsaAppealReviewFailure) : Exception(failure.name)

data class DsaAppealDecision(
    val outcome: String,
    val facts: String,
    val legalBasis: String?,
    val termsBasis: String?,
    val territory: String,
    val duration: String,
    val redress: String,
    val automationUsed: Boolean,
    val humanReviewConfirmed: Boolean,
    val decidedAt: Instant,
    val appealDeadline: Instant,
) {
    override fun toString() = "DsaAppealDecision(<redacted>)"
}

/** Exact fingerprint of the selected review fields, NOT a server CAS/version token. */
data class DsaAppealReviewSnapshot(
    val reportId: String,
    val reporterUid: String,
    val context: FeedbackCaseContext,
    val decision: DsaAppealDecision,
    val fingerprint: String,
) {
    override fun toString() = "DsaAppealReviewSnapshot(<redacted>)"
}

/** Fresh read bound to one account/backend revision. Does not authorize a future send. */
data class DsaAppealReview(val session: DsaAppealSession, val snapshot: DsaAppealReviewSnapshot) {
    override fun toString() = "DsaAppealReview(<redacted>)"
}
