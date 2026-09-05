package at.uac.android.feature.moderation

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class ModerationDecisionState(
    val session: ModerationSession? = null,
    val journalReady: Boolean = false,
    val busy: Boolean = false,
    val pending: List<ModerationPending> = emptyList(),
    val confirmation: ModerationDecision? = null,
    val error: ModerationDecisionFailure? = null,
    val observation: ModerationObservation? = null,
    val completion: Long = 0,
) {
    fun forSession(current: ModerationSession?) =
        if (session == current && current?.allowed == true) this
        else ModerationDecisionState(session = current)

    override fun toString() = "ModerationDecisionState(busy=$busy, [redacted])"
}

class ModerationDecisionViewModel(
    private val repository: ModerationDecisionRepository,
    private val authority: () -> ModerationSession? = repository::currentSession,
    private val workScope: CoroutineScope? = null,
) : ViewModel() {
    private val scope
        get() = workScope ?: viewModelScope

    private val mutable = MutableStateFlow(ModerationDecisionState())
    val state: StateFlow<ModerationDecisionState> = mutable.asStateFlow()
    private var observer: Job? = null
    private var read: Job? = null
    private var readGeneration = 0L

    private data class View(
        val session: ModerationSession,
        val version: ModerationReviewVersion,
        val token: ModerationPresentation,
    )

    private var view: View? = null
    private var viewGuard: () -> Boolean = { false }

    private fun alive(session: ModerationSession) =
        session == authority() && session == mutable.value.session && session.allowed

    fun snapshot(session: ModerationSession?) =
        if (session == authority()) state.value.forSession(session) else ModerationDecisionState()

    fun observeSessions(sessions: Flow<ModerationSession?>) {
        observer?.cancel()
        observer = scope.launch { sessions.collect(::bind) }
    }

    fun bind(session: ModerationSession?) {
        val current = session?.takeIf { it == authority() && it.allowed }
        if (mutable.value.session == current) return
        readGeneration++
        read?.cancel()
        view = null
        viewGuard = { false }
        mutable.value = ModerationDecisionState(session = current)
        refreshPending()
    }

    fun bindView(
        session: ModerationSession?,
        version: ModerationReviewVersion?,
        token: ModerationPresentation?,
        canSubmit: () -> Boolean,
    ) {
        bind(session)
        val next =
            if (
                session != null && alive(session) && version != null && token != null && canSubmit()
            )
                View(session, version, token)
            else null
        if (view != next) mutable.value = mutable.value.copy(confirmation = null)
        view = next
        viewGuard = canSubmit
    }

    fun refreshPending() {
        val session = mutable.value.session ?: return
        if (!alive(session) || mutable.value.busy) return
        val generation = ++readGeneration
        read?.cancel()
        read = scope.launch {
            try {
                val pending = repository.pending(session)
                if (generation == readGeneration && alive(session))
                    mutable.value =
                        mutable.value.copy(pending = pending, journalReady = true, error = null)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (generation == readGeneration && alive(session))
                    mutable.value =
                        mutable.value.copy(
                            journalReady = false,
                            error = moderationDecisionFailure(error),
                        )
            }
        }
    }

    fun request(decision: ModerationDecision) {
        val captured = view ?: return
        if (
            !alive(captured.session) ||
                !viewGuard() ||
                !mutable.value.journalReady ||
                mutable.value.busy ||
                mutable.value.pending.any { it.version.target == captured.version.target }
        )
            return
        mutable.value =
            mutable.value.copy(confirmation = decision, error = null, observation = null)
    }

    fun cancelConfirmation() {
        mutable.value = mutable.value.copy(confirmation = null)
    }

    fun confirm() {
        val captured = view ?: return
        val decision = mutable.value.confirmation ?: return
        val originalGuard = viewGuard
        if (
            !alive(captured.session) ||
                !originalGuard() ||
                mutable.value.busy ||
                !mutable.value.journalReady
        )
            return
        perform(captured.session) {
            repository.execute(captured.session, captured.version, decision) {
                view == captured && alive(captured.session) && originalGuard()
            }
        }
    }

    fun reconcile(entry: ModerationPending) {
        val session = mutable.value.session ?: return
        if (
            !alive(session) || !viewGuard() || mutable.value.busy || entry !in mutable.value.pending
        )
            return
        perform(session) { repository.reconcile(session, entry) }
    }

    private fun perform(
        session: ModerationSession,
        operation: suspend () -> ModerationObservation,
    ) {
        readGeneration++
        read?.cancel()
        mutable.value =
            mutable.value.copy(busy = true, confirmation = null, error = null, observation = null)
        scope.launch {
            var observation: ModerationObservation? = null
            var failure: ModerationDecisionFailure? = null
            try {
                observation = operation()
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                failure = moderationDecisionFailure(error)
            }
            if (!alive(session)) return@launch
            var pending = mutable.value.pending
            var ready = true
            try {
                pending = repository.pending(session)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                failure = ModerationDecisionFailure.JOURNAL
                ready = false
            }
            if (alive(session))
                mutable.value =
                    mutable.value.copy(
                        busy = false,
                        pending = pending,
                        journalReady = ready,
                        error = failure,
                        observation = observation,
                        completion =
                            mutable.value.completion + if (observation?.confirmed == true) 1 else 0,
                    )
        }
    }

    override fun onCleared() {
        readGeneration++
        view = null
        viewGuard = { false }
        super.onCleared()
    }
}
