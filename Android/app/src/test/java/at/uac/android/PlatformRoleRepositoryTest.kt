package at.uac.android

import at.uac.android.feature.moderation.ModerationDecisionGate
import at.uac.android.feature.moderation.ModerationSession
import at.uac.android.feature.platformrolemanagement.*
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
class PlatformRoleRepositoryTest {
    private val f = PlatformRoleUnitFixture
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

    private class Journal : PlatformRoleJournal {
        var entries = emptyList<PlatformRolePending>()
        val writes = mutableListOf<PlatformRolePhase>()
        var clears = 0
        var onPending: (suspend () -> Unit)? = null
        var onPut: ((PlatformRolePending) -> Unit)? = null
        var failPhase: PlatformRolePhase? = null
        var corruptReadback = false
        var clearFails = false

        override suspend fun pending(uid: String): List<PlatformRolePending> {
            onPending?.invoke()
            return entries
        }

        override suspend fun put(
            uid: String,
            entry: PlatformRolePending,
            expected: PlatformRolePending?,
        ): PlatformRolePending {
            if (entry.phase == failPhase) throw IllegalStateException("synthetic durable failure")
            val old = entries.firstOrNull { it.version.targetId == entry.version.targetId }
            check(old == expected)
            check(entry.accountHash == PlatformRoleRecovery.accountHash(uid))
            writes += entry.phase
            entries = entries.filterNot { it == old } + entry
            onPut?.invoke(entry)
            return if (corruptReadback)
                entry.copy(reasonHash = PlatformRoleRecovery.hash("corrupt"))
            else entry
        }

        override suspend fun clear(uid: String, expected: PlatformRolePending) {
            if (clearFails) throw IllegalStateException("synthetic clear failure")
            check(expected in entries)
            check(expected.accountHash == PlatformRoleRecovery.accountHash(uid))
            entries = entries - expected
            clears++
        }
    }

    private class Source(private val gate: Gate) : PlatformRoleSource {
        private val f = PlatformRoleUnitFixture
        var fields = f.fields()
        var reads = 0
        var metadataReads = 0
        var metadata = PlatformRoleTargetAuth(f.target, true, false)
        var onMetadata: (suspend () -> Unit)? = null
        var receiptOverride: PlatformRoleReceipt? = null
        var sends = 0
        var tasks = 0
        var reconciles = 0
        var onRead: (suspend () -> Unit)? = null
        var beforeDispatch: (() -> Unit)? = null
        var settle: CompletableDeferred<Unit>? = null
        var sendFailure: Exception? = null
        var onSettled: (() -> Unit)? = null
        var onReconcile: (suspend () -> Unit)? = null
        var overrideObservation: PlatformRoleObservation? = null
        var lastReceipt: PlatformRoleReceipt? = null
        val changes = MutableSharedFlow<Unit>()

        override suspend fun read(
            session: ModerationSession,
            targetId: String,
        ): PlatformRoleSnapshot {
            check(gate.depth == 1)
            reads++
            onRead?.invoke()
            return PlatformRoleRecovery.snapshot(targetId, fields)
        }

        override suspend fun targetAuth(
            session: ModerationSession,
            targetId: String,
        ): PlatformRoleTargetAuth {
            check(gate.depth == 1)
            metadataReads++
            onMetadata?.invoke()
            return metadata
        }

        override fun changes(session: ModerationSession, targetId: String) = changes.map { it }

        override suspend fun send(
            session: ModerationSession,
            entry: PlatformRolePending,
            reason: String,
            canDispatch: () -> Boolean,
        ): PlatformRoleReceipt {
            check(gate.depth == 1 && entry.phase == PlatformRolePhase.DISPATCHED)
            sends++
            beforeDispatch?.invoke()
            if (!canDispatch()) throw PlatformRoleException(PlatformRoleFailure.STALE)
            // Model the source contract's final raw-version check, not server CAS.
            if (
                PlatformRoleRecovery.snapshot(entry.version.targetId, fields).version !=
                    entry.version
            )
                throw PlatformRoleException(PlatformRoleFailure.STALE)
            check(PlatformRoleRecovery.hash(reason) == entry.reasonHash)
            tasks++
            settle?.await()
            sendFailure?.let { throw it }
            val receipt = PlatformRoleRecovery.receipt(entry, f.response(entry.action))
            fields =
                fields +
                    mapOf(
                        "globalRole" to entry.action.newRole,
                        "roleUpdatedAt" to f.time.plusNanos(7),
                        "roleUpdatedBy" to session.uid,
                    )
            onSettled?.invoke()
            lastReceipt = receipt
            return receiptOverride ?: receipt
        }

        override suspend fun reconcile(
            session: ModerationSession,
            entry: PlatformRolePending,
        ): PlatformRoleObservation {
            check(gate.depth == 1)
            reconciles++
            onReconcile?.invoke()
            return overrideObservation
                ?: PlatformRoleRecovery.observation(entry, session.uid, fields)
        }
    }

    private data class Harness(
        val repo: PlatformRoleRepository,
        val source: Source,
        val journal: Journal,
        val gate: Gate,
    )

    private fun harness(): Harness {
        val gate = Gate()
        val source = Source(gate)
        val journal = Journal()
        return Harness(
            PlatformRoleRepository(source, journal, { live }, gate, { f.operation }),
            source,
            journal,
            gate,
        )
    }

    private suspend fun execute(h: Harness, canSubmit: () -> Boolean = { true }) =
        h.repo.execute(
            f.actor,
            PlatformRoleRecovery.snapshot(f.target, f.fields()).version,
            PlatformRoleAction.ASSIGN,
            "PRIVATE reason 😀",
            canSubmit = canSubmit,
        )

    private suspend fun fails(expected: PlatformRoleFailure, action: suspend () -> Any?) {
        try {
            action()
            fail("Expected rejection")
        } catch (error: PlatformRoleException) {
            assertEquals(expected, error.failure)
        }
    }

    @Test
    fun metadataPreviewIsOwnerGatedReadOnlyAndBoundToTarget() = runTest {
        val h = harness()
        assertEquals(h.source.metadata, h.repo.targetAuth(f.actor, f.target))
        assertEquals(1, h.gate.calls)
        assertEquals(1, h.source.metadataReads)
        assertEquals(0, h.source.reads)
        assertEquals(0, h.source.tasks)
        assertTrue(h.journal.entries.isEmpty())
        h.source.metadata = h.source.metadata.copy(targetId = "foreign-target")
        fails(PlatformRoleFailure.STALE) { h.repo.targetAuth(f.actor, f.target) }
    }

    @Test
    fun metadataPreviewDeniesNonOwnerAndInvalidTargetBeforeSource() = runTest {
        val h = harness()
        for (session in
            listOf(
                f.actor.copy(role = "admin"),
                f.actor.copy(role = "user"),
                f.actor.copy(ready = false),
            )) {
            live = session
            fails(PlatformRoleFailure.ACCESS) { h.repo.targetAuth(session, f.target) }
        }
        live = f.actor
        fails(PlatformRoleFailure.INVALID) { h.repo.targetAuth(f.actor, "bad/target") }
        assertEquals(0, h.source.metadataReads)
        assertEquals(0, h.gate.calls)
    }

    @Test
    fun metadataPreviewMapsOfflineAndActualGateDenialWithoutJournalMutation() = runTest {
        val h = harness()
        h.source.onMetadata = { throw java.io.IOException("synthetic metadata network failure") }
        fails(PlatformRoleFailure.OFFLINE) { h.repo.targetAuth(f.actor, f.target) }
        h.gate.before = {
            throw at.uac.android.feature.moderation.ModerationException(
                at.uac.android.feature.moderation.ModerationFailure.DENIED
            )
        }
        fails(PlatformRoleFailure.ACCESS) { h.repo.targetAuth(f.actor, f.target) }
        assertTrue(h.journal.entries.isEmpty())
        assertEquals(0, h.source.tasks)
    }

    @Test
    fun metadataPreviewCancelledDuringNonCancellableGateNeverExposesLateResult() = runTest {
        val h = harness()
        val release = CompletableDeferred<Unit>()
        h.source.onMetadata = { release.await() }
        var exposed = false
        val job = launch {
            h.repo.targetAuth(f.actor, f.target)
            exposed = true
        }
        runCurrent()
        job.cancel()
        runCurrent()
        assertFalse(job.isCompleted)
        release.complete(Unit)
        job.join()
        assertTrue(job.isCancelled)
        assertFalse(exposed)
        assertTrue(h.journal.entries.isEmpty())
    }

    @Test
    fun metadataPreviewCancelsBeforeSourceIfCallerOrOwnerChangesOnGateEntry() = runTest {
        for (cancel in listOf(false, true)) {
            live = f.actor
            val h = harness()
            var job: Job? = null
            h.gate.before = {
                if (cancel) job!!.cancel() else live = f.actor.copy(revision = 17)
            }
            job =
                launch(start = CoroutineStart.LAZY) {
                    h.repo.targetAuth(f.actor, f.target)
                    fail("Obsolete metadata exposed")
                }
            job.start()
            job.join()
            assertTrue(job.isCancelled)
            assertEquals(0, h.source.metadataReads)
        }
    }

    @Test
    fun metadataPreviewOwnerChangeDuringReadNeverExposesPrivateResult() = runTest {
        val h = harness()
        h.source.onMetadata = { live = f.actor.copy(uid = "other-owner", revision = 88) }
        val job = launch {
            h.repo.targetAuth(f.actor, f.target)
            fail("Old metadata escaped")
        }
        job.join()
        assertTrue(job.isCancelled)
        assertTrue(h.journal.entries.isEmpty())
    }

    @Test
    fun successfulOperationPersistsEveryPhaseBeforeReadbackWithOneTask() = runTest {
        val h = harness()
        h.source.onReconcile = {
            assertEquals(PlatformRolePhase.ACKNOWLEDGED, h.journal.entries.single().phase)
        }
        assertEquals(PlatformRoleObservation.CONFIRMED_CURRENT, execute(h))
        assertEquals(PlatformRolePhase.entries, h.journal.writes)
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
            PlatformRoleRepository(
                source,
                journal,
                { live },
                gate,
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
                    PlatformRoleAction.ASSIGN,
                    "PRIVATE reason 😀",
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
        h.journal.onPut = { if (it.phase == PlatformRolePhase.PREPARED) job.cancel() }
        job = launch(start = CoroutineStart.LAZY) { execute(h) }
        job.start()
        job.join()
        assertEquals(listOf(PlatformRolePhase.PREPARED), h.journal.writes)
        assertEquals(1, h.journal.clears)
        assertTrue(h.journal.entries.isEmpty())
        assertEquals(0, h.source.tasks)
    }

    @Test
    fun cancellationAfterDispatchedRetainsPendingWithoutCallingSource() = runTest {
        val h = harness()
        lateinit var job: Job
        h.journal.onPut = { if (it.phase == PlatformRolePhase.DISPATCHED) job.cancel() }
        job = launch(start = CoroutineStart.LAZY) { execute(h) }
        job.start()
        job.join()
        assertEquals(PlatformRolePhase.DISPATCHED, h.journal.entries.single().phase)
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
        assertEquals(PlatformRolePhase.ACKNOWLEDGED, h.journal.entries.single().phase)
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
            PlatformRoleRecovery.accountHash(f.actor.uid),
            h.journal.entries.single().accountHash,
        )
        assertEquals(PlatformRolePhase.ACKNOWLEDGED, h.journal.entries.single().phase)
        assertEquals(0, h.source.reconciles)
    }

    @Test
    fun targetRoleOrAcknowledgementChangeBeforeDispatchVetoesWithoutJournal() = runTest {
        for (fields in
            listOf(
                f.fields() + ("globalRole" to "owner"),
                f.fields() + ("statusAcknowledgedAt" to f.time.plusNanos(1)),
            )) {
            val h = harness()
            h.source.fields = fields
            fails(PlatformRoleFailure.STALE) { execute(h) }
            assertTrue(h.journal.writes.isEmpty())
            assertEquals(0, h.source.tasks)
        }
    }

    @Test
    fun livePresentationVetoBeforeAndAfterPreparedPreventsSending() = runTest {
        val early = harness()
        fails(PlatformRoleFailure.STALE) { execute(early) { false } }
        assertEquals(0, early.source.reads)
        val late = harness()
        var allowed = true
        late.journal.onPut = { if (it.phase == PlatformRolePhase.PREPARED) allowed = false }
        fails(PlatformRoleFailure.STALE) { execute(late) { allowed } }
        assertTrue(late.journal.entries.isEmpty())
        assertEquals(0, late.source.tasks)
    }

    @Test
    fun finalSourceCanDispatchVetoLeavesConservativePendingAndZeroTasks() = runTest {
        val h = harness()
        var allowed = true
        h.source.beforeDispatch = { allowed = false }
        fails(PlatformRoleFailure.UNCONFIRMED) { execute(h) { allowed } }
        assertEquals(1, h.source.sends)
        assertEquals(0, h.source.tasks)
        assertEquals(PlatformRolePhase.DISPATCHED, h.journal.entries.single().phase)
    }

    @Test
    fun concurrentDoubleTapIsRejectedRatherThanQueuedForResend() = runTest {
        val h = harness()
        val settlement = CompletableDeferred<Unit>()
        h.source.settle = settlement
        val first = async { execute(h) }
        runCurrent()
        fails(PlatformRoleFailure.PENDING) { execute(h) }
        assertEquals(1, h.source.tasks)
        settlement.complete(Unit)
        assertEquals(PlatformRoleObservation.CONFIRMED_CURRENT, first.await())
        assertEquals(1, h.source.tasks)
    }

    @Test
    fun preparedAndDispatchedPersistenceFailuresNeverStartSdkTask() = runTest {
        for (phase in listOf(PlatformRolePhase.PREPARED, PlatformRolePhase.DISPATCHED)) {
            val h = harness()
            h.journal.failPhase = phase
            fails(PlatformRoleFailure.JOURNAL) { execute(h) }
            assertEquals(0, h.source.tasks)
        }
    }

    @Test
    fun corruptPreparedReadbackNeverDispatches() = runTest {
        val h = harness()
        h.journal.corruptReadback = true
        fails(PlatformRoleFailure.JOURNAL) { execute(h) }
        assertEquals(0, h.source.tasks)
        assertEquals(PlatformRolePhase.PREPARED, h.journal.entries.single().phase)
    }

    @Test
    fun receiptPersistenceFailureRetainsDispatchedWithoutReadbackOrRetry() = runTest {
        val h = harness()
        h.journal.failPhase = PlatformRolePhase.ACKNOWLEDGED
        fails(PlatformRoleFailure.JOURNAL) { execute(h) }
        assertEquals(1, h.source.tasks)
        assertEquals(0, h.source.reconciles)
        assertEquals(PlatformRolePhase.DISPATCHED, h.journal.entries.single().phase)
        h.journal.failPhase = null
        fails(PlatformRoleFailure.PENDING) { execute(h) }
        assertEquals(1, h.source.tasks)
    }

    @Test
    fun unknownTransportOutcomeRetainsPendingAndNeverAutomaticallyRepeats() = runTest {
        val h = harness()
        h.source.sendFailure = PlatformRoleException(PlatformRoleFailure.OFFLINE)
        fails(PlatformRoleFailure.UNCONFIRMED) { execute(h) }
        val pending = h.journal.entries.single()
        assertEquals(PlatformRoleObservation.UNCONFIRMED, h.repo.reconcile(f.actor, pending))
        fails(PlatformRoleFailure.PENDING) { execute(h) }
        assertEquals(1, h.source.tasks)
    }

    @Test
    fun observedStateWithoutReceiptCannotClearJournalEvenAfterColdRecovery() = runTest {
        val h = harness()
        val entry = f.prepared().copy(phase = PlatformRolePhase.DISPATCHED)
        h.journal.entries = listOf(entry)
        h.source.fields = f.after(entry.action)
        assertEquals(
            PlatformRoleObservation.OBSERVED_WITHOUT_RECEIPT,
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
        h.source.overrideObservation = PlatformRoleObservation.CONFIRMED_CURRENT
        fails(PlatformRoleFailure.UNCONFIRMED) { h.repo.reconcile(f.actor, entry) }
        assertEquals(listOf(entry), h.journal.entries)
    }

    @Test
    fun confirmedLaterStateChangeClearsWithoutSendingAgain() = runTest {
        val h = harness()
        h.source.onSettled = {
            h.source.fields = h.source.fields + ("statusAcknowledgedAt" to f.time.plusSeconds(4))
        }
        assertEquals(PlatformRoleObservation.CONFIRMED_CHANGED, execute(h))
        assertEquals(1, h.source.tasks)
        assertTrue(h.journal.entries.isEmpty())
    }

    @Test
    fun acknowledgedReadbackTimeoutPreservesAcceptanceAndJournalForReadOnlyRecovery() = runTest {
        val h = harness()
        h.source.onReconcile = { withTimeout(1) { delay(2) } }
        assertEquals(PlatformRoleObservation.CONFIRMED_UNAVAILABLE, execute(h))
        assertEquals(PlatformRolePhase.ACKNOWLEDGED, h.journal.entries.single().phase)
        h.source.onReconcile = null
        assertEquals(
            PlatformRoleObservation.CONFIRMED_CURRENT,
            h.repo.reconcile(f.actor, h.journal.entries.single()),
        )
        assertEquals(1, h.source.tasks)
        assertTrue(h.journal.entries.isEmpty())
    }

    @Test
    fun preflightAndStandaloneTimeoutsAreTypedOfflineNotExternalCancellation() = runTest {
        val h = harness()
        h.source.onRead = { withTimeout(1) { delay(2) } }
        fails(PlatformRoleFailure.OFFLINE) { execute(h) }
        assertTrue(h.journal.entries.isEmpty())
        val entry = f.prepared()
        h.journal.entries = listOf(entry)
        h.source.onReconcile = { withTimeout(1) { delay(2) } }
        fails(PlatformRoleFailure.OFFLINE) { h.repo.reconcile(f.actor, entry) }
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
    fun refreshedOwnerSessionCanReconcileAnExistingOwnReceipt() = runTest {
        val h = harness()
        val owner = f.actor.copy(role = "owner")
        val prepared =
            PlatformRoleRecovery.prepared(
                    owner,
                    PlatformRoleRecovery.snapshot(f.target, f.fields()),
                    PlatformRoleAction.ASSIGN,
                    "PRIVATE reason 😀",
                    PlatformRoleTargetAuth(f.target, true, false),
                    f.operation,
                )
                .copy(phase = PlatformRolePhase.DISPATCHED)
        val entry =
            prepared.copy(
                phase = PlatformRolePhase.ACKNOWLEDGED,
                receipt = PlatformRoleRecovery.receipt(prepared, f.response(prepared.action)),
            )
        h.journal.entries = listOf(entry)
        h.source.fields = f.after(entry.action)
        live = f.actor.copy(revision = 20)
        assertEquals(PlatformRoleObservation.CONFIRMED_CURRENT, h.repo.reconcile(live!!, entry))
        assertEquals(0, h.source.tasks)
        assertTrue(h.journal.entries.isEmpty())
    }

    @Test
    fun noReadyNoManagerAndOwnTargetCannotStartAnOperation() = runTest {
        val h = harness()
        for (actor in listOf(f.actor.copy(ready = false), f.actor.copy(role = "user"))) {
            live = actor
            fails(PlatformRoleFailure.ACCESS) {
                h.repo.execute(
                    actor,
                    f.prepared().version,
                    PlatformRoleAction.ASSIGN,
                    "PRIVATE reason 😀",
                    canSubmit = { true },
                )
            }
        }
        live = f.actor.copy(uid = f.target)
        fails(PlatformRoleFailure.ACCESS) {
            h.repo.execute(
                live!!,
                f.prepared().version,
                PlatformRoleAction.ASSIGN,
                "PRIVATE reason 😀",
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
        fails(PlatformRoleFailure.JOURNAL) { h.repo.pending(f.actor) }
        h.journal.entries =
            listOf(entry.copy(accountHash = PlatformRoleRecovery.accountHash("foreign")))
        fails(PlatformRoleFailure.ACCESS) { h.repo.pending(f.actor) }
        h.journal.entries = List(17) { entry }
        fails(PlatformRoleFailure.JOURNAL) { h.repo.pending(f.actor) }
    }

    @Test
    fun fullBoundedJournalVetoesAnotherTargetBeforeAnySourceRead() = runTest {
        val h = harness()
        h.journal.entries =
            List(PlatformRoleRecovery.MAX_PENDING) { index ->
                val target = "synthetic-existing-$index"
                PlatformRoleRecovery.prepared(
                    f.actor,
                    PlatformRoleRecovery.snapshot(target, f.fields()),
                    PlatformRoleAction.ASSIGN,
                    "PRIVATE reason 😀",
                    PlatformRoleTargetAuth(target, true, false),
                    "0a0a0a0a-1111-4222-8333-${index.toString().padStart(12, '0')}",
                )
            }
        fails(PlatformRoleFailure.PENDING) { execute(h) }
        assertEquals(0, h.source.reads)
        assertEquals(0, h.source.tasks)
        assertTrue(h.journal.writes.isEmpty())
    }

    @Test
    fun journalClearFailureRetainsAcknowledgedStateWithoutRepeatingTask() = runTest {
        val h = harness()
        h.journal.clearFails = true
        fails(PlatformRoleFailure.JOURNAL) { execute(h) }
        assertEquals(PlatformRolePhase.ACKNOWLEDGED, h.journal.entries.single().phase)
        assertEquals(1, h.source.tasks)
    }

    @Test
    fun assignmentReadsMetadataOnceButRemovalNeverRequestsUnavailableTargetAuth() = runTest {
        val assign = harness()
        assertEquals(PlatformRoleObservation.CONFIRMED_CURRENT, execute(assign))
        assertEquals(1, assign.source.metadataReads)
        val remove = harness()
        remove.source.fields =
            f.fields(PlatformRoleAction.REMOVE) +
                mapOf(
                    "accountStatus" to "deactivated",
                    "blockState" to "bannedPermanent",
                )
        remove.source.onMetadata = { fail("Removal must not request target Auth") }
        val reviewed = PlatformRoleRecovery.snapshot(f.target, remove.source.fields).version
        assertEquals(
            PlatformRoleObservation.CONFIRMED_CURRENT,
            remove.repo.execute(f.actor, reviewed, PlatformRoleAction.REMOVE, "reason") { true },
        )
        assertEquals(0, remove.source.metadataReads)
        assertEquals(1, remove.source.tasks)
        assertEquals("deactivated", remove.source.fields["accountStatus"])
        assertEquals("bannedPermanent", remove.source.fields["blockState"])
    }

    @Test
    fun invalidAssignmentMetadataNeverCreatesPendingOrCallsSend() = runTest {
        for (metadata in
            listOf(
                PlatformRoleTargetAuth(f.target, false, false),
                PlatformRoleTargetAuth(f.target, true, true),
                PlatformRoleTargetAuth("foreign", true, false),
            )) {
            val h = harness()
            h.source.metadata = metadata
            fails(PlatformRoleFailure.STALE) { execute(h) }
            assertEquals(1, h.source.metadataReads)
            assertTrue(h.journal.entries.isEmpty())
            assertEquals(0, h.source.sends)
        }
    }

    @Test
    fun metadataTimeoutIsOfflineBeforeAnyJournalOrMutation() = runTest {
        val h = harness()
        h.source.onMetadata = { withTimeout(1) { delay(2) } }
        fails(PlatformRoleFailure.OFFLINE) { execute(h) }
        assertTrue(h.journal.writes.isEmpty())
        assertEquals(0, h.source.tasks)
    }

    @Test
    fun callerCancellationAndPrivacyVetoDuringMetadataCreateNoPending() = runTest {
        val h = harness()
        lateinit var job: Job
        h.source.onMetadata = { job.cancel() }
        job = launch(start = CoroutineStart.LAZY) { execute(h) }
        job.start()
        job.join()
        assertTrue(job.isCancelled)
        assertTrue(h.journal.writes.isEmpty())
        assertEquals(0, h.source.sends)
        val veto = harness()
        var allowed = true
        veto.source.onMetadata = { allowed = false }
        fails(PlatformRoleFailure.STALE) { execute(veto) { allowed } }
        assertTrue(veto.journal.writes.isEmpty())
    }

    @Test
    fun ownerAuthorityLostDuringMetadataCannotPersistIntent() = runTest {
        val h = harness()
        h.source.onMetadata = { live = f.actor.copy(role = "admin", revision = 8) }
        val job = launch {
            execute(h)
            fail("Revoked scope escaped")
        }
        job.join()
        assertTrue(job.isCancelled)
        assertTrue(h.journal.writes.isEmpty())
        assertEquals(0, h.source.sends)
    }

    @Test
    fun appAdminCannotReadRecoverOrDispatchEvenItsOldOwnerReceipt() = runTest {
        val h = harness()
        val entry = f.acknowledged()
        h.journal.entries = listOf(entry)
        live = f.actor.copy(role = "admin", revision = 8)
        fails(PlatformRoleFailure.ACCESS) { h.repo.pending(live!!) }
        fails(PlatformRoleFailure.ACCESS) { h.repo.read(live!!, f.target) }
        fails(PlatformRoleFailure.ACCESS) { h.repo.reconcile(live!!, entry) }
        fails(PlatformRoleFailure.ACCESS) {
            h.repo.execute(live!!, entry.version, entry.action, "reason") { true }
        }
        assertEquals(listOf(entry), h.journal.entries)
        assertEquals(0, h.source.reads)
        assertEquals(0, h.source.reconciles)
        assertEquals(0, h.source.metadataReads)
        assertEquals(0, h.source.tasks)
    }

    @Test
    fun roleAndSelfPreflightVetoRunsBeforeMetadataLookup() = runTest {
        for (role in listOf("owner", "admin")) {
            val h = harness()
            h.source.fields = f.fields() + ("globalRole" to role)
            val reviewed = PlatformRoleRecovery.snapshot(f.target, h.source.fields).version
            fails(if (role == "owner") PlatformRoleFailure.ACCESS else PlatformRoleFailure.STALE) {
                h.repo.execute(f.actor, reviewed, PlatformRoleAction.ASSIGN, "reason") { true }
            }
            assertEquals(0, h.source.metadataReads)
            assertTrue(h.journal.writes.isEmpty())
        }
    }

    @Test
    fun unknownPendingBlocksOppositeActionAndCannotBeClearedByMatchingRole() = runTest {
        val h = harness()
        val entry = f.prepared().copy(phase = PlatformRolePhase.DISPATCHED)
        h.journal.entries = listOf(entry)
        h.source.fields = f.after()
        fails(PlatformRoleFailure.PENDING) {
            h.repo.execute(
                f.actor,
                PlatformRoleRecovery.snapshot(f.target, h.source.fields).version,
                PlatformRoleAction.REMOVE,
                "reason",
            ) {
                true
            }
        }
        assertEquals(
            PlatformRoleObservation.OBSERVED_WITHOUT_RECEIPT,
            h.repo.reconcile(f.actor, entry),
        )
        assertEquals(listOf(entry), h.journal.entries)
        assertEquals(0, h.source.tasks)
        assertEquals(0, h.source.metadataReads)
    }

    @Test
    fun malformedOwnResponseBindingNeverBecomesDurableAck() = runTest {
        val h = harness()
        h.source.receiptOverride = f.acknowledged().receipt!!.copy(requestHash = "f".repeat(64))
        fails(PlatformRoleFailure.UNCONFIRMED) { execute(h) }
        assertEquals(PlatformRolePhase.DISPATCHED, h.journal.entries.single().phase)
        assertEquals(0, h.source.reconciles)
        fails(PlatformRoleFailure.PENDING) { execute(h) }
        assertEquals(1, h.source.tasks)
    }

    @Test
    fun allForgedConfirmedOutcomesWithoutAckAreRejected() = runTest {
        for (observation in PlatformRoleObservation.entries.filter { it.confirmed }) {
            val h = harness()
            val entry = f.prepared()
            h.journal.entries = listOf(entry)
            h.source.overrideObservation = observation
            fails(PlatformRoleFailure.UNCONFIRMED) { h.repo.reconcile(f.actor, entry) }
            assertEquals(listOf(entry), h.journal.entries)
            assertEquals(0, h.journal.clears)
        }
    }

    @Test
    fun sameRoleAfterAbaStillHasDifferentReviewedRawVersion() = runTest {
        val h = harness()
        h.source.fields = f.fields() + ("roleUpdatedAt" to f.time.plusNanos(1))
        fails(PlatformRoleFailure.STALE) { execute(h) }
        assertEquals(0, h.source.metadataReads)
        assertEquals(0, h.source.sends)
        assertTrue(h.journal.writes.isEmpty())
    }

    @Test
    fun unknownPreparePersistenceAndCleanupFailureDoNotPermitResend() = runTest {
        val h = harness()
        h.journal.onPut = { throw IllegalStateException("Synthetic lost write receipt") }
        fails(PlatformRoleFailure.JOURNAL) { execute(h) }
        assertEquals(PlatformRolePhase.PREPARED, h.journal.entries.single().phase)
        h.journal.onPut = null
        fails(PlatformRoleFailure.PENDING) { execute(h) }
        assertEquals(0, h.source.sends)
        val veto = harness()
        var allowed = true
        veto.journal.onPut = { allowed = false }
        veto.journal.clearFails = true
        fails(PlatformRoleFailure.JOURNAL) { execute(veto) { allowed } }
        assertEquals(PlatformRolePhase.PREPARED, veto.journal.entries.single().phase)
        assertEquals(0, veto.source.sends)
    }

    @Test
    fun profileChangeWhileMetadataIsReadNeedsFinalSourceVetoNotServerCasClaim() = runTest {
        val h = harness()
        h.source.onMetadata = {
            h.source.fields = h.source.fields + ("roleUpdatedAt" to f.time.plusNanos(1))
        }
        fails(PlatformRoleFailure.UNCONFIRMED) { execute(h) }
        assertEquals(0, h.source.tasks)
        assertEquals(1, h.source.sends)
        assertEquals(PlatformRolePhase.DISPATCHED, h.journal.entries.single().phase)
        assertEquals(0, h.journal.clears)
    }
}
