package at.uac.android.feature.dsaowner

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import at.uac.android.feature.moderation.ModerationSession
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class DsaOwnerState(
    val session: ModerationSession? = null,
    val reportId: String? = null,
    val visible: Boolean = false,
    val loading: Boolean = false,
    val review: DsaOwnerReview? = null,
    val error: DsaOwnerFailure? = null,
    val submitting: Boolean = false,
    val receipt: DsaOwnerReceipt? = null,
) {
    override fun toString() = "DsaOwnerState(<redacted>)"
}

class DsaOwnerDecisionViewModel(
    source: DsaOwnerSource,
    private val authority: () -> ModerationSession?,
    gate: suspend (ModerationSession, suspend () -> DsaOwnerReceipt) -> DsaOwnerReceipt,
) : ViewModel() {
    private val repository = DsaOwnerDecisionRepository(source, authority, gate)
    private val mutable = MutableStateFlow(DsaOwnerState(session = authority()))
    val state = mutable.asStateFlow()
    private var work: Job? = null
    private var epoch = 0L

    fun bind(session: ModerationSession?) {
        if (mutable.value.session == session) return
        epoch++
        work?.cancel()
        mutable.value = DsaOwnerState(session = session)
    }

    fun show(reportId: String) {
        bind(authority())
        if (mutable.value.visible && mutable.value.reportId == reportId) return
        epoch++
        work?.cancel()
        mutable.value = DsaOwnerState(session = authority(), reportId = reportId, visible = true)
        refresh()
    }

    fun hide(reportId: String) {
        if (mutable.value.reportId != reportId) return
        epoch++
        work?.cancel()
        mutable.value = DsaOwnerState(session = authority())
    }

    fun refresh() {
        val captured = mutable.value
        val actor = captured.session
        val report = captured.reportId
        if (!captured.visible || captured.submitting || work?.isActive == true) return
        if (actor == null || !actor.ready || actor.role != "owner" || report == null) {
            mutable.value = captured.copy(review = null, error = DsaOwnerFailure.ACCESS)
            return
        }
        val generation = ++epoch
        fun current() = generation == epoch && authority() == actor &&
            mutable.value.visible && mutable.value.reportId == report && mutable.value.session == actor
        mutable.value = captured.copy(loading = true, review = null, error = null)
        work = viewModelScope.launch {
            try {
                val review = repository.review(actor, report)
                if (current()) mutable.value = mutable.value.copy(loading = false, review = review)
            } catch (error: CancellationException) {
                throw error
            } catch (error: DsaOwnerException) {
                if (current()) mutable.value = mutable.value.copy(loading = false, error = error.failure)
            } catch (_: Exception) {
                if (current()) mutable.value = mutable.value.copy(loading = false, error = DsaOwnerFailure.UNKNOWN)
            }
        }
    }

    fun decide(draft: Any) {
        val captured = mutable.value
        val review = captured.review ?: return
        if (!captured.visible || captured.submitting || captured.receipt != null ||
            work?.isActive == true || authority() != review.session) return
        val generation = ++epoch
        fun current() = generation == epoch && authority() == review.session &&
            mutable.value.visible && mutable.value.reportId == review.reportId
        mutable.value = captured.copy(submitting = true, error = null)
        work = viewModelScope.launch {
            try {
                val receipt = repository.decide(review, draft)
                if (current()) mutable.value = mutable.value.copy(
                    submitting = false, review = null, receipt = receipt)
            } catch (error: CancellationException) {
                throw error
            } catch (error: DsaOwnerException) {
                if (current()) mutable.value = mutable.value.copy(
                    submitting = false, review = null, error = error.failure)
            } catch (_: Exception) {
                if (current()) mutable.value = mutable.value.copy(
                    submitting = false, review = null, error = DsaOwnerFailure.UNCONFIRMED)
            }
        }
    }
}
