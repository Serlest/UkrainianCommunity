package at.uac.android

import at.uac.android.feature.feedback.FeedbackAudience
import at.uac.android.feature.feedbackdeletion.*
import at.uac.android.feature.moderation.ModerationSession
import at.uac.android.feature.platformrolemanagement.PlatformRoleJournalCodec
import java.time.Instant
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class FeedbackDeletionJournalCodecTest {
    private val actor = "PRIVATE-ACTOR-ID"
    private val secret = "PRIVATE SUBJECT MESSAGE CONTACT"

    private fun pending(target: String = "target-1", uid: String = actor) =
        FeedbackDeletionRecovery.prepared(
            ModerationSession(uid, 1, "owner", true),
            FeedbackAudience.MANAGEMENT,
            FeedbackDeletionRecovery.snapshot(
                target,
                mapOf(
                    "userId" to "PRIVATE-AUTHOR",
                    "userDisplayName" to secret,
                    "subject" to secret,
                    "message" to secret,
                    "type" to "question",
                    "status" to "open",
                    "createdAt" to Instant.parse("2026-09-03T16:00:00.123456789Z"),
                ),
            ),
            UUID.randomUUID().toString(),
        )

    private fun ack(prepared: FeedbackDeletionPending): FeedbackDeletionPending {
        val dispatched = prepared.copy(phase = FeedbackDeletionPhase.DISPATCHED)
        return dispatched.copy(
            phase = FeedbackDeletionPhase.ACKNOWLEDGED,
            receipt = FeedbackDeletionRecovery.receipt(dispatched, mapOf("deletedCount" to 1)),
        )
    }

    private fun denied(block: () -> Any?) {
        val error = runCatching(block).exceptionOrNull()
        assertTrue(error is FeedbackDeletionException)
        assertEquals(FeedbackDeletionFailure.JOURNAL, (error as FeedbackDeletionException).failure)
    }

    @Test
    fun everyPhaseRoundTripsWithoutPrivateRawFields() {
        val prepared = pending()
        for (entry in
            listOf(
                prepared,
                prepared.copy(phase = FeedbackDeletionPhase.DISPATCHED),
                ack(prepared),
            )) {
            val bytes = FeedbackDeletionJournalCodec.encode(listOf(entry))
            assertEquals(listOf(entry), FeedbackDeletionJournalCodec.decode(bytes))
            val raw = bytes.toString(Charsets.UTF_8)
            for (value in
                listOf(actor, secret, "PRIVATE-AUTHOR", "2026-09-03", "deletedCount")) assertFalse(
                raw.contains(value)
            )
            assertTrue(raw.contains(entry.version.targetId)) // Permitted opaque routing ID only.
        }
    }

    @Test
    fun sixteenMaximumUtf8TargetsFitWithoutEvictingSeventeenth() {
        val entries = List(16) { ack(pending(it.toString().padStart(3, '0') + "界".repeat(197))) }
        val bytes = FeedbackDeletionJournalCodec.encode(entries)
        assertTrue(bytes.size <= 32_768)
        assertEquals(entries, FeedbackDeletionJournalCodec.decode(bytes))
        denied { FeedbackDeletionJournalCodec.encode(entries + pending("overflow")) }
    }

    @Test
    fun duplicateAccountTargetOrOperationCannotEnterOrDecode() {
        val first = pending()
        denied {
            FeedbackDeletionJournalCodec.encode(
                listOf(first, first.copy(operationId = UUID.randomUUID().toString()))
            )
        }
        denied {
            FeedbackDeletionJournalCodec.encode(
                listOf(first, pending("target-2", "other").copy(operationId = first.operationId))
            )
        }
        val bytes = FeedbackDeletionJournalCodec.encode(listOf(first, pending("target-2")))
        val corrupt =
            bytes
                .toString(Charsets.ISO_8859_1)
                .replace("target-2", "target-1")
                .toByteArray(Charsets.ISO_8859_1)
        denied { FeedbackDeletionJournalCodec.decode(corrupt) }
    }

    @Test
    fun malformedFramesLengthsVersionsAndTrailingBytesFailClosed() {
        val bytes = FeedbackDeletionJournalCodec.encode(listOf(pending()))
        for (bad in
            listOf(
                byteArrayOf(),
                byteArrayOf(1, 2),
                bytes.copyOf(15),
                bytes + 0,
                bytes.copyOf().also { it[4] = 99 },
                bytes.copyOf().also { it[5] = 127 },
                ByteArray(32_769),
            )) denied { FeedbackDeletionJournalCodec.decode(bad) }
    }

    @Test
    fun invalidUtf8TargetCannotBeReplacedSilently() {
        val bytes = FeedbackDeletionJournalCodec.encode(listOf(pending()))
        val offset = bytes.toString(Charsets.ISO_8859_1).indexOf("target-1")
        assertTrue(offset > 0)
        bytes[offset] = 0xC0.toByte()
        denied { FeedbackDeletionJournalCodec.decode(bytes) }
    }

    @Test
    fun foreignAppBackendAndOtherFeatureFramesAreRejected() {
        val bytes = FeedbackDeletionJournalCodec.encode(listOf(pending()))
        denied {
            FeedbackDeletionJournalCodec.decode(
                bytes.copyOf().also {
                    it[9] = if (it[9] == 'a'.code.toByte()) 'b'.code.toByte() else 'a'.code.toByte()
                }
            )
        }
        denied {
            FeedbackDeletionJournalCodec.encode(listOf(pending().copy(backend = "another-project")))
        }
        denied { FeedbackDeletionJournalCodec.decode(PlatformRoleJournalCodec.encode(emptyList())) }
        assertTrue(
            runCatching {
                PlatformRoleJournalCodec.decode(FeedbackDeletionJournalCodec.encode(emptyList()))
            }
                .isFailure
        )
    }

    @Test
    fun malformedIdentitiesVersionsAndReceiptBindingsCannotBePersisted() {
        val prepared = pending()
        val acknowledged = ack(prepared)
        for (bad in
            listOf(
                prepared.copy(accountHash = actor),
                prepared.copy(operationId = "bad"),
                prepared.copy(version = prepared.version.copy(targetId = "a/b")),
                prepared.copy(version = prepared.version.copy(fingerprint = secret)),
                acknowledged.copy(operationId = UUID.randomUUID().toString()),
                acknowledged.copy(phase = FeedbackDeletionPhase.DISPATCHED),
                acknowledged.copy(receipt = null),
                acknowledged.copy(
                    receipt = acknowledged.receipt!!.copy(responseHash = "f".repeat(64))
                ),
            )) denied { FeedbackDeletionJournalCodec.encode(listOf(bad)) }
    }

    @Test
    fun separateAccountsWithSameTargetAndExplicitEmptyFrameRemainValid() {
        val entries = listOf(pending("same"), pending("same", "other"))
        assertEquals(
            entries,
            FeedbackDeletionJournalCodec.decode(FeedbackDeletionJournalCodec.encode(entries)),
        )
        assertEquals(
            emptyList<FeedbackDeletionPending>(),
            FeedbackDeletionJournalCodec.decode(FeedbackDeletionJournalCodec.encode(emptyList())),
        )
    }

    @Test
    fun decodedAcceptedAbsenceStillCannotClearOrReplayBecauseCascadeGateIsOpen() {
        val reloaded =
            FeedbackDeletionJournalCodec.decode(
                    FeedbackDeletionJournalCodec.encode(listOf(ack(pending())))
                )
                .single()
        val observed =
            FeedbackDeletionRecovery.observation(reloaded, actor, FeedbackDeletionRead.Absent)
        assertTrue(observed.hasOwnReceipt)
        assertTrue(observed.parentAbsent)
        assertFalse(observed.clearsPending)
        assertFalse(observed.allowsReplay)
    }
}
