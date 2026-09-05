package at.uac.android.feature.dsaappeal

import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.dsastatement.DsaStatementContract
import java.io.IOException
import java.time.Instant
import kotlin.coroutines.CoroutineContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

/** An adapter must supply an owned SERVER read without pending writes, never cache as absence. */
fun interface DsaAppealReadSource {
    suspend fun read(session: DsaAppealSession, reportId: String): RawDocument?
}

interface DsaAppealReadGate {
    suspend fun <T> withSession(session: DsaAppealSession, action: suspend () -> T): T
}

/**
 * Fresh review only. No journal allocation, send, retry or permission to perform a later action.
 */
class DsaAppealReadRepository(
    private val source: DsaAppealReadSource,
    private val authority: () -> DsaAppealSession?,
    private val gate: DsaAppealReadGate,
    private val clock: () -> Instant = Instant::now,
) {
    private fun ensure(actor: DsaAppealSession, caller: CoroutineContext) {
        caller.ensureActive()
        if (actor != authority()) throw CancellationException("Appeal review scope changed")
        if (
            !actor.ready ||
                !DsaStatementContract.validId(actor.uid, 128) ||
                actor.backend.isBlank() ||
                actor.backend.length > 1_024
        )
            DsaAppealReviewContract.fail(DsaAppealReviewFailure.ACCESS)
    }

    suspend fun read(
        actor: DsaAppealSession,
        reportId: String,
        expectedFingerprint: String? = null,
        stillSelected: () -> Boolean = { true },
    ): DsaAppealReview {
        val caller = currentCoroutineContext()
        fun selected() {
            ensure(actor, caller)
            if (!stillSelected()) DsaAppealReviewContract.fail(DsaAppealReviewFailure.STALE)
            ensure(actor, caller)
        }
        try {
            selected()
            if (
                !DsaStatementContract.validId(reportId) ||
                    expectedFingerprint?.matches(Regex("[a-f0-9]{64}")) == false
            )
                DsaAppealReviewContract.fail(DsaAppealReviewFailure.INVALID)
            val result =
                gate.withSession(actor) {
                    selected()
                    val row = source.read(actor, reportId)
                    selected()
                    if (row == null) DsaAppealReviewContract.fail(DsaAppealReviewFailure.MISSING)
                    if (row.id != reportId)
                        DsaAppealReviewContract.fail(DsaAppealReviewFailure.STALE)
                    val snapshot = DsaAppealReviewContract.snapshot(row, actor.uid, clock())
                    selected()
                    if (expectedFingerprint != null && snapshot.fingerprint != expectedFingerprint)
                        DsaAppealReviewContract.fail(DsaAppealReviewFailure.STALE)
                    DsaAppealReview(actor, snapshot)
                }
            selected()
            // The gate itself can wait: expiry after its awaited Task still invalidates review.
            DsaAppealReviewContract.requireOpenWindow(result.snapshot.decision, clock())
            selected()
            return result
        } catch (failure: Exception) {
            selected()
            when (failure) {
                is TimeoutCancellationException ->
                    DsaAppealReviewContract.fail(DsaAppealReviewFailure.OFFLINE)
                is CancellationException -> throw failure
                is DsaAppealReviewException -> throw failure
                is IOException -> DsaAppealReviewContract.fail(DsaAppealReviewFailure.OFFLINE)
                else -> DsaAppealReviewContract.fail(DsaAppealReviewFailure.UNKNOWN)
            }
        }
    }
}
