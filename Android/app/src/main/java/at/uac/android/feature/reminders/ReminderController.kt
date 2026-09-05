package at.uac.android.feature.reminders

import at.uac.android.feature.auth.AuthSession
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.browse.Content
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

/**
 * Live host veto is separate from durable desired state. Missing host is never a saved READY grant.
 */
class ReminderAuthority {
    @Volatile private var generation = 0L
    @Volatile private var attached = false
    @Volatile private var session: ReminderSession? = null
    @Volatile private var liveAuth: (() -> AuthSession)? = null

    @Synchronized
    fun attachAuth(supplier: () -> AuthSession) {
        liveAuth = supplier
        generation++
    }

    @Synchronized
    fun bind(next: ReminderSession?): Boolean {
        if (attached && next == session) return false
        attached = true
        generation++
        session = next
        return true
    }

    fun currentSession(): ReminderSession? = session

    @Synchronized
    fun invalidate() {
        generation++
    }

    fun capture(owner: String): Long? {
        val supplier = liveAuth
        if (supplier != null) {
            val live = runCatching { supplier().reminderSession() }.getOrNull()
            if (live == null || !live.ready || live != session || reminderOwner(live.uid) != owner)
                return null
        }
        return if (!attached || session?.let { it.ready && reminderOwner(it.uid) == owner } == true)
            generation
        else null
    }

    fun matches(owner: String, captured: Long): Boolean = capture(owner) == captured
}

class ReminderController(
    private val source: ReminderSource,
    private val ledger: ReminderLedger,
    private val scheduler: ReminderScheduler,
    private val notifications: ReminderNotificationSink,
    private val authority: ReminderAuthority,
    private val scope: CoroutineScope,
    private val clock: () -> Instant = Instant::now,
) {
    private val mutable = MutableStateFlow(ReminderState())
    val state: StateFlow<ReminderState> = mutable
    private var generation = 0L
    private var job: Job? = null

    /**
     * Host calls synchronously for every actual Auth scope transition, including
     * busy/non-ready/logout.
     */
    fun bindAuth(session: AuthSession) =
        bind(session.reminderSession(), session.stage == AuthStage.RESTORING)

    fun bind(session: ReminderSession?, restoring: Boolean = false) {
        if (!authority.bind(session)) return
        generation++
        job?.cancel()
        cancelSystem()
        mutable.value = ReminderState(permission = permission(), session = session)
        val captured = generation
        job = scope.launch {
            try {
                // Only claimed tap tickets survive a same-owner refresh. They still need a NEW
                // ready scope and server proof.
                val keepOwner =
                    session?.uid?.let(::reminderOwner) ?: source.currentOwner().takeIf { restoring }
                ledger.retire(keepOwner) { generation == captured }
                if (generation == captured && session?.ready == true) reconcile()
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (generation == captured) failed(error, session)
            }
        }
    }

    fun registrationChanged(eventId: String) {
        if (reminderId(eventId)) reconcile()
    }

    fun preferencesChanged() = reconcile()

    fun visibilityChanged() = reconcile()

    fun permissionReturned() = reconcile()

    fun reconcile() {
        val session = authority.currentSession()?.takeIf { it.ready } ?: return
        val owner = reminderOwner(session.uid)
        authority.invalidate()
        val lease = authority.capture(owner) ?: return
        generation++
        val captured = generation
        job?.cancel()
        cancelSystem()
        val permission = permission()
        mutable.value = ReminderState(ReminderStage.CHECKING, permission, session = session)
        fun current() =
            generation == captured &&
                authority.matches(owner, lease) &&
                source.currentOwner() == owner
        job = scope.launch {
            try {
                // Retire first: an old durable plan must not remain active after a failed
                // preference/visibility refresh.
                ledger.retire(owner, ::current)
                if (permission != ReminderPermission.ALLOWED) {
                    if (current())
                        mutable.value =
                            ReminderState(ReminderStage.DISABLED, permission, session = session)
                    return@launch
                }
                val snapshot = withTimeout(20_000) { source.snapshot(session, ::current) }
                if (
                    !current() ||
                        snapshot.session != session ||
                        snapshot.confirmedAt > clock() ||
                        snapshot.confirmedAt < clock().minusSeconds(60)
                )
                    throw ReminderException(ReminderFailure.STALE)
                val plan = ledger.replace(snapshot, ::current)
                if (!current()) throw ReminderException(ReminderFailure.STALE)
                schedule(plan)
                mutable.value =
                    ReminderState(
                        if (
                            snapshot.preferences.notificationsEnabled &&
                                snapshot.preferences.eventRemindersEnabled
                        )
                            ReminderStage.SCHEDULED
                        else ReminderStage.DISABLED,
                        permission,
                        plan.tickets.count { it.state == ReminderTicketState.PENDING },
                        session = session,
                    )
            } catch (error: TimeoutCancellationException) {
                if (current()) failed(ReminderException(ReminderFailure.OFFLINE), session)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (current()) failed(error, session)
            }
        }
    }

    /** Explicit button only; no permission dialog or server consent write is performed here. */
    fun scheduleLocalTest() {
        if (
            mutable.value.stage != ReminderStage.SCHEDULED ||
                permission() != ReminderPermission.ALLOWED
        )
            return
        val session = authority.currentSession()?.takeIf { it.ready } ?: return
        val owner = reminderOwner(session.uid)
        val lease = authority.capture(owner) ?: return
        val captured = generation
        fun current() =
            generation == captured &&
                authority.matches(owner, lease) &&
                source.currentOwner() == owner
        scope.launch {
            try {
                val plan = ledger.addLocalTest(owner, clock(), ::current)
                if (!current()) return@launch
                schedule(plan)
                mutable.value = mutable.value.copy(localTestRequested = true)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (current()) failed(error, session)
            }
        }
    }

    /**
     * Root must call only after startup, current Auth, AppLock and its navigation guard allow
     * interaction.
     */
    suspend fun resolveTap(request: ReminderTapRequest): Content? =
        (resolveTapOutcome(request) as? ReminderTapOutcome.Event)?.content

    suspend fun resolveTapOutcome(request: ReminderTapRequest): ReminderTapOutcome? {
        if (!reminderOpaque(request.epoch) || !reminderOpaque(request.token)) return null
        val session = authority.currentSession()?.takeIf { it.ready } ?: return null
        val owner = reminderOwner(session.uid)
        val lease = authority.capture(owner) ?: return null
        fun current() = authority.matches(owner, lease) && source.currentOwner() == owner
        return try {
            withTimeout(REMINDER_BUDGET_MS) {
                val plan = ledger.read()
                val ticket =
                    plan.tickets.singleOrNull {
                        it.epoch == request.epoch &&
                            it.token == request.token &&
                            it.owner == owner &&
                            it.state == ReminderTicketState.CLAIMED
                    } ?: return@withTimeout null
                if (!ticket.due(clock())) return@withTimeout null
                val confirmed = source.verify(ticket, ::current)
                val fresh = ledger.read()
                if (
                    !current() ||
                        confirmed.ticket != ticket ||
                        fresh.epoch != ticket.epoch ||
                        fresh.tickets.none { it == ticket } ||
                        !ticket.due(clock())
                )
                    return@withTimeout null
                if (ticket.localTest && confirmed.content == null) ReminderTapOutcome.LocalTest
                else
                    confirmed.content
                        ?.takeIf { it.id == ticket.eventId && !ticket.localTest }
                        ?.let { ReminderTapOutcome.Event(it) }
            }
        } catch (error: TimeoutCancellationException) {
            null
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            null
        }
    }

    private fun permission(): ReminderPermission = runCatching {
        notifications.permission()
    }
        .getOrDefault(ReminderPermission.APP_DENIED)

    private fun cancelSystem() {
        runCatching { scheduler.cancelOwned() }
        runCatching { notifications.cancelOwned() }
    }

    private fun schedule(plan: ReminderPlan) {
        val next =
            plan.tickets
                .filter { it.state == ReminderTicketState.PENDING && it.occurrence.end > clock() }
                .minWithOrNull(compareBy<ReminderTicket> { it.fireAt }.thenBy { it.token })
        if (next == null) scheduler.cancelOwned() else scheduler.requestNext(next, clock())
    }

    private fun failed(error: Exception, session: ReminderSession?) {
        cancelSystem()
        mutable.value =
            ReminderState(
                ReminderStage.FAILED,
                permission(),
                error = (error as? ReminderException)?.failure ?: ReminderFailure.SYSTEM,
                session = session,
            )
    }
}

/** The notification side effect is serialized on Main with the live Auth invalidation hook. */
class ReminderDelivery(
    private val source: ReminderSource,
    private val ledger: ReminderLedger,
    private val scheduler: ReminderScheduler,
    private val sink: ReminderNotificationSink,
    private val authority: ReminderAuthority,
    private val clock: () -> Instant = Instant::now,
) {
    suspend fun receive(request: ReminderTapRequest) {
        if (!reminderOpaque(request.epoch) || !reminderOpaque(request.token)) return
        val plan = ledger.read()
        val triggered =
            plan.tickets.singleOrNull {
                it.token == request.token &&
                    it.epoch == request.epoch &&
                    it.state == ReminderTicketState.PENDING
            } ?: return
        val lease = authority.capture(triggered.owner) ?: return
        fun current() =
            authority.matches(triggered.owner, lease) && source.currentOwner() == triggered.owner
        if (!current()) return
        // Arm a future item before verification; an interrupted receiver must not lose unrelated
        // future alarms.
        reschedule()
        val due =
            plan.tickets
                .filter { it.state == ReminderTicketState.PENDING && it.fireAt <= clock() }
                .sortedWith(compareBy<ReminderTicket> { it.fireAt }.thenBy { it.token })
        for (ticket in due.take(8)) {
            if (!current()) return
            try {
                val confirmed = withTimeout(5_000) { source.verify(ticket, ::current) }
                if (
                    !current() ||
                        confirmed.ticket != ticket ||
                        sink.permission() != ReminderPermission.ALLOWED
                )
                    throw ReminderException(ReminderFailure.SUPPRESSED)
                val receipt = ledger.finish(ticket, true, clock(), ::current) ?: continue
                withContext(Dispatchers.Main.immediate) {
                    if (
                        current() &&
                            sink.permission() == ReminderPermission.ALLOWED &&
                            receipt.due(clock())
                    )
                        sink.postGeneric(confirmed.copy(ticket = receipt))
                }
            } catch (error: TimeoutCancellationException) {
                ledger.finish(ticket, false, clock(), ::current)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                // No blind notification retry, including a notify() failure after a durable claim.
                ledger.finish(ticket, false, clock(), ::current)
            }
        }
        // A bounded burst cannot turn into a repeated wake-up loop. Excess due tickets are consumed
        // without display.
        for (ticket in due.drop(8)) ledger.finish(ticket, false, clock(), ::current)
        reschedule()
    }

    suspend fun reschedule() {
        val plan = ledger.read()
        val owner = plan.owner ?: return
        val lease = authority.capture(owner)
        if (
            lease == null ||
                source.currentOwner() != owner ||
                sink.permission() != ReminderPermission.ALLOWED
        ) {
            withContext(Dispatchers.Main.immediate) {
                scheduler.cancelOwned()
                sink.cancelOwned()
            }
            return
        }
        // Missed/cold/reboot alarms are not catch-up notifications. Only a still-future desired
        // item is restored.
        val next =
            plan.tickets
                .filter {
                    it.state == ReminderTicketState.PENDING &&
                        it.fireAt > clock() &&
                        it.occurrence.end > clock()
                }
                .minWithOrNull(compareBy<ReminderTicket> { it.fireAt }.thenBy { it.token })
        withContext(Dispatchers.Main.immediate) {
            if (authority.matches(owner, lease) && source.currentOwner() == owner) {
                if (next == null) scheduler.cancelOwned() else scheduler.requestNext(next, clock())
            }
        }
    }
}
