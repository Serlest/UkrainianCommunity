package at.uac.android.feature.inbox

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class InboxState(
    val session: InboxSession? = null,
    val items: List<InboxNotice> = emptyList(),
    val cursor: InboxCursor? = null,
    val hasMore: Boolean = false,
    val unreadCount: Long = 0,
    val unreadOnly: Boolean = false,
    val loading: Boolean = false,
    val mutating: Boolean = false,
    val error: InboxFailure? = null,
    val preferences: InboxPreferences? = null,
    val preferencesSaved: Boolean = false,
    val partialSweep: Boolean = false,
    val invalidRows: Int = 0,
) {
    val visibleItems: List<InboxNotice>
        get() = items.filter { !unreadOnly || it.unread }

    fun forSession(authority: InboxSession?): InboxState =
        if (session == authority) this else InboxState(session = authority)
}

class InboxViewModel(
    source: InboxSource,
    private val authority: () -> InboxSession?,
    mutations: InboxMutationGate,
    workScope: CoroutineScope? = null,
    private val onPreferencesConfirmed: (InboxSession, InboxPreferences) -> Unit = { _, _ -> },
) : ViewModel() {
    private val scope = workScope ?: viewModelScope
    private val mutable = MutableStateFlow(InboxState())
    val state = mutable.asStateFlow()
    private val repository = InboxRepository(source, authority, mutations)
    private var watch: Job? = null
    private var load: Job? = null
    private var mutation: Job? = null
    private var preferenceLoad: Job? = null
    private var loadRevision = 0L

    fun observeSessions(sessions: Flow<InboxSession?>): Job =
        scope.launch(Dispatchers.Main.immediate, start = CoroutineStart.UNDISPATCHED) {
            sessions.collect(::bind)
        }

    fun bind(session: InboxSession?) {
        if (mutable.value.session == session) return
        watch?.cancel()
        load?.cancel()
        mutation?.cancel()
        preferenceLoad?.cancel()
        loadRevision++
        mutable.value = InboxState(session = session)
        if (session == null) return
        refresh()
        watch = scope.launch {
            try {
                if (current(session))
                    repository.changes().collect {
                        if (current(session) && !state.value.mutating) refresh()
                    }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                fail(session, error)
            }
        }
    }

    private fun current(session: InboxSession): Boolean =
        authority() == session && state.value.session == session

    private fun fail(session: InboxSession, error: Exception) {
        if (!current(session)) return
        val reason = (error as? InboxException)?.reason ?: InboxFailure.UNKNOWN
        mutable.value =
            if (reason == InboxFailure.DENIED || reason == InboxFailure.SIGN_IN)
                InboxState(session = session, error = reason)
            else state.value.copy(error = reason)
    }

    fun filterUnread(value: Boolean) {
        mutable.value = state.value.copy(unreadOnly = value)
    }

    fun refresh(more: Boolean = false): Job? {
        val session = state.value.session ?: return null
        if (!current(session) || more && (!state.value.hasMore || state.value.loading)) return null
        val after = if (more) state.value.cursor else null
        val revision = ++loadRevision
        load?.cancel()
        mutable.value = state.value.copy(loading = true, error = null)
        return scope
            .launch {
                try {
                    val page = repository.page(after)
                    if (!current(session)) return@launch
                    mutable.value =
                        state.value.copy(
                            items =
                                (if (more) state.value.items + page.items else page.items)
                                    .distinctBy { it.id },
                            cursor = page.next,
                            hasMore = page.hasMore,
                            invalidRows = (if (more) state.value.invalidRows else 0) + page.invalid,
                        )
                    val count = repository.unreadCount()
                    if (current(session)) mutable.value = state.value.copy(unreadCount = count)
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Exception) {
                    fail(session, error)
                } finally {
                    if (current(session) && revision == loadRevision)
                        mutable.value = state.value.copy(loading = false)
                }
            }
            .also { load = it }
    }

    fun loadPreferences(): Job? {
        val session = state.value.session ?: return null
        if (!current(session) || preferenceLoad?.isActive == true) return null
        return scope
            .launch {
                try {
                    val preferences = repository.preferences()
                    if (current(session))
                        mutable.value = state.value.copy(preferences = preferences, error = null)
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Exception) {
                    fail(session, error)
                }
            }
            .also { preferenceLoad = it }
    }

    fun savePreferences(preferences: InboxPreferences): Job? = mutate {
        val confirmed = repository.savePreferences(preferences)
        mutable.value = state.value.copy(preferences = confirmed, preferencesSaved = true)
        state.value.session?.takeIf(::current)?.let { session ->
            runCatching { onPreferencesConfirmed(session, confirmed) }
        }
    }

    fun change(notice: InboxNotice, action: InboxMutation): Job? = mutate {
        repository.mutate(notice, action)
        refresh()?.join()
    }

    fun changeAll(action: InboxMutation): Job? = mutate {
        val result = repository.mutateAll(action)
        mutable.value = state.value.copy(partialSweep = !result.complete)
        refresh()?.join()
    }

    private fun mutate(operation: suspend () -> Unit): Job? {
        val session = state.value.session ?: return null
        if (!current(session) || state.value.mutating) return null
        mutable.value =
            state.value.copy(
                mutating = true,
                error = null,
                preferencesSaved = false,
                partialSweep = false,
            )
        return scope
            .launch {
                try {
                    operation()
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Exception) {
                    fail(session, error)
                } finally {
                    if (current(session)) mutable.value = state.value.copy(mutating = false)
                }
            }
            .also { mutation = it }
    }
}
