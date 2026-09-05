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

data class AttendeesAccessState(
    val session: AttendeesSession? = null,
    val eventId: String? = null,
    val visible: Boolean = false,
    val checking: Boolean = false,
    val permitted: Boolean = false,
    val error: AttendeesFailure? = null,
) {
    fun forSession(current: AttendeesSession?, target: String) =
        if (session == current && eventId == target) this
        else AttendeesAccessState(session = current, eventId = target)
}

/** The entry-point model deliberately never calls registrations/profiles or their listener. */
class AttendeesAccessViewModel(
    private val source: AttendeesSource,
    private val authority: () -> AttendeesSession?,
) : ViewModel() {
    private val repository = AttendeesRepository(source, authority)
    private val mutable = MutableStateFlow(AttendeesAccessState())
    val state = mutable.asStateFlow()
    private var observer: Job? = null
    private var read: Job? = null
    private var watch: Job? = null
    private var watched: Pair<String, String?>? = null
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
        mutable.value = AttendeesAccessState(session = session)
    }

    fun show(id: String) {
        if (mutable.value.session != authority()) bind(authority())
        if (mutable.value.visible && mutable.value.eventId == id) return
        stop()
        mutable.value = AttendeesAccessState(session = authority(), eventId = id, visible = true)
        refresh()
    }

    fun hide() {
        stop()
        mutable.value = AttendeesAccessState(session = authority())
    }

    private fun stop() {
        generation++
        read?.cancel()
        watch?.cancel()
        read = null
        watch = null
        watched = null
    }

    private fun unavailable(failure: AttendeesFailure) {
        stop()
        mutable.value = mutable.value.copy(checking = false, permitted = false, error = failure)
    }

    fun canOpen(id: String, session: AttendeesSession?) =
        session?.ready == true &&
            authority() == session &&
            mutable.value.let {
                it.session == session &&
                    it.eventId == id &&
                    it.visible &&
                    it.permitted &&
                    !it.checking
            }

    fun refresh() {
        val previous = mutable.value
        val id = previous.eventId ?: return
        if (!previous.visible || previous.session != authority()) return
        val session = previous.session
        if (session?.ready != true) {
            mutable.value =
                previous.copy(
                    permitted = false,
                    checking = false,
                    error =
                        if (session == null) AttendeesFailure.SIGN_IN
                        else AttendeesFailure.NOT_READY,
                )
            return
        }
        read?.cancel()
        val version = ++generation
        mutable.value = previous.copy(checking = true, permitted = false, error = null)
        read = viewModelScope.launch {
            fun current() =
                version == generation &&
                    authority() == session &&
                    mutable.value.session == session &&
                    mutable.value.eventId == id &&
                    mutable.value.visible
            try {
                val check = repository.inspectAccess(id)
                if (current()) {
                    mutable.value =
                        mutable.value.copy(
                            checking = false,
                            permitted = check.event != null,
                            error = check.failure,
                        )
                    observe(id, check.organizationId, session)
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (current()) unavailable(attendeesFailure(error))
            }
        }
    }

    private fun observe(eventId: String, organizationId: String?, session: AttendeesSession) {
        val target = eventId to organizationId
        if (watch?.isActive == true && watched == target) return
        watch?.cancel()
        watched = target
        watch = viewModelScope.launch {
            fun current() =
                authority() == session &&
                    mutable.value.session == session &&
                    mutable.value.visible &&
                    mutable.value.eventId == eventId
            try {
                source.accessChanges(eventId, organizationId, session).collect { result ->
                    if (current()) {
                        if (result.isSuccess) refresh()
                        else unavailable(attendeesFailure(result.exceptionOrNull()!!))
                    }
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (current()) {
                    unavailable(attendeesFailure(error))
                }
            }
        }
    }

    override fun onCleared() {
        stop()
        observer?.cancel()
        mutable.value = AttendeesAccessState()
        super.onCleared()
    }
}
