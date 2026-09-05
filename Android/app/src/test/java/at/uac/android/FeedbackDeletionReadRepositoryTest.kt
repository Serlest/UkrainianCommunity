package at.uac.android

import at.uac.android.feature.feedback.FeedbackAudience
import at.uac.android.feature.feedbackdeletion.*
import at.uac.android.feature.moderation.ModerationDecisionGate
import at.uac.android.feature.moderation.ModerationSession
import java.io.IOException
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.*
import kotlinx.coroutines.test.*
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class FeedbackDeletionReadRepositoryTest {
    private val actor = ModerationSession("review-owner", 4, "owner", true)
    private val audience = FeedbackAudience.MANAGEMENT
    private val id = "review-target"
    private val fields =
        mapOf(
            "userId" to "private-author",
            "userDisplayName" to "PRIVATE NAME",
            "message" to "PRIVATE MESSAGE",
            "subject" to "PRIVATE SUBJECT",
            "type" to "question",
            "status" to "open",
            "createdAt" to Instant.parse("2026-09-03T17:00:00.000000001Z"),
        )

    private fun snapshot(target: String = id, extra: Map<String, Any?> = emptyMap()) =
        FeedbackDeletionRecovery.snapshot(target, fields + extra)

    private fun entry(target: String = id, owner: ModerationSession = actor) =
        FeedbackDeletionRecovery.prepared(
            owner,
            audience,
            snapshot(target),
            UUID.randomUUID().toString(),
        )

    private fun ack(entry: FeedbackDeletionPending): FeedbackDeletionPending {
        val dispatched = entry.copy(phase = FeedbackDeletionPhase.DISPATCHED)
        return dispatched.copy(
            phase = FeedbackDeletionPhase.ACKNOWLEDGED,
            receipt = FeedbackDeletionRecovery.receipt(dispatched, mapOf("deletedCount" to 1)),
        )
    }

    private class Gate : ModerationDecisionGate {
        var before: (suspend () -> Unit)? = null
        var depth = 0

        override suspend fun <T> withSession(
            session: ModerationSession,
            action: suspend () -> T,
        ): T =
            withContext(NonCancellable) {
                before?.invoke()
                depth++
                try {
                    action()
                } finally {
                    depth--
                }
            }
    }

    private class Journal : FeedbackDeletionJournal {
        var entries: List<FeedbackDeletionPending> = emptyList()
        var reads = 0
        var writes = 0
        var clears = 0
        var before: (suspend () -> Unit)? = null

        override suspend fun pending(uid: String): List<FeedbackDeletionPending> {
            reads++
            before?.invoke()
            return entries
        }

        override suspend fun put(
            uid: String,
            entry: FeedbackDeletionPending,
            expected: FeedbackDeletionPending?,
        ): FeedbackDeletionPending {
            writes++
            error("Read-only coordinator must not write")
        }

        override suspend fun clear(uid: String, expected: FeedbackDeletionPending) {
            clears++
            error("Read-only coordinator must not clear")
        }
    }

    private inner class Harness {
        var live: ModerationSession? = actor
        val gate = Gate()
        val journal = Journal()
        var reads = 0
        var beforeRead: (suspend () -> Unit)? = null
        var result: FeedbackDeletionRead = FeedbackDeletionRead.Present(snapshot())
        val repo =
            FeedbackDeletionReadRepository(
                FeedbackDeletionReadSource { session, target ->
                    check(gate.depth == 1 && session == actor && target == id)
                    reads++
                    beforeRead?.invoke()
                    result
                },
                journal,
                { live },
                gate,
            )

        suspend fun review(canReview: () -> Boolean = { true }) =
            repo.review(actor, audience, snapshot().version, canReview)

        suspend fun reconcile(entry: FeedbackDeletionPending) =
            repo.reconcile(actor, audience, entry)

        fun readOnly() {
            assertEquals(0, journal.writes)
            assertEquals(0, journal.clears)
        }
    }

    private suspend fun denied(failure: FeedbackDeletionFailure, action: suspend () -> Any?) {
        val error =
            try {
                action()
                null
            } catch (error: Throwable) {
                error
            }
        assertTrue(
            "Expected $failure, got ${error?.javaClass?.simpleName}",
            error is FeedbackDeletionException,
        )
        assertEquals(failure, (error as FeedbackDeletionException).failure)
    }

    private suspend fun cancelled(action: suspend () -> Any?) {
        val error =
            try {
                action()
                null
            } catch (error: Throwable) {
                error
            }
        assertTrue(error is CancellationException)
    }

    @Test
    fun freshReviewReturnsExactSnapshotWithoutAllocatingOrWriting() = runTest {
        val h = Harness()
        assertEquals(snapshot(), h.review())
        assertEquals(1, h.reads)
        assertEquals(2, h.journal.reads)
        assertTrue(h.journal.entries.isEmpty())
        h.readOnly()
    }

    @Test
    fun ownerAuthoredClosedAndDsaLinkedRecordsRemainReviewable() = runTest {
        val h = Harness()
        val own =
            snapshot(
                extra = mapOf("userId" to actor.uid, "status" to "closed", "hasDsaCase" to true)
            )
        h.result = FeedbackDeletionRead.Present(own)
        assertEquals(own, h.repo.review(actor, audience, own.version) { true })
        h.readOnly()
    }

    @Test
    fun wrongRoleNotReadyMalformedAndObsoleteSessionsCannotRead() = runTest {
        for (session in
            listOf(
                actor.copy(role = "admin"),
                actor.copy(ready = false),
                actor.copy(uid = "bad/id"),
                actor.copy(revision = -1),
            )) {
            val h = Harness()
            h.live = session
            denied(FeedbackDeletionFailure.ACCESS) { h.repo.read(session, audience, id) }
            assertEquals(0, h.reads)
        }
        val h = Harness()
        h.live = actor.copy(revision = 5)
        cancelled { h.repo.read(actor, audience, id) }
        assertEquals(0, h.reads)
    }

    @Test
    fun nonManagementAudienceRejectedBeforeAnySourceOrJournalRead() = runTest {
        for (other in FeedbackAudience.entries.filter { it != audience }) {
            val h = Harness()
            denied(FeedbackDeletionFailure.ACCESS) { h.repo.read(actor, other, id) }
            denied(FeedbackDeletionFailure.ACCESS) {
                h.repo.review(actor, other, snapshot().version) { true }
            }
            denied(FeedbackDeletionFailure.ACCESS) { h.repo.reconcile(actor, other, entry()) }
            assertEquals(0, h.reads)
            assertEquals(0, h.journal.reads)
        }
    }

    @Test
    fun invalidTargetAndVersionNeverReachSource() = runTest {
        val h = Harness()
        denied(FeedbackDeletionFailure.INVALID) { h.repo.read(actor, audience, "bad/id") }
        denied(FeedbackDeletionFailure.INVALID) {
            h.repo.review(
                actor,
                audience,
                snapshot().version.copy(fingerprint = "bad"),
            ) {
                true
            }
        }
        assertEquals(0, h.reads)
        h.readOnly()
    }

    @Test
    fun explicitAbsenceAndUnavailableHaveDifferentReviewFailures() = runTest {
        val h = Harness()
        h.result = FeedbackDeletionRead.Absent
        assertEquals(FeedbackDeletionRead.Absent, h.repo.read(actor, audience, id))
        denied(FeedbackDeletionFailure.MISSING) { h.review() }
        h.result = FeedbackDeletionRead.Unavailable
        assertEquals(FeedbackDeletionRead.Unavailable, h.repo.read(actor, audience, id))
        denied(FeedbackDeletionFailure.OFFLINE) { h.review() }
        h.readOnly()
    }

    @Test
    fun mismatchedTargetProjectionAndVersionFailClosed() = runTest {
        val h = Harness()
        h.result = FeedbackDeletionRead.Present(snapshot("foreign-target"))
        denied(FeedbackDeletionFailure.STALE) { h.repo.read(actor, audience, id) }
        h.result =
            FeedbackDeletionRead.Present(
                snapshot().copy(target = snapshot("foreign-target").target)
            )
        denied(FeedbackDeletionFailure.INVALID) { h.repo.read(actor, audience, id) }
        h.result = FeedbackDeletionRead.Present(snapshot(extra = mapOf("unshownField" to 1)))
        denied(FeedbackDeletionFailure.STALE) { h.review() }
        h.readOnly()
    }

    @Test
    fun selectionLossBeforeAndDuringReadCannotReturnReview() = runTest {
        val h = Harness()
        denied(FeedbackDeletionFailure.STALE) { h.review { false } }
        assertEquals(0, h.reads)
        var selected = true
        h.beforeRead = { selected = false }
        denied(FeedbackDeletionFailure.STALE) { h.review { selected } }
        h.readOnly()
    }

    @Test
    fun selectionLossDuringEitherJournalReadStopsReview() = runTest {
        for (stopAt in listOf(1, 2)) {
            val h = Harness()
            var selected = true
            h.journal.before = { if (h.journal.reads == stopAt) selected = false }
            denied(FeedbackDeletionFailure.STALE) { h.review { selected } }
            assertEquals(stopAt - 1, h.reads)
            h.readOnly()
        }
    }

    @Test
    fun sameTargetPendingAllPhasesBlockReviewWithoutRead() = runTest {
        val original = entry()
        for (pending in
            listOf(
                original,
                original.copy(phase = FeedbackDeletionPhase.DISPATCHED),
                ack(original),
            )) {
            val h = Harness()
            h.journal.entries = listOf(pending)
            denied(FeedbackDeletionFailure.PENDING) { h.review() }
            assertEquals(0, h.reads)
            assertEquals(listOf(pending), h.journal.entries)
            h.readOnly()
        }
    }

    @Test
    fun fullJournalBlocksButUnrelatedPendingDoesNot() = runTest {
        val h = Harness()
        h.journal.entries = List(16) { entry("target-$it") }
        denied(FeedbackDeletionFailure.PENDING) { h.review() }
        assertEquals(0, h.reads)
        h.journal.entries = h.journal.entries.take(15)
        assertEquals(snapshot(), h.review())
        h.readOnly()
    }

    @Test
    fun pendingAppearingDuringReadBlocksFreshReview() = runTest {
        val h = Harness()
        val pending = entry()
        h.beforeRead = { h.journal.entries = listOf(pending) }
        denied(FeedbackDeletionFailure.PENDING) { h.review() }
        assertEquals(listOf(pending), h.journal.entries)
        h.readOnly()
    }

    @Test
    fun corruptForeignDuplicateAndOversizedJournalNeverBecomeEmpty() = runTest {
        val first = entry()
        for (entries in
            listOf(
                listOf(first.copy(accountHash = "a".repeat(64))),
                listOf(first, first),
                listOf(first, entry("another").copy(operationId = first.operationId)),
                List(17) { entry("target-$it") },
                listOf(first.copy(backend = "foreign")),
                listOf(first.copy(phase = FeedbackDeletionPhase.ACKNOWLEDGED)),
            )) {
            val h = Harness()
            h.journal.entries = entries
            denied(FeedbackDeletionFailure.JOURNAL) { h.repo.pending(actor) }
            denied(FeedbackDeletionFailure.JOURNAL) { h.review() }
            assertEquals(0, h.reads)
            assertEquals(entries, h.journal.entries)
            h.readOnly()
        }
    }

    @Test
    fun pendingReturnsDetachedListAndJournalIoIsNotAnEmptyList() = runTest {
        val h = Harness()
        val mutable = mutableListOf(entry())
        h.journal.entries = mutable
        val captured = h.repo.pending(actor)
        mutable.clear()
        assertEquals(1, captured.size)
        h.journal.before = { throw IOException("synthetic disk fault") }
        denied(FeedbackDeletionFailure.JOURNAL) { h.repo.pending(actor) }
        h.readOnly()
    }

    @Test
    fun sourceIoTimeoutAndUnexpectedFailuresNeverImplyAbsence() = runTest {
        val h = Harness()
        h.beforeRead = { throw IOException("synthetic connection fault") }
        denied(FeedbackDeletionFailure.OFFLINE) { h.repo.read(actor, audience, id) }
        h.beforeRead = { withTimeout(1) { delay(2) } }
        denied(FeedbackDeletionFailure.OFFLINE) { h.review() }
        h.beforeRead = { throw IllegalStateException("synthetic source fault") }
        denied(FeedbackDeletionFailure.UNCONFIRMED) { h.repo.read(actor, audience, id) }
        h.readOnly()
    }

    @Test
    fun permissionAndTypedMissingErrorsNeverBecomeAbsentRecovery() = runTest {
        for (failure in
            listOf(
                FeedbackDeletionFailure.ACCESS,
                FeedbackDeletionFailure.MISSING,
                FeedbackDeletionFailure.INVALID,
                FeedbackDeletionFailure.UNCONFIRMED,
            )) {
            val h = Harness()
            val pending = ack(entry())
            h.journal.entries = listOf(pending)
            h.beforeRead = { throw FeedbackDeletionException(failure) }
            denied(failure) { h.reconcile(pending) }
            assertEquals(listOf(pending), h.journal.entries)
            h.readOnly()
        }
    }

    @Test
    fun recoveryMatrixNeverClearsWritesOrReplays() = runTest {
        val original = entry()
        for (pending in
            listOf(
                original,
                original.copy(phase = FeedbackDeletionPhase.DISPATCHED),
                ack(original),
            )) {
            for (read in
                listOf(
                    FeedbackDeletionRead.Absent,
                    FeedbackDeletionRead.Unavailable,
                    FeedbackDeletionRead.Present(snapshot()),
                    FeedbackDeletionRead.Present(snapshot(extra = mapOf("message" to "later"))),
                )) {
                val h = Harness()
                h.journal.entries = listOf(pending)
                h.result = read
                val observed = h.reconcile(pending)
                assertEquals(
                    FeedbackDeletionRecovery.observation(pending, actor.uid, read),
                    observed,
                )
                assertFalse(observed.allowsReplay)
                assertFalse(observed.clearsPending)
                assertEquals(listOf(pending), h.journal.entries)
                assertEquals(1, h.reads)
                h.readOnly()
            }
        }
    }

    @Test
    fun offlineRecoveryKeepsOwnReceiptDistinctFromUnknown() = runTest {
        for (pending in listOf(entry(), ack(entry()))) {
            val h = Harness()
            h.journal.entries = listOf(pending)
            h.beforeRead = { throw IOException("offline") }
            assertEquals(
                if (pending.receipt == null) FeedbackDeletionObservation.UNAVAILABLE
                else FeedbackDeletionObservation.ACCEPTED_UNAVAILABLE,
                h.reconcile(pending),
            )
            h.readOnly()
        }
    }

    @Test
    fun recoveryRequiresExactDurableEntryBeforeAndAfterRead() = runTest {
        val h = Harness()
        val original = entry()
        denied(FeedbackDeletionFailure.PENDING) { h.reconcile(original) }
        assertEquals(0, h.reads)
        h.journal.entries = listOf(original)
        h.beforeRead = { h.journal.entries = listOf(ack(original)) }
        denied(FeedbackDeletionFailure.PENDING) { h.reconcile(original) }
        assertEquals(listOf(ack(original)), h.journal.entries)
        h.readOnly()
    }

    @Test
    fun foreignRecoveryEntryDeniedBeforeSourceAndJournalAccess() = runTest {
        val h = Harness()
        denied(FeedbackDeletionFailure.ACCESS) {
            h.reconcile(entry(owner = actor.copy(uid = "other-owner")))
        }
        assertEquals(0, h.reads)
        assertEquals(0, h.journal.reads)
    }

    @Test
    fun scopeLossWhileWaitingForNonCancellableGatePreventsAllIo() = runTest {
        val h = Harness()
        h.gate.before = { h.live = null }
        cancelled { h.review() }
        assertEquals(0, h.reads)
        assertEquals(0, h.journal.reads)
    }

    @Test
    fun cancellationWhileWaitingForNonCancellableGatePreventsAllIo() = runTest {
        val h = Harness()
        val release = CompletableDeferred<Unit>()
        h.gate.before = { release.await() }
        val job = async { h.review() }
        runCurrent()
        job.cancel()
        release.complete(Unit)
        job.join()
        assertTrue(job.isCancelled)
        assertEquals(0, h.reads)
        assertEquals(0, h.journal.reads)
    }

    @Test
    fun sourceResultAfterCallerCancellationCannotReturnOrReconcile() = runTest {
        val h = Harness()
        val release = CompletableDeferred<Unit>()
        h.beforeRead = { release.await() }
        val job = async { h.review() }
        runCurrent()
        assertEquals(1, h.reads)
        job.cancel()
        release.complete(Unit)
        job.join()
        assertTrue(job.isCancelled)
        assertEquals(1, h.journal.reads)
        h.readOnly()
    }

    @Test
    fun accountRevisionRoleAndReadyLossRejectLatePrivateResults() = runTest {
        for (next in
            listOf(
                null,
                actor.copy(uid = "other-owner"),
                actor.copy(revision = 5),
                actor.copy(role = "admin"),
                actor.copy(ready = false),
            )) {
            val h = Harness()
            h.beforeRead = { h.live = next }
            cancelled { h.review() }
            assertEquals(1, h.journal.reads)
            h.readOnly()
        }
    }

    @Test
    fun scopeLossDuringJournalReadRejectsPendingAndRecovery() = runTest {
        val h = Harness()
        h.journal.entries = listOf(entry())
        h.journal.before = { h.live = null }
        cancelled { h.repo.pending(actor) }
        h.live = actor
        cancelled { h.reconcile(h.journal.entries.single()) }
        assertEquals(0, h.reads)
        h.readOnly()
    }

    @Test
    fun cancellationAndScopeLossTakePrecedenceOverLateReadErrors() = runTest {
        val h = Harness()
        h.beforeRead = {
            h.live = null
            throw IOException("late failure")
        }
        cancelled { h.repo.read(actor, audience, id) }
        h.live = actor
        h.beforeRead = { throw CancellationException("caller cancelled") }
        cancelled { h.review() }
        h.readOnly()
    }
}
