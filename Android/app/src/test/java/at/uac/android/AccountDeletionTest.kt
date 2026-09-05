package at.uac.android

import at.uac.android.core.*
import at.uac.android.feature.accountdeletion.*
import at.uac.android.feature.auth.*
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class AccountDeletionTest {
    @Before
    fun setup() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @After
    fun finish() {
        Dispatchers.resetMain()
    }

    private val alice = AccountDeletionSession("deletion-alice", 1)
    private val bob = AccountDeletionSession("deletion-bob", 2)
    private val time = Instant.parse("2026-09-03T03:00:00Z")
    private val ordinary = AccountDeletionPolicy(false, false, false)

    private inner class Journal : AccountDeletionJournal {
        val entries = mutableMapOf<String, DeletionJournalEntry>()
        var writes = 0
        var reads = 0
        var failRead = false
        var failWrite = false
        var failClear = false
        var beforeWrite: suspend () -> Unit = {}

        override suspend fun pending(uid: String): DeletionJournalEntry? {
            reads++
            if (failRead) error("Synthetic disk failure")
            return entries[uid]
        }

        override suspend fun record(uid: String, submittedAt: Instant): DeletionJournalEntry {
            beforeWrite()
            if (failWrite) error("Synthetic commit failure")
            writes++
            return DeletionJournalEntry(
                    DeletionJournalCodec.accountHash(uid),
                    Instant.ofEpochMilli(submittedAt.toEpochMilli()),
                )
                .also { entries[uid] = it }
        }

        override suspend fun markPartial(
            uid: String,
            expectedSubmittedAt: Instant,
        ): DeletionJournalEntry? =
            entries[uid]?.let {
                if (it.submittedAt != expectedSubmittedAt) it
                else
                    it.copy(status = DeletionJournalStatus.PARTIAL).also { partial ->
                        entries[uid] = partial
                    }
            }

        override suspend fun clearConfirmed(uid: String, expectedSubmittedAt: Instant): Boolean {
            if (failClear) error("Synthetic clear failure")
            if (entries[uid]?.submittedAt != expectedSubmittedAt) return false
            entries.remove(uid)
            return true
        }
    }

    private inner class Source : AccountDeletionSource {
        var policy = ordinary
        var proof = AccountDeletionProof(alice.uid, time, false)
        var checks = 0
        var passwords = 0
        var deletes = 0
        var statusReads = 0
        var status = AccountDeletionIdentityStatus.PRESENT
        var reauthFailure: Exception? = null
        var deleteFailure: Exception? = null
        var statusFailure: Exception? = null
        var beforeReauth: suspend () -> Unit = {}
        var afterReauth: suspend () -> Unit = {}
        var afterPolicy: suspend (Int) -> Unit = {}
        var beforeDelete: suspend () -> Unit = {}
        var afterDelete: suspend () -> Unit = {}

        override suspend fun policy(uid: String): AccountDeletionPolicy {
            checks++
            afterPolicy(checks)
            return policy
        }

        override suspend fun reauthenticate(uid: String, password: String): AccountDeletionProof {
            passwords++
            beforeReauth()
            reauthFailure?.let { throw it }
            afterReauth()
            return proof
        }

        override suspend fun delete(uid: String): AccountDeletionReceipt {
            beforeDelete()
            deletes++
            deleteFailure?.let { throw it }
            afterDelete()
            return AccountDeletionReceipt(time, AccountDeletionConfirmation.SERVER_RECEIPT)
        }

        override suspend fun status(uid: String): AccountDeletionIdentityStatus {
            statusReads++
            statusFailure?.let { throw it }
            return status
        }
    }

    private class Gate : AccountDeletionGate {
        val mutex = Mutex()
        var entered = 0
        var inside = false

        override suspend fun <T> withSession(
            session: AccountDeletionSession,
            action: suspend () -> T,
        ): T = mutex.withLock {
            assertFalse(inside)
            inside = true
            entered++
            try {
                action()
            } finally {
                inside = false
            }
        }
    }

    private class WaitTimer : AccountDeletionWaitTimer {
        var nanos = 0L
        var reads = 0
        val pauses = mutableListOf<Long>()
        var afterPause: (Long) -> Unit = {}

        override fun elapsedRealtimeNanos(): Long {
            reads++
            return nanos
        }

        override suspend fun pauseMillis(milliseconds: Long) {
            pauses += milliseconds
            delay(milliseconds)
            nanos += milliseconds * 1_000_000L
            afterPause(milliseconds)
        }
    }

    private class Challenge(private val proof: AccountDeletionProof) : AccountDeletionChallenge {
        override val factors =
            listOf(AccountDeletionFactor("opaque-totp-id", "Synthetic authenticator"))
        var resolutions = 0
        var failure: AccountDeletionFailure? = null

        override suspend fun resolve(factorId: String, code: String): AccountDeletionProof {
            resolutions++
            failure?.let { throw AccountDeletionException(it) }
            return proof
        }
    }

    private suspend fun failure(expected: AccountDeletionFailure, operation: suspend () -> Any?) {
        try {
            operation()
            fail("Expected $expected")
        } catch (error: AccountDeletionException) {
            assertEquals(expected, error.failure)
        }
    }

    private suspend fun AccountDeletionRepository.start(
        attempt: AccountDeletionAttempt = AccountDeletionAttempt()
    ) = begin("synthetic-only", attempt, {}, {})

    private fun repository(
        source: Source = Source(),
        journal: Journal = Journal(),
        gate: Gate = Gate(),
        authority: () -> AccountDeletionSession? = { alice },
        clock: () -> Instant = { time },
        freshnessWait: AccountDeletionFreshnessWait = AccountDeletionFreshnessWait(),
    ) = AccountDeletionRepository(source, journal, authority, gate, clock, freshnessWait)

    @Test
    fun journalCodecRoundTripsOnlyHashTimestampAndStatus() {
        val uid = "synthetic-private-uid@example.invalid"
        val hash = DeletionJournalCodec.accountHash(uid)
        assertTrue(hash.matches(Regex("[a-f0-9]{64}")))
        assertNotEquals(hash, DeletionJournalCodec.accountHash("another-synthetic-uid"))
        for (status in DeletionJournalStatus.entries) {
            val entry = DeletionJournalEntry(hash, time, status)
            val bytes = DeletionJournalCodec.encode(entry)
            assertTrue(bytes.size <= DeletionJournalCodec.MAX_BYTES)
            assertFalse(bytes.toString(Charsets.ISO_8859_1).contains(uid))
            assertEquals(entry, DeletionJournalCodec.decode(bytes, hash))
        }
    }

    @Test
    fun journalCodecRejectsForeignTruncatedTrailingInvalidVersionAndStatus() {
        val hash = DeletionJournalCodec.accountHash(alice.uid)
        val bytes = DeletionJournalCodec.encode(DeletionJournalEntry(hash, time))
        assertTrue(
            runCatching {
                DeletionJournalCodec.decode(bytes, DeletionJournalCodec.accountHash(bob.uid))
            }
                .isFailure
        )
        for (bad in
            listOf(
                ByteArray(0),
                bytes.copyOf(7),
                bytes + byteArrayOf(1),
                ByteArray(257),
                bytes.clone().apply { this[0] = 0 },
                bytes.clone().apply { this[4] = 2 },
                bytes.clone().apply { this[lastIndex] = 99 },
            )) {
            assertTrue(runCatching { DeletionJournalCodec.decode(bad, hash) }.isFailure)
        }
        assertTrue(
            runCatching { DeletionJournalCodec.encode(DeletionJournalEntry(hash, Instant.EPOCH)) }
                .isFailure
        )
    }

    @Test
    fun documentIdentityAndLogsNeverExposeOrAcceptPaths() {
        for (bad in listOf("", "..", "u/path", " u", "u\n", "x".repeat(129))) {
            assertTrue(runCatching { AccountDeletionSession(bad, 0) }.isFailure)
        }
        assertFalse(alice.toString().contains(alice.uid))
        assertFalse(AccountDeletionProof(alice.uid, time, true).toString().contains(alice.uid))
    }

    @Test
    fun freshProofRequiresPastTimeAndStrictFourMinuteBoundary() {
        val proof = AccountDeletionProof(alice.uid, time, true)
        assertFalse(proof.recent(time.minusSeconds(1)))
        assertTrue(proof.recent(time))
        assertTrue(proof.recent(time.plusSeconds(239)))
        assertFalse(proof.recent(time.plusSeconds(240)))
    }

    @Test
    fun secondRoundedProofStillRejectsSubsecondFutureClockSkew() {
        val proof = AccountDeletionProof(alice.uid, time, true)
        // Auth auth_time is whole seconds; a device just behind that boundary must not gain a
        // tolerance bypass.
        assertFalse(proof.recent(time.minusNanos(37_500_000)))
        assertFalse(proof.recent(time.minusNanos(1)))
        assertTrue(proof.recent(time))
        assertTrue(proof.recent(time.plusSeconds(240).minusNanos(1)))
        assertFalse(proof.recent(time.plusSeconds(240)))
    }

    @Test
    fun freshnessDiagnosticKeepsExactFutureReasonWhenMillisRoundToZero() {
        val proof = AccountDeletionProof(alice.uid, time, false)
        for ((nanos, millis) in listOf(1L to 0L, 37_500_000L to -37L, 203_500_000L to -203L)) {
            val now = time.minusNanos(nanos)
            assertFalse(proof.recent(now))
            val diagnostic =
                AccountDeletionFreshnessDiagnostic.rejectedClock(
                    AccountDeletionFreshnessStage.FIRST_CLOCK_CHECK,
                    time,
                    now,
                )
            assertEquals(AccountDeletionFreshnessReason.FUTURE, diagnostic.reason)
            assertEquals(millis, diagnostic.ageMillis)
        }
        assertTrue(proof.recent(time.plusSeconds(240).minusNanos(1)))
        assertFalse(proof.recent(time.plusSeconds(240)))
        assertEquals(
            AccountDeletionFreshnessDiagnostic(
                AccountDeletionFreshnessStage.POST_POLICY_CLOCK_CHECK,
                AccountDeletionFreshnessReason.EXPIRED,
                240_000L,
            ),
            AccountDeletionFreshnessDiagnostic.rejectedClock(
                AccountDeletionFreshnessStage.POST_POLICY_CLOCK_CHECK,
                time,
                time.plusSeconds(240),
            ),
        )
    }

    @Test
    fun freshnessDiagnosticBoundsAgeWithoutKeepingAnyIdentityOrTimestamp() {
        for ((from, to, expected) in
            listOf(
                Triple(Instant.MIN, Instant.MAX, 86_400_000L),
                Triple(Instant.MAX, Instant.MIN, -86_400_000L),
            )) {
            val diagnostic =
                AccountDeletionFreshnessDiagnostic.rejectedClock(
                    AccountDeletionFreshnessStage.FIRST_CLOCK_CHECK,
                    from,
                    to,
                )
            assertEquals(expected, diagnostic.ageMillis)
            assertFalse(diagnostic.toString().contains(alice.uid))
            assertFalse(diagnostic.toString().contains(from.toString()))
            assertFalse(diagnostic.toString().contains(to.toString()))
        }
    }

    @Test
    fun firstFreshnessRejectionUsesTheSameSingleClockSampleAndNeverSubmits() = runTest {
        var samples = 0
        val source = Source()
        val journal = Journal()
        val repo =
            repository(
                source,
                journal,
                clock = {
                    samples++
                    if (samples == 1) time.minusNanos(2_203_500_000) else time.plusSeconds(2)
                },
            )
        try {
            repo.start()
            fail("Future proof must be rejected")
        } catch (error: AccountDeletionException) {
            assertEquals(AccountDeletionFailure.RECENT_AUTH_REQUIRED, error.failure)
            assertEquals(
                AccountDeletionFreshnessDiagnostic(
                    AccountDeletionFreshnessStage.FIRST_CLOCK_CHECK,
                    AccountDeletionFreshnessReason.FUTURE,
                    -2203L,
                ),
                error.freshnessDiagnostic,
            )
        }
        assertEquals(1, samples)
        assertEquals(1, source.checks)
        assertEquals(1, source.passwords)
        assertEquals(0, journal.writes)
        assertEquals(0, source.deletes)
    }

    @Test
    fun secondFreshnessRejectionIdentifiesPostPolicyAndStillNeverSubmits() = runTest {
        var now = time
        var samples = 0
        val source = Source().apply { afterPolicy = { if (it == 2) now = time.plusSeconds(240) } }
        val journal = Journal()
        try {
            repository(
                    source,
                    journal,
                    clock = {
                        samples++
                        now
                    },
                )
                .start()
            fail("Expired proof must be rejected")
        } catch (error: AccountDeletionException) {
            assertEquals(AccountDeletionFailure.RECENT_AUTH_REQUIRED, error.failure)
            assertEquals(
                AccountDeletionFreshnessStage.POST_POLICY_CLOCK_CHECK,
                error.freshnessDiagnostic?.stage,
            )
            assertEquals(AccountDeletionFreshnessReason.EXPIRED, error.freshnessDiagnostic?.reason)
            assertEquals(240_000L, error.freshnessDiagnostic?.ageMillis)
        }
        assertEquals(2, samples)
        assertEquals(2, source.checks)
        assertEquals(0, journal.writes)
        assertEquals(0, source.deletes)
    }

    @Test
    fun wrappedClaimDiagnosticIsRetainedWithoutReadingCauseMessages() {
        val diagnostic =
            AccountDeletionFreshnessDiagnostic(
                AccountDeletionFreshnessStage.CLAIM_PARSE,
                AccountDeletionFreshnessReason.INVALID_INTEGER,
            )
        val original =
            AccountDeletionException(
                AccountDeletionFailure.RECENT_AUTH_REQUIRED,
                freshnessDiagnostic = diagnostic,
            )
        val wrapped =
            AccountDeletionException(AccountDeletionFailure.RECENT_AUTH_REQUIRED, original)
        assertSame(original, wrapped.cause)
        assertSame(diagnostic, wrapped.accountDeletionFreshnessDiagnostic())
        assertNull(
            AccountDeletionException(AccountDeletionFailure.INVALID_CREDENTIALS)
                .accountDeletionFreshnessDiagnostic()
        )
        val cycle = Exception("Synthetic cause cycle")
        cycle.initCause(cycle.let { Exception("Synthetic other cause", it) })
        assertNull(cycle.accountDeletionFreshnessDiagnostic())
    }

    @Test
    fun viewModelFreshnessFailureIsMaskedAndClearedBeforeExplicitRetry() = runTest {
        var now = time.minusSeconds(2).minusNanos(1)
        var authority = alice
        val source = Source()
        val journal = Journal()
        val model =
            AccountDeletionViewModel(source, journal, { authority }, Gate(), { _, _ -> }, { now })
        model.bind(alice)
        model.load()
        advanceUntilIdle()
        model.begin("password", true)
        advanceUntilIdle()
        assertEquals(
            AccountDeletionFreshnessReason.FUTURE,
            model.state.value.freshnessDiagnostic?.reason,
        )
        assertFalse(model.state.value.busy)
        assertFalse(model.state.value.unresolved)
        assertEquals(0, source.deletes)
        assertEquals(0, journal.writes)
        assertNull(model.state.value.forSession(bob).freshnessDiagnostic)
        assertNull(model.state.value.forSession(null).freshnessDiagnostic)
        advanceUntilIdle()
        assertEquals(1, source.passwords)
        val hold = CompletableDeferred<Unit>()
        source.beforeReauth = { hold.await() }
        now = time
        model.begin("password", true)
        assertNull(model.state.value.freshnessDiagnostic)
        runCurrent()
        assertEquals(2, source.passwords)
        assertEquals(0, source.deletes)
        authority = bob
        model.bind(bob)
        hold.complete(Unit)
        advanceUntilIdle()
        assertEquals(AccountDeletionState(bob), model.state.value)
        assertEquals(0, source.deletes)
    }

    @Test
    fun viewModelFreshnessDiagnosticClearsOnNewReadAndNonFreshnessFailure() = runTest {
        val diagnostic =
            AccountDeletionFreshnessDiagnostic(
                AccountDeletionFreshnessStage.SDK_REAUTH,
                AccountDeletionFreshnessReason.SDK_REJECTED,
            )
        val source =
            Source().apply {
                reauthFailure =
                    AccountDeletionException(
                        AccountDeletionFailure.RECENT_AUTH_REQUIRED,
                        freshnessDiagnostic = diagnostic,
                    )
            }
        val model =
            AccountDeletionViewModel(source, Journal(), { alice }, Gate(), { _, _ -> }, { time })
        model.bind(alice)
        model.load()
        advanceUntilIdle()
        model.begin("password", true)
        advanceUntilIdle()
        assertEquals(diagnostic, model.state.value.freshnessDiagnostic)
        model.load()
        assertNull(model.state.value.freshnessDiagnostic)
        advanceUntilIdle()
        source.reauthFailure = AccountDeletionException(AccountDeletionFailure.INVALID_CREDENTIALS)
        model.begin("password", true)
        advanceUntilIdle()
        assertEquals(AccountDeletionFailure.INVALID_CREDENTIALS, model.state.value.error)
        assertNull(model.state.value.freshnessDiagnostic)
        assertEquals(0, source.deletes)
    }

    @Test
    fun callableFreshnessRejectionRetainsActualPendingJournalAndNeverAutomaticallyRetries() =
        runTest {
            val diagnostic =
                AccountDeletionFreshnessDiagnostic(
                    AccountDeletionFreshnessStage.CALLABLE,
                    AccountDeletionFreshnessReason.SERVER_REJECTED,
                )
            val source =
                Source().apply {
                    deleteFailure =
                        AccountDeletionException(
                            AccountDeletionFailure.RECENT_AUTH_REQUIRED,
                            freshnessDiagnostic = diagnostic,
                        )
                }
            val journal = Journal()
            val model =
                AccountDeletionViewModel(source, journal, { alice }, Gate(), { _, _ -> }, { time })
            model.bind(alice)
            model.load()
            advanceUntilIdle()
            model.begin("password", true)
            advanceUntilIdle()
            assertEquals(AccountDeletionFailure.RECENT_AUTH_REQUIRED, model.state.value.error)
            assertEquals(diagnostic, model.state.value.freshnessDiagnostic)
            assertTrue(model.state.value.unresolved)
            assertNotNull(journal.pending(alice.uid))
            assertEquals(1, source.deletes)
            model.begin("password", true)
            advanceUntilIdle()
            assertEquals(1, source.deletes)
            model.load()
            assertNull(model.state.value.freshnessDiagnostic)
            advanceUntilIdle()
            assertTrue(model.state.value.unresolved)
            assertEquals(AccountDeletionFailure.UNCONFIRMED, model.state.value.error)
            assertEquals(1, source.deletes)
        }

    @Test
    fun tinyFutureCatchesUpWithoutRepeatingAnySdkOperationOrPolicy() = runTest {
        for (futureNanos in listOf(1L, 107_000_000L, 224_000_000L, 2_000_000_000L)) {
            var now = time.minusNanos(futureNanos)
            val timer = WaitTimer().apply { afterPause = { now = now.plusMillis(it) } }
            val source = Source()
            val journal = Journal()
            val gate = Gate()
            val repo =
                repository(
                    source,
                    journal,
                    gate,
                    clock = { now },
                    freshnessWait = AccountDeletionFreshnessWait(timer),
                )
            assertTrue(repo.start() is AccountDeletionStep.Completed)
            assertTrue(timer.pauses.isNotEmpty())
            assertTrue(timer.pauses.all { it in 1..25 })
            assertTrue(timer.pauses.sum() <= 2000)
            assertTrue(timer.nanos <= 2_000_000_000L)
            assertEquals(1, source.passwords)
            assertEquals(2, source.checks)
            assertEquals(1, source.deletes)
            assertEquals(1, journal.writes)
            assertEquals(1, gate.entered)
        }
    }

    @Test
    fun futureLargerThanTwoSecondsAndExpiredProofNeverWaitOrSubmit() = runTest {
        for (authenticatedAt in
            listOf(
                time.plusSeconds(2).plusNanos(1),
                time.plusSeconds(30),
                time.minusSeconds(240),
            )) {
            val timer = WaitTimer()
            val source =
                Source().apply { proof = AccountDeletionProof(alice.uid, authenticatedAt, false) }
            val journal = Journal()
            failure(AccountDeletionFailure.RECENT_AUTH_REQUIRED) {
                repository(source, journal, freshnessWait = AccountDeletionFreshnessWait(timer))
                    .start()
            }
            assertEquals(0, timer.reads)
            assertTrue(timer.pauses.isEmpty())
            assertEquals(1, source.passwords)
            assertEquals(1, source.checks)
            assertEquals(0, journal.writes)
            assertEquals(0, source.deletes)
        }
    }

    @Test
    fun wallClockBackwardsJumpCannotExtendMonotonicCatchupBudget() = runTest {
        var now = time.minusMillis(107)
        val timer = WaitTimer().apply { afterPause = { now = now.minusSeconds(10) } }
        val source = Source()
        val journal = Journal()
        try {
            repository(
                    source,
                    journal,
                    clock = { now },
                    freshnessWait = AccountDeletionFreshnessWait(timer),
                )
                .start()
            fail("A backwards wall clock must not permit deletion")
        } catch (error: AccountDeletionException) {
            assertEquals(AccountDeletionFailure.RECENT_AUTH_REQUIRED, error.failure)
            assertEquals(
                AccountDeletionFreshnessReason.WAIT_LIMIT_REACHED,
                error.freshnessDiagnostic?.reason,
            )
            assertEquals(
                AccountDeletionFreshnessStage.FIRST_CLOCK_CHECK,
                error.freshnessDiagnostic?.stage,
            )
        }
        assertEquals(2000L, timer.pauses.sum())
        assertEquals(2_000_000_000L, timer.nanos)
        assertEquals(1, source.passwords)
        assertEquals(0, journal.writes)
        assertEquals(0, source.deletes)
    }

    @Test
    fun lateSchedulerResumeOrMonotonicResetCannotGrantAccessEvenIfWallClockCaughtUp() = runTest {
        for (reset in listOf(false, true)) {
            var now = time.minusMillis(107)
            val timer =
                WaitTimer().apply {
                    afterPause = {
                        now = time.plusSeconds(1)
                        nanos = if (reset) -1 else 2_000_000_001L
                    }
                }
            val source = Source()
            val journal = Journal()
            try {
                repository(
                        source,
                        journal,
                        clock = { now },
                        freshnessWait = AccountDeletionFreshnessWait(timer),
                    )
                    .start()
                fail("A deadline cannot be renewed by clock catch-up")
            } catch (error: AccountDeletionException) {
                assertEquals(
                    AccountDeletionFreshnessReason.WAIT_LIMIT_REACHED,
                    error.freshnessDiagnostic?.reason,
                )
            }
            assertEquals(listOf(25L), timer.pauses)
            assertEquals(0, source.deletes)
            assertEquals(0, journal.writes)
        }
    }

    @Test
    fun noSecondCatchupIsPerformedIfPolicyReadMakesTheProofFutureAgain() = runTest {
        var now = time
        val timer = WaitTimer()
        val source = Source().apply { afterPolicy = { if (it == 2) now = time.minusMillis(107) } }
        val journal = Journal()
        try {
            repository(
                    source,
                    journal,
                    clock = { now },
                    freshnessWait = AccountDeletionFreshnessWait(timer),
                )
                .start()
            fail("Second guard stays strict with no second wait")
        } catch (error: AccountDeletionException) {
            assertEquals(
                AccountDeletionFreshnessStage.POST_POLICY_CLOCK_CHECK,
                error.freshnessDiagnostic?.stage,
            )
            assertEquals(AccountDeletionFreshnessReason.FUTURE, error.freshnessDiagnostic?.reason)
        }
        assertEquals(0, timer.reads)
        assertTrue(timer.pauses.isEmpty())
        assertEquals(2, source.checks)
        assertEquals(0, journal.writes)
        assertEquals(0, source.deletes)
    }

    @Test
    fun explicitAttemptCancellationDuringCatchupNeverCreatesJournalOrDelete() = runTest {
        var now = time.minusMillis(107)
        val timer = WaitTimer().apply { afterPause = { now = now.plusMillis(it) } }
        val source = Source()
        val journal = Journal()
        val attempt = AccountDeletionAttempt()
        val operation = async {
            repository(
                    source,
                    journal,
                    clock = { now },
                    freshnessWait = AccountDeletionFreshnessWait(timer),
                )
                .start(attempt)
        }
        runCurrent()
        assertEquals(1, source.passwords)
        attempt.cancelBeforeSubmission()
        advanceUntilIdle()
        assertTrue(operation.isCancelled)
        assertEquals(listOf(25L), timer.pauses)
        assertEquals(0, journal.writes)
        assertEquals(0, source.deletes)
    }

    @Test
    fun originalCallerCancellationStopsCatchupInsideNonCancellableIdentityGate() = runTest {
        var now = time.minusMillis(107)
        val timer = WaitTimer().apply { afterPause = { now = now.plusMillis(it) } }
        val source = Source()
        val journal = Journal()
        val gate = Gate()
        val operation = async {
            repository(
                    source,
                    journal,
                    gate,
                    clock = { now },
                    freshnessWait = AccountDeletionFreshnessWait(timer),
                )
                .start()
        }
        runCurrent()
        assertTrue(gate.inside)
        operation.cancel()
        assertTrue(gate.inside)
        advanceUntilIdle()
        assertTrue(operation.isCancelled)
        assertFalse(gate.inside)
        assertEquals(listOf(25L), timer.pauses)
        assertEquals(1, source.passwords)
        assertEquals(0, journal.writes)
        assertEquals(0, source.deletes)
    }

    @Test
    fun exactUidOrRevisionChangeDuringCatchupStopsBeforeJournalAndDelete() = runTest {
        for (next in listOf(bob, alice.copy(revision = alice.revision + 1))) {
            var authority = alice
            var now = time.minusMillis(107)
            val timer = WaitTimer().apply { afterPause = { now = now.plusMillis(it) } }
            val source = Source()
            val journal = Journal()
            val operation = async {
                repository(
                        source,
                        journal,
                        authority = { authority },
                        clock = { now },
                        freshnessWait = AccountDeletionFreshnessWait(timer),
                    )
                    .start()
            }
            runCurrent()
            authority = next
            advanceUntilIdle()
            assertTrue(operation.isCancelled)
            assertEquals(0, journal.writes)
            assertEquals(0, source.deletes)
            assertEquals(listOf(25L), timer.pauses)
        }
    }

    @Test
    fun clockSpecificErrorIsBilingualAndNeverUsedForServerOrExpiredProof() {
        for (language in listOf("de", "uk")) {
            val standard =
                accountDeletionFailureText(AccountDeletionFailure.RECENT_AUTH_REQUIRED, language)
            for (reason in
                listOf(
                    AccountDeletionFreshnessReason.FUTURE,
                    AccountDeletionFreshnessReason.WAIT_LIMIT_REACHED,
                )) {
                val text =
                    accountDeletionFailureText(
                        AccountDeletionFailure.RECENT_AUTH_REQUIRED,
                        language,
                        AccountDeletionFreshnessDiagnostic(
                            AccountDeletionFreshnessStage.FIRST_CLOCK_CHECK,
                            reason,
                            -107,
                        ),
                    )
                assertNotEquals(standard, text)
                assertTrue(
                    text.contains(
                        if (language == "de") "keine Löschung gesendet" else "не надіслано"
                    )
                )
            }
            for (reason in
                listOf(
                    AccountDeletionFreshnessReason.EXPIRED,
                    AccountDeletionFreshnessReason.SERVER_REJECTED,
                )) {
                assertEquals(
                    standard,
                    accountDeletionFailureText(
                        AccountDeletionFailure.RECENT_AUTH_REQUIRED,
                        language,
                        AccountDeletionFreshnessDiagnostic(
                            AccountDeletionFreshnessStage.CALLABLE,
                            reason,
                        ),
                    ),
                )
            }
        }
    }

    @Test
    fun actualReceiptSchemaIsRequiredAndMalformedSuccessIsAmbiguous() = runTest {
        assertEquals(
            AccountDeletionConfirmation.SERVER_RECEIPT,
            AccountDeletionContract.receipt(
                    mapOf("status" to "deleted", "completedAt" to time.toString())
                )
                .confirmation,
        )
        for (bad in
            listOf(
                null,
                true,
                emptyMap<String, Any>(),
                mapOf("status" to "ok", "completedAt" to time.toString()),
                mapOf("status" to "deleted", "completedAt" to "bad"),
                mapOf("status" to "deleted", "completedAt" to Instant.EPOCH.toString()),
            )) {
            failure(AccountDeletionFailure.UNCONFIRMED) { AccountDeletionContract.receipt(bad) }
        }
    }

    @Test
    fun scopeAllowsRestrictedUnverifiedAndMissingProfileNotGuestOrBusy() {
        val identity = AuthIdentity(alice.uid, "a@example.invalid", false)
        for (stage in
            listOf(
                AuthStage.AUTHENTICATED,
                AuthStage.VERIFICATION_PENDING,
                AuthStage.SESSION_UNAVAILABLE,
            )) {
            val session = AuthSession(stage, identity, revision = 1, gate = AuthGate.RESTRICTED)
            assertEquals(alice, session.accountDeletionScope())
            assertFalse(session.readyForActions)
            assertNull(session.copy(busy = true).accountDeletionScope())
        }
        assertNull(AuthSession(AuthStage.GUEST).accountDeletionScope())
        assertNull(
            AuthSession(AuthStage.AUTHENTICATED, identity.copy(anonymous = true))
                .accountDeletionScope()
        )
    }

    @Test
    fun guestAndMissingGateCannotReachAnySourceCall() = runTest {
        val source = Source()
        failure(AccountDeletionFailure.SIGN_IN) { repository(source, authority = { null }).start() }
        failure(AccountDeletionFailure.SIGN_IN) {
            AccountDeletionRepository(source, Journal(), { alice }).start()
        }
        assertEquals(0, source.checks)
        assertEquals(0, source.deletes)
    }

    @Test
    fun platformAndOrganizationOwnersRejectedBeforeCredentialsOrJournal() = runTest {
        for ((policy, reason) in
            listOf(
                ordinary.copy(platformOwner = true) to AccountDeletionFailure.PLATFORM_OWNER,
                ordinary.copy(ownsOrganization = true) to AccountDeletionFailure.ORGANIZATION_OWNER,
            )) {
            val source = Source().apply { this.policy = policy }
            val journal = Journal()
            failure(reason) { repository(source, journal).start() }
            assertEquals(0, source.passwords)
            assertEquals(0, journal.writes)
            assertEquals(0, source.deletes)
        }
    }

    @Test
    fun wrongPasswordAndCorruptCheckpointNeverSubmitOrClearExistingIntent() = runTest {
        val source =
            Source().apply {
                reauthFailure = AccountDeletionException(AccountDeletionFailure.INVALID_CREDENTIALS)
            }
        val journal = Journal()
        failure(AccountDeletionFailure.INVALID_CREDENTIALS) { repository(source, journal).start() }
        assertEquals(0, journal.writes)
        assertEquals(0, source.deletes)
        journal.failRead = true
        failure(AccountDeletionFailure.CHECKPOINT) { repository(source, journal).start() }
        assertEquals(1, source.passwords)
        assertEquals(0, source.deletes)
    }

    @Test
    fun unknownOwnerReadAndPartialStatusDoNotBypassRealServerDelete() = runTest {
        val source =
            Source().apply {
                policy =
                    ordinary.copy(
                        ownsOrganization = null,
                        profileMissing = true,
                        deletionInProgress = true,
                    )
            }
        assertTrue(repository(source).start() is AccountDeletionStep.Completed)
        assertEquals(2, source.checks)
        assertEquals(1, source.passwords)
        assertEquals(1, source.deletes)
    }

    @Test
    fun durableWriteOccursAfterActualReauthBeforeOnlyDeleteUnderSameGate() = runTest {
        val source = Source()
        val journal = Journal()
        val gate = Gate()
        journal.beforeWrite = {
            assertEquals(1, source.passwords)
            assertTrue(gate.inside)
            assertEquals(0, source.deletes)
        }
        source.beforeDelete = {
            assertTrue(gate.inside)
            assertEquals(1, journal.writes)
            assertEquals(time, journal.pending(alice.uid)?.submittedAt)
        }
        val result = repository(source, journal, gate).start() as AccountDeletionStep.Completed
        assertTrue(result.receipt.journalCleared)
        assertNull(journal.pending(alice.uid))
        assertEquals(1, gate.entered)
        assertFalse(gate.inside)
    }

    @Test
    fun checkpointWriteFailureStopsBeforeDestructionAndClearFailureKeepsTrueReceipt() = runTest {
        val source = Source()
        val journal = Journal().apply { failWrite = true }
        failure(AccountDeletionFailure.CHECKPOINT) { repository(source, journal).start() }
        assertEquals(1, source.passwords)
        assertEquals(0, source.deletes)
        journal.failWrite = false
        journal.failClear = true
        val completed = repository(source, journal).start() as AccountDeletionStep.Completed
        assertFalse(completed.receipt.journalCleared)
        assertNotNull(journal.pending(alice.uid))
        assertEquals(1, source.deletes)
    }

    @Test
    fun changedOwnershipAfterReauthStopsBeforeJournalAndServerDelete() = runTest {
        val source =
            Source().apply { afterReauth = { policy = ordinary.copy(ownsOrganization = true) } }
        val journal = Journal()
        failure(AccountDeletionFailure.ORGANIZATION_OWNER) { repository(source, journal).start() }
        assertEquals(0, journal.writes)
        assertEquals(0, source.deletes)
    }

    @Test
    fun proofUidFreshnessAndActualTotpClaimAreMandatory() = runTest {
        for ((proof, policy, reason) in
            listOf(
                Triple(
                    AccountDeletionProof(bob.uid, time, true),
                    ordinary,
                    AccountDeletionFailure.SIGN_IN,
                ),
                Triple(
                    AccountDeletionProof(alice.uid, time.minusSeconds(240), true),
                    ordinary,
                    AccountDeletionFailure.RECENT_AUTH_REQUIRED,
                ),
                Triple(
                    AccountDeletionProof(alice.uid, time, false),
                    ordinary.copy(requiresTotp = true),
                    AccountDeletionFailure.MFA_REQUIRED,
                ),
            )) {
            val source =
                Source().apply {
                    this.proof = proof
                    this.policy = policy
                }
            val journal = Journal()
            failure(reason) { repository(source, journal).start() }
            assertEquals(0, journal.writes)
            assertEquals(0, source.deletes)
        }
    }

    @Test
    fun slowSecondPreflightCannotUseNowStaleProof() = runTest {
        var now = time
        val source = Source().apply { afterPolicy = { if (it == 2) now = time.plusSeconds(240) } }
        failure(AccountDeletionFailure.RECENT_AUTH_REQUIRED) {
            repository(source, clock = { now }).start()
        }
        assertEquals(0, source.deletes)
    }

    @Test
    fun opaqueChallengeMustBeIssuedByThisRepositoryForExactSession() = runTest {
        val challenge = Challenge(AccountDeletionProof(alice.uid, time, true))
        var current = alice
        val source = Source().apply { reauthFailure = AccountDeletionChallengeRequired(challenge) }
        val repository = repository(source, authority = { current })
        failure(AccountDeletionFailure.SIGN_IN) {
            repository.completeChallenge(
                challenge,
                "opaque-totp-id",
                "123456",
                AccountDeletionAttempt(),
                {},
                {},
            )
        }
        assertTrue(repository.start() is AccountDeletionStep.Challenge)
        current = bob
        failure(AccountDeletionFailure.SIGN_IN) {
            repository.completeChallenge(
                challenge,
                "opaque-totp-id",
                "123456",
                AccountDeletionAttempt(),
                {},
                {},
            )
        }
        assertEquals(0, challenge.resolutions)
        assertEquals(0, source.deletes)
    }

    @Test
    fun actualChallengeRejectsBadFactorCodeAndCanRetryFreshCodeWithoutPasswordReplay() = runTest {
        val challenge = Challenge(AccountDeletionProof(alice.uid, time, true))
        val source =
            Source().apply {
                policy = ordinary.copy(requiresTotp = true)
                reauthFailure = AccountDeletionChallengeRequired(challenge)
            }
        val journal = Journal()
        val repository = repository(source, journal)
        val step = repository.start() as AccountDeletionStep.Challenge
        assertEquals(0, journal.writes)
        for ((factor, code) in
            listOf(
                "foreign" to "123456",
                "opaque-totp-id" to "123",
                "opaque-totp-id" to "１２３４５６",
            )) failure(AccountDeletionFailure.MFA_INVALID) {
            repository.completeChallenge(step.value, factor, code, AccountDeletionAttempt(), {}, {})
        }
        assertEquals(0, challenge.resolutions)
        challenge.failure = AccountDeletionFailure.MFA_INVALID
        failure(AccountDeletionFailure.MFA_INVALID) {
            repository.completeChallenge(
                step.value,
                "opaque-totp-id",
                "123456",
                AccountDeletionAttempt(),
                {},
                {},
            )
        }
        challenge.failure = null
        assertTrue(
            repository.completeChallenge(
                step.value,
                "opaque-totp-id",
                "654321",
                AccountDeletionAttempt(),
                {},
                {},
            ) is AccountDeletionStep.Completed
        )
        assertEquals(1, source.passwords)
        assertEquals(1, source.deletes)
    }

    @Test
    fun cancellationBeforeReauthOrAfterItsTaskNeverCreatesJournal() = runTest {
        val source = Source()
        val journal = Journal()
        val attempt = AccountDeletionAttempt().apply { cancelBeforeSubmission() }
        try {
            repository(source, journal).start(attempt)
            fail("Cancelled")
        } catch (_: CancellationException) {}
        assertEquals(0, source.passwords)
        val next = AccountDeletionAttempt()
        source.afterReauth = { next.cancelBeforeSubmission() }
        try {
            repository(source, journal).start(next)
            fail("Cancelled")
        } catch (_: CancellationException) {}
        assertEquals(0, journal.writes)
        assertEquals(0, source.deletes)
    }

    @Test
    fun accountSwitchDuringDiskCommitCannotStartServerRequestAndKeepsPendingJournal() = runTest {
        var current = alice
        val source = Source()
        val journal = Journal().apply { beforeWrite = { current = bob } }
        try {
            repository(source, journal, authority = { current }).start()
            fail("Switched")
        } catch (_: CancellationException) {}
        assertEquals(0, source.deletes)
        assertNotNull(journal.pending(alice.uid))
        assertNull(journal.pending(bob.uid))
    }

    @Test
    fun callerCancellationWaitsForActualDeletionBeforeUnlockingIdentity() = runTest {
        val settled = CompletableDeferred<Unit>()
        val gate = Gate()
        val journal = Journal()
        var actualFinished = false
        var nextIdentityEntered = false
        val source =
            Source().apply {
                afterDelete = {
                    settled.await()
                    actualFinished = true
                }
            }
        val operation = async { repository(source, journal, gate).start() }
        runCurrent()
        operation.cancel()
        val next = launch { gate.mutex.withLock { nextIdentityEntered = true } }
        runCurrent()
        assertTrue(gate.inside)
        assertFalse(nextIdentityEntered)
        assertFalse(actualFinished)
        settled.complete(Unit)
        operation.join()
        next.join()
        assertTrue(actualFinished)
        assertTrue(nextIdentityEntered)
        assertNull(journal.pending(alice.uid))
    }

    @Test
    fun ambiguousOutcomePersistsWithoutAutomaticOrEarlyExplicitRetry() = runTest {
        var now = time
        val source =
            Source().apply {
                deleteFailure = AccountDeletionException(AccountDeletionFailure.UNCONFIRMED)
            }
        val journal = Journal()
        val repository = repository(source, journal, clock = { now })
        failure(AccountDeletionFailure.UNCONFIRMED) { repository.start() }
        assertNotNull(journal.pending(alice.uid))
        failure(AccountDeletionFailure.UNCONFIRMED) { repository.start() }
        assertEquals(1, source.passwords)
        assertEquals(1, source.deletes)
        assertEquals(AccountDeletionIdentityStatus.PRESENT, repository.reconcile().first)
        now = time.plusSeconds(299)
        failure(AccountDeletionFailure.UNCONFIRMED) { repository.start() }
        assertEquals(1, source.deletes)
        now = time.plusSeconds(300)
        source.proof = source.proof.copy(authenticatedAt = now)
        source.deleteFailure = null
        assertTrue(repository.start() is AccountDeletionStep.Completed)
        assertEquals(2, source.passwords)
        assertEquals(2, source.deletes)
    }

    @Test
    fun elapsedTimeAloneDoesNotGrantRetryAndColdRepositoryMustReconcileAgain() = runTest {
        val journal = Journal().apply { record(alice.uid, time) }
        val source = Source()
        val now = time.plusSeconds(301)
        source.proof = source.proof.copy(authenticatedAt = now)
        val first = repository(source, journal, clock = { now })
        failure(AccountDeletionFailure.UNCONFIRMED) { first.start() }
        first.reconcile()
        val cold = repository(source, journal, clock = { now })
        failure(AccountDeletionFailure.UNCONFIRMED) { cold.start() }
        assertEquals(0, source.passwords)
        cold.reconcile()
        assertTrue(cold.start() is AccountDeletionStep.Completed)
    }

    @Test
    fun privateProfileMissingIsPartialNotConfirmedAndDisabledOrExpiredNeverClear() = runTest {
        val journal = Journal().apply { record(alice.uid, time) }
        val source = Source().apply { status = AccountDeletionIdentityStatus.PARTIAL }
        val repository = repository(source, journal)
        val (status, receipt) = repository.reconcile()
        assertEquals(AccountDeletionIdentityStatus.PARTIAL, status)
        assertNull(receipt)
        assertEquals(DeletionJournalStatus.PARTIAL, journal.pending(alice.uid)?.status)
        for (reason in
            listOf(
                AccountDeletionFailure.SIGN_IN,
                AccountDeletionFailure.DENIED,
                AccountDeletionFailure.OFFLINE,
            )) {
            source.statusFailure = AccountDeletionException(reason)
            failure(reason) { repository.reconcile() }
            assertNotNull(journal.pending(alice.uid))
        }
    }

    @Test
    fun exactAuthAbsenceCompletesOnlyOwnJournalNotOtherOrNewerEntry() = runTest {
        val journal =
            Journal().apply {
                record(alice.uid, time)
                record(bob.uid, time)
            }
        val source = Source().apply { status = AccountDeletionIdentityStatus.ABSENT }
        assertEquals(
            AccountDeletionConfirmation.AUTH_IDENTITY_ABSENT,
            repository(source, journal).reconcile().second?.confirmation,
        )
        assertNull(journal.pending(alice.uid))
        assertNotNull(journal.pending(bob.uid))
        assertEquals(0, source.deletes)
        journal.record(alice.uid, time.plusSeconds(1))
        assertFalse(journal.clearConfirmed(alice.uid, time))
        assertNotNull(journal.pending(alice.uid))
    }

    @Test
    fun stateProjectionClearsPrivateFactorAndReceiptBeforeCollectorRuns() {
        val state =
            AccountDeletionState(
                alice,
                factors = listOf(AccountDeletionFactor("private", "private")),
                submittedAt = time,
            )
        assertEquals(AccountDeletionState(bob), state.forSession(bob))
        assertEquals(AccountDeletionState(), state.forSession(null))
    }

    @Test
    fun viewModelRequiresConfirmationRejectsDuplicatesAndCallsBackAfterGateRelease() = runTest {
        val source = Source()
        val journal = Journal()
        val gate = Gate()
        var callbacks = 0
        val model =
            AccountDeletionViewModel(
                source,
                journal,
                { alice },
                gate,
                { session, _ ->
                    assertEquals(alice, session)
                    assertFalse(gate.inside)
                    callbacks++
                },
                { time },
            )
        model.bind(alice)
        model.load()
        advanceUntilIdle()
        model.begin("password", false)
        runCurrent()
        assertEquals(0, source.passwords)
        model.begin("password", true)
        model.begin("password", true)
        advanceUntilIdle()
        assertEquals(1, source.passwords)
        assertEquals(1, source.deletes)
        assertEquals(1, callbacks)
        assertNotNull(model.state.value.receipt)
        model.begin("password", true)
        advanceUntilIdle()
        assertEquals(1, source.deletes)
    }

    @Test
    fun viewModelPendingRestoreDoesNotSubmitAndMfaLoadDoesNotLoseChallenge() = runTest {
        val journal = Journal().apply { record(alice.uid, time) }
        val source = Source()
        val model =
            AccountDeletionViewModel(source, journal, { alice }, Gate(), { _, _ -> }, { time })
        model.bind(alice)
        model.load()
        advanceUntilIdle()
        assertTrue(model.state.value.unresolved)
        model.begin("password", true)
        advanceUntilIdle()
        assertEquals(0, source.passwords)
        val challenge = Challenge(AccountDeletionProof(alice.uid, time, true))
        source.reauthFailure = AccountDeletionChallengeRequired(challenge)
        val next =
            AccountDeletionViewModel(source, Journal(), { alice }, Gate(), { _, _ -> }, { time })
        next.bind(alice)
        next.load()
        advanceUntilIdle()
        next.begin("password", true)
        advanceUntilIdle()
        assertEquals(AccountDeletionPhase.MFA, next.state.value.phase)
        next.load()
        advanceUntilIdle()
        assertEquals(AccountDeletionPhase.MFA, next.state.value.phase)
        next.verifySecondFactor("opaque-totp-id", "123456")
        advanceUntilIdle()
        assertNotNull(next.state.value.receipt)
    }

    @Test
    fun viewModelSwitchMasksInflightDeletionAndNeverConfirmsNewIdentity() = runTest {
        var current = alice
        val completed = CompletableDeferred<Unit>()
        var callbacks = 0
        val source = Source().apply { afterDelete = { completed.await() } }
        val journal = Journal()
        val model =
            AccountDeletionViewModel(
                source,
                journal,
                { current },
                Gate(),
                { _, _ -> callbacks++ },
                { time },
            )
        model.bind(alice)
        model.load()
        advanceUntilIdle()
        model.begin("password", true)
        runCurrent()
        assertEquals(AccountDeletionPhase.DELETING, model.state.value.phase)
        model.cancelBeforeSubmission()
        assertFalse(model.state.value.cancelRequested)
        current = bob
        model.bind(bob)
        assertEquals(AccountDeletionState(bob), model.state.value)
        completed.complete(Unit)
        advanceUntilIdle()
        assertEquals(0, callbacks)
        assertEquals(AccountDeletionState(bob), model.state.value)
    }

    @Test
    fun viewModelPreSubmissionCancelAwaitsReauthWithoutDeleting() = runTest {
        val done = CompletableDeferred<Unit>()
        val source = Source().apply { beforeReauth = { done.await() } }
        val model =
            AccountDeletionViewModel(
                source,
                Journal(),
                { alice },
                Gate(),
                { _, _ -> fail("Cancelled receipt") },
                { time },
            )
        model.bind(alice)
        model.load()
        advanceUntilIdle()
        model.begin("password", true)
        runCurrent()
        model.cancelBeforeSubmission()
        assertTrue(model.state.value.cancelRequested)
        assertTrue(model.state.value.busy)
        done.complete(Unit)
        advanceUntilIdle()
        assertEquals(AccountDeletionPhase.IDLE, model.state.value.phase)
        assertFalse(model.state.value.cancelRequested)
        assertEquals(0, source.deletes)
    }
}
