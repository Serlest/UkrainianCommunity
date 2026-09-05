package at.uac.android.feature.platformrolemanagement

import at.uac.android.feature.moderation.ModerationDecisionGate
import at.uac.android.feature.moderation.ModerationSession
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

class PlatformRoleRepository(
    private val source: PlatformRoleSource,
    private val journal: PlatformRoleJournal,
    private val authority: () -> ModerationSession?,
    private val gate: ModerationDecisionGate,
    private val operationId: () -> String = { UUID.randomUUID().toString() },
) {
    private val operations = Mutex()

    fun currentSession(): ModerationSession? = authority()

    private fun ensure(session: ModerationSession) {
        PlatformRoleContract.requireSession(session)
        if (session != authority()) throw CancellationException("Platform role scope changed")
    }

    suspend fun pending(session: ModerationSession): List<PlatformRolePending> {
        val caller = currentCoroutineContext()
        caller.ensureActive()
        ensure(session)
        val entries = journalOperation { journal.pending(session.uid) }
        caller.ensureActive()
        ensure(session)
        if (
            entries.size > PlatformRoleRecovery.MAX_PENDING ||
                entries.map { it.version.targetId }.distinct().size != entries.size ||
                entries.map { it.operationId }.distinct().size != entries.size
        )
            PlatformRoleRecovery.fail(PlatformRoleFailure.JOURNAL)
        entries.forEach { PlatformRoleRecovery.requireOwner(session, it) }
        return entries
    }

    suspend fun read(session: ModerationSession, targetId: String): PlatformRoleSnapshot {
        val caller = currentCoroutineContext()
        caller.ensureActive()
        ensure(session)
        if (!PlatformRoleContract.id(targetId))
            PlatformRoleRecovery.fail(PlatformRoleFailure.INVALID)
        val result = readOperation {
            gate.withSession(session) {
                source.read(session, targetId).also {
                    ensure(session)
                    PlatformRoleRecovery.validate(it.version)
                    if (it.version.targetId != targetId)
                        PlatformRoleRecovery.fail(PlatformRoleFailure.STALE)
                }
            }
        }
        caller.ensureActive()
        ensure(session)
        return result
    }

    /** Read-only advisory preview. Execute independently re-fetches assignment metadata. */
    suspend fun targetAuth(
        session: ModerationSession,
        targetId: String,
    ): PlatformRoleTargetAuth {
        val caller = currentCoroutineContext()
        caller.ensureActive()
        ensure(session)
        if (!PlatformRoleContract.id(targetId))
            PlatformRoleRecovery.fail(PlatformRoleFailure.INVALID)
        val result = platformRoleReadOperation {
            gate.withSession(session) {
                // Gates may wait non-cancellably; do not start a read for an obsolete caller.
                caller.ensureActive()
                ensure(session)
                source.targetAuth(session, targetId).also {
                    ensure(session)
                    if (it.targetId != targetId)
                        PlatformRoleRecovery.fail(PlatformRoleFailure.STALE)
                }
            }
        }
        caller.ensureActive()
        ensure(session)
        return result
    }

    fun changes(session: ModerationSession, targetId: String): Flow<Unit> = flow {
        ensure(session)
        if (!PlatformRoleContract.id(targetId))
            PlatformRoleRecovery.fail(PlatformRoleFailure.INVALID)
        readOperation {
            source.changes(session, targetId).collect {
                ensure(session)
                emit(Unit)
            }
        }
    }

    suspend fun execute(
        session: ModerationSession,
        version: PlatformRoleVersion,
        action: PlatformRoleAction,
        reason: String,
        canSubmit: () -> Boolean,
    ): PlatformRoleObservation {
        // A queued double tap must not turn into a second single-send operation after settlement.
        if (!operations.tryLock()) PlatformRoleRecovery.fail(PlatformRoleFailure.PENDING)
        try {
            val caller = currentCoroutineContext()
            caller.ensureActive()
            ensure(session)
            PlatformRoleRecovery.validate(version)
            val text = PlatformRoleContract.normalizeReason(reason)
            PlatformRoleContract.payload(version.targetId, text)
            if (!canSubmit()) PlatformRoleRecovery.fail(PlatformRoleFailure.STALE)
            val result =
                try {
                    gate.withSession(session) {
                        withContext(NonCancellable) {
                            caller.ensureActive()
                            ensure(session)
                            val existing = pending(session)
                            if (
                                existing.any { it.version.targetId == version.targetId } ||
                                    existing.size >= PlatformRoleRecovery.MAX_PENDING
                            )
                                PlatformRoleRecovery.fail(PlatformRoleFailure.PENDING)
                            caller.ensureActive()
                            // Only a client preflight. The callable still has no expectedVersion
                            // CAS.
                            val fresh = readOperation { source.read(session, version.targetId) }
                            ensure(session)
                            caller.ensureActive()
                            if (fresh.version != version || !canSubmit())
                                PlatformRoleRecovery.fail(PlatformRoleFailure.STALE)
                            PlatformRoleContract.requireTargetRole(session, fresh.target, action)
                            val targetAuth =
                                if (action == PlatformRoleAction.ASSIGN)
                                    readOperation { source.targetAuth(session, version.targetId) }
                                else null
                            ensure(session)
                            caller.ensureActive()
                            if (!canSubmit()) PlatformRoleRecovery.fail(PlatformRoleFailure.STALE)
                            var entry =
                                PlatformRoleRecovery.prepared(
                                    session,
                                    fresh,
                                    action,
                                    text,
                                    targetAuth,
                                    operationId(),
                                )
                            caller.ensureActive()
                            ensure(session)
                            if (!canSubmit()) PlatformRoleRecovery.fail(PlatformRoleFailure.STALE)
                            entry = put(session.uid, entry)
                            if (!caller.isActive || session != authority() || !canSubmit()) {
                                // This invocation has not dispatched. Only this exact PREPARED
                                // entry
                                // can be safely cleared; crash-discovered PREPARED is never
                                // replayed.
                                journalOperation { journal.clear(session.uid, entry) }
                                caller.ensureActive()
                                ensure(session)
                                PlatformRoleRecovery.fail(PlatformRoleFailure.STALE)
                            }
                            entry =
                                put(
                                    session.uid,
                                    entry.copy(phase = PlatformRolePhase.DISPATCHED),
                                    entry,
                                )
                            val receipt =
                                try {
                                    val canDispatch = {
                                        caller.isActive && session == authority() && canSubmit()
                                    }
                                    if (!canDispatch())
                                        PlatformRoleRecovery.fail(PlatformRoleFailure.STALE)
                                    source.send(session, entry, text, canDispatch)
                                } catch (error: Exception) {
                                    // DISPATCHED is conservative even if a final source veto ran
                                    // before
                                    // Task creation. Neither an exception nor cancellation
                                    // authorizes replay.
                                    throw PlatformRoleException(
                                        PlatformRoleFailure.UNCONFIRMED,
                                        error,
                                    )
                                }
                            // Receipt must survive caller/actor change and precede any readback. Do
                            // not
                            // check current session between actual Task settlement and this durable
                            // put.
                            val acknowledged =
                                entry.copy(
                                    phase = PlatformRolePhase.ACKNOWLEDGED,
                                    receipt = receipt,
                                )
                            try {
                                PlatformRoleRecovery.validate(acknowledged)
                            } catch (error: PlatformRoleException) {
                                throw PlatformRoleException(PlatformRoleFailure.UNCONFIRMED, error)
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
        entry: PlatformRolePending,
    ): PlatformRoleObservation = operations.withLock {
        val caller = currentCoroutineContext()
        caller.ensureActive()
        ensure(session)
        PlatformRoleRecovery.requireOwner(session, entry)
        val result =
            try {
                gate.withSession(session) {
                    withContext(NonCancellable) {
                        caller.ensureActive()
                        ensure(session)
                        if (pending(session).none { it == entry })
                            PlatformRoleRecovery.fail(PlatformRoleFailure.PENDING)
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
        entry: PlatformRolePending,
    ): PlatformRoleObservation {
        val observation =
            try {
                readOperation { source.reconcile(session, entry) }
            } catch (error: PlatformRoleException) {
                // A confirmed own-call response does not disappear because its readback is offline.
                if (entry.receipt != null && error.failure == PlatformRoleFailure.OFFLINE)
                    PlatformRoleObservation.CONFIRMED_UNAVAILABLE
                else throw error
            }
        ensure(session)
        if (observation.confirmed && entry.receipt == null)
            PlatformRoleRecovery.fail(PlatformRoleFailure.UNCONFIRMED)
        if (observation.clearsPending) journalOperation { journal.clear(session.uid, entry) }
        return observation
    }

    private suspend fun put(
        uid: String,
        entry: PlatformRolePending,
        expected: PlatformRolePending? = null,
    ): PlatformRolePending = journalOperation {
        PlatformRoleRecovery.validate(entry)
        val readback = journal.put(uid, entry, expected)
        PlatformRoleRecovery.validate(readback)
        if (readback != entry) PlatformRoleRecovery.fail(PlatformRoleFailure.JOURNAL)
        readback
    }

    private suspend fun <T> readOperation(action: suspend () -> T): T =
        try {
            action()
        } catch (error: TimeoutCancellationException) {
            throw PlatformRoleException(PlatformRoleFailure.OFFLINE, error)
        }

    private suspend fun <T> journalOperation(action: suspend () -> T): T =
        try {
            action()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            throw PlatformRoleException(PlatformRoleFailure.JOURNAL, error)
        }
}
