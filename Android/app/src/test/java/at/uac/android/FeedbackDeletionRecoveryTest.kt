package at.uac.android

import at.uac.android.core.backend.CompiledBackend
import at.uac.android.feature.feedback.FeedbackAudience
import at.uac.android.feature.feedbackdeletion.*
import at.uac.android.feature.moderation.ModerationSession
import com.google.firebase.Timestamp
import java.time.Instant
import org.junit.Assert.*
import org.junit.Test

class FeedbackDeletionRecoveryTest {
    private val actor = ModerationSession("deletion-owner", 3, "owner", true)
    private val id = "deletion-target"
    private val operation = "00000000-0000-4000-8000-000000000001"
    private val otherOperation = "00000000-0000-4000-8000-000000000002"
    private val now = Instant.parse("2026-09-03T16:00:00.123456789Z")
    private val fields: Map<String, Any?> =
        mapOf(
            "id" to id,
            "userId" to "private-author",
            "userDisplayName" to "PRIVATE NAME",
            "message" to "PRIVATE MESSAGE",
            "type" to "question",
            "status" to "open",
            "subject" to "PRIVATE SUBJECT",
            "createdAt" to now,
            "unknown" to mapOf("timestamp" to now, "value" to 1L),
        )

    private fun snapshot(extra: Map<String, Any?> = emptyMap()) =
        FeedbackDeletionRecovery.snapshot(id, fields + extra)

    private fun prepared() =
        FeedbackDeletionRecovery.prepared(actor, FeedbackAudience.MANAGEMENT, snapshot(), operation)

    private fun dispatched() = prepared().copy(phase = FeedbackDeletionPhase.DISPATCHED)

    private fun acknowledged(): FeedbackDeletionPending {
        val value = dispatched()
        return value.copy(
            phase = FeedbackDeletionPhase.ACKNOWLEDGED,
            receipt = FeedbackDeletionRecovery.receipt(value, mapOf("deletedCount" to 1)),
        )
    }

    private fun invalid(block: () -> Unit) {
        val error = runCatching(block).exceptionOrNull()
        assertTrue(error is FeedbackDeletionException)
        assertEquals(FeedbackDeletionFailure.INVALID, (error as FeedbackDeletionException).failure)
    }

    @Test
    fun fullRawMapOrderDoesNotChangeVersion() {
        val reversed = fields.entries.reversed().associate { it.key to it.value }
        assertEquals(snapshot().version, FeedbackDeletionRecovery.snapshot(id, reversed).version)
    }

    @Test
    fun allUnshownFieldsNullPresenceAndWhitespaceAffectVersion() {
        val original = snapshot().version
        for (extra in
            listOf(
                mapOf("unshown" to "new"),
                mapOf("unshown" to null),
                mapOf("message" to "PRIVATE MESSAGE "),
                mapOf("unknown" to emptyMap<String, Any>()),
                mapOf("unreadForOwner" to true),
                mapOf("ownerReply" to "later reply"),
            )) assertNotEquals(original, snapshot(extra).version)
        assertNotEquals(snapshot(mapOf("unshown" to null)).version, original)
    }

    @Test
    fun integerRepresentationsNormalizeButFloatingBitsAndTypesDoNot() {
        fun version(value: Any?) = snapshot(mapOf("number" to value)).version
        assertEquals(version(1), version(1L))
        assertNotEquals(version(1L), version(1.0))
        assertNotEquals(version(0.0), version(-0.0))
        assertNotEquals(version("1"), version(1L))
        assertNotEquals(version(true), version(1L))
        assertNotEquals(version(listOf(1, 2)), version(listOf(2, 1)))
    }

    @Test
    fun firebaseTimestampAndInstantRetainExactSecondsAndNanos() {
        val sdk = Timestamp(now.epochSecond, now.nano)
        val fromSdk = snapshot(mapOf("createdAt" to sdk))
        assertEquals(snapshot().version, fromSdk.version)
        assertEquals(now, fromSdk.target.createdAt)
        assertNotEquals(
            snapshot().version,
            snapshot(mapOf("createdAt" to now.plusNanos(1))).version,
        )
        assertNotEquals(
            snapshot().version,
            snapshot(mapOf("unknown" to mapOf("timestamp" to now.plusNanos(1), "value" to 1L)))
                .version,
        )
    }

    @Test
    fun rawVersionBindsCanonicalPathAndRejectsMismatchedStoredId() {
        val otherFields = (fields - "id")
        assertNotEquals(
            FeedbackDeletionRecovery.snapshot(id, otherFields).version,
            FeedbackDeletionRecovery.snapshot("another-id", otherFields).version,
        )
        invalid { FeedbackDeletionRecovery.snapshot("another-id", fields) }
    }

    @Test
    fun invalidNumbersUnsupportedObjectsAndMalformedUnicodeFailWithoutStringifying() {
        val sentinel =
            object {
                override fun toString(): String = error("Must never stringify raw data")
            }
        for (value in
            listOf(
                Double.NaN,
                Double.POSITIVE_INFINITY,
                1F,
                sentinel,
                "\uD800",
                byteArrayOf(1),
            )) invalid { snapshot(mapOf("unknown" to value)) }
        invalid { snapshot(mapOf("unknown" to mapOf(1 to "not a string key"))) }
        invalid { snapshot(mapOf("\uDC00" to "malformed key")) }
    }

    @Test
    fun byteEntryDepthAndCycleBudgetsRejectBeforeUnboundedConversion() {
        invalid { snapshot(mapOf("unknown" to "ї".repeat(600_000))) }
        invalid { snapshot(mapOf("unknown" to List(4096) { it })) }
        var deep: Any? = "leaf"
        repeat(22) { deep = listOf(deep) }
        invalid { snapshot(mapOf("unknown" to deep)) }
        val cycle = mutableListOf<Any?>()
        cycle.add(cycle)
        invalid { snapshot(mapOf("unknown" to cycle)) }
    }

    @Test
    fun timestampsOutsideFirestoreRangeCannotBeVersioned() {
        invalid { snapshot(mapOf("unknown" to Instant.MIN)) }
        invalid { snapshot(mapOf("unknown" to Instant.MAX)) }
    }

    @Test
    fun snapshotDoesNotRetainCallerMutableMaps() {
        val nested = mutableMapOf<String, Any?>("value" to 1L)
        val raw = (fields + ("unknown" to nested)).toMutableMap()
        val captured = FeedbackDeletionRecovery.snapshot(id, raw)
        val originalVersion = captured.version
        nested["value"] = 2L
        raw["subject"] = "changed"
        assertEquals(originalVersion, captured.version)
        assertEquals("PRIVATE SUBJECT", captured.target.subject)
        assertNotEquals(originalVersion, FeedbackDeletionRecovery.snapshot(id, raw).version)
    }

    @Test
    fun prepareBindsAccountPathVersionAndCanonicalOperationWithoutPrivateLabels() {
        val pending = prepared()
        FeedbackDeletionRecovery.validate(pending)
        assertEquals(FeedbackDeletionPhase.PREPARED, pending.phase)
        assertNull(pending.receipt)
        assertEquals(CompiledBackend.PROJECT_ID, pending.backend)
        assertEquals(snapshot().version, pending.version)
        assertNotEquals(actor.uid, pending.accountHash)
        assertEquals(64, pending.accountHash.length)
        assertNotEquals(pending.accountHash, FeedbackDeletionRecovery.accountHash("other-owner"))
    }

    @Test
    fun prepareCannotBorrowAnotherPathAudienceOrAdminAuthority() {
        invalid {
            FeedbackDeletionRecovery.prepared(
                actor,
                FeedbackAudience.MANAGEMENT,
                snapshot().copy(target = snapshot().target.copy(feedbackId = "other")),
                operation,
            )
        }
        for ((session, audience) in
            listOf(
                actor.copy(role = "admin") to FeedbackAudience.MANAGEMENT,
                actor to FeedbackAudience.OWN,
                actor.copy(ready = false) to FeedbackAudience.MANAGEMENT,
            )) {
            val error = runCatching {
                FeedbackDeletionRecovery.prepared(session, audience, snapshot(), operation)
            }
                .exceptionOrNull()
            assertEquals(
                FeedbackDeletionFailure.ACCESS,
                (error as FeedbackDeletionException).failure,
            )
        }
    }

    @Test
    fun ownerAuthoredFeedbackEvenWithSameCanonicalIdIsNotAUserRoleMutation() {
        val own =
            FeedbackDeletionRecovery.snapshot(
                actor.uid,
                fields + mapOf("id" to actor.uid, "userId" to actor.uid),
            )
        FeedbackDeletionRecovery.prepared(actor, FeedbackAudience.MANAGEMENT, own, operation)
    }

    @Test
    fun malformedVersionsBackendAndOperationIdsAreRejected() {
        val value = prepared()
        for (bad in
            listOf(
                value.copy(backend = "another-project"),
                value.copy(accountHash = "raw-uid"),
                value.copy(operationId = "1-1-1-1-1"),
                value.copy(operationId = "not a uuid"),
                value.copy(version = value.version.copy(fingerprint = "A".repeat(64))),
                value.copy(version = value.version.copy(targetId = "redirect/path")),
            )) invalid { FeedbackDeletionRecovery.validate(bad) }
    }

    @Test
    fun onlyDispatchedActualSuccessfulDataMayConstructReceipt() {
        val early = runCatching {
            FeedbackDeletionRecovery.receipt(prepared(), mapOf("deletedCount" to 1))
        }
            .exceptionOrNull()
        assertEquals(
            FeedbackDeletionFailure.UNCONFIRMED,
            (early as FeedbackDeletionException).failure,
        )
        for (data in listOf(null, mapOf("deletedCount" to 0), mapOf("error" to "not-found"))) {
            val error = runCatching {
                FeedbackDeletionRecovery.receipt(dispatched(), data)
            }
                .exceptionOrNull()
            assertEquals(
                FeedbackDeletionFailure.UNCONFIRMED,
                (error as FeedbackDeletionException).failure,
            )
        }
        FeedbackDeletionRecovery.validate(acknowledged())
    }

    @Test
    fun receiptPhaseAndEveryLocalBindingMustMatch() {
        val ack = acknowledged()
        for (bad in
            listOf(
                ack.copy(phase = FeedbackDeletionPhase.DISPATCHED),
                ack.copy(receipt = null),
                ack.copy(accountHash = FeedbackDeletionRecovery.accountHash("other-owner")),
                ack.copy(operationId = otherOperation),
                ack.copy(version = snapshot(mapOf("unshown" to true)).version),
                ack.copy(version = ack.version.copy(targetId = "different-feedback")),
                ack.copy(receipt = ack.receipt!!.copy(responseHash = "a".repeat(64))),
                ack.copy(receipt = ack.receipt!!.copy(requestHash = "b".repeat(64))),
            )) invalid { FeedbackDeletionRecovery.validate(bad) }
        assertNotEquals(
            ack.receipt,
            FeedbackDeletionRecovery.receipt(
                dispatched().copy(operationId = otherOperation),
                mapOf("deletedCount" to 1),
            ),
        )
    }

    @Test
    fun recoveryRejectsOtherAccountAndRevokedOwner() {
        for (session in
            listOf(
                actor.copy(uid = "other-owner"),
                actor.copy(role = "admin"),
                actor.copy(ready = false),
            )) {
            val error = runCatching {
                FeedbackDeletionRecovery.requireOwner(session, acknowledged())
            }
                .exceptionOrNull()
            assertEquals(
                FeedbackDeletionFailure.ACCESS,
                (error as FeedbackDeletionException).failure,
            )
        }
        val error = runCatching {
            FeedbackDeletionRecovery.observation(
                dispatched(),
                "other-owner",
                FeedbackDeletionRead.Absent,
            )
        }
            .exceptionOrNull()
        assertEquals(FeedbackDeletionFailure.ACCESS, (error as FeedbackDeletionException).failure)
    }

    @Test
    fun absenceUnavailableAndMatchingDataNeverCreateOwnReceipt() {
        val reads =
            listOf(
                FeedbackDeletionRead.Absent,
                FeedbackDeletionRead.Unavailable,
                FeedbackDeletionRead.Present(snapshot()),
                FeedbackDeletionRead.Present(snapshot(mapOf("changed" to true))),
            )
        val expected =
            listOf(
                FeedbackDeletionObservation.ABSENT_WITHOUT_RECEIPT,
                FeedbackDeletionObservation.UNAVAILABLE,
                FeedbackDeletionObservation.UNCHANGED_WITHOUT_RECEIPT,
                FeedbackDeletionObservation.CHANGED_WITHOUT_RECEIPT,
            )
        for (entry in listOf(prepared(), dispatched())) for ((read, result) in
            reads.zip(expected)) {
            val observation = FeedbackDeletionRecovery.observation(entry, actor.uid, read)
            assertEquals(result, observation)
            assertFalse(observation.hasOwnReceipt)
        }
    }

    @Test
    fun ownAckRemainsDistinctFromParentAbsenceUnchangedChangedAndUnavailable() {
        val reads =
            listOf(
                FeedbackDeletionRead.Absent,
                FeedbackDeletionRead.Unavailable,
                FeedbackDeletionRead.Present(snapshot()),
                FeedbackDeletionRead.Present(snapshot(mapOf("changed" to true))),
            )
        val expected =
            listOf(
                FeedbackDeletionObservation.ACCEPTED_ABSENT,
                FeedbackDeletionObservation.ACCEPTED_UNAVAILABLE,
                FeedbackDeletionObservation.ACCEPTED_UNCHANGED,
                FeedbackDeletionObservation.ACCEPTED_CHANGED,
            )
        for ((read, result) in reads.zip(expected)) {
            val observation = FeedbackDeletionRecovery.observation(acknowledged(), actor.uid, read)
            assertEquals(result, observation)
            assertTrue(observation.hasOwnReceipt)
            assertEquals(read == FeedbackDeletionRead.Absent, observation.parentAbsent)
        }
    }

    @Test
    fun foreignOrMalformedPresentReadIsNotTreatedAsAbsence() {
        val other = FeedbackDeletionRecovery.snapshot("other", fields + ("id" to "other"))
        invalid {
            FeedbackDeletionRecovery.observation(
                acknowledged(),
                actor.uid,
                FeedbackDeletionRead.Present(other),
            )
        }
        invalid {
            FeedbackDeletionRecovery.observation(
                acknowledged(),
                actor.uid,
                FeedbackDeletionRead.Present(
                    snapshot().copy(version = snapshot().version.copy(fingerprint = "invalid"))
                ),
            )
        }
    }

    @Test
    fun unresolvedServerCascadeGateNeverPermitsReplayOrAutomaticPendingClearance() {
        for (result in FeedbackDeletionObservation.entries) {
            assertFalse(result.allowsReplay)
            assertFalse(result.clearsPending)
        }
    }

    @Test
    fun allRecoveryDiagnosticStringsRedactRoutingAndPrivateData() {
        val value =
            snapshot().toString() +
                snapshot().version +
                prepared() +
                acknowledged().receipt +
                FeedbackDeletionRead.Present(snapshot())
        for (secret in
            listOf(
                actor.uid,
                id,
                "private-author",
                "PRIVATE NAME",
                "PRIVATE MESSAGE",
                "PRIVATE SUBJECT",
                operation,
            )) assertFalse(value.contains(secret))
    }
}
