package at.uac.android

import at.uac.android.feature.moderation.*
import com.google.firebase.Timestamp
import java.time.Instant
import java.util.UUID
import kotlin.coroutines.Continuation
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.test.*
import org.junit.Assert.*
import org.junit.Test

internal object ModerationDecisionUnitFixture {
    val actor = ModerationSession("synthetic-moderation-reviewer", 7, "admin", true)
    val time = Instant.parse("2026-09-03T10:00:00Z")

    fun target(kind: ModerationKind = ModerationKind.NEWS) =
        ModerationTarget(kind, "synthetic-review-target")

    fun fields(kind: ModerationKind = ModerationKind.NEWS): Map<String, Any?> =
        mapOf(
            "id" to target(kind).id,
            "organizationId" to "synthetic-review-org",
            "sourceType" to "organization",
            "moderationStatus" to "pendingReview",
            "updatedAt" to time,
            "createdAt" to time,
            "title" to "Private title",
            "body" to "Private complete body",
            "localizations" to mapOf("uk" to mapOf("body" to "Повний приватний текст")),
            "likeCount" to 1L,
            "registeredCount" to 3L,
        )

    fun version(kind: ModerationKind = ModerationKind.NEWS) =
        ModerationReviewVersion.from(target(kind), fields(kind))

    fun pending(phase: ModerationDecisionPhase = ModerationDecisionPhase.PREPARED) =
        ModerationPending(
            ModerationDecisionContract.accountHash(actor.uid),
            version(),
            UUID.randomUUID().toString(),
            actor.role,
            ModerationDecision.APPROVE,
            time,
            phase,
        )
}

@OptIn(ExperimentalCoroutinesApi::class)
class ModerationDecisionTest {
    private val actor = ModerationDecisionUnitFixture.actor
    private var live: ModerationSession? = actor
    private val version
        get() = ModerationDecisionUnitFixture.version()

    private class Journal : ModerationDecisionJournal {
        var entries = emptyList<ModerationPending>()
        var failPhase: ModerationDecisionPhase? = null
        var failRead = false
        var failClear = false
        var afterPrepared: (() -> Unit)? = null
        var readOverride: (suspend () -> List<ModerationPending>)? = null
        val phases = mutableListOf<ModerationDecisionPhase>()

        override suspend fun pending(uid: String): List<ModerationPending> {
            readOverride?.let {
                return it()
            }
            if (failRead) throw ModerationDecisionException(ModerationDecisionFailure.JOURNAL)
            return entries.filter { it.accountHash == ModerationDecisionContract.accountHash(uid) }
        }

        override suspend fun put(
            uid: String,
            entry: ModerationPending,
            expected: ModerationPending?,
        ): ModerationPending {
            if (entry.phase == failPhase)
                throw ModerationDecisionException(ModerationDecisionFailure.JOURNAL)
            assertEquals(
                expected,
                entries.firstOrNull {
                    it.version.target == entry.version.target && it.accountHash == entry.accountHash
                },
            )
            entries = entries.filterNot { it == expected } + entry
            ModerationDecisionJournalCodec.validate(entries)
            phases += entry.phase
            if (entry.phase == ModerationDecisionPhase.PREPARED) afterPrepared?.invoke()
            return entry
        }

        override suspend fun clear(uid: String, expected: ModerationPending) {
            if (failClear) throw ModerationDecisionException(ModerationDecisionFailure.JOURNAL)
            assertTrue(expected in entries)
            entries = entries - expected
        }
    }

    private class Source : ModerationDecisionSource {
        var authorizeError: Exception? = null
        var executionError: Exception? = null
        var readError: Exception? = null
        var beforeDispatch: CompletableDeferred<Unit>? = null
        var task: CompletableDeferred<Unit>? = null
        var readTask: CompletableDeferred<Unit>? = null
        var authorizeTimeout = false
        var readTimeout = false
        var authorizations = 0
        var calls = 0
        var dispatches = 0
        var reads = 0
        var observation = ModerationObservation.CONFIRMED_CURRENT

        override suspend fun authorize(session: ModerationSession) {
            authorizations++
            if (authorizeTimeout) withTimeout(1) { awaitCancellation() }
            authorizeError?.let { throw it }
        }

        override suspend fun execute(
            session: ModerationSession,
            pending: ModerationPending,
            canDispatch: () -> Boolean,
        ) {
            calls++
            assertEquals(ModerationDecisionPhase.DISPATCHED, pending.phase)
            beforeDispatch?.await()
            if (!canDispatch()) throw ModerationDecisionException(ModerationDecisionFailure.STALE)
            dispatches++
            task?.await()
            executionError?.let { throw it }
        }

        override suspend fun reconcile(
            session: ModerationSession,
            pending: ModerationPending,
        ): ModerationObservation {
            reads++
            if (readTimeout) withTimeout(1) { awaitCancellation() }
            readTask?.await()
            readError?.let { throw it }
            return observation
        }
    }

    private class Gate : ModerationDecisionGate {
        val mutex = Mutex()
        var held = false

        override suspend fun <T> withSession(
            session: ModerationSession,
            action: suspend () -> T,
        ): T = mutex.withLock {
            held = true
            try {
                action()
            } finally {
                held = false
            }
        }
    }

    private fun repository(source: Source, journal: Journal, gate: Gate = Gate()) =
        ModerationDecisionRepository(
            source,
            journal,
            { live },
            gate,
            { ModerationDecisionUnitFixture.time },
        )

    private suspend fun failure(expected: ModerationDecisionFailure, action: suspend () -> Any?) {
        try {
            action()
            fail("Expected scoped decision failure")
        } catch (error: ModerationDecisionException) {
            assertEquals(expected, error.failure)
        }
    }

    private fun invalid(action: () -> Any?) {
        try {
            action()
            fail("Expected invalid reviewed version")
        } catch (error: ModerationDecisionException) {
            assertEquals(ModerationDecisionFailure.INVALID, error.failure)
        }
    }

    @Test
    fun mapOrderAndIntWidthsDoNotChangeRawCanonicalVersion() {
        val fields = ModerationDecisionUnitFixture.fields()
        assertEquals(
            version,
            ModerationReviewVersion.from(
                version.target,
                fields.entries.reversed().associate { it.toPair() },
            ),
        )
        assertEquals(
            ModerationReviewVersion.hash(version.target, mapOf("n" to 7)),
            ModerationReviewVersion.hash(version.target, mapOf("n" to 7L)),
        )
    }

    @Test
    fun int64ValuesAboveDoublePrecisionRemainDifferent() {
        assertNotEquals(
            ModerationReviewVersion.hash(version.target, mapOf("n" to 9_007_199_254_740_992L)),
            ModerationReviewVersion.hash(version.target, mapOf("n" to 9_007_199_254_740_993L)),
        )
    }

    @Test
    fun numericTypesAndNegativeZeroAreDistinct() {
        val hash: (Any) -> String = {
            ModerationReviewVersion.hash(version.target, mapOf("n" to it))
        }
        assertNotEquals(hash(1L), hash(1.0))
        assertNotEquals(hash(0.0), hash(-0.0))
    }

    @Test
    fun nullMissingArrayOrderAndWhitespaceRemainDistinct() {
        val h: (Map<String, Any?>) -> String = { ModerationReviewVersion.hash(version.target, it) }
        assertNotEquals(h(emptyMap()), h(mapOf("x" to null)))
        assertNotEquals(h(mapOf("x" to listOf(1, 2))), h(mapOf("x" to listOf(2, 1))))
        assertNotEquals(h(mapOf("x" to " text")), h(mapOf("x" to "text")))
    }

    @Test
    fun sdkAndInstantTimestampUseExactSecondsAndNanoseconds() {
        val t = ModerationDecisionUnitFixture.time
        val h: (Any) -> String = { ModerationReviewVersion.hash(version.target, mapOf("t" to it)) }
        assertEquals(h(t), h(Timestamp(t.epochSecond, t.nano)))
        assertNotEquals(h(t), h(t.plusNanos(1)))
    }

    @Test
    fun allKnownRootCountersAreExcludedButNestedAndUnknownFieldsAreReviewed() {
        val target = ModerationDecisionUnitFixture.target(ModerationKind.EVENT)
        val fields = ModerationDecisionUnitFixture.fields(ModerationKind.EVENT)
        val original = ModerationReviewVersion.from(target, fields)
        assertEquals(
            original,
            ModerationReviewVersion.from(
                target,
                fields +
                    mapOf(
                        "registeredCount" to 900L,
                        "commentCount" to 8L,
                        "viewCount" to 19L,
                        "likeCount" to 66L,
                    ),
            ),
        )
        assertNotEquals(
            original,
            ModerationReviewVersion.from(target, fields + ("nested" to mapOf("likeCount" to 9L))),
        )
        assertNotEquals(
            version,
            ModerationReviewVersion.from(
                version.target,
                ModerationDecisionUnitFixture.fields() + ("registeredCount" to 9L),
            ),
        )
    }

    @Test
    fun everyBodyLocalizationMediaScheduleAndUnknownChangeInvalidatesReviewedVersion() {
        for ((key, value) in
            mapOf(
                "body" to "changed",
                "localizations" to mapOf("uk" to mapOf("body" to "зміна")),
                "imageURL" to "https://example.invalid/new",
                "scheduledAt" to ModerationDecisionUnitFixture.time,
                "future" to true,
            )) assertNotEquals(
            version,
            ModerationReviewVersion.from(
                version.target,
                ModerationDecisionUnitFixture.fields() + (key to value),
            ),
        )
    }

    @Test
    fun preservedHashExcludesOnlyDecisionFieldsAndCounters() {
        val fields = ModerationDecisionUnitFixture.fields()
        assertEquals(
            version.preservedHash,
            ModerationReviewVersion.hash(
                version.target,
                fields +
                    mapOf(
                        "moderationStatus" to "approved",
                        "updatedAt" to ModerationDecisionUnitFixture.time.plusSeconds(1),
                    ),
                true,
            ),
        )
        assertNotEquals(
            version.preservedHash,
            ModerationReviewVersion.hash(
                version.target,
                fields + ("publishedAt" to ModerationDecisionUnitFixture.time),
                true,
            ),
        )
    }

    @Test
    fun organizationApprovedAndWrongSourceNeverAcquireDecisionVersion() {
        invalid {
            ModerationReviewVersion.from(
                ModerationDecisionUnitFixture.target(ModerationKind.ORGANIZATION),
                ModerationDecisionUnitFixture.fields(),
            )
        }
        invalid {
            ModerationReviewVersion.from(
                version.target,
                ModerationDecisionUnitFixture.fields() + ("moderationStatus" to "approved"),
            )
        }
        invalid {
            ModerationReviewVersion.from(
                version.target,
                ModerationDecisionUnitFixture.fields() + ("sourceType" to "app"),
            )
        }
    }

    @Test
    fun unsupportedNonFiniteAndMalformedUnicodeFailClosed() {
        for (value in
            listOf(
                Any(),
                byteArrayOf(1),
                Double.NaN,
                Double.POSITIVE_INFINITY,
                "\uD800",
                "\uDC00",
            )) invalid { ModerationReviewVersion.hash(version.target, mapOf("x" to value)) }
        assertNotNull(ModerationReviewVersion.hash(version.target, mapOf("x" to "Їжак 🦔")))
    }

    @Test
    fun cumulativeUtf8BudgetPrecedesLargeStringAllocation() {
        assertNotNull(
            ModerationReviewVersion.hash(version.target, mapOf("body" to "x".repeat(900_000)))
        )
        invalid {
            ModerationReviewVersion.hash(
                version.target,
                mapOf("body" to "x".repeat(ModerationReviewVersion.MAX_BYTES)),
            )
        }
        invalid {
            ModerationReviewVersion.hash(
                version.target,
                mapOf("a" to "я".repeat(300_000), "b" to "я".repeat(300_000)),
            )
        }
    }

    @Test
    fun nestedCumulativeEntryAndDepthLimitsAreBounded() {
        invalid { ModerationReviewVersion.hash(version.target, mapOf("x" to List(4096) { 1 })) }
        var nested: Any? = "leaf"
        repeat(25) { nested = listOf(nested) }
        invalid { ModerationReviewVersion.hash(version.target, mapOf("x" to nested)) }
    }

    @Test
    fun receiptCoreMatchesExistingSchemaAndDoesNotContainReviewedPrivateText() {
        val entry = ModerationDecisionUnitFixture.pending()
        val fields = ModerationDecisionContract.receiptFields(entry, actor.uid)
        assertEquals(2L, fields["severityRank"])
        assertEquals(true, fields["isAppAdminReadable"])
        assertEquals("approveNewsPost", fields["operationName"])
        assertTrue((fields["metadata"] as Map<*, *>).values.all { it is String })
        assertFalse(fields.toString().contains("Private complete body"))
        assertFalse(fields.containsKey("actorDisplayName"))
        assertEquals(
            false,
            ModerationDecisionContract.receiptFields(entry.copy(issuedRole = "owner"), actor.uid)[
                    "isAppAdminReadable"],
        )
    }

    @Test
    fun onlyLegitimateReviewAcknowledgementMayChangeReceipt() {
        val entry = ModerationDecisionUnitFixture.pending()
        val original =
            ModerationDecisionContract.receiptFields(entry, actor.uid) +
                mapOf("createdAt" to entry.issuedAt, "isReviewed" to false)
        assertEquals(
            entry.issuedAt,
            ModerationDecisionContract.receiptTime(entry, actor.uid, original),
        )
        assertEquals(
            entry.issuedAt,
            ModerationDecisionContract.receiptTime(
                entry,
                actor.uid,
                original +
                    mapOf(
                        "isReviewed" to true,
                        "reviewedAt" to entry.issuedAt,
                        "reviewedByUserId" to "synthetic-other-admin",
                    ),
            ),
        )
        for (change in
            listOf(
                mapOf("targetId" to "another"),
                mapOf("outcome" to "rejected"),
                mapOf("extra" to true),
                mapOf("severityRank" to 2.0),
                mapOf("isReviewed" to true),
                mapOf("metadata" to emptyMap<String, String>()),
            )) assertNull(
            ModerationDecisionContract.receiptTime(entry, actor.uid, original + change)
        )
    }

    @Test
    fun happyPathDurablyStagesBeforeOneSdkCallAndClearsOnlyMatchingReceipt() = runTest {
        val source = Source()
        val journal = Journal()
        assertEquals(
            ModerationObservation.CONFIRMED_CURRENT,
            repository(source, journal).execute(actor, version, ModerationDecision.APPROVE) {
                true
            },
        )
        assertEquals(
            listOf(
                ModerationDecisionPhase.PREPARED,
                ModerationDecisionPhase.DISPATCHED,
                ModerationDecisionPhase.ACKNOWLEDGED,
            ),
            journal.phases,
        )
        assertEquals(1, source.dispatches)
        assertTrue(journal.entries.isEmpty())
    }

    @Test
    fun authorizationFailureAndInvisiblePreviewDoNotCreatePendingOrDispatch() = runTest {
        val source =
            Source().apply {
                authorizeError = ModerationDecisionException(ModerationDecisionFailure.ACCESS)
            }
        val journal = Journal()
        val repo = repository(source, journal)
        failure(ModerationDecisionFailure.STALE) {
            repo.execute(actor, version, ModerationDecision.APPROVE) { false }
        }
        failure(ModerationDecisionFailure.ACCESS) {
            repo.execute(actor, version, ModerationDecision.APPROVE) { true }
        }
        assertEquals(0, source.calls)
        assertTrue(journal.entries.isEmpty())
    }

    @Test
    fun anyExistingPendingPhaseBlocksSameTargetWithoutAuthorizingOrDispatching() = runTest {
        for (phase in ModerationDecisionPhase.entries) {
            val source = Source()
            val journal =
                Journal().apply { entries = listOf(ModerationDecisionUnitFixture.pending(phase)) }
            failure(ModerationDecisionFailure.PENDING) {
                repository(source, journal).execute(actor, version, ModerationDecision.REJECT) {
                    true
                }
            }
            assertEquals(0, source.authorizations)
            assertEquals(0, source.calls)
        }
    }

    @Test
    fun preparedAndDispatchedStorageFailuresNeverStartTheSdk() = runTest {
        for (phase in
            listOf(ModerationDecisionPhase.PREPARED, ModerationDecisionPhase.DISPATCHED)) {
            val source = Source()
            val journal = Journal().apply { failPhase = phase }
            failure(ModerationDecisionFailure.JOURNAL) {
                repository(source, journal).execute(actor, version, ModerationDecision.APPROVE) {
                    true
                }
            }
            assertEquals(0, source.dispatches)
        }
    }

    @Test
    fun confirmationLostWhilePreparedCanClearOnlyKnownUnsentEntry() = runTest {
        var visible = true
        val source = Source()
        val journal = Journal().apply { afterPrepared = { visible = false } }
        failure(ModerationDecisionFailure.STALE) {
            repository(source, journal).execute(actor, version, ModerationDecision.APPROVE) {
                visible
            }
        }
        assertTrue(journal.entries.isEmpty())
        assertEquals(0, source.calls)
    }

    @Test
    fun originalCallerCancelledDuringPendingReadStopsBeforeAuthorizationAndJournalWrite() =
        runTest {
            val readStarted = CompletableDeferred<Unit>()
            val finishRead = CompletableDeferred<Unit>()
            val source = Source()
            val journal =
                Journal().apply {
                    readOverride = {
                        readStarted.complete(Unit)
                        finishRead.await()
                        emptyList()
                    }
                }
            val repo = repository(source, journal)
            val action = async {
                repo.execute(actor, version, ModerationDecision.APPROVE) { true }
            }
            runCurrent()
            assertTrue(readStarted.isCompleted)
            action.cancel()
            finishRead.complete(Unit)
            advanceUntilIdle()
            assertTrue(action.isCancelled)
            assertEquals(0, source.authorizations)
            assertEquals(0, source.calls)
            assertEquals(0, source.dispatches)
            assertTrue(journal.phases.isEmpty())
            assertTrue(journal.entries.isEmpty())
        }

    @Test
    fun originalCallerCancelledAfterPreparedCannotDispatchWhenPresentationRemainsCurrent() =
        runTest {
            val source = Source()
            lateinit var action: Deferred<ModerationObservation>
            val journal = Journal().apply { afterPrepared = { action.cancel() } }
            val repo = repository(source, journal)
            action = async {
                repo.execute(actor, version, ModerationDecision.APPROVE) { true }
            }
            advanceUntilIdle()
            assertTrue(action.isCancelled)
            assertEquals(
                "Cancellation must veto an operation not yet dispatched",
                0,
                source.dispatches,
            )
            assertEquals(listOf(ModerationDecisionPhase.PREPARED), journal.phases)
            assertTrue(
                "Only the exact known-unsent PREPARED entry may be cleared",
                journal.entries.isEmpty(),
            )
        }

    @Test
    fun originalCallerCancelledDuringFinalAuthorizationRetainsDispatchedWithoutSending() = runTest {
        val finalAuthorization = CompletableDeferred<Unit>()
        val source = Source().apply { beforeDispatch = finalAuthorization }
        val journal = Journal()
        val repo = repository(source, journal)
        val action = async {
            repo.execute(actor, version, ModerationDecision.APPROVE) { true }
        }
        runCurrent()
        assertEquals(ModerationDecisionPhase.DISPATCHED, journal.entries.single().phase)
        assertEquals(0, source.dispatches)
        action.cancel()
        finalAuthorization.complete(Unit)
        advanceUntilIdle()
        assertTrue(action.isCancelled)
        assertEquals(
            "Final dispatch callback must also sample the original Job",
            0,
            source.dispatches,
        )
        assertEquals(ModerationDecisionPhase.DISPATCHED, journal.entries.single().phase)
    }

    @Test
    fun delayedFinalSdkAuthorizationRechecksScopeBeforeDispatch() = runTest {
        val ready = CompletableDeferred<Unit>()
        val source = Source().apply { beforeDispatch = ready }
        val journal = Journal()
        val repo = repository(source, journal)
        val action = async {
            runCatching { repo.execute(actor, version, ModerationDecision.APPROVE) { true } }
        }
        runCurrent()
        live = actor.copy(revision = actor.revision + 1)
        ready.complete(Unit)
        advanceUntilIdle()
        assertTrue(action.await().isFailure)
        assertEquals(0, source.dispatches)
        assertEquals(ModerationDecisionPhase.DISPATCHED, journal.entries.single().phase)
    }

    @Test
    fun discardedAckCanOnlyRecoverByReadingReceiptNotByAnotherSend() = runTest {
        val source = Source().apply { executionError = java.io.IOException("Synthetic lost ACK") }
        val journal = Journal()
        val repo = repository(source, journal)
        failure(ModerationDecisionFailure.UNCONFIRMED) {
            repo.execute(actor, version, ModerationDecision.APPROVE) { true }
        }
        assertEquals(ModerationDecisionPhase.DISPATCHED, journal.entries.single().phase)
        failure(ModerationDecisionFailure.PENDING) {
            repo.execute(actor, version, ModerationDecision.APPROVE) { true }
        }
        assertEquals(
            ModerationObservation.CONFIRMED_CURRENT,
            repo.reconcile(actor, journal.entries.single()),
        )
        assertEquals(1, source.dispatches)
        assertTrue(journal.entries.isEmpty())
    }

    @Test
    fun acknowledgedStorageFailureRetainsDispatchedMarkerAfterRealTask() = runTest {
        val source = Source()
        val journal = Journal().apply { failPhase = ModerationDecisionPhase.ACKNOWLEDGED }
        failure(ModerationDecisionFailure.JOURNAL) {
            repository(source, journal).execute(actor, version, ModerationDecision.APPROVE) { true }
        }
        assertEquals(1, source.dispatches)
        assertEquals(ModerationDecisionPhase.DISPATCHED, journal.entries.single().phase)
    }

    @Test
    fun readBackFailureKeepsAcknowledgedPendingAndNeverRetriesMutation() = runTest {
        val source = Source().apply { readError = java.io.IOException("Synthetic offline read") }
        val journal = Journal()
        val repo = repository(source, journal)
        failure(ModerationDecisionFailure.UNCONFIRMED) {
            repo.execute(actor, version, ModerationDecision.APPROVE) { true }
        }
        assertEquals(ModerationDecisionPhase.ACKNOWLEDGED, journal.entries.single().phase)
        assertEquals(1, source.dispatches)
    }

    @Test
    fun allUnprovenOrAuthorityLimitedObservationsKeepExactJournalWithoutReplay() = runTest {
        for (observation in ModerationObservation.entries.filterNot { it.confirmed }) {
            val entry = ModerationDecisionUnitFixture.pending(ModerationDecisionPhase.DISPATCHED)
            val source = Source().apply { this.observation = observation }
            val journal = Journal().apply { entries = listOf(entry) }
            val repo = repository(source, journal)
            repeat(2) { assertEquals(observation, repo.reconcile(actor, entry)) }
            assertEquals(listOf(entry), journal.entries)
            assertEquals(0, source.calls)
        }
    }

    @Test
    fun confirmedLaterChangedOrUnavailableClearsWithoutReassertingDesiredStatus() = runTest {
        for (observation in
            listOf(
                ModerationObservation.CONFIRMED_CHANGED,
                ModerationObservation.CONFIRMED_UNAVAILABLE,
            )) {
            val entry = ModerationDecisionUnitFixture.pending(ModerationDecisionPhase.DISPATCHED)
            val source = Source().apply { this.observation = observation }
            val journal = Journal().apply { entries = listOf(entry) }
            assertEquals(observation, repository(source, journal).reconcile(actor, entry))
            assertEquals(0, source.calls)
            assertTrue(journal.entries.isEmpty())
        }
    }

    @Test
    fun terminalJournalClearFailureCannotEnableAnotherDecision() = runTest {
        val source = Source()
        val journal = Journal().apply { failClear = true }
        val repo = repository(source, journal)
        failure(ModerationDecisionFailure.JOURNAL) {
            repo.execute(actor, version, ModerationDecision.APPROVE) { true }
        }
        failure(ModerationDecisionFailure.PENDING) {
            repo.execute(actor, version, ModerationDecision.APPROVE) { true }
        }
        assertEquals(1, source.dispatches)
    }

    @Test
    fun foreignAccountAndWrongStoredBackendCannotBeRecovered() = runTest {
        val entry = ModerationDecisionUnitFixture.pending()
        val source = Source()
        val journal = Journal().apply { entries = listOf(entry) }
        val repo = repository(source, journal)
        val foreign = actor.copy(uid = "another-synthetic-reviewer")
        live = foreign
        failure(ModerationDecisionFailure.ACCESS) { repo.reconcile(foreign, entry) }
        live = actor
        failure(ModerationDecisionFailure.INVALID) {
            repo.reconcile(actor, entry.copy(backend = "not-the-local-project"))
        }
        assertEquals(0, source.reads)
    }

    @Test
    fun cancellingCallerCannotDetachActualTaskOrReleaseIdentityMutexEarly() = runTest {
        val done = CompletableDeferred<Unit>()
        val source = Source().apply { task = done }
        val journal = Journal()
        val gate = Gate()
        val repo = repository(source, journal, gate)
        var delivered = false
        val action = launch {
            repo.execute(actor, version, ModerationDecision.APPROVE) { true }
            delivered = true
        }
        runCurrent()
        action.cancel()
        runCurrent()
        assertFalse(action.isCompleted)
        assertTrue(gate.held)
        var transitioned = false
        val transition = launch { gate.mutex.withLock { transitioned = true } }
        runCurrent()
        assertFalse(transitioned)
        done.complete(Unit)
        advanceUntilIdle()
        action.join()
        transition.join()
        assertTrue(transitioned)
        assertTrue(action.isCancelled)
        assertFalse(delivered)
        assertEquals(1, source.dispatches)
    }

    @Test
    fun cancelledCallerWaitsForLateSdkFailureAndKeepsPending() = runTest {
        val done = CompletableDeferred<Unit>()
        val source =
            Source().apply {
                task = done
                executionError = java.io.IOException("Synthetic late failure")
            }
        val journal = Journal()
        val gate = Gate()
        val action = launch {
            repository(source, journal, gate).execute(actor, version, ModerationDecision.APPROVE) {
                true
            }
        }
        runCurrent()
        action.cancel()
        runCurrent()
        assertTrue(gate.held)
        done.complete(Unit)
        advanceUntilIdle()
        action.join()
        assertTrue(action.isCancelled)
        assertEquals(ModerationDecisionPhase.DISPATCHED, journal.entries.single().phase)
        assertEquals(1, source.dispatches)
    }

    @Test
    fun viewConfirmationIsOneUseAndInvalidatedByNewPresentationToken() = runTest {
        val source = Source()
        val model = ModerationDecisionViewModel(repository(source, Journal()), workScope = this)
        model.bindView(actor, version, ModerationPresentation()) { true }
        runCurrent()
        model.request(ModerationDecision.APPROVE)
        assertEquals(ModerationDecision.APPROVE, model.state.value.confirmation)
        model.bindView(actor, version, ModerationPresentation()) { true }
        assertNull(model.state.value.confirmation)
        model.confirm()
        runCurrent()
        assertEquals(0, source.calls)
    }

    @Test
    fun livePreviewVetoAfterClickStopsDelayedSdkAndRepeatedClicksSendAtMostOnce() = runTest {
        var visible = true
        val ready = CompletableDeferred<Unit>()
        val source = Source().apply { beforeDispatch = ready }
        val journal = Journal()
        val model = ModerationDecisionViewModel(repository(source, journal), workScope = this)
        model.bindView(actor, version, ModerationPresentation()) { visible }
        runCurrent()
        model.request(ModerationDecision.APPROVE)
        model.confirm()
        model.confirm()
        runCurrent()
        visible = false
        ready.complete(Unit)
        advanceUntilIdle()
        assertEquals(0, source.dispatches)
        assertEquals(1, source.calls)
        assertTrue(model.state.value.pending.isNotEmpty())
    }

    @Test
    fun delayedAuthBindMasksPendingAndSameUidRevisionImmediately() = runTest {
        val journal = Journal().apply { entries = listOf(ModerationDecisionUnitFixture.pending()) }
        val model = ModerationDecisionViewModel(repository(Source(), journal), workScope = this)
        model.bindView(actor, version, ModerationPresentation()) { true }
        runCurrent()
        assertEquals(1, model.snapshot(actor).pending.size)
        live = actor.copy(revision = actor.revision + 1)
        assertTrue(model.snapshot(live).pending.isEmpty())
        assertTrue(model.snapshot(actor).pending.isEmpty())
    }

    @Test
    fun journalRecoveryCanBeReadExplicitlyWithoutSelectingAnyContentPreview() = runTest {
        val journal = Journal().apply { entries = listOf(ModerationDecisionUnitFixture.pending()) }
        val source = Source().apply { observation = ModerationObservation.UNCONFIRMED }
        val model = ModerationDecisionViewModel(repository(source, journal), workScope = this)
        model.bindView(actor, null, ModerationPresentation()) { true }
        runCurrent()
        model.reconcile(model.state.value.pending.single())
        advanceUntilIdle()
        assertEquals(1, source.reads)
        assertEquals(0, source.dispatches)
        model.request(ModerationDecision.APPROVE)
        assertNull(model.state.value.confirmation)
    }

    @Test
    fun nonCooperativeOldJournalReadCannotReplaceNewerSameSessionList() = runTest {
        val old = ModerationDecisionUnitFixture.pending()
        val journal = Journal()
        lateinit var delayed: Continuation<List<ModerationPending>>
        journal.readOverride = { suspendCoroutine { delayed = it } }
        val model = ModerationDecisionViewModel(repository(Source(), journal), workScope = this)
        model.bind(actor)
        runCurrent()
        journal.readOverride = null
        model.refreshPending()
        runCurrent()
        assertTrue(model.state.value.journalReady)
        assertTrue(model.state.value.pending.isEmpty())
        delayed.resume(listOf(old))
        advanceUntilIdle()
        assertTrue(model.state.value.journalReady)
        assertTrue(model.state.value.pending.isEmpty())
        assertNull(model.state.value.error)
    }

    @Test
    fun nonCooperativeOldJournalFailureCannotInvalidateNewerReadyState() = runTest {
        val journal = Journal()
        lateinit var delayed: Continuation<List<ModerationPending>>
        journal.readOverride = { suspendCoroutine { delayed = it } }
        val model = ModerationDecisionViewModel(repository(Source(), journal), workScope = this)
        model.bind(actor)
        runCurrent()
        journal.readOverride = null
        model.refreshPending()
        runCurrent()
        delayed.resumeWithException(ModerationDecisionException(ModerationDecisionFailure.JOURNAL))
        advanceUntilIdle()
        assertTrue(model.state.value.journalReady)
        assertNull(model.state.value.error)
    }

    @Test
    fun nonCooperativeRefreshCannotRestorePendingAfterExplicitReconcileClearsIt() = runTest {
        val old = ModerationDecisionUnitFixture.pending()
        val journal = Journal().apply { entries = listOf(old) }
        val source = Source()
        val model = ModerationDecisionViewModel(repository(source, journal), workScope = this)
        model.bindView(actor, null, ModerationPresentation()) { true }
        runCurrent()
        lateinit var delayed: Continuation<List<ModerationPending>>
        journal.readOverride = { suspendCoroutine { delayed = it } }
        model.refreshPending()
        runCurrent()
        journal.readOverride = null
        model.reconcile(old)
        runCurrent()
        assertEquals(1L, model.state.value.completion)
        assertTrue(model.state.value.pending.isEmpty())
        delayed.resume(listOf(old))
        advanceUntilIdle()
        assertTrue(model.state.value.pending.isEmpty())
        assertTrue(model.state.value.journalReady)
        assertEquals(ModerationObservation.CONFIRMED_CURRENT, model.state.value.observation)
        assertEquals(1, source.reads)
        assertEquals(0, source.dispatches)
    }

    @Test
    fun standaloneReconcileHoldsSameIdentityGateThroughReadAndConfirmedJournalClear() = runTest {
        val entry = ModerationDecisionUnitFixture.pending(ModerationDecisionPhase.DISPATCHED)
        val done = CompletableDeferred<Unit>()
        val source = Source().apply { readTask = done }
        val journal = Journal().apply { entries = listOf(entry) }
        val gate = Gate()
        val repo = repository(source, journal, gate)
        val action = async { repo.reconcile(actor, entry) }
        runCurrent()
        assertTrue(gate.held)
        var transition = false
        val next = launch {
            gate.mutex.withLock {
                transition = true
                assertTrue(journal.entries.isEmpty())
            }
        }
        runCurrent()
        assertFalse(transition)
        done.complete(Unit)
        advanceUntilIdle()
        assertEquals(ModerationObservation.CONFIRMED_CURRENT, action.await())
        next.join()
        assertTrue(transition)
        assertEquals(0, source.dispatches)
    }

    @Test
    fun cancelledReconcileWaitsForReadSettlementWithoutDeliveringResultOrReplaying() = runTest {
        val entry = ModerationDecisionUnitFixture.pending(ModerationDecisionPhase.DISPATCHED)
        val done = CompletableDeferred<Unit>()
        val source = Source().apply { readTask = done }
        val journal = Journal().apply { entries = listOf(entry) }
        val gate = Gate()
        var delivered = false
        val action = launch {
            repository(source, journal, gate).reconcile(actor, entry)
            delivered = true
        }
        runCurrent()
        action.cancel()
        runCurrent()
        assertTrue(gate.held)
        assertFalse(action.isCompleted)
        done.complete(Unit)
        advanceUntilIdle()
        action.join()
        assertTrue(action.isCancelled)
        assertFalse(delivered)
        assertFalse(gate.held)
        assertTrue(journal.entries.isEmpty())
        assertEquals(1, source.reads)
        assertEquals(0, source.dispatches)
    }

    @Test
    fun cancelledReconcileLateReadFailureRetainsJournalWithoutActiveUiError() = runTest {
        val entry = ModerationDecisionUnitFixture.pending()
        val done = CompletableDeferred<Unit>()
        val source =
            Source().apply {
                readTask = done
                readError = java.io.IOException("Synthetic read failure")
            }
        val journal = Journal().apply { entries = listOf(entry) }
        val gate = Gate()
        val action = launch { repository(source, journal, gate).reconcile(actor, entry) }
        runCurrent()
        action.cancel()
        runCurrent()
        assertTrue(gate.held)
        done.complete(Unit)
        advanceUntilIdle()
        action.join()
        assertTrue(action.isCancelled)
        assertEquals(listOf(entry), journal.entries)
        assertEquals(0, source.dispatches)
    }

    @Test
    fun exactLiveScopeLossDuringReadCannotClearPendingOrDeliverConfirmation() = runTest {
        val entry = ModerationDecisionUnitFixture.pending()
        val done = CompletableDeferred<Unit>()
        val source = Source().apply { readTask = done }
        val journal = Journal().apply { entries = listOf(entry) }
        val repo = repository(source, journal)
        val action = async { runCatching { repo.reconcile(actor, entry) } }
        runCurrent()
        live = actor.copy(revision = actor.revision + 1)
        done.complete(Unit)
        advanceUntilIdle()
        assertTrue(action.await().exceptionOrNull() is CancellationException)
        assertEquals(listOf(entry), journal.entries)
        assertEquals(0, source.dispatches)
    }

    @Test
    fun preflightTimeoutReturnsOfflineAndClearsBusyWithoutJournalOrSdkDispatch() = runTest {
        val source = Source().apply { authorizeTimeout = true }
        val journal = Journal()
        val model = ModerationDecisionViewModel(repository(source, journal), workScope = this)
        model.bindView(actor, version, ModerationPresentation()) { true }
        runCurrent()
        model.request(ModerationDecision.APPROVE)
        model.confirm()
        advanceUntilIdle()
        assertFalse(model.state.value.busy)
        assertEquals(ModerationDecisionFailure.OFFLINE, model.state.value.error)
        assertTrue(journal.entries.isEmpty())
        assertEquals(0, source.calls)
    }

    @Test
    fun standaloneRecoveryTimeoutReturnsOfflineWithReadRetryAndNoMutation() = runTest {
        val entry = ModerationDecisionUnitFixture.pending(ModerationDecisionPhase.DISPATCHED)
        val source = Source().apply { readTimeout = true }
        val journal = Journal().apply { entries = listOf(entry) }
        val model = ModerationDecisionViewModel(repository(source, journal), workScope = this)
        model.bindView(actor, null, ModerationPresentation()) { true }
        runCurrent()
        model.reconcile(entry)
        advanceUntilIdle()
        assertFalse(model.state.value.busy)
        assertEquals(ModerationDecisionFailure.OFFLINE, model.state.value.error)
        assertEquals(listOf(entry), model.state.value.pending)
        source.readTimeout = false
        model.reconcile(entry)
        advanceUntilIdle()
        assertEquals(ModerationObservation.CONFIRMED_CURRENT, model.state.value.observation)
        assertTrue(journal.entries.isEmpty())
        assertEquals(2, source.reads)
        assertEquals(0, source.dispatches)
    }

    @Test
    fun postDispatchReadTimeoutKeepsAcknowledgedJournalAndReportsUnconfirmedNotOffline() = runTest {
        val source = Source().apply { readTimeout = true }
        val journal = Journal()
        val model = ModerationDecisionViewModel(repository(source, journal), workScope = this)
        model.bindView(actor, version, ModerationPresentation()) { true }
        runCurrent()
        model.request(ModerationDecision.APPROVE)
        model.confirm()
        advanceUntilIdle()
        assertFalse(model.state.value.busy)
        assertEquals(ModerationDecisionFailure.UNCONFIRMED, model.state.value.error)
        assertEquals(ModerationDecisionPhase.ACKNOWLEDGED, journal.entries.single().phase)
        model.request(ModerationDecision.APPROVE)
        model.confirm()
        advanceUntilIdle()
        assertEquals(1, source.dispatches)
    }
}
