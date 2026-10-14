package at.uac.android.feature.dsaappeal

import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalCallableFailure
import at.uac.android.feature.browse.RawDocument
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.CancellationException

/** One settled callable attempt. The server owns authorization, revision CAS and idempotency. */
fun interface DsaAppealSubmissionSource {
    suspend fun submit(session: DsaAppealSession, payload: Map<String, String>): Any?
}

class DsaAppealSubmissionRepository(
    private val read: DsaAppealReadRepository,
    private val readSource: DsaAppealReadSource,
    private val submitSource: DsaAppealSubmissionSource,
    private val authority: () -> DsaAppealSession?,
    private val gate: DsaAppealReadGate,
    private val counter: DsaAppealCharacterCounter,
    private val clock: () -> Instant = Instant::now,
    private val operationId: () -> String = { UUID.randomUUID().toString() },
) {
    suspend fun submit(shown: DsaAppealReview, rawReason: String): DsaAppealResponse {
        val actor = shown.session
        if (authority() != actor || !actor.ready || shown.snapshot.reporterUid != actor.uid)
            DsaAppealReviewContract.fail(DsaAppealReviewFailure.ACCESS)
        val reason = DsaAppealContract.review(rawReason, counter)
        // A screen read is never an authorization to send. Read the exact owned record again.
        val fresh = read.read(actor, shown.snapshot.reportId, shown.snapshot.fingerprint)
        val revision = fresh.snapshot.updatedAt
        if (revision == Instant.EPOCH || revision.epochSecond < 0)
            DsaAppealReviewContract.fail(DsaAppealReviewFailure.INVALID)
        val id = operationId()
        if (!Regex("[A-Za-z0-9-]{1,200}").matches(id))
            DsaAppealReviewContract.fail(DsaAppealReviewFailure.INVALID)
        val payload = DsaAppealContract.payload(fresh.snapshot.reportId, reason) +
            mapOf(
                "operationId" to id,
                "expectedRevision" to "${revision.epochSecond}:${revision.nano}",
            )
        var dispatchStarted = false
        return try {
            gate.withSession(actor) {
                if (authority() != actor || clock() >= fresh.snapshot.decision.appealDeadline)
                    DsaAppealReviewContract.fail(DsaAppealReviewFailure.STALE)
                dispatchStarted = true
                val data = submitSource.submit(actor, payload)
                val receipt = DsaAppealContract.response(
                    fresh.snapshot.reportId,
                    fresh.snapshot.context.caseNumber,
                    data,
                )
                // Read the user's iOS-visible projection after the server commits. A callable
                // response alone cannot prove that Android and iOS will see the same appeal.
                val row = readSource.read(actor, receipt.reportId)
                    ?: DsaAppealReviewContract.fail(DsaAppealReviewFailure.UNCONFIRMED)
                requireReceipt(row, actor, reason.reason, receipt)
                receipt
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: LocalCallableException) {
            DsaAppealReviewContract.fail(
                when (error.code) {
                    LocalCallableFailure.ABORTED -> DsaAppealReviewFailure.STALE
                    LocalCallableFailure.PERMISSION_DENIED,
                    LocalCallableFailure.UNAUTHENTICATED -> DsaAppealReviewFailure.ACCESS
                    LocalCallableFailure.FAILED_PRECONDITION,
                    LocalCallableFailure.ALREADY_EXISTS -> DsaAppealReviewFailure.INELIGIBLE
                    LocalCallableFailure.UNCONFIRMED,
                    LocalCallableFailure.UNAVAILABLE,
                    LocalCallableFailure.DEADLINE_EXCEEDED -> DsaAppealReviewFailure.UNCONFIRMED
                    else -> if (dispatchStarted) DsaAppealReviewFailure.UNCONFIRMED else DsaAppealReviewFailure.UNKNOWN
                }
            )
        } catch (error: DsaAppealReviewException) {
            if (dispatchStarted) DsaAppealReviewContract.fail(DsaAppealReviewFailure.UNCONFIRMED)
            throw error
        } catch (_: Exception) {
            DsaAppealReviewContract.fail(
                if (dispatchStarted) DsaAppealReviewFailure.UNCONFIRMED else DsaAppealReviewFailure.UNKNOWN
            )
        }
    }

    private fun requireReceipt(
        row: RawDocument,
        actor: DsaAppealSession,
        reason: String,
        receipt: DsaAppealResponse,
    ) {
        val fields = row.fields
        val case = fields["dsaCase"] as? Map<*, *>
        val appeal = case?.get("appeal") as? Map<*, *>
        if (
            case == null || appeal == null ||
            row.id != receipt.reportId ||
                fields["userId"] != actor.uid ||
                case["caseNumber"] != receipt.caseNumber ||
                case["status"] != "appealed" ||
                appeal["status"] != "pending" ||
                appeal["reason"] != reason ||
                appeal["submittedAt"] != receipt.submittedAt
        ) DsaAppealReviewContract.fail(DsaAppealReviewFailure.UNCONFIRMED)
    }
}
