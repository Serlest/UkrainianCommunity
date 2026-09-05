package at.uac.android

import at.uac.android.feature.moderation.ModerationSession
import at.uac.android.feature.platformrolemanagement.*
import com.google.firebase.Timestamp
import java.time.Instant
import org.junit.Assert.*
import org.junit.Test

internal object PlatformRoleUnitFixture {
    val actor = ModerationSession("synthetic-role-owner", 7, "owner", true)
    const val target = "synthetic-role-target"
    const val operation = "0a0a0a0a-1111-4222-8333-444444444444"
    val time = Instant.parse("2026-09-03T12:30:00.123456789Z")

    fun fields(action: PlatformRoleAction = PlatformRoleAction.ASSIGN): Map<String, Any?> =
        mapOf(
            "id" to "legacy-stored-id",
            "globalRole" to action.previousRole,
            "displayName" to "PRIVATE display label",
            "email" to "private@example.invalid",
            "accountStatus" to "active",
            "blockState" to "warned",
            "requiresMultiFactorAuth" to false,
            "statusAcknowledgedAt" to time,
            "statusReason" to "PRIVATE previous reason",
            "updatedAt" to time,
            "organizationMemberships" to listOf("synthetic-org"),
            "roleUpdatedAt" to time.minusSeconds(10),
            "roleUpdatedBy" to "previous-actor",
        )

    fun prepared(action: PlatformRoleAction = PlatformRoleAction.ASSIGN) =
        PlatformRoleRecovery.prepared(
            actor,
            PlatformRoleRecovery.snapshot(target, fields(action)),
            action,
            "PRIVATE reason 😀",
            PlatformRoleTargetAuth(target, true, false),
            operation,
        )

    fun response(action: PlatformRoleAction) =
        mapOf(
            "targetUserId" to target,
            "previousGlobalRole" to action.previousRole,
            "newGlobalRole" to action.newRole,
            "updatedAt" to "2026-09-03T12:30:00.123Z",
        )

    fun acknowledged(action: PlatformRoleAction = PlatformRoleAction.ASSIGN): PlatformRolePending {
        val dispatched = prepared(action).copy(phase = PlatformRolePhase.DISPATCHED)
        return dispatched.copy(
            phase = PlatformRolePhase.ACKNOWLEDGED,
            receipt = PlatformRoleRecovery.receipt(dispatched, response(action)),
        )
    }

    fun after(action: PlatformRoleAction = PlatformRoleAction.ASSIGN) =
        fields(action) +
            mapOf(
                "globalRole" to action.newRole,
                "roleUpdatedAt" to time.plusNanos(7),
                "roleUpdatedBy" to actor.uid,
            )
}

class PlatformRoleRecoveryTest {
    private val f = PlatformRoleUnitFixture

    private fun version(fields: Map<String, Any?>) =
        PlatformRoleRecovery.snapshot(f.target, fields).version

    private fun invalid(block: () -> Unit) {
        try {
            block()
            fail("Expected invalid recovery data")
        } catch (error: PlatformRoleException) {
            assertEquals(PlatformRoleFailure.INVALID, error.failure)
        }
    }

    @Test
    fun mapOrderAndIntegralWidthsAreCanonicalButDoubleIsDistinct() {
        assertEquals(
            version(mapOf("a" to 1, "b" to true)),
            version(linkedMapOf("b" to true, "a" to 1L)),
        )
        assertNotEquals(version(mapOf("a" to 1)), version(mapOf("a" to 1.0)))
        assertNotEquals(version(mapOf("a" to 0.0)), version(mapOf("a" to -0.0)))
    }

    @Test
    fun timestampAndInstantKeepExactNanosWithoutMillisecondRounding() {
        val raw = f.fields()
        assertEquals(
            version(raw),
            version(raw + ("updatedAt" to Timestamp(f.time.epochSecond, f.time.nano))),
        )
        assertNotEquals(version(raw), version(raw + ("updatedAt" to f.time.plusNanos(1))))
        assertNotEquals(version(raw), version(raw + ("updatedAt" to f.time.toEpochMilli())))
    }

    @Test
    fun missingNullLegacyIdAndRoleArePartOfRawFingerprint() {
        val raw = f.fields()
        for (other in
            listOf(
                raw - "id",
                raw + ("id" to null),
                raw + ("id" to f.target),
                raw + ("globalRole" to "moderator"),
            )) assertNotEquals(version(raw), version(other))
        assertNotEquals(version(emptyMap()), version(mapOf("newField" to null)))
    }

    @Test
    fun onlyThreeRoleFieldsAreExcludedFromPreservedState() {
        val before = version(f.fields())
        val after = version(f.after())
        assertEquals(before.preservedHash, after.preservedHash)
        assertNotEquals(before.fingerprint, after.fingerprint)
        for ((key, value) in
            mapOf(
                "requiresMultiFactorAuth" to true,
                "updatedAt" to f.time.plusNanos(1),
                "statusAcknowledgedAt" to null,
                "organizationMemberships" to emptyList<String>(),
                "displayName" to "changed",
                "email" to "new@example.invalid",
                "accountStatus" to "deactivated",
            )) {
            assertNotEquals(
                key,
                before.preservedHash,
                version(f.after() + (key to value)).preservedHash,
            )
        }
    }

    @Test
    fun nestedListsTypesAndMapKeysCannotAlias() {
        val variants =
            listOf(
                mapOf("a" to listOf(1, 2)),
                mapOf("a" to listOf(2, 1)),
                mapOf("a" to listOf("1", "2")),
                mapOf("a" to mapOf("1" to 2)),
                mapOf("a1" to 2),
            )
        assertEquals(variants.size, variants.map { version(it).fingerprint }.toSet().size)
    }

    @Test
    fun privatePreviewTruncationNeverTruncatesFingerprintOrSurrogatePair() {
        val name = "x".repeat(499) + "😀" + "tail"
        val a = PlatformRoleRecovery.snapshot(f.target, f.fields() + ("displayName" to name))
        val b =
            PlatformRoleRecovery.snapshot(f.target, f.fields() + ("displayName" to name + "change"))
        assertEquals("x".repeat(499) + "…", a.displayName)
        assertEquals(a.displayName, b.displayName)
        assertNotEquals(a.version, b.version)
        assertFalse(a.toString().contains("PRIVATE"))
    }

    @Test
    fun foreignCanonicalPathChangesBothDigests() {
        val first = version(f.fields())
        val other = PlatformRoleRecovery.snapshot("foreign", f.fields()).version
        assertNotEquals(first.fingerprint, other.fingerprint)
        assertNotEquals(first.preservedHash, other.preservedHash)
    }

    @Test
    fun malformedUnicodeOversizeDepthAndUnsupportedTypesFailClosed() {
        var deep: Any? = "leaf"
        repeat(22) { deep = listOf(deep) }
        for (value in
            listOf(
                "\uD800",
                "\uDC00",
                "x".repeat(1_048_577),
                Double.NaN,
                Double.POSITIVE_INFINITY,
                Float.NaN,
                Any(),
                List(4096) { 1 },
                deep,
                mapOf(7 to "bad-key"),
            )) {
            invalid { version(mapOf("field" to value)) }
        }
    }

    @Test
    fun futureRawTimeOutOfFirestoreRangeFailsClosed() {
        invalid { version(mapOf("time" to Instant.parse("+10000-01-01T00:00:00Z"))) }
    }

    @Test
    fun preparationBindsOwnerActionReasonAndSnapshotWithoutRawSecrets() {
        for (action in PlatformRoleAction.entries) {
            val p = f.prepared(action)
            PlatformRoleRecovery.validate(p)
            assertEquals(PlatformRolePhase.PREPARED, p.phase)
            assertEquals(PlatformRoleRecovery.accountHash(f.actor.uid), p.accountHash)
            assertEquals(PlatformRoleRecovery.hash("PRIVATE reason 😀"), p.reasonHash)
            assertFalse(p.toString().contains(f.actor.uid))
            assertFalse(p.toString().contains("PRIVATE"))
        }
    }

    @Test
    fun policyProjectionCannotRedirectVersionOrRole() {
        val snapshot = PlatformRoleRecovery.snapshot(f.target, f.fields())
        for (bad in
            listOf(
                snapshot.copy(target = snapshot.target.copy(targetId = "foreign")),
                snapshot.copy(target = snapshot.target.copy(role = "admin")),
            )) {
            invalid {
                PlatformRoleRecovery.prepared(
                    f.actor,
                    bad,
                    PlatformRoleAction.ASSIGN,
                    "reason",
                    PlatformRoleTargetAuth(f.target, true, false),
                    f.operation,
                )
            }
        }
    }

    @Test
    fun ownResponseIsBoundToOperationAccountTargetActionAndExactRawVersion() {
        val ack = f.acknowledged()
        PlatformRoleRecovery.validate(ack)
        for (bad in
            listOf(
                ack.copy(operationId = "0a0a0a0a-1111-4222-8333-444444444445"),
                ack.copy(accountHash = PlatformRoleRecovery.accountHash("foreign")),
                ack.copy(version = ack.version.copy(targetId = "other")),
                ack.copy(version = ack.version.copy(fingerprint = "f".repeat(64))),
                ack.copy(version = ack.version.copy(preservedHash = "f".repeat(64))),
                ack.copy(reasonHash = "f".repeat(64)),
                ack.copy(action = PlatformRoleAction.REMOVE),
                ack.copy(backend = "foreign-project"),
            )) invalid { PlatformRoleRecovery.validate(bad) }
    }

    @Test
    fun phaseAndCanonicalResponseDigestRejectGraftedOrModifiedReceipt() {
        val ack = f.acknowledged()
        val receipt = requireNotNull(ack.receipt)
        for (bad in
            listOf(
                ack.copy(phase = PlatformRolePhase.PREPARED),
                ack.copy(receipt = null),
                ack.copy(receipt = receipt.copy(responseHash = "a".repeat(64))),
                ack.copy(receipt = receipt.copy(wireTime = receipt.wireTime.plusMillis(1))),
                ack.copy(receipt = receipt.copy(wireTime = receipt.wireTime.plusNanos(1))),
            )) invalid { PlatformRoleRecovery.validate(bad) }
        try {
            PlatformRoleRecovery.receipt(f.prepared(), f.response(PlatformRoleAction.ASSIGN))
            fail()
        } catch (error: PlatformRoleException) {
            assertEquals(PlatformRoleFailure.UNCONFIRMED, error.failure)
        }
    }

    @Test
    fun matchingCurrentStateWithoutOwnResponseNeverConfirmsOrClears() {
        for (phase in listOf(PlatformRolePhase.PREPARED, PlatformRolePhase.DISPATCHED)) {
            val entry = f.prepared().copy(phase = phase)
            val observation = PlatformRoleRecovery.observation(entry, f.actor.uid, f.after())
            assertEquals(PlatformRoleObservation.OBSERVED_WITHOUT_RECEIPT, observation)
            assertFalse(observation.confirmed)
            assertFalse(observation.clearsPending)
        }
    }

    @Test
    fun ownAckWithCurrentChangedOrUnavailableStateKeepsCorrectEvidence() {
        val ack = f.acknowledged()
        assertEquals(
            PlatformRoleObservation.CONFIRMED_CURRENT,
            PlatformRoleRecovery.observation(ack, f.actor.uid, f.after()),
        )
        assertEquals(
            PlatformRoleObservation.CONFIRMED_CHANGED,
            PlatformRoleRecovery.observation(ack, f.actor.uid, f.fields()),
        )
        for (unavailable in listOf(null, mapOf("bad" to Any()))) {
            val outcome = PlatformRoleRecovery.observation(ack, f.actor.uid, unavailable)
            assertEquals(PlatformRoleObservation.CONFIRMED_UNAVAILABLE, outcome)
            assertTrue(outcome.confirmed)
            assertFalse(outcome.clearsPending)
        }
    }

    @Test
    fun profileChangesAndMissingActorOrCommitTimeDoNotMatchExpectedState() {
        val entry = f.acknowledged()
        for (fields in
            listOf(
                f.after() - "roleUpdatedAt",
                f.after() - "roleUpdatedBy",
                f.after() + ("roleUpdatedBy" to "another-actor"),
                f.after() + ("requiresMultiFactorAuth" to true),
                f.after() + ("statusAcknowledgedAt" to null),
                f.after() + ("roleUpdatedAt" to "2026-09-03"),
            )) {
            assertFalse(PlatformRoleRecovery.matches(entry, f.actor.uid, fields))
        }
        // Wire time is not the commit timestamp; exact equality between the two is not required.
        assertTrue(PlatformRoleRecovery.matches(entry, f.actor.uid, f.after()))
    }

    @Test
    fun abaRoleWithDifferentCommitVersionIsNotTheReviewedVersionOrOwnReceipt() {
        val raw = f.fields()
        val aba = raw + ("roleUpdatedAt" to f.time.plusSeconds(20))
        assertNotEquals(version(raw), version(aba))
        assertEquals(
            PlatformRoleObservation.UNCONFIRMED,
            PlatformRoleRecovery.observation(f.prepared(), f.actor.uid, aba),
        )
    }

    @Test
    fun wrongActorAndSelfBoundJournalCannotBeRecovered() {
        val entry = f.prepared()
        invalid {
            PlatformRoleRecovery.validate(
                entry.copy(accountHash = PlatformRoleRecovery.accountHash(f.target))
            )
        }
        try {
            PlatformRoleRecovery.observation(entry, "foreign", f.after())
            fail()
        } catch (error: PlatformRoleException) {
            assertEquals(PlatformRoleFailure.ACCESS, error.failure)
        }
        try {
            PlatformRoleRecovery.requireOwner(f.actor.copy(role = "admin"), entry)
            fail()
        } catch (error: PlatformRoleException) {
            assertEquals(PlatformRoleFailure.ACCESS, error.failure)
        }
    }
}
