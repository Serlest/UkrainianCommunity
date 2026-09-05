package at.uac.pushprobe

import org.junit.Assert.*
import org.junit.Test

class ProbePolicyTest {
    private val now = 1_788_000_000_000L
    private val run = "9d057b8f-3023-4f68-9fb3-73ba27810d41"
    private val id = "8699987e-e85d-4c2d-a64d-96d137215dd2"
    private val fid = "c123456789012345678901"
    private val hash = ProbeContract.hash(fid)

    private fun ready() = ProbeState().optIn(now, run).registrationAcknowledged(1, hash, now + 1)

    private fun payload() =
        mapOf(
            "kind" to ProbeContract.KIND,
            "runId" to run,
            "targetHash" to hash,
            "probeId" to id,
            "sentAtEpochMs" to now.toString(),
            "expiresAtEpochMs" to (now + 60_000).toString(),
        )

    private fun decision(
        state: ProbeState = ready(),
        data: Map<String, String> = payload(),
        sender: String? = ProbeContract.NUMBER,
        notification: Boolean = false,
        permission: Boolean = true,
        time: Long = now + 2,
    ) = decideProbeMessage(state, data, sender, notification, permission, time)

    @Test
    fun defaultIsOffWithoutImplicitRegistration() {
        assertFalse(ProbeState().everOptedIn)
        assertEquals(ProbeEvent.REJECTED_CONSENT, decision(ProbeState()).refusal)
    }

    @Test
    fun exactSyntheticDataIsAccepted() {
        assertEquals(id, decision().message?.probeId)
        assertNull(decision().refusal)
    }

    @Test
    fun serverTextNeverBecomesDisplayContent() {
        assertEquals(
            ProbeEvent.REJECTED_SCHEMA,
            decision(data = payload() + ("body" to "private text")).refusal,
        )
    }

    @Test
    fun notificationEnvelopeIsRejectedInHandler() {
        assertEquals(ProbeEvent.REJECTED_SCHEMA, decision(notification = true).refusal)
    }

    @Test
    fun wrongSenderAndTopicsAreRejected() {
        listOf(null, "other", "/topics/all").forEach {
            assertEquals(ProbeEvent.REJECTED_SENDER, decision(sender = it).refusal)
        }
    }

    @Test
    fun permissionDeniedCannotDisplay() {
        assertEquals(ProbeEvent.REJECTED_PERMISSION, decision(permission = false).refusal)
    }

    @Test
    fun wrongRunAndInstallationCannotDisplay() {
        assertEquals(
            ProbeEvent.REJECTED_TARGET,
            decision(data = payload() + ("runId" to id)).refusal,
        )
        assertEquals(
            ProbeEvent.REJECTED_TARGET,
            decision(data = payload() + ("targetHash" to "f".repeat(64))).refusal,
        )
    }

    @Test
    fun expiredPayloadAndRunAreRejected() {
        assertEquals(ProbeEvent.REJECTED_EXPIRED, decision(time = now + 60_000).refusal)
        assertEquals(
            ProbeEvent.REJECTED_EXPIRED,
            decision(state = ready().copy(runExpiresAt = now)).refusal,
        )
    }

    @Test
    fun excessiveTtlAndFutureClockAreRejected() {
        assertEquals(
            ProbeEvent.REJECTED_EXPIRED,
            decision(data = payload() + ("expiresAtEpochMs" to (now + 300_001).toString())).refusal,
        )
        val future = now + 130_000
        assertEquals(
            ProbeEvent.REJECTED_EXPIRED,
            decision(
                    data =
                        payload() +
                            mapOf(
                                "sentAtEpochMs" to future.toString(),
                                "expiresAtEpochMs" to (future + 10_000).toString(),
                            )
                )
                .refusal,
        )
    }

    @Test
    fun malformedTimesAndIdentifiersFailClosed() {
        listOf("sentAtEpochMs", "expiresAtEpochMs", "probeId", "runId", "targetHash").forEach {
            assertEquals(
                ProbeEvent.REJECTED_SCHEMA,
                decision(data = payload() + (it to "untrusted")).refusal,
            )
        }
    }

    @Test
    fun missingAndUnknownFieldsAreRejected() {
        assertEquals(ProbeEvent.REJECTED_SCHEMA, decision(data = payload() - "kind").refusal)
        assertEquals(
            ProbeEvent.REJECTED_SCHEMA,
            decision(data = payload() + ("route" to "https://example.invalid")).refusal,
        )
    }

    @Test
    fun duplicateProbeCannotPostTwice() {
        assertEquals(
            ProbeEvent.REJECTED_DUPLICATE,
            decision(ready().copy(seen = listOf(id))).refusal,
        )
    }

    @Test
    fun capacityNeverEvictsSeenIdsAndAllowsAReplay() {
        val full =
            ready().copy(seen = (1..64).map { "00000000-0000-4000-8000-${"%012d".format(it)}" })
        assertEquals(ProbeEvent.REJECTED_CAPACITY, decision(full).refusal)
        assertEquals(
            ProbeEvent.REJECTED_DUPLICATE,
            decision(full, data = payload() + ("probeId" to full.seen.first())).refusal,
        )
    }

    @Test
    fun callbackCannotManufactureRegisterAcknowledgement() {
        val pending = ProbeState().optIn(now, run).event(ProbeEvent.REGISTER_CALLBACK, now)
        assertTrue(pending.registering)
        assertNull(pending.registrationHash)
        assertEquals(ProbeEvent.REJECTED_CONSENT, decision(pending).refusal)
    }

    @Test
    fun optOutImmediatelyMasksEvenBeforeSdkCleanup() {
        val stopped = ready().optOut(now + 2)
        assertTrue(stopped.cleanupPending)
        assertFalse(stopped.optedIn)
        assertNull(stopped.registrationHash)
        assertNull(stopped.runId)
        assertEquals(ProbeEvent.REJECTED_CONSENT, decision(stopped).refusal)
    }

    @Test
    fun lateRegisterCannotRestoreConsentOrTarget() {
        val stopped = ProbeState().optIn(now, run).optOut(now + 1)
        assertEquals(stopped, stopped.registrationAcknowledged(1, hash, now + 2))
    }

    @Test
    fun lateUnregisterCannotInvalidateANewRun() {
        val stopped = ready().optOut(now + 2).unregistrationAcknowledged(2, now + 3)
        val next = stopped.optIn(now + 4, id)
        assertEquals(next, next.unregistrationAcknowledged(2, now + 5))
    }

    @Test
    fun cleanupMustBeConfirmedBeforeAnotherOptIn() {
        val stopped = ready().optOut(now + 2)
        assertTrue(runCatching { stopped.optIn(now + 3, id) }.isFailure)
        assertTrue(
            stopped
                .unregistrationAcknowledged(stopped.generation, now + 3)
                .optIn(now + 4, id)
                .optedIn
        )
    }

    @Test
    fun registerAfterRunExpiryDoesNotCreateTarget() {
        val pending = ProbeState().optIn(now, run)
        assertEquals(
            pending,
            pending.registrationAcknowledged(1, hash, now + ProbeContract.RUN_LIFETIME_MS),
        )
    }

    @Test
    fun receiptsAreBoundedAndNeverAcceptUntrustedFreeText() {
        val state =
            (1..90).fold(ProbeState()) { acc, n ->
                acc.event(ProbeEvent.RECEIVED, now + n, "not-an-id")
            }
        assertEquals(48, state.receipts.size)
        assertTrue(state.receipts.all { it.probeId == null })
    }

    @Test
    fun configurationCannotPointAtProductionOtherAppOrRelease() {
        val key = "AIza" + "a".repeat(35)
        fun allowed(
            project: String = ProbeContract.PROJECT,
            number: String = ProbeContract.NUMBER,
            app: String = ProbeContract.APP,
            pkg: String = ProbeContract.PACKAGE,
            debug: Boolean = true,
            apiKey: String = key,
        ) = ProbeContract.configurationAllowed(project, number, app, pkg, debug, apiKey)
        assertTrue(allowed())
        assertFalse(allowed(project = "production"))
        assertFalse(allowed(number = "000"))
        assertFalse(allowed(app = "other"))
        assertFalse(allowed(pkg = "at.uac.android.local"))
        assertFalse(allowed(debug = false))
        assertFalse(allowed(apiKey = ""))
    }

    @Test
    fun onlyValidFidCanBecomePrivateTarget() {
        assertTrue(ProbeContract.validFid(fid))
        assertFalse(ProbeContract.validFid("token:arbitrary"))
        assertEquals(64, hash.length)
    }

    @Test
    fun scopedCleanupAcceptsOnlyPreparedRunAndItsOwnPendingCompletion() {
        val active = ready()
        val scope = ProbeCleanupScope(active.generation, run)
        assertTrue(scope.matches(active))
        assertTrue(scope.matches(active.optOut(now + 1)))
        assertTrue(
            scope.matches(
                active.optOut(now + 1).unregistrationAcknowledged(active.generation + 1, now + 2)
            )
        )
    }

    @Test
    fun scopedCleanupCannotStopAnotherOrNewerRun() {
        val active = ready()
        val scope = ProbeCleanupScope(active.generation, run)
        assertFalse(scope.matches(active.copy(runId = id)))
        val newRun =
            active
                .optOut(now + 1)
                .unregistrationAcknowledged(active.generation + 1, now + 2)
                .optIn(now + 3, id)
        assertFalse(scope.matches(newRun))
    }
}
