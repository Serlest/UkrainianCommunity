package at.uac.android.feature.registrations

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import at.uac.android.feature.personal.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

class RegistrationsViewModel(
    source: RegistrationsSource,
    private val authority: () -> PersonalSession?,
    workScope: CoroutineScope? = null,
) : ViewModel() {
    private val scope = workScope ?: viewModelScope
    private val repository = RegistrationsRepository(source, authority)
    private val mutable = MutableStateFlow(RegistrationsState())
    val state = mutable.asStateFlow()
    private var load: Job? = null
    private var generation = 0L

    fun observeSessions(sessions: Flow<PersonalSession?>) =
        scope.launch(Dispatchers.Main.immediate, start = CoroutineStart.UNDISPATCHED) {
            sessions.collect(::bind)
        }

    fun bind(session: PersonalSession?) {
        if (state.value.session == session) return
        generation++
        load?.cancel()
        load = null
        mutable.value = RegistrationsState(session = session)
    }

    fun segment(value: RegistrationSegment) {
        if (state.value.session == authority()) mutable.value = state.value.copy(segment = value)
    }

    fun refresh(more: Boolean = false): Job? {
        if (state.value.session != authority()) {
            bind(authority())
            return null
        }
        val captured = state.value.session ?: return null
        if (!captured.ready || more && (!state.value.hasMore || state.value.loading)) return null
        load?.cancel()
        val request = ++generation
        val previous = state.value
        mutable.value = previous.copy(loading = true, error = null)
        return scope
            .launch {
                fun current() =
                    request == generation &&
                        authority() == captured &&
                        state.value.session == captured
                try {
                    val page = repository.load(if (more) previous.next else null)
                    if (current())
                        mutable.value =
                            state.value.copy(
                                items =
                                    ((if (more) previous.items else emptyList()) + page.items)
                                        .distinctBy { it.id },
                                loaded = true,
                                loading = false,
                                next = page.next,
                                hasMore = page.hasMore,
                                unavailable =
                                    (if (more) previous.unavailable else 0) + page.unavailable,
                                error = null,
                            )
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Exception) {
                    if (current()) {
                        val failure =
                            (error as? PersonalException)?.reason ?: PersonalFailure.UNKNOWN
                        mutable.value =
                            if (failure == PersonalFailure.OFFLINE)
                                state.value.copy(loading = false, error = failure)
                            else
                                RegistrationsState(
                                    session = captured,
                                    error = failure,
                                    segment = state.value.segment,
                                )
                    }
                } finally {
                    if (current()) {
                        mutable.value = state.value.copy(loading = false)
                        load = null
                    }
                }
            }
            .also { load = it }
    }
}
