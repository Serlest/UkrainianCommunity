package at.uac.android.feature.feedbackdeletion

import at.uac.android.feature.feedback.FeedbackAudience
import at.uac.android.feature.moderation.ModerationDecisionGate
import at.uac.android.feature.moderation.ModerationSession
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.isActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

fun interface FeedbackDeletionMutationSource {
    suspend fun delete(
        session: ModerationSession,
        entry: FeedbackDeletionPending,
        canDispatch: () -> Boolean,
    ): FeedbackDeletionReceipt
}

/**
 * Exactly-once client dispatch. A dispatched entry is never replayed: an interrupted transport is
 * kept for manual reconciliation. Only the callable's checked successful response clears it.
 */
class FeedbackDeletionRepository(
    private val reviews: FeedbackDeletionReadRepository,
    private val source: FeedbackDeletionMutationSource,
    private val journal: FeedbackDeletionJournal,
    private val authority: () -> ModerationSession?,
    private val gate: ModerationDecisionGate,
    private val operationId: () -> String = { UUID.randomUUID().toString() },
) {
    private val operations = Mutex()

    private fun ensure(session: ModerationSession) {
        FeedbackDeletionContract.requireSession(session)
        if (session != authority()) throw CancellationException("Feedback deletion scope changed")
    }

    suspend fun delete(
        session: ModerationSession,
        audience: FeedbackAudience,
        version: FeedbackDeletionVersion,
        canSubmit: () -> Boolean,
    ): FeedbackDeletionReceipt = operations.withLock {
        val caller = currentCoroutineContext()
        ensure(session)
        FeedbackDeletionRecovery.validate(version)
        if (!canSubmit()) FeedbackDeletionRecovery.fail(FeedbackDeletionFailure.STALE)
        val receipt =
            try {
                gate.withSession(session) {
                    withContext(NonCancellable) {
                        caller.ensureActive()
                        ensure(session)
                        val snapshot = reviews.review(session, audience, version, canSubmit)
                        var entry =
                            FeedbackDeletionRecovery.prepared(
                                session,
                                audience,
                                snapshot,
                                operationId(),
                            )
                        entry = journal.put(session.uid, entry)
                        if (!caller.isActive || session != authority() || !canSubmit()) {
                            journal.clear(session.uid, entry)
                            caller.ensureActive()
                            ensure(session)
                            FeedbackDeletionRecovery.fail(FeedbackDeletionFailure.STALE)
                        }
                        entry =
                            journal.put(
                                session.uid,
                                entry.copy(phase = FeedbackDeletionPhase.DISPATCHED),
                                entry,
                            )
                        val accepted =
                            try {
                                source.delete(session, entry) {
                                    caller.isActive && session == authority() && canSubmit()
                                }
                            } catch (error: CancellationException) {
                                throw error
                            } catch (error: FeedbackDeletionException) {
                                throw error
                            } catch (error: Exception) {
                                throw FeedbackDeletionException(
                                    FeedbackDeletionFailure.UNCONFIRMED,
                                    error,
                                )
                            }
                        entry =
                            journal.put(
                                session.uid,
                                entry.copy(
                                    phase = FeedbackDeletionPhase.ACKNOWLEDGED,
                                    receipt = accepted,
                                ),
                                entry,
                            )
                        ensure(session)
                        journal.clear(session.uid, entry)
                        accepted
                    }
                }
            } catch (error: Exception) {
                currentCoroutineContext().ensureActive()
                throw error
            }
        currentCoroutineContext().ensureActive()
        ensure(session)
        receipt
    }

    /** Clears only a durable acknowledged receipt. PREPARED/DISPATCHED entries are never replayed. */
    suspend fun reconcile(
        session: ModerationSession,
        audience: FeedbackAudience,
        entry: FeedbackDeletionPending,
    ): FeedbackDeletionObservation = operations.withLock {
        ensure(session)
        FeedbackDeletionRecovery.requireOwner(session, entry)
        val observation = reviews.reconcile(session, audience, entry)
        ensure(session)
        if (entry.phase == FeedbackDeletionPhase.ACKNOWLEDGED && entry.receipt != null)
            journal.clear(session.uid, entry)
        observation
    }
}
