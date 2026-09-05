package at.uac.android.feature.usermanagement

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import at.uac.android.feature.moderation.ModerationSession
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class ManagedUsersPresentation internal constructor() {
    internal var revoked = false
}

data class ManagedUsersState(
    val session: ModerationSession? = null,
    val visible: Boolean = false,
    val loading: Boolean = false,
    val error: ManagedUsersFailure? = null,
    val users: List<ManagedUser> = emptyList(),
    val next: ManagedUsersCursor? = null,
    val consumed: Int = 0,
    val capped: Boolean = false,
    val query: String = "",
    val filter: ManagedUsersFilter = ManagedUsersFilter.ALL,
    val totalMatches: Int? = null,
    val unavailable: Int = 0,
    val selectedId: String? = null,
    val detail: ManagedUser? = null,
    val security: ManagedUserSecurity? = null,
    val securityError: ManagedUsersFailure? = null,
) {
    override fun toString() =
        "ManagedUsersState([redacted], visible=$visible, loading=$loading, error=$error)"
}

/** All private data, query, target, and SDK cursors are memory-only; no SavedStateHandle. */
class ManagedUsersViewModel(
    private val repository: ManagedUsersRepository,
    private val authority: () -> ModerationSession? = repository::currentSession,
    suppliedScope: CoroutineScope? = null,
) : ViewModel() {
    private val scope = suppliedScope ?: viewModelScope
    private val mutable = MutableStateFlow(ManagedUsersState())
    val state = mutable.asStateFlow()
    private var observer: Job? = null
    private var read: Job? = null
    private var watch: Job? = null
    private var debounce: Job? = null
    private var generation = 0L
    private var presentation: ManagedUsersPresentation? = null
    private var presentationAllowed: () -> Boolean = { false }
    private var dirty = false

    fun currentSession() = authority()

    fun observeSessions(values: Flow<ModerationSession?>) {
        observer?.cancel()
        observer =
            scope.launch(Dispatchers.Main.immediate, start = CoroutineStart.UNDISPATCHED) {
                values.collect(::bind)
            }
    }

    fun bind(session: ModerationSession?) {
        if (mutable.value.session == session) return
        stop()
        presentation = null
        presentationAllowed = { false }
        mutable.value = ManagedUsersState(session = session)
    }

    fun present(allowed: () -> Boolean = { true }): ManagedUsersPresentation {
        bind(authority())
        stop()
        val owned = ManagedUsersPresentation()
        presentation = owned
        presentationAllowed = allowed
        mutable.value = ManagedUsersState(session = authority(), visible = true)
        if (owns(owned)) {
            startWatch()
            refresh()
        }
        return owned
    }

    fun owns(value: ManagedUsersPresentation?): Boolean {
        if (value == null || value !== presentation || value.revoked) return false
        if (
            !mutable.value.visible || mutable.value.session != authority() || !presentationAllowed()
        ) {
            // A sampled loss of privacy/foreground authority permanently consumes this lease.
            // A later true predicate cannot resurrect its retained private data.
            value.revoked = true
            stop()
            presentationAllowed = { false }
            mutable.value = ManagedUsersState(session = authority())
            return false
        }
        return true
    }

    fun snapshot(current: ModerationSession?, owned: ManagedUsersPresentation?): ManagedUsersState {
        val retained = owns(owned)
        return if (current == authority() && mutable.value.session == current && retained)
            mutable.value
        else ManagedUsersState(session = current)
    }

    fun dismiss(owned: ManagedUsersPresentation) {
        if (presentation !== owned) return
        stop()
        presentation = null
        presentationAllowed = { false }
        mutable.value = ManagedUsersState(session = authority())
    }

    private fun stop() {
        generation++
        read?.cancel()
        read = null
        watch?.cancel()
        watch = null
        debounce?.cancel()
        debounce = null
        dirty = false
    }

    private fun usable(): Boolean = owns(presentation) && mutable.value.session?.allowed == true

    private fun current(session: ModerationSession, version: Long) =
        usable() &&
            authority() == session &&
            mutable.value.session == session &&
            generation == version

    fun search(value: String) {
        if (!usable() || mutable.value.selectedId != null) return
        debounce?.cancel()
        read?.cancel()
        read = null
        generation++
        mutable.value =
            mutable.value.copy(
                query = value.take(ManagedUsersContract.MAX_QUERY_INPUT),
                users = emptyList(),
                next = null,
                consumed = 0,
                totalMatches = null,
                unavailable = 0,
                capped = false,
                loading = false,
                error = null,
            )
        val session = mutable.value.session!!
        val version = generation
        debounce = scope.launch {
            delay(350)
            if (current(session, version)) refresh()
        }
    }

    fun filter(value: ManagedUsersFilter) {
        if (usable()) mutable.value = mutable.value.copy(filter = value)
    }

    fun open(targetId: String) {
        if (!usable() || mutable.value.loading || mutable.value.users.none { it.id == targetId })
            return
        read?.cancel()
        read = null
        debounce?.cancel()
        debounce = null
        generation++
        mutable.value =
            mutable.value.copy(
                selectedId = targetId,
                detail = null,
                security = null,
                securityError = null,
                error = null,
            )
        startWatch()
        refresh()
    }

    fun closeTarget() {
        if (!usable()) return
        read?.cancel()
        read = null
        generation++
        mutable.value =
            mutable.value.copy(
                selectedId = null,
                detail = null,
                security = null,
                securityError = null,
            )
        startWatch()
        refresh()
    }

    fun refresh(more: Boolean = false) {
        val previous = mutable.value
        if (!owns(presentation)) return
        if (previous.session?.allowed != true) {
            mutable.value =
                previous.copy(
                    error =
                        when {
                            previous.session == null -> ManagedUsersFailure.SIGN_IN
                            !previous.session.ready -> ManagedUsersFailure.NOT_READY
                            else -> ManagedUsersFailure.DENIED
                        }
                )
            return
        }
        if (
            more &&
                (previous.loading ||
                    previous.next == null ||
                    previous.query.isNotBlank() ||
                    previous.selectedId != null)
        )
            return
        debounce?.cancel()
        debounce = null
        if (read?.isActive == true) {
            // Coalesce metadata bursts into a bounded follow-up, never publish the dirty response.
            dirty = true
            mutable.value =
                previous.copy(users = emptyList(), detail = null, security = null, loading = true)
            return
        }
        val session = previous.session ?: return
        val version = ++generation
        val selected = previous.selectedId
        val query = previous.query
        val prefix = previous.users.takeIf { more }.orEmpty()
        val cursor = previous.next.takeIf { more }
        dirty = false
        mutable.value =
            previous.copy(
                users = emptyList(),
                detail = null,
                security = null,
                securityError = null,
                error = null,
                loading = true,
            )
        read = scope.launch {
            try {
                var repeat = 0
                while (true) {
                    dirty = false
                    val result =
                        if (selected != null) {
                            val user =
                                repository.user(session, selected)
                                    ?: ManagedUsersContract.fail(ManagedUsersFailure.MISSING)
                            var securityError: ManagedUsersFailure? = null
                            val security =
                                try {
                                    repository.security(session, selected)
                                } catch (error: CancellationException) {
                                    throw error
                                } catch (error: Exception) {
                                    val failure = managedUsersFailure(error)
                                    if (
                                        failure !in
                                            setOf(
                                                ManagedUsersFailure.MISSING,
                                                ManagedUsersFailure.INVALID,
                                            )
                                    )
                                        throw error
                                    securityError = failure
                                    null
                                }
                            mutable.value.copy(
                                detail = user,
                                security = security,
                                securityError = securityError,
                            )
                        } else if (query.isBlank()) {
                            val page = repository.page(session, if (repeat == 0) cursor else null)
                            val users =
                                ((if (repeat == 0) prefix else emptyList()) + page.users)
                                    .distinctBy { it.id }
                            mutable.value.copy(
                                users = users,
                                next = page.next,
                                consumed = page.consumed,
                                capped = page.capped,
                                totalMatches = null,
                                unavailable = 0,
                            )
                        } else {
                            val search = repository.search(session, ManagedUsersQuery.from(query))
                            mutable.value.copy(
                                users = search.users,
                                next = null,
                                consumed = 0,
                                capped = false,
                                totalMatches = search.totalMatches,
                                unavailable = search.unavailable,
                            )
                        }
                    if (!current(session, version)) return@launch
                    if (dirty) {
                        if (++repeat > 2) ManagedUsersContract.fail(ManagedUsersFailure.STALE)
                        continue
                    }
                    mutable.value = result.copy(loading = false, error = null)
                    if (watch?.isActive != true) startWatch()
                    break
                }
            } catch (error: CancellationException) {
                // A caller can still be alive when an independent authority check rejects a stale
                // read.
                if (generation == version) dirty = false
                if (current(session, version))
                    mutable.value =
                        mutable.value.copy(loading = false, error = ManagedUsersFailure.STALE)
            } catch (error: Exception) {
                if (generation == version) dirty = false
                if (current(session, version))
                    mutable.value =
                        mutable.value.copy(
                            users = emptyList(),
                            next = null,
                            detail = null,
                            security = null,
                            loading = false,
                            error = managedUsersFailure(error),
                        )
            } finally {
                if (generation == version) {
                    read = null
                    if (dirty && current(session, version)) {
                        dirty = false
                        refresh()
                    }
                }
            }
        }
    }

    private fun startWatch() {
        watch?.cancel()
        watch = null
        val session = mutable.value.session?.takeIf { it.allowed } ?: return
        if (!usable()) return
        val owned = presentation
        val selected = mutable.value.selectedId
        watch = scope.launch {
            try {
                repository.invalidations(session, selected).collect {
                    if (owns(owned) && mutable.value.selectedId == selected) {
                        mutable.value =
                            mutable.value.copy(users = emptyList(), detail = null, security = null)
                        refresh()
                    }
                }
            } catch (error: CancellationException) {
                /* detached lease */
            } catch (error: Exception) {
                if (owns(owned) && mutable.value.selectedId == selected) {
                    read?.cancel()
                    read = null
                    generation++
                    mutable.value =
                        mutable.value.copy(
                            users = emptyList(),
                            next = null,
                            detail = null,
                            security = null,
                            loading = false,
                            error = managedUsersFailure(error),
                        )
                }
            }
        }
    }

    override fun onCleared() {
        stop()
        observer?.cancel()
    }
}
