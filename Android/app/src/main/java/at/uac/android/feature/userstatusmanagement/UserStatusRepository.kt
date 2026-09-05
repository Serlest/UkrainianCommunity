package at.uac.android.feature.userstatusmanagement

import at.uac.android.feature.moderation.ModerationDecisionGate
import at.uac.android.feature.moderation.ModerationSession
import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

class UserStatusRepository(
    private val source: UserStatusSource,
    private val journal: UserStatusJournal,
    private val authority: () -> ModerationSession?,
    private val gate: ModerationDecisionGate,
    private val clock: () -> Instant = Instant::now,
    private val operationId: () -> String = { UUID.randomUUID().toString() },
) {
    private val operations = Mutex()

    fun currentSession(): ModerationSession? = authority()

    private fun ensure(session: ModerationSession) {
        UserStatusContract.requireSession(session)
        if (session != authority()) throw CancellationException("User status scope changed")
    }

    suspend fun pending(session: ModerationSession): List<UserStatusPending> {
        val caller = currentCoroutineContext()
        caller.ensureActive()
        ensure(session)
        val entries = journalOperation { journal.pending(session.uid) }
        caller.ensureActive()
        ensure(session)
        if (
            entries.size > UserStatusContract.MAX_PENDING ||
                entries.map { it.version.targetId }.distinct().size != entries.size ||
                entries.map { it.operationId }.distinct().size != entries.size
        )
            UserStatusContract.fail(UserStatusFailure.JOURNAL)
        entries.forEach { UserStatusContract.requireOwner(session, it) }
        return entries
    }

    suspend fun read(session: ModerationSession, targetId: String): UserStatusSnapshot {
        val caller = currentCoroutineContext()
        caller.ensureActive()
        ensure(session)
        if (!UserStatusContract.id(targetId)) UserStatusContract.fail(UserStatusFailure.INVALID)
        val result = readOperation {
            gate.withSession(session) {
                source.read(session, targetId).also {
                    ensure(session)
                    UserStatusContract.validate(it.version)
                    if (it.version.targetId != targetId)
                        UserStatusContract.fail(UserStatusFailure.STALE)
                }
            }
        }
        caller.ensureActive()
        ensure(session)
        return result
    }

    fun changes(session: ModerationSession, targetId: String): Flow<Unit> = flow {
        ensure(session)
        if (!UserStatusContract.id(targetId)) UserStatusContract.fail(UserStatusFailure.INVALID)
        readOperation {
            source.changes(session, targetId).collect {
                ensure(session)
                emit(Unit)
            }
        }
    }

    suspend fun execute(
        session: ModerationSession,
        version: UserStatusVersion,
        action: UserStatusAction,
        reason: String,
        suspensionDays: Int = UserStatusContract.DEFAULT_SUSPENSION_DAYS,
        zoneId: ZoneId = ZoneId.systemDefault(),
        canSubmit: () -> Boolean,
    ): UserStatusObservation {
        // A queued double tap must not turn into a second single-send operation after settlement.
        if (!operations.tryLock()) UserStatusContract.fail(UserStatusFailure.PENDING)
        try {
            val caller = currentCoroutineContext()
            caller.ensureActive()
            ensure(session)
            UserStatusContract.validate(version)
            val text = UserStatusContract.normalizeText(reason)
            val until =
                if (action == UserStatusAction.SUSPEND)
                    UserStatusContract.suspensionUntil(clock(), suspensionDays, zoneId)
                else null
            UserStatusContract.payload(version.targetId, action, text, until)
            if (!canSubmit()) UserStatusContract.fail(UserStatusFailure.STALE)
            val result =
                try {
                    gate.withSession(session) {
                        withContext(NonCancellable) {
                            caller.ensureActive()
                            ensure(session)
                            val existing = pending(session)
                            if (
                                existing.any { it.version.targetId == version.targetId } ||
                                    existing.size >= UserStatusContract.MAX_PENDING
                            )
                                UserStatusContract.fail(UserStatusFailure.PENDING)
                            caller.ensureActive()
                            // Only a client preflight. The callable still has no expectedVersion
                            // CAS.
                            val fresh = readOperation { source.read(session, version.targetId) }
                            ensure(session)
                            caller.ensureActive()
                            if (fresh.version != version || !canSubmit())
                                UserStatusContract.fail(UserStatusFailure.STALE)
                            UserStatusContract.requireTarget(session, fresh, action)
                            if (until != null && until <= clock())
                                UserStatusContract.fail(UserStatusFailure.STALE)
                            var entry =
                                UserStatusContract.prepared(
                                    session,
                                    fresh,
                                    action,
                                    text,
                                    until,
                                    operationId(),
                                )
                            caller.ensureActive()
                            ensure(session)
                            if (!canSubmit()) UserStatusContract.fail(UserStatusFailure.STALE)
                            entry = put(session.uid, entry)
                            if (!caller.isActive || session != authority() || !canSubmit()) {
                                // This invocation has not dispatched. Only this exact PREPARED
                                // entry
                                // can be safely cleared; crash-discovered PREPARED is never
                                // replayed.
                                journalOperation { journal.clear(session.uid, entry) }
                                caller.ensureActive()
                                ensure(session)
                                UserStatusContract.fail(UserStatusFailure.STALE)
                            }
                            entry =
                                put(
                                    session.uid,
                                    entry.copy(phase = UserStatusPhase.DISPATCHED),
                                    entry,
                                )
                            val receipt =
                                try {
                                    val canDispatch = {
                                        caller.isActive && session == authority() && canSubmit()
                                    }
                                    if (!canDispatch())
                                        UserStatusContract.fail(UserStatusFailure.STALE)
                                    source.send(session, entry, text, until, canDispatch)
                                } catch (error: Exception) {
                                    // DISPATCHED is conservative even if a final source veto ran
                                    // before
                                    // Task creation. Neither an exception nor cancellation
                                    // authorizes replay.
                                    throw UserStatusException(UserStatusFailure.UNCONFIRMED, error)
                                }
                            // Receipt must survive caller/actor change and precede any readback. Do
                            // not
                            // check current session between actual Task settlement and this durable
                            // put.
                            val acknowledged =
                                entry.copy(phase = UserStatusPhase.ACKNOWLEDGED, receipt = receipt)
                            try {
                                UserStatusContract.validate(acknowledged)
                            } catch (error: UserStatusException) {
                                throw UserStatusException(UserStatusFailure.UNCONFIRMED, error)
                            }
                            entry = put(session.uid, acknowledged, entry)
                            ensure(session)
                            caller.ensureActive()
                            val observation = reconcileInsideGate(session, entry)
                            caller.ensureActive()
                            observation
                        }
                    }
                } catch (error: Exception) {
                    currentCoroutineContext().ensureActive()
                    throw error
                }
            currentCoroutineContext().ensureActive()
            ensure(session)
            return result
        } finally {
            operations.unlock()
        }
    }

    suspend fun reconcile(
        session: ModerationSession,
        entry: UserStatusPending,
    ): UserStatusObservation = operations.withLock {
        val caller = currentCoroutineContext()
        caller.ensureActive()
        ensure(session)
        UserStatusContract.requireOwner(session, entry)
        val result =
            try {
                gate.withSession(session) {
                    withContext(NonCancellable) {
                        caller.ensureActive()
                        ensure(session)
                        if (pending(session).none { it == entry })
                            UserStatusContract.fail(UserStatusFailure.PENDING)
                        caller.ensureActive()
                        reconcileInsideGate(session, entry).also { caller.ensureActive() }
                    }
                }
            } catch (error: Exception) {
                currentCoroutineContext().ensureActive()
                throw error
            }
        currentCoroutineContext().ensureActive()
        ensure(session)
        result
    }

    private suspend fun reconcileInsideGate(
        session: ModerationSession,
        entry: UserStatusPending,
    ): UserStatusObservation {
        val observation =
            try {
                readOperation { source.reconcile(session, entry) }
            } catch (error: UserStatusException) {
                // A confirmed own-call response does not disappear because its readback is offline.
                if (entry.receipt != null && error.failure == UserStatusFailure.OFFLINE)
                    UserStatusObservation.CONFIRMED_UNAVAILABLE
                else throw error
            }
        ensure(session)
        if (observation.confirmed && entry.receipt == null)
            UserStatusContract.fail(UserStatusFailure.UNCONFIRMED)
        if (observation.clearsPending) journalOperation { journal.clear(session.uid, entry) }
        return observation
    }

    private suspend fun put(
        uid: String,
        entry: UserStatusPending,
        expected: UserStatusPending? = null,
    ): UserStatusPending = journalOperation {
        UserStatusContract.validate(entry)
        val readback = journal.put(uid, entry, expected)
        UserStatusContract.validate(readback)
        if (readback != entry) UserStatusContract.fail(UserStatusFailure.JOURNAL)
        readback
    }

    private suspend fun <T> readOperation(action: suspend () -> T): T =
        try {
            action()
        } catch (error: TimeoutCancellationException) {
            throw UserStatusException(UserStatusFailure.OFFLINE, error)
        }

    private suspend fun <T> journalOperation(action: suspend () -> T): T =
        try {
            action()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            throw UserStatusException(UserStatusFailure.JOURNAL, error)
        }
}
