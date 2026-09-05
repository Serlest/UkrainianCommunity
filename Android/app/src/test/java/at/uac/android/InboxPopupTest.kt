package at.uac.android

import at.uac.android.feature.auth.*
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.inbox.*
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.test.*
import kotlinx.coroutines.withContext
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class InboxPopupTest {
    private val now = Instant.parse("2026-09-03T01:00:00Z")
    private val alice = InboxSession("synthetic-popup-alice", 1, false)
    private val bob = InboxSession("synthetic-popup-bob", 2, true)

    private fun account(session: InboxSession?) =
        InboxPopupAccount(session?.uid, session?.revision ?: 0, session)

    private val gate =
        object : InboxMutationGate {
            override suspend fun <T> withSession(
                session: InboxSession,
                preferences: Boolean,
                operation: suspend () -> T,
            ): T {
                assertFalse(preferences)
                return withContext(NonCancellable) { operation() }
            }
        }

    @Before
    fun setup() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @After
    fun finish() {
        Dispatchers.resetMain()
    }

    private fun row(id: String, extra: Map<String, Any?> = emptyMap()) =
        RawDocument(
            id,
            mapOf(
                "type" to "systemAnnouncement",
                "createdAt" to now,
                "isRead" to false,
                "severity" to "critical",
                "requiresPopup" to true,
                "actionType" to "openEvent",
                "sourceId" to "synthetic-event-01",
                "title" to "Synthetic important notice",
                "message" to "Test only",
            ) + extra,
        )

    private fun head(vararg rows: RawDocument) = InboxPopupHead(rows.toList())

    private fun coordinator() = InboxPopupCoordinator { now }.also { it.configure(account(alice)) }

    private fun decoded(row: RawDocument) = decodeInboxNotice(alice.uid, row)!!

    private class Fake : InboxPopupSource {
        val heads = MutableSharedFlow<InboxPopupHead>(extraBufferCapacity = 16)
        val rows = mutableMapOf<String, RawDocument>()
        val writes = mutableListOf<Pair<String, InboxMutation>>()
        var pageCalls = 0
        var delayWrite = 0L
        var failure: InboxMutation? = null
        var dishonest = false
        var readDelay = 0L

        override fun popupHeads(uid: String) = heads

        override suspend fun popupNotice(uid: String, id: String): RawDocument? {
            delay(readDelay)
            return rows[id]
        }

        override suspend fun page(uid: String, after: InboxCursor?, size: Int): InboxRawPage {
            pageCalls++
            error("Popup must not paginate")
        }

        override suspend fun unreadCount(uid: String) = 0L

        override suspend fun preferences(uid: String) = InboxPreferences()

        override suspend fun savePreferences(
            uid: String,
            preferences: InboxPreferences,
            stillCurrent: () -> Boolean,
        ) = Unit

        override fun changes(uid: String) = emptyFlow<Unit>()

        override suspend fun mutate(
            uid: String,
            ids: List<String>,
            mutation: InboxMutation,
            stillCurrent: () -> Boolean,
        ) {
            delay(delayWrite)
            if (!stillCurrent()) throw CancellationException("Account scope changed")
            if (failure == mutation) throw InboxException(InboxFailure.OFFLINE)
            writes += uid to mutation
            if (!dishonest)
                ids.forEach { id ->
                    rows[id] =
                        rows.getValue(id).let {
                            it.copy(
                                fields =
                                    it.fields +
                                        when (mutation) {
                                            InboxMutation.POPUP_PRESENTED ->
                                                mapOf(
                                                    "popupPresentedAt" to
                                                        Instant.parse("2026-09-03T01:00:01Z")
                                                )
                                            InboxMutation.READ -> mapOf("isRead" to true)
                                            else -> error("Unexpected popup mutation")
                                        }
                            )
                        }
                }
        }
    }

    @Test
    fun initialConfirmedHeadSeedsWithoutPresentingOldNotices() {
        val model = coordinator()
        model.receive(alice, head(row("old")))
        assertTrue(model.confirmed)
        assertNull(model.active)
        assertEquals(0, model.queuedCount)
        model.receive(alice, head(row("old"), row("new")))
        assertEquals("new", model.active?.id)
    }

    @Test
    fun cacheAndPendingWritesCannotSeedOrPresent() {
        for (snapshot in
            listOf(
                head(row("cache")).copy(fromCache = true),
                head(row("pending")).copy(pendingWrites = true),
            )) {
            val model = coordinator()
            model.receive(alice, snapshot)
            assertFalse(model.confirmed)
            assertNull(model.active)
            model.receive(alice, head(row("first-server")))
            assertTrue(model.confirmed)
            assertNull(model.active)
        }
    }

    @Test
    fun exactEligibilityExcludesAccountLegalRetiredAndNonCritical() {
        val normal = decoded(row("one"))
        assertTrue(normal.eligibleForPopup(now))
        for (invalid in
            listOf(
                normal.copy(requiresPopup = false),
                normal.copy(severity = "warning"),
                normal.copy(popupPresentedAt = now),
                normal.copy(archivedAt = now),
                normal.copy(deletedAt = now),
                normal.copy(expiresAt = now),
                normal.copy(expiresAt = now.minusSeconds(1)),
                normal.copy(kind = InboxKind.ACCOUNT_STATUS),
                normal.copy(kind = InboxKind.LEGAL),
            )) assertFalse(invalid.eligibleForPopup(now))
        assertTrue(normal.copy(isRead = true, expiresAt = now.plusSeconds(1)).eligibleForPopup(now))
    }

    @Test
    fun newBatchIsFifoWithStableIdTieBreak() {
        val model = coordinator()
        model.receive(alice, head())
        model.receive(
            alice,
            head(row("later", mapOf("createdAt" to now.plusSeconds(1))), row("b"), row("a")),
        )
        assertEquals("a", model.active?.id)
        assertEquals(2, model.queuedCount)
        assertTrue(model.beginDismiss("a"))
        assertNull(model.active)
        model.endDismiss()
        assertEquals("b", model.active?.id)
        model.beginDismiss("b")
        model.endDismiss()
        assertEquals("later", model.active?.id)
    }

    @Test
    fun activeDisappearanceSortsNewAndQueuedTogether() {
        val model = coordinator()
        model.receive(alice, head())
        model.receive(
            alice,
            head(row("active"), row("queued", mapOf("createdAt" to now.plusSeconds(3)))),
        )
        model.receive(
            alice,
            head(
                row("queued", mapOf("createdAt" to now.plusSeconds(3))),
                row("new-earlier", mapOf("createdAt" to now.plusSeconds(1))),
            ),
        )
        assertEquals("new-earlier", model.active?.id)
    }

    @Test
    fun knownIdDoesNotReplayAfterMutationRemovalOrReturn() {
        val model = coordinator()
        model.receive(alice, head(row("known", mapOf("requiresPopup" to false))))
        model.receive(alice, head(row("known")))
        assertNull(model.active)
        model.receive(alice, head())
        model.receive(alice, head(row("known")))
        assertNull(model.active)
    }

    @Test
    fun activeAndQueueReconcileWithAuthoritativeContent() {
        val model = coordinator()
        model.receive(alice, head())
        model.receive(alice, head(row("a"), row("b"), row("c")))
        model.receive(
            alice,
            head(
                row("a", mapOf("title" to "Updated server title")),
                row("b", mapOf("archivedAt" to now)),
                row("c"),
            ),
        )
        assertEquals("Updated server title", model.active?.title)
        assertEquals(1, model.queuedCount)
        model.receive(
            alice,
            head(row("a", mapOf("popupPresentedAt" to now)), row("c", mapOf("deletedAt" to now))),
        )
        assertNull(model.active)
        assertEquals(0, model.queuedCount)
    }

    @Test
    fun sameUidRevisionMasksOldHeadButPreservesSeenIds() {
        val model = coordinator()
        model.receive(alice, head(row("old")))
        model.receive(alice, head(row("old"), row("new")))
        val next = alice.copy(revision = 3)
        model.configure(InboxPopupAccount(alice.uid, 3, null))
        assertNull(model.active)
        assertFalse(model.confirmed)
        assertFalse(model.receive(alice, head(row("stale"))))
        model.configure(account(next))
        assertNull(model.active)
        model.receive(next, head(row("old"), row("new")))
        assertEquals("new", model.active?.id)
        model.beginDismiss("new")
        model.endDismiss()
        model.receive(next, head(row("old"), row("new")))
        assertNull(model.active)
    }

    @Test
    fun trueLogoutAndAccountSwitchStartWithFreshInitialSeed() {
        for (other in listOf(account(null), account(bob))) {
            val model = coordinator()
            model.receive(alice, head())
            model.receive(alice, head(row("private")))
            model.configure(other)
            assertNull(model.active)
            model.configure(account(alice))
            model.receive(alice, head(row("private"), row("arrived-while-away")))
            assertNull(model.active)
        }
    }

    @Test
    fun cacheTransitionMasksContentUntilNextServerConfirmation() {
        val model = coordinator()
        model.receive(alice, head())
        model.receive(alice, head(row("new")))
        model.receive(alice, head(row("new")).copy(fromCache = true))
        assertNull(model.active)
        model.receive(alice, head(row("new")))
        assertEquals("new", model.active?.id)
    }

    @Test
    fun malformedInitialIdsDoNotBecomeNewAndDuplicateHeadsFailClosed() {
        val model = coordinator()
        model.receive(alice, head(row("malformed", mapOf("isRead" to "bad"))))
        model.receive(alice, head(row("malformed")))
        assertNull(model.active)
        try {
            model.receive(alice, head(row("duplicate"), row("duplicate")))
            fail("Duplicate head")
        } catch (error: InboxException) {
            assertEquals(InboxFailure.INVALID, error.reason)
        }
    }

    @Test
    fun unknownCriticalTextRemainsReadableButHasNoAction() {
        val unknown = decoded(row("unknown", mapOf("type" to "future-critical")))
        assertTrue(unknown.eligibleForPopup(now))
        assertNull(unknown.destination(now))
        assertEquals("Synthetic important notice", unknown.displayTitle("uk"))
    }

    @Test
    fun authBusyPreservesUidButNeverUsableInboxSession() {
        val identity = AuthIdentity(alice.uid, "synthetic@example.invalid", true)
        val ready = AuthSession(AuthStage.AUTHENTICATED, identity, revision = 8)
        assertEquals(alice.uid, ready.inboxPopupAccount().uid)
        assertNotNull(ready.inboxPopupAccount().session)
        assertEquals(alice.uid, ready.copy(busy = true).inboxPopupAccount().uid)
        assertNull(ready.copy(busy = true).inboxPopupAccount().session)
        assertNull(ready.copy(identity = identity.copy(anonymous = true)).inboxPopupAccount().uid)
    }

    @Test
    fun dismissOnlyWritesPopupReceiptUnlessReadExplicitlyRequested() = runTest {
        val source = Fake().apply { rows["one"] = row("one") }
        val repo = InboxPopupRepository(source, { account(alice) }, gate) { now }
        val receipt = repo.acknowledge(alice, decoded(row("one")), false)
        assertNotNull(receipt.popupPresentedAt)
        assertFalse(receipt.isRead)
        assertEquals(listOf(alice.uid to InboxMutation.POPUP_PRESENTED), source.writes)
        repo.acknowledge(alice, decoded(row("one")), true)
        assertEquals(
            listOf(alice.uid to InboxMutation.POPUP_PRESENTED, alice.uid to InboxMutation.READ),
            source.writes,
        )
    }

    @Test
    fun bothConfirmedReceiptsRequiredAndExistingOnesAreNotRewritten() = runTest {
        val source = Fake().apply { rows["one"] = row("one") }
        val repo = InboxPopupRepository(source, { account(alice) }, gate) { now }
        val first = repo.acknowledge(alice, decoded(row("one")), true)
        assertTrue(first.isRead)
        assertNotNull(first.popupPresentedAt)
        repo.acknowledge(alice, decoded(row("one")), true)
        assertEquals(2, source.writes.size)
    }

    @Test
    fun dishonestPopupReceiptCannotTriggerReadMutation() = runTest {
        val source =
            Fake().apply {
                rows["one"] = row("one")
                dishonest = true
            }
        try {
            InboxPopupRepository(source, { account(alice) }, gate) { now }
                .acknowledge(alice, decoded(row("one")), true)
            fail("No receipt")
        } catch (error: InboxException) {
            assertEquals(InboxFailure.UNKNOWN, error.reason)
        }
        assertEquals(listOf(alice.uid to InboxMutation.POPUP_PRESENTED), source.writes)
    }

    @Test
    fun retiredMissingOrForeignNoticeCannotBeAcknowledged() = runTest {
        for (extra in
            listOf(
                mapOf("deletedAt" to now),
                mapOf("archivedAt" to now),
                mapOf("expiresAt" to now),
                mapOf("type" to "accountStatusChanged"),
                mapOf("type" to "legalDocumentsUpdated"),
            )) {
            val source = Fake().apply { rows["one"] = row("one", extra) }
            try {
                InboxPopupRepository(source, { account(alice) }, gate) { now }
                    .acknowledge(alice, decoded(row("one")), false)
                fail("Retired notice")
            } catch (error: InboxException) {
                assertEquals(InboxFailure.MISSING, error.reason)
            }
            assertTrue(source.writes.isEmpty())
        }
        val source = Fake()
        try {
            InboxPopupRepository(source, { account(bob) }, gate) { now }
                .acknowledge(bob, decoded(row("one")), false)
            fail("Foreign notice")
        } catch (error: InboxException) {
            assertEquals(InboxFailure.DENIED, error.reason)
        }
    }

    @Test
    fun serverReadTimeoutNeverWritesOrClaimsSuccess() = runTest {
        val source =
            Fake().apply {
                readDelay = 16_000
                rows["one"] = row("one")
            }
        try {
            InboxPopupRepository(source, { account(alice) }, gate) { now }
                .acknowledge(alice, decoded(row("one")), false)
            fail("Timed out")
        } catch (error: InboxException) {
            assertEquals(InboxFailure.OFFLINE, error.reason)
        }
        assertTrue(source.writes.isEmpty())
    }

    @Test
    fun accountSwitchDuringWriteCannotTargetNewIdentity() = runTest {
        val source =
            Fake().apply {
                rows["one"] = row("one")
                delayWrite = 100
            }
        var current = account(alice)
        val repo = InboxPopupRepository(source, { current }, gate) { now }
        val result = async { runCatching { repo.acknowledge(alice, decoded(row("one")), true) } }
        runCurrent()
        current = account(bob)
        advanceUntilIdle()
        assertTrue(result.await().exceptionOrNull() is CancellationException)
        assertTrue(source.writes.isEmpty())
    }

    @Test
    fun viewModelUsesOnlyHeadAndExpiresWithoutAnotherNetworkSnapshot() = runTest {
        val source = Fake()
        val model =
            InboxPopupViewModel(source, { account(alice) }, gate, backgroundScope) {
                now.plusMillis(testScheduler.currentTime)
            }
        model.bind(account(alice))
        runCurrent()
        source.heads.emit(head())
        runCurrent()
        source.heads.emit(head(row("expires", mapOf("expiresAt" to now.plusMillis(100)))))
        runCurrent()
        assertEquals("expires", model.state.value.active?.id)
        advanceTimeBy(101)
        runCurrent()
        assertNull(model.state.value.active)
        assertEquals(0, source.pageCalls)
    }

    @Test
    fun confirmedOpenEmitsOneFreshScopedAction() = runTest {
        val source = Fake().apply { rows["one"] = row("one", mapOf("sourceId" to "fresh-target")) }
        val model = InboxPopupViewModel(source, { account(alice) }, gate, backgroundScope) { now }
        model.bind(account(alice))
        runCurrent()
        source.heads.emit(head())
        runCurrent()
        source.heads.emit(head(row("one")))
        runCurrent()
        model.dismiss("one", open = true)
        runCurrent()
        val action = model.state.value.action!!
        assertEquals("fresh-target", action.destination.target)
        assertTrue(action.notice.isRead)
        assertNotNull(action.notice.popupPresentedAt)
        assertEquals(action, model.takeAction(action.sequence))
        assertNull(model.takeAction(action.sequence))
    }

    @Test
    fun optionalReadFailureKeepsErrorWithoutActionOrPopupReplay() = runTest {
        val source =
            Fake().apply {
                rows["one"] = row("one")
                rows["two"] = row("two")
                failure = InboxMutation.READ
            }
        val model = InboxPopupViewModel(source, { account(alice) }, gate, backgroundScope) { now }
        model.bind(account(alice))
        runCurrent()
        source.heads.emit(head())
        runCurrent()
        source.heads.emit(head(row("one"), row("two")))
        runCurrent()
        model.dismiss("one", open = true)
        runCurrent()
        assertEquals(InboxFailure.OFFLINE, model.state.value.error)
        assertTrue(model.state.value.acknowledgementFailed)
        assertNull(model.state.value.action)
        assertEquals("two", model.state.value.active?.id)
        assertNotNull(source.rows.getValue("one").fields["popupPresentedAt"])
        assertEquals(false, source.rows.getValue("one").fields["isRead"])
        source.heads.emit(head(source.rows.getValue("one"), row("two")))
        runCurrent()
        assertEquals("two", model.state.value.active?.id)
        assertEquals(1, source.writes.size)
    }

    @Test
    fun duplicateDismissAndOldFrameAreRejectedBeforeSecondMutation() = runTest {
        val source =
            Fake().apply {
                rows["one"] = row("one")
                delayWrite = 100
            }
        var current = account(alice)
        val model = InboxPopupViewModel(source, { current }, gate, backgroundScope) { now }
        model.bind(current)
        runCurrent()
        source.heads.emit(head())
        runCurrent()
        source.heads.emit(head(row("one")))
        runCurrent()
        val old = model.state.value
        assertNull(old.forAccount(account(bob)).active)
        assertNotNull(model.dismiss("one"))
        assertNull(model.dismiss("one"))
        runCurrent()
        current = account(bob)
        model.bind(current)
        advanceTimeBy(101)
        runCurrent()
        assertNull(model.state.value.active)
        assertNull(model.state.value.action)
        assertTrue(source.writes.isEmpty())
    }

    @Test
    fun unknownActionCannotStartAckAndExpiredActionCannotBeConsumed() = runTest {
        var time = now
        val source =
            Fake().apply { rows["one"] = row("one", mapOf("expiresAt" to now.plusSeconds(1))) }
        val model = InboxPopupViewModel(source, { account(alice) }, gate, backgroundScope) { time }
        model.bind(account(alice))
        runCurrent()
        source.heads.emit(head())
        runCurrent()
        source.heads.emit(head(row("unknown", mapOf("type" to "future-critical"))))
        runCurrent()
        assertNull(model.dismiss("unknown", open = true))
        assertTrue(source.writes.isEmpty())
        source.heads.emit(head(row("one", mapOf("expiresAt" to now.plusSeconds(1)))))
        runCurrent()
        model.dismiss("one", open = true)
        runCurrent()
        val action = model.state.value.action!!
        time = now.plusSeconds(1)
        assertNull(model.takeAction(action.sequence))
    }
}
