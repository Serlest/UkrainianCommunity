package at.uac.android.feature.personal

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import at.uac.android.feature.browse.Content
import at.uac.android.feature.browse.ContentKind
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class PersonalViewModel(
    source: PersonalSource,
    visibility: (Content) -> Boolean = { true },
    private val sessionAuthority: (() -> PersonalSession?)? = null,
    mutationGate: PersonalMutationGate = DirectPersonalMutationGate,
    private val onConfirmedChange: (PersonalChangeReceipt) -> Unit = {},
) : ViewModel() {
    @Volatile private var session: PersonalSession? = null

    private fun authoritativeSession(): PersonalSession? =
        if (sessionAuthority == null) session else sessionAuthority.invoke()

    private val repository =
        PersonalRepository(source, ::authoritativeSession, visibility, mutationGate)
    private val mutable = MutableStateFlow(PersonalState())
    val state = mutable.asStateFlow()
    private val jobs = mutableMapOf<String, Job>()
    private var sessionObserver: Job? = null

    fun observeSessions(sessions: Flow<PersonalSession?>) {
        sessionObserver?.cancel()
        sessionObserver =
            viewModelScope.launch(Dispatchers.Main.immediate, start = CoroutineStart.UNDISPATCHED) {
                sessions.collect(::bind)
            }
    }

    /** Call synchronously when the auth gate changes, before showing another account's UI. */
    fun bind(value: PersonalSession?) {
        if (value == session) return
        session = value
        jobs.values.toList().forEach(Job::cancel)
        jobs.clear()
        mutable.value = PersonalState(session = value)
    }

    private fun run(key: String, operation: suspend () -> Unit) {
        if (session != authoritativeSession()) {
            bind(authoritativeSession())
            return
        }
        if (jobs[key]?.isActive == true) return
        val captured = session
        jobs[key] = viewModelScope.launch {
            try {
                operation()
            } finally {
                if (session == captured && jobs[key] === currentCoroutineContext()[Job])
                    jobs.remove(key)
            }
        }
    }

    /**
     * Block-state changes invalidate only read jobs; a submitted write must still finish safely.
     */
    fun visibilityChanged() {
        if (session != authoritativeSession()) {
            bind(authoritativeSession())
            return
        }
        val reloadSaved = mutable.value.savedLoading || mutable.value.saved.isNotEmpty()
        val reloadSubscriptions =
            mutable.value.subscriptionsLoading || mutable.value.subscriptions != null
        jobs.remove("saved")?.cancel()
        jobs.remove("subscriptions")?.cancel()
        mutable.update {
            it.copy(
                saved = emptyMap(),
                savedLoading = false,
                savedError = null,
                subscriptions = null,
                subscriptionsLoading = false,
                subscriptionsError = null,
            )
        }
        if (session?.ready == true) {
            if (reloadSaved) loadSaved()
            if (reloadSubscriptions) loadSubscriptions()
        }
    }

    private fun reason(error: Exception): PersonalFailure =
        when (error) {
            is PersonalException -> error.reason
            else -> PersonalFailure.UNKNOWN
        }

    fun loadProfile() =
        run("profile") {
            mutable.update {
                it.copy(profileLoading = true, profileError = null, profileSaved = false)
            }
            try {
                val profile = repository.profile()
                mutable.update { it.copy(profile = profile, profileLoading = false) }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                mutable.update {
                    it.copy(profile = null, profileLoading = false, profileError = reason(error))
                }
            }
        }

    fun saveProfile(draft: ProfileDraft) =
        run("profile") {
            mutable.update {
                it.copy(profileSaving = true, profileError = null, profileSaved = false)
            }
            try {
                val profile = repository.saveProfile(draft)
                mutable.update {
                    it.copy(profile = profile, profileSaving = false, profileSaved = true)
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                mutable.update { it.copy(profileSaving = false, profileError = reason(error)) }
            }
        }

    fun loadActions(target: PersonalTarget) =
        run("action:${target.key}") {
            mutable.update {
                it.copy(
                    actionsLoading = it.actionsLoading + target,
                    actionErrors = it.actionErrors - target,
                )
            }
            try {
                val actions = repository.actions(target)
                mutable.update {
                    it.copy(
                        actions = it.actions + (target to actions),
                        actionsLoading = it.actionsLoading - target,
                    )
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                mutable.update {
                    it.copy(
                        actions = it.actions - target,
                        actionsLoading = it.actionsLoading - target,
                        actionErrors = it.actionErrors + (target to reason(error)),
                    )
                }
            }
        }

    fun set(target: PersonalTarget, action: PersonalAction, enabled: Boolean) =
        run("action:${target.key}") {
            mutable.update {
                it.copy(
                    actionsPending = it.actionsPending + target,
                    actionErrors = it.actionErrors - target,
                )
            }
            try {
                val receipt = repository.setConfirmed(target, action, enabled)
                mutable.update {
                    val existing = it.actions[target] ?: PersonalActions()
                    it.copy(
                        actions = it.actions + (target to existing.with(action, receipt.enabled)),
                        actionsPending = it.actionsPending - target,
                    )
                }
                if (action == PersonalAction.BOOKMARK && state.value.saved.isNotEmpty()) loadSaved()
                if (action == PersonalAction.SUBSCRIBE && state.value.subscriptions != null)
                    loadSubscriptions()
                currentCoroutineContext().ensureActive()
                if (
                    receipt.didChange == true &&
                        session == receipt.session &&
                        authoritativeSession() == receipt.session
                ) {
                    // A secondary history failure must not turn an already-confirmed
                    // bookmark/subscription into a failed action.
                    runCatching { onConfirmedChange(receipt) }
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                mutable.update {
                    it.copy(
                        actionsPending = it.actionsPending - target,
                        actionErrors = it.actionErrors + (target to reason(error)),
                    )
                }
            }
        }

    fun loadSaved(more: Boolean = false) =
        run("saved") {
            val previous = if (more) state.value.saved else emptyMap()
            mutable.update { it.copy(savedLoading = true, savedError = null, saved = previous) }
            try {
                val result = coroutineScope {
                    ContentKind.entries
                        .associateWith { kind ->
                            async {
                                val old = previous[kind]
                                if (old != null && !old.hasMore) old
                                else merge(old, repository.saved(kind, old?.next))
                            }
                        }
                        .mapValues { it.value.await() }
                }
                mutable.update { it.copy(saved = result, savedLoading = false) }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                mutable.update {
                    it.copy(
                        saved =
                            if (reason(error) == PersonalFailure.DENIED) emptyMap() else previous,
                        savedLoading = false,
                        savedError = reason(error),
                    )
                }
            }
        }

    fun loadSubscriptions(more: Boolean = false) =
        run("subscriptions") {
            val previous = if (more) state.value.subscriptions else null
            if (previous != null && !previous.hasMore) return@run
            mutable.update {
                it.copy(
                    subscriptionsLoading = true,
                    subscriptionsError = null,
                    subscriptions = previous,
                )
            }
            try {
                val page = merge(previous, repository.subscriptions(previous?.next))
                mutable.update { it.copy(subscriptions = page, subscriptionsLoading = false) }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                mutable.update {
                    it.copy(
                        subscriptions =
                            if (reason(error) == PersonalFailure.DENIED) null else previous,
                        subscriptionsLoading = false,
                        subscriptionsError = reason(error),
                    )
                }
            }
        }

    private fun merge(old: PersonalListPage?, fresh: PersonalListPage): PersonalListPage =
        fresh.copy(
            items = (old?.items.orEmpty() + fresh.items).distinctBy { it.id },
            unavailable = (old?.unavailable ?: 0) + fresh.unavailable,
        )
}
