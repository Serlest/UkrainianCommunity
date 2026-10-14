package at.uac.android.feature.dsaowner

import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalCallableFailure
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.dsaappeal.AndroidDsaAppealCharacters
import at.uac.android.feature.dsaappeal.DsaAppealContract
import at.uac.android.feature.dsaappeal.DsaAppealCharacterCounter
import at.uac.android.feature.dsastatement.DsaStatementContract
import at.uac.android.feature.feedback.FeedbackCaseContext
import at.uac.android.feature.feedback.FeedbackContract
import at.uac.android.feature.feedback.FeedbackException
import at.uac.android.feature.moderation.ModerationSession
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.CancellationException

enum class DsaOwnerFailure { ACCESS, MISSING, INVALID, INELIGIBLE, STALE, OFFLINE, UNCONFIRMED, UNKNOWN }
class DsaOwnerException(val failure: DsaOwnerFailure) : Exception(failure.name)

enum class DsaOwnerAction { CASE, APPEAL }

data class DsaOwnerReview(
    val session: ModerationSession,
    val reportId: String,
    val caseNumber: String,
    val context: FeedbackCaseContext,
    val message: String,
    val action: DsaOwnerAction,
    val updatedAt: Instant,
    val caseProjection: Map<*, *>,
) {
    override fun toString() = "DsaOwnerReview(<redacted>)"
}

data class DsaOwnerCaseDraft(
    val outcome: String,
    val facts: String,
    val legalBasis: String,
    val termsBasis: String,
    val territory: String,
    val duration: String,
    val redress: String,
    val humanReviewConfirmed: Boolean,
) {
    override fun toString() = "DsaOwnerCaseDraft(<redacted>)"
}

data class DsaOwnerAppealDraft(
    val outcome: String,
    val reason: String,
    val humanReviewConfirmed: Boolean,
) {
    override fun toString() = "DsaOwnerAppealDraft(<redacted>)"
}

data class DsaOwnerReceipt(
    val caseNumber: String,
    val status: String,
    val decidedAt: Instant,
) {
    override fun toString() = "DsaOwnerReceipt(<redacted>)"
}

interface DsaOwnerSource {
    suspend fun read(session: ModerationSession, reportId: String): RawDocument?
    suspend fun call(session: ModerationSession, action: DsaOwnerAction, payload: Map<String, Any?>): Any?
}

/** Source reads are SERVER-only; the server owns the canonical case, CAS and target validation. */
class DsaOwnerDecisionRepository(
    private val source: DsaOwnerSource,
    private val authority: () -> ModerationSession?,
    private val gate: suspend (ModerationSession, suspend () -> DsaOwnerReceipt) -> DsaOwnerReceipt,
    private val operationId: () -> String = { UUID.randomUUID().toString() },
    private val counter: DsaAppealCharacterCounter = AndroidDsaAppealCharacters,
) {
    private fun fail(failure: DsaOwnerFailure): Nothing = throw DsaOwnerException(failure)

    private fun ensure(actor: ModerationSession) {
        if (authority() != actor || !actor.ready || actor.role != "owner") fail(DsaOwnerFailure.ACCESS)
    }

    private fun projection(row: RawDocument?, actor: ModerationSession): DsaOwnerReview {
        if (row == null) fail(DsaOwnerFailure.MISSING)
        val fields = row.fields
        val item = try { FeedbackContract.item(row) } catch (_: FeedbackException) { fail(DsaOwnerFailure.INVALID) }
        val case = fields["dsaCase"] as? Map<*, *> ?: fail(DsaOwnerFailure.INVALID)
        val context = item.caseContext ?: fail(DsaOwnerFailure.INVALID)
        val updatedAt = fields["updatedAt"] as? Instant ?: fail(DsaOwnerFailure.INVALID)
        if (item.id != row.id || !item.hasDsaCase || context.caseNumber.isBlank() ||
            context.caseNumber.length > 200 || updatedAt <= Instant.EPOCH) fail(DsaOwnerFailure.INVALID)
        val action = when (case["status"]) {
            "submitted", "underReview" -> DsaOwnerAction.CASE
            "appealed" -> {
                if (context.appeal?.status != "pending") fail(DsaOwnerFailure.INELIGIBLE)
                DsaOwnerAction.APPEAL
            }
            else -> fail(DsaOwnerFailure.INELIGIBLE)
        }
        if (action == DsaOwnerAction.CASE && context.appeal?.status == "pending")
            fail(DsaOwnerFailure.INELIGIBLE)
        ensure(actor)
        return DsaOwnerReview(actor, row.id, context.caseNumber, context,
            item.message, action, updatedAt, case.toMap())
    }

    suspend fun review(actor: ModerationSession, reportId: String): DsaOwnerReview {
        ensure(actor)
        if (!DsaStatementContract.validId(reportId)) fail(DsaOwnerFailure.INVALID)
        val row = source.read(actor, reportId)
        ensure(actor)
        return projection(row, actor)
    }

    private fun text(raw: String, max: Int, minLogical: Int = 1): String {
        val normalized = try { DsaAppealContract.normalize(raw) } catch (_: Exception) { fail(DsaOwnerFailure.INVALID) }
        if (normalized.length > max || counter.count(normalized) < minLogical)
            fail(DsaOwnerFailure.INVALID)
        return normalized
    }

    private fun payload(review: DsaOwnerReview, draft: Any, id: String): Map<String, Any?> {
        if (id.length !in 1..200 || !id.matches(Regex("[A-Za-z0-9-]+"))) fail(DsaOwnerFailure.INVALID)
        val common = mapOf(
            "reportId" to review.reportId,
            "humanReviewConfirmed" to true,
            "operationId" to id,
            "expectedRevision" to "${review.updatedAt.epochSecond}:${review.updatedAt.nano}",
        )
        return when (draft) {
            is DsaOwnerCaseDraft -> {
                if (review.action != DsaOwnerAction.CASE || !draft.humanReviewConfirmed ||
                    draft.outcome !in setOf("noAction", "restricted", "removed")) fail(DsaOwnerFailure.INVALID)
                val basis = draft.legalBasis.takeIf(String::isNotBlank)?.let { text(it, 2_000) }
                val terms = draft.termsBasis.takeIf(String::isNotBlank)?.let { text(it, 2_000) }
                if (basis == null && terms == null) fail(DsaOwnerFailure.INVALID)
                common + mapOf(
                    "outcome" to draft.outcome,
                    "factsAndCircumstances" to text(draft.facts, 5_000, 20),
                    "legalBasis" to basis,
                    "termsBasis" to terms,
                    "territorialScope" to text(draft.territory, 500),
                    "duration" to text(draft.duration, 500),
                    "redressInformation" to text(draft.redress, 2_000),
                )
            }
            is DsaOwnerAppealDraft -> {
                if (review.action != DsaOwnerAction.APPEAL || !draft.humanReviewConfirmed ||
                    draft.outcome !in setOf("upheld", "changed")) fail(DsaOwnerFailure.INVALID)
                common + mapOf("outcome" to draft.outcome, "reason" to text(draft.reason, 5_000, 20))
            }
            else -> fail(DsaOwnerFailure.INVALID)
        }
    }

    suspend fun decide(shown: DsaOwnerReview, draft: Any): DsaOwnerReceipt {
        val actor = shown.session
        ensure(actor)
        val fresh = review(actor, shown.reportId)
        if (fresh.action != shown.action || fresh.updatedAt != shown.updatedAt ||
            fresh.caseProjection != shown.caseProjection) fail(DsaOwnerFailure.STALE)
        val data = payload(fresh, draft, operationId())
        var started = false
        return try {
            gate(actor) {
                ensure(actor)
                started = true
                val raw = source.call(actor, fresh.action, data)
                val receipt = decodeReceipt(raw, fresh)
                val row = source.read(actor, fresh.reportId) ?: fail(DsaOwnerFailure.UNCONFIRMED)
                confirm(row, fresh, data, receipt)
                receipt
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: LocalCallableException) {
            fail(when (error.code) {
                LocalCallableFailure.ABORTED -> DsaOwnerFailure.STALE
                LocalCallableFailure.UNAUTHENTICATED,
                LocalCallableFailure.PERMISSION_DENIED -> DsaOwnerFailure.ACCESS
                LocalCallableFailure.FAILED_PRECONDITION,
                LocalCallableFailure.ALREADY_EXISTS -> DsaOwnerFailure.INELIGIBLE
                else -> DsaOwnerFailure.UNCONFIRMED
            })
        } catch (error: DsaOwnerException) {
            if (started) fail(DsaOwnerFailure.UNCONFIRMED)
            throw error
        } catch (_: Exception) {
            fail(if (started) DsaOwnerFailure.UNCONFIRMED else DsaOwnerFailure.UNKNOWN)
        }
    }

    private fun decodeReceipt(raw: Any?, review: DsaOwnerReview): DsaOwnerReceipt {
        val fields = raw as? Map<*, *> ?: fail(DsaOwnerFailure.UNCONFIRMED)
        val keys = if (review.action == DsaOwnerAction.CASE)
            setOf("reportId", "caseNumber", "status", "decidedAt", "appealDeadline")
        else setOf("reportId", "caseNumber", "status", "decidedAt")
        if (fields.keys != keys || fields["reportId"] != review.reportId ||
            fields["caseNumber"] != review.caseNumber) fail(DsaOwnerFailure.UNCONFIRMED)
        val status = fields["status"] as? String ?: fail(DsaOwnerFailure.UNCONFIRMED)
        if (review.action == DsaOwnerAction.CASE && status != "decided" ||
            review.action == DsaOwnerAction.APPEAL && status !in setOf("submitted", "appealDecided"))
            fail(DsaOwnerFailure.UNCONFIRMED)
        val decided = (fields["decidedAt"] as? String)?.let { runCatching { Instant.parse(it) }.getOrNull() }
            ?: fail(DsaOwnerFailure.UNCONFIRMED)
        if (review.action == DsaOwnerAction.CASE &&
            (fields["appealDeadline"] as? String)?.let { runCatching { Instant.parse(it) }.getOrNull() } == null)
            fail(DsaOwnerFailure.UNCONFIRMED)
        return DsaOwnerReceipt(review.caseNumber, status, decided)
    }

    private fun confirm(row: RawDocument, review: DsaOwnerReview, data: Map<String, Any?>, receipt: DsaOwnerReceipt) {
        val fields = row.fields
        val case = fields["dsaCase"] as? Map<*, *> ?: fail(DsaOwnerFailure.UNCONFIRMED)
        val expectedStatus = receipt.status
        if (row.id != review.reportId || case["caseNumber"] != review.caseNumber ||
            case["status"] != expectedStatus || fields["updatedAt"] != receipt.decidedAt)
            fail(DsaOwnerFailure.UNCONFIRMED)
        if (review.action == DsaOwnerAction.CASE) {
            val decision = case["decision"] as? Map<*, *> ?: fail(DsaOwnerFailure.UNCONFIRMED)
            if (decision["outcome"] != data["outcome"] ||
                decision["factsAndCircumstances"] != data["factsAndCircumstances"] ||
                decision["legalBasis"] != data["legalBasis"] ||
                decision["termsBasis"] != data["termsBasis"] ||
                decision["decidedAt"] != receipt.decidedAt)
                fail(DsaOwnerFailure.UNCONFIRMED)
        } else {
            val appeal = case["appeal"] as? Map<*, *> ?: fail(DsaOwnerFailure.UNCONFIRMED)
            if (appeal["status"] != "decided" || appeal["outcome"] != data["outcome"] ||
                appeal["reason"] != data["reason"] || appeal["decidedAt"] != receipt.decidedAt)
                fail(DsaOwnerFailure.UNCONFIRMED)
        }
    }
}
