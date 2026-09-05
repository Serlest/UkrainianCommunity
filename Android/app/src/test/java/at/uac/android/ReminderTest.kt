package at.uac.android

import at.uac.android.feature.auth.AuthIdentity
import at.uac.android.feature.auth.AuthProfile
import at.uac.android.feature.auth.AuthSession
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.browse.Content
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.inbox.InboxPreferences
import at.uac.android.feature.reminders.*
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ReminderTest {
    private val now = Instant.parse("2026-09-03T10:00:00Z")
    private val alice = ReminderSession("synthetic-reminder-alice", 3, true)
    private val bob = ReminderSession("synthetic-reminder-bob", 4, true)
    private val prefs = InboxPreferences(true, true, 60)

    @Before
    fun setup() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @After
    fun cleanup() {
        Dispatchers.resetMain()
    }

    private fun event(
        start: Instant = now.plusSeconds(7_200),
        end: Instant = start.plusSeconds(3_600),
        extra: Map<String, Any?> = emptyMap(),
    ): Content =
        Content(
            ContentKind.EVENTS,
            "synthetic-event",
            mapOf(
                "moderationStatus" to "approved",
                "sourceType" to "organization",
                "startDate" to start,
                "endDate" to end,
                "title" to "Private synthetic title",
            ) + extra,
        )

    private fun occurrence(id: String, start: Instant, status: String = "scheduled") =
        mapOf(
            "id" to id,
            "startDate" to start,
            "endDate" to start.plusSeconds(3_600),
            "status" to status,
        )

    private fun snapshot(
        session: ReminderSession = alice,
        candidates: List<ReminderCandidate> =
            listOf(ReminderPlanner.candidate(event(), prefs, now)!!),
        preferences: InboxPreferences = prefs,
        complete: Boolean = true,
    ) = ReminderSnapshot(session, preferences, candidates, complete, now)

    private class Disk {
        var plan = ReminderPlan()
        var writes = 0
        var failRead = false
        var failWrite = false
        var discardWrites = false
        val ledger =
            TransactionalReminderLedger(
                {
                    if (failRead) throw ReminderException(ReminderFailure.STORAGE)
                    plan
                },
                {
                    if (failWrite) throw ReminderException(ReminderFailure.STORAGE)
                    writes++
                    if (!discardWrites)
                        plan = ReminderLedgerCodec.decode(ReminderLedgerCodec.encode(it))
                },
            )
    }

    private class Scheduler : ReminderScheduler {
        val scheduled = mutableListOf<ReminderTicket>()
        var cancellations = 0

        override fun requestNext(ticket: ReminderTicket, now: Instant) {
            scheduled += ticket
        }

        override fun cancelOwned() {
            cancellations++
        }
    }

    private class Sink : ReminderNotificationSink {
        var allowed = ReminderPermission.ALLOWED
        var failPost = false
        var cancellations = 0
        val shown = mutableListOf<ConfirmedReminder>()

        override fun permission() = allowed

        override fun postGeneric(receipt: ConfirmedReminder) {
            if (failPost) throw ReminderException(ReminderFailure.SYSTEM)
            shown += receipt
        }

        override fun cancelOwned() {
            cancellations++
        }
    }

    private inner class Source : ReminderSource {
        var owner: String? = reminderOwner(alice.uid)
        var wait: CompletableDeferred<Unit>? = null
        var fail = false
        var verifications = 0
        var snapshots = 0
        var data = snapshot()
        var onVerified: () -> Unit = {}

        override fun currentOwner() = owner

        override suspend fun snapshot(
            session: ReminderSession,
            current: () -> Boolean,
        ): ReminderSnapshot {
            snapshots++
            wait?.await()
            if (fail) throw ReminderException(ReminderFailure.OFFLINE)
            return data.copy(session = session)
        }

        override suspend fun verify(
            ticket: ReminderTicket,
            current: () -> Boolean,
        ): ConfirmedReminder {
            verifications++
            wait?.await()
            if (fail) throw ReminderException(ReminderFailure.OFFLINE)
            onVerified()
            return ConfirmedReminder(ticket, if (ticket.localTest) null else event(), ticket.fireAt)
        }
    }

    private fun request(ticket: ReminderTicket) = ReminderTapRequest(ticket.epoch, ticket.token)

    @Test
    fun defaultsAndIosLeadChoicesRemainDistinctFromValidLegacyValues() {
        assertFalse(InboxPreferences().notificationsEnabled)
        assertTrue(InboxPreferences().eventRemindersEnabled)
        assertEquals(60, InboxPreferences().reminderLeadMinutes)
        assertEquals(listOf(15, 30, 60, 120, 1_440), ReminderPlanner.leadChoices)
        assertTrue(prefs.copy(reminderLeadMinutes = 0).valid())
        assertTrue(prefs.copy(reminderLeadMinutes = 10_080).valid())
        assertFalse(prefs.copy(reminderLeadMinutes = -1).valid())
        assertFalse(prefs.copy(reminderLeadMinutes = 10_081).valid())
    }

    @Test
    fun disabledPreferencesNeverPlan() {
        assertNull(
            ReminderPlanner.candidate(event(), prefs.copy(notificationsEnabled = false), now)
        )
        assertNull(
            ReminderPlanner.candidate(event(), prefs.copy(eventRemindersEnabled = false), now)
        )
    }

    @Test
    fun invalidLeadIsRejectedNotClampedIntoConsent() {
        assertTrue(
            runCatching {
                ReminderPlanner.candidate(event(), prefs.copy(reminderLeadMinutes = -1), now)
            }
                .isFailure
        )
    }

    @Test
    fun legacyTopLevelOccurrenceAndMinutePrecisionMatchIos() {
        val candidate = ReminderPlanner.candidate(event(now.plusSeconds(7_259)), prefs, now)!!
        assertEquals("legacy", candidate.occurrence.id)
        assertEquals(now.plusSeconds(3_600), candidate.fireAt)
    }

    @Test
    fun roundingToCurrentMinuteDoesNotCreatePastAlarm() {
        assertNull(
            ReminderPlanner.candidate(event(now.plusSeconds(3_659)), prefs, now.plusSeconds(30))
        )
    }

    @Test
    fun nearestSortsAndSkipsCancelledOccurrences() {
        val first = now.plusSeconds(7_200)
        val later = now.plusSeconds(14_400)
        val content =
            event(
                extra =
                    mapOf(
                        "occurrences" to
                            listOf(
                                occurrence("later", later),
                                occurrence("cancelled", now.plusSeconds(3_600), "cancelled"),
                                occurrence("first", first),
                            )
                    )
            )
        assertEquals("first", ReminderPlanner.candidate(content, prefs, now)!!.occurrence.id)
    }

    @Test
    fun ongoingOccurrenceDoesNotJumpToLaterEvent() {
        val content =
            event(
                extra =
                    mapOf(
                        "occurrences" to
                            listOf(
                                occurrence("ongoing", now.minusSeconds(600)),
                                occurrence("future", now.plusSeconds(7_200)),
                            )
                    )
            )
        assertEquals("ongoing", ReminderPlanner.nearest(content, now)!!.id)
        assertNull(ReminderPlanner.candidate(content, prefs, now))
    }

    @Test
    fun cancelledEventAndAllCancelledOccurrencesAreExcluded() {
        assertNull(
            ReminderPlanner.candidate(
                event(extra = mapOf("cancellationState" to "cancelled")),
                prefs,
                now,
            )
        )
        assertNull(
            ReminderPlanner.candidate(
                event(
                    extra =
                        mapOf(
                            "occurrences" to
                                listOf(occurrence("one", now.plusSeconds(7_200), "cancelled"))
                        )
                ),
                prefs,
                now,
            )
        )
    }

    @Test
    fun privateAndNonOrganizationEventsAreExcluded() {
        assertNull(
            ReminderPlanner.candidate(
                event(extra = mapOf("moderationStatus" to "draft")),
                prefs,
                now,
            )
        )
        assertNull(
            ReminderPlanner.candidate(event(extra = mapOf("sourceType" to "user")), prefs, now)
        )
    }

    @Test
    fun instantsDoNotReapplyDstOffsets() {
        val beforeDst = Instant.parse("2026-10-25T00:00:00Z")
        val candidate =
            ReminderPlanner.candidate(
                event(Instant.parse("2026-10-25T02:00:00Z")),
                prefs,
                beforeDst,
            )!!
        assertEquals(Instant.parse("2026-10-25T01:00:00Z"), candidate.fireAt)
    }

    @Test
    fun overlargeOccurrenceArrayFailsClosed() {
        assertTrue(
            runCatching {
                ReminderPlanner.nearest(
                    event(
                        extra =
                            mapOf(
                                "occurrences" to
                                    List(367) { occurrence("$it", now.plusSeconds(7_200)) }
                            )
                    ),
                    now,
                )
            }
                .isFailure
        )
    }

    @Test
    fun ownerHashIsScopedAndContainsNoRawIdentity() {
        assertEquals(reminderOwner(alice.uid), reminderOwner(alice.uid))
        assertNotEquals(reminderOwner(alice.uid), reminderOwner(bob.uid))
        assertTrue(reminderOwner(alice.uid).matches(Regex("[a-f0-9]{64}")))
        assertFalse(reminderOwner(alice.uid).contains(alice.uid))
    }

    @Test
    fun ledgerRoundTripHasNoUidOrPrivateTitle() = runTest {
        val disk = Disk()
        val plan = disk.ledger.replace(snapshot()) { true }
        val bytes = ReminderLedgerCodec.encode(plan)
        assertEquals(plan, ReminderLedgerCodec.decode(bytes))
        assertFalse(bytes.toString(Charsets.UTF_8).contains(alice.uid))
        assertFalse(bytes.toString(Charsets.UTF_8).contains("Private synthetic title"))
    }

    @Test
    fun corruptTruncatedOversizedAndTrailingLedgerBytesAreRejected() = runTest {
        val bytes = ReminderLedgerCodec.encode(Disk().ledger.replace(snapshot()) { true })
        assertTrue(
            runCatching { ReminderLedgerCodec.decode(bytes.copyOf(bytes.size - 1)) }.isFailure
        )
        assertTrue(runCatching { ReminderLedgerCodec.decode(bytes + byteArrayOf(1)) }.isFailure)
        assertTrue(
            runCatching { ReminderLedgerCodec.decode(ByteArray(ReminderLedgerCodec.MAX_BYTES + 1)) }
                .isFailure
        )
        bytes[0] = 0
        assertTrue(runCatching { ReminderLedgerCodec.decode(bytes) }.isFailure)
    }

    @Test
    fun partialSnapshotNeverReplacesConfirmedPlan() = runTest {
        val disk = Disk()
        val before = disk.ledger.replace(snapshot()) { true }
        assertTrue(
            runCatching { disk.ledger.replace(snapshot(complete = false)) { true } }.isFailure
        )
        assertEquals(before, disk.plan)
    }

    @Test
    fun duplicateEventAndOverLimitSnapshotsAreRejected() = runTest {
        val candidate = snapshot().candidates.single()
        val disk = Disk()
        assertTrue(
            runCatching {
                disk.ledger.replace(snapshot(candidates = listOf(candidate, candidate))) {
                    true
                }
            }
                .isFailure
        )
        assertTrue(
            runCatching {
                disk.ledger.replace(
                    snapshot(candidates = List(201) { candidate.copy(eventId = "event-$it") })
                ) {
                    true
                }
            }
                .isFailure
        )
        assertEquals(0, disk.writes)
    }

    @Test
    fun ledgerWriteFailureAndUnconfirmedReadBackDoNotReturnPlan() = runTest {
        val disk = Disk()
        disk.failWrite = true
        assertTrue(runCatching { disk.ledger.replace(snapshot()) { true } }.isFailure)
        disk.failWrite = false
        disk.discardWrites = true
        assertTrue(runCatching { disk.ledger.replace(snapshot()) { true } }.isFailure)
    }

    @Test
    fun changedScopeRejectsLedgerWrite() = runTest {
        val disk = Disk()
        assertTrue(runCatching { disk.ledger.replace(snapshot()) { false } }.isFailure)
        assertEquals(0, disk.writes)
    }

    @Test
    fun claimIsDurableOneShotAndCannotHappenEarly() = runTest {
        val disk = Disk()
        val ticket = disk.ledger.replace(snapshot()) { true }.tickets.single()
        assertNull(disk.ledger.finish(ticket, true, now) { true })
        val claimed = disk.ledger.finish(ticket, true, ticket.fireAt) { true }!!
        assertEquals(ReminderTicketState.CLAIMED, claimed.state)
        assertNull(disk.ledger.finish(ticket, true, ticket.fireAt) { true })
        assertEquals(1, disk.plan.receipts.size)
    }

    @Test
    fun leadChangeDoesNotReplayClaimedOccurrence() = runTest {
        val disk = Disk()
        val ticket = disk.ledger.replace(snapshot()) { true }.tickets.single()
        disk.ledger.finish(ticket, true, ticket.fireAt) { true }
        val next =
            disk.ledger.replace(
                snapshot(
                    candidates =
                        listOf(snapshot().candidates.single().copy(fireAt = now.plusSeconds(5_400)))
                )
            ) {
                true
            }
        assertEquals(0, next.tickets.count { it.state == ReminderTicketState.PENDING })
    }

    @Test
    fun sameOwnerRefreshKeepsOnlyClaimedTapAndForeignOwnerClearsIt() = runTest {
        val disk = Disk()
        val ticket = disk.ledger.replace(snapshot()) { true }.tickets.single()
        disk.ledger.finish(ticket, true, ticket.fireAt) { true }
        disk.ledger.retire(ticket.owner) { true }
        assertEquals(ReminderTicketState.CLAIMED, disk.plan.tickets.single().state)
        disk.ledger.retire(reminderOwner(bob.uid)) { true }
        assertTrue(disk.plan.tickets.isEmpty())
        assertNull(disk.plan.owner)
        assertEquals(1, disk.plan.receipts.size)
    }

    @Test
    fun oldPendingTokenIsInvalidAfterReconcileEvenForSameUid() = runTest {
        val disk = Disk()
        val old = disk.ledger.replace(snapshot()) { true }.tickets.single()
        val fresh = disk.ledger.replace(snapshot()) { true }.tickets.single()
        assertNotEquals(old.token, fresh.token)
        assertNull(disk.ledger.finish(old, true, old.fireAt) { true })
    }

    @Test
    fun absentHostDoesNotSupplyReadyAndAttachedNonReadyVetoesColdProof() {
        val authority = ReminderAuthority()
        val owner = reminderOwner(alice.uid)
        assertNull(authority.currentSession())
        assertNotNull(authority.capture(owner))
        authority.bind(alice.copy(ready = false))
        assertNull(authority.capture(owner))
        authority.bind(alice)
        val captured = authority.capture(owner)!!
        authority.bind(alice.copy(revision = 4))
        assertFalse(authority.matches(owner, captured))
        authority.bind(null)
        assertNull(authority.capture(owner))
    }

    @Test
    fun explicitInvalidationStopsInFlightProofWithoutChangingIdentity() {
        val authority = ReminderAuthority()
        authority.bind(alice)
        val lease = authority.capture(reminderOwner(alice.uid))!!
        authority.invalidate()
        assertEquals(alice, authority.currentSession())
        assertFalse(authority.matches(reminderOwner(alice.uid), lease))
    }

    @Test
    fun delayedBindCannotUseOldReadyRevisionAfterLiveAuthChanged() {
        var live =
            AuthSession(
                AuthStage.AUTHENTICATED,
                AuthIdentity(alice.uid, "synthetic@example.invalid", true),
                AuthProfile(alice.uid, "synthetic@example.invalid", "Synthetic"),
                revision = alice.revision,
            )
        val authority = ReminderAuthority()
        authority.attachAuth { live }
        authority.bind(alice)
        val owner = reminderOwner(alice.uid)
        val lease = authority.capture(owner)!!
        live = live.copy(revision = live.revision + 1)
        assertFalse(authority.matches(owner, lease))
        assertNull(authority.capture(owner))
    }

    @Test
    fun delayedBindCannotIgnoreLiveBusyOrReadyLoss() {
        var live =
            AuthSession(
                AuthStage.AUTHENTICATED,
                AuthIdentity(alice.uid, "synthetic@example.invalid", true),
                AuthProfile(alice.uid, "synthetic@example.invalid", "Synthetic"),
                revision = alice.revision,
            )
        val authority = ReminderAuthority()
        authority.attachAuth { live }
        authority.bind(alice)
        val owner = reminderOwner(alice.uid)
        val lease = authority.capture(owner)!!
        live = live.copy(busy = true)
        assertFalse(authority.matches(owner, lease))
        assertNull(authority.capture(owner))
        live = live.copy(busy = false, stage = AuthStage.SESSION_UNAVAILABLE)
        assertNull(authority.capture(owner))
    }

    @Test
    fun exactReadyScopeKeepsConfirmedReminderUiState() {
        val state =
            ReminderState(
                ReminderStage.SCHEDULED,
                ReminderPermission.ALLOWED,
                7,
                localTestRequested = true,
                session = alice,
            )
        assertSame(state, state.forSession(alice))
    }

    @Test
    fun delayedAccountBindMasksFormerCountErrorAndTestReceipt() {
        val state =
            ReminderState(
                ReminderStage.FAILED,
                ReminderPermission.ALLOWED,
                7,
                ReminderFailure.STORAGE,
                localTestRequested = true,
                session = alice,
            )
        val projected = state.forSession(bob)
        assertEquals(
            ReminderState(permission = ReminderPermission.ALLOWED, session = bob),
            projected,
        )
        assertEquals(ReminderStage.IDLE, projected.stage)
        assertEquals(0, projected.scheduled)
        assertNull(projected.error)
        assertFalse(projected.localTestRequested)
    }

    @Test
    fun sameUidNewRevisionCannotRenderFormerReminderState() {
        val next = alice.copy(revision = alice.revision + 1)
        val state =
            ReminderState(
                ReminderStage.SCHEDULED,
                ReminderPermission.ALLOWED,
                7,
                localTestRequested = true,
                session = alice,
            )
        assertEquals(
            ReminderState(permission = ReminderPermission.ALLOWED, session = next),
            state.forSession(next),
        )
    }

    @Test
    fun readyLossAndGuestMaskEvenWhenUidAndRevisionAreUnchanged() {
        val state =
            ReminderState(
                ReminderStage.SCHEDULED,
                ReminderPermission.CHANNEL_DENIED,
                7,
                ReminderFailure.OFFLINE,
                localTestRequested = true,
                session = alice,
            )
        for (current in listOf(alice.copy(ready = false), null)) {
            assertEquals(
                ReminderState(permission = ReminderPermission.CHANNEL_DENIED, session = current),
                state.forSession(current),
            )
        }
        val notReady = alice.copy(ready = false)
        assertEquals(
            ReminderState(permission = ReminderPermission.CHANNEL_DENIED, session = notReady),
            state.copy(session = notReady).forSession(notReady),
        )
    }

    @Test
    fun unscopedStateNeverBecomesAccountAuthorityByProjection() {
        val unscoped =
            ReminderState(
                ReminderStage.SCHEDULED,
                ReminderPermission.ALLOWED,
                7,
                localTestRequested = true,
            )
        assertEquals(
            ReminderState(permission = ReminderPermission.ALLOWED, session = alice),
            unscoped.forSession(alice),
        )
        assertEquals(
            ReminderState(permission = ReminderPermission.ALLOWED),
            unscoped.forSession(null),
        )
    }

    @Test
    fun controllerPublishesCapturedScopeForPendingConfirmedFailedAndReboundStates() = runTest {
        val source = Source()
        val disk = Disk()
        val model =
            ReminderController(
                source,
                disk.ledger,
                Scheduler(),
                Sink(),
                ReminderAuthority(),
                backgroundScope,
            ) {
                now
            }
        source.wait = CompletableDeferred()
        model.bind(alice)
        runCurrent()
        assertEquals(ReminderStage.CHECKING, model.state.value.stage)
        assertEquals(alice, model.state.value.session)
        source.wait!!.complete(Unit)
        runCurrent()
        assertEquals(ReminderStage.SCHEDULED, model.state.value.stage)
        assertEquals(alice, model.state.value.session)
        source.wait = null
        source.fail = true
        model.reconcile()
        runCurrent()
        assertEquals(ReminderStage.FAILED, model.state.value.stage)
        assertEquals(alice, model.state.value.session)
        model.bind(bob.copy(ready = false))
        runCurrent()
        assertEquals(ReminderStage.IDLE, model.state.value.stage)
        assertEquals(bob.copy(ready = false), model.state.value.session)
        model.bind(null)
        runCurrent()
        assertEquals(ReminderState(permission = ReminderPermission.ALLOWED), model.state.value)
    }

    @Test
    fun chosenAppLanguageWinsAndUnknownValuesCannotBecomeNotificationContent() {
        assertEquals("de", reminderLanguage("de", "uk"))
        assertEquals("uk", reminderLanguage("uk", "de"))
        assertEquals("uk", reminderLanguage("unknown private string", "uk"))
        assertEquals("de", reminderLanguage(null, "fr"))
    }

    @Test
    fun confirmedScheduleRequestsOnlyNearestAlarm() = runTest {
        val source = Source()
        val disk = Disk()
        val scheduler = Scheduler()
        val sink = Sink()
        val model =
            ReminderController(
                source,
                disk.ledger,
                scheduler,
                sink,
                ReminderAuthority(),
                backgroundScope,
            ) {
                now
            }
        model.bind(alice)
        runCurrent()
        assertEquals(ReminderStage.SCHEDULED, model.state.value.stage)
        assertEquals(1, scheduler.scheduled.size)
        assertEquals(1, model.state.value.scheduled)
        assertTrue(sink.shown.isEmpty())
    }

    @Test
    fun deniedSystemPermissionRetiresPlanWithoutServerReadOrOptimisticConsent() = runTest {
        val source = Source()
        val disk = Disk()
        val sink = Sink().apply { allowed = ReminderPermission.APP_DENIED }
        disk.ledger.replace(snapshot()) { true }
        val model =
            ReminderController(
                source,
                disk.ledger,
                Scheduler(),
                sink,
                ReminderAuthority(),
                backgroundScope,
            ) {
                now
            }
        model.bind(alice)
        runCurrent()
        assertEquals(0, source.snapshots)
        assertTrue(disk.plan.tickets.isEmpty())
        assertEquals(ReminderStage.DISABLED, model.state.value.stage)
    }

    @Test
    fun logoutWhileSnapshotPendingCannotInstallOldPlan() = runTest {
        val source = Source().apply { wait = CompletableDeferred() }
        val disk = Disk()
        val scheduler = Scheduler()
        val model =
            ReminderController(
                source,
                disk.ledger,
                scheduler,
                Sink(),
                ReminderAuthority(),
                backgroundScope,
            ) {
                now
            }
        model.bind(alice)
        runCurrent()
        model.bind(null)
        source.owner = null
        source.wait!!.complete(Unit)
        runCurrent()
        assertTrue(scheduler.scheduled.isEmpty())
        assertTrue(disk.plan.tickets.isEmpty())
    }

    @Test
    fun offlineReconcileCancelsOldPlanAndShowsRetryState() = runTest {
        val source = Source()
        val disk = Disk()
        val scheduler = Scheduler()
        val model =
            ReminderController(
                source,
                disk.ledger,
                scheduler,
                Sink(),
                ReminderAuthority(),
                backgroundScope,
            ) {
                now
            }
        model.bind(alice)
        runCurrent()
        source.fail = true
        model.preferencesChanged()
        runCurrent()
        assertEquals(ReminderStage.FAILED, model.state.value.stage)
        assertEquals(ReminderFailure.OFFLINE, model.state.value.error)
        assertTrue(disk.plan.tickets.isEmpty())
    }

    @Test
    fun localTestIsExplicitAndUsesNoEventTarget() = runTest {
        val source = Source()
        val disk = Disk()
        val model =
            ReminderController(
                source,
                disk.ledger,
                Scheduler(),
                Sink(),
                ReminderAuthority(),
                backgroundScope,
            ) {
                now
            }
        model.scheduleLocalTest()
        runCurrent()
        assertTrue(disk.plan.tickets.isEmpty())
        model.bind(alice)
        runCurrent()
        model.scheduleLocalTest()
        runCurrent()
        assertEquals(1, disk.plan.tickets.count { it.localTest })
        assertTrue(model.state.value.localTestRequested)
    }

    @Test
    fun deliveryClaimsBeforeNotificationAndDuplicateBroadcastNeverReplays() = runTest {
        val source = Source()
        val disk = Disk()
        val sink = Sink()
        val scheduler = Scheduler()
        val ticket = disk.ledger.replace(snapshot()) { true }.tickets.single()
        val delivery =
            ReminderDelivery(source, disk.ledger, scheduler, sink, ReminderAuthority()) {
                ticket.fireAt
            }
        delivery.receive(request(ticket))
        delivery.receive(request(ticket))
        assertEquals(1, sink.shown.size)
        assertEquals(ReminderTicketState.CLAIMED, disk.plan.tickets.single().state)
        assertEquals(1, source.verifications)
    }

    @Test
    fun offlineAndExpiredDeliveryAreTerminalWithoutNotification() = runTest {
        val source = Source().apply { fail = true }
        val disk = Disk()
        val sink = Sink()
        val ticket = disk.ledger.replace(snapshot()) { true }.tickets.single()
        val delivery =
            ReminderDelivery(source, disk.ledger, Scheduler(), sink, ReminderAuthority()) {
                ticket.fireAt
            }
        delivery.receive(request(ticket))
        delivery.receive(request(ticket))
        assertTrue(sink.shown.isEmpty())
        assertEquals(1, source.verifications)
        assertEquals(ReminderTicketState.SUPPRESSED, disk.plan.tickets.single().state)
    }

    @Test
    fun postFailureDoesNotReleaseClaimOrReplay() = runTest {
        val source = Source()
        val disk = Disk()
        val sink = Sink().apply { failPost = true }
        val ticket = disk.ledger.replace(snapshot()) { true }.tickets.single()
        val delivery =
            ReminderDelivery(source, disk.ledger, Scheduler(), sink, ReminderAuthority()) {
                ticket.fireAt
            }
        delivery.receive(request(ticket))
        sink.failPost = false
        delivery.receive(request(ticket))
        assertTrue(sink.shown.isEmpty())
        assertEquals(ReminderTicketState.CLAIMED, disk.plan.tickets.single().state)
    }

    @Test
    fun accountSwitchDuringServerReadNeverClaimsOrPostsOldNotice() = runTest {
        val source = Source()
        val disk = Disk()
        val sink = Sink()
        val authority = ReminderAuthority()
        authority.bind(alice)
        source.onVerified = {
            source.owner = reminderOwner(bob.uid)
            authority.bind(bob)
        }
        val ticket = disk.ledger.replace(snapshot()) { true }.tickets.single()
        ReminderDelivery(source, disk.ledger, Scheduler(), sink, authority) { ticket.fireAt }
            .receive(request(ticket))
        assertTrue(sink.shown.isEmpty())
        assertTrue(disk.plan.receipts.isEmpty())
    }

    @Test
    fun permissionLossAfterVerificationConsumesButDoesNotShow() = runTest {
        val source = Source()
        val disk = Disk()
        val sink = Sink()
        source.onVerified = { sink.allowed = ReminderPermission.CHANNEL_DENIED }
        val ticket = disk.ledger.replace(snapshot()) { true }.tickets.single()
        ReminderDelivery(source, disk.ledger, Scheduler(), sink, ReminderAuthority()) {
                ticket.fireAt
            }
            .receive(request(ticket))
        assertTrue(sink.shown.isEmpty())
        assertEquals(ReminderTicketState.SUPPRESSED, disk.plan.tickets.single().state)
    }

    @Test
    fun claimStorageFailureCannotShow() = runTest {
        val source = Source()
        val disk = Disk()
        val sink = Sink()
        val ticket = disk.ledger.replace(snapshot()) { true }.tickets.single()
        disk.failWrite = true
        runCatching {
            ReminderDelivery(source, disk.ledger, Scheduler(), sink, ReminderAuthority()) {
                    ticket.fireAt
                }
                .receive(request(ticket))
        }
        assertTrue(sink.shown.isEmpty())
    }

    @Test
    fun coldRestoreSchedulesOnlyFutureTicketsAndNeverDisplaysFromDisk() = runTest {
        val source = Source()
        val disk = Disk()
        val sink = Sink()
        val scheduler = Scheduler()
        val ticket = disk.ledger.replace(snapshot()) { true }.tickets.single()
        ReminderDelivery(source, disk.ledger, scheduler, sink, ReminderAuthority()) { now }
            .reschedule()
        assertEquals(1, scheduler.scheduled.size)
        assertTrue(sink.shown.isEmpty())
        assertEquals(0, source.verifications)
        scheduler.scheduled.clear()
        ReminderDelivery(source, disk.ledger, scheduler, sink, ReminderAuthority()) {
                ticket.fireAt.plusSeconds(1)
            }
            .reschedule()
        assertTrue(scheduler.scheduled.isEmpty())
    }

    @Test
    fun foreignColdIdentityCancelsOwnedSystemState() = runTest {
        val source = Source().apply { owner = reminderOwner(bob.uid) }
        val disk = Disk()
        val sink = Sink()
        val scheduler = Scheduler()
        disk.ledger.replace(snapshot()) { true }
        ReminderDelivery(source, disk.ledger, scheduler, sink, ReminderAuthority()) { now }
            .reschedule()
        assertTrue(scheduler.scheduled.isEmpty())
        assertEquals(1, scheduler.cancellations)
        assertEquals(1, sink.cancellations)
    }

    @Test
    fun tapNeedsClaimAndCurrentReadyScopeThenPerformsFreshVerification() = runTest {
        val source = Source()
        val disk = Disk()
        val authority = ReminderAuthority()
        val ticket = disk.ledger.replace(snapshot()) { true }.tickets.single()
        val model =
            ReminderController(
                source,
                disk.ledger,
                Scheduler(),
                Sink(),
                authority,
                backgroundScope,
            ) {
                ticket.fireAt
            }
        assertNull(model.resolveTap(request(ticket)))
        authority.bind(alice)
        assertNull(model.resolveTap(request(ticket)))
        disk.ledger.finish(ticket, true, ticket.fireAt) { true }
        assertNotNull(model.resolveTap(request(ticket)))
        assertEquals(1, source.verifications)
        authority.bind(alice.copy(ready = false))
        assertNull(model.resolveTap(request(ticket)))
    }

    @Test
    fun invalidTapIsRejectedBeforeAnyRead() = runTest {
        val source = Source()
        val disk = Disk()
        val model =
            ReminderController(
                source,
                disk.ledger,
                Scheduler(),
                Sink(),
                ReminderAuthority(),
                backgroundScope,
            ) {
                now
            }
        assertNull(model.resolveTap(ReminderTapRequest("../foreign", "token")))
        assertEquals(0, source.verifications)
    }

    @Test
    fun localTestTapIsTypedOnlyAfterClaimAndFreshReadyProof() = runTest {
        val source = Source()
        val disk = Disk()
        val authority = ReminderAuthority()
        authority.bind(alice)
        disk.ledger.replace(snapshot()) { true }
        val test =
            disk.ledger
                .addLocalTest(reminderOwner(alice.uid), now) { true }
                .tickets
                .single { it.localTest }
        val model =
            ReminderController(
                source,
                disk.ledger,
                Scheduler(),
                Sink(),
                authority,
                backgroundScope,
            ) {
                test.fireAt
            }
        assertNull(model.resolveTapOutcome(request(test)))
        disk.ledger.finish(test, true, test.fireAt) { true }
        assertEquals(ReminderTapOutcome.LocalTest, model.resolveTapOutcome(request(test)))
        assertEquals(1, source.verifications)
        assertNull(model.resolveTap(request(test)))
    }

    @Test
    fun failedFreshTestProofIsNotConvertedToLocalSuccess() = runTest {
        val source = Source().apply { fail = true }
        val disk = Disk()
        val authority = ReminderAuthority()
        authority.bind(alice)
        disk.ledger.replace(snapshot()) { true }
        val test =
            disk.ledger
                .addLocalTest(reminderOwner(alice.uid), now) { true }
                .tickets
                .single { it.localTest }
        disk.ledger.finish(test, true, test.fireAt) { true }
        val model =
            ReminderController(
                source,
                disk.ledger,
                Scheduler(),
                Sink(),
                authority,
                backgroundScope,
            ) {
                test.fireAt
            }
        assertNull(model.resolveTapOutcome(request(test)))
    }

    @Test
    fun actualEventTapOutcomeKeepsFreshContentNotIntentData() = runTest {
        val source = Source()
        val disk = Disk()
        val authority = ReminderAuthority()
        authority.bind(alice)
        val ticket = disk.ledger.replace(snapshot()) { true }.tickets.single()
        disk.ledger.finish(ticket, true, ticket.fireAt) { true }
        val model =
            ReminderController(
                source,
                disk.ledger,
                Scheduler(),
                Sink(),
                authority,
                backgroundScope,
            ) {
                ticket.fireAt
            }
        val outcome = model.resolveTapOutcome(request(ticket)) as ReminderTapOutcome.Event
        assertEquals(ticket.eventId, outcome.content.id)
    }

    @Test
    fun receiverWakeLeaseReleasesOnSuccessFailureAndCancellation() = runTest {
        for (mode in 0..2) {
            var acquired = 0
            var released = 0
            val lease = ReminderWakeGuard({ acquired++ }, { released++ })
            assertTrue(lease.acquire())
            val job = launch {
                runCatching {
                    finishReminderReceiver(lease) {
                        when (mode) {
                            1 -> error("synthetic")
                            2 -> delay(60_000)
                            else -> Unit
                        }
                    }
                }
            }
            runCurrent()
            if (mode == 2) job.cancel()
            job.join()
            lease.close()
            assertEquals(1, acquired)
            assertEquals(1, released)
        }
    }

    @Test
    fun receiverDeadlineReleasesCpuLeaseBeforeEightSecondLimit() = runTest {
        var released = false
        val lease = ReminderWakeGuard({}, { released = true })
        lease.acquire()
        val started = currentTime
        assertTrue(runCatching { finishReminderReceiver(lease) { delay(60_000) } }.isFailure)
        assertEquals(7_000L, currentTime - started)
        assertTrue(released)
    }

    @Test
    fun receiverAcquisitionFailureDoesNotPretendToHoldLease() {
        var released = false
        val lease = ReminderWakeGuard({ error("synthetic") }, { released = true })
        assertFalse(lease.acquire())
        lease.close()
        assertFalse(released)
    }
}
