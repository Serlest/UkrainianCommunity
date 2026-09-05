package at.uac.android

import at.uac.android.feature.browse.*
import at.uac.android.feature.community.*
import at.uac.android.feature.history.*
import at.uac.android.feature.personal.*
import java.time.Instant
import kotlinx.coroutines.*
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class HistoryTest {
    private val alice = HistorySession("synthetic-alice", 1, true)
    private var authority: HistorySession? = alice
    private var allowed = true
    private var foreground = true
    private val time = Instant.parse("2026-09-03T10:00:00Z")

    @Before
    fun setup() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @After
    fun teardown() {
        Dispatchers.resetMain()
    }

    private fun target(id: String = "synthetic-news", type: HistoryType = HistoryType.NEWS) =
        HistoryTarget(type, id)

    private fun raw(target: HistoryTarget = target(), extra: Fields = emptyMap()) =
        RawDocument(
            target.id,
            mapOf(
                "id" to target.id,
                "moderationStatus" to "approved",
                "sourceType" to "organization",
                "title" to "Visible title",
                "body" to "Body",
                "summary" to "Summary",
                "details" to "Details",
                "name" to "Organization",
                "city" to "Wien",
                "description" to "Description",
                "createdAt" to time,
                "updatedAt" to time,
                "startDate" to time,
                "endDate" to time.plusSeconds(3600),
            ) + extra,
        )

    private fun row(
        target: HistoryTarget = target(),
        at: Instant = time,
        action: HistoryAction? = null,
        id: String = target.recentId,
    ) =
        RawDocument(
            id,
            HistoryContract.fields(
                target,
                action,
                "Private snapshot",
                "Private subtitle",
                "https://example.invalid/private-image",
                id,
                at,
            ),
        )

    private fun repo(fake: Fake) =
        HistoryRepository(fake, { authority }, { allowed }, DirectHistoryMutationGate)

    private fun model(fake: Fake) =
        HistoryViewModel(
            fake,
            { authority },
            { allowed },
            DirectHistoryMutationGate,
            { foreground },
        )

    private suspend fun failure(expected: HistoryFailure, action: suspend () -> Any?) {
        try {
            action()
            fail("Expected $expected")
        } catch (error: HistoryException) {
            assertEquals(expected, error.failure)
        }
    }

    private suspend fun cancelled(action: suspend () -> Any?) {
        try {
            action()
            fail("Expected stale cancellation")
        } catch (_: CancellationException) {}
    }

    private inner class Fake : HistorySource {
        val rows = linkedMapOf<String, RawDocument>()
        val content = mutableMapOf<HistoryTarget, RawDocument>()
        var writeCalls = 0
        var readCalls = 0
        var deleteCalls = 0
        var reconcileReads = 0
        var failure: HistoryFailure? = null
        var writeFailure: HistoryFailure? = null
        var delayRead: CompletableDeferred<Unit>? = null
        var delayWrite: CompletableDeferred<Unit>? = null
        var malformedPage: HistoryRawPage? = null
        val requests = mutableListOf<Int>()

        override suspend fun page(
            session: HistorySession,
            section: HistorySection,
            cursor: HistoryCursor?,
            size: Int,
        ): HistoryRawPage {
            readCalls++
            requests += size
            delayRead?.let { withContext(NonCancellable) { it.await() } }
            failure?.let { throw HistoryException(it) }
            malformedPage?.let {
                return it
            }
            val sorted =
                rows.values
                    .filter { it.fields[section.dateField] is Instant }
                    .sortedWith { a, b ->
                        HistoryContract.compare(
                            a.fields[section.dateField] as Instant,
                            a.id,
                            b.fields[section.dateField] as Instant,
                            b.id,
                        )
                    }
                    .filter {
                        cursor == null ||
                            HistoryContract.compare(
                                cursor.at,
                                cursor.id,
                                it.fields[section.dateField] as Instant,
                                it.id,
                            ) < 0
                    }
            return HistoryRawPage(sorted.take(size), sorted.size > size)
        }

        override suspend fun targets(
            kind: ContentKind,
            ids: List<String>,
            stillCurrent: () -> Boolean,
        ) = content.filterKeys { it.type.kind == kind && it.id in ids }.values.toList()

        override suspend fun record(
            session: HistorySession,
            section: HistorySection,
            id: String,
        ): RawDocument? {
            reconcileReads++
            return rows[id]
        }

        override suspend fun write(
            value: HistoryWrite,
            current: () -> Boolean,
            visible: (Content) -> Boolean,
        ): HistoryWriteReceipt {
            writeCalls++
            delayWrite?.await()
            if (!current()) throw CancellationException()
            writeFailure?.let { throw HistoryException(it) }
            val target = content[value.target] ?: throw HistoryException(HistoryFailure.MISSING)
            if (!visible(HistoryContract.content(value.target, target)))
                throw HistoryException(HistoryFailure.DENIED)
            val row =
                row(value.target, time.plusSeconds(writeCalls.toLong()), value.action, value.id)
            rows[value.id] = row
            return HistoryWriteReceipt(HistoryContract.record(value.section, row), false)
        }

        override suspend fun delete(value: HistoryDelete, current: () -> Boolean) {
            deleteCalls++
            if (!current()) throw CancellationException()
            writeFailure?.let { throw HistoryException(it) }
            if (
                value.records.any { expected ->
                    rows[expected.id]?.let {
                        HistoryContract.record(value.section, it) != expected
                    } == true
                }
            )
                throw HistoryException(HistoryFailure.CONFLICT)
            value.records.forEach { rows.remove(it.id) }
        }

        fun seed(count: Int, section: HistorySection = HistorySection.RECENT) {
            repeat(count) { index ->
                val target = target("synthetic-${index.toString().padStart(3, '0')}")
                val row =
                    row(
                        target,
                        time.minusSeconds(index.toLong()),
                        if (section == HistorySection.ACTIVITY) HistoryAction.SAVE_NEWS else null,
                        if (section == HistorySection.ACTIVITY) "activity-$index"
                        else target.recentId,
                    )
                rows[row.id] = row
                content[target] = raw(target)
            }
        }
    }

    @Test
    fun exactTenActionsAndThreeTypesMatchBuild65() {
        assertEquals(10, HistoryAction.entries.size)
        assertEquals(3, HistoryType.entries.size)
        HistoryAction.entries.forEach { action ->
            val intent = HistoryContract.write(alice, target(type = action.type), action, "uk")
            HistoryContract.validate(intent)
            assertEquals(
                action,
                HistoryContract.record(
                        HistorySection.ACTIVITY,
                        row(intent.target, action = action, id = intent.id),
                    )
                    .action,
            )
        }
        assertTrue(
            HistoryAction.entries.none {
                it.wire.contains("like", true) || it.wire.contains("comment", true)
            }
        )
    }

    @Test
    fun recentCanonicalIdAndAllowedFieldsAreStrict() = runTest {
        assertEquals(target(), HistoryContract.record(HistorySection.RECENT, row()).target)
        failure(HistoryFailure.INVALID) {
            HistoryContract.record(HistorySection.RECENT, row().copy(id = "spoof"))
        }
        failure(HistoryFailure.INVALID) {
            HistoryContract.record(
                HistorySection.RECENT,
                row().copy(fields = row().fields + ("email" to "private")),
            )
        }
    }

    @Test
    fun activityTargetTypeAndBodyIdCannotBeForged() = runTest {
        val value = row(action = HistoryAction.SAVE_NEWS, id = "activity")
        failure(HistoryFailure.INVALID) {
            HistoryContract.record(
                HistorySection.ACTIVITY,
                value.copy(fields = value.fields + ("id" to "foreign")),
            )
        }
        failure(HistoryFailure.INVALID) {
            HistoryContract.record(
                HistorySection.ACTIVITY,
                value.copy(fields = value.fields + ("targetType" to "event")),
            )
        }
        failure(HistoryFailure.INVALID) {
            HistoryContract.record(
                HistorySection.ACTIVITY,
                value.copy(fields = value.fields + ("actionType" to "likedNews")),
            )
        }
    }

    @Test
    fun timestampsAndTextTypesAreRequiredNotGuessed() = runTest {
        for (extra in
            listOf(
                mapOf("viewedAt" to 123),
                mapOf("subtitle" to true),
                mapOf("imageURL" to 5),
                mapOf("title" to null),
            )) failure(HistoryFailure.INVALID) {
            HistoryContract.record(HistorySection.RECENT, row().copy(fields = row().fields + extra))
        }
    }

    @Test
    fun privateDebugRepresentationsAreRedacted() {
        val record = HistoryContract.record(HistorySection.RECENT, row())
        for (text in
            listOf(
                record.toString(),
                HistoryEntry(record, HistoryContract.content(target(), raw())).toString(),
                HistoryCursor(alice, HistorySection.RECENT, time, record.id, 1).toString(),
                alice.toString(),
            )) {
            assertFalse(text.contains("Private"))
            assertFalse(text.contains("synthetic"))
        }
    }

    @Test
    fun guestAndRestrictedScopesDoNotQueryPrivateHistory() = runTest {
        val fake = Fake()
        authority = null
        failure(HistoryFailure.SIGN_IN) { repo(fake).page(HistorySection.RECENT) }
        authority = alice.copy(ready = false)
        failure(HistoryFailure.NOT_READY) { repo(fake).page(HistorySection.ACTIVITY) }
        assertEquals(0, fake.readCalls)
    }

    @Test
    fun recentWindowIsThirtyWithHonestTruncationAndCursor() = runTest {
        val fake = Fake().apply { seed(35) }
        val first = repo(fake).page(HistorySection.RECENT)
        assertEquals(15, first.entries.size)
        assertNotNull(first.next)
        assertFalse(first.capped)
        val last = repo(fake).page(HistorySection.RECENT, first.next)
        assertEquals(15, last.entries.size)
        assertNull(last.next)
        assertTrue(last.capped)
        assertEquals(30, last.consumed)
        assertEquals(listOf(15, 15), fake.requests)
    }

    @Test
    fun activityWindowIsOneHundredNotAnUnboundedList() = runTest {
        val fake = Fake().apply { seed(110, HistorySection.ACTIVITY) }
        var cursor: HistoryCursor? = null
        repeat(4) {
            val page = repo(fake).page(HistorySection.ACTIVITY, cursor)
            cursor = page.next
            assertEquals(25, page.entries.size)
            if (it == 3) {
                assertNull(cursor)
                assertTrue(page.capped)
                assertEquals(100, page.consumed)
            }
        }
    }

    @Test
    fun foreignSectionForeignSessionAndExhaustedCursorsAreRejected() = runTest {
        val fake = Fake()
        for (cursor in
            listOf(
                HistoryCursor(alice.copy(uid = "other"), HistorySection.RECENT, time, "id", 1),
                HistoryCursor(alice, HistorySection.ACTIVITY, time, "id", 1),
                HistoryCursor(alice, HistorySection.RECENT, time, "id", 30),
            )) failure(HistoryFailure.INVALID) { repo(fake).page(HistorySection.RECENT, cursor) }
        assertEquals(0, fake.readCalls)
    }

    @Test
    fun duplicatesWrongOrderAndNonAdvancingRowsAreRejected() = runTest {
        val fake = Fake()
        fake.malformedPage = HistoryRawPage(listOf(row(), row()), false)
        failure(HistoryFailure.INVALID) { repo(fake).page(HistorySection.RECENT) }
        fake.malformedPage =
            HistoryRawPage(listOf(row(at = time.minusSeconds(1)), row(target("new"))), false)
        failure(HistoryFailure.INVALID) { repo(fake).page(HistorySection.RECENT) }
        fake.malformedPage = HistoryRawPage(listOf(row()), false)
        failure(HistoryFailure.INVALID) {
            repo(fake)
                .page(
                    HistorySection.RECENT,
                    HistoryCursor(alice, HistorySection.RECENT, time, target().recentId, 1),
                )
        }
    }

    @Test
    fun equalTimestampUsesDescendingUtf8DocumentOrder() {
        assertTrue(HistoryContract.compare(time, "😀", time, "\uE000") < 0)
        assertTrue(HistoryContract.compare(time, "z", time, "a") < 0)
        assertEquals(0, HistoryContract.compare(time, "a", time, "a"))
    }

    @Test
    fun blockedAndMissingTargetsRetainOnlyGenericHistoryRows() = runTest {
        val fake = Fake().apply { seed(2) }
        allowed = false
        val page = repo(fake).page(HistorySection.RECENT)
        assertEquals(2, page.entries.size)
        assertTrue(page.entries.all { it.content == null })
        assertEquals(2, fake.rows.size)
        assertTrue(
            HistoryContract.selected(
                    page.entries,
                    HistoryFilter.ALL,
                    HistorySort.NEWEST,
                    "Private",
                    "de",
                )
                .isEmpty()
        )
    }

    @Test
    fun mixedAvailableMissingAndPrivateTargetsKeepTheAvailableNeighbour() = runTest {
        val fake = Fake().apply { seed(3) }
        val targets = fake.content.keys.toList()
        fake.content.remove(targets[1])
        fake.content[targets[2]] = raw(targets[2], mapOf("moderationStatus" to "draft"))
        val page = repo(fake).page(HistorySection.RECENT)
        assertEquals(3, page.entries.size)
        assertEquals(
            listOf(targets[0]),
            page.entries.filter { it.content != null }.map { it.record.target },
        )
        assertEquals(2, page.entries.count { it.content == null })
        assertEquals(3, fake.rows.size)
        assertEquals(0, fake.deleteCalls)
    }

    @Test
    fun freshTitlesInsteadOfSnapshotTextDriveSearchAndSort() = runTest {
        val fake = Fake().apply { seed(1) }
        val entries = repo(fake).page(HistorySection.RECENT).entries
        assertEquals(
            1,
            HistoryContract.selected(
                    entries,
                    HistoryFilter.ALL,
                    HistorySort.NAME_ASCENDING,
                    "Visible",
                    "de",
                )
                .size,
        )
        assertEquals(
            0,
            HistoryContract.selected(
                    entries,
                    HistoryFilter.ALL,
                    HistorySort.NEWEST,
                    "Private snapshot",
                    "de",
                )
                .size,
        )
    }

    @Test
    fun exactScopeChangeDuringReadDiscardsResult() = runTest {
        val fake =
            Fake().apply {
                seed(1)
                delayRead = CompletableDeferred()
            }
        val job = async { repo(fake).page(HistorySection.RECENT) }
        runCurrent()
        authority = alice.copy(revision = 2)
        fake.delayRead!!.complete(Unit)
        cancelled { job.await() }
    }

    @Test
    fun desiredDeleteRejectsEmptyDuplicateOverCapAndWrongSection() = runTest {
        val record = HistoryContract.record(HistorySection.RECENT, row())
        for (records in
            listOf(
                emptyList(),
                listOf(record, record),
                listOf(record.copy(section = HistorySection.ACTIVITY)),
            )) failure(HistoryFailure.INVALID) {
            HistoryContract.delete(HistoryDelete(alice, HistorySection.RECENT, records))
        }
        val many = (0..30).map { record.copy(id = "news-$it") }
        failure(HistoryFailure.INVALID) {
            HistoryContract.delete(HistoryDelete(alice, HistorySection.RECENT, many))
        }
    }

    @Test
    fun updatedRecentVersionSurvivesAnOldConfirmation() = runTest {
        val fake = Fake().apply { rows[target().recentId] = row() }
        val intent =
            HistoryDelete(
                alice,
                HistorySection.RECENT,
                listOf(HistoryContract.record(HistorySection.RECENT, row())),
            )
        fake.rows[target().recentId] = row(at = time.plusSeconds(1))
        failure(HistoryFailure.CONFLICT) { repo(fake).delete(intent) }
        assertEquals(1, fake.rows.size)
    }

    @Test
    fun reconcileNeverResubmitsAnyMutation() = runTest {
        val fake = Fake()
        val write = HistoryContract.write(alice, target(), HistoryAction.SAVE_NEWS, "de")
        assertEquals(HistoryReconciliation.ABSENT, repo(fake).reconcile(write))
        fake.rows[write.id] = row(action = write.action, id = write.id)
        assertEquals(HistoryReconciliation.PRESENT, repo(fake).reconcile(write))
        assertEquals(0, fake.writeCalls)
        assertEquals(0, fake.deleteCalls)
    }

    @Test
    fun postCommitReadFailurePreservesUncertaintyInsteadOfClaimingAnUnsentWrite() = runTest {
        for (reason in
            listOf(
                HistoryFailure.OFFLINE,
                HistoryFailure.DENIED,
                HistoryFailure.INVALID,
                HistoryFailure.MISSING,
            )) failure(HistoryFailure.UNCONFIRMED) {
            historyWriteReadBack { throw HistoryException(reason) }
        }
        assertEquals("confirmed", historyWriteReadBack { "confirmed" })
    }

    @Test
    fun postCommitReadBackNeverSwallowsAccountCancellation() = runTest {
        cancelled { historyWriteReadBack { throw CancellationException("Scope changed") } }
    }

    @Test
    fun repeatedVisitOnlyAttemptsOneWrite() = runTest {
        val fake = Fake().apply { content[target()] = raw() }
        val model = model(fake)
        repeat(3) {
            model.recordView(HistoryContract.content(target(), raw()), "entry-1", "de") { true }
        }
        advanceUntilIdle()
        assertEquals(1, fake.writeCalls)
    }

    @Test
    fun guestBackgroundCachedAndCancelledEventsNeverStartWrites() = runTest {
        val fake = Fake()
        val model = model(fake)
        val content = HistoryContract.content(target(), raw())
        foreground = false
        model.recordView(content, "entry-1", "de") { true }
        foreground = true
        model.recordView(content, "entry-2", "de") { false }
        authority = null
        model.recordView(content, "entry-3", "de") { true }
        authority = alice
        model.bind(alice)
        val event = target(type = HistoryType.EVENT)
        model.recordView(
            HistoryContract.content(event, raw(event, mapOf("cancellationState" to "cancelled"))),
            "entry-4",
            "de",
        ) {
            true
        }
        advanceUntilIdle()
        assertEquals(0, fake.writeCalls)
    }

    @Test
    fun ambiguousWriteIsNotRetriedByRecompositionNewVisitOrReconcile() = runTest {
        val fake =
            Fake().apply {
                content[target()] = raw()
                writeFailure = HistoryFailure.UNCONFIRMED
            }
        val model = model(fake)
        val content = HistoryContract.content(target(), raw())
        model.recordView(content, "first", "de") { true }
        advanceUntilIdle()
        model.recordView(content, "second", "de") { true }
        advanceUntilIdle()
        assertEquals(1, fake.writeCalls)
        assertEquals(1, model.state.value.pendingWrites)
        model.reconcile()
        advanceUntilIdle()
        assertEquals(1, fake.writeCalls)
        assertEquals(0, model.state.value.pendingWrites)
        assertTrue(model.state.value.reconciled)
    }

    @Test
    fun reconciliationCannotRaceAnInFlightWrite() = runTest {
        val fake =
            Fake().apply {
                content[target()] = raw()
                delayWrite = CompletableDeferred()
            }
        val model = model(fake)
        model.recordView(HistoryContract.content(target(), raw()), "first", "de") { true }
        runCurrent()
        model.reconcile()
        runCurrent()
        assertEquals(0, fake.reconcileReads)
        fake.delayWrite!!.complete(Unit)
        advanceUntilIdle()
        assertEquals(0, model.state.value.pendingWrites)
    }

    @Test
    fun sessionSwitchClearsPageConfirmationAndPendingWritesImmediately() = runTest {
        val fake =
            Fake().apply {
                seed(1)
                writeFailure = HistoryFailure.UNCONFIRMED
                content[target()] = raw()
            }
        val model = model(fake)
        model.show(HistorySection.RECENT)
        advanceUntilIdle()
        model.requestDelete(model.state.value.page!!.entries.map { it.record.id }.toSet())
        model.recordView(HistoryContract.content(target(), raw()), "first", "de") { true }
        advanceUntilIdle()
        authority = alice.copy(uid = "synthetic-bob", revision = 2)
        model.bind(authority)
        assertNull(model.state.value.page)
        assertNull(model.state.value.confirmation)
        assertEquals(0, model.state.value.pendingWrites)
    }

    @Test
    fun lateReadCannotRepopulateHiddenPage() = runTest {
        val fake =
            Fake().apply {
                seed(1)
                delayRead = CompletableDeferred()
            }
        val model = model(fake)
        model.show(HistorySection.RECENT)
        runCurrent()
        model.hide()
        fake.delayRead!!.complete(Unit)
        advanceUntilIdle()
        assertNull(model.state.value.page)
        assertFalse(model.state.value.visible)
    }

    @Test
    fun safetyInvalidationAndOfflineHideOldTitles() = runTest {
        val fake = Fake().apply { seed(1) }
        val model = model(fake)
        model.show(HistorySection.RECENT)
        advanceUntilIdle()
        assertNotNull(model.state.value.page!!.entries.single().content)
        allowed = false
        model.visibilityChanged()
        assertNull(model.state.value.page)
        advanceUntilIdle()
        assertNull(model.state.value.page!!.entries.single().content)
        fake.failure = HistoryFailure.OFFLINE
        model.refresh()
        advanceUntilIdle()
        assertNull(model.state.value.page)
        assertEquals(HistoryFailure.OFFLINE, model.state.value.error)
    }

    @Test
    fun selectionMustReferToActuallyLoadedRowsAndIsExplicit() = runTest {
        val fake = Fake().apply { seed(2) }
        val model = model(fake)
        model.show(HistorySection.RECENT)
        advanceUntilIdle()
        model.requestDelete(setOf("foreign"))
        assertNull(model.state.value.confirmation)
        assertEquals(0, fake.deleteCalls)
        model.requestDelete(setOf(model.state.value.page!!.entries.first().record.id))
        assertNotNull(model.state.value.confirmation)
        model.cancelDelete()
        assertNull(model.state.value.confirmation)
        assertEquals(0, fake.deleteCalls)
    }

    @Test
    fun uncertainDeletionRequiresReadOnlyReconciliationBeforeAnotherConfirmation() = runTest {
        val fake =
            Fake().apply {
                seed(1)
                writeFailure = HistoryFailure.UNCONFIRMED
            }
        val model = model(fake)
        model.show(HistorySection.RECENT)
        advanceUntilIdle()
        model.requestDelete(setOf(model.state.value.page!!.entries.single().record.id))
        model.confirmDelete()
        advanceUntilIdle()
        assertNotNull(model.state.value.uncertainDelete)
        assertEquals(1, fake.deleteCalls)
        model.confirmDelete()
        advanceUntilIdle()
        assertEquals(1, fake.deleteCalls)
        model.reconcile()
        advanceUntilIdle()
        assertNull(model.state.value.uncertainDelete)
        assertEquals(1, fake.deleteCalls)
    }

    @Test
    fun likeNoopLegacyAndForeignReceiptsNeverLogActivity() = runTest {
        val fake = Fake()
        val model = model(fake)
        val personal = PersonalSession(alice.uid, true, true, alice.revision)
        val receipt =
            PersonalChangeReceipt(
                personal,
                PersonalTarget(ContentKind.NEWS, target().id),
                PersonalAction.BOOKMARK,
                true,
                true,
            )
        model.personalChanged(receipt.copy(action = PersonalAction.LIKE), "de")
        model.personalChanged(receipt.copy(didChange = false), "de")
        model.personalChanged(receipt.copy(didChange = null), "de")
        model.personalChanged(receipt.copy(session = personal.copy(uid = "other")), "de")
        advanceUntilIdle()
        assertEquals(0, fake.writeCalls)
    }

    @Test
    fun actualBookmarkAndRegistrationReceiptsMapOnlyTheirExactActions() = runTest {
        val event = target(type = HistoryType.EVENT)
        val fake =
            Fake().apply {
                content[target()] = raw()
                content[event] = raw(event)
            }
        val model = model(fake)
        model.personalChanged(
            PersonalChangeReceipt(
                PersonalSession(alice.uid, true, true, 1),
                PersonalTarget(ContentKind.NEWS, target().id),
                PersonalAction.BOOKMARK,
                true,
                true,
            ),
            "uk",
        )
        model.registrationChanged(
            CommunityRegistrationChange(
                CommunitySession(alice.uid, 1, true, "user"),
                CommunityTarget(ContentKind.EVENTS, event.id),
                EventParticipation(event.id, false, 0, null, time, false, true, true),
                true,
            ),
            "de",
        )
        advanceUntilIdle()
        assertEquals(2, fake.writeCalls)
        assertEquals(
            setOf("savedNews", "canceledEventRegistration"),
            fake.rows.values.map { it.fields["actionType"] }.toSet(),
        )
    }
}
