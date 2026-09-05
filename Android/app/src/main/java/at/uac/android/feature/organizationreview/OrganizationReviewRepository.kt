package at.uac.android.feature.organizationreview

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

class OrganizationReviewRepository(
    private val source: OrganizationReviewSource,
    private val journal: OrganizationReviewJournal,
    private val authority: () -> ModerationSession?,
    private val gate: ModerationDecisionGate,
    private val operationId: () -> String = { UUID.randomUUID().toString() },
) {
    private val operations = Mutex()

    fun currentSession() = authority()

    private fun ensure(session: ModerationSession) {
        OrganizationReviewContract.requireSession(session)
        if (session != authority()) throw CancellationException("Organization review scope changed")
    }

    suspend fun pending(session: ModerationSession): List<OrganizationReviewPending> {
        ensure(session)
        return journal.pending(session.uid).also { entries ->
            ensure(session)
            entries.forEach { OrganizationReviewContract.requireOwner(session, it) }
        }
    }

    suspend fun read(session: ModerationSession, id: String): OrganizationReviewSnapshot {
        ensure(session)
        return gate.withSession(session) { source.read(session, id).also { ensure(session) } }
    }

    fun changes(session: ModerationSession, id: String) = source.changes(session, id)

    suspend fun execute(
        session: ModerationSession,
        version: OrganizationReviewVersion,
        action: OrganizationReviewAction,
        text: String,
        canSubmit: () -> Boolean,
    ): OrganizationReviewObservation = operations.withLock {
        val caller = currentCoroutineContext()
        ensure(session)
        OrganizationReviewContract.validate(version)
        val normalized = OrganizationReviewContract.normalizeText(text)
        OrganizationReviewContract.payload(version.organizationId, action, normalized)
        if (!canSubmit()) OrganizationReviewContract.fail(OrganizationReviewFailure.STALE)
        val result =
            try {
                gate.withSession(session) {
                    withContext(NonCancellable) {
                        ensure(session)
                        if (
                            pending(session).any {
                                it.version.organizationId == version.organizationId
                            }
                        )
                            OrganizationReviewContract.fail(OrganizationReviewFailure.PENDING)
                        caller.ensureActive()
                        // This is only client preflight; the existing callable has no
                        // expectedVersion CAS.
                        if (
                            source.read(session, version.organizationId).version != version ||
                                !canSubmit()
                        )
                            OrganizationReviewContract.fail(OrganizationReviewFailure.STALE)
                        ensure(session)
                        caller.ensureActive()
                        var entry =
                            OrganizationReviewPending(
                                OrganizationReviewContract.accountHash(session.uid),
                                version,
                                action,
                                OrganizationReviewContract.hash(normalized),
                                operationId(),
                                session.role,
                                OrganizationReviewPhase.PREPARED,
                            )
                        entry = journal.put(session.uid, entry)
                        if (!caller.isActive || session != authority() || !canSubmit()) {
                            // Only this live invocation knows that no SDK send happened before
                            // DISPATCHED.
                            journal.clear(session.uid, entry)
                            caller.ensureActive()
                            ensure(session)
                            OrganizationReviewContract.fail(OrganizationReviewFailure.STALE)
                        }
                        entry =
                            journal.put(
                                session.uid,
                                entry.copy(phase = OrganizationReviewPhase.DISPATCHED),
                                entry,
                            )
                        val receipt =
                            try {
                                source.send(session, entry, normalized) {
                                    caller.isActive && session == authority() && canSubmit()
                                }
                            } catch (error: Exception) {
                                throw OrganizationReviewException(
                                    OrganizationReviewFailure.UNCONFIRMED,
                                    error,
                                )
                            }
                        // Persist response before any cancellable UI delivery/read. No new send on
                        // recovery.
                        entry =
                            journal.put(
                                session.uid,
                                entry.copy(
                                    phase = OrganizationReviewPhase.ACKNOWLEDGED,
                                    receipt = receipt,
                                ),
                                entry,
                            )
                        ensure(session)
                        val observation = source.reconcile(session, entry)
                        ensure(session)
                        if (observation.confirmed) journal.clear(session.uid, entry)
                        observation
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

    suspend fun reconcile(
        session: ModerationSession,
        entry: OrganizationReviewPending,
    ): OrganizationReviewObservation = operations.withLock {
        ensure(session)
        OrganizationReviewContract.requireOwner(session, entry)
        val result =
            try {
                gate.withSession(session) {
                    withContext(NonCancellable) {
                        ensure(session)
                        if (pending(session).none { it == entry })
                            OrganizationReviewContract.fail(OrganizationReviewFailure.PENDING)
                        val observation = source.reconcile(session, entry)
                        ensure(session)
                        if (observation.confirmed) journal.clear(session.uid, entry)
                        observation
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
}
