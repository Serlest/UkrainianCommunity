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
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.test.*
import kotlinx.coroutines.withContext
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class InboxTest {
    private val now = Instant.parse("2026-09-03T01:00:00.123456Z")
    private val alice = InboxSession("synthetic-alice", 1, true)
    private val bob = InboxSession("synthetic-bob", 2, true)
    private val gate =
        object : InboxMutationGate {
            override suspend fun <T> withSession(
                session: InboxSession,
                preferences: Boolean,
                operation: suspend () -> T,
            ): T = withContext(NonCancellable) { operation() }
        }

    @Before
    fun setup() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @After
    fun finish() {
        Dispatchers.resetMain()
    }

    private fun row(id: String = "notice", extra: Map<String, Any?> = emptyMap()) =
        RawDocument(
            id,
            mapOf(
                "type" to "eventUpdated",
                "sourceId" to "event-a",
                "createdAt" to now,
                "isRead" to false,
                "archivedAt" to null,
                "deletedAt" to null,
            ) + extra,
        )

    private fun notice(extra: Map<String, Any?> = emptyMap()) =
        decodeInboxNotice(alice.uid, row(extra = extra))!!

    private inner class Fake : InboxSource {
        val rows = mutableMapOf<String, MutableList<RawDocument>>()
        var prefs = InboxPreferences()
        var writes = 0
        var delayRead = 0L
        var delayWrite = 0L
        var failure: InboxFailure? = null
        var dishonestPreferenceReadback = false
        var stuckCursor = false

        override suspend fun page(uid: String, after: InboxCursor?, size: Int): InboxRawPage {
            delay(delayRead)
            failure?.let { throw InboxException(it) }
            val sorted =
                rows[uid]
                    .orEmpty()
                    .sortedWith(
                        compareByDescending<RawDocument> { it.fields["createdAt"] as Instant }
                            .thenByDescending { it.id }
                    )
            val start = if (after == null) 0 else sorted.indexOfFirst { it.id == after.id } + 1
            val page = sorted.drop(start).take(size)
            val cursor =
                if (stuckCursor) after
                else
                    page.lastOrNull()?.let { InboxCursor(it.fields["createdAt"] as Instant, it.id) }
            return InboxRawPage(page, cursor, start + page.size < sorted.size)
        }

        override suspend fun unreadCount(uid: String): Long {
            failure?.let { throw InboxException(it) }
            return rows[uid].orEmpty().count { decodeInboxNotice(uid, it)?.unread == true }.toLong()
        }

        override suspend fun preferences(uid: String) = prefs

        override suspend fun savePreferences(
            uid: String,
            preferences: InboxPreferences,
            stillCurrent: () -> Boolean,
        ) {
            delay(delayWrite)
            if (!stillCurrent()) throw CancellationException()
            writes++
            if (!dishonestPreferenceReadback) prefs = preferences
        }

        override suspend fun mutate(
            uid: String,
            ids: List<String>,
            mutation: InboxMutation,
            stillCurrent: () -> Boolean,
        ) {
            delay(delayWrite)
            if (!stillCurrent()) throw CancellationException()
            writes++
            rows[uid] =
                rows[uid]
                    .orEmpty()
                    .map { row ->
                        if (row.id !in ids) row
                        else
                            row.copy(
                                fields =
                                    row.fields +
                                        when (mutation) {
                                            InboxMutation.READ -> mapOf("isRead" to true)
                                            InboxMutation.UNREAD -> mapOf("isRead" to false)
                                            InboxMutation.DELETE ->
                                                mapOf("isRead" to true, "deletedAt" to now)
                                            InboxMutation.ARCHIVE ->
                                                mapOf("isRead" to true, "archivedAt" to now)
                                            InboxMutation.POPUP_PRESENTED ->
                                                mapOf("popupPresentedAt" to now)
                                        }
                            )
                    }
                    .toMutableList()
        }

        override fun changes(uid: String) = emptyFlow<Unit>()
    }

    private suspend fun failure(expected: InboxFailure, action: suspend () -> Unit) {
        try {
            action()
            fail("Expected $expected")
        } catch (error: InboxException) {
            assertEquals(expected, error.reason)
        }
    }

    @Test
    fun defaultsAreOptOutWithOneHourReminders() {
        assertEquals(InboxPreferences(false, true, 60), decodeInboxPreferences(null))
        assertFalse(InboxPreferences(reminderLeadMinutes = -1).valid())
        assertFalse(InboxPreferences(reminderLeadMinutes = 10_081).valid())
        assertTrue(InboxPreferences(reminderLeadMinutes = 10_080).valid())
    }

    @Test
    fun malformedPreferencesDoNotSilentlyEnablePush() = runTest {
        failure(InboxFailure.INVALID) {
            decodeInboxPreferences(mapOf("notificationsEnabled" to "true"))
        }
        failure(InboxFailure.INVALID) {
            decodeInboxPreferences(
                mapOf(
                    "notificationsEnabled" to true,
                    "eventRemindersEnabled" to true,
                    "reminderLeadMinutes" to 1.5,
                )
            )
        }
        assertEquals(
            15,
            decodeInboxPreferences(
                    mapOf(
                        "notificationsEnabled" to false,
                        "eventRemindersEnabled" to true,
                        "reminderLeadMinutes" to 15L,
                    )
                )
                .reminderLeadMinutes,
        )
    }

    @Test
    fun documentPathOwnsIdentityAndTimestampPrecisionIsPreserved() {
        val decoded = notice(mapOf("id" to "spoof", "recipientUserId" to bob.uid))
        assertEquals("notice", decoded.id)
        assertEquals(alice.uid, decoded.uid)
        assertEquals(now, decoded.createdAt)
    }

    @Test
    fun invalidDocumentsCannotCreateUnreadGhosts() {
        assertNull(decodeInboxNotice(alice.uid, row(extra = mapOf("createdAt" to "today"))))
        assertNull(decodeInboxNotice(alice.uid, row(extra = mapOf("isRead" to "false"))))
        assertNull(decodeInboxNotice(alice.uid, row(extra = mapOf("deletedAt" to "bad"))))
        assertNull(decodeInboxNotice(alice.uid, row("nested/path")))
    }

    @Test
    fun archivedVisibleDeletedHiddenAndExpiryOnlyDisablesRoute() {
        assertTrue(notice(mapOf("archivedAt" to now)).visible)
        assertFalse(notice(mapOf("archivedAt" to now)).unread)
        assertFalse(notice(mapOf("deletedAt" to now)).visible)
        val expired = notice(mapOf("expiresAt" to now))
        assertTrue(expired.visible)
        assertTrue(expired.unread)
        assertNull(expired.destination(now))
    }

    @Test
    fun legacyKindDefaultsMirrorBuild65() {
        assertEquals(
            InboxDestination(InboxDestinationKind.EVENT, "event-a"),
            notice().destination(now),
        )
        assertEquals("critical", notice(mapOf("type" to "legalDocumentsUpdated")).severity)
        assertEquals(
            InboxDestination(InboxDestinationKind.LEGAL),
            notice(mapOf("type" to "legalDocumentsUpdated")).destination(now),
        )
    }

    @Test
    fun unknownKindStaysReadableButNeverNavigates() {
        val unknown =
            notice(
                mapOf(
                    "type" to "future-server-kind",
                    "actionType" to "openProfile",
                    "title" to "Information",
                )
            )
        assertEquals("Information", unknown.displayTitle("de"))
        assertNull(unknown.destination(now))
        assertNull(
            InboxRoutes.fromPush(mapOf("type" to "future-server-kind", "route" to "profile"))
        )
    }

    @Test
    fun routePriorityAndTypeGuards() {
        val fields =
            mapOf(
                "type" to "eventUpdated",
                "sourceType" to "event",
                "sourceId" to "source",
                "actionTargetId" to "action",
                "routeTargetId" to "route",
            )
        assertEquals("route", InboxRoutes.fromPush(fields)?.target)
        assertEquals("action", InboxRoutes.fromPush(fields - "routeTargetId")?.target)
        assertEquals(
            "source",
            InboxRoutes.fromPush(fields - "routeTargetId" - "actionTargetId")?.target,
        )
        assertNull(InboxRoutes.fromPush(fields + ("actionType" to "openShell")))
        assertNull(InboxRoutes.fromPush(fields + ("sourceType" to "arbitrary")))
        assertNull(InboxRoutes.fromPush(fields + ("route" to "arbitrary")))
    }

    @Test
    fun externalRouteRequiresSafeHttpsAndNoPathInjection() {
        for (url in
            listOf(
                "javascript:alert(1)",
                "file:///tmp/private",
                "http://example.invalid",
                "https://user:pass@example.invalid",
                "https://example.invalid:444",
                "https://example.invalid\\@evil.invalid",
            )) assertNull(InboxRoutes.destination("openURL", url))
        assertEquals(
            "https://example.invalid/path",
            InboxRoutes.destination("url", "https://example.invalid/path")?.target,
        )
        assertNull(InboxRoutes.destination("event", "events/private"))
        assertNull(InboxRoutes.destination("event", null))
        assertEquals(
            InboxDestination(InboxDestinationKind.FEEDBACK),
            InboxRoutes.destination("feedback", null),
        )
    }

    @Test
    fun explicitNoActionAndMissingTargetsCannotNavigate() {
        assertNull(notice(mapOf("actionType" to "none")).destination(now))
        assertNull(notice(mapOf("sourceId" to null)).destination(now))
        assertEquals("target", notice(mapOf("actionTargetId" to "target")).destination(now)?.target)
    }

    @Test
    fun localizationDoesNotExposeServerLocalizationKeys() {
        val notice =
            notice(mapOf("title" to "notifications.fake", "message" to "notifications.fake"))
        assertFalse(notice.displayTitle("uk").startsWith("notifications."))
        assertFalse(notice.displayBody("de").startsWith("notifications."))
        assertNotEquals(notice.displayTitle("de"), notice.displayTitle("uk"))
    }

    @Test
    fun restrictedAndUnverifiedCanReadStatusInboxButNotPreferences() {
        val identity = AuthIdentity(alice.uid, "demo@example.invalid", true)
        val profile = AuthProfile(alice.uid, identity.email, "Demo")
        val restricted =
            AuthSession(AuthStage.AUTHENTICATED, identity, profile, gate = AuthGate.RESTRICTED)
        assertEquals(false, restricted.inboxScope()?.canEditPreferences)
        assertNotNull(restricted.copy(gate = AuthGate.LEGAL_REQUIRED).inboxScope())
        assertNotNull(
            restricted.copy(stage = AuthStage.VERIFICATION_PENDING, profile = null).inboxScope()
        )
        assertNull(restricted.copy(busy = true).inboxScope())
        assertNull(restricted.copy(stage = AuthStage.SESSION_UNAVAILABLE).inboxScope())
        assertNull(restricted.copy(identity = identity.copy(anonymous = true)).inboxScope())
    }

    @Test
    fun ownInboxUsesServerCountAndStablePagination() = runTest {
        val source =
            Fake().apply {
                rows[alice.uid] =
                    (1..51).map { row("notice-${it.toString().padStart(3, '0')}") }.toMutableList()
            }
        val repository = InboxRepository(source, { alice }, gate)
        val first = repository.page()
        val second = repository.page(first.next)
        assertEquals(50, first.items.size)
        assertTrue(first.hasMore)
        assertEquals(1, second.items.size)
        assertEquals(51, (first.items + second.items).map { it.id }.distinct().size)
        assertEquals(51L, repository.unreadCount())
    }

    @Test
    fun guestAndForeignRecipientWritesAreDeniedBeforeMutation() = runTest {
        val source = Fake()
        failure(InboxFailure.SIGN_IN) { InboxRepository(source, { null }, gate).page() }
        failure(InboxFailure.DENIED) {
            InboxRepository(source, { bob }, gate).mutate(notice(), InboxMutation.READ)
        }
        assertEquals(0, source.writes)
    }

    @Test
    fun restrictedPreferencesCannotBeChangedAndReadbackMustMatch() = runTest {
        val source = Fake()
        failure(InboxFailure.NOT_READY) {
            InboxRepository(source, { alice.copy(canEditPreferences = false) }, gate)
                .savePreferences(InboxPreferences(true))
        }
        assertEquals(0, source.writes)
        source.dishonestPreferenceReadback = true
        failure(InboxFailure.UNKNOWN) {
            InboxRepository(source, { alice }, gate).savePreferences(InboxPreferences(true))
        }
    }

    @Test
    fun clearAllProcessesEveryPageAndPreservesServerFields() = runTest {
        val source =
            Fake().apply {
                rows[alice.uid] =
                    (1..123)
                        .map { row("notice-$it", mapOf("title" to "Preserved")) }
                        .toMutableList()
            }
        val repository = InboxRepository(source, { alice }, gate)
        assertEquals(InboxBulkResult(123, true), repository.mutateAll(InboxMutation.DELETE))
        assertEquals(3, source.writes)
        assertEquals(0L, repository.unreadCount())
        assertTrue(
            source.rows[alice.uid]!!.all {
                it.fields["title"] == "Preserved" && it.fields["deletedAt"] == now
            }
        )
    }

    @Test
    fun markAllReadSkipsArchivedDeletedAndAlreadyRead() = runTest {
        val source =
            Fake().apply {
                rows[alice.uid] =
                    mutableListOf(
                        row("unread"),
                        row("archived", mapOf("archivedAt" to now)),
                        row("deleted", mapOf("deletedAt" to now)),
                        row("read", mapOf("isRead" to true)),
                    )
            }
        assertEquals(
            InboxBulkResult(1, true),
            InboxRepository(source, { alice }, gate).mutateAll(InboxMutation.READ),
        )
    }

    @Test
    fun invalidEarlierPageCannotBeReportedAsCompleteClear() = runTest {
        val source =
            Fake().apply {
                rows[alice.uid] =
                    (1..51)
                        .map {
                            row(
                                "notice-${it.toString().padStart(3, '0')}",
                                if (it == 51) mapOf("isRead" to "bad") else emptyMap(),
                            )
                        }
                        .toMutableList()
            }
        val result = InboxRepository(source, { alice }, gate).mutateAll(InboxMutation.DELETE)
        assertFalse(result.complete)
        assertEquals(50, result.changed)
    }

    @Test
    fun repeatingCursorFailsInsteadOfLooping() = runTest {
        val source =
            Fake().apply {
                rows[alice.uid] = (1..51).map { row("n$it") }.toMutableList()
                stuckCursor = true
            }
        failure(InboxFailure.INVALID) { InboxRepository(source, { alice }, gate).page() }
    }

    @Test
    fun timedOutReadIsOfflineAndLateAccountResponseIsDiscarded() = runTest {
        val source = Fake().apply { delayRead = 16_000 }
        failure(InboxFailure.OFFLINE) { InboxRepository(source, { alice }, gate).page() }
        source.delayRead = 100
        var session: InboxSession? = alice
        val repository = InboxRepository(source, { session }, gate)
        val result = async { runCatching { repository.page() } }
        runCurrent()
        session = bob
        advanceUntilIdle()
        assertTrue(result.await().exceptionOrNull() is CancellationException)
    }

    @Test
    fun accountSwitchDuringMutationCannotWriteForNewAccount() = runTest {
        val source =
            Fake().apply {
                delayWrite = 100
                rows[alice.uid] = mutableListOf(row())
            }
        var session: InboxSession? = alice
        val repository = InboxRepository(source, { session }, gate)
        val result = async { runCatching { repository.mutate(notice(), InboxMutation.READ) } }
        runCurrent()
        session = bob
        advanceUntilIdle()
        assertTrue(result.await().exceptionOrNull() is CancellationException)
        assertEquals(0, source.writes)
    }

    @Test
    fun viewModelDropsPrivateStateSynchronouslyOnLogoutAndMaskRejectsOldFrame() = runTest {
        val source = Fake().apply { rows[alice.uid] = mutableListOf(row()) }
        var session: InboxSession? = alice
        val model = InboxViewModel(source, { session }, gate, backgroundScope)
        model.bind(alice)
        runCurrent()
        assertEquals(1, model.state.value.items.size)
        assertTrue(model.state.value.forSession(bob).items.isEmpty())
        session = null
        model.bind(null)
        assertTrue(model.state.value.items.isEmpty())
        assertEquals(0L, model.state.value.unreadCount)
        assertNull(model.state.value.preferences)
    }

    @Test
    fun offlineRefreshKeepsSameUsersKnownBadgeButPermissionDenialErasesIt() = runTest {
        val source = Fake().apply { rows[alice.uid] = mutableListOf(row()) }
        val model = InboxViewModel(source, { alice }, gate, backgroundScope)
        model.bind(alice)
        runCurrent()
        source.failure = InboxFailure.OFFLINE
        model.refresh()
        runCurrent()
        assertEquals(1L, model.state.value.unreadCount)
        assertEquals(1, model.state.value.items.size)
        source.failure = InboxFailure.DENIED
        model.refresh()
        runCurrent()
        assertEquals(0L, model.state.value.unreadCount)
        assertTrue(model.state.value.items.isEmpty())
    }

    @Test
    fun repeatedTapDoesNotIssueParallelWrites() = runTest {
        val source =
            Fake().apply {
                rows[alice.uid] = mutableListOf(row())
                delayWrite = 100
            }
        val model = InboxViewModel(source, { alice }, gate, backgroundScope)
        model.bind(alice)
        runCurrent()
        assertNotNull(model.change(notice(), InboxMutation.READ))
        assertNull(model.change(notice(), InboxMutation.READ))
        runCurrent()
        advanceTimeBy(101)
        runCurrent()
        assertEquals(1, source.writes)
    }

    @Test
    fun preferenceCallbackReceivesOnlyConfirmedCurrentServerValueAndFailureCannotUndoSave() =
        runTest {
            val source = Fake()
            val receipts = mutableListOf<Pair<InboxSession, InboxPreferences>>()
            val model =
                InboxViewModel(source, { alice }, gate, backgroundScope) { session, value ->
                    receipts += session to value
                    error("Incidental reminder scheduling failure")
                }
            model.bind(alice)
            runCurrent()
            val requested = InboxPreferences(true, true, 120)
            model.savePreferences(requested)
            runCurrent()
            assertEquals(listOf(alice to requested), receipts)
            assertTrue(model.state.value.preferencesSaved)
            assertEquals(requested, model.state.value.preferences)
            assertNull(model.state.value.error)
        }

    @Test
    fun unconfirmedPreferenceWriteCannotScheduleReminders() = runTest {
        val source = Fake().apply { dishonestPreferenceReadback = true }
        var callbacks = 0
        val model = InboxViewModel(source, { alice }, gate, backgroundScope) { _, _ -> callbacks++ }
        model.bind(alice)
        runCurrent()
        model.savePreferences(InboxPreferences(true))
        runCurrent()
        assertEquals(0, callbacks)
        assertFalse(model.state.value.preferencesSaved)
        assertNotNull(model.state.value.error)
    }

    @Test
    fun delayedOldAccountPreferencesCannotReachTheNewAccountsReminderHook() = runTest {
        val source = Fake().apply { delayWrite = 100 }
        var session: InboxSession? = alice
        var callbacks = 0
        val model =
            InboxViewModel(source, { session }, gate, backgroundScope) { _, _ -> callbacks++ }
        model.bind(alice)
        runCurrent()
        model.savePreferences(InboxPreferences(true))
        runCurrent()
        session = bob
        model.bind(bob)
        advanceTimeBy(101)
        runCurrent()
        assertEquals(0, callbacks)
        assertEquals(0, source.writes)
        assertFalse(model.state.value.preferencesSaved)
    }
}
