package at.uac.android.feature.subscribers

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import at.uac.android.feature.browse.Content
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class SubscribersState(
    val session: SubscriberSession? = null,
    val organizationId: String? = null,
    val visible: Boolean = false,
    val loading: Boolean = false,
    val page: SubscribersSnapshot? = null,
    val error: SubscribersFailure? = null,
    val search: String = "",
) {
    fun forSession(current: SubscriberSession?, target: String?) =
        if (session == current && organizationId == target) this
        else SubscribersState(session = current, organizationId = target)

    override fun toString() =
        "SubscribersState([redacted], visible=$visible, loading=$loading, error=$error)"
}

/** The host's live policy masks retained rows synchronously, before any reload effect can run. */
fun SubscribersState.visiblePage(
    organization: (Content) -> Boolean,
    author: (String?) -> Boolean,
): SubscribersSnapshot? =
    page
        ?.takeIf {
            visible &&
                !loading &&
                error == null &&
                session?.ready == true &&
                it.session == session &&
                it.organization.id == organizationId &&
                organization(it.organization.content)
        }
        ?.let { it.copy(members = it.members.filter { person -> author(person.userId) }) }

class SubscribersViewModel(
    private val source: SubscribersSource,
    private val authority: () -> SubscriberSession?,
    private val visibleOrganization: (Content) -> Boolean,
    private val visibleAuthor: (String?) -> Boolean,
) : ViewModel() {
    private val repository =
        SubscribersRepository(source, authority, visibleOrganization, visibleAuthor)
    private val mutable = MutableStateFlow(SubscribersState())
    val state = mutable.asStateFlow()
    private var observer: Job? = null
    private var read: Job? = null
    private var watch: Job? = null
    private var watchTarget: Pair<String, SubscriberSession>? = null
    private var generation = 0L
    private var requestedWindow = SubscribersContract.PAGE_SIZE
    private var refreshPending = false

    fun observeSessions(values: Flow<SubscriberSession?>) {
        observer?.cancel()
        observer =
            viewModelScope.launch(Dispatchers.Main.immediate, start = CoroutineStart.UNDISPATCHED) {
                values.collect(::bind)
            }
    }

    fun bind(session: SubscriberSession?) {
        if (mutable.value.session == session) return
        stop()
        mutable.value = SubscribersState(session = session)
    }

    fun show(id: String) {
        if (mutable.value.session != authority()) bind(authority())
        if (mutable.value.visible && mutable.value.organizationId == id) return
        stop()
        requestedWindow = SubscribersContract.PAGE_SIZE
        mutable.value = SubscribersState(session = authority(), organizationId = id, visible = true)
        refresh()
    }

    fun hide() {
        stop()
        requestedWindow = SubscribersContract.PAGE_SIZE
        mutable.value = SubscribersState(session = authority())
    }

    private fun stop() {
        generation++
        read?.cancel()
        watch?.cancel()
        read = null
        watch = null
        watchTarget = null
        refreshPending = false
    }

    private fun current(session: SubscriberSession, id: String, version: Long) =
        authority() == session &&
            mutable.value.session == session &&
            mutable.value.organizationId == id &&
            mutable.value.visible &&
            generation == version

    private fun unavailable(failure: SubscribersFailure) {
        stop()
        mutable.value = mutable.value.copy(page = null, loading = false, error = failure)
    }

    fun search(value: String) {
        if (mutable.value.session == authority())
            mutable.value = mutable.value.copy(search = value.take(160))
    }

    fun visibilityChanged() {
        if (mutable.value.visible) refresh(keepWindow = true)
    }

    fun refresh(more: Boolean = false, keepWindow: Boolean = false) {
        val state = mutable.value
        if (!state.visible) return
        val session = state.session
        if (session == null || !session.ready) {
            unavailable(
                if (session == null) SubscribersFailure.SIGN_IN else SubscribersFailure.NOT_READY
            )
            return
        }
        val id = state.organizationId ?: return
        if (authority() != session || more && (state.loading || state.page?.next == null)) return
        val previous = state.page.takeIf { more }
        requestedWindow =
            when {
                more ->
                    ((previous?.references?.size ?: 0) + SubscribersContract.PAGE_SIZE)
                        .coerceAtMost(SubscribersContract.MAX_SUBSCRIBERS)
                keepWindow -> requestedWindow
                else -> SubscribersContract.PAGE_SIZE
            }
        val desired = requestedWindow
        // Initial organization/query snapshots often arrive together. Never cancel and restart
        // an in-flight protected join for each metadata signal; one dirty bit coalesces the burst.
        if (read?.isActive == true) {
            refreshPending = true
            mutable.value = state.copy(loading = true, page = null, error = null)
            return
        }
        val version = ++generation
        refreshPending = false
        mutable.value = state.copy(loading = true, page = null, error = null)
        read = viewModelScope.launch {
            try {
                var rechecks = 0
                var append = previous
                while (true) {
                    refreshPending = false
                    var page = repository.load(id, append)
                    while (page.references.size < desired && page.next != null) page =
                        repository.load(id, page)
                    if (!current(session, id, version)) return@launch
                    if (refreshPending) {
                        // Continuous changes must not spin indefinitely or expose an unsettled
                        // page.
                        if (++rechecks > 2) throw SubscribersException(SubscribersFailure.STALE)
                        append = null
                        continue
                    }
                    mutable.value = mutable.value.copy(page = page, loading = false)
                    watch(id, session)
                    break
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (current(session, id, version)) unavailable(subscribersFailure(error))
            } finally {
                if (generation == version) read = null
            }
        }
    }

    private fun watch(id: String, session: SubscriberSession) {
        val target = id to session
        if (watch?.isActive == true && watchTarget == target) return
        watch?.cancel()
        watchTarget = target
        watch = viewModelScope.launch {
            try {
                source.changes(id, session).collect { result ->
                    if (
                        authority() == session &&
                            mutable.value.session == session &&
                            mutable.value.visible &&
                            mutable.value.organizationId == id
                    ) {
                        if (result.isSuccess) refresh(keepWindow = true)
                        else unavailable(subscribersFailure(result.exceptionOrNull()!!))
                    }
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (
                    authority() == session &&
                        mutable.value.session == session &&
                        mutable.value.organizationId == id
                )
                    unavailable(subscribersFailure(error))
            }
        }
    }

    override fun onCleared() {
        stop()
        observer?.cancel()
        mutable.value = SubscribersState()
        super.onCleared()
    }
}
