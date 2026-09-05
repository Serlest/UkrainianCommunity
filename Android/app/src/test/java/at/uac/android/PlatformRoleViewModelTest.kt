package at.uac.android

import at.uac.android.core.LocalCallableProtocol
import at.uac.android.feature.moderation.ModerationDecisionGate
import at.uac.android.feature.moderation.ModerationException
import at.uac.android.feature.moderation.ModerationFailure
import at.uac.android.feature.moderation.ModerationSession
import at.uac.android.feature.platformrolemanagement.*
import at.uac.android.feature.usermanagement.ManagedUsersPresentation
import java.io.IOException
import java.time.Instant
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
class PlatformRoleViewModelTest {
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

    private val actor = ModerationSession("role-ui-manager", 4, "owner", true)
    private val now = Instant.parse("2026-10-24T10:00:00.123Z")
    private val first = "role-ui-first"
    private val second = "role-ui-second"
    private val secret = "PRIVATE-ROLE-REASON"
    private var live: ModerationSession? = actor

    private fun fields(id: String, status: String = "active", role: String = "user") =
        mapOf<String, Any?>(
            "id" to id,
            "displayName" to "PRIVATE Role target",
            "globalRole" to role,
            "accountStatus" to status,
            "blockState" to status,
            "warningCount" to 0L,
            "statusReason" to "  original raw reason  ",
            "updatedAt" to now,
            "privateUnshownField" to "not-in-ManagedUser",
        )

    private inner class Source : PlatformRoleSource {
        val data = mutableMapOf(first to fields(first), second to fields(second))
        val events = MutableSharedFlow<Result<Unit>>(extraBufferCapacity = 8)
        var reads = 0
        var sends = 0
        var reconciles = 0
        var readHook: (suspend (String) -> PlatformRoleSnapshot)? = null
        var sendHook: (suspend () -> Unit)? = null
        var lostReceipt = false
        var unavailable = false
        var sentReason: String? = null
        var metadataReads = 0
        var metadataHook: (suspend (String) -> PlatformRoleTargetAuth)? = null

        override suspend fun read(
            session: ModerationSession,
            targetId: String,
        ): PlatformRoleSnapshot {
            reads++
            return readHook?.invoke(targetId)
                ?: PlatformRoleRecovery.snapshot(targetId, data.getValue(targetId))
        }

        override fun changes(session: ModerationSession, targetId: String) = events.map {
            it.getOrThrow()
        }

        override suspend fun targetAuth(
            session: ModerationSession,
            targetId: String,
        ): PlatformRoleTargetAuth {
            metadataReads++
            return metadataHook?.invoke(targetId) ?: PlatformRoleTargetAuth(targetId, true, false)
        }

        override suspend fun send(
            session: ModerationSession,
            entry: PlatformRolePending,
            reason: String,
            canDispatch: () -> Boolean,
        ): PlatformRoleReceipt {
            check(canDispatch())
            sends++
            sentReason = reason
            sendHook?.invoke()
            data[entry.version.targetId] =
                data.getValue(entry.version.targetId) +
                    mapOf(
                        "globalRole" to entry.action.newRole,
                        "roleUpdatedAt" to now,
                        "roleUpdatedBy" to session.uid,
                    )
            if (lostReceipt) throw IOException("Synthetic transport loss")
            return PlatformRoleRecovery.receipt(
                entry,
                mapOf(
                    "targetUserId" to entry.version.targetId,
                    "previousGlobalRole" to entry.action.previousRole,
                    "newGlobalRole" to entry.action.newRole,
                    "updatedAt" to now.toString(),
                ),
            )
        }

        override suspend fun reconcile(
            session: ModerationSession,
            entry: PlatformRolePending,
        ): PlatformRoleObservation {
            reconciles++
            if (unavailable) return PlatformRoleObservation.CONFIRMED_UNAVAILABLE
            return PlatformRoleRecovery.observation(
                entry,
                session.uid,
                data[entry.version.targetId],
            )
        }
    }

    private class Journal : PlatformRoleJournal {
        var entries = emptyList<PlatformRolePending>()
        var unavailable = false

        override suspend fun pending(uid: String): List<PlatformRolePending> {
            if (unavailable) throw IOException("Synthetic journal failure")
            return entries.filter { it.accountHash == PlatformRoleRecovery.accountHash(uid) }
        }

        override suspend fun put(
            uid: String,
            entry: PlatformRolePending,
            expected: PlatformRolePending?,
        ): PlatformRolePending {
            val old = entries.firstOrNull {
                it.accountHash == entry.accountHash && it.version.targetId == entry.version.targetId
            }
            check(old == expected)
            entries = entries.filterNot { it == old } + entry
            return entry
        }

        override suspend fun clear(uid: String, expected: PlatformRolePending) {
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
        PlatformRoleViewModel(
            PlatformRoleRepository(source, journal, { live }, gate),
            workScope = backgroundScope,
        )

    private fun present(
        model: PlatformRoleViewModel,
        id: String? = first,
        token: ManagedUsersPresentation = ManagedUsersPresentation(),
        host: () -> Boolean = { true },
        target: () -> Boolean = { true },
    ) {
        model.bindView(live, id, token, host, target)
    }

    private fun prepared(source: Source) =
        PlatformRoleRecovery.prepared(
            actor,
            PlatformRoleRecovery.snapshot(first, source.data.getValue(first)),
            PlatformRoleAction.ASSIGN,
            secret,
            PlatformRoleTargetAuth(first, true, false),
            UUID.randomUUID().toString(),
        )

    @Test
    fun assignmentWaitsForBoundMetadataAndExecuteIndependentlyRefreshesIt() = runTest {
        val source = Source()
        val release = CompletableDeferred<Unit>()
        source.metadataHook = { id ->
            release.await()
            PlatformRoleTargetAuth(id, true, false)
        }
        val model = model(source)
        present(model)
        runCurrent()
        assertTrue(model.state.value.loading)
        assertNull(model.state.value.targetAuth)
        model.request(PlatformRoleAction.ASSIGN)
        assertNull(model.state.value.confirmation)
        release.complete(Unit)
        runCurrent()
        assertEquals(first, model.state.value.targetAuth?.targetId)
        assertEquals(1, source.metadataReads)
        model.request(PlatformRoleAction.ASSIGN)
        model.editReason(secret)
        model.confirm()
        runCurrent()
        assertEquals(2, source.metadataReads)
        assertEquals(1, source.sends)
    }

    @Test
    fun removalNeverReadsMissingAuthAndWorksForRestrictedProfile() = runTest {
        val source =
            Source().apply {
                data[first] = fields(first, status = "deactivated", role = "admin")
                metadataHook = { throw IOException("Auth is missing") }
            }
        val model = model(source)
        present(model)
        runCurrent()
        assertEquals(listOf(PlatformRoleAction.REMOVE), model.state.value.availableActions)
        assertNull(model.state.value.targetAuth)
        model.request(PlatformRoleAction.REMOVE)
        model.editReason(secret)
        assertTrue(model.state.value.canConfirm)
        // Post-operation user profile remains restricted, so refresh does not fetch Auth either.
        model.confirm()
        runCurrent()
        assertEquals(0, source.metadataReads)
        assertEquals(1, source.sends)
        assertEquals(PlatformRoleObservation.CONFIRMED_CURRENT, model.state.value.observation)
        assertEquals("deactivated", source.data.getValue(first)["accountStatus"])
    }

    @Test
    fun disabledUnverifiedForeignOrUnavailableMetadataNeverEnablesAssignment() = runTest {
        val variants =
            listOf(
                PlatformRoleTargetAuth(first, false, false),
                PlatformRoleTargetAuth(first, true, true),
                PlatformRoleTargetAuth(second, true, false),
                null,
            )
        for (value in variants) {
            val source =
                Source().apply {
                    metadataHook = { value ?: throw IOException("Synthetic metadata unavailable") }
                }
            val model = model(source)
            present(model)
            runCurrent()
            model.request(PlatformRoleAction.ASSIGN)
            model.editReason(secret)
            assertFalse(model.state.value.canConfirm)
            model.confirm()
            runCurrent()
            assertEquals(0, source.sends)
            assertTrue(model.state.value.pending.isEmpty())
            if (value == null) assertEquals(PlatformRoleFailure.OFFLINE, model.state.value.error)
            if (value?.targetId == second)
                assertEquals(PlatformRoleFailure.STALE, model.state.value.error)
        }
    }

    @Test
    fun restrictedUserHasNoAssignmentAndDoesNotFetchMetadata() = runTest {
        for (status in listOf("suspendedUntil", "banned", "deactivated", "unknown")) {
            val source = Source().apply { data[first] = fields(first, status = status) }
            val model = model(source)
            present(model)
            runCurrent()
            assertTrue(model.state.value.availableActions.isEmpty())
            model.request(PlatformRoleAction.ASSIGN)
            assertNull(model.state.value.confirmation)
            assertEquals(0, source.metadataReads)
            assertEquals(0, source.sends)
        }
    }

    @Test
    fun metadataBecomingIneligibleAfterPreviewIsVetoedBeforePendingOrSend() = runTest {
        val source = Source()
        val journal = Journal()
        val model = model(source, journal)
        present(model)
        runCurrent()
        model.request(PlatformRoleAction.ASSIGN)
        model.editReason(secret)
        assertTrue(model.state.value.canConfirm)
        source.metadataHook = { id -> PlatformRoleTargetAuth(id, false, true) }
        model.confirm()
        runCurrent()
        assertEquals(PlatformRoleFailure.STALE, model.state.value.attemptOutcome?.failure)
        assertEquals(0, source.sends)
        assertTrue(journal.entries.isEmpty())
    }

    @Test
    fun lateUncancellableMetadataCannotPublishForAnotherTargetOrRevokedHost() = runTest {
        for (changeHost in listOf(false, true)) {
            val source = Source()
            val release = CompletableDeferred<Unit>()
            source.metadataHook = { id ->
                if (id == first) withContext(NonCancellable) { release.await() }
                PlatformRoleTargetAuth(id, true, false)
            }
            val model = model(source)
            val token = ManagedUsersPresentation()
            present(model, token = token)
            runCurrent()
            if (changeHost) model.dismiss(token) else present(model, id = second, token = token)
            runCurrent()
            release.complete(Unit)
            runCurrent()
            if (changeHost) {
                assertNull(model.state.value.snapshot)
                assertNull(model.state.value.targetAuth)
                assertNull(model.state.value.targetId)
            } else {
                assertEquals(second, model.state.value.snapshot?.version?.targetId)
                assertEquals(second, model.state.value.targetAuth?.targetId)
            }
            assertEquals(0, source.sends)
        }
    }

    @Test
    fun sameTargetRefreshTicketCannotRestoreOldMetadata() = runTest {
        val source = Source()
        val release = CompletableDeferred<Unit>()
        var reads = 0
        source.metadataHook = { id ->
            reads++
            if (reads == 1) {
                withContext(NonCancellable) { release.await() }
                PlatformRoleTargetAuth(id, true, false)
            } else PlatformRoleTargetAuth(id, false, true)
        }
        val model = model(source)
        present(model)
        runCurrent()
        model.refresh()
        runCurrent()
        assertEquals(false, model.state.value.targetAuth?.emailVerified)
        release.complete(Unit)
        runCurrent()
        assertEquals(false, model.state.value.targetAuth?.emailVerified)
        model.request(PlatformRoleAction.ASSIGN)
        model.editReason(secret)
        assertFalse(model.state.value.canConfirm)
    }

    @Test
    fun nonOwnerAndNotReadyPresentationCannotReadPrivateDataOrJournal() = runTest {
        for (session in
            listOf(
                null,
                actor.copy(role = "admin"),
                actor.copy(role = "user"),
                actor.copy(ready = false),
            )) {
            live = session
            val source = Source()
            val model = model(source)
            present(model)
            runCurrent()
            assertNull(model.state.value.session)
            assertNull(model.state.value.snapshot)
            assertNull(model.state.value.targetAuth)
            assertFalse(model.state.value.journalReady)
            assertEquals(0, source.reads)
            assertEquals(0, source.metadataReads)
        }
    }

    @Test
    fun ownerRoleLossDuringMetadataClearsAllPrivateState() = runTest {
        val source = Source()
        val release = CompletableDeferred<Unit>()
        source.metadataHook = { id ->
            withContext(NonCancellable) { release.await() }
            PlatformRoleTargetAuth(id, true, false)
        }
        val model = model(source)
        present(model)
        runCurrent()
        live = actor.copy(role = "admin", revision = 99)
        model.bind(live)
        release.complete(Unit)
        runCurrent()
        assertNull(model.state.value.snapshot)
        assertNull(model.state.value.targetAuth)
        assertTrue(model.state.value.pending.isEmpty())
        assertEquals("", model.state.value.reason)
    }

    @Test
    fun watcherFailureRevokesDraftAndAuthPreviewUntilExplicitRefresh() = runTest {
        val source = Source()
        val model = model(source)
        present(model)
        runCurrent()
        model.request(PlatformRoleAction.ASSIGN)
        model.editReason(secret)
        source.events.emit(Result.failure(IOException("Synthetic listener lost")))
        runCurrent()
        assertEquals(PlatformRoleFailure.OFFLINE, model.state.value.error)
        assertNull(model.state.value.targetAuth)
        assertNull(model.state.value.snapshot)
        assertNull(model.state.value.confirmation)
        assertEquals("", model.state.value.reason)
        model.confirm()
        runCurrent()
        assertEquals(0, source.sends)
        model.refresh()
        runCurrent()
        assertTrue(model.state.value.fresh)
        assertNotNull(model.state.value.targetAuth)
        assertNull(model.state.value.error)
    }

    @Test
    fun fullJournalBlocksNewActionOnAnotherTargetWithoutDroppingPending() = runTest {
        val source = Source()
        val entries =
            (1..PlatformRoleRecovery.MAX_PENDING).map { index ->
                val id = "other-pending-$index"
                PlatformRoleRecovery.prepared(
                    actor,
                    PlatformRoleRecovery.snapshot(id, fields(id)),
                    PlatformRoleAction.ASSIGN,
                    secret,
                    PlatformRoleTargetAuth(id, true, false),
                    UUID.randomUUID().toString(),
                )
            }
        val journal = Journal().apply { this.entries = entries }
        val model = model(source, journal)
        present(model)
        runCurrent()
        assertTrue(model.state.value.journalReady)
        assertTrue(model.state.value.fresh)
        assertFalse(model.state.value.canAct)
        model.request(PlatformRoleAction.ASSIGN)
        assertNull(model.state.value.confirmation)
        assertEquals(entries, journal.entries)
        assertEquals(0, source.sends)
    }

    @Test
    fun sessionObserverRevokesOwnerPresentationOnSignOutWithoutAUiRead() = runTest {
        val sessions = kotlinx.coroutines.flow.MutableStateFlow<ModerationSession?>(actor)
        val source = Source()
        val model = model(source)
        model.observeSessions(sessions)
        runCurrent()
        present(model)
        runCurrent()
        model.request(PlatformRoleAction.ASSIGN)
        model.editReason(secret)
        live = null
        sessions.value = null
        runCurrent()
        assertNull(model.state.value.session)
        assertNull(model.state.value.snapshot)
        assertNull(model.state.value.targetAuth)
        assertNull(model.state.value.confirmation)
        assertEquals("", model.state.value.reason)
        assertTrue(model.state.value.pending.isEmpty())
        assertEquals(0, source.sends)
    }

    @Test
    fun privateMetadataAndOutcomeStringsDoNotExposeContactsOrReason() = runTest {
        val model = model()
        present(model)
        runCurrent()
        model.request(PlatformRoleAction.ASSIGN)
        model.editReason(secret)
        val current = model.state.value
        val text = listOf(current, current.targetAuth, current.snapshot).joinToString()
        for (privateText in listOf(first, actor.uid, secret, "PRIVATE Role target")) assertFalse(
            text.contains(privateText)
        )
    }

    @Test
    fun freshRawReadIsRequiredAndMerelyOpeningNeverSends() = runTest {
        val source = Source()
        val model = model(source)
        present(model)
        assertFalse(model.state.value.canAct)
        runCurrent()
        assertTrue(model.snapshot(actor).canAct)
        assertEquals("PRIVATE Role target", model.state.value.snapshot?.displayName)
        assertEquals(
            PlatformRoleRecovery.snapshot(first, source.data.getValue(first)).version,
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
        assertEquals(PlatformRoleFailure.ACCESS, model.state.value.error)
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
        assertEquals(PlatformRoleFailure.ACCESS, model.state.value.error)
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
        assertEquals(PlatformRoleFailure.OFFLINE, model.state.value.error)
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
        model.request(PlatformRoleAction.ASSIGN)
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
    fun onlyOwnerCanAssignUserOrRemoveAdminAndSelfOwnerAreNeverTargets() = runTest {
        val source = Source()
        val model = model(source)
        val token = ManagedUsersPresentation()
        present(model, token = token)
        runCurrent()
        assertEquals(listOf(PlatformRoleAction.ASSIGN), model.state.value.availableActions)
        for (role in listOf("admin", "owner", "legacy")) {
            source.data[first] = fields(first, role = role)
            source.events.emit(Result.success(Unit))
            runCurrent()
            assertEquals(
                when (role) {
                    "admin" -> listOf(PlatformRoleAction.REMOVE)
                    "owner" -> emptyList()
                    else -> listOf(PlatformRoleAction.ASSIGN)
                },
                model.state.value.availableActions,
            )
        }
        source.data[actor.uid] = fields(actor.uid)
        present(model, id = actor.uid, token = token)
        runCurrent()
        assertTrue(model.state.value.availableActions.isEmpty())
        assertEquals(0, source.sends)
    }

    @Test
    fun privateUnshownRawChangeRevokesConfirmationAndReason() = runTest {
        val source = Source()
        val model = model(source)
        present(model)
        runCurrent()
        val old = model.state.value.snapshot!!.version
        model.request(PlatformRoleAction.ASSIGN)
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
        model.request(PlatformRoleAction.ASSIGN)
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
        model.request(PlatformRoleAction.ASSIGN)
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
        model.request(PlatformRoleAction.ASSIGN)
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
        assertEquals(PlatformRoleObservation.UNCONFIRMED, model.state.value.observation)
    }

    @Test
    fun uncancellableOldTargetReadCannotPublishIntoNewTarget() = runTest {
        val source = Source()
        val release = CompletableDeferred<Unit>()
        source.readHook = { id ->
            if (id == first) withContext(NonCancellable) { release.await() }
            PlatformRoleRecovery.snapshot(id, source.data.getValue(id))
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
        model.request(PlatformRoleAction.ASSIGN)
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
    fun doubleConfirmHasOneSendAndBusyIgnoresTextAndCancel() = runTest {
        val source = Source()
        val release = CompletableDeferred<Unit>()
        source.sendHook = { release.await() }
        val model = model(source)
        present(model)
        runCurrent()
        model.request(PlatformRoleAction.ASSIGN)
        model.editReason(secret)

        model.confirm()
        model.confirm()
        runCurrent()
        assertEquals(1, source.sends)
        assertTrue(model.state.value.busy)
        model.editReason("replacement")

        model.cancelConfirmation()
        assertEquals(secret, model.state.value.reason)

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
        model.request(PlatformRoleAction.ASSIGN)
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
        assertEquals(
            PlatformRoleObservation.OBSERVED_WITHOUT_RECEIPT,
            model.state.value.observation,
        )
        assertEquals(1, model.state.value.pending.size)
        assertEquals(1, source.sends)
    }

    @Test
    fun acknowledgedUnavailableKeepsReadOnlyRecoveryAndAcceptedOutcome() = runTest {
        val source = Source().apply { unavailable = true }
        val model = model(source)
        present(model)
        runCurrent()
        model.request(PlatformRoleAction.ASSIGN)
        model.editReason(secret)
        model.confirm()
        runCurrent()
        assertEquals(PlatformRoleObservation.CONFIRMED_UNAVAILABLE, model.state.value.observation)
        assertEquals(PlatformRolePhase.ACKNOWLEDGED, model.state.value.pending.single().phase)
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
        model.request(PlatformRoleAction.ASSIGN)
        model.editReason(secret)
        model.confirm()
        runCurrent()
        live = actor.copy(uid = "role-other-owner", revision = 10)
        model.bind(live)
        assertEquals("", model.state.value.reason)
        release.complete(Unit)
        runCurrent()
        assertEquals(1, source.sends)
        assertEquals(PlatformRolePhase.ACKNOWLEDGED, journal.entries.single().phase)
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
        assertEquals(PlatformRoleFailure.JOURNAL, model.state.value.error)
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
        model.request(PlatformRoleAction.ASSIGN)
        model.editReason(secret)
        model.confirm()
        runCurrent()
        live = actor.copy(uid = "role-next-owner", revision = 40)
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
    fun privateStateToStringIsRedacted() = runTest {
        val model = model()
        present(model)
        runCurrent()
        model.request(PlatformRoleAction.ASSIGN)
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
        model.request(PlatformRoleAction.ASSIGN)
        model.editReason(secret)
        source.data[first] =
            source.data.getValue(first) + ("privateUnshownField" to "new raw version")
        model.confirm()
        runCurrent()
        assertEquals(0, source.sends)
        assertTrue(model.state.value.fresh)
        assertNull(model.state.value.error)
        assertEquals(PlatformRoleFailure.STALE, model.state.value.attemptOutcome?.failure)
        assertEquals(first, model.state.value.attemptOutcome?.targetId)
        assertNull(model.state.value.confirmation)
        assertEquals("", model.state.value.reason)
        model.refresh()
        runCurrent()
        assertEquals(PlatformRoleFailure.STALE, model.state.value.attemptOutcome?.failure)
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
        model.request(PlatformRoleAction.ASSIGN)
        model.editReason(secret)
        model.confirm()
        runCurrent()
        assertNull(model.state.value.snapshot)
        assertEquals("", model.state.value.reason)
        release.complete(Unit)
        runCurrent()
        assertEquals(
            PlatformRoleObservation.CONFIRMED_CURRENT,
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
            PlatformRoleObservation.CONFIRMED_CURRENT,
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
        model.request(PlatformRoleAction.ASSIGN)
        model.editReason(secret)
        model.confirm()
        runCurrent()
        assertNotNull(model.state.value.attemptOutcome)
        model.request(PlatformRoleAction.REMOVE)
        assertNull(model.state.value.attemptOutcome)
        model.editReason("Second explicit reason")
        model.confirm()
        runCurrent()
        assertEquals(PlatformRoleAction.REMOVE, model.state.value.attemptOutcome?.action)
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
        model.request(PlatformRoleAction.ASSIGN)
        model.editReason(secret)
        model.confirm()
        runCurrent()
        present(model, id = second, token = token, host = { active })
        runCurrent()
        assertNull(model.state.value.attemptOutcome)
        model.request(PlatformRoleAction.ASSIGN)
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
        model.request(PlatformRoleAction.ASSIGN)
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
        model.request(PlatformRoleAction.ASSIGN)
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
            PlatformRoleObservation.OBSERVED_WITHOUT_RECEIPT,
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
        model.request(PlatformRoleAction.ASSIGN)
        model.editReason(secret)
        model.confirm()
        runCurrent()
        source.readHook = { throw IOException("Synthetic later read error") }
        model.refresh()
        runCurrent()
        assertEquals(PlatformRoleFailure.OFFLINE, model.state.value.error)
        assertEquals(
            PlatformRoleObservation.CONFIRMED_CURRENT,
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
        model.request(PlatformRoleAction.ASSIGN)
        model.editReason(secret)
        assertTrue(model.state.value.canConfirm)
        model.editReason("x".repeat(PlatformRoleState.MAX_REASON_CHARACTERS + 1))
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
        assertEquals("Corrected reason", source.sentReason)
        assertEquals(1, source.sends)
        assertFalse(model.state.value.reasonRejected)
    }

    @Test
    fun reasonLimitBoundaryCancelAndLostTargetClearRejectionFlag() = runTest {
        val model = model()
        var current = true
        present(model, target = { current })
        runCurrent()
        model.request(PlatformRoleAction.ASSIGN)
        model.editReason("x".repeat(PlatformRoleState.MAX_REASON_CHARACTERS))
        // The editor accepts this many UTF-16 units, but the wire limit includes JSON overhead.
        assertEquals(PlatformRoleState.MAX_REASON_CHARACTERS, model.state.value.reason.length)
        assertFalse(model.state.value.reasonRejected)
        assertFalse(model.state.value.canConfirm)
        model.editReason("x".repeat(PlatformRoleState.MAX_REASON_CHARACTERS + 1))
        assertTrue(model.state.value.reasonRejected)
        model.cancelConfirmation()
        assertFalse(model.state.value.reasonRejected)
        assertEquals("", model.state.value.reason)
        model.request(PlatformRoleAction.ASSIGN)
        model.editReason("x".repeat(PlatformRoleState.MAX_REASON_CHARACTERS + 1))
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
            model.request(PlatformRoleAction.ASSIGN)
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
            assertEquals(exact, source.sentReason)
            assertEquals(PlatformRoleObservation.CONFIRMED_CURRENT, model.state.value.observation)
        }
    }

    @Test
    fun attemptOutcomeRequiresOneTypedResultAndRedactsRoutingIdentity() {
        assertTrue(
            runCatching { PlatformRoleAttemptOutcome(first, PlatformRoleAction.ASSIGN) }.isFailure
        )
        assertTrue(
            runCatching {
                PlatformRoleAttemptOutcome(
                    first,
                    PlatformRoleAction.ASSIGN,
                    observation = PlatformRoleObservation.CONFIRMED_CURRENT,
                    failure = PlatformRoleFailure.OFFLINE,
                )
            }
                .isFailure
        )
        val outcome =
            PlatformRoleAttemptOutcome(
                first,
                PlatformRoleAction.ASSIGN,
                failure = PlatformRoleFailure.STALE,
            )
        assertFalse(outcome.toString().contains(first))
        assertFalse(outcome.toString().contains(secret))
    }
}
