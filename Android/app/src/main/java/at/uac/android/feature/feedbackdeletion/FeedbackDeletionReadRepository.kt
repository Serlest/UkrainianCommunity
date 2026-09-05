package at.uac.android.feature.feedbackdeletion

import at.uac.android.feature.feedback.FeedbackAudience
import at.uac.android.feature.moderation.ModerationDecisionGate
import at.uac.android.feature.moderation.ModerationSession
import java.io.IOException
import kotlin.coroutines.CoroutineContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

/**
 * Read-only seam, deliberately without send/delete. A future SDK implementation must establish
 * actual owner/TOTP authority and SERVER metadata; cache/permission errors are never Absent.
 */
fun interface FeedbackDeletionReadSource {
    suspend fun read(session: ModerationSession, targetId: String): FeedbackDeletionRead
}

/**
 * Inert review/recovery coordinator. No SDK implementation or UI wiring, no journal writes,
 * clearance, operation allocation or callable dispatch. Review is not a lease or server CAS.
 */
class FeedbackDeletionReadRepository(
    private val source: FeedbackDeletionReadSource,
    private val journal: FeedbackDeletionJournal,
    private val authority: () -> ModerationSession?,
    private val gate: ModerationDecisionGate,
) {
    private fun ensure(session: ModerationSession, caller: CoroutineContext) {
        caller.ensureActive()
        FeedbackDeletionContract.requireSession(session)
        if (session != authority()) throw CancellationException("Feedback deletion scope changed")
    }

    private suspend fun <T> scoped(
        session: ModerationSession,
        audience: FeedbackAudience,
        action: suspend (CoroutineContext) -> T,
    ): T {
        val caller = currentCoroutineContext()
        ensure(session, caller)
        if (audience != FeedbackAudience.MANAGEMENT)
            FeedbackDeletionRecovery.fail(FeedbackDeletionFailure.ACCESS)
        try {
            val result =
                gate.withSession(session) {
                    // The Auth gate can wait/run non-cancellably: preserve the original consumer.
                    ensure(session, caller)
                    action(caller)
                }
            ensure(session, caller)
            return result
        } catch (error: Exception) {
            ensure(session, caller)
            throw error
        }
    }

    suspend fun pending(session: ModerationSession): List<FeedbackDeletionPending> =
        scoped(session, FeedbackAudience.MANAGEMENT) { caller -> pendingInside(session, caller) }

    private suspend fun pendingInside(
        session: ModerationSession,
        caller: CoroutineContext,
    ): List<FeedbackDeletionPending> {
        ensure(session, caller)
        val entries =
            try {
                // Own the list snapshot even if a source returns a mutable backing collection.
                journal.pending(session.uid).toList().also { values ->
                    if (
                        values.size > FeedbackDeletionRecovery.MAX_PENDING ||
                            values.map { it.version.targetId }.distinct().size != values.size ||
                            values.map { it.operationId }.distinct().size != values.size
                    )
                        FeedbackDeletionRecovery.fail(FeedbackDeletionFailure.JOURNAL)
                    values.forEach { FeedbackDeletionRecovery.requireOwner(session, it) }
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                throw FeedbackDeletionException(FeedbackDeletionFailure.JOURNAL, error)
            }
        ensure(session, caller)
        return entries
    }

    suspend fun read(
        session: ModerationSession,
        audience: FeedbackAudience,
        targetId: String,
    ): FeedbackDeletionRead =
        scoped(session, audience) { caller ->
            readInside(session, targetId, caller)
        }

    private suspend fun readInside(
        session: ModerationSession,
        targetId: String,
        caller: CoroutineContext,
    ): FeedbackDeletionRead {
        ensure(session, caller)
        if (!FeedbackDeletionContract.id(targetId))
            FeedbackDeletionRecovery.fail(FeedbackDeletionFailure.INVALID)
        val result =
            try {
                source.read(session, targetId)
            } catch (error: TimeoutCancellationException) {
                throw FeedbackDeletionException(FeedbackDeletionFailure.OFFLINE, error)
            } catch (error: CancellationException) {
                throw error
            } catch (error: FeedbackDeletionException) {
                throw error
            } catch (error: IOException) {
                throw FeedbackDeletionException(FeedbackDeletionFailure.OFFLINE, error)
            } catch (error: Exception) {
                throw FeedbackDeletionException(FeedbackDeletionFailure.UNCONFIRMED, error)
            }
        ensure(session, caller)
        if (result is FeedbackDeletionRead.Present) {
            FeedbackDeletionRecovery.validate(result.snapshot)
            if (result.snapshot.version.targetId != targetId)
                FeedbackDeletionRecovery.fail(FeedbackDeletionFailure.STALE)
            FeedbackDeletionContract.requireTarget(
                session,
                FeedbackAudience.MANAGEMENT,
                result.snapshot.target,
            )
        }
        return result
    }

    /** Fresh preview only. Never creates a PREPARED record or grants future dispatch authority. */
    suspend fun review(
        session: ModerationSession,
        audience: FeedbackAudience,
        version: FeedbackDeletionVersion,
        canReview: () -> Boolean,
    ): FeedbackDeletionSnapshot =
        scoped(session, audience) { caller ->
            FeedbackDeletionRecovery.validate(version)
            fun selected() {
                ensure(session, caller)
                if (!canReview()) FeedbackDeletionRecovery.fail(FeedbackDeletionFailure.STALE)
            }
            suspend fun available() {
                val entries = pendingInside(session, caller)
                if (
                    entries.size >= FeedbackDeletionRecovery.MAX_PENDING ||
                        entries.any { it.version.targetId == version.targetId }
                )
                    FeedbackDeletionRecovery.fail(FeedbackDeletionFailure.PENDING)
            }
            selected()
            available()
            selected()
            val fresh =
                when (val result = readInside(session, version.targetId, caller)) {
                    FeedbackDeletionRead.Absent ->
                        FeedbackDeletionRecovery.fail(FeedbackDeletionFailure.MISSING)
                    FeedbackDeletionRead.Unavailable ->
                        FeedbackDeletionRecovery.fail(FeedbackDeletionFailure.OFFLINE)
                    is FeedbackDeletionRead.Present -> result.snapshot
                }
            selected()
            if (fresh.version != version)
                FeedbackDeletionRecovery.fail(FeedbackDeletionFailure.STALE)
            // Another repository can observe/write the journal while the server read is suspended.
            available()
            selected()
            fresh
        }

    /** Read-only observation: even own ACK+absence never clears or repeats an operation. */
    suspend fun reconcile(
        session: ModerationSession,
        audience: FeedbackAudience,
        entry: FeedbackDeletionPending,
    ): FeedbackDeletionObservation =
        scoped(session, audience) { caller ->
            FeedbackDeletionRecovery.requireOwner(session, entry)
            suspend fun exactPending() {
                if (pendingInside(session, caller).none { it == entry })
                    FeedbackDeletionRecovery.fail(FeedbackDeletionFailure.PENDING)
            }
            exactPending()
            val read =
                try {
                    readInside(session, entry.version.targetId, caller)
                } catch (error: FeedbackDeletionException) {
                    if (error.failure == FeedbackDeletionFailure.OFFLINE)
                        FeedbackDeletionRead.Unavailable
                    else throw error
                }
            ensure(session, caller)
            exactPending()
            FeedbackDeletionRecovery.observation(entry, session.uid, read)
        }
}
