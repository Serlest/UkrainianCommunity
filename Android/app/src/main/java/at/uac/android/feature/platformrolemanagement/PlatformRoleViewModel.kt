package at.uac.android.feature.platformrolemanagement

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import at.uac.android.feature.moderation.ModerationSession
import at.uac.android.feature.usermanagement.ManagedUsersPresentation
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

/** One completed attempt, bound by the VM to its live actor/host. No reason or contact data. */
data class PlatformRoleAttemptOutcome(
    val targetId: String,
    val action: PlatformRoleAction,
    val observation: PlatformRoleObservation? = null,
    val failure: PlatformRoleFailure? = null,
) {
    init {
        require(PlatformRoleContract.id(targetId))
        require((observation != null) != (failure != null))
    }

    override fun toString() = "PlatformRoleAttemptOutcome([redacted])"
}

/** Private editor data is memory-only; it is never a saved-state or log payload. */
data class PlatformRoleState(
    val session: ModerationSession? = null,
    val targetId: String? = null,
    val snapshot: PlatformRoleSnapshot? = null,
    val targetAuth: PlatformRoleTargetAuth? = null,
    val fresh: Boolean = false,
    val loading: Boolean = false,
    val busy: Boolean = false,
    val journalReady: Boolean = false,
    val pending: List<PlatformRolePending> = emptyList(),
    val confirmation: PlatformRoleAction? = null,
    val reason: String = "",
    val reasonRejected: Boolean = false,
    val error: PlatformRoleFailure? = null,
    val attemptOutcome: PlatformRoleAttemptOutcome? = null,
    val completion: Long = 0,
    // Memory-only observation identity, not a server version or authorization. An identical raw
    // reread after a render-epoch veto must still notify a conflating StateFlow collector.
    val readRevision: Long = 0,
) {
    companion object {
        const val MAX_REASON_CHARACTERS = 65_536
    }

    // Read-only compatibility projection: the attempt has a single source of truth.
    val observation: PlatformRoleObservation?
        get() = attemptOutcome?.observation

    val observationTargetId: String?
        get() = attemptOutcome?.targetId

    val availableActions: List<PlatformRoleAction>
        get() =
            snapshot
                ?.let { current ->
                    val actor = session ?: return@let emptyList()
                    PlatformRoleAction.entries.filter { action ->
                        runCatching {
                            PlatformRoleContract.requireTargetRole(actor, current.target, action)
                        }
                            .isSuccess &&
                            (action != PlatformRoleAction.ASSIGN || current.target.usableProfile)
                    }
                }
                .orEmpty()

    val canAct: Boolean
        get() =
            snapshot?.let { current ->
                session?.ready == true &&
                    session.role == "owner" &&
                    fresh &&
                    !loading &&
                    !busy &&
                    journalReady &&
                    pending.size < PlatformRoleRecovery.MAX_PENDING &&
                    pending.none { it.version.targetId == current.version.targetId }
            } == true

    val canConfirm: Boolean
        get() {
            val action = confirmation ?: return false
            val current = snapshot ?: return false
            if (!canAct || reasonRejected || action !in availableActions) return false
            return runCatching {
                PlatformRoleContract.requireTarget(
                    session ?: return false,
                    current.target,
                    action,
                    targetAuth,
                )
                PlatformRoleContract.payload(current.version.targetId, reason)
            }
                .isSuccess
        }

    override fun toString() = "PlatformRoleState(fresh=$fresh, busy=$busy, [redacted])"
}

class PlatformRoleViewModel(
    private val repository: PlatformRoleRepository,
    private val authority: () -> ModerationSession? = repository::currentSession,
    private val workScope: CoroutineScope? = null,
) : ViewModel() {
    private val scope
        get() = workScope ?: viewModelScope

    private val mutable = MutableStateFlow(PlatformRoleState())
    val state: StateFlow<PlatformRoleState> = mutable.asStateFlow()
    private var observer: Job? = null
    private var watcher: Job? = null
    private var read: Job? = null
    private var pendingRead: Job? = null
    private var operation: Job? = null
    private var generation = 0L
    private var readTicket = 0L
    private var pendingTicket = 0L
    private var operationTicket = 0L
    private var attemptEpoch = 0L
    private var attemptTargetId: String? = null
    private var lastPresentedTargetId: String? = null

    private class Host(val session: ModerationSession, val token: ManagedUsersPresentation)

    private class Target(val host: Host, val id: String)

    private var host: Host? = null
    private var target: Target? = null
    private var hostGuard: () -> Boolean = { false }
    private var targetGuard: () -> Boolean = { false }
    private val revoked =
        Collections.newSetFromMap(WeakHashMap<ManagedUsersPresentation, Boolean>())

    fun currentSession() = authority()

    private fun alive(session: ModerationSession) =
        session.ready &&
            session.role == "owner" &&
            session == authority() &&
            session == mutable.value.session

    private fun clearTarget() {
        target = null
        targetGuard = { false }
        readTicket++
        read?.cancel()
        watcher?.cancel()
        watcher = null
        mutable.value =
            mutable.value.copy(
                targetId = null,
                snapshot = null,
                targetAuth = null,
                fresh = false,
                loading = false,
                confirmation = null,
                reason = "",
                reasonRejected = false,
            )
    }

    private fun revokeHost() {
        host?.let { revoked.add(it.token) }
        host = null
        hostGuard = { false }
        lastPresentedTargetId = null
        generation++
        clearAttempt()
        clearTarget()
        pendingTicket++
        pendingRead?.cancel()
        // The repository, not this presentation, settles a submitted SDK task and its journal.
        mutable.value =
            PlatformRoleState(session = mutable.value.session, busy = operation?.isActive == true)
    }

    private fun liveHost(): Boolean {
        val owned = host ?: return false
        if (alive(owned.session) && owned.token !in revoked && hostGuard()) return true
        revokeHost()
        return false
    }

    private fun owns(owned: Target): Boolean {
        if (!liveHost() || target !== owned) return false
        if (targetGuard()) return true
        clearTarget()
        return false
    }

    fun snapshot(session: ModerationSession?): PlatformRoleState {
        if (!liveHost() || session == null || !alive(session)) return PlatformRoleState()
        target?.let(::owns)
        return mutable.value
    }

    fun dismiss(presentation: ManagedUsersPresentation) {
        if (host?.token === presentation) revokeHost()
    }

    fun observeSessions(sessions: Flow<ModerationSession?>) {
        observer?.cancel()
        observer = scope.launch { sessions.collect(::bind) }
    }

    fun bind(session: ModerationSession?) {
        val next = session?.takeIf { it == authority() && it.ready && it.role == "owner" }
        if (mutable.value.session == next) return
        revokeHost()
        operation?.cancel()
        mutable.value = PlatformRoleState(session = next, busy = operation?.isActive == true)
    }

    /**
     * Target ID is routing only. Every actionable version comes from repository.read, never the
     * list DTO.
     */
    fun bindView(
        session: ModerationSession?,
        targetId: String?,
        presentation: ManagedUsersPresentation?,
        hostIsCurrent: () -> Boolean,
        canSubmit: () -> Boolean,
    ) {
        bind(session)
        // Sample the OLD guards before replacing them: a false→true presentation must not revive.
        if (host != null) liveHost()
        target?.let(::owns)
        val valid =
            session != null &&
                alive(session) &&
                presentation != null &&
                presentation !in revoked &&
                hostIsCurrent()
        if (!valid) {
            if (host != null) revokeHost()
            return
        }
        val readySession = session
        val readyPresentation = presentation
        val current = host
        if (
            current == null ||
                current.session != readySession ||
                current.token !== readyPresentation
        ) {
            if (current != null) revokeHost()
            host = Host(readySession, readyPresentation)
        }
        hostGuard = hostIsCurrent
        val currentHost = host ?: return
        val id = targetId?.takeIf { PlatformRoleContract.id(it) && canSubmit() }
        if (id != null && id != lastPresentedTargetId) {
            if (attemptTargetId != null && attemptTargetId != id) clearAttempt()
            lastPresentedTargetId = id
        }
        if ((target != null && target?.host !== currentHost) || target?.id != id) {
            clearTarget()
            if (id != null) {
                target = Target(currentHost, id)
                mutable.value = mutable.value.copy(targetId = id)
                targetGuard = canSubmit
                watch(target!!)
                refresh()
            }
        } else targetGuard = canSubmit
        if (!mutable.value.journalReady && pendingRead?.isActive != true) refreshPending()
    }

    fun refreshPending() {
        val owned = host ?: return
        if (!liveHost()) return
        val ticket = ++pendingTicket
        pendingRead?.cancel()
        pendingRead = scope.launch {
            try {
                val entries = repository.pending(owned.session)
                if (host !== owned || !liveHost() || ticket != pendingTicket) return@launch
                mutable.value =
                    mutable.value.copy(
                        pending = entries,
                        journalReady = true,
                        error =
                            mutable.value.error?.takeUnless { it == PlatformRoleFailure.JOURNAL },
                    )
            } catch (error: Exception) {
                rethrowCancellation(error)

                if (host === owned && liveHost() && ticket == pendingTicket)
                    mutable.value = mutable.value.copy(journalReady = false, error = failure(error))
            }
        }
    }

    private fun invalidateData() {
        mutable.value =
            mutable.value.copy(
                fresh = false,
                snapshot = null,
                targetAuth = null,
                confirmation = null,
                reason = "",
                reasonRejected = false,
            )
    }

    private fun watch(owned: Target) {
        watcher?.cancel()
        watcher = scope.launch {
            try {
                repository.changes(owned.host.session, owned.id).collect {
                    if (!owns(owned)) return@collect
                    invalidateData()
                    if (!mutable.value.busy) refresh()
                }
            } catch (error: Exception) {
                rethrowCancellation(error)
                if (!owns(owned)) return@launch
                readTicket++
                read?.cancel()
                invalidateData()
                mutable.value = mutable.value.copy(loading = false, error = failure(error))
                watcher = null
            }
        }
    }

    fun refresh() {
        val owned = target ?: return
        if (!owns(owned) || operation?.isActive == true) return
        if (watcher?.isActive != true) watch(owned)
        val ticket = ++readTicket
        read?.cancel()
        invalidateData()
        mutable.value =
            mutable.value.copy(
                loading = true,
                error = mutable.value.error?.takeIf { it == PlatformRoleFailure.JOURNAL },
            )
        read = scope.launch {
            try {
                val value = repository.read(owned.host.session, owned.id)
                if (!owns(owned) || ticket != readTicket) return@launch
                if (value.version.targetId != owned.id)
                    PlatformRoleContract.fail(PlatformRoleFailure.INVALID)
                // Assignment metadata is advisory and belongs to this exact read/presentation.
                // Removal must not depend on a missing/disabled target Auth account.
                val needsAuth =
                    value.target.role == "user" &&
                        value.target.usableProfile &&
                        value.target.targetId != owned.host.session.uid
                val auth =
                    if (needsAuth) repository.targetAuth(owned.host.session, owned.id) else null
                if (!owns(owned) || ticket != readTicket) return@launch
                mutable.value =
                    mutable.value.copy(
                        snapshot = value,
                        readRevision = ticket,
                        targetAuth = auth,
                        fresh = true,
                        loading = false,
                    )
            } catch (error: Exception) {
                rethrowCancellation(error)
                if (owns(owned) && ticket == readTicket)
                    mutable.value =
                        mutable.value.copy(
                            snapshot = null,
                            targetAuth = null,
                            fresh = false,
                            loading = false,
                            error = failure(error),
                        )
            }
        }
    }

    fun request(action: PlatformRoleAction) {
        val owned = target ?: return
        if (!owns(owned) || !mutable.value.canAct || action !in mutable.value.availableActions)
            return
        clearAttempt()
        mutable.value =
            mutable.value.copy(
                confirmation = action,
                reason = "",
                reasonRejected = false,
                error = null,
            )
    }

    fun editReason(value: String) {
        val owned = target ?: return
        if (!owns(owned) || mutable.value.busy || mutable.value.confirmation == null) return
        mutable.value =
            if (value.length > PlatformRoleState.MAX_REASON_CHARACTERS)
                mutable.value.copy(reasonRejected = true)
            else mutable.value.copy(reason = value, reasonRejected = false)
    }

    fun cancelConfirmation() {
        if (mutable.value.busy) return
        mutable.value =
            mutable.value.copy(
                confirmation = null,
                reason = "",
                reasonRejected = false,
            )
    }

    private fun clearAttempt() {
        attemptEpoch++
        attemptTargetId = null
        mutable.value = mutable.value.copy(attemptOutcome = null)
    }

    fun dismissOutcome() {
        if (liveHost() && mutable.value.attemptOutcome != null) clearAttempt()
    }

    private fun beginAttempt(targetId: String): Long {
        clearAttempt()
        attemptTargetId = targetId
        return attemptEpoch
    }

    private fun ownsAttempt(owned: Host, attempt: Long, epoch: Long): Boolean =
        host === owned && attempt == attemptEpoch && generation == epoch && liveHost()

    fun confirm() {
        val owned = target ?: return
        if (!owns(owned) || !mutable.value.canConfirm || operation?.isActive == true) return
        val captured = mutable.value
        val version = captured.snapshot?.version ?: return
        val action = captured.confirmation ?: return
        val epoch = generation
        val attempt = beginAttempt(owned.id)
        val ticket = ++operationTicket
        mutable.value = mutable.value.copy(busy = true, error = null)
        operation = scope.launch {
            try {
                val result =
                    repository.execute(
                        session = owned.host.session,
                        version = version,
                        action = action,
                        reason = captured.reason,
                        canSubmit = {
                            generation == epoch &&
                                owns(owned) &&
                                mutable.value.fresh &&
                                mutable.value.snapshot?.version == version
                        },
                    )
                // Outcome ownership is independent of the now-invalidated raw preview. It cannot
                // authorize another write or bring that preview back after parent refresh.
                if (!ownsAttempt(owned.host, attempt, epoch)) return@launch
                mutable.value =
                    mutable.value.copy(
                        attemptOutcome =
                            PlatformRoleAttemptOutcome(owned.id, action, observation = result),
                        completion = mutable.value.completion + if (result.confirmed) 1 else 0,
                    )
            } catch (error: Exception) {
                rethrowCancellation(error)
                if (ownsAttempt(owned.host, attempt, epoch))
                    mutable.value =
                        mutable.value.copy(
                            attemptOutcome =
                                PlatformRoleAttemptOutcome(
                                    owned.id,
                                    action,
                                    failure = failure(error),
                                )
                        )
            } finally {
                if (ticket == operationTicket) operation = null
                settlePresentation()
            }
        }
    }

    fun reconcile(entry: PlatformRolePending) {
        val owned = host ?: return
        if (
            !liveHost() ||
                mutable.value.busy ||
                operation?.isActive == true ||
                entry !in mutable.value.pending
        )
            return
        val epoch = generation
        val attempt = beginAttempt(entry.version.targetId)
        val ticket = ++operationTicket
        mutable.value = mutable.value.copy(busy = true, error = null)
        operation = scope.launch {
            try {
                val result = repository.reconcile(owned.session, entry)
                if (!ownsAttempt(owned, attempt, epoch)) return@launch
                mutable.value =
                    mutable.value.copy(
                        attemptOutcome =
                            PlatformRoleAttemptOutcome(
                                entry.version.targetId,
                                entry.action,
                                observation = result,
                            ),
                        completion = mutable.value.completion + if (result.confirmed) 1 else 0,
                    )
            } catch (error: Exception) {
                rethrowCancellation(error)
                if (ownsAttempt(owned, attempt, epoch))
                    mutable.value =
                        mutable.value.copy(
                            attemptOutcome =
                                PlatformRoleAttemptOutcome(
                                    entry.version.targetId,
                                    entry.action,
                                    failure = failure(error),
                                )
                        )
            } finally {
                if (ticket == operationTicket) operation = null
                settlePresentation()
            }
        }
    }

    private fun settlePresentation() {
        // Completion releases the local busy latch even if its original host/account was revoked.
        mutable.value = mutable.value.copy(busy = operation?.isActive == true)
        if (!liveHost()) return
        mutable.value =
            mutable.value.copy(
                busy = operation?.isActive == true,
                fresh = false,
                journalReady = false,
                confirmation = null,
                reason = "",
                reasonRejected = false,
            )
        refreshPending()
        refresh()
    }

    private fun failure(error: Exception) = platformRoleFailure(error)

    private fun rethrowCancellation(error: Exception) {
        if (error is CancellationException && error !is TimeoutCancellationException) throw error
    }

    override fun onCleared() {
        revokeHost()
        observer?.cancel()
        operation?.cancel()
        super.onCleared()
    }
}
