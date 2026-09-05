package at.uac.android

import at.uac.android.feature.moderation.*
import java.time.Instant
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class ModerationDecisionJournalTest {
    private val fixture
        get() = ModerationDecisionUnitFixture.pending()

    private fun rejects(action: () -> Any?) {
        try {
            action()
            fail("Expected invalid bounded journal")
        } catch (_: IllegalArgumentException) {} catch (_: ModerationDecisionException) {} catch (
            _: java.io.EOFException) {}
    }

    @Test
    fun everyPhaseRoundTripsExactlyWithoutRawUidOrReviewedContent() {
        for (phase in ModerationDecisionPhase.entries) {
            val value = fixture.copy(phase = phase)
            val encoded = ModerationDecisionJournalCodec.encode(listOf(value))
            assertEquals(listOf(value), ModerationDecisionJournalCodec.decode(encoded))
            val raw = encoded.toString(Charsets.ISO_8859_1)
            assertFalse(raw.contains(ModerationDecisionUnitFixture.actor.uid))
            assertFalse(raw.contains("Private complete body"))
            assertFalse(value.toString().contains(value.operationId))
        }
    }

    @Test
    fun exactMaximumEntriesFitsBoundAndOneMoreFailsBeforeEncoding() {
        val entry = fixture
        val all =
            List(16) {
                entry.copy(
                    operationId = UUID.randomUUID().toString(),
                    version =
                        entry.version.copy(
                            target = entry.version.target.copy(id = "synthetic-$it")
                        ),
                )
            }
        assertEquals(
            all,
            ModerationDecisionJournalCodec.decode(ModerationDecisionJournalCodec.encode(all)),
        )
        rejects { ModerationDecisionJournalCodec.encode(all + entry) }
    }

    @Test
    fun duplicateTargetAndDuplicateOperationAcrossAccountsAreRejected() {
        val entry = fixture
        rejects {
            ModerationDecisionJournalCodec.encode(
                listOf(entry, entry.copy(operationId = UUID.randomUUID().toString()))
            )
        }
        rejects {
            ModerationDecisionJournalCodec.encode(
                listOf(
                    entry,
                    entry.copy(
                        accountHash = "a".repeat(64),
                        version =
                            entry.version.copy(target = entry.version.target.copy(id = "other")),
                    ),
                )
            )
        }
    }

    @Test
    fun unsupportedSchemaTrailingAndTruncatedBytesDoNotBecomeEmpty() {
        val data = ModerationDecisionJournalCodec.encode(listOf(fixture))
        rejects { ModerationDecisionJournalCodec.decode(data.copyOf(8)) }
        rejects { ModerationDecisionJournalCodec.decode(data + 0) }
        rejects { ModerationDecisionJournalCodec.decode(data.copyOf().also { it[4] = 99 }) }
        rejects { ModerationDecisionJournalCodec.decode(byteArrayOf()) }
        rejects {
            ModerationDecisionJournalCodec.decode(
                ByteArray(ModerationDecisionJournalCodec.MAX_BYTES + 1)
            )
        }
    }

    @Test
    fun backendAccountOperationAndRawTargetBoundsAreStrict() {
        val entry = fixture
        for (invalid in
            listOf(
                entry.copy(backend = "production"),
                entry.copy(accountHash = "uid"),
                entry.copy(operationId = "not-uuid"),
                entry.copy(issuedRole = "user"),
                entry.copy(
                    version =
                        entry.version.copy(target = entry.version.target.copy(id = "../other"))
                ),
                entry.copy(version = entry.version.copy(organizationId = "x".repeat(129))),
            )) rejects { ModerationDecisionJournalCodec.encode(listOf(invalid)) }
    }

    @Test
    fun timestampsPreserveNanosecondsAndNoAutomaticExpiryIsApplied() {
        val entry =
            fixture.copy(
                issuedAt = Instant.parse("2001-01-01T00:00:00.123456789Z"),
                phase = ModerationDecisionPhase.DISPATCHED,
            )
        assertEquals(
            entry,
            ModerationDecisionJournalCodec.decode(
                    ModerationDecisionJournalCodec.encode(listOf(entry))
                )
                .single(),
        )
    }

    @Test
    fun organizationTargetsCanNeverEnterModerationDecisionJournal() {
        val entry = fixture
        rejects {
            ModerationDecisionJournalCodec.encode(
                listOf(
                    entry.copy(
                        version =
                            entry.version.copy(
                                target =
                                    entry.version.target.copy(kind = ModerationKind.ORGANIZATION)
                            )
                    )
                )
            )
        }
    }
}
