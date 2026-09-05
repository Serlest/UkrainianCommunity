package at.uac.android.feature.contentlifecycle

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import at.uac.android.feature.organization.OrganizationMutationGate
import at.uac.android.feature.organization.OrganizationSession
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class ContentLifecycleState(
    val session: OrganizationSession? = null,
    val target: ContentLifecycleTarget? = null,
    val visible: Boolean = false,
    val snapshot: ContentLifecycleSnapshot? = null,
    val fresh: Boolean = false,
    val loading: Boolean = false,
    val busy: Boolean = false,
    val confirmation: ContentLifecycleIntent? = null,
    val uncertain: ContentLifecycleIntent? = null,
    val confirmed: ContentLifecycleConfirmation? = null,
    val observed: ContentLifecycleObserved? = null,
    val error: ContentLifecycleFailure? = null,
) {
    val actionable
        get() =
            visible &&
                session?.ready == true &&
                fresh &&
                !loading &&
                !busy &&
                uncertain == null &&
                confirmed == null &&
                snapshot?.let { ContentLifecycleContract.actionable(it, session) } == true
}

class ContentLifecycleViewModel(
    source: ContentLifecycleSource,
    private val currentSession: () -> OrganizationSession?,
    gate: OrganizationMutationGate,
) : ViewModel() {
    private val repository = ContentLifecycleRepository(source, currentSession, gate)
    private val mutable = MutableStateFlow(ContentLifecycleState(session = currentSession()))
    val state = mutable.asStateFlow()
    private var epoch = 0L
    private var ticket = 0L
    private var sessions: Job? = null
    private var read: Job? = null
    private var watch: Job? = null
    private var watchKey: String? = null
    private var refreshPending = false
    private var inFlight: ContentLifecycleIntent? = null
    private val unresolved = linkedMapOf<ContentLifecycleTarget, ContentLifecycleIntent>()

    private fun same(session: OrganizationSession?, version: Long) =
        epoch == version && currentSession() == session && mutable.value.session == session

    private fun sameRead(session: OrganizationSession?, version: Long, token: Long) =
        same(session, version) && ticket == token

    private fun stopRead() {
        ticket++
        read?.cancel()
        read = null
    }

    private fun stopWatch() {
        watch?.cancel()
        watch = null
        watchKey = null
    }

    private fun reset(
        session: OrganizationSession?,
        target: ContentLifecycleTarget?,
        visible: Boolean,
    ) {
        val old = mutable.value
        val sameAccount = session != null && old.session?.uid == session.uid
        val sameOwner = sameAccount && old.target == target
        if (!sameAccount) unresolved.clear()
        else
            (old.uncertain ?: inFlight.takeIf { old.busy })?.let {
                unresolved[it.snapshot.target] = it
            }
        epoch++
        stopRead()
        stopWatch()
        refreshPending = false
        // A new revision never retains write permission. The same account retains only its
        // unresolved receipt intent.
        mutable.value =
            ContentLifecycleState(
                session,
                target,
                visible,
                uncertain = target?.let(unresolved::get),
                confirmed = old.confirmed.takeIf { sameOwner },
            )
    }

    fun observeSessions(flow: Flow<OrganizationSession?>) {
        sessions?.cancel()
        sessions = viewModelScope.launch {
            flow.collect { session ->
                if (session != mutable.value.session) {
                    reset(session, mutable.value.target, mutable.value.visible)
                    refresh()
                }
            }
        }
    }

    fun show(target: ContentLifecycleTarget) {
        if (mutable.value.target != target || mutable.value.session != currentSession())
            reset(currentSession(), target, true)
        else if (mutable.value.visible) return
        else mutable.value = mutable.value.copy(visible = true)
        refresh()
    }

    fun hide() {
        stopRead()
        stopWatch()
        refreshPending = false
        mutable.value =
            mutable.value.copy(visible = false, fresh = false, loading = false, confirmation = null)
    }

    private fun watch(snapshot: ContentLifecycleSnapshot, session: OrganizationSession) {
        val key = snapshot.item?.status?.wire ?: "absent"
        if (watch?.isActive == true && watchKey == key) return
        stopWatch()
        watchKey = key
        val version = epoch
        watch = viewModelScope.launch {
            try {
                repository.changes(snapshot, session).collect { result ->
                    if (same(session, version)) {
                        mutable.value = mutable.value.copy(fresh = false, confirmation = null)
                        if (result.isFailure) {
                            stopRead()
                            stopWatch()
                            refreshPending = false
                            mutable.value =
                                mutable.value.copy(
                                    loading = false,
                                    error =
                                        result.exceptionOrNull()?.let(::contentLifecycleFailure)
                                            ?: ContentLifecycleFailure.UNKNOWN,
                                )
                        } else if (read?.isActive == true || mutable.value.busy)
                            refreshPending = true
                        else load(clearError = false)
                    }
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (same(session, version)) {
                    stopRead()
                    stopWatch()
                    refreshPending = false
                    mutable.value =
                        mutable.value.copy(
                            fresh = false,
                            loading = false,
                            confirmation = null,
                            error = contentLifecycleFailure(error),
                        )
                }
            }
        }
    }

    fun refresh() = load(clearError = true)

    private fun load(clearError: Boolean) {
        val value = mutable.value
        val session = value.session ?: return
        val target = value.target ?: return
        if (
            !value.visible ||
                !session.ready ||
                session != currentSession() ||
                value.busy ||
                read?.isActive == true
        )
            return
        val version = epoch
        val token = ++ticket
        mutable.value =
            value.copy(
                loading = true,
                fresh = false,
                confirmation = null,
                error = if (clearError) null else value.error,
            )
        read = viewModelScope.launch {
            try {
                val snapshot = repository.load(target)
                if (sameRead(session, version, token)) {
                    mutable.value =
                        mutable.value.copy(snapshot = snapshot, fresh = true, loading = false)
                    watch(snapshot, session)
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (sameRead(session, version, token)) {
                    stopWatch()
                    val reason = contentLifecycleFailure(error)
                    mutable.value =
                        mutable.value.copy(
                            fresh = false,
                            loading = false,
                            error = reason,
                            snapshot =
                                mutable.value.snapshot.takeUnless {
                                    reason in
                                        setOf(
                                            ContentLifecycleFailure.DENIED,
                                            ContentLifecycleFailure.NOT_READY,
                                            ContentLifecycleFailure.MISSING,
                                        )
                                },
                        )
                }
            } finally {
                if (sameRead(session, version, token)) {
                    read = null
                    if (refreshPending && mutable.value.visible && !mutable.value.busy) {
                        refreshPending = false
                        load(clearError = false)
                    }
                }
            }
        }
    }

    fun request() {
        val value = mutable.value
        if (!value.actionable || value.session != currentSession()) return
        if (unresolved.size >= 16) {
            mutable.value = value.copy(error = ContentLifecycleFailure.UNCONFIRMED)
            return
        }
        mutable.value =
            value.copy(
                confirmation = ContentLifecycleIntent(requireNotNull(value.snapshot)),
                error = null,
            )
    }

    fun dismiss() {
        if (!mutable.value.busy) mutable.value = mutable.value.copy(confirmation = null)
    }

    fun confirm() {
        val value = mutable.value
        val session = value.session ?: return
        val intent = value.confirmation ?: return
        if (!value.actionable || session != currentSession() || value.snapshot != intent.snapshot)
            return
        val version = epoch
        inFlight = intent
        stopRead()
        mutable.value = value.copy(busy = true, confirmation = null, error = null, observed = null)
        viewModelScope.launch {
            try {
                val result = repository.execute(intent)
                if (same(session, version)) {
                    unresolved.remove(intent.snapshot.target)
                    mutable.value =
                        mutable.value.copy(
                            snapshot = result.snapshot,
                            confirmed = result,
                            uncertain = null,
                            busy = false,
                            fresh = false,
                        )
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (same(session, version)) {
                    val failure = contentLifecycleFailure(error)
                    if (
                        failure in
                            setOf(
                                ContentLifecycleFailure.UNCONFIRMED,
                                ContentLifecycleFailure.UNKNOWN,
                            )
                    )
                        unresolved[intent.snapshot.target] = intent
                    mutable.value =
                        mutable.value.copy(
                            busy = false,
                            fresh = false,
                            error = failure,
                            uncertain =
                                intent.takeIf {
                                    failure in
                                        setOf(
                                            ContentLifecycleFailure.UNCONFIRMED,
                                            ContentLifecycleFailure.UNKNOWN,
                                        )
                                },
                        )
                }
            } finally {
                if (inFlight === intent) inFlight = null
                if (same(session, version)) {
                    mutable.value = mutable.value.copy(busy = false)
                    refreshPending = false
                    load(clearError = false)
                }
            }
        }
    }

    fun recover() {
        val value = mutable.value
        val intent = value.uncertain ?: return
        val session = value.session ?: return
        if (
            !value.visible ||
                !session.ready ||
                session != currentSession() ||
                value.busy ||
                value.loading
        )
            return
        val version = epoch
        val token = ++ticket
        mutable.value = value.copy(loading = true, fresh = false, confirmation = null, error = null)
        read = viewModelScope.launch {
            try {
                val result = repository.recover(intent)
                if (sameRead(session, version, token)) {
                    mutable.value =
                        mutable.value.copy(
                            snapshot = result.snapshot,
                            fresh = true,
                            loading = false,
                            observed = result.observed,
                        )
                    watch(result.snapshot, session)
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (sameRead(session, version, token)) {
                    stopWatch()
                    mutable.value =
                        mutable.value.copy(
                            loading = false,
                            fresh = false,
                            error = contentLifecycleFailure(error),
                        )
                }
            } finally {
                if (sameRead(session, version, token)) {
                    read = null
                    refreshPending = false
                }
            }
        }
    }

    override fun onCleared() {
        sessions?.cancel()
        stopRead()
        stopWatch()
    }
}
