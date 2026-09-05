package at.uac.android.feature.organizationreview

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import at.uac.android.feature.moderation.ModerationKind
import at.uac.android.feature.moderation.ModerationPresentation
import at.uac.android.feature.moderation.ModerationSession
import at.uac.android.feature.moderation.ModerationTarget
import java.util.Collections
import java.util.WeakHashMap
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class OrganizationReviewState(
    val session: ModerationSession? = null,
    val snapshot: OrganizationReviewSnapshot? = null,
    val fresh: Boolean = false,
    val loading: Boolean = false,
    val busy: Boolean = false,
    val journalReady: Boolean = false,
    val pending: List<OrganizationReviewPending> = emptyList(),
    val confirmation: OrganizationReviewAction? = null,
    val text: String = "",
    val error: OrganizationReviewFailure? = null,
    val observation: OrganizationReviewObservation? = null,
    val observationTargetId: String? = null,
    val completion: Long = 0,
) {
    val canAct: Boolean
        get() {
            val current = snapshot ?: return false
            return session?.allowed == true &&
                fresh &&
                !loading &&
                !busy &&
                journalReady &&
                pending.none { it.version.organizationId == current.version.organizationId }
        }

    val canConfirm: Boolean
        get() {
            val action = confirmation ?: return false
            val current = snapshot ?: return false
            if (!canAct) return false
            return runCatching {
                OrganizationReviewContract.payload(current.version.organizationId, action, text)
            }
                .isSuccess
        }

    override fun toString() = "OrganizationReviewState(fresh=$fresh, busy=$busy, [redacted])"
}

class OrganizationReviewViewModel(
    private val repository: OrganizationReviewRepository,
    private val authority: () -> ModerationSession? = repository::currentSession,
    private val workScope: CoroutineScope? = null,
) : ViewModel() {
    private val scope
        get() = workScope ?: viewModelScope

    private val mutable = MutableStateFlow(OrganizationReviewState())
    val state: StateFlow<OrganizationReviewState> = mutable.asStateFlow()
    private var observer: Job? = null
    private var watcher: Job? = null
    private var read: Job? = null
    private var operation: Job? = null
    private var generation = 0L
    private var readTicket = 0L
    private var pendingTicket = 0L

    private data class View(
        val session: ModerationSession,
        val target: ModerationTarget,
        val fingerprint: String,
        val token: ModerationPresentation,
    )

    private data class Host(val session: ModerationSession, val token: ModerationPresentation)

    private var view: View? = null
    private var host: Host? = null
    private val revoked = Collections.newSetFromMap(WeakHashMap<ModerationPresentation, Boolean>())
    private var guard: () -> Boolean = { false }
    private var hostGuard: () -> Boolean = { false }

    private fun alive(session: ModerationSession) =
        session == authority() && session == mutable.value.session && session.allowed

    private fun liveHost(): Boolean {
        val captured = host ?: return false
        if (alive(captured.session) && captured.token !in revoked && hostGuard()) return true
        revoked.add(captured.token)
        host = null
        view = null
        readTicket++
        pendingTicket++
        read?.cancel()
        watcher?.cancel()
        watcher = null
        mutable.value =
            mutable.value.copy(
                snapshot = null,
                fresh = false,
                loading = false,
                confirmation = null,
                text = "",
            )
        return false
    }

    private fun owns(captured: View) = liveHost() && view == captured && guard()

    fun snapshot(session: ModerationSession?): OrganizationReviewState {
        if (session == null || !alive(session) || !liveHost()) return OrganizationReviewState()
        if (view != null && !guard()) {
            // A closed/refreshed preview revokes its descriptor, not the still-visible queue host.
            view = null
            readTicket++
            read?.cancel()
            watcher?.cancel()
            watcher = null
            mutable.value =
                mutable.value.copy(
                    snapshot = null,
                    fresh = false,
                    loading = false,
                    confirmation = null,
                    text = "",
                )
        }
        return mutable.value
    }

    fun observeSessions(sessions: Flow<ModerationSession?>) {
        observer?.cancel()
        observer = scope.launch { sessions.collect(::bind) }
    }

    fun bind(session: ModerationSession?) {
        val current = session?.takeIf { it == authority() && it.allowed }
        if (mutable.value.session == current) return
        generation++
        readTicket++
        pendingTicket++
        watcher?.cancel()
        watcher = null
        read?.cancel()
        operation?.cancel()
        host?.let { revoked.add(it.token) }
        host = null
        view = null
        guard = { false }
        hostGuard = { false }
        mutable.value = OrganizationReviewState(session = current)
        refreshPending()
    }

    fun bindView(
        session: ModerationSession?,
        target: ModerationTarget?,
        reviewedFingerprint: String?,
        presentation: ModerationPresentation?,
        hostIsCurrent: (() -> Boolean)? = null,
        canSubmit: () -> Boolean,
    ) {
        bind(session)
        hostGuard = hostIsCurrent ?: canSubmit
        val nextHost =
            if (
                session != null &&
                    alive(session) &&
                    presentation != null &&
                    presentation !in revoked &&
                    hostGuard()
            )
                Host(session, presentation)
            else null
        if (host != null && host != nextHost) host?.let { revoked.add(it.token) }
        host = nextHost
        val next =
            if (
                nextHost != null &&
                    target?.kind == ModerationKind.ORGANIZATION &&
                    reviewedFingerprint != null &&
                    canSubmit()
            )
                View(nextHost.session, target, reviewedFingerprint, nextHost.token)
            else null
        guard = canSubmit
        if (view == next) {
            if (nextHost != null && !mutable.value.journalReady) refreshPending()
            return
        }
        view = next
        mutable.value =
            mutable.value.copy(
                observation = null,
                observationTargetId = null,
                error = mutable.value.error?.takeIf { it == OrganizationReviewFailure.JOURNAL },
            )
        readTicket++
        read?.cancel()
        watcher?.cancel()
        watcher = null
        mutable.value =
            mutable.value.copy(
                snapshot = null,
                fresh = false,
                loading = false,
                confirmation = null,
                text = "",
            )
        if (next != null) {
            startWatch(next)
            refresh()
        }
    }

    private fun startWatch(captured: View) {
        watcher?.cancel()
        watcher = scope.launch {
            try {
                repository.changes(captured.session, captured.target.id).collect {
                    if (owns(captured)) {
                        mutable.value =
                            mutable.value.copy(fresh = false, confirmation = null, text = "")
                        if (!mutable.value.busy) refresh()
                    }
                }
            } catch (error: Exception) {
                throwIfCancelled(error)
                if (owns(captured)) {
                    readTicket++
                    read?.cancel()
                    watcher = null
                    mutable.value =
                        mutable.value.copy(
                            fresh = false,
                            loading = false,
                            confirmation = null,
                            text = "",
                            error = organizationReviewFailure(error),
                        )
                }
            }
        }
    }

    fun refreshPending() {
        val session = mutable.value.session ?: return
        if (!alive(session) || mutable.value.busy) return
        val ticket = ++pendingTicket
        scope.launch {
            try {
                val entries = repository.pending(session)
                if (ticket == pendingTicket && alive(session))
                    mutable.value = mutable.value.copy(pending = entries, journalReady = true)
            } catch (error: Exception) {
                throwIfCancelled(error)
                if (ticket == pendingTicket && alive(session))
                    mutable.value =
                        mutable.value.copy(
                            journalReady = false,
                            error = organizationReviewFailure(error),
                        )
            }
        }
    }

    fun refresh() {
        val captured = view ?: return
        if (!owns(captured) || mutable.value.busy) return
        if (watcher == null) startWatch(captured)
        val ticket = ++readTicket
        val pendingRead = ++pendingTicket
        read?.cancel()
        mutable.value =
            mutable.value.copy(fresh = false, loading = true, confirmation = null, text = "")
        read = scope.launch {
            try {
                val snapshot = repository.read(captured.session, captured.target.id)
                val entries = repository.pending(captured.session)
                if (ticket == readTicket && owns(captured)) {
                    val same = snapshot.version.fingerprint == captured.fingerprint
                    mutable.value =
                        mutable.value.copy(
                            snapshot = snapshot,
                            fresh = same,
                            loading = false,
                            journalReady =
                                if (pendingRead == pendingTicket) true
                                else mutable.value.journalReady,
                            pending =
                                if (pendingRead == pendingTicket) entries
                                else mutable.value.pending,
                            error = if (same) null else OrganizationReviewFailure.STALE,
                        )
                }
            } catch (error: Exception) {
                throwIfCancelled(error)
                if (ticket == readTicket && owns(captured))
                    mutable.value =
                        mutable.value.copy(
                            fresh = false,
                            loading = false,
                            error = organizationReviewFailure(error),
                        )
            }
        }
    }

    fun request(action: OrganizationReviewAction) {
        val captured = view ?: return
        if (!owns(captured) || !mutable.value.canAct) return
        mutable.value =
            mutable.value.copy(confirmation = action, text = "", error = null, observation = null)
    }

    fun editText(value: String) {
        if (
            !mutable.value.busy &&
                mutable.value.confirmation != null &&
                view?.let(::owns) == true &&
                value.length <= 65_536
        )
            mutable.value = mutable.value.copy(text = value)
    }

    fun cancelConfirmation() {
        if (!mutable.value.busy) mutable.value = mutable.value.copy(confirmation = null, text = "")
    }

    fun confirm() {
        val captured = view ?: return
        val state = mutable.value
        val action = state.confirmation ?: return
        val version = state.snapshot?.version ?: return
        if (!owns(captured) || !state.canConfirm || version.fingerprint != captured.fingerprint)
            return
        val originalGuard = guard
        val ticket = generation
        pendingTicket++
        mutable.value = state.copy(busy = true, error = null)
        operation = scope.launch {
            try {
                val observation =
                    repository.execute(captured.session, version, action, state.text) {
                        owns(captured) && originalGuard() && mutable.value.fresh
                    }
                if (ticket == generation && alive(captured.session))
                    mutable.value =
                        mutable.value.copy(
                            observation = observation.takeIf { view?.target == captured.target },
                            observationTargetId =
                                captured.target.id.takeIf { view?.target == captured.target },
                            completion =
                                mutable.value.completion + if (observation.confirmed) 1 else 0,
                        )
            } catch (error: Exception) {
                throwIfCancelled(error)
                if (
                    ticket == generation &&
                        alive(captured.session) &&
                        view?.target == captured.target
                )
                    mutable.value = mutable.value.copy(error = organizationReviewFailure(error))
            } finally {
                if (ticket == generation && alive(captured.session)) {
                    mutable.value =
                        mutable.value.copy(
                            busy = false,
                            fresh = false,
                            journalReady = false,
                            confirmation = null,
                            text = "",
                        )
                    refreshPending()
                    refresh()
                }
            }
        }
    }

    fun reconcile(entry: OrganizationReviewPending) {
        val session = mutable.value.session ?: return
        if (!alive(session) || mutable.value.busy || entry !in mutable.value.pending || !liveHost())
            return
        val ticket = generation
        pendingTicket++
        mutable.value = mutable.value.copy(busy = true, error = null)
        operation = scope.launch {
            try {
                val observation = repository.reconcile(session, entry)
                if (ticket == generation && alive(session))
                    mutable.value =
                        mutable.value.copy(
                            observation =
                                observation.takeIf {
                                    view == null || view?.target?.id == entry.version.organizationId
                                },
                            observationTargetId =
                                entry.version.organizationId.takeIf {
                                    view == null || view?.target?.id == entry.version.organizationId
                                },
                            completion =
                                mutable.value.completion + if (observation.confirmed) 1 else 0,
                        )
            } catch (error: Exception) {
                throwIfCancelled(error)
                if (ticket == generation && alive(session))
                    mutable.value = mutable.value.copy(error = organizationReviewFailure(error))
            } finally {
                if (ticket == generation && alive(session)) {
                    mutable.value = mutable.value.copy(busy = false, journalReady = false)
                    refreshPending()
                    refresh()
                }
            }
        }
    }

    override fun onCleared() {
        observer?.cancel()
        watcher?.cancel()
        read?.cancel()
        operation?.cancel()
        super.onCleared()
    }

    private fun throwIfCancelled(error: Exception) {
        if (error is CancellationException && error !is TimeoutCancellationException) throw error
    }
}
