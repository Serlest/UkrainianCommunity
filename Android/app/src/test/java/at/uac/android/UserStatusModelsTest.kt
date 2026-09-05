package at.uac.android

import at.uac.android.feature.moderation.ModerationSession
import at.uac.android.feature.userstatusmanagement.*
import com.google.firebase.Timestamp
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test

/** Pure synthetic contracts; this fixture is not an actual privileged SDK/TOTP session. */
internal object UserStatusUnitFixture {
    val actor = ModerationSession("synthetic-status-actor", 17, "admin", true)
    const val target = "synthetic-status-target"
    const val reason = "PRIVATE reason without durable plaintext"
    val now = Instant.parse("2026-09-03T10:00:00.123456789Z")
    val zone: ZoneId = ZoneId.of("Europe/Vienna")
    const val operation = "0a0a0a0a-1111-4222-8333-444444444444"

    fun fields(action: UserStatusAction = UserStatusAction.WARN): Map<String, Any?> =
        mapOf(
            "id" to target,
            "globalRole" to "user",
            "displayName" to "PRIVATE target name",
            "email" to "private-target@example.invalid",
            "accountStatus" to
                if (action == UserStatusAction.RESTORE) "bannedPermanent" else "active",
            "blockState" to if (action == UserStatusAction.RESTORE) "bannedPermanent" else "active",
            "isBlocked" to (action == UserStatusAction.RESTORE),
            "warningCount" to 2L,
            "statusReason" to "PRIVATE previous reason",
            "statusMessage" to "PRIVATE previous message",
            "statusUpdatedAt" to now.minusSeconds(10),
            "statusAcknowledgedAt" to now.minusSeconds(5),
            "statusUpdatedBy" to "synthetic-previous-actor",
            "banExpiresAt" to null,
            "updatedAt" to now.minusSeconds(10),
            "createdAt" to now.minusSeconds(100),
        )

    fun until(action: UserStatusAction): Instant? =
        if (action == UserStatusAction.SUSPEND) UserStatusContract.suspensionUntil(now, 7, zone)
        else null

    fun prepared(action: UserStatusAction = UserStatusAction.WARN) =
        UserStatusContract.prepared(
            actor,
            UserStatusContract.snapshot(target, fields(action)),
            action,
            reason,
            until(action),
            operation,
        )

    fun response(
        entry: UserStatusPending,
        count: Long = if (entry.action == UserStatusAction.WARN) 3 else 2,
    ): Map<String, Any?> =
        mapOf(
            "targetUserId" to target,
            "previousAccountStatus" to
                if (entry.action == UserStatusAction.RESTORE) "bannedPermanent" else "active",
            "newAccountStatus" to entry.action.status,
            "previousBlockState" to
                if (entry.action == UserStatusAction.RESTORE) "bannedPermanent" else "active",
            "newBlockState" to entry.action.status,
            "warningCount" to count,
            "banExpiresAt" to until(entry.action)?.toString(),
            "updatedAt" to now.minusSeconds(1).toEpochMilli().let(Instant::ofEpochMilli).toString(),
        )

    fun acknowledged(
        action: UserStatusAction = UserStatusAction.WARN,
        count: Long = if (action == UserStatusAction.WARN) 3 else 2,
    ): UserStatusPending {
        val dispatched = prepared(action).copy(phase = UserStatusPhase.DISPATCHED)
        return dispatched.copy(
            phase = UserStatusPhase.ACKNOWLEDGED,
            receipt = UserStatusContract.receipt(dispatched, response(dispatched, count)),
        )
    }

    fun after(
        entry: UserStatusPending,
        count: Long = if (entry.action == UserStatusAction.WARN) 3 else 2,
    ): Map<String, Any?> =
        fields(entry.action) +
            mapOf(
                "accountStatus" to entry.action.status,
                "blockState" to entry.action.status,
                "warningCount" to count,
                "banExpiresAt" to until(entry.action),
                "isBlocked" to entry.action.blocked,
                "statusReason" to reason,
                "statusMessage" to entry.action.messagePrefix + reason,
                "statusUpdatedAt" to now.plusSeconds(1),
                "updatedAt" to now.plusSeconds(1),
                "statusUpdatedBy" to actor.uid,
                "statusAcknowledgedAt" to null,
            )
}

class UserStatusModelsTest {
    private val f = UserStatusUnitFixture

    private fun invalid(action: () -> Any?) {
        assertEquals(
            UserStatusFailure.INVALID,
            assertThrows(UserStatusException::class.java) { action() }.failure,
        )
    }

    @Test
    fun exactFiveCallablePayloadsRequireAReason() {
        assertEquals(
            setOf("warnUser", "suspendUser", "banUser", "deactivateUser", "restoreUser"),
            UserStatusAction.entries.map { it.callable }.toSet(),
        )
        for (action in UserStatusAction.entries) {
            val payload =
                UserStatusContract.payload(
                    f.target,
                    action,
                    "\uFEFF ${f.reason} \u00A0",
                    f.until(action),
                )
            assertEquals(f.target, payload["targetUserId"])
            assertEquals(f.reason, payload["reason"])
            assertEquals(
                if (action == UserStatusAction.SUSPEND) setOf("targetUserId", "reason", "until")
                else setOf("targetUserId", "reason"),
                payload.keys,
            )
            invalid {
                UserStatusContract.payload(f.target, action, " \n\uFEFF\u00A0", f.until(action))
            }
        }
    }

    @Test
    fun unsafeReasonAndPayloadShapesFailClosed() {
        for (text in listOf("bad\u0000reason", "bad\uD800", "a".repeat(65_537))) invalid {
            UserStatusContract.payload(f.target, UserStatusAction.WARN, text, null)
        }
        invalid { UserStatusContract.payload("users/other", UserStatusAction.WARN, f.reason, null) }
        invalid { UserStatusContract.payload(f.target, UserStatusAction.SUSPEND, f.reason, null) }
        invalid { UserStatusContract.payload(f.target, UserStatusAction.BAN, f.reason, f.now) }
        invalid { UserStatusContract.payload(f.target, UserStatusAction.SUSPEND, f.reason, f.now) }
    }

    @Test
    fun suspensionDaysAreCalendarDaysAcrossBothViennaDstTransitions() {
        assertEquals(7, UserStatusContract.DEFAULT_SUSPENSION_DAYS)
        assertEquals(listOf(1, 7, 14, 30), UserStatusContract.suspensionOptions)
        val spring = Instant.parse("2026-03-28T12:00:00.123Z")
        val autumn = Instant.parse("2026-10-24T12:00:00.123Z")
        assertEquals(
            23L,
            Duration.between(spring, UserStatusContract.suspensionUntil(spring, 1, f.zone))
                .toHours(),
        )
        assertEquals(
            25L,
            Duration.between(autumn, UserStatusContract.suspensionUntil(autumn, 1, f.zone))
                .toHours(),
        )
        for (days in listOf(0, 2, 6, 8, 365)) invalid {
            UserStatusContract.suspensionUntil(f.now, days, f.zone)
        }
        assertEquals(
            f.now.atZone(f.zone).plusDays(7).toInstant().toEpochMilli(),
            UserStatusContract.suspensionUntil(f.now, zoneId = f.zone).toEpochMilli(),
        )
        assertEquals(0, UserStatusContract.suspensionUntil(f.now, 7, f.zone).nano % 1_000_000)
    }

    @Test
    fun strictRoleSelfAndIosActionRestrictions() {
        val current = UserStatusContract.snapshot(f.target, f.fields())
        assertEquals(
            listOf(
                UserStatusAction.WARN,
                UserStatusAction.SUSPEND,
                UserStatusAction.BAN,
                UserStatusAction.DEACTIVATE,
            ),
            UserStatusContract.availableActions(f.actor, current),
        )
        assertTrue(
            UserStatusContract.availableActions(f.actor.copy(uid = f.target), current).isEmpty()
        )
        assertTrue(
            UserStatusContract.availableActions(f.actor.copy(ready = false), current).isEmpty()
        )
        assertTrue(
            UserStatusContract.availableActions(f.actor.copy(role = "user"), current).isEmpty()
        )
        assertTrue(
            UserStatusContract.availableActions(f.actor, current.copy(role = "owner")).isEmpty()
        )
        assertTrue(
            UserStatusContract.availableActions(f.actor, current.copy(role = "admin")).isEmpty()
        )
        assertFalse(
            UserStatusContract.availableActions(
                    f.actor.copy(role = "owner"),
                    current.copy(role = "admin"),
                )
                .isEmpty()
        )
        assertTrue(
            UserStatusContract.availableActions(f.actor, current.copy(role = "malformed")).isEmpty()
        )
        assertFalse(
            UserStatusContract.availableActions(f.actor, current.copy(blockState = "warned"))
                .contains(UserStatusAction.WARN)
        )
        assertEquals(
            listOf(UserStatusAction.RESTORE, UserStatusAction.BAN, UserStatusAction.DEACTIVATE),
            UserStatusContract.availableActions(
                f.actor,
                current.copy(blockState = "suspendedUntil"),
            ),
        )
        for (status in listOf("bannedPermanent", "deactivated")) assertEquals(
            listOf(UserStatusAction.RESTORE),
            UserStatusContract.availableActions(f.actor, current.copy(blockState = status)),
        )
    }

    @Test
    fun exactRawFingerprintIncludesEveryAuthorityAndNoticeField() {
        val base = f.fields()
        val original = UserStatusContract.snapshot(f.target, base).version
        val alternatives =
            mapOf<String, Any?>(
                "globalRole" to "admin",
                "warningCount" to 3L,
                "accountStatus" to "warned",
                "blockState" to "warned",
                "statusReason" to " ${base["statusReason"]}",
                "statusMessage" to "new message",
                "banExpiresAt" to f.now.plusSeconds(10),
                "statusUpdatedAt" to f.now.minusSeconds(10).plusNanos(1),
                "statusAcknowledgedAt" to f.now.minusSeconds(5).plusNanos(1),
                "statusUpdatedBy" to "other-actor",
            )
        for ((key, value) in alternatives) assertNotEquals(
            key,
            original.fingerprint,
            UserStatusContract.snapshot(f.target, base + (key to value)).version.fingerprint,
        )
        assertEquals(
            original.fingerprint,
            UserStatusContract.snapshot(f.target, base.toList().reversed().toMap())
                .version
                .fingerprint,
        )
    }

    @Test
    fun confirmationLabelsUseOnlyTheSameRawSnapshotAndCanonicalTarget() {
        val fields =
            f.fields() +
                mapOf(
                    "id" to "legacy-other",
                    "displayName" to "  PRIVATE fresh name  ",
                    "fullName" to "PRIVATE fallback name",
                    "email" to " PRIVATE-fresh@example.invalid ",
                )
        val snapshot = UserStatusContract.snapshot(f.target, fields)
        assertEquals("  PRIVATE fresh name  ", snapshot.displayName)
        assertEquals(" PRIVATE-fresh@example.invalid ", snapshot.email)
        assertEquals(f.target, snapshot.version.targetId)
        val fallback = UserStatusContract.snapshot(f.target, fields + ("displayName" to " \t "))
        assertEquals("PRIVATE fallback name", fallback.displayName)
        val payload =
            UserStatusContract.payload(
                snapshot.version.targetId,
                UserStatusAction.WARN,
                f.reason,
                null,
            )
        assertEquals(mapOf("targetUserId" to f.target, "reason" to f.reason), payload)
        assertFalse(snapshot.toString().contains(snapshot.displayName!!))
        assertFalse(snapshot.toString().contains(snapshot.email!!))
    }

    @Test
    fun absentOptionalLabelsAndLegacyNonTextLabelsDoNotInventAnIdentity() {
        val absent =
            UserStatusContract.snapshot(
                f.target,
                f.fields() - setOf("displayName", "fullName", "email"),
            )
        assertNull(absent.displayName)
        assertNull(absent.email)
        val nonText =
            UserStatusContract.snapshot(
                f.target,
                f.fields() +
                    mapOf(
                        "displayName" to 7L,
                        "fullName" to null,
                        "email" to false,
                    ),
            )
        assertNull(nonText.displayName)
        assertNull(nonText.email)
        assertEquals(f.target, nonText.version.targetId)
        assertNotEquals(absent.version.fingerprint, nonText.version.fingerprint)
        val withoutNewConstructorArguments =
            UserStatusSnapshot(
                absent.version,
                absent.role,
                absent.accountStatus,
                absent.blockState,
                absent.warningCount,
                absent.statusReason,
                absent.statusMessage,
                absent.banExpiresAt,
                absent.statusUpdatedAt,
                absent.statusAcknowledgedAt,
                absent.statusUpdatedBy,
            )
        assertNull(withoutNewConstructorArguments.displayName)
        assertNull(withoutNewConstructorArguments.email)
    }

    @Test
    fun labelChangesInvalidateExactReviewedVersionEvenWhenTheShownLabelIsUnchanged() {
        val fields = f.fields() + ("fullName" to "PRIVATE unused fallback")
        val original = UserStatusContract.snapshot(f.target, fields)
        for ((key, value) in
            mapOf(
                "displayName" to "PRIVATE changed name",
                "fullName" to "PRIVATE changed fallback",
                "email" to "changed@example.invalid",
            )) {
            val next = UserStatusContract.snapshot(f.target, fields + (key to value))
            assertEquals(f.target, next.version.targetId)
            assertNotEquals(key, original.version.fingerprint, next.version.fingerprint)
            assertNotEquals(key, original.version.preservedHash, next.version.preservedHash)
            assertEquals(original.version.previousStateHash, next.version.previousStateHash)
            if (key == "fullName") assertEquals(original.displayName, next.displayName)
        }
    }

    @Test
    fun displayPreviewLimitNeverTruncatesRawFingerprintOrContactHash() {
        val prefix = "x".repeat(500)
        val fields = f.fields() + mapOf("displayName" to prefix + "a", "email" to prefix + "a")
        val first = UserStatusContract.snapshot(f.target, fields)
        val changed =
            UserStatusContract.snapshot(
                f.target,
                fields + mapOf("displayName" to prefix + "b", "email" to prefix + "b"),
            )
        assertEquals(prefix + "…", first.displayName)
        assertEquals(prefix + "…", first.email)
        assertEquals(first.displayName, changed.displayName)
        assertEquals(first.email, changed.email)
        assertNotEquals(first.version.fingerprint, changed.version.fingerprint)
        assertNotEquals(first.version.preservedHash, changed.version.preservedHash)
        assertEquals(prefix + "a", fields["displayName"])
        assertEquals(prefix + "a", fields["email"])
        assertFalse(first.toString().contains(prefix))
    }

    @Test
    fun displayPreviewNeverCutsASupplementaryUnicodeCharacterInHalf() {
        val raw = "x".repeat(499) + "😀" + "suffix"
        val fields = f.fields() + mapOf("displayName" to raw, "email" to raw)
        val snapshot = UserStatusContract.snapshot(f.target, fields)
        assertEquals("x".repeat(499) + "…", snapshot.displayName)
        assertEquals(snapshot.displayName, snapshot.email)
        assertEquals(raw, fields["displayName"])
        val changed =
            UserStatusContract.snapshot(f.target, fields + ("displayName" to raw + "changed"))
        assertEquals(snapshot.displayName, changed.displayName)
        assertNotEquals(snapshot.version.fingerprint, changed.version.fingerprint)
    }

    @Test
    fun timestampsKeepNanosecondsAndDoNotUseDisplayNormalization() {
        val base = f.fields()
        val time = f.now.minusSeconds(10)
        val timestamp = Timestamp(time.epochSecond, time.nano)
        val native = UserStatusContract.snapshot(f.target, base + ("statusUpdatedAt" to timestamp))
        assertEquals(time, native.statusUpdatedAt)
        assertEquals(UserStatusContract.snapshot(f.target, base).version, native.version)
        val raw = "  exact reason  "
        assertEquals(
            raw,
            UserStatusContract.snapshot(f.target, base + ("statusReason" to raw)).statusReason,
        )
    }

    @Test
    fun knownLegacyAliasesNormalizeOnlyAfterTheExactRawFingerprint() {
        val first =
            UserStatusContract.snapshot(
                f.target,
                f.fields() +
                    mapOf("accountStatus" to "temporarilyBanned", "blockState" to "blocked"),
            )
        val second =
            UserStatusContract.snapshot(
                f.target,
                f.fields() +
                    mapOf("accountStatus" to "suspendedUntil", "blockState" to "suspendedUntil"),
            )
        assertEquals(first.accountStatus, second.accountStatus)
        assertEquals(first.blockState, second.blockState)
        assertNotEquals(first.version.fingerprint, second.version.fingerprint)
        assertEquals(
            "user",
            UserStatusContract.snapshot(f.target, f.fields() + ("globalRole" to "topAdmin")).role,
        )
    }

    @Test
    fun malformedAuthorityCountsAndTimesNeverBecomeActiveDefaults() {
        val bad =
            listOf<Pair<String, Any?>>(
                "globalRole" to "superuser",
                "globalRole" to null,
                "accountStatus" to null,
                "accountStatus" to true,
                "blockState" to 4L,
                "isBlocked" to "false",
                "warningCount" to null,
                "warningCount" to -1L,
                "warningCount" to 1.5,
                "warningCount" to Double.NaN,
                "warningCount" to Double.POSITIVE_INFINITY,
                "warningCount" to (UserStatusContract.MAX_SAFE_COUNT + 1),
                "warningCount" to "2",
                "statusReason" to false,
                "statusMessage" to listOf("text"),
                "statusUpdatedBy" to "other/path",
                "statusUpdatedAt" to "2026-09-03T00:00:00Z",
                "statusAcknowledgedAt" to 3L,
                "banExpiresAt" to Instant.MAX,
            )
        for ((key, value) in bad) invalid {
            UserStatusContract.snapshot(f.target, f.fields() + (key to value))
        }
        invalid { UserStatusContract.snapshot(f.target, f.fields() + ("id" to 9L)) }
    }

    @Test
    fun missingOrMismatchedLegacyStoredIdNeverRedirectsTheCanonicalTarget() {
        val original = UserStatusContract.snapshot(f.target, f.fields())
        for (fields in listOf(f.fields() - "id", f.fields() + ("id" to "legacy-other"))) {
            val snapshot = UserStatusContract.snapshot(f.target, fields)
            assertEquals(f.target, snapshot.version.targetId)
            assertNotEquals(original.version.fingerprint, snapshot.version.fingerprint)
            val entry =
                UserStatusContract.prepared(
                        f.actor,
                        snapshot,
                        UserStatusAction.WARN,
                        f.reason,
                        null,
                        f.operation,
                    )
                    .copy(phase = UserStatusPhase.DISPATCHED)
            assertEquals(
                f.target,
                UserStatusContract.payload(entry.version.targetId, entry.action, f.reason, null)[
                        "targetUserId"],
            )
            val receipt = UserStatusContract.receipt(entry, f.response(entry))
            val acknowledged = entry.copy(phase = UserStatusPhase.ACKNOWLEDGED, receipt = receipt)
            val after =
                if (fields.containsKey("id")) f.after(entry) + ("id" to fields["id"])
                else f.after(entry) - "id"
            assertTrue(UserStatusContract.matches(acknowledged, f.actor.uid, after))
            assertEquals(
                UserStatusFailure.UNCONFIRMED,
                assertThrows(UserStatusException::class.java) {
                        UserStatusContract.receipt(
                            entry,
                            f.response(entry) + ("targetUserId" to "legacy-other"),
                        )
                    }
                    .failure,
            )
        }
    }

    @Test
    fun rawHashRejectsUnboundedNestedAndUnsupportedValues() {
        var nested: Any? = "leaf"
        repeat(25) { nested = listOf(nested) }
        for (value in
            listOf(
                nested,
                Any(),
                "\uDC00",
                "x".repeat(1_048_577),
                List(4097) { 1L },
                mapOf(1 to "bad key"),
            )) invalid {
            UserStatusContract.snapshot(f.target, f.fields() + ("extra" to value))
        }
        invalid {
            UserStatusContract.snapshot(
                f.target,
                f.fields() +
                    mapOf("large1" to "x".repeat(600_000), "large2" to "x".repeat(600_000)),
            )
        }
    }

    @Test
    fun sameNumericValueKeepsFirestoreWireTypeInFingerprint() {
        val integer = UserStatusContract.snapshot(f.target, f.fields())
        val number = UserStatusContract.snapshot(f.target, f.fields() + ("warningCount" to 2.0))
        assertEquals(integer.warningCount, number.warningCount)
        assertNotEquals(integer.version.fingerprint, number.version.fingerprint)
    }

    @Test
    fun warningOverflowIsNotDispatched() {
        val snapshot =
            UserStatusContract.snapshot(
                f.target,
                f.fields() + ("warningCount" to UserStatusContract.MAX_SAFE_COUNT),
            )
        invalid {
            UserStatusContract.prepared(
                f.actor,
                snapshot,
                UserStatusAction.WARN,
                f.reason,
                null,
                f.operation,
            )
        }
    }

    @Test
    fun exactFiveValidatedReceiptsMatchServerFields() {
        for (action in UserStatusAction.entries) {
            val entry = f.acknowledged(action)
            UserStatusContract.validate(entry)
            assertTrue(UserStatusContract.matches(entry, f.actor.uid, f.after(entry)))
            assertEquals(
                UserStatusObservation.CONFIRMED_CURRENT,
                UserStatusContract.observation(entry, f.actor.uid, f.after(entry)),
            )
        }
    }

    @Test
    fun receiptUsesActualServerPreviousAndCountDespiteNoCas() {
        val pending = f.prepared().copy(phase = UserStatusPhase.DISPATCHED)
        val receipt =
            UserStatusContract.receipt(
                pending,
                f.response(pending, 9) +
                    mapOf(
                        "previousAccountStatus" to "bannedPermanent",
                        "previousBlockState" to "bannedPermanent",
                    ),
            )
        assertNotEquals(pending.version.previousStateHash, receipt.previousStateHash)
        assertNotEquals(pending.desiredStateHash, receipt.newStateHash)
        val acknowledged = pending.copy(phase = UserStatusPhase.ACKNOWLEDGED, receipt = receipt)
        assertTrue(UserStatusContract.matches(acknowledged, f.actor.uid, f.after(acknowledged, 9)))
        assertFalse(UserStatusContract.matches(acknowledged, f.actor.uid, f.after(acknowledged, 3)))
    }

    @Test
    fun responseWireTimeIsNotComparedWithTheServerCommitTimestamp() {
        val entry = f.acknowledged()
        assertNotEquals(entry.receipt!!.wireTime, f.after(entry)["statusUpdatedAt"])
        assertTrue(UserStatusContract.matches(entry, f.actor.uid, f.after(entry)))
    }

    @Test
    fun matchingStateWithoutReceiptNeverProvesOwnOperationOrClearsPending() {
        val entry = f.prepared().copy(phase = UserStatusPhase.DISPATCHED)
        val outcome = UserStatusContract.observation(entry, f.actor.uid, f.after(entry))
        assertEquals(UserStatusObservation.OBSERVED_WITHOUT_RECEIPT, outcome)
        assertFalse(outcome.confirmed)
        assertFalse(outcome.clearsPending)
    }

    @Test
    fun laterRoleAcknowledgementActorTextOrStatusChangesPreserveOwnAcceptanceOnly() {
        val entry = f.acknowledged()
        for ((key, value) in
            mapOf<String, Any?>(
                "globalRole" to "owner",
                "statusAcknowledgedAt" to f.now.plusSeconds(2),
                "statusUpdatedBy" to "other-actor",
                "statusReason" to "other reason",
                "statusMessage" to "other message",
                "accountStatus" to "bannedPermanent",
                "warningCount" to 50L,
                "email" to "changed@example.invalid",
            )) assertEquals(
            key,
            UserStatusObservation.CONFIRMED_CHANGED,
            UserStatusContract.observation(entry, f.actor.uid, f.after(entry) + (key to value)),
        )
    }

    @Test
    fun acknowledgedUnavailableIsConfirmedButRetainsRecovery() {
        val outcome = UserStatusContract.observation(f.acknowledged(), f.actor.uid, null)
        assertEquals(UserStatusObservation.CONFIRMED_UNAVAILABLE, outcome)
        assertTrue(outcome.confirmed)
        assertFalse(outcome.clearsPending)
        assertEquals(
            UserStatusObservation.UNAVAILABLE,
            UserStatusContract.observation(f.prepared(), f.actor.uid, null),
        )
    }

    @Test
    fun malformedReadbackIsUnavailableAndCannotBeClaimedByAnotherActor() {
        val entry = f.acknowledged()
        val malformed = f.after(entry) + ("warningCount" to "wrong-type")
        assertEquals(
            UserStatusObservation.CONFIRMED_UNAVAILABLE,
            UserStatusContract.observation(entry, f.actor.uid, malformed),
        )
        assertEquals(
            UserStatusObservation.UNAVAILABLE,
            UserStatusContract.observation(f.prepared(), f.actor.uid, malformed),
        )
        assertEquals(
            UserStatusFailure.ACCESS,
            assertThrows(UserStatusException::class.java) {
                    UserStatusContract.observation(entry, "other-actor", f.after(entry))
                }
                .failure,
        )
    }

    @Test
    fun malformedReceiptsRemainUnconfirmed() {
        val entry = f.prepared().copy(phase = UserStatusPhase.DISPATCHED)
        val bad =
            listOf<Pair<String, Any?>>(
                "targetUserId" to "other",
                "previousAccountStatus" to "unknown",
                "previousBlockState" to "blocked",
                "newAccountStatus" to "active",
                "newBlockState" to "active",
                "warningCount" to 0L,
                "warningCount" to -1L,
                "warningCount" to 1.25,
                "warningCount" to Double.NaN,
                "banExpiresAt" to "2026-10-01T00:00:00Z",
                "updatedAt" to f.now.toString(),
                "updatedAt" to "bad",
            )
        for ((key, value) in bad) assertEquals(
            key,
            UserStatusFailure.UNCONFIRMED,
            assertThrows(UserStatusException::class.java) {
                    UserStatusContract.receipt(entry, f.response(entry) + (key to value))
                }
                .failure,
        )
        for (value in
            listOf(
                null,
                emptyMap<String, Any?>(),
                f.response(entry) + ("extra" to true),
                f.response(entry) - "previousAccountStatus",
            )) assertEquals(
            UserStatusFailure.UNCONFIRMED,
            assertThrows(UserStatusException::class.java) {
                    UserStatusContract.receipt(entry, value)
                }
                .failure,
        )
    }

    @Test
    fun suspensionReceiptMustMatchTheActualRequestedUntil() {
        val entry = f.prepared(UserStatusAction.SUSPEND).copy(phase = UserStatusPhase.DISPATCHED)
        for (value in listOf(null, f.until(entry.action)!!.plusSeconds(1).toString())) assertEquals(
            UserStatusFailure.UNCONFIRMED,
            assertThrows(UserStatusException::class.java) {
                    UserStatusContract.receipt(entry, f.response(entry) + ("banExpiresAt" to value))
                }
                .failure,
        )
    }

    @Test
    fun hashOnlyReceiptCannotBeGraftedOntoAnotherOperationActorReasonOrVersion() {
        val entry = f.acknowledged()
        for (bad in
            listOf(
                entry.copy(operationId = "0a0a0a0a-1111-4222-8333-555555555555"),
                entry.copy(accountHash = UserStatusContract.accountHash("other-actor")),
                entry.copy(reasonHash = UserStatusContract.hash("other")),
                entry.copy(
                    version = entry.version.copy(fingerprint = UserStatusContract.hash("changed"))
                ),
                entry.copy(backend = "demo-other"),
                entry.copy(phase = UserStatusPhase.DISPATCHED),
                entry.copy(receipt = null),
            )) invalid { UserStatusContract.validate(bad) }
    }

    @Test
    fun diagnosticsNeverExposePendingSensitiveFields() {
        val snapshot = UserStatusContract.snapshot(f.target, f.fields())
        val entry = f.acknowledged()
        val output =
            listOf(snapshot, snapshot.version, entry, entry.receipt, f.actor).joinToString()
        for (privateValue in
            listOf(
                f.target,
                f.reason,
                f.actor.uid,
                "PRIVATE target name",
                "private-target@example.invalid",
            )) assertFalse(output.contains(privateValue))
    }
}
