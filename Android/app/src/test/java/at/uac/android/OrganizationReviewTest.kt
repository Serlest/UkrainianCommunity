package at.uac.android

import at.uac.android.feature.moderation.*
import at.uac.android.feature.organizationreview.*
import com.google.firebase.Timestamp
import java.time.Instant
import java.util.UUID
import kotlin.coroutines.Continuation
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.test.*
import org.junit.Assert.*
import org.junit.Test

internal object OrganizationReviewUnitFixture {
    val actor = ModerationSession("synthetic-reviewer", 9, "admin", true)
    val time = Instant.parse("2026-09-03T08:00:00.123456789Z")
    const val id = "synthetic-review-request"
    const val submitter = "synthetic-private-submitter"
    const val privateText = "PRIVATE-REVIEW-TEXT-NEVER-ON-DISK"

    fun fields() =
        mapOf<String, Any?>(
            "id" to id,
            "name" to "Synthetic request",
            "submittedByUserId" to submitter,
            "moderationStatus" to "pendingReview",
            "updatedAt" to time,
            "createdAt" to time,
            "ownerId" to "",
            "fullDescription" to privateText,
            "localizations" to mapOf("uk" to mapOf("fullDescription" to "Приватний опис")),
            "logoURL" to "synthetic-image",
            "memberCount" to 0L,
        )

    fun version() = OrganizationReviewContract.snapshot(id, fields()).version

    fun pending(
        action: OrganizationReviewAction = OrganizationReviewAction.APPROVE,
        phase: OrganizationReviewPhase = OrganizationReviewPhase.PREPARED,
        uid: String = actor.uid,
    ) =
        OrganizationReviewPending(
            OrganizationReviewContract.accountHash(uid),
            version(),
            action,
            OrganizationReviewContract.hash(
                if (action == OrganizationReviewAction.APPROVE) "" else privateText
            ),
            UUID.randomUUID().toString(),
            "admin",
            phase,
        )

    fun response(
        entry: OrganizationReviewPending,
        recipient: String = submitter,
    ): Map<String, Any?> =
        mapOf(
            "organizationId" to id,
            "moderationStatus" to entry.action.status,
            "notificationId" to
                "${when (entry.action) { OrganizationReviewAction.APPROVE -> "organizationRequestApproved"
 OrganizationReviewAction.REQUEST_REVISION -> "organizationRequestNeedsRevision"
 OrganizationReviewAction.REJECT -> "organizationRequestRejected" }}_${UUID.randomUUID()}_${id}_$recipient",
            "updatedAt" to time.minusSeconds(1).toString(),
        )

    fun after(entry: OrganizationReviewPending): Map<String, Any?> =
        fields().toMutableMap().apply {
            put("moderationStatus", entry.action.status)
            put("reviewedByUserId", actor.uid)
            put("reviewedAt", time.plusSeconds(3))
            put("updatedAt", time.plusSeconds(3))
            when (entry.action) {
                OrganizationReviewAction.APPROVE -> put("ownerId", submitter)
                OrganizationReviewAction.REQUEST_REVISION -> put("reviewMessage", privateText)
                OrganizationReviewAction.REJECT -> put("rejectionReason", privateText)
            }
        }
}

@OptIn(ExperimentalCoroutinesApi::class)
class OrganizationReviewTest {
    private val f = OrganizationReviewUnitFixture
    private var live: ModerationSession? = f.actor

    private class Journal : OrganizationReviewJournal {
        var entries = emptyList<OrganizationReviewPending>()
        var failPhase: OrganizationReviewPhase? = null
        var failClear = false
        var afterPut: ((OrganizationReviewPending) -> Unit)? = null
        var readHook: (suspend () -> List<OrganizationReviewPending>)? = null

        override suspend fun pending(uid: String): List<OrganizationReviewPending> =
            readHook?.invoke()
                ?: entries.filter { it.accountHash == OrganizationReviewContract.accountHash(uid) }

        override suspend fun put(
            uid: String,
            entry: OrganizationReviewPending,
            expected: OrganizationReviewPending?,
        ): OrganizationReviewPending {
            if (entry.phase == failPhase)
                throw OrganizationReviewException(OrganizationReviewFailure.JOURNAL)
            val old = entries.firstOrNull {
                it.accountHash == entry.accountHash &&
                    it.version.organizationId == entry.version.organizationId
            }
            check(old == expected)
            entries = entries.filterNot { it == old } + entry
            afterPut?.invoke(entry)
            return entry
        }

        override suspend fun clear(uid: String, expected: OrganizationReviewPending) {
            if (failClear) throw OrganizationReviewException(OrganizationReviewFailure.JOURNAL)
            check(expected in entries)
            entries = entries - expected
        }
    }

    private class Source : OrganizationReviewSource {
        var fields = OrganizationReviewUnitFixture.fields()
        var sends = 0
        var reads = 0
        var reconciles = 0
        val events = MutableSharedFlow<Result<Unit>>(extraBufferCapacity = 4)
        var onRead: (suspend () -> OrganizationReviewSnapshot)? = null
        var onSend: (suspend (OrganizationReviewPending) -> Unit)? = null
        var onReconcile: (suspend () -> Unit)? = null

        override suspend fun read(
            session: ModerationSession,
            organizationId: String,
        ): OrganizationReviewSnapshot {
            reads++
            return onRead?.invoke() ?: OrganizationReviewContract.snapshot(organizationId, fields)
        }

        override fun changes(session: ModerationSession, organizationId: String) = events.map {
            it.getOrThrow()
        }

        override suspend fun send(
            session: ModerationSession,
            entry: OrganizationReviewPending,
            text: String,
            canDispatch: () -> Boolean,
        ): OrganizationReviewReceipt {
            if (!canDispatch()) throw OrganizationReviewException(OrganizationReviewFailure.STALE)
            sends++
            onSend?.invoke(entry)
            return OrganizationReviewContract.receipt(
                entry,
                OrganizationReviewUnitFixture.response(entry),
            )
        }

        override suspend fun reconcile(
            session: ModerationSession,
            entry: OrganizationReviewPending,
        ): OrganizationReviewObservation {
            reconciles++
            onReconcile?.invoke()
            return if (entry.receipt != null) OrganizationReviewObservation.CONFIRMED_CURRENT
            else OrganizationReviewObservation.OBSERVED_WITHOUT_RECEIPT
        }
    }

    private fun repo(source: Source, journal: Journal) =
        OrganizationReviewRepository(
            source,
            journal,
            { live },
            object : ModerationDecisionGate {
                override suspend fun <T> withSession(
                    session: ModerationSession,
                    action: suspend () -> T,
                ): T = action()
            },
        )

    private fun failReason(expected: OrganizationReviewFailure, action: () -> Any?) {
        try {
            action()
            fail("Expected rejection")
        } catch (error: OrganizationReviewException) {
            assertEquals(expected, error.failure)
        }
    }

    private suspend fun failSuspend(
        expected: OrganizationReviewFailure,
        action: suspend () -> Any?,
    ) {
        try {
            action()
            fail("Expected rejection")
        } catch (error: OrganizationReviewException) {
            assertEquals(expected, error.failure)
        }
    }

    @Test
    fun exactThreePayloadsAndWhitespace() {
        assertEquals(
            mapOf("organizationId" to f.id),
            OrganizationReviewContract.payload(f.id, OrganizationReviewAction.APPROVE, ""),
        )
        assertEquals(
            mapOf("organizationId" to f.id, "message" to "Text"),
            OrganizationReviewContract.payload(
                f.id,
                OrganizationReviewAction.REQUEST_REVISION,
                "\uFEFF Text \u00a0",
            ),
        )
        assertEquals(
            mapOf("organizationId" to f.id, "reason" to "Text"),
            OrganizationReviewContract.payload(f.id, OrganizationReviewAction.REJECT, " Text "),
        )
    }

    @Test
    fun confirmationRequiresStableActionSnapshotAndEveryExistingGate() {
        val ready =
            OrganizationReviewState(
                session = f.actor,
                snapshot = OrganizationReviewContract.snapshot(f.id, f.fields()),
                fresh = true,
                journalReady = true,
                confirmation = OrganizationReviewAction.APPROVE,
            )
        assertTrue(ready.canConfirm)
        for (state in
            listOf(
                ready.copy(confirmation = null),
                ready.copy(snapshot = null),
                ready.copy(session = null),
                ready.copy(fresh = false),
                ready.copy(loading = true),
                ready.copy(busy = true),
                ready.copy(journalReady = false),
                ready.copy(pending = listOf(f.pending())),
                ready.copy(confirmation = OrganizationReviewAction.REJECT, text = " "),
            )) assertFalse(state.canConfirm)
    }

    @Test
    fun requiredTextAndOnlyApprovalEmpty() {
        for (action in OrganizationReviewAction.entries) failReason(
            OrganizationReviewFailure.INVALID
        ) {
            OrganizationReviewContract.payload(
                f.id,
                action,
                if (action == OrganizationReviewAction.APPROVE) "Unexpected" else " \n",
            )
        }
    }

    @Test
    fun transportBudgetAndInvalidIdsAreRejected() {
        failReason(OrganizationReviewFailure.INVALID) {
            OrganizationReviewContract.payload(
                f.id,
                OrganizationReviewAction.REJECT,
                "\"".repeat(40_000),
            )
        }
        for (id in listOf("", "a/b", "a b", "a".repeat(129))) failReason(
            OrganizationReviewFailure.INVALID
        ) {
            OrganizationReviewContract.payload(id, OrganizationReviewAction.APPROVE, "")
        }
    }

    @Test
    fun everyKnownRawChangeInvalidatesFingerprint() {
        for ((key, value) in
            mapOf(
                "submittedByUserId" to "other",
                "logoURL" to "changed",
                "fullDescription" to "changed",
                "localizations" to mapOf("uk" to mapOf("fullDescription" to "Changed")),
                "updatedAt" to f.time.plusNanos(1),
                "memberCount" to 1L,
            )) assertNotEquals(
            f.version().fingerprint,
            OrganizationReviewContract.fingerprint(f.id, f.fields() + (key to value)),
        )
    }

    @Test
    fun exactTimestampAndInstantNormalizeToSameHash() {
        assertEquals(
            f.version().fingerprint,
            OrganizationReviewContract.fingerprint(
                f.id,
                f.fields() + ("updatedAt" to Timestamp(f.time.epochSecond, f.time.nano)),
            ),
        )
    }

    @Test
    fun mapOrderingIsStableAndListOrderingIsNot() {
        assertEquals(
            f.version().fingerprint,
            OrganizationReviewContract.fingerprint(
                f.id,
                f.fields().toSortedMap(compareByDescending { it }),
            ),
        )
        assertNotEquals(
            OrganizationReviewContract.rawHash(f.id, mapOf("x" to listOf(1L, 2L))),
            OrganizationReviewContract.rawHash(f.id, mapOf("x" to listOf(2L, 1L))),
        )
    }

    @Test
    fun malformedAndLegacyMissingFieldsStayReadonly() {
        for (fields in
            listOf(
                f.fields() - "id",
                f.fields() - "updatedAt",
                f.fields() + ("moderationStatus" to "approved"),
                f.fields() + ("submittedByUserId" to ""),
                f.fields() + ("unknown" to Any()),
                f.fields() + ("name" to "\uD800"),
            )) failReason(OrganizationReviewFailure.INVALID) {
            OrganizationReviewContract.snapshot(f.id, fields)
        }
    }

    @Test
    fun allThreeReviewableStatesMatchBackend() {
        for (status in listOf("pendingReview", "needsRevision", "rejected")) assertEquals(
            status,
            OrganizationReviewContract.snapshot(f.id, f.fields() + ("moderationStatus" to status))
                .status,
        )
    }

    @Test
    fun depthAndEntryBudgetFailClosed() {
        var value: Any? = "x"
        repeat(25) { value = listOf(value) }
        failReason(OrganizationReviewFailure.INVALID) {
            OrganizationReviewContract.rawHash(f.id, mapOf("x" to value))
        }
        failReason(OrganizationReviewFailure.INVALID) {
            OrganizationReviewContract.rawHash(f.id, mapOf("x" to List(4097) { null }))
        }
    }

    @Test
    fun receiptTimeIsNotRequiredToEqualCommitTime() {
        val entry = f.pending()
        val receipt = OrganizationReviewContract.receipt(entry, f.response(entry))
        assertEquals(f.time.minusSeconds(1), receipt.wireTime)
        assertTrue(OrganizationReviewContract.matches(entry, f.actor.uid, f.after(entry)))
    }

    @Test
    fun changedSubmitterAfterPreflightPreservesValidReceiptButNotCurrentMatch() {
        val entry = f.pending()
        val receipt = OrganizationReviewContract.receipt(entry, f.response(entry, "new-submitter"))
        assertEquals(64, receipt.notificationDigest.length)
        assertFalse(
            OrganizationReviewContract.matches(
                entry,
                f.actor.uid,
                f.after(entry) +
                    ("submittedByUserId" to "new-submitter") +
                    ("ownerId" to "new-submitter"),
            )
        )
    }

    @Test
    fun invalidReceiptTargetStatusPrefixAndTimeAreNotAcknowledged() {
        val entry = f.pending()
        for (change in
            listOf(
                mapOf("organizationId" to "other"),
                mapOf("moderationStatus" to "rejected"),
                mapOf("notificationId" to "untrusted"),
                mapOf("updatedAt" to "bad"),
                mapOf("unexpected" to true),
            )) failReason(OrganizationReviewFailure.UNCONFIRMED) {
            OrganizationReviewContract.receipt(entry, f.response(entry) + change)
        }
    }

    @Test
    fun exactActionReadbacksAndPreservedFields() {
        for (action in OrganizationReviewAction.entries) {
            val entry = f.pending(action)
            val after = f.after(entry)
            assertTrue(OrganizationReviewContract.matches(entry, f.actor.uid, after))
            for (change in
                listOf(
                    mapOf("fullDescription" to "Changed"),
                    mapOf("reviewedByUserId" to "other"),
                    mapOf("updatedAt" to f.time),
                    mapOf("rejectionReason" to "unexpected"),
                )) {
                if (
                    action == OrganizationReviewAction.REJECT &&
                        change.keys == setOf("rejectionReason")
                )
                    assertFalse(
                        OrganizationReviewContract.matches(entry, f.actor.uid, after + change)
                    )
                else
                    assertFalse(
                        OrganizationReviewContract.matches(entry, f.actor.uid, after + change)
                    )
            }
        }
    }

    @Test
    fun codecContainsHashesNotPrivateMessageOrRecipientAndRoundTrips() {
        val prepared = f.pending(OrganizationReviewAction.REJECT)
        val ack =
            prepared.copy(
                phase = OrganizationReviewPhase.ACKNOWLEDGED,
                receipt = OrganizationReviewContract.receipt(prepared, f.response(prepared)),
            )
        val bytes = OrganizationReviewJournalCodec.encode(listOf(ack))
        assertEquals(listOf(ack), OrganizationReviewJournalCodec.decode(bytes))
        val raw = bytes.toString(Charsets.ISO_8859_1)
        for (secret in listOf(f.actor.uid, f.submitter, f.privateText)) assertFalse(
            raw.contains(secret)
        )
    }

    @Test
    fun codecCorruptionDuplicateIdentityAndCapFailClosed() {
        val entry = f.pending()
        for (bytes in
            listOf(
                byteArrayOf(1, 2),
                OrganizationReviewJournalCodec.encode(listOf(entry)) + byteArrayOf(1),
                ByteArray(OrganizationReviewJournalCodec.MAX_BYTES + 1),
            )) assertTrue(runCatching { OrganizationReviewJournalCodec.decode(bytes) }.isFailure)
        assertTrue(
            runCatching {
                OrganizationReviewJournalCodec.encode(
                    listOf(entry, entry.copy(operationId = UUID.randomUUID().toString()))
                )
            }
                .isFailure
        )
        assertTrue(
            runCatching {
                OrganizationReviewJournalCodec.encode(
                    List(17) {
                        entry.copy(
                            version = entry.version.copy(organizationId = "target-$it"),
                            operationId = UUID.randomUUID().toString(),
                        )
                    }
                )
            }
                .isFailure
        )
    }

    @Test
    fun rolesAndForeignJournalStayDenied() {
        for (role in listOf("user", "moderator", "organizationAdmin")) failReason(
            OrganizationReviewFailure.ACCESS
        ) {
            OrganizationReviewContract.requireSession(f.actor.copy(role = role))
        }
        failReason(OrganizationReviewFailure.ACCESS) {
            OrganizationReviewContract.requireOwner(f.actor.copy(uid = "other"), f.pending())
        }
    }

    @Test
    fun oneSendReceivesAndClearsOnlyAfterReadback() = runTest {
        val source = Source()
        val journal = Journal()
        val repository = repo(source, journal)
        source.onReconcile = {
            assertEquals(OrganizationReviewPhase.ACKNOWLEDGED, journal.entries.single().phase)
        }
        assertEquals(
            OrganizationReviewObservation.CONFIRMED_CURRENT,
            repository.execute(f.actor, f.version(), OrganizationReviewAction.APPROVE, "") { true },
        )
        assertEquals(1, source.sends)
        assertTrue(journal.entries.isEmpty())
    }

    @Test
    fun prepareFailurePreventsSdk() = runTest {
        val source = Source()
        val journal = Journal().apply { failPhase = OrganizationReviewPhase.PREPARED }
        failSuspend(OrganizationReviewFailure.JOURNAL) {
            repo(source, journal).execute(
                f.actor,
                f.version(),
                OrganizationReviewAction.APPROVE,
                "",
            ) {
                true
            }
        }
        assertEquals(0, source.sends)
    }

    @Test
    fun staleRawPreflightPreventsJournalAndSdk() = runTest {
        val source = Source().apply { fields = fields + ("logoURL" to "new") }
        val journal = Journal()
        failSuspend(OrganizationReviewFailure.STALE) {
            repo(source, journal).execute(
                f.actor,
                f.version(),
                OrganizationReviewAction.APPROVE,
                "",
            ) {
                true
            }
        }
        assertTrue(journal.entries.isEmpty())
        assertEquals(0, source.sends)
    }

    @Test
    fun canceledOriginalCallerAfterPrepareNeverDispatches() = runTest {
        val source = Source()
        val journal = Journal()
        val repository = repo(source, journal)
        lateinit var job: Job
        journal.afterPut = { if (it.phase == OrganizationReviewPhase.PREPARED) job.cancel() }
        job = launch {
            repository.execute(f.actor, f.version(), OrganizationReviewAction.APPROVE, "") { true }
        }
        runCurrent()
        job.join()
        assertEquals(0, source.sends)
        assertTrue(journal.entries.isEmpty())
    }

    @Test
    fun canceledAfterDispatchRetainsSettlementAndNeverReplays() = runTest {
        val source = Source()
        val journal = Journal()
        val release = CompletableDeferred<Unit>()
        source.onSend = { release.await() }
        val repository = repo(source, journal)
        val job = launch {
            repository.execute(f.actor, f.version(), OrganizationReviewAction.APPROVE, "") { true }
        }
        runCurrent()
        assertEquals(1, source.sends)
        job.cancel()
        assertFalse(job.isCompleted)
        release.complete(Unit)
        runCurrent()
        assertTrue(job.isCompleted)
        assertEquals(1, source.sends)
        assertTrue(journal.entries.isEmpty())
    }

    @Test
    fun lostResultRemainsPendingAndReadOnlyObservationCannotClearIt() = runTest {
        val source =
            Source().apply { onSend = { throw java.io.IOException("Synthetic lost receipt") } }
        val journal = Journal()
        val repository = repo(source, journal)
        failSuspend(OrganizationReviewFailure.UNCONFIRMED) {
            repository.execute(f.actor, f.version(), OrganizationReviewAction.APPROVE, "") { true }
        }
        val entry = journal.entries.single()
        assertEquals(OrganizationReviewPhase.DISPATCHED, entry.phase)
        assertEquals(
            OrganizationReviewObservation.OBSERVED_WITHOUT_RECEIPT,
            repository.reconcile(f.actor, entry),
        )
        assertEquals(listOf(entry), journal.entries)
        failSuspend(OrganizationReviewFailure.PENDING) {
            repository.execute(f.actor, f.version(), OrganizationReviewAction.APPROVE, "") { true }
        }
        assertEquals(1, source.sends)
    }

    @Test
    fun acknowledgementPersistenceFailureKeepsDispatchedRecord() = runTest {
        val source = Source()
        val journal = Journal().apply { failPhase = OrganizationReviewPhase.ACKNOWLEDGED }
        failSuspend(OrganizationReviewFailure.JOURNAL) {
            repo(source, journal).execute(
                f.actor,
                f.version(),
                OrganizationReviewAction.APPROVE,
                "",
            ) {
                true
            }
        }
        assertEquals(OrganizationReviewPhase.DISPATCHED, journal.entries.single().phase)
        assertEquals(1, source.sends)
    }

    @Test
    fun clearFailureDoesNotDestroyReceipt() = runTest {
        val source = Source()
        val journal = Journal().apply { failClear = true }
        failSuspend(OrganizationReviewFailure.JOURNAL) {
            repo(source, journal).execute(
                f.actor,
                f.version(),
                OrganizationReviewAction.APPROVE,
                "",
            ) {
                true
            }
        }
        assertEquals(OrganizationReviewPhase.ACKNOWLEDGED, journal.entries.single().phase)
    }

    @Test
    fun logoutAfterSendRetainsAckPrivatelyForOldUid() = runTest {
        val source = Source().apply { onSend = { live = null } }
        val journal = Journal()
        assertTrue(
            runCatching {
                repo(source, journal).execute(
                    f.actor,
                    f.version(),
                    OrganizationReviewAction.APPROVE,
                    "",
                ) {
                    true
                }
            }
                .exceptionOrNull() is CancellationException
        )
        assertEquals(OrganizationReviewPhase.ACKNOWLEDGED, journal.entries.single().phase)
        assertTrue(journal.pending("other-uid").isEmpty())
    }

    private fun TestScope.model(source: Source, journal: Journal): OrganizationReviewViewModel =
        OrganizationReviewViewModel(repo(source, journal), workScope = backgroundScope)

    private fun bind(
        model: OrganizationReviewViewModel,
        token: ModerationPresentation = ModerationPresentation(),
        guard: () -> Boolean = { true },
    ) {
        model.bindView(
            f.actor,
            ModerationTarget(ModerationKind.ORGANIZATION, f.id),
            f.version().fingerprint,
            token,
            canSubmit = guard,
        )
    }

    @Test
    fun vmRequiresDisplayedFingerprintAndNeverSendsAutomatically() = runTest {
        val source = Source()
        val model = model(source, Journal())
        model.bindView(
            f.actor,
            ModerationTarget(ModerationKind.ORGANIZATION, f.id),
            "a".repeat(64),
            ModerationPresentation(),
        ) {
            true
        }
        runCurrent()
        assertFalse(model.snapshot(f.actor).canAct)
        assertEquals(OrganizationReviewFailure.STALE, model.snapshot(f.actor).error)
        assertEquals(0, source.sends)
    }

    @Test
    fun vmDoubleTapSingleSendAndClosedHostImmediatelyMasks() = runTest {
        val source = Source()
        val release = CompletableDeferred<Unit>()
        source.onSend = { release.await() }
        val model = model(source, Journal())
        var active = true
        val token = ModerationPresentation()
        bind(model, token) { active }
        runCurrent()
        model.request(OrganizationReviewAction.APPROVE)
        model.confirm()
        model.confirm()
        runCurrent()
        assertEquals(1, source.sends)
        active = false
        assertNull(model.snapshot(f.actor).session)
        active = true
        bind(model, token) { active }
        assertNull(model.snapshot(f.actor).session)
        release.complete(Unit)
        runCurrent()
        bind(model)
        runCurrent()
        assertNotNull(model.snapshot(f.actor).session)
    }

    @Test
    fun vmUnselectedHostCanReconcilePendingWithoutSend() = runTest {
        val source = Source()
        val journal =
            Journal().apply {
                entries = listOf(f.pending(phase = OrganizationReviewPhase.DISPATCHED))
            }
        val model = model(source, journal)
        model.bindView(f.actor, null, null, ModerationPresentation()) { true }
        runCurrent()
        val entry = model.snapshot(f.actor).pending.single()
        model.reconcile(entry)
        runCurrent()
        assertEquals(1, source.reconciles)
        assertEquals(0, source.sends)
        assertEquals(1, model.snapshot(f.actor).pending.size)
    }

    @Test
    fun vmOlderPendingReadCannotOverwriteNewerPending() = runTest {
        val source = Source()
        val journal = Journal()
        val continuations = mutableListOf<Continuation<List<OrganizationReviewPending>>>()
        journal.readHook = { suspendCoroutine { continuations += it } }
        val model = model(source, journal)
        model.bindView(f.actor, null, null, ModerationPresentation()) { true }
        runCurrent()
        journal.readHook = null
        journal.entries = listOf(f.pending(phase = OrganizationReviewPhase.DISPATCHED))
        model.refreshPending()
        runCurrent()
        continuations.forEach { it.resume(emptyList()) }
        runCurrent()
        assertEquals(1, model.snapshot(f.actor).pending.size)
    }

    @Test
    fun vmListenerFailureCannotBeUndoneByLateRead() = runTest {
        val source = Source()
        var continuation: Continuation<OrganizationReviewSnapshot>? = null
        source.onRead = { suspendCoroutine { continuation = it } }
        val model = model(source, Journal())
        bind(model)
        runCurrent()
        source.events.emit(
            Result.failure(OrganizationReviewException(OrganizationReviewFailure.ACCESS))
        )
        runCurrent()
        continuation!!.resume(OrganizationReviewContract.snapshot(f.id, f.fields()))
        runCurrent()
        assertFalse(model.snapshot(f.actor).fresh)
        assertEquals(OrganizationReviewFailure.ACCESS, model.snapshot(f.actor).error)
    }

    @Test
    fun vmReadTimeoutIsOfflineNotStuckLoading() = runTest {
        val source =
            Source().apply {
                onRead = {
                    withTimeout(1) {
                        delay(10)
                        OrganizationReviewContract.snapshot(f.id, f.fields())
                    }
                }
            }
        val model = model(source, Journal())
        bind(model)
        runCurrent()
        advanceTimeBy(2)
        runCurrent()
        assertFalse(model.snapshot(f.actor).loading)
        assertEquals(OrganizationReviewFailure.OFFLINE, model.snapshot(f.actor).error)
    }

    @Test
    fun vmVersionChangeClosesConfirmationAndClearsMessage() = runTest {
        val source = Source()
        val model = model(source, Journal())
        val token = ModerationPresentation()
        bind(model, token)
        runCurrent()
        model.request(OrganizationReviewAction.REJECT)
        model.editText(f.privateText)
        source.fields = source.fields + ("logoURL" to "updated")
        model.bindView(
            f.actor,
            ModerationTarget(ModerationKind.ORGANIZATION, f.id),
            OrganizationReviewContract.fingerprint(f.id, source.fields),
            token,
        ) {
            true
        }
        runCurrent()
        assertNull(model.snapshot(f.actor).confirmation)
        assertEquals("", model.snapshot(f.actor).text)
        assertEquals(0, source.sends)
    }

    @Test
    fun sameHostPreviewCloseAllowsQueueReconciliation() = runTest {
        val journal =
            Journal().apply {
                entries = listOf(f.pending(phase = OrganizationReviewPhase.DISPATCHED))
            }
        val source = Source()
        val model = model(source, journal)
        val token = ModerationPresentation()
        var selected = true
        model.bindView(
            f.actor,
            ModerationTarget(ModerationKind.ORGANIZATION, f.id),
            f.version().fingerprint,
            token,
            hostIsCurrent = { true },
        ) {
            selected
        }
        runCurrent()
        selected = false
        assertNull(model.snapshot(f.actor).snapshot)
        assertNotNull(model.snapshot(f.actor).session)
        model.bindView(f.actor, null, null, token, hostIsCurrent = { true }) { false }
        runCurrent()
        model.reconcile(model.snapshot(f.actor).pending.single())
        runCurrent()
        assertEquals(1, source.reconciles)
        assertEquals(0, source.sends)
    }

    @Test
    fun sameHostNewFingerprintRevalidatesAndOldOutcomeDoesNotMoveToAnotherTarget() = runTest {
        val source = Source()
        val model = model(source, Journal())
        val token = ModerationPresentation()
        var selected = true
        model.bindView(
            f.actor,
            ModerationTarget(ModerationKind.ORGANIZATION, f.id),
            f.version().fingerprint,
            token,
            hostIsCurrent = { true },
        ) {
            selected
        }
        runCurrent()
        model.request(OrganizationReviewAction.APPROVE)
        model.confirm()
        runCurrent()
        assertNotNull(model.snapshot(f.actor).observation)
        selected = false
        assertNull(model.snapshot(f.actor).snapshot)
        source.fields = source.fields + ("logoURL" to "changed")
        selected = true
        model.bindView(
            f.actor,
            ModerationTarget(ModerationKind.ORGANIZATION, f.id),
            OrganizationReviewContract.fingerprint(f.id, source.fields),
            token,
            hostIsCurrent = { true },
        ) {
            selected
        }
        runCurrent()
        assertTrue(model.snapshot(f.actor).fresh)
        assertNull(model.snapshot(f.actor).observation)
    }

    @Test
    fun canceledJournalDiscoveryStartsNoAdditionalReadOrSend() = runTest {
        val source = Source()
        val journal = Journal()
        var continuation: Continuation<List<OrganizationReviewPending>>? = null
        journal.readHook = { suspendCoroutine { continuation = it } }
        val job = launch {
            repo(source, journal).execute(
                f.actor,
                f.version(),
                OrganizationReviewAction.APPROVE,
                "",
            ) {
                true
            }
        }
        runCurrent()
        job.cancel()
        continuation!!.resume(emptyList())
        runCurrent()
        assertEquals(0, source.reads)
        assertEquals(0, source.sends)
        assertTrue(journal.entries.isEmpty())
    }

    @Test
    fun protocolErrorMappingIsPureAndJournalTextNeverPromisesNotSent() {
        assertEquals(
            OrganizationReviewFailure.ACCESS,
            organizationReviewFailure(
                at.uac.android.core.LocalCallableException(
                    at.uac.android.core.LocalCallableFailure.PERMISSION_DENIED
                )
            ),
        )
        assertFalse(
            organizationReviewFailureText(OrganizationReviewFailure.JOURNAL, "de")
                .contains("nichts gesendet")
        )
    }

    @Test
    fun redactedDiagnosticsNeverContainPrivatePayload() {
        val entry = f.pending(OrganizationReviewAction.REJECT)
        val state =
            OrganizationReviewState(
                session = f.actor,
                snapshot = OrganizationReviewContract.snapshot(f.id, f.fields()),
                text = f.privateText,
            )
        for (text in
            listOf(
                entry.toString(),
                state.toString(),
                entry.version.toString(),
                state.snapshot.toString(),
            )) {
            assertFalse(text.contains(f.privateText))
            assertFalse(text.contains(f.submitter))
            assertFalse(text.contains(f.actor.uid))
        }
    }
}
