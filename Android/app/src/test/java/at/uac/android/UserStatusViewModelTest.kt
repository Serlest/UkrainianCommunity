package at.uac.android

import at.uac.android.core.LocalCallableProtocol
import at.uac.android.feature.moderation.ModerationDecisionGate
import at.uac.android.feature.moderation.ModerationException
import at.uac.android.feature.moderation.ModerationFailure
import at.uac.android.feature.moderation.ModerationSession
import at.uac.android.feature.usermanagement.ManagedUsersPresentation
import at.uac.android.feature.userstatusmanagement.*
import java.io.IOException
import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Test

/** Injected source/gate tests of presentation ownership, not SDK/TOTP authorization evidence. */
@OptIn(ExperimentalCoroutinesApi::class)
class UserStatusViewModelTest {
    @Test
    fun freshReadOfIdenticalRawDataIsANewPresentationObservation() = runTest {
        val model = model()
        present(model)
        runCurrent()
        val firstRead = model.state.value
        assertTrue(firstRead.fresh)
        model.refresh()
        runCurrent()
        val secondRead = model.state.value
        assertTrue(secondRead.fresh)
        assertEquals(firstRead.snapshot?.version, secondRead.snapshot?.version)
        assertTrue(secondRead.readRevision > firstRead.readRevision)
        assertEquals(firstRead.copy(readRevision = secondRead.readRevision), secondRead)
        assertNotEquals(
            "A completed reread must not disappear through StateFlow conflation",
            firstRead,
            secondRead,
        )
    }

    private val actor = ModerationSession("status-ui-manager", 4, "admin", true)
    private val now = Instant.parse("2026-10-24T10:00:00.123Z")
    private val first = "status-ui-first"
    private val second = "status-ui-second"
    private val secret = "PRIVATE-STATUS-REASON"
    private var live: ModerationSession? = actor

    private fun fields(id: String, status: String = "active", role: String = "user") =
        mapOf<String, Any?>(
            "id" to id,
            "globalRole" to role,
            "accountStatus" to status,
            "blockState" to status,
            "warningCount" to 0L,
            "statusReason" to "  original raw reason  ",
            "updatedAt" to now,
            "privateUnshownField" to "not-in-ManagedUser",
        )

    private inner class Source : UserStatusSource {
        val data = mutableMapOf(first to fields(first), second to fields(second))
        val events = MutableSharedFlow<Result<Unit>>(extraBufferCapacity = 8)
        var reads = 0
        var sends = 0
        var reconciles = 0
        var readHook: (suspend (String) -> UserStatusSnapshot)? = null
        var sendHook: (suspend () -> Unit)? = null
        var lostReceipt = false
        var unavailable = false
        var sentUntil: Instant? = null

        override suspend fun read(
            session: ModerationSession,
            targetId: String,
        ): UserStatusSnapshot {
            reads++
            return readHook?.invoke(targetId)
                ?: UserStatusContract.snapshot(targetId, data.getValue(targetId))
        }

        override fun changes(session: ModerationSession, targetId: String) = events.map {
            it.getOrThrow()
        }

        override suspend fun send(
            session: ModerationSession,
            entry: UserStatusPending,
            reason: String,
            until: Instant?,
            canDispatch: () -> Boolean,
        ): UserStatusReceipt {
            check(canDispatch())
            sends++
            sentUntil = until
            sendHook?.invoke()
            val before =
                UserStatusContract.snapshot(
                    entry.version.targetId,
                    data.getValue(entry.version.targetId),
                )
            val count = before.warningCount + if (entry.action == UserStatusAction.WARN) 1 else 0
            data[entry.version.targetId] =
                data.getValue(entry.version.targetId) +
                    mapOf(
                        "accountStatus" to entry.action.status,
                        "blockState" to entry.action.status,
                        "warningCount" to count,
                        "banExpiresAt" to until,
                        "isBlocked" to entry.action.blocked,
                        "statusReason" to reason,
                        "statusMessage" to entry.action.messagePrefix + reason,
                        "statusUpdatedAt" to now,
                        "updatedAt" to now,
                        "statusUpdatedBy" to session.uid,
                        "statusAcknowledgedAt" to null,
                    )
            if (lostReceipt) throw IOException("Synthetic transport loss")
            return UserStatusContract.receipt(
                entry,
                mapOf(
                    "targetUserId" to entry.version.targetId,
                    "previousAccountStatus" to before.accountStatus,
                    "newAccountStatus" to entry.action.status,
                    "previousBlockState" to before.blockState,
                    "newBlockState" to entry.action.status,
                    "warningCount" to count,
                    "banExpiresAt" to until?.toString(),
                    "updatedAt" to now.toString(),
                ),
            )
        }

        override suspend fun reconcile(
            session: ModerationSession,
            entry: UserStatusPending,
        ): UserStatusObservation {
            reconciles++
            if (unavailable) return UserStatusObservation.CONFIRMED_UNAVAILABLE
            return UserStatusContract.observation(entry, session.uid, data[entry.version.targetId])
        }
    }

    private class Journal : UserStatusJournal {
        var entries = emptyList<UserStatusPending>()
        var unavailable = false

        override suspend fun pending(uid: String): List<UserStatusPending> {
            if (unavailable) throw IOException("Synthetic journal failure")
            return entries.filter { it.accountHash == UserStatusContract.accountHash(uid) }
        }

        override suspend fun put(
            uid: String,
            entry: UserStatusPending,
            expected: UserStatusPending?,
        ): UserStatusPending {
            val old = entries.firstOrNull {
                it.accountHash == entry.accountHash && it.version.targetId == entry.version.targetId
            }
            check(old == expected)
            entries = entries.filterNot { it == old } + entry
            return entry
        }

        override suspend fun clear(uid: String, expected: UserStatusPending) {
            check(expected in entries)
            entries = entries - expected
        }
    }

    private val gate =
        object : ModerationDecisionGate {
            override suspend fun <T> withSession(
                session: ModerationSession,
                action: suspend () -> T,
            ): T = action()
        }

    private fun TestScope.model(source: Source = Source(), journal: Journal = Journal()) =
        UserStatusViewModel(
            UserStatusRepository(source, journal, { live }, gate, { now }),
            workScope = backgroundScope,
            clock = { now },
        )

    private fun present(
        model: UserStatusViewModel,
        id: String? = first,
        token: ManagedUsersPresentation = ManagedUsersPresentation(),
        host: () -> Boolean = { true },
        target: () -> Boolean = { true },
    ) {
        model.bindView(live, id, token, host, target)
    }

    private fun prepared(source: Source) =
        UserStatusContract.prepared(
            actor,
            UserStatusContract.snapshot(first, source.data.getValue(first)),
            UserStatusAction.WARN,
            secret,
            null,
            UUID.randomUUID().toString(),
        )

    @Test
    fun freshRawReadIsRequiredAndMerelyOpeningNeverSends() = runTest {
        val source = Source()
        val model = model(source)
        present(model)
        assertFalse(model.state.value.canAct)
        runCurrent()
        assertTrue(model.snapshot(actor).canAct)
        assertEquals("  original raw reason  ", model.state.value.snapshot?.statusReason)
        assertEquals(
            UserStatusContract.snapshot(first, source.data.getValue(first)).version,
            model.state.value.snapshot?.version,
        )
        assertEquals(0, source.sends)
    }

    @Test
    fun actualModerationDenialReadShowsAccessNotUnknownOperation() = runTest {
        val source =
            Source().apply {
                readHook = { throw ModerationException(ModerationFailure.DENIED) }
            }
        val model = model(source)
        present(model)
        runCurrent()
        assertEquals(UserStatusFailure.ACCESS, model.state.value.error)
        assertFalse(model.state.value.loading)
        assertFalse(model.state.value.canAct)
        assertNull(model.state.value.snapshot)
        assertTrue(model.state.value.pending.isEmpty())
        assertEquals(0, source.sends)
    }

    @Test
    fun actualModerationNotReadyReadShowsAccessNotUnknownOperation() = runTest {
        val source =
            Source().apply {
                readHook = { throw ModerationException(ModerationFailure.NOT_READY) }
            }
        val model = model(source)
        present(model)
        runCurrent()
        assertEquals(UserStatusFailure.ACCESS, model.state.value.error)
        assertFalse(model.state.value.loading)
        assertFalse(model.state.value.canAct)
        assertNull(model.state.value.snapshot)
        assertTrue(model.state.value.pending.isEmpty())
        assertEquals(0, source.sends)
    }

    @Test
    fun actualIOExceptionReadShowsOfflineWithoutPendingMutation() = runTest {
        val source = Source().apply { readHook = { throw IOException("Synthetic read failure") } }
        val model = model(source)
        present(model)
        runCurrent()
        assertEquals(UserStatusFailure.OFFLINE, model.state.value.error)
        assertFalse(model.state.value.loading)
        assertFalse(model.state.value.canAct)
        assertNull(model.state.value.snapshot)
        assertTrue(model.state.value.pending.isEmpty())
        assertEquals(0, source.sends)
    }

    @Test
    fun readCancellationIsNotSwallowedIntoAccessOfflineOrUnknownError() = runTest {
        val source =
            Source().apply { readHook = { throw CancellationException("Synthetic canceled read") } }
        val model = model(source)
        val token = ManagedUsersPresentation()
        present(model, token = token)
        runCurrent()
        assertNull(model.state.value.error)
        assertNull(model.state.value.snapshot)
        assertFalse(model.state.value.canAct)
        assertTrue(model.state.value.pending.isEmpty())
        model.dismiss(token)
        assertFalse(model.state.value.loading)
        assertNull(model.state.value.error)
        assertEquals(0, source.sends)
    }

    @Test
    fun requiredReasonAndCancelNeverSend() = runTest {
        val source = Source()
        val model = model(source)
        present(model)
        runCurrent()
        model.request(UserStatusAction.WARN)
        assertFalse(model.state.value.canConfirm)
        model.editReason("\u00a0\u2003")
        assertFalse(model.state.value.canConfirm)
        model.editReason(secret)
        assertTrue(model.state.value.canConfirm)
        model.cancelConfirmation()
        assertNull(model.state.value.confirmation)
        assertEquals("", model.state.value.reason)
        assertEquals(0, source.sends)
    }

    @Test
    fun iOSActionsAndTargetGuardsAreNotExpandedByUI() = runTest {
        val source = Source().apply { data[first] = fields(first, "suspendedUntil") }
        val model = model(source)
        present(model)
        runCurrent()
        assertEquals(
            listOf(UserStatusAction.RESTORE, UserStatusAction.BAN, UserStatusAction.DEACTIVATE),
            model.state.value.availableActions,
        )
        model.request(UserStatusAction.WARN)
        assertNull(model.state.value.confirmation)
        source.data[first] = fields(first, role = "admin")
        source.events.emit(Result.success(Unit))
        runCurrent()
        assertTrue(model.state.value.availableActions.isEmpty())
        model.request(UserStatusAction.RESTORE)
        assertNull(model.state.value.confirmation)
        assertEquals(0, source.sends)
    }

    @Test
    fun privateUnshownRawChangeRevokesConfirmationAndReason() = runTest {
        val source = Source()
        val model = model(source)
        present(model)
        runCurrent()
        val old = model.state.value.snapshot!!.version
        model.request(UserStatusAction.WARN)
        model.editReason(secret)
        source.data[first] = source.data.getValue(first) + ("privateUnshownField" to "changed")
        source.events.emit(Result.success(Unit))
        runCurrent()
        assertNull(model.state.value.confirmation)
        assertEquals("", model.state.value.reason)
        assertNotEquals(old, model.state.value.snapshot!!.version)
        model.confirm()
        runCurrent()
        assertEquals(0, source.sends)
    }

    @Test
    fun staleRawWithoutListenerStillFailsRepositoryPreflight() = runTest {
        val source = Source()
        val model = model(source)
        present(model)
        runCurrent()
        model.request(UserStatusAction.WARN)
        model.editReason(secret)
        source.data[first] = source.data.getValue(first) + ("privateUnshownField" to "changed")
        model.confirm()
        runCurrent()
        assertEquals(0, source.sends)
        assertNull(model.state.value.confirmation)
        assertEquals("", model.state.value.reason)
    }

    @Test
    fun oldRenderedTargetGuardIsSampledBeforeNewGuardAndEpoch() = runTest {
        val model = model()
        val token = ManagedUsersPresentation()
        var rendered = Any()
        val old = rendered
        present(model, token = token, target = { rendered === old })
        runCurrent()
        model.request(UserStatusAction.WARN)
        model.editReason(secret)
        rendered = Any()
        val fresh = rendered
        present(model, token = token, target = { rendered === fresh })
        assertNull(model.state.value.confirmation)
        assertEquals("", model.state.value.reason)
        assertFalse(model.state.value.fresh)
        runCurrent()
        assertTrue(model.state.value.fresh)
    }

    @Test
    fun privacyVetoClearsPrivateStateAndSameLeaseCannotRebound() = runTest {
        val source = Source()
        val journal = Journal().apply { entries = listOf(prepared(source)) }
        val model = model(source, journal)
        val token = ManagedUsersPresentation()
        var allowed = true
        present(model, token = token, host = { allowed })
        runCurrent()
        assertEquals(1, model.state.value.pending.size)
        allowed = false
        assertNull(model.snapshot(actor).snapshot)
        assertTrue(model.state.value.pending.isEmpty())
        assertNull(model.state.value.targetId)
        allowed = true
        present(model, token = token, host = { allowed })
        runCurrent()
        assertNull(model.snapshot(actor).snapshot)
        present(model, host = { allowed })
        runCurrent()
        assertNotNull(model.snapshot(actor).snapshot)
    }

    @Test
    fun targetBackClearsDraftButPendingRemainsOnLiveHost() = runTest {
        val source = Source()
        val journal = Journal().apply { entries = listOf(prepared(source)) }
        val model = model(source, journal)
        val token = ManagedUsersPresentation()
        present(model, id = second, token = token)
        runCurrent()
        model.request(UserStatusAction.WARN)
        model.editReason(secret)
        present(model, id = null, token = token)
        runCurrent()
        assertNull(model.state.value.snapshot)
        assertEquals("", model.state.value.reason)
        assertEquals(1, model.state.value.pending.size)
        model.reconcile(model.state.value.pending.single())
        runCurrent()
        assertEquals(0, source.sends)
        assertEquals(1, source.reconciles)
        assertEquals(UserStatusObservation.UNCONFIRMED, model.state.value.observation)
    }

    @Test
    fun uncancellableOldTargetReadCannotPublishIntoNewTarget() = runTest {
        val source = Source()
        val release = CompletableDeferred<Unit>()
        source.readHook = { id ->
            if (id == first) withContext(NonCancellable) { release.await() }
            UserStatusContract.snapshot(id, source.data.getValue(id))
        }
        val model = model(source)
        val token = ManagedUsersPresentation()
        present(model, token = token)
        runCurrent()
        present(model, id = second, token = token)
        runCurrent()
        assertEquals(second, model.state.value.snapshot?.version?.targetId)
        release.complete(Unit)
        runCurrent()
        assertEquals(second, model.state.value.snapshot?.version?.targetId)
    }

    @Test
    fun sessionRevisionChangeClearsReasonAndLateRead() = runTest {
        val source = Source()
        val model = model(source)
        present(model)
        runCurrent()
        model.request(UserStatusAction.WARN)
        model.editReason(secret)
        live = actor.copy(revision = actor.revision + 1)
        assertNull(model.snapshot(actor).snapshot)
        assertEquals("", model.state.value.reason)
        assertTrue(model.state.value.pending.isEmpty())
        model.bind(live)
        assertNull(model.state.value.snapshot)
        assertEquals(0, source.sends)
    }

    @Test
    fun doubleConfirmHasOneSendAndBusyIgnoresTextDaysCancel() = runTest {
        val source = Source()
        val release = CompletableDeferred<Unit>()
        source.sendHook = { release.await() }
        val model = model(source)
        present(model)
        runCurrent()
        model.request(UserStatusAction.SUSPEND)
        model.editReason(secret)
        model.chooseDays(14)
        model.confirm()
        model.confirm()
        runCurrent()
        assertEquals(1, source.sends)
        assertTrue(model.state.value.busy)
        model.editReason("replacement")
        model.chooseDays(30)
        model.cancelConfirmation()
        assertEquals(secret, model.state.value.reason)
        assertEquals(14, model.state.value.suspensionDays)
        release.complete(Unit)
        runCurrent()
        assertEquals(1, source.sends)
        assertFalse(model.state.value.busy)
        assertEquals("", model.state.value.reason)
        assertEquals(1L, model.state.value.completion)
    }

    @Test
    fun lostReceiptAllowsOnlyReadOnlyReconcileNotAutoResend() = runTest {
        val source = Source().apply { lostReceipt = true }
        val model = model(source)
        present(model)
        runCurrent()
        model.request(UserStatusAction.WARN)
        model.editReason(secret)
        model.confirm()
        runCurrent()
        assertEquals(1, source.sends)
        assertEquals(1, model.state.value.pending.size)
        assertFalse(model.state.value.canAct)
        assertNull(model.state.value.confirmation)
        assertEquals("", model.state.value.reason)
        model.confirm()
        model.refresh()
        runCurrent()
        model.reconcile(model.state.value.pending.single())
        runCurrent()
        assertEquals(UserStatusObservation.OBSERVED_WITHOUT_RECEIPT, model.state.value.observation)
        assertEquals(1, model.state.value.pending.size)
        assertEquals(1, source.sends)
    }

    @Test
    fun acknowledgedUnavailableKeepsReadOnlyRecoveryAndAcceptedOutcome() = runTest {
        val source = Source().apply { unavailable = true }
        val model = model(source)
        present(model)
        runCurrent()
        model.request(UserStatusAction.WARN)
        model.editReason(secret)
        model.confirm()
        runCurrent()
        assertEquals(UserStatusObservation.CONFIRMED_UNAVAILABLE, model.state.value.observation)
        assertEquals(UserStatusPhase.ACKNOWLEDGED, model.state.value.pending.single().phase)
        assertFalse(model.state.value.canAct)
        assertEquals(1, source.sends)
    }

    @Test
    fun actorChangeDuringSubmittedTaskRetainsReceiptWithoutOldUiResult() = runTest {
        val source = Source()
        val journal = Journal()
        val release = CompletableDeferred<Unit>()
        source.sendHook = { release.await() }
        val model = model(source, journal)
        present(model)
        runCurrent()
        model.request(UserStatusAction.WARN)
        model.editReason(secret)
        model.confirm()
        runCurrent()
        live = actor.copy(uid = "status-other-manager", revision = 10)
        model.bind(live)
        assertEquals("", model.state.value.reason)
        release.complete(Unit)
        runCurrent()
        assertEquals(1, source.sends)
        assertEquals(UserStatusPhase.ACKNOWLEDGED, journal.entries.single().phase)
        assertNull(model.state.value.observation)
        assertTrue(model.state.value.pending.isEmpty())
        assertEquals(0L, model.state.value.completion)
    }

    @Test
    fun brokenJournalFailsClosedAndExplicitReadRetryRecovers() = runTest {
        val journal = Journal().apply { unavailable = true }
        val model = model(journal = journal)
        present(model)
        runCurrent()
        assertFalse(model.state.value.canAct)
        assertEquals(UserStatusFailure.JOURNAL, model.state.value.error)
        journal.unavailable = false
        model.refreshPending()
        runCurrent()
        assertTrue(model.state.value.canAct)
    }

    @Test
    fun settledOldAccountOperationDoesNotLeaveNewHostPermanentlyBusy() = runTest {
        val source = Source()
        val release = CompletableDeferred<Unit>()
        source.sendHook = { release.await() }
        val model = model(source)
        present(model)
        runCurrent()
        model.request(UserStatusAction.WARN)
        model.editReason(secret)
        model.confirm()
        runCurrent()
        live = actor.copy(uid = "status-next-manager", revision = 40)
        model.bind(live)
        release.complete(Unit)
        runCurrent()
        assertFalse(model.state.value.busy)
        present(model, id = second)
        runCurrent()
        assertTrue(model.state.value.canAct)
        assertTrue(model.state.value.pending.isEmpty())
        assertEquals("", model.state.value.reason)
        assertEquals(1, source.sends)
    }

    @Test
    fun calendarChoiceDefaultsSevenRejectsOtherDaysAndUsesCapturedZone() = runTest {
        val source = Source()
        val model = model(source)
        present(model)
        runCurrent()
        model.request(UserStatusAction.SUSPEND)
        assertEquals(7, model.state.value.suspensionDays)
        val zone = model.state.value.suspensionZoneId
        model.chooseDays(365)
        assertEquals(7, model.state.value.suspensionDays)
        model.chooseDays(1)
        model.editReason(secret)
        model.confirm()
        runCurrent()
        assertEquals(UserStatusContract.suspensionUntil(now, 1, zone), source.sentUntil)
        val vienna = ZoneId.of("Europe/Vienna")
        assertEquals(
            25 * 3600L,
            UserStatusContract.suspensionUntil(now, 1, vienna).epochSecond - now.epochSecond,
        )
    }

    @Test
    fun privateStateToStringIsRedacted() = runTest {
        val model = model()
        present(model)
        runCurrent()
        model.request(UserStatusAction.WARN)
        model.editReason(secret)
        val text = model.state.value.toString()
        assertFalse(text.contains(secret))
        assertFalse(text.contains(first))
        assertFalse(text.contains(actor.uid))
    }

    @Test
    fun preflightFailureSurvivesItsSuccessfulInternalReadRefresh() = runTest {
        val source = Source()
        val model = model(source)
        present(model)
        runCurrent()
        model.request(UserStatusAction.WARN)
        model.editReason(secret)
        source.data[first] =
            source.data.getValue(first) + ("privateUnshownField" to "new raw version")
        model.confirm()
        runCurrent()
        assertEquals(0, source.sends)
        assertTrue(model.state.value.fresh)
        assertNull(model.state.value.error)
        assertEquals(UserStatusFailure.STALE, model.state.value.attemptOutcome?.failure)
        assertEquals(first, model.state.value.attemptOutcome?.targetId)
        assertNull(model.state.value.confirmation)
        assertEquals("", model.state.value.reason)
        model.refresh()
        runCurrent()
        assertEquals(UserStatusFailure.STALE, model.state.value.attemptOutcome?.failure)
    }

    @Test
    fun ownReceiptSurvivesPreviewInvalidationAndParentNullToSameRefresh() = runTest {
        val source = Source()
        val model = model(source)
        val token = ManagedUsersPresentation()
        var targetCurrent = true
        val release = CompletableDeferred<Unit>()
        present(model, token = token, target = { targetCurrent })
        runCurrent()
        source.sendHook = {
            targetCurrent = false
            model.snapshot(actor)
            release.await()
        }
        model.request(UserStatusAction.WARN)
        model.editReason(secret)
        model.confirm()
        runCurrent()
        assertNull(model.state.value.snapshot)
        assertEquals("", model.state.value.reason)
        release.complete(Unit)
        runCurrent()
        assertEquals(
            UserStatusObservation.CONFIRMED_CURRENT,
            model.state.value.attemptOutcome?.observation,
        )
        assertEquals(first, model.state.value.attemptOutcome?.targetId)
        assertNull(model.state.value.snapshot)
        present(model, id = null, token = token)
        runCurrent()
        targetCurrent = true
        present(model, token = token, target = { targetCurrent })
        runCurrent()
        assertEquals(first, model.state.value.snapshot?.version?.targetId)
        assertEquals(
            UserStatusObservation.CONFIRMED_CURRENT,
            model.state.value.attemptOutcome?.observation,
        )
        assertEquals(1L, model.state.value.completion)
        assertEquals(1, source.sends)
        assertEquals("", model.state.value.reason)
    }

    @Test
    fun nextExplicitActionAndOutcomeDismissDoNotReplayPreviousAttempt() = runTest {
        val source = Source()
        val model = model(source)
        present(model)
        runCurrent()
        model.request(UserStatusAction.WARN)
        model.editReason(secret)
        model.confirm()
        runCurrent()
        assertNotNull(model.state.value.attemptOutcome)
        model.request(UserStatusAction.BAN)
        assertNull(model.state.value.attemptOutcome)
        model.editReason("Second explicit reason")
        model.confirm()
        runCurrent()
        assertEquals(UserStatusAction.BAN, model.state.value.attemptOutcome?.action)
        model.dismissOutcome()
        model.refresh()
        model.refreshPending()
        runCurrent()
        assertNull(model.state.value.attemptOutcome)
        assertEquals(2, source.sends)
        assertEquals("", model.state.value.reason)
    }

    @Test
    fun newTargetClearsOutcomeAndPrivacyRevocationCannotRestoreIt() = runTest {
        val source = Source()
        val model = model(source)
        val token = ManagedUsersPresentation()
        var active = true
        present(model, token = token, host = { active })
        runCurrent()
        model.request(UserStatusAction.WARN)
        model.editReason(secret)
        model.confirm()
        runCurrent()
        present(model, id = second, token = token, host = { active })
        runCurrent()
        assertNull(model.state.value.attemptOutcome)
        model.request(UserStatusAction.WARN)
        model.editReason(secret)
        model.confirm()
        runCurrent()
        assertEquals(second, model.state.value.attemptOutcome?.targetId)
        active = false
        model.snapshot(actor)
        assertNull(model.state.value.attemptOutcome)
        active = true
        present(model, id = second, token = token, host = { active })
        runCurrent()
        assertNull(model.snapshot(actor).attemptOutcome)
        present(model, id = second, host = { active })
        runCurrent()
        assertNull(model.state.value.attemptOutcome)
        assertEquals(2, source.sends)
    }

    @Test
    fun oldAttemptCannotPublishAfterARealDifferentTargetSelection() = runTest {
        val source = Source()
        val release = CompletableDeferred<Unit>()
        source.sendHook = { release.await() }
        val model = model(source)
        val token = ManagedUsersPresentation()
        present(model, token = token)
        runCurrent()
        model.request(UserStatusAction.WARN)
        model.editReason(secret)
        model.confirm()
        runCurrent()
        present(model, id = second, token = token)
        runCurrent()
        release.complete(Unit)
        runCurrent()
        assertEquals(second, model.state.value.snapshot?.version?.targetId)
        assertNull(model.state.value.attemptOutcome)
        assertEquals("", model.state.value.reason)
        assertEquals(1, source.sends)
    }

    @Test
    fun readOnlyPendingReconcileKeepsExplicitTargetWithoutReplacingOtherProfile() = runTest {
        val source = Source().apply { lostReceipt = true }
        val model = model(source)
        val token = ManagedUsersPresentation()
        present(model, token = token)
        runCurrent()
        model.request(UserStatusAction.WARN)
        model.editReason(secret)
        model.confirm()
        runCurrent()
        val entry = model.state.value.pending.single()
        present(model, id = second, token = token)
        runCurrent()
        model.reconcile(entry)
        runCurrent()
        present(model, id = second, token = token)
        runCurrent()
        assertEquals(
            UserStatusObservation.OBSERVED_WITHOUT_RECEIPT,
            model.state.value.attemptOutcome?.observation,
        )
        assertEquals(first, model.state.value.attemptOutcome?.targetId)
        assertEquals(second, model.state.value.snapshot?.version?.targetId)
        assertEquals(1, source.sends)
    }

    @Test
    fun laterRawReadFailureDoesNotReplaceAcceptedAttemptOutcome() = runTest {
        val source = Source()
        val model = model(source)
        present(model)
        runCurrent()
        model.request(UserStatusAction.WARN)
        model.editReason(secret)
        model.confirm()
        runCurrent()
        source.readHook = { throw IOException("Synthetic later read error") }
        model.refresh()
        runCurrent()
        assertEquals(UserStatusFailure.OFFLINE, model.state.value.error)
        assertEquals(
            UserStatusObservation.CONFIRMED_CURRENT,
            model.state.value.attemptOutcome?.observation,
        )
        assertNull(model.state.value.snapshot)
        assertEquals(1, source.sends)
    }

    @Test
    fun oversizePasteBlocksOldReasonUntilValidReplacementAndNeverSendsOldText() = runTest {
        val source = Source()
        val model = model(source)
        present(model)
        runCurrent()
        model.request(UserStatusAction.WARN)
        model.editReason(secret)
        assertTrue(model.state.value.canConfirm)
        model.editReason("x".repeat(UserStatusState.MAX_REASON_CHARACTERS + 1))
        assertEquals(secret, model.state.value.reason)
        assertTrue(model.state.value.reasonRejected)
        assertFalse(model.state.value.canConfirm)
        model.confirm()
        runCurrent()
        assertEquals(0, source.sends)
        model.editReason("Corrected reason")
        assertFalse(model.state.value.reasonRejected)
        assertTrue(model.state.value.canConfirm)
        model.confirm()
        runCurrent()
        assertEquals("Corrected reason", source.data.getValue(first)["statusReason"])
        assertEquals(1, source.sends)
        assertFalse(model.state.value.reasonRejected)
    }

    @Test
    fun reasonLimitBoundaryCancelAndLostTargetClearRejectionFlag() = runTest {
        val model = model()
        var current = true
        present(model, target = { current })
        runCurrent()
        model.request(UserStatusAction.WARN)
        model.editReason("x".repeat(UserStatusState.MAX_REASON_CHARACTERS))
        // The editor accepts this many UTF-16 units, but the wire limit includes JSON overhead.
        assertEquals(UserStatusState.MAX_REASON_CHARACTERS, model.state.value.reason.length)
        assertFalse(model.state.value.reasonRejected)
        assertFalse(model.state.value.canConfirm)
        model.editReason("x".repeat(UserStatusState.MAX_REASON_CHARACTERS + 1))
        assertTrue(model.state.value.reasonRejected)
        model.cancelConfirmation()
        assertFalse(model.state.value.reasonRejected)
        assertEquals("", model.state.value.reason)
        model.request(UserStatusAction.WARN)
        model.editReason("x".repeat(UserStatusState.MAX_REASON_CHARACTERS + 1))
        current = false
        model.snapshot(actor)
        assertFalse(model.state.value.reasonRejected)
        assertEquals("", model.state.value.reason)
        assertNull(model.state.value.confirmation)
    }

    @Test
    fun exactWireBudgetIncludesEnvelopeUtf8AndEscapesAndRejectsBeforeSend() = runTest {
        val envelopeBytes =
            "{\"data\":{\"targetUserId\":\"$first\",\"reason\":\"\"}}"
                .toByteArray(Charsets.UTF_8)
                .size
        val reasonBytes = LocalCallableProtocol.MAX_REQUEST_BYTES - envelopeBytes
        // Exact serialized costs, not String.length: ASCII, Cyrillic, emoji and JSON escapes.
        for ((unit, bytes) in listOf("x" to 1, "Ж" to 2, "😀" to 4, "\"" to 2, "\\" to 2)) {
            val source = Source()
            val model = model(source)
            present(model)
            runCurrent()
            model.request(UserStatusAction.WARN)
            val exact = unit.repeat(reasonBytes / bytes) + "x".repeat(reasonBytes % bytes)
            model.editReason(exact)
            assertEquals(exact, model.state.value.reason)
            assertFalse(model.state.value.reasonRejected)
            assertTrue(
                "Exactly fitting serialized payload must remain valid",
                model.state.value.canConfirm,
            )
            model.editReason(exact + "x")
            assertFalse(model.state.value.reasonRejected)
            assertFalse(
                "One excess wire byte must block confirmation",
                model.state.value.canConfirm,
            )
            model.confirm()
            runCurrent()
            assertEquals(0, source.sends)
            assertTrue(model.state.value.pending.isEmpty())
            model.editReason(exact)
            model.confirm()
            runCurrent()
            assertEquals(1, source.sends)
            assertEquals(exact, source.data.getValue(first)["statusReason"])
            assertEquals(UserStatusObservation.CONFIRMED_CURRENT, model.state.value.observation)
        }
    }

    @Test
    fun attemptOutcomeRequiresOneTypedResultAndRedactsRoutingIdentity() {
        assertTrue(runCatching { UserStatusAttemptOutcome(first, UserStatusAction.WARN) }.isFailure)
        assertTrue(
            runCatching {
                UserStatusAttemptOutcome(
                    first,
                    UserStatusAction.WARN,
                    observation = UserStatusObservation.CONFIRMED_CURRENT,
                    failure = UserStatusFailure.OFFLINE,
                )
            }
                .isFailure
        )
        val outcome =
            UserStatusAttemptOutcome(
                first,
                UserStatusAction.WARN,
                failure = UserStatusFailure.STALE,
            )
        assertFalse(outcome.toString().contains(first))
        assertFalse(outcome.toString().contains(secret))
    }
}
