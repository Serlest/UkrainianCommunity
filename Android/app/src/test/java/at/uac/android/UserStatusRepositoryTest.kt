package at.uac.android

import at.uac.android.feature.moderation.ModerationDecisionGate
import at.uac.android.feature.moderation.ModerationSession
import at.uac.android.feature.userstatusmanagement.*
import java.time.Instant
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.test.*
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class UserStatusRepositoryTest {
    private val f = UserStatusUnitFixture
    private var live: ModerationSession? = f.actor

    private class Gate : ModerationDecisionGate {
        private val mutex = Mutex()
        var depth = 0
        var calls = 0
        var before: (() -> Unit)? = null

        override suspend fun <T> withSession(
            session: ModerationSession,
            action: suspend () -> T,
        ): T {
            calls++
            before?.invoke()
            return mutex.withLock {
                depth++
                try {
                    withContext(NonCancellable) { action() }
                } finally {
                    depth--
                }
            }
        }
    }

    private class Journal : UserStatusJournal {
        var entries = emptyList<UserStatusPending>()
        val writes = mutableListOf<UserStatusPhase>()
        var clears = 0
        var onPending: (suspend () -> Unit)? = null
        var onPut: ((UserStatusPending) -> Unit)? = null
        var failPhase: UserStatusPhase? = null
        var corruptReadback = false
        var clearFails = false

        override suspend fun pending(uid: String): List<UserStatusPending> {
            onPending?.invoke()
            return entries
        }

        override suspend fun put(
            uid: String,
            entry: UserStatusPending,
            expected: UserStatusPending?,
        ): UserStatusPending {
            if (entry.phase == failPhase) throw IllegalStateException("synthetic durable failure")
            val old = entries.firstOrNull { it.version.targetId == entry.version.targetId }
            check(old == expected)
            check(entry.accountHash == UserStatusContract.accountHash(uid))
            writes += entry.phase
            entries = entries.filterNot { it == old } + entry
            onPut?.invoke(entry)
            return if (corruptReadback) entry.copy(reasonHash = UserStatusContract.hash("corrupt"))
            else entry
        }

        override suspend fun clear(uid: String, expected: UserStatusPending) {
            if (clearFails) throw IllegalStateException("synthetic clear failure")
            check(expected in entries)
            check(expected.accountHash == UserStatusContract.accountHash(uid))
            entries = entries - expected
            clears++
        }
    }

    private class Source(private val gate: Gate) : UserStatusSource {
        private val f = UserStatusUnitFixture
        var fields = f.fields()
        var reads = 0
        var sends = 0
        var tasks = 0
        var reconciles = 0
        var onRead: (suspend () -> Unit)? = null
        var beforeDispatch: (() -> Unit)? = null
        var settle: CompletableDeferred<Unit>? = null
        var sendFailure: Exception? = null
        var onSettled: (() -> Unit)? = null
        var onReconcile: (suspend () -> Unit)? = null
        var overrideObservation: UserStatusObservation? = null
        var lastReceipt: UserStatusReceipt? = null
        val changes = MutableSharedFlow<Unit>()

        override suspend fun read(
            session: ModerationSession,
            targetId: String,
        ): UserStatusSnapshot {
            check(gate.depth == 1)
            reads++
            onRead?.invoke()
            return UserStatusContract.snapshot(targetId, fields)
        }

        override fun changes(session: ModerationSession, targetId: String) = changes.map { it }

        override suspend fun send(
            session: ModerationSession,
            entry: UserStatusPending,
            reason: String,
            until: Instant?,
            canDispatch: () -> Boolean,
        ): UserStatusReceipt {
            check(gate.depth == 1 && entry.phase == UserStatusPhase.DISPATCHED)
            sends++
            beforeDispatch?.invoke()
            if (!canDispatch()) throw UserStatusException(UserStatusFailure.STALE)
            check(UserStatusContract.hash(reason) == entry.reasonHash)
            check(UserStatusContract.untilHash(until) == entry.untilHash)
            tasks++
            settle?.await()
            sendFailure?.let { throw it }
            val receipt = UserStatusContract.receipt(entry, f.response(entry))
            fields = f.after(entry)
            onSettled?.invoke()
            lastReceipt = receipt
            return receipt
        }

        override suspend fun reconcile(
            session: ModerationSession,
            entry: UserStatusPending,
        ): UserStatusObservation {
            check(gate.depth == 1)
            reconciles++
            onReconcile?.invoke()
            return overrideObservation ?: UserStatusContract.observation(entry, session.uid, fields)
        }
    }

    private data class Harness(
        val repo: UserStatusRepository,
        val source: Source,
        val journal: Journal,
        val gate: Gate,
    )

    private fun harness(): Harness {
        val gate = Gate()
        val source = Source(gate)
        val journal = Journal()
        return Harness(
            UserStatusRepository(source, journal, { live }, gate, { f.now }, { f.operation }),
            source,
            journal,
            gate,
        )
    }

    private suspend fun execute(h: Harness, canSubmit: () -> Boolean = { true }) =
        h.repo.execute(
            f.actor,
            UserStatusContract.snapshot(f.target, f.fields()).version,
            UserStatusAction.WARN,
            f.reason,
            zoneId = f.zone,
            canSubmit = canSubmit,
        )

    private suspend fun fails(expected: UserStatusFailure, action: suspend () -> Any?) {
        try {
            action()
            fail("Expected rejection")
        } catch (error: UserStatusException) {
            assertEquals(expected, error.failure)
        }
    }

    @Test
    fun successfulOperationPersistsEveryPhaseBeforeReadbackWithOneTask() = runTest {
        val h = harness()
        h.source.onReconcile = {
            assertEquals(UserStatusPhase.ACKNOWLEDGED, h.journal.entries.single().phase)
        }
        assertEquals(UserStatusObservation.CONFIRMED_CURRENT, execute(h))
        assertEquals(UserStatusPhase.entries, h.journal.writes)
        assertEquals(1, h.source.tasks)
        assertEquals(1, h.source.reconciles)
        assertTrue(h.journal.entries.isEmpty())
        assertEquals(0, h.gate.depth)
    }

    @Test
    fun originalCallerCancelledOnGateEntryCreatesNoJournalOrSourceRead() = runTest {
        val h = harness()
        lateinit var job: Job
        h.gate.before = { job.cancel() }
        job = launch(start = CoroutineStart.LAZY) { execute(h) }
        job.start()
        job.join()
        assertTrue(job.isCancelled)
        assertTrue(h.journal.writes.isEmpty())
        assertEquals(0, h.source.reads)
        assertEquals(0, h.source.tasks)
    }

    @Test
    fun originalCancellationDuringPendingDiscoveryCreatesNoJournalOrRead() = runTest {
        val h = harness()
        lateinit var job: Job
        h.journal.onPending = { job.cancel() }
        job = launch(start = CoroutineStart.LAZY) { execute(h) }
        job.start()
        job.join()
        assertTrue(h.journal.writes.isEmpty())
        assertEquals(0, h.source.reads)
        assertEquals(0, h.source.tasks)
    }

    @Test
    fun originalCancellationDuringFreshPreflightCreatesNoJournalOrSend() = runTest {
        val h = harness()
        lateinit var job: Job
        h.source.onRead = { job.cancel() }
        job = launch(start = CoroutineStart.LAZY) { execute(h) }
        job.start()
        job.join()
        assertTrue(h.journal.writes.isEmpty())
        assertEquals(0, h.source.tasks)
    }

    @Test
    fun actorRevisionOrReadinessLossDuringPreflightCreatesNoJournalOrSend() = runTest {
        for (changed in
            listOf(
                f.actor.copy(revision = 18),
                f.actor.copy(ready = false),
                f.actor.copy(role = "user"),
            )) {
            live = f.actor
            val h = harness()
            h.source.onRead = { live = changed }
            val job = launch {
                execute(h)
                fail("Stale actor escaped")
            }
            job.join()
            assertTrue(job.isCancelled)
            assertTrue(h.journal.writes.isEmpty())
            assertEquals(0, h.source.tasks)
        }
    }

    @Test
    fun cancellationImmediatelyBeforePreparedPersistenceWritesNothing() = runTest {
        val gate = Gate()
        val source = Source(gate)
        val journal = Journal()
        lateinit var job: Job
        val repo =
            UserStatusRepository(
                source,
                journal,
                { live },
                gate,
                { f.now },
                {
                    job.cancel()
                    f.operation
                },
            )
        job =
            launch(start = CoroutineStart.LAZY) {
                repo.execute(
                    f.actor,
                    f.prepared().version,
                    UserStatusAction.WARN,
                    f.reason,
                    canSubmit = { true },
                )
            }
        job.start()
        job.join()
        assertTrue(journal.writes.isEmpty())
        assertEquals(0, source.tasks)
    }

    @Test
    fun cancellationAfterPreparedClearsOnlyTheKnownUndispatchedEntry() = runTest {
        val h = harness()
        lateinit var job: Job
        h.journal.onPut = { if (it.phase == UserStatusPhase.PREPARED) job.cancel() }
        job = launch(start = CoroutineStart.LAZY) { execute(h) }
        job.start()
        job.join()
        assertEquals(listOf(UserStatusPhase.PREPARED), h.journal.writes)
        assertEquals(1, h.journal.clears)
        assertTrue(h.journal.entries.isEmpty())
        assertEquals(0, h.source.tasks)
    }

    @Test
    fun cancellationAfterDispatchedRetainsPendingWithoutCallingSource() = runTest {
        val h = harness()
        lateinit var job: Job
        h.journal.onPut = { if (it.phase == UserStatusPhase.DISPATCHED) job.cancel() }
        job = launch(start = CoroutineStart.LAZY) { execute(h) }
        job.start()
        job.join()
        assertEquals(UserStatusPhase.DISPATCHED, h.journal.entries.single().phase)
        assertEquals(0, h.source.sends)
        assertEquals(0, h.source.tasks)
        assertEquals(0, h.journal.clears)
    }

    @Test
    fun callerCancellationDoesNotDetachActualSettlementAndReceiptPersistence() = runTest {
        val h = harness()
        val settlement = CompletableDeferred<Unit>()
        h.source.settle = settlement
        val job = launch { execute(h) }
        runCurrent()
        assertEquals(1, h.source.tasks)
        job.cancel()
        runCurrent()
        assertFalse(job.isCompleted)
        assertEquals(1, h.gate.depth)
        settlement.complete(Unit)
        job.join()
        assertEquals(UserStatusPhase.ACKNOWLEDGED, h.journal.entries.single().phase)
        assertNotNull(h.journal.entries.single().receipt)
        assertEquals(0, h.source.reconciles)
        assertEquals(0, h.gate.depth)
    }

    @Test
    fun accountSwitchDuringSettlementPersistsOldReceiptAndDoesNotReadAsNewUser() = runTest {
        val h = harness()
        val settlement = CompletableDeferred<Unit>()
        h.source.settle = settlement
        val job = launch { execute(h) }
        runCurrent()
        live = f.actor.copy(uid = "other-account", revision = 18)
        settlement.complete(Unit)
        job.join()
        assertTrue(job.isCancelled)
        assertEquals(
            UserStatusContract.accountHash(f.actor.uid),
            h.journal.entries.single().accountHash,
        )
        assertEquals(UserStatusPhase.ACKNOWLEDGED, h.journal.entries.single().phase)
        assertEquals(0, h.source.reconciles)
    }

    @Test
    fun targetRoleOrAcknowledgementChangeBeforeDispatchVetoesWithoutJournal() = runTest {
        for (fields in
            listOf(
                f.fields() + ("globalRole" to "owner"),
                f.fields() + ("statusAcknowledgedAt" to f.now),
            )) {
            val h = harness()
            h.source.fields = fields
            fails(UserStatusFailure.STALE) { execute(h) }
            assertTrue(h.journal.writes.isEmpty())
            assertEquals(0, h.source.tasks)
        }
    }

    @Test
    fun livePresentationVetoBeforeAndAfterPreparedPreventsSending() = runTest {
        val early = harness()
        fails(UserStatusFailure.STALE) { execute(early) { false } }
        assertEquals(0, early.source.reads)
        val late = harness()
        var allowed = true
        late.journal.onPut = { if (it.phase == UserStatusPhase.PREPARED) allowed = false }
        fails(UserStatusFailure.STALE) { execute(late) { allowed } }
        assertTrue(late.journal.entries.isEmpty())
        assertEquals(0, late.source.tasks)
    }

    @Test
    fun finalSourceCanDispatchVetoLeavesConservativePendingAndZeroTasks() = runTest {
        val h = harness()
        var allowed = true
        h.source.beforeDispatch = { allowed = false }
        fails(UserStatusFailure.UNCONFIRMED) { execute(h) { allowed } }
        assertEquals(1, h.source.sends)
        assertEquals(0, h.source.tasks)
        assertEquals(UserStatusPhase.DISPATCHED, h.journal.entries.single().phase)
    }

    @Test
    fun concurrentDoubleTapIsRejectedRatherThanQueuedForResend() = runTest {
        val h = harness()
        val settlement = CompletableDeferred<Unit>()
        h.source.settle = settlement
        val first = async { execute(h) }
        runCurrent()
        fails(UserStatusFailure.PENDING) { execute(h) }
        assertEquals(1, h.source.tasks)
        settlement.complete(Unit)
        assertEquals(UserStatusObservation.CONFIRMED_CURRENT, first.await())
        assertEquals(1, h.source.tasks)
    }

    @Test
    fun preparedAndDispatchedPersistenceFailuresNeverStartSdkTask() = runTest {
        for (phase in listOf(UserStatusPhase.PREPARED, UserStatusPhase.DISPATCHED)) {
            val h = harness()
            h.journal.failPhase = phase
            fails(UserStatusFailure.JOURNAL) { execute(h) }
            assertEquals(0, h.source.tasks)
        }
    }

    @Test
    fun corruptPreparedReadbackNeverDispatches() = runTest {
        val h = harness()
        h.journal.corruptReadback = true
        fails(UserStatusFailure.JOURNAL) { execute(h) }
        assertEquals(0, h.source.tasks)
        assertEquals(UserStatusPhase.PREPARED, h.journal.entries.single().phase)
    }

    @Test
    fun receiptPersistenceFailureRetainsDispatchedWithoutReadbackOrRetry() = runTest {
        val h = harness()
        h.journal.failPhase = UserStatusPhase.ACKNOWLEDGED
        fails(UserStatusFailure.JOURNAL) { execute(h) }
        assertEquals(1, h.source.tasks)
        assertEquals(0, h.source.reconciles)
        assertEquals(UserStatusPhase.DISPATCHED, h.journal.entries.single().phase)
        h.journal.failPhase = null
        fails(UserStatusFailure.PENDING) { execute(h) }
        assertEquals(1, h.source.tasks)
    }

    @Test
    fun unknownTransportOutcomeRetainsPendingAndNeverAutomaticallyRepeats() = runTest {
        val h = harness()
        h.source.sendFailure = UserStatusException(UserStatusFailure.OFFLINE)
        fails(UserStatusFailure.UNCONFIRMED) { execute(h) }
        val pending = h.journal.entries.single()
        assertEquals(UserStatusObservation.UNCONFIRMED, h.repo.reconcile(f.actor, pending))
        fails(UserStatusFailure.PENDING) { execute(h) }
        assertEquals(1, h.source.tasks)
    }

    @Test
    fun observedStateWithoutReceiptCannotClearJournalEvenAfterColdRecovery() = runTest {
        val h = harness()
        val entry = f.prepared().copy(phase = UserStatusPhase.DISPATCHED)
        h.journal.entries = listOf(entry)
        h.source.fields = f.after(entry)
        assertEquals(
            UserStatusObservation.OBSERVED_WITHOUT_RECEIPT,
            h.repo.reconcile(f.actor, entry),
        )
        assertEquals(listOf(entry), h.journal.entries)
        assertEquals(0, h.source.tasks)
    }

    @Test
    fun sourceCannotFabricateOwnAcceptanceWithoutPersistedReceipt() = runTest {
        val h = harness()
        val entry = f.prepared()
        h.journal.entries = listOf(entry)
        h.source.overrideObservation = UserStatusObservation.CONFIRMED_CURRENT
        fails(UserStatusFailure.UNCONFIRMED) { h.repo.reconcile(f.actor, entry) }
        assertEquals(listOf(entry), h.journal.entries)
    }

    @Test
    fun confirmedLaterStateChangeClearsWithoutSendingAgain() = runTest {
        val h = harness()
        h.source.onSettled = {
            h.source.fields = h.source.fields + ("statusAcknowledgedAt" to f.now.plusSeconds(4))
        }
        assertEquals(UserStatusObservation.CONFIRMED_CHANGED, execute(h))
        assertEquals(1, h.source.tasks)
        assertTrue(h.journal.entries.isEmpty())
    }

    @Test
    fun acknowledgedReadbackTimeoutPreservesAcceptanceAndJournalForReadOnlyRecovery() = runTest {
        val h = harness()
        h.source.onReconcile = { withTimeout(1) { delay(2) } }
        assertEquals(UserStatusObservation.CONFIRMED_UNAVAILABLE, execute(h))
        assertEquals(UserStatusPhase.ACKNOWLEDGED, h.journal.entries.single().phase)
        h.source.onReconcile = null
        assertEquals(
            UserStatusObservation.CONFIRMED_CURRENT,
            h.repo.reconcile(f.actor, h.journal.entries.single()),
        )
        assertEquals(1, h.source.tasks)
        assertTrue(h.journal.entries.isEmpty())
    }

    @Test
    fun preflightAndStandaloneTimeoutsAreTypedOfflineNotExternalCancellation() = runTest {
        val h = harness()
        h.source.onRead = { withTimeout(1) { delay(2) } }
        fails(UserStatusFailure.OFFLINE) { execute(h) }
        assertTrue(h.journal.entries.isEmpty())
        val entry = f.prepared()
        h.journal.entries = listOf(entry)
        h.source.onReconcile = { withTimeout(1) { delay(2) } }
        fails(UserStatusFailure.OFFLINE) { h.repo.reconcile(f.actor, entry) }
        assertEquals(listOf(entry), h.journal.entries)
    }

    @Test
    fun staleJournalReadAndChangesCannotEscapeIntoAnotherAccount() = runTest {
        val h = harness()
        h.journal.onPending = { live = f.actor.copy(revision = 18) }
        val read = launch {
            h.repo.pending(f.actor)
            fail("Stale result escaped")
        }
        read.join()
        assertTrue(read.isCancelled)
        live = f.actor
        val watch = launch {
            h.repo.changes(f.actor, f.target).collect { fail("Stale event escaped") }
        }
        runCurrent()
        live = f.actor.copy(uid = "other-account", revision = 19)
        h.source.changes.emit(Unit)
        watch.join()
        assertTrue(watch.isCancelled)
    }

    @Test
    fun cancelledReadConsumerNeverReceivesTheNonCancellableGateResult() = runTest {
        val h = harness()
        val release = CompletableDeferred<Unit>()
        h.source.onRead = { release.await() }
        var exposed = false
        val job = launch {
            h.repo.read(f.actor, f.target)
            exposed = true
        }
        runCurrent()
        job.cancel()
        runCurrent()
        assertFalse(job.isCompleted)
        assertEquals(1, h.gate.depth)
        release.complete(Unit)
        job.join()
        assertFalse(exposed)
        assertEquals(0, h.gate.depth)
    }

    @Test
    fun standaloneReconcileCancellationStillWaitsForActualReadSettlement() = runTest {
        val h = harness()
        val entry = f.prepared()
        h.journal.entries = listOf(entry)
        val release = CompletableDeferred<Unit>()
        h.source.onReconcile = { release.await() }
        var exposed = false
        val job = launch {
            h.repo.reconcile(f.actor, entry)
            exposed = true
        }
        runCurrent()
        job.cancel()
        runCurrent()
        assertFalse(job.isCompleted)
        assertEquals(1, h.gate.depth)
        release.complete(Unit)
        job.join()
        assertFalse(exposed)
        assertEquals(0, h.gate.depth)
        assertEquals(listOf(entry), h.journal.entries)
    }

    @Test
    fun privilegedRoleChangeMayOnlyReconcileAnExistingOwnReceipt() = runTest {
        val h = harness()
        val owner = f.actor.copy(role = "owner")
        val prepared =
            UserStatusContract.prepared(
                    owner,
                    UserStatusContract.snapshot(f.target, f.fields()),
                    UserStatusAction.WARN,
                    f.reason,
                    null,
                    f.operation,
                )
                .copy(phase = UserStatusPhase.DISPATCHED)
        val entry =
            prepared.copy(
                phase = UserStatusPhase.ACKNOWLEDGED,
                receipt = UserStatusContract.receipt(prepared, f.response(prepared)),
            )
        h.journal.entries = listOf(entry)
        h.source.fields = f.after(entry)
        live = f.actor.copy(revision = 20)
        assertEquals(UserStatusObservation.CONFIRMED_CURRENT, h.repo.reconcile(live!!, entry))
        assertEquals(0, h.source.tasks)
        assertTrue(h.journal.entries.isEmpty())
    }

    @Test
    fun noReadyNoManagerAndOwnTargetCannotStartAnOperation() = runTest {
        val h = harness()
        for (actor in listOf(f.actor.copy(ready = false), f.actor.copy(role = "user"))) {
            live = actor
            fails(UserStatusFailure.ACCESS) {
                h.repo.execute(
                    actor,
                    f.prepared().version,
                    UserStatusAction.WARN,
                    f.reason,
                    canSubmit = { true },
                )
            }
        }
        live = f.actor.copy(uid = f.target)
        fails(UserStatusFailure.ACCESS) {
            h.repo.execute(
                live!!,
                f.prepared().version,
                UserStatusAction.WARN,
                f.reason,
                canSubmit = { true },
            )
        }
        assertEquals(0, h.source.tasks)
        assertTrue(h.journal.entries.isEmpty())
    }

    @Test
    fun malformedDuplicateOrForeignPendingEntriesAreNotExposed() = runTest {
        val h = harness()
        val entry = f.prepared()
        h.journal.entries = listOf(entry, entry)
        fails(UserStatusFailure.JOURNAL) { h.repo.pending(f.actor) }
        h.journal.entries =
            listOf(entry.copy(accountHash = UserStatusContract.accountHash("foreign")))
        fails(UserStatusFailure.ACCESS) { h.repo.pending(f.actor) }
        h.journal.entries = List(17) { entry }
        fails(UserStatusFailure.JOURNAL) { h.repo.pending(f.actor) }
    }

    @Test
    fun fullBoundedJournalVetoesAnotherTargetBeforeAnySourceRead() = runTest {
        val h = harness()
        h.journal.entries =
            List(UserStatusContract.MAX_PENDING) { index ->
                val target = "synthetic-existing-$index"
                UserStatusContract.prepared(
                    f.actor,
                    UserStatusContract.snapshot(target, f.fields()),
                    UserStatusAction.WARN,
                    f.reason,
                    null,
                    "0a0a0a0a-1111-4222-8333-${index.toString().padStart(12, '0')}",
                )
            }
        fails(UserStatusFailure.PENDING) { execute(h) }
        assertEquals(0, h.source.reads)
        assertEquals(0, h.source.tasks)
        assertTrue(h.journal.writes.isEmpty())
    }

    @Test
    fun journalClearFailureRetainsAcknowledgedStateWithoutRepeatingTask() = runTest {
        val h = harness()
        h.journal.clearFails = true
        fails(UserStatusFailure.JOURNAL) { execute(h) }
        assertEquals(UserStatusPhase.ACKNOWLEDGED, h.journal.entries.single().phase)
        assertEquals(1, h.source.tasks)
    }
}
