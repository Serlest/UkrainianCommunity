package at.uac.android.feature.community

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class CommunityState(
    val session: CommunitySession? = null,
    val target: CommunityTarget? = null,
    val visible: Boolean = false,
    val participation: EventParticipation? = null,
    val registrationError: CommunityFailure? = null,
    val registrationBusy: Boolean = false,
    val page: CommentPage? = null,
    val commentsError: CommunityFailure? = null,
    val commentsLoading: Boolean = false,
    val canModerate: Boolean = false,
    val draft: String = "",
    val sending: Boolean = false,
    val deleting: Set<String> = emptySet(),
    val actionError: CommunityFailure? = null,
    val sentId: String? = null,
    val uncertain: Boolean = false,
)

class CommunityViewModel(
    source: CommunitySource,
    private val sessionAuthority: () -> CommunitySession?,
    mutationGate: CommunityMutationGate,
    private val onConfirmedRegistration: (CommunityRegistrationChange) -> Unit = {},
) : ViewModel() {
    private val repository = CommunityRepository(source, sessionAuthority, mutationGate)
    private val mutable = MutableStateFlow(CommunityState(session = sessionAuthority()))
    val state: StateFlow<CommunityState> = mutable.asStateFlow()
    private var observer: Job? = null
    private var commentsJob: Job? = null
    private val jobs = mutableMapOf<String, Job>()
    private val uncertainTargets = mutableSetOf<Pair<CommunitySession?, CommunityTarget>>()
    private val sendsInFlight = mutableSetOf<Pair<CommunitySession?, CommunityTarget>>()
    private var epoch = 0L

    fun observeSessions(sessions: Flow<CommunitySession?>) {
        observer?.cancel()
        observer =
            viewModelScope.launch(Dispatchers.Main.immediate, start = CoroutineStart.UNDISPATCHED) {
                sessions.collect { scope ->
                    if (mutable.value.session != scope) {
                        uncertainTargets.removeAll { it.first != scope }
                        val previous = mutable.value
                        reset(
                            CommunityState(
                                session = scope,
                                target = previous.target,
                                visible = previous.visible,
                            )
                        )
                        if (previous.visible) restart()
                    }
                }
            }
    }

    fun show(target: CommunityTarget) {
        if (
            mutable.value.visible &&
                mutable.value.target == target &&
                mutable.value.session == sessionAuthority()
        )
            return
        val previous = mutable.value
        val preserveDraft = previous.target == target && previous.session == sessionAuthority()
        reset(
            CommunityState(
                sessionAuthority(),
                target,
                true,
                draft = if (preserveDraft) previous.draft else "",
                sending = (sessionAuthority() to target) in sendsInFlight,
                uncertain = (sessionAuthority() to target) in uncertainTargets,
            )
        )
        restart()
    }

    fun hide(target: CommunityTarget) {
        if (mutable.value.target != target) return
        reset(
            CommunityState(
                sessionAuthority(),
                target,
                false,
                draft = mutable.value.draft,
                uncertain = mutable.value.uncertain,
            )
        )
    }

    private fun reset(value: CommunityState) {
        epoch++
        commentsJob?.cancel()
        jobs.values.forEach { it.cancel() }
        jobs.clear()
        mutable.value = value
    }

    private fun current(captured: CommunityState, generation: Long): Boolean =
        epoch == generation &&
            mutable.value.visible &&
            captured.target == mutable.value.target &&
            sessionAuthority() == captured.session

    private fun restart() {
        watchComments()
        refreshRegistration()
        launch("moderation") { captured, update ->
            val allowed = repository.moderation(captured.target!!)
            update { it.copy(canModerate = allowed) }
        }
    }

    private fun watchComments() {
        commentsJob?.cancel()
        val captured = mutable.value
        val target = captured.target ?: return
        val generation = epoch
        mutable.value = captured.copy(commentsLoading = true, commentsError = null)
        commentsJob = viewModelScope.launch {
            repository.comments(target).collect { result ->
                if (!current(captured, generation)) return@collect
                mutable.value =
                    mutable.value.copy(
                        page = result.getOrNull(),
                        commentsLoading = false,
                        commentsError = result.exceptionOrNull()?.let(::communityFailure),
                    )
            }
        }
    }

    fun refreshComments() {
        if (mutable.value.visible) watchComments()
    }

    fun refreshRegistration() {
        if (mutable.value.target?.type != "event" || mutable.value.session?.ready != true) return
        launch(
            "registration",
            before = { it.copy(registrationBusy = true, registrationError = null) },
            failure = { state, error ->
                state.copy(
                    participation = null,
                    registrationBusy = false,
                    registrationError = error,
                )
            },
        ) { captured, update ->
            val actual = repository.participation(captured.target!!)
            update { it.copy(participation = actual, registrationBusy = false) }
        }
    }

    fun setRegistration(registered: Boolean) {
        if (mutable.value.target?.type != "event") return
        launch(
            "registration",
            before = { it.copy(registrationBusy = true, registrationError = null) },
            failure = { state, error ->
                state.copy(
                    registrationBusy = false,
                    participation = null,
                    registrationError = error,
                )
            },
        ) { captured, update ->
            val generation = epoch
            val receipt = repository.setRegistrationConfirmed(captured.target!!, registered)
            update { it.copy(participation = receipt.participation, registrationBusy = false) }
            currentCoroutineContext().ensureActive()
            if (receipt.didChange && current(captured, generation)) {
                // Callback is outside the identity gate, after server read-back; secondary work
                // cannot undo registration.
                runCatching { onConfirmedRegistration(receipt) }
            }
        }
    }

    fun draft(value: String) {
        if (sessionAuthority() != mutable.value.session || !mutable.value.visible) return
        mutable.value =
            mutable.value.copy(
                draft = value,
                sentId = null,
                actionError = if (mutable.value.uncertain) CommunityFailure.UNCONFIRMED else null,
            )
    }

    fun acknowledgeUncertainSend() {
        if (
            mutable.value.page?.cached == false &&
                !mutable.value.sending &&
                (mutable.value.session to mutable.value.target) !in sendsInFlight
        ) {
            mutable.value.target?.let { uncertainTargets.remove(mutable.value.session to it) }
            mutable.value = mutable.value.copy(uncertain = false, actionError = null)
        }
    }

    fun addComment() {
        if (
            mutable.value.uncertain ||
                mutable.value.sending ||
                mutable.value.session?.ready != true ||
                mutable.value.target?.acceptsNewComments != true
        )
            return
        launch(
            "send",
            before = {
                uncertainTargets.add(it.session to it.target!!)
                sendsInFlight.add(it.session to it.target)
                it.copy(sending = true, actionError = null, sentId = null)
            },
            failure = { state, error ->
                state.copy(
                    sending = false,
                    actionError = error,
                    uncertain = error == CommunityFailure.UNCONFIRMED,
                    page = if (error == CommunityFailure.UNCONFIRMED) null else state.page,
                )
            },
        ) { captured, update ->
            val key = captured.session to captured.target!!
            try {
                val saved = repository.addComment(captured.target, captured.draft)
                uncertainTargets.remove(key)
                update {
                    it.copy(
                        sending = false,
                        sentId = saved.id,
                        draft = if (it.draft == captured.draft) "" else it.draft,
                    )
                }
            } catch (error: CommunityException) {
                if (error.failure != CommunityFailure.UNCONFIRMED) uncertainTargets.remove(key)
                throw error
            } finally {
                sendsInFlight.remove(key)
                if (
                    mutable.value.target == captured.target &&
                        sessionAuthority() == captured.session
                )
                    mutable.value =
                        mutable.value.copy(sending = false, uncertain = key in uncertainTargets)
            }
        }
    }

    fun deleteComment(id: String) {
        if (!mutable.value.canModerate || mutable.value.page?.cached != false) return
        launch(
            "delete:$id",
            before = { it.copy(deleting = it.deleting + id, actionError = null) },
            failure = { state, error ->
                state.copy(deleting = state.deleting - id, actionError = error)
            },
        ) { captured, update ->
            repository.deleteComment(captured.target!!, id)
            update { it.copy(deleting = it.deleting - id) }
        }
    }

    private fun launch(
        key: String,
        before: (CommunityState) -> CommunityState = { it },
        failure: (CommunityState, CommunityFailure) -> CommunityState = { state, _ -> state },
        action: suspend (CommunityState, ((CommunityState) -> CommunityState) -> Unit) -> Unit,
    ) {
        val captured = mutable.value
        if (
            !captured.visible ||
                captured.target == null ||
                captured.session != sessionAuthority() ||
                jobs[key]?.isActive == true
        )
            return
        val generation = epoch
        mutable.value = before(captured)
        jobs[key] = viewModelScope.launch {
            try {
                action(captured) { transform ->
                    if (current(captured, generation)) mutable.value = transform(mutable.value)
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (current(captured, generation))
                    mutable.value = failure(mutable.value, communityFailure(error))
            }
        }
    }
}
