package at.uac.android

import at.uac.android.feature.platformrolemanagement.*
import java.time.Instant
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class PlatformRoleJournalCodecTest {
    private val actor = "RAW-ACTOR-MUST-NOT-BE-SERIALIZED"
    private val secret = "Private reason/contact/token must not be on disk"

    private fun pending(target: String = "target-1", uid: String = actor) =
        PlatformRolePending(
            PlatformRoleRecovery.accountHash(uid),
            PlatformRoleVersion(target, "a".repeat(64), "b".repeat(64), "user"),
            PlatformRoleAction.ASSIGN,
            PlatformRoleRecovery.hash(secret),
            UUID.randomUUID().toString(),
            PlatformRolePhase.PREPARED,
        )

    private fun acknowledged(prepared: PlatformRolePending): PlatformRolePending {
        val dispatched = prepared.copy(phase = PlatformRolePhase.DISPATCHED)
        return dispatched.copy(
            phase = PlatformRolePhase.ACKNOWLEDGED,
            receipt =
                PlatformRoleRecovery.receipt(
                    dispatched,
                    mapOf(
                        "targetUserId" to dispatched.version.targetId,
                        "previousGlobalRole" to "user",
                        "newGlobalRole" to "admin",
                        "updatedAt" to "2026-09-03T13:00:00.123Z",
                    ),
                ),
        )
    }

    private fun denied(action: () -> Any?) {
        try {
            action()
            fail("Expected bounded journal rejection")
        } catch (error: PlatformRoleException) {
            assertEquals(PlatformRoleFailure.JOURNAL, error.failure)
        }
    }

    @Test
    fun phasesAndActualReceiptBindingRoundTripWithoutRawPrivateFields() {
        val prepared = pending()
        val entries =
            listOf(
                prepared,
                prepared.copy(phase = PlatformRolePhase.DISPATCHED),
                acknowledged(prepared),
            )
        entries.forEach { entry ->
            val bytes = PlatformRoleJournalCodec.encode(listOf(entry))
            assertEquals(listOf(entry), PlatformRoleJournalCodec.decode(bytes))
            val raw = bytes.toString(Charsets.ISO_8859_1)
            assertFalse(raw.contains(actor))
            assertFalse(raw.contains(secret))
            assertTrue(
                raw.contains(entry.version.targetId)
            ) // Explicit routing ID exception, not private display data.
        }
    }

    @Test
    fun sixteenLargestAcknowledgedTargetsFitAndSeventeenthNeverEvicts() {
        val entries =
            List(16) { index -> acknowledged(pending("$index".padStart(3, '0') + "界".repeat(125))) }
        val bytes = PlatformRoleJournalCodec.encode(entries)
        assertTrue(bytes.size <= 32_768)
        assertEquals(entries, PlatformRoleJournalCodec.decode(bytes))
        denied { PlatformRoleJournalCodec.encode(entries + pending("overflow")) }
    }

    @Test
    fun duplicateAccountTargetAndOperationAcrossAccountsAreDenied() {
        val first = pending()
        denied {
            PlatformRoleJournalCodec.encode(
                listOf(first, first.copy(operationId = UUID.randomUUID().toString()))
            )
        }
        denied {
            PlatformRoleJournalCodec.encode(
                listOf(
                    first,
                    pending("target-2", "second-actor").copy(operationId = first.operationId),
                )
            )
        }
        val second = pending("target-2")
        val valid = PlatformRoleJournalCodec.encode(listOf(first, second))
        val duplicateTarget =
            valid
                .toString(Charsets.ISO_8859_1)
                .replace("target-2", "target-1")
                .toByteArray(Charsets.ISO_8859_1)
        denied { PlatformRoleJournalCodec.decode(duplicateTarget) }
    }

    @Test
    fun malformedFramesVersionsTrailingBytesAndHugeLengthsFailClosed() {
        val bytes = PlatformRoleJournalCodec.encode(listOf(pending()))
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
            denied { PlatformRoleJournalCodec.decode(bad) }
        }
    }

    @Test
    fun corruptCompiledIdentityHeaderAndForeignBackendAreRejected() {
        val bytes = PlatformRoleJournalCodec.encode(listOf(pending()))
        denied {
            PlatformRoleJournalCodec.decode(
                bytes.copyOf().also {
                    it[9] = if (it[9] == 'a'.code.toByte()) 'b'.code.toByte() else 'a'.code.toByte()
                }
            )
        }
        for (backend in listOf("uac-android-test-20260903", "demo-other", "production")) {
            denied { PlatformRoleJournalCodec.encode(listOf(pending().copy(backend = backend))) }
        }
    }

    @Test
    fun corruptAccountIdsOperationsAndRoleCannotEnterLedger() {
        val entry = pending()
        for (bad in
            listOf(
                entry.copy(accountHash = actor),
                entry.copy(operationId = "bad"),
                entry.copy(version = entry.version.copy(previousRole = "owner")),
                entry.copy(version = entry.version.copy(targetId = "../foreign")),
                entry.copy(reasonHash = secret),
            )) {
            denied { PlatformRoleJournalCodec.encode(listOf(bad)) }
        }
    }

    @Test
    fun receiptCannotBeGraftedToAnotherOperationOrPhase() {
        val entry = acknowledged(pending())
        val receipt = requireNotNull(entry.receipt)
        denied {
            PlatformRoleJournalCodec.encode(
                listOf(entry.copy(operationId = UUID.randomUUID().toString()))
            )
        }
        denied {
            PlatformRoleJournalCodec.encode(
                listOf(entry.copy(phase = PlatformRolePhase.DISPATCHED))
            )
        }
        denied { PlatformRoleJournalCodec.encode(listOf(entry.copy(receipt = null))) }
        denied {
            PlatformRoleJournalCodec.encode(
                listOf(entry.copy(receipt = receipt.copy(requestHash = "f".repeat(64))))
            )
        }
    }

    @Test
    fun wireTimeIsLosslessMillisecondPrecisionNotSynthesizedServerTime() {
        val entry = acknowledged(pending())
        val receipt = requireNotNull(entry.receipt)
        val reloaded =
            PlatformRoleJournalCodec.decode(PlatformRoleJournalCodec.encode(listOf(entry))).single()
        assertEquals(Instant.parse("2026-09-03T13:00:00.123Z"), reloaded.receipt?.wireTime)
        denied {
            PlatformRoleJournalCodec.encode(
                listOf(entry.copy(receipt = receipt.copy(wireTime = receipt.wireTime.plusNanos(1))))
            )
        }
    }

    @Test
    fun otherAccountsRemainSeparateAndEmptyLedgerIsAnExplicitValidFrame() {
        val entries = listOf(pending("same-target"), pending("same-target", "other-actor"))
        assertEquals(
            entries,
            PlatformRoleJournalCodec.decode(PlatformRoleJournalCodec.encode(entries)),
        )
        assertEquals(
            emptyList<PlatformRolePending>(),
            PlatformRoleJournalCodec.decode(PlatformRoleJournalCodec.encode(emptyList())),
        )
    }
}
