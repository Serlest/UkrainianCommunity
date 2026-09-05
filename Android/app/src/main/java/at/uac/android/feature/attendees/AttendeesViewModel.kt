package at.uac.android.feature.attendees

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class AttendeesState(
    val session: AttendeesSession? = null,
    val eventId: String? = null,
    val visible: Boolean = false,
    val loading: Boolean = false,
    val page: AttendeesPage? = null,
    val error: AttendeesFailure? = null,
    val search: String = "",
    val sort: AttendeesSort = AttendeesSort.OLDEST,
) {
    fun forSession(current: AttendeesSession?, target: String?) =
        if (session == current && eventId == target) this
        else AttendeesState(session = current, eventId = target)

    override fun toString() =
        "AttendeesState([redacted], visible=$visible, loading=$loading, error=$error)"
}

class AttendeesViewModel(
    private val source: AttendeesSource,
    private val authority: () -> AttendeesSession?,
) : ViewModel() {
    private val repository = AttendeesRepository(source, authority)
    private val mutable = MutableStateFlow(AttendeesState())
    val state = mutable.asStateFlow()
    private var observer: Job? = null
    private var read: Job? = null
    private var watch: Job? = null
    private var watchTarget: Pair<String, String?>? = null
    private var generation = 0L

    fun observeSessions(values: Flow<AttendeesSession?>) {
        observer?.cancel()
        observer =
            viewModelScope.launch(Dispatchers.Main.immediate, start = CoroutineStart.UNDISPATCHED) {
                values.collect(::bind)
            }
    }

    fun bind(session: AttendeesSession?) {
        if (mutable.value.session == session) return
        stop()
        mutable.value = AttendeesState(session = session)
    }

    fun show(id: String) {
        if (mutable.value.session != authority()) bind(authority())
        if (mutable.value.visible && mutable.value.eventId == id) return
        stop()
        mutable.value = AttendeesState(session = authority(), eventId = id, visible = true)
        refresh()
    }

    fun hide() {
        stop()
        mutable.value = AttendeesState(session = authority())
    }

    private fun stop() {
        generation++
        read?.cancel()
        watch?.cancel()
        read = null
        watch = null
        watchTarget = null
    }

    private fun current(session: AttendeesSession, id: String, version: Long) =
        authority() == session &&
            mutable.value.session == session &&
            mutable.value.eventId == id &&
            mutable.value.visible &&
            generation == version

    private fun unavailable(failure: AttendeesFailure) {
        // Firestore terminates a failed listener. A later explicit retry must install fresh
        // listeners.
        stop()
        mutable.value = mutable.value.copy(page = null, loading = false, error = failure)
    }

    fun search(value: String) {
        if (mutable.value.session == authority())
            mutable.value = mutable.value.copy(search = value.take(160))
    }

    fun sort(value: AttendeesSort) {
        if (mutable.value.session == authority()) mutable.value = mutable.value.copy(sort = value)
    }

    fun refresh(more: Boolean = false) {
        val state = mutable.value
        if (!state.visible) return
        val session = state.session
        if (session == null || !session.ready) {
            mutable.value =
                state.copy(
                    page = null,
                    loading = false,
                    error =
                        if (session == null) AttendeesFailure.SIGN_IN
                        else AttendeesFailure.NOT_READY,
                )
            return
        }
        val id = state.eventId ?: return
        if (authority() != session || more && (state.loading || state.page?.next == null)) return
        val previous = state.page.takeIf { more }
        read?.cancel()
        val version = ++generation
        mutable.value = state.copy(loading = true, page = null, error = null)
        read = viewModelScope.launch {
            try {
                val page = repository.load(id, previous)
                if (current(session, id, version)) {
                    mutable.value = mutable.value.copy(page = page, loading = false)
                    watch(page.event, session)
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (current(session, id, version)) unavailable(attendeesFailure(error))
            }
        }
    }

    private fun watch(event: AttendeesEvent, session: AttendeesSession) {
        val target = event.id to event.organizationId
        if (watch?.isActive == true && watchTarget == target) return
        watch?.cancel()
        watchTarget = target
        watch = viewModelScope.launch {
            try {
                source.changes(event.id, event.organizationId, session).collect { result ->
                    if (
                        authority() == session &&
                            mutable.value.session == session &&
                            mutable.value.visible &&
                            mutable.value.eventId == event.id
                    ) {
                        if (result.isSuccess) refresh()
                        else unavailable(attendeesFailure(result.exceptionOrNull()!!))
                    }
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (authority() == session && mutable.value.eventId == event.id) {
                    unavailable(attendeesFailure(error))
                }
            }
        }
    }

    override fun onCleared() {
        stop()
        observer?.cancel()
        mutable.value = AttendeesState()
        super.onCleared()
    }
}
