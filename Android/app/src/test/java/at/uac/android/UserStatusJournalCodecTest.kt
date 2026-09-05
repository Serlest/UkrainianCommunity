package at.uac.android

import at.uac.android.feature.userstatusmanagement.*
import java.time.Instant
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class UserStatusJournalCodecTest {
    private val actor = "RAW-ACTOR-MUST-NOT-BE-SERIALIZED"
    private val secret = "Private reason/contact/token must not be on disk"

    private fun pending(target: String = "target-1", uid: String = actor) =
        UserStatusPending(
            UserStatusContract.accountHash(uid),
            UserStatusVersion(target, "a".repeat(64), "b".repeat(64), "c".repeat(64)),
            UserStatusAction.WARN,
            UserStatusContract.hash(secret),
            UserStatusContract.hash(UserStatusAction.WARN.messagePrefix + secret),
            "d".repeat(64),
            UserStatusContract.untilHash(null),
            UUID.randomUUID().toString(),
            "owner",
            UserStatusPhase.PREPARED,
        )

    private fun acknowledged(prepared: UserStatusPending): UserStatusPending {
        val dispatched = prepared.copy(phase = UserStatusPhase.DISPATCHED)
        return dispatched.copy(
            phase = UserStatusPhase.ACKNOWLEDGED,
            receipt =
                UserStatusContract.receipt(
                    dispatched,
                    mapOf(
                        "targetUserId" to dispatched.version.targetId,
                        "previousAccountStatus" to "active",
                        "previousBlockState" to "active",
                        "newAccountStatus" to "warned",
                        "newBlockState" to "warned",
                        "warningCount" to 3,
                        "banExpiresAt" to null,
                        "updatedAt" to "2026-09-03T13:00:00.123Z",
                    ),
                ),
        )
    }

    private fun denied(action: () -> Any?) {
        try {
            action()
            fail("Expected bounded journal rejection")
        } catch (error: UserStatusException) {
            assertEquals(UserStatusFailure.JOURNAL, error.failure)
        }
    }

    @Test
    fun phasesAndActualReceiptBindingRoundTripWithoutRawPrivateFields() {
        val prepared = pending()
        val entries =
            listOf(
                prepared,
                prepared.copy(phase = UserStatusPhase.DISPATCHED),
                acknowledged(prepared),
            )
        entries.forEach { entry ->
            val bytes = UserStatusJournalCodec.encode(listOf(entry))
            assertEquals(listOf(entry), UserStatusJournalCodec.decode(bytes))
            val raw = bytes.toString(Charsets.ISO_8859_1)
            assertFalse(raw.contains(actor))
            assertFalse(raw.contains(secret))
            assertFalse(raw.contains(UserStatusAction.WARN.messagePrefix))
            assertTrue(
                raw.contains(entry.version.targetId)
            ) // Explicit routing ID exception, not private display data.
        }
    }

    @Test
    fun sixteenLargestAcknowledgedTargetsFitAndSeventeenthNeverEvicts() {
        val entries =
            List(16) { index -> acknowledged(pending("$index".padStart(3, '0') + "界".repeat(125))) }
        val bytes = UserStatusJournalCodec.encode(entries)
        assertTrue(bytes.size <= 32_768)
        assertEquals(entries, UserStatusJournalCodec.decode(bytes))
        denied { UserStatusJournalCodec.encode(entries + pending("overflow")) }
    }

    @Test
    fun duplicateAccountTargetAndOperationAcrossAccountsAreDenied() {
        val first = pending()
        denied {
            UserStatusJournalCodec.encode(
                listOf(first, first.copy(operationId = UUID.randomUUID().toString()))
            )
        }
        denied {
            UserStatusJournalCodec.encode(
                listOf(
                    first,
                    pending("target-2", "second-actor").copy(operationId = first.operationId),
                )
            )
        }
        val second = pending("target-2")
        val valid = UserStatusJournalCodec.encode(listOf(first, second))
        val duplicateTarget =
            valid
                .toString(Charsets.ISO_8859_1)
                .replace("target-2", "target-1")
                .toByteArray(Charsets.ISO_8859_1)
        denied { UserStatusJournalCodec.decode(duplicateTarget) }
    }

    @Test
    fun malformedFramesVersionsTrailingBytesAndHugeLengthsFailClosed() {
        val bytes = UserStatusJournalCodec.encode(listOf(pending()))
        for (bad in
            listOf(
                byteArrayOf(),
                byteArrayOf(1, 2),
                bytes.copyOf(15),
                bytes + 0,
                bytes.copyOf().also { it[4] = 99 },
                bytes.copyOf().also { it[5] = 127 },
                ByteArray(32_769),
            )) {
            denied { UserStatusJournalCodec.decode(bad) }
        }
    }

    @Test
    fun corruptCompiledIdentityHeaderAndForeignBackendAreRejected() {
        val bytes = UserStatusJournalCodec.encode(listOf(pending()))
        denied {
            UserStatusJournalCodec.decode(
                bytes.copyOf().also {
                    it[9] = if (it[9] == 'a'.code.toByte()) 'b'.code.toByte() else 'a'.code.toByte()
                }
            )
        }
        for (backend in listOf("uac-android-test-20260903", "demo-other", "production")) {
            denied { UserStatusJournalCodec.encode(listOf(pending().copy(backend = backend))) }
        }
    }

    @Test
    fun corruptAccountIdsOperationsAndRoleCannotEnterLedger() {
        val entry = pending()
        for (bad in
            listOf(
                entry.copy(accountHash = actor),
                entry.copy(operationId = "bad"),
                entry.copy(issuedRole = "user"),
                entry.copy(version = entry.version.copy(targetId = "../foreign")),
                entry.copy(reasonHash = secret),
            )) {
            denied { UserStatusJournalCodec.encode(listOf(bad)) }
        }
    }

    @Test
    fun receiptCannotBeGraftedToAnotherOperationOrPhase() {
        val entry = acknowledged(pending())
        val receipt = requireNotNull(entry.receipt)
        denied {
            UserStatusJournalCodec.encode(
                listOf(entry.copy(operationId = UUID.randomUUID().toString()))
            )
        }
        denied {
            UserStatusJournalCodec.encode(listOf(entry.copy(phase = UserStatusPhase.DISPATCHED)))
        }
        denied { UserStatusJournalCodec.encode(listOf(entry.copy(receipt = null))) }
        denied {
            UserStatusJournalCodec.encode(
                listOf(entry.copy(receipt = receipt.copy(requestHash = "f".repeat(64))))
            )
        }
    }

    @Test
    fun wireTimeIsLosslessMillisecondPrecisionNotSynthesizedServerTime() {
        val entry = acknowledged(pending())
        val receipt = requireNotNull(entry.receipt)
        val reloaded =
            UserStatusJournalCodec.decode(UserStatusJournalCodec.encode(listOf(entry))).single()
        assertEquals(Instant.parse("2026-09-03T13:00:00.123Z"), reloaded.receipt?.wireTime)
        denied {
            UserStatusJournalCodec.encode(
                listOf(entry.copy(receipt = receipt.copy(wireTime = receipt.wireTime.plusNanos(1))))
            )
        }
    }

    @Test
    fun otherAccountsRemainSeparateAndEmptyLedgerIsAnExplicitValidFrame() {
        val entries = listOf(pending("same-target"), pending("same-target", "other-actor"))
        assertEquals(entries, UserStatusJournalCodec.decode(UserStatusJournalCodec.encode(entries)))
        assertEquals(
            emptyList<UserStatusPending>(),
            UserStatusJournalCodec.decode(UserStatusJournalCodec.encode(emptyList())),
        )
    }
}
