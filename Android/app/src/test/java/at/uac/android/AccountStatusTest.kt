package at.uac.android

import at.uac.android.feature.accountstatus.*
import com.google.firebase.Timestamp
import java.time.Instant
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.*
import kotlinx.coroutines.withContext
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class AccountStatusTest {
    private val dispatcher = StandardTestDispatcher()
    private val time = Instant.parse("2026-09-03T05:00:00.123456789Z")

    private fun version(status: String = "warned", block: String = "active") =
        AccountStatusVersion(
            "status-user",
            status,
            block,
            time,
            " raw reason ",
            " raw message ",
            time.plusSeconds(60),
        )

    private fun session(v: AccountStatusVersion = version()) =
        AccountStatusSession(v.uid, 4, AccountStatusObservation(v, null), true, true)

    private fun fields(v: AccountStatusVersion = version()): Map<String, Any?> =
        mapOf(
            "id" to v.uid,
            "accountStatus" to v.status,
            "blockState" to v.blockState,
            "statusUpdatedAt" to Timestamp(v.updatedAt.epochSecond, v.updatedAt.nano),
            "statusAcknowledgedAt" to null,
            "statusReason" to v.reason,
            "statusMessage" to v.message,
            "banExpiresAt" to v.expiresAt?.let { Timestamp(it.epochSecond, it.nano) },
            "globalRole" to "user",
            "requiresMultiFactorAuth" to false,
        )

    @Before
    fun setup() {
        Dispatchers.setMain(dispatcher)
    }

    @After
    fun cleanup() {
        Dispatchers.resetMain()
    }

    @Test
    fun allCasesAndLegacyStatusAliasesAreExact() {
        assertEquals(AccountStatusKind.WARNED, version().kind)
        for (value in listOf("suspendedUntil", "temporarilyBanned")) assertEquals(
            AccountStatusKind.SUSPENDED,
            version(value).kind,
        )
        for (value in listOf("bannedPermanent", "permanentlyBanned")) assertEquals(
            AccountStatusKind.BANNED,
            version(value).kind,
        )
        assertEquals(AccountStatusKind.DEACTIVATED, version("deactivated").kind)
        assertEquals(AccountStatusKind.RESTORED, version("active").kind)
        assertNull(version("unknown").kind)
    }

    @Test
    fun restrictedCasesSignOutButWarnedAndRestoredAcknowledge() {
        assertFalse(version().requiresSignOut)
        assertFalse(version("active").requiresSignOut)
        for (value in
            listOf(
                "suspendedUntil",
                "temporarilyBanned",
                "bannedPermanent",
                "permanentlyBanned",
                "deactivated",
            )) assertTrue(version(value).requiresSignOut)
    }

    @Test
    fun noNoticeWithoutARealStatusUpdate() {
        assertNull(decodeAccountStatus("status-user", fields() - "statusUpdatedAt").notice)
        assertNull(AccountStatusObservation(null, null).notice)
    }

    @Test
    fun acknowledgementComparesFullNanosecondPrecision() {
        val v = version()
        assertNotNull(AccountStatusObservation(v, time.minusNanos(1)).notice)
        assertNull(AccountStatusObservation(v, time).notice)
        assertNull(AccountStatusObservation(v, time.plusNanos(1)).notice)
        assertTrue(AccountStatusObservation(v, time).confirms(v))
    }

    @Test
    fun activeWithNonActiveBlockDoesNotInventRestoration() {
        assertNull(version("active", "warned").kind)
        assertEquals(AccountStatusKind.SUSPENDED, version("active", "suspendedUntil").kind)
    }

    @Test
    fun legacyRestrictionWinsOverWarningOrActiveStatusWithoutChangingRawFence() {
        for (account in listOf("active", "warned")) {
            for ((block, kind) in
                mapOf(
                    "blocked" to AccountStatusKind.SUSPENDED,
                    "suspendedUntil" to AccountStatusKind.SUSPENDED,
                    "bannedPermanent" to AccountStatusKind.BANNED,
                    "deactivated" to AccountStatusKind.DEACTIVATED,
                )) {
                val value = version(account, block)
                assertEquals(kind, value.kind)
                assertTrue(value.requiresSignOut)
                assertEquals(account, value.status)
                assertEquals(block, value.blockState)
                assertEquals(value, decodeAccountStatus(value.uid, fields(value)).notice)
            }
        }
    }

    @Test
    fun mixedLegacyRestrictionCannotGainAcknowledgementByForgingUiCapability() {
        for (block in listOf("blocked", "suspendedUntil", "bannedPermanent", "deactivated")) {
            val value = version("warned", block)
            fails(AccountStatusFailure.DENIED) {
                requireAcknowledgementProfile(session(value), fields(value))
            }
        }
        assertEquals(AccountStatusKind.BANNED, version("bannedPermanent", "blocked").kind)
    }

    @Test
    fun defaultDtoDiagnosticsNeverIncludeRawNoticeOrUid() {
        val value = version()
        for (rendered in listOf(value.toString(), session(value).observation.toString())) {
            assertFalse(rendered.contains(requireNotNull(value.reason)))
            assertFalse(rendered.contains(requireNotNull(value.message)))
            assertFalse(rendered.contains(value.uid))
            assertFalse(rendered.contains(requireNotNull(value.expiresAt).toString()))
            assertTrue(rendered.contains("redacted"))
        }
    }

    @Test
    fun reasonMessageAndExpiryAreIndependentRawFenceFields() {
        val v = version()
        assertEquals(v, decodeAccountStatus(v.uid, fields(v)).version)
        assertNotEquals(v, v.copy(reason = v.reason?.trim()))
        assertNotEquals(v, v.copy(message = v.message?.trim()))
        assertNotEquals(v, v.copy(expiresAt = v.expiresAt?.plusNanos(1)))
        assertNotEquals(v, v.copy(updatedAt = v.updatedAt.plusNanos(1)))
        assertNotEquals(v, v.copy(blockState = "warned"))
    }

    @Test
    fun malformedKnownStatusAndFieldTypesFailClosed() {
        for ((key, value) in
            listOf(
                "accountStatus" to "alien",
                "blockState" to 12,
                "statusReason" to true,
                "statusMessage" to 1,
                "statusUpdatedAt" to time.toString(),
                "statusAcknowledgedAt" to 7,
                "banExpiresAt" to "tomorrow",
            )) {
            fails(AccountStatusFailure.INVALID) {
                decodeAccountStatus("status-user", fields() + (key to value))
            }
        }
    }

    @Test
    fun missingOrForeignStoredIdIsNotRepairedByAcknowledgement() {
        fails(AccountStatusFailure.INVALID) {
            requireAcknowledgementProfile(session(), fields() - "id")
        }
        fails(AccountStatusFailure.INVALID) {
            requireAcknowledgementProfile(session(), fields() + ("id" to "other"))
        }
    }

    @Test
    fun restrictedProfileCannotBeAcknowledgedUsingOldActiveSession() {
        for (value in listOf("suspendedUntil", "bannedPermanent", "deactivated")) fails(
            AccountStatusFailure.DENIED
        ) {
            requireAcknowledgementProfile(session(), fields(version(value)))
        }
    }

    @Test
    fun freshPrivilegedProfileNeedsStrictActivatedRealTotp() {
        val owner = session().copy(role = "owner", totpAuthenticated = false)
        val elevated = fields() + mapOf("globalRole" to "owner", "requiresMultiFactorAuth" to true)
        fails(AccountStatusFailure.DENIED) { requireAcknowledgementProfile(owner, elevated) }
        fails(AccountStatusFailure.DENIED) {
            requireAcknowledgementProfile(
                owner.copy(totpAuthenticated = true),
                elevated + ("requiresMultiFactorAuth" to false),
            )
        }
        requireAcknowledgementProfile(owner.copy(totpAuthenticated = true), elevated)
        fails(AccountStatusFailure.STALE) { requireAcknowledgementProfile(session(), elevated) }
    }

    @Test
    fun legacyNonPrivilegedRoleNeverBecomesElevated() {
        requireAcknowledgementProfile(session(), fields() + ("globalRole" to "moderator"))
    }

    private class Gate : AccountStatusMutationGate, AccountStatusReadGate {
        var entries = 0
        var readEntries = 0
        var denied = false

        override suspend fun <T> withSession(
            session: AccountStatusSession,
            action: suspend () -> T,
        ): T {
            entries++
            if (denied) throw AccountStatusException(AccountStatusFailure.DENIED)
            return withContext(NonCancellable) { action() }
        }

        override suspend fun <T> withReadSession(
            session: AccountStatusSession,
            action: suspend () -> T,
        ): T {
            readEntries++
            return withContext(NonCancellable) { action() }
        }
    }

    private fun repository(source: Source, gate: Gate = Gate()) =
        AccountStatusRepository(source, gate, gate)

    private class Source(initial: AccountStatusObservation) : AccountStatusSource {
        var observed = initial
        var sends = 0
        var reads = 0
        var lostReceipt = false
        var readFailure: AccountStatusFailure? = null
        var waitBeforeCommit: CompletableDeferred<Unit>? = null
        var waitAfterCommitChecks: CompletableDeferred<Unit>? = null
        var waitBeforeDispatch: CompletableDeferred<Unit>? = null

        override suspend fun read(session: AccountStatusSession): AccountStatusObservation {
            reads++
            readFailure?.let { throw AccountStatusException(it) }
            return observed
        }

        override suspend fun acknowledge(
            session: AccountStatusSession,
            expected: AccountStatusVersion,
            canDispatch: () -> Boolean,
            onDispatch: () -> Unit,
        ) {
            if (!canDispatch()) throw AccountStatusException(AccountStatusFailure.STALE)
            waitBeforeDispatch?.await()
            onDispatch()
            waitBeforeCommit?.await()
            if (!canDispatch()) throw AccountStatusException(AccountStatusFailure.STALE)
            if (observed.version != expected)
                throw AccountStatusException(AccountStatusFailure.STALE)
            sends++
            waitAfterCommitChecks?.await()
            observed = observed.copy(acknowledgedAt = expected.updatedAt.plusSeconds(1))
            if (lostReceipt) throw IllegalStateException("synthetic lost receipt")
        }
    }

    @Test
    fun successfulAcknowledgementRequiresActualReadBack() =
        runTest(dispatcher) {
            val s = session()
            val source = Source(s.observation)
            val gate = Gate()
            val result = repository(source, gate).acknowledge(s, version()) { true }
            assertTrue(result.confirms(version()))
            assertEquals(1, source.sends)
            assertEquals(1, source.reads)
            assertEquals(1, gate.entries)
        }

    @Test
    fun lostReceiptIsUnconfirmedAndReconciliationNeverResends() =
        runTest(dispatcher) {
            val s = session()
            val source = Source(s.observation).apply { lostReceipt = true }
            val repo = repository(source)
            suspendFails(AccountStatusFailure.UNCONFIRMED) {
                repo.acknowledge(s, version()) { true }
            }
            assertEquals(AccountStatusReconciliation.CONFIRMED, repo.reconcile(s, version()))
            assertEquals(1, source.sends)
        }

    @Test
    fun readBackFailureAfterCommitRemainsUnconfirmed() =
        runTest(dispatcher) {
            val s = session()
            val source = Source(s.observation).apply { readFailure = AccountStatusFailure.OFFLINE }
            suspendFails(AccountStatusFailure.UNCONFIRMED) {
                repository(source).acknowledge(s, version()) { true }
            }
            assertEquals(1, source.sends)
        }

    @Test
    fun changedVersionNeverCountsAsCurrentConfirmation() =
        runTest(dispatcher) {
            val s = session()
            val source =
                Source(
                    AccountStatusObservation(version().copy(message = "new unseen message"), null)
                )
            val repo = repository(source)
            suspendFails(AccountStatusFailure.STALE) { repo.acknowledge(s, version()) { true } }
            assertEquals(0, source.sends)
            assertEquals(AccountStatusReconciliation.CHANGED, repo.reconcile(s, version()))
        }

    @Test
    fun closedPresentationCannotDispatchQueuedWrite() =
        runTest(dispatcher) {
            val source = Source(session().observation)
            suspendFails(AccountStatusFailure.STALE) {
                repository(source).acknowledge(session(), version()) { false }
            }
            assertEquals(0, source.sends)
        }

    @Test
    fun deniedGateAndForeignVersionDoNotReachSource() =
        runTest(dispatcher) {
            val source = Source(session().observation)
            val gate = Gate().apply { denied = true }
            val repo = repository(source, gate)
            suspendFails(AccountStatusFailure.DENIED) {
                repo.acknowledge(session(), version()) { true }
            }
            suspendFails(AccountStatusFailure.DENIED) {
                repo.acknowledge(session(), version().copy(uid = "foreign")) { true }
            }
            assertEquals(0, source.sends)
            assertEquals(0, source.reads)
        }

    @Test
    fun restrictedSessionCanReconcileReadOnlyWithoutAckGate() =
        runTest(dispatcher) {
            val source = Source(session().observation)
            val gate = Gate().apply { denied = true }
            val repo = repository(source, gate)
            assertEquals(
                AccountStatusReconciliation.NOT_CONFIRMED,
                repo.reconcile(session().copy(canAcknowledge = false), version()),
            )
            assertEquals(0, gate.entries)
            assertEquals(1, gate.readEntries)
            assertEquals(0, source.sends)
        }

    private class Fixture(
        val sessions: MutableStateFlow<AccountStatusSession?>,
        val source: Source,
        val model: AccountStatusViewModel,
    )

    private fun fixture(signOut: suspend (AccountStatusSession) -> Boolean = { true }): Fixture {
        val sessions = MutableStateFlow<AccountStatusSession?>(session())
        val source = Source(session().observation)
        val model = AccountStatusViewModel(repository(source), { sessions.value }, signOut)
        model.observeSessions(sessions)
        model.bindSession(sessions.value)
        model.setVisible(true)
        return Fixture(sessions, source, model)
    }

    @Test
    fun duplicateTapsProduceOneMutation() =
        runTest(dispatcher) {
            val f = fixture()
            f.model.acknowledge()
            f.model.acknowledge()
            advanceUntilIdle()
            assertEquals(1, f.source.sends)
            assertNull(f.model.state.value.notice)
        }

    @Test
    fun leavingBeforeDispatchDoesNotSave() =
        runTest(dispatcher) {
            val f = fixture()
            f.model.acknowledge()
            f.model.setVisible(false)
            advanceUntilIdle()
            assertEquals(0, f.source.sends)
        }

    @Test
    fun uidSwitchDuringRealSettlementSuppressesOldResult() =
        runTest(dispatcher) {
            val f = fixture()
            val wait = CompletableDeferred<Unit>()
            f.source.waitBeforeCommit = wait
            f.model.acknowledge()
            runCurrent()
            f.sessions.value = session(version().copy(uid = "new-user")).copy(revision = 5)
            runCurrent()
            wait.complete(Unit)
            advanceUntilIdle()
            assertEquals("new-user", f.model.state.value.notice?.uid)
            assertFalse(f.model.state.value.busy)
            assertNull(f.model.state.value.failure)
        }

    @Test
    fun newerWarningDuringPendingWriteCannotBeAcknowledgedUnseen() =
        runTest(dispatcher) {
            val f = fixture()
            val wait = CompletableDeferred<Unit>()
            f.source.waitBeforeCommit = wait
            f.model.acknowledge()
            runCurrent()
            val newer = version().copy(updatedAt = time.plusSeconds(10), message = "New warning")
            f.source.observed = AccountStatusObservation(newer, null)
            f.sessions.value = session(newer)
            runCurrent()
            wait.complete(Unit)
            advanceUntilIdle()
            assertEquals(0, f.source.sends)
            assertEquals(newer, f.model.state.value.notice)
            assertNull(f.source.observed.acknowledgedAt)
        }

    @Test
    fun uncertainUiRequiresExplicitReadBeforeAnotherSend() =
        runTest(dispatcher) {
            val f = fixture()
            f.source.lostReceipt = true
            f.model.acknowledge()
            advanceUntilIdle()
            assertEquals(AccountStatusFailure.UNCONFIRMED, f.model.state.value.failure)
            f.model.acknowledge()
            advanceUntilIdle()
            assertEquals(1, f.source.sends)
            f.model.reconcile()
            advanceUntilIdle()
            assertNull(f.model.state.value.notice)
            assertEquals(1, f.source.sends)
        }

    @Test
    fun sameUidNewRevisionKeepsUnknownAckReadOnlyUntilReconciled() =
        runTest(dispatcher) {
            val f = fixture()
            f.source.lostReceipt = true
            f.model.acknowledge()
            advanceUntilIdle()
            f.sessions.value = session().copy(revision = 5)
            advanceUntilIdle()
            assertEquals(version(), f.model.state.value.pending)
            f.model.acknowledge()
            advanceUntilIdle()
            assertEquals(1, f.source.sends)
        }

    @Test
    fun transientClearedProfileRetainsOnlyVersionMarkerThenRequiresReadBeforeResend() =
        runTest(dispatcher) {
            val f = fixture()
            f.source.lostReceipt = true
            f.model.acknowledge()
            advanceUntilIdle()
            f.model.bindSession(null, retainedUid = "status-user")
            assertNull(f.model.state.value.pending)
            assertNull(f.model.state.value.notice)
            assertNull(f.model.state.value.session)
            f.sessions.value = session().copy(revision = 5)
            advanceUntilIdle()
            assertEquals(version(), f.model.state.value.pending)
            f.model.acknowledge()
            advanceUntilIdle()
            assertEquals(1, f.source.sends)
            f.model.reconcile()
            advanceUntilIdle()
            assertEquals(1, f.source.sends)
            assertNull(f.model.state.value.pending)
            assertNull(f.model.state.value.notice)
        }

    @Test
    fun cancellationAfterActualDispatchKeepsPendingUntilExactReadBackOnNewRevision() =
        runTest(dispatcher) {
            val f = fixture()
            val settlement = CompletableDeferred<Unit>()
            f.source.waitAfterCommitChecks = settlement
            f.model.acknowledge()
            runCurrent()
            assertEquals(1, f.source.sends)
            assertEquals(version(), f.model.state.value.pending)
            assertNull(f.source.observed.acknowledgedAt)
            f.model.bindSession(null, retainedUid = "status-user")
            assertNull(f.model.state.value.pending)
            f.sessions.value = session().copy(revision = 5)
            runCurrent()
            assertEquals(version(), f.model.state.value.pending)
            f.model.acknowledge()
            runCurrent()
            assertEquals(1, f.source.sends)
            settlement.complete(Unit)
            advanceUntilIdle()
            assertTrue(f.source.observed.confirms(version()))
            assertEquals(version(), f.model.state.value.pending)
            f.model.reconcile()
            advanceUntilIdle()
            assertEquals(1, f.source.sends)
            assertNull(f.model.state.value.pending)
            assertNull(f.model.state.value.notice)
        }

    @Test
    fun lateDispatchCallbackCannotCreateOldPrivateMarkerAfterLogoutOrNewUid() =
        runTest(dispatcher) {
            for (next in listOf(null, session(version().copy(uid = "other-user")))) {
                val f = fixture()
                val dispatch = CompletableDeferred<Unit>()
                f.source.waitBeforeDispatch = dispatch
                f.model.acknowledge()
                runCurrent()
                assertNull(f.model.state.value.pending)
                f.sessions.value = next
                runCurrent()
                dispatch.complete(Unit)
                advanceUntilIdle()
                assertEquals(0, f.source.sends)
                assertNull(f.model.state.value.pending)
                f.sessions.value = session().copy(revision = 6)
                advanceUntilIdle()
                assertNull(f.model.state.value.pending)
                assertEquals(version(), f.model.state.value.notice)
            }
        }

    @Test
    fun transientPendingMarkerDoesNotAttachToAChangedRawVersionOrSendAutomatically() =
        runTest(dispatcher) {
            val f = fixture()
            f.source.lostReceipt = true
            f.model.acknowledge()
            advanceUntilIdle()
            f.model.bindSession(null, retainedUid = "status-user")
            val newer = version().copy(message = "Distinct unseen raw version")
            f.source.observed = AccountStatusObservation(newer, null)
            f.sessions.value = session(newer).copy(revision = 5)
            advanceUntilIdle()
            assertNull(f.model.state.value.pending)
            assertEquals(newer, f.model.state.value.notice)
            assertNull(f.source.observed.acknowledgedAt)
            assertEquals(1, f.source.sends)
        }

    @Test
    fun actualLogoutOrOtherUidClearsTransientPendingMarkerBeforeOriginalUidReturns() =
        runTest(dispatcher) {
            for (newUid in listOf(null, "other-user")) {
                val f = fixture()
                f.source.lostReceipt = true
                f.model.acknowledge()
                advanceUntilIdle()
                f.model.bindSession(null, retainedUid = "status-user")
                f.model.bindSession(null, retainedUid = newUid)
                f.sessions.value = session().copy(revision = 6)
                advanceUntilIdle()
                assertNull(f.model.state.value.pending)
                assertEquals(version(), f.model.state.value.notice)
                assertEquals(1, f.source.sends)
            }
        }

    @Test
    fun logoutClearsAllPrivateNoticeAndPendingState() =
        runTest(dispatcher) {
            val f = fixture()
            f.source.lostReceipt = true
            f.model.acknowledge()
            advanceUntilIdle()
            f.sessions.value = null
            advanceUntilIdle()
            assertNull(f.model.state.value.notice)
            assertNull(f.model.state.value.pending)
            assertNull(f.model.state.value.session)
        }

    @Test
    fun verificationEscapeDoesNotAcknowledgeAndReappearsAfterVerifiedSession() =
        runTest(dispatcher) {
            val f = fixture()
            f.sessions.value = session().copy(canAcknowledge = false, verified = false)
            advanceUntilIdle()
            assertTrue(f.model.escapeForAuthentication())
            assertNull(f.model.state.value.notice)
            assertEquals(0, f.source.sends)
            f.sessions.value = session()
            advanceUntilIdle()
            assertEquals(version(), f.model.state.value.notice)
        }

    @Test
    fun failedSignOutIsNotTreatedAsSuccess() =
        runTest(dispatcher) {
            val f = fixture { false }
            f.model.requestSignOut()
            advanceUntilIdle()
            assertEquals(AccountStatusFailure.SIGN_OUT_FAILED, f.model.state.value.failure)
            assertEquals(version(), f.model.state.value.notice)
            assertEquals(0, f.source.sends)
        }

    @Test
    fun legacyBlockedSnapshotRemainsReadableButCannotAcknowledge() {
        val raw = fields(version("suspendedUntil", "blocked"))
        assertEquals(
            AccountStatusKind.SUSPENDED,
            decodeAccountStatus("status-user", raw).notice?.kind,
        )
        fails(AccountStatusFailure.DENIED) { requireAcknowledgementProfile(session(), raw) }
    }

    @Test
    fun presentNullAuthorityAndMalformedLegacyBlockNeverDefaultActive() {
        for (key in listOf("accountStatus", "blockState")) fails(AccountStatusFailure.INVALID) {
            decodeAccountStatus("status-user", fields() + (key to null))
        }
        fails(AccountStatusFailure.INVALID) {
            decodeAccountStatus("status-user", fields() - "blockState" + ("isBlocked" to "true"))
        }
        fails(AccountStatusFailure.INVALID) {
            decodeAccountStatus("status-user", fields() + ("statusUpdatedAt" to time))
        }
    }

    @Test
    fun nativeDateFormatterHasDefensiveExtremeFallback() {
        assertEquals("Zeitpunkt nicht verfügbar", accountStatusExpiryText(Instant.MAX, "de"))
        assertEquals("Дата недоступна", accountStatusExpiryText(Instant.MIN, "uk"))
        assertTrue(accountStatusExpiryText(time, "de").isNotBlank())
    }

    @Test
    fun privacyClosingDuringTransactionRetryPreventsDispatch() =
        runTest(dispatcher) {
            val f = fixture()
            val wait = CompletableDeferred<Unit>()
            f.source.waitBeforeCommit = wait
            f.model.acknowledge()
            runCurrent()
            f.model.setVisible(false)
            wait.complete(Unit)
            advanceUntilIdle()
            assertEquals(0, f.source.sends)
        }

    @Test
    fun remediationEscapeSurvivesSameUidBusyAndRevisionButNotRealLogout() =
        runTest(dispatcher) {
            val f = fixture()
            val limited = session().copy(canAcknowledge = false, verified = false)
            f.sessions.value = limited
            advanceUntilIdle()
            assertTrue(f.model.escapeForAuthentication())
            f.model.bindSession(null, retainedUid = limited.uid)
            f.model.bindSession(limited.copy(revision = 5))
            assertNull(f.model.state.value.notice)
            f.model.bindSession(null)
            f.model.bindSession(limited.copy(revision = 6))
            assertEquals(version(), f.model.state.value.notice)
        }

    @Test
    fun cancelledSignOutResetsBusyWithoutPretendingSuccess() =
        runTest(dispatcher) {
            val f = fixture {
                throw kotlinx.coroutines.CancellationException("synthetic cancellation")
            }
            f.model.requestSignOut()
            advanceUntilIdle()
            assertFalse(f.model.state.value.busy)
            assertEquals(version(), f.model.state.value.notice)
        }

    private fun fails(reason: AccountStatusFailure, action: () -> Unit) {
        val error =
            runCatching(action).exceptionOrNull() ?: throw AssertionError("Expected failure")
        assertEquals(reason, (error as AccountStatusException).failure)
    }

    private suspend fun suspendFails(reason: AccountStatusFailure, action: suspend () -> Unit) {
        val error =
            try {
                action()
                null
            } catch (error: Exception) {
                error
            }
        assertNotNull(error)
        assertEquals(reason, (error as AccountStatusException).failure)
    }
}
