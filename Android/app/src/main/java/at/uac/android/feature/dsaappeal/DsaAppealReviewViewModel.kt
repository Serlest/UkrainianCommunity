package at.uac.android.feature.dsaappeal

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import at.uac.android.feature.dsastatement.DsaStatementContract
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Read-only preparation; never represents server authorization, a draft or an operation receipt.
 */
data class DsaAppealReviewState(
    val session: DsaAppealSession? = null,
    val reportId: String? = null,
    val visible: Boolean = false,
    val loading: Boolean = false,
    val review: DsaAppealReview? = null,
    val error: DsaAppealReviewFailure? = null,
) {
    override fun toString() = "DsaAppealReviewState([redacted])"
}

fun DsaAppealReviewState.forSession(
    authority: DsaAppealSession?,
    now: Instant,
): DsaAppealReviewState {
    if (session != authority || authority?.ready != true)
        return DsaAppealReviewState(session = authority)
    val decision = review?.snapshot?.decision ?: return this
    return if (!now.isBefore(decision.appealDeadline))
        copy(review = null, loading = false, error = DsaAppealReviewFailure.EXPIRED)
    else if (now.isBefore(decision.decidedAt))
        copy(review = null, loading = false, error = DsaAppealReviewFailure.INELIGIBLE)
    else this
}

class DsaAppealReviewViewModel(
    source: DsaAppealReadSource,
    private val authority: () -> DsaAppealSession?,
    gate: DsaAppealReadGate,
    private val clock: () -> Instant = Instant::now,
) : ViewModel() {
    private val repository = DsaAppealReadRepository(source, authority, gate, clock)
    private val mutable = MutableStateFlow(DsaAppealReviewState(session = authority()))
    val state = mutable.asStateFlow()
    private var observer: Job? = null
    private var readJob: Job? = null
    private var expiryJob: Job? = null
    private var epoch = 0L

    fun observeSessions(sessions: Flow<DsaAppealSession?>) {
        observer?.cancel()
        observer =
            viewModelScope.launch(Dispatchers.Main.immediate, start = CoroutineStart.UNDISPATCHED) {
                sessions.collect(::bind)
            }
    }

    private fun invalidate() {
        epoch++
        readJob?.cancel()
        readJob = null
        expiryJob?.cancel()
        expiryJob = null
    }

    fun bind(session: DsaAppealSession?) {
        if (mutable.value.session == session) return
        invalidate()
        mutable.value = DsaAppealReviewState(session = session)
    }

    fun show(reportId: String) {
        bind(authority())
        if (mutable.value.visible && mutable.value.reportId == reportId) return
        invalidate()
        mutable.value =
            DsaAppealReviewState(session = authority(), reportId = reportId, visible = true)
        refresh()
    }

    fun hide(reportId: String) {
        if (mutable.value.reportId != reportId) return
        invalidate()
        mutable.value = DsaAppealReviewState(session = authority())
    }

    fun refresh() {
        if (mutable.value.session != authority()) {
            bind(authority())
            return
        }
        val captured = mutable.value
        if (!captured.visible || readJob?.isActive == true) return
        expiryJob?.cancel()
        expiryJob = null
        val actor = captured.session
        val report = captured.reportId
        if (actor?.ready != true) {
            mutable.value =
                captured.copy(review = null, loading = false, error = DsaAppealReviewFailure.ACCESS)
            return
        }
        if (report == null || !DsaStatementContract.validId(report)) {
            mutable.value =
                captured.copy(
                    review = null,
                    loading = false,
                    error = DsaAppealReviewFailure.INVALID,
                )
            return
        }
        val generation = ++epoch
        fun current() =
            generation == epoch &&
                mutable.value.visible &&
                mutable.value.reportId == report &&
                mutable.value.session == actor &&
                authority() == actor
        mutable.value = captured.copy(review = null, loading = true, error = null)
        readJob = viewModelScope.launch {
            try {
                val review = repository.read(actor, report, stillSelected = ::current)
                if (current()) {
                    mutable.value = mutable.value.copy(review = review, loading = false)
                    expiryJob = viewModelScope.launch {
                        // Local visibility fence only. No automatic network reload or dispatch.
                        while (current()) {
                            val now = clock()
                            val masked = mutable.value.forSession(actor, now)
                            if (masked.review == null) {
                                mutable.value = masked
                                break
                            }
                            val remaining =
                                Duration.between(now, review.snapshot.decision.appealDeadline)
                            // Recheck wall-clock jumps at most once/minute; ceil avoids early
                            // expiry.
                            val millis =
                                (remaining.toMillis() +
                                        if (remaining.nano % 1_000_000 != 0) 1 else 0)
                                    .coerceIn(1, 60_000)
                            delay(millis)
                        }
                    }
                }
            } catch (error: CancellationException) {
                if (current()) mutable.value = mutable.value.copy(review = null, loading = false)
                throw error
            } catch (error: DsaAppealReviewException) {
                if (current())
                    mutable.value =
                        mutable.value.copy(review = null, loading = false, error = error.failure)
            }
        }
    }
}
