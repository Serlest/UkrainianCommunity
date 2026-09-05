package at.uac.android.feature.moderation

import at.uac.android.feature.auth.AuthStore
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.isActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

class AuthModerationDecisionGate(private val auth: AuthStore) : ModerationDecisionGate {
    override suspend fun <T> withSession(session: ModerationSession, action: suspend () -> T): T =
        auth.withReadySession(session.uid, session.revision, action)
}

class ModerationDecisionRepository(
    private val source: ModerationDecisionSource,
    private val journal: ModerationDecisionJournal,
    private val authority: () -> ModerationSession?,
    private val gate: ModerationDecisionGate,
    private val clock: () -> Instant = Instant::now,
    private val operationId: () -> String = { UUID.randomUUID().toString() },
) {
    // A second UI/host cannot race journal discovery with a write or a reconcile/clear.
    private val operations = Mutex()

    fun currentSession(): ModerationSession? = authority()

    private fun ensure(session: ModerationSession) {
        ModerationDecisionContract.requireSession(session)
        if (session != authority()) throw CancellationException("Moderation decision scope changed")
    }

    suspend fun pending(session: ModerationSession): List<ModerationPending> {
        ensure(session)
        return journal.pending(session.uid).also { entries ->
            ensure(session)
            entries.forEach { ModerationDecisionContract.requireOwner(session, it) }
        }
    }

    suspend fun execute(
        session: ModerationSession,
        version: ModerationReviewVersion,
        decision: ModerationDecision,
        canSubmit: () -> Boolean,
    ): ModerationObservation = operations.withLock {
        // The Auth gate deliberately settles an already-started Task in NonCancellable. Keep the
        // original consumer separately so cancellation can still veto a not-yet-sent decision.
        val caller = currentCoroutineContext()
        ensure(session)
        version.validate()
        if (!canSubmit()) ModerationDecisionContract.fail(ModerationDecisionFailure.STALE)
        val observation =
            try {
                gate.withSession(session) {
                    // Even an injected gate must not detach a dispatched SDK operation on caller
                    // cancellation.
                    withContext(NonCancellable) {
                        caller.ensureActive()
                        ensure(session)
                        if (pending(session).any { it.version.target == version.target })
                            ModerationDecisionContract.fail(ModerationDecisionFailure.PENDING)
                        caller.ensureActive()
                        source.authorize(session)
                        ensure(session)
                        caller.ensureActive()
                        if (!canSubmit())
                            ModerationDecisionContract.fail(ModerationDecisionFailure.STALE)
                        var entry =
                            ModerationPending(
                                ModerationDecisionContract.accountHash(session.uid),
                                version,
                                operationId(),
                                session.role,
                                decision,
                                clock(),
                                ModerationDecisionPhase.PREPARED,
                            )
                        entry = journal.put(session.uid, entry)
                        // Before DISPATCHED/SDK only, this exact running invocation knows no send
                        // happened.
                        if (!caller.isActive || session != authority() || !canSubmit()) {
                            journal.clear(session.uid, entry)
                            caller.ensureActive()
                            ensure(session)
                            ModerationDecisionContract.fail(ModerationDecisionFailure.STALE)
                        }
                        entry =
                            journal.put(
                                session.uid,
                                entry.copy(phase = ModerationDecisionPhase.DISPATCHED),
                                entry,
                            )
                        // No mutation replay, even if a second authorization read fails before the
                        // SDK
                        // Task starts.
                        try {
                            source.execute(session, entry) {
                                caller.isActive && session == authority() && canSubmit()
                            }
                        } catch (error: Exception) {
                            throw ModerationDecisionException(
                                ModerationDecisionFailure.UNCONFIRMED,
                                error,
                            )
                        }
                        entry =
                            journal.put(
                                session.uid,
                                entry.copy(phase = ModerationDecisionPhase.ACKNOWLEDGED),
                                entry,
                            )
                        ensure(session)
                        val observation =
                            try {
                                source.reconcile(session, entry)
                            } catch (error: TimeoutCancellationException) {
                                throw ModerationDecisionException(
                                    ModerationDecisionFailure.UNCONFIRMED,
                                    error,
                                )
                            } catch (error: CancellationException) {
                                throw error
                            } catch (error: Exception) {
                                throw ModerationDecisionException(
                                    ModerationDecisionFailure.UNCONFIRMED,
                                    error,
                                )
                            }
                        ensure(session)
                        if (observation.confirmed) journal.clear(session.uid, entry)
                        observation
                    }
                }
            } catch (error: Exception) {
                // Actual SDK settlement and journal work above finish first. A cancelled UI caller
                // must not receive a late transport failure as a new active-screen result.
                currentCoroutineContext().ensureActive()
                if (error is TimeoutCancellationException)
                    throw ModerationDecisionException(ModerationDecisionFailure.OFFLINE, error)
                throw error
            }
        currentCoroutineContext().ensureActive()
        ensure(session)
        observation
    }

    suspend fun reconcile(
        session: ModerationSession,
        entry: ModerationPending,
    ): ModerationObservation = operations.withLock {
        ensure(session)
        ModerationDecisionContract.requireOwner(session, entry)
        val result =
            try {
                gate.withSession(session) {
                    withContext(NonCancellable) {
                        ensure(session)
                        if (pending(session).none { it == entry })
                            ModerationDecisionContract.fail(ModerationDecisionFailure.PENDING)
                        // The source bounds the read result to 15s. A timeout does not force RPC
                        // cancellation, but this path never publishes or retries a mutation.
                        val observation = source.reconcile(session, entry)
                        ensure(session)
                        if (observation.confirmed) journal.clear(session.uid, entry)
                        observation
                    }
                }
            } catch (error: Exception) {
                currentCoroutineContext().ensureActive()
                if (error is TimeoutCancellationException)
                    throw ModerationDecisionException(ModerationDecisionFailure.OFFLINE, error)
                throw error
            }
        currentCoroutineContext().ensureActive()
        ensure(session)
        result
    }
}

fun moderationDecisionFailure(error: Throwable): ModerationDecisionFailure =
    when (error) {
        is ModerationDecisionException -> error.failure
        is ModerationException ->
            when (error.failure) {
                ModerationFailure.OFFLINE -> ModerationDecisionFailure.OFFLINE
                ModerationFailure.STALE -> ModerationDecisionFailure.STALE
                ModerationFailure.INVALID -> ModerationDecisionFailure.INVALID
                else -> ModerationDecisionFailure.ACCESS
            }
        is java.io.IOException,
        is kotlinx.coroutines.TimeoutCancellationException,
        is com.google.firebase.FirebaseNetworkException -> ModerationDecisionFailure.OFFLINE
        else -> ModerationDecisionFailure.UNCONFIRMED
    }
