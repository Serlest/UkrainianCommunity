package at.uac.android

import at.uac.android.feature.feedback.FeedbackAudience
import at.uac.android.feature.feedbackdeletion.*
import at.uac.android.feature.moderation.ModerationDecisionGate
import at.uac.android.feature.moderation.ModerationSession
import java.time.Instant
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

class FeedbackDeletionRepositoryTest {
    private val actor = ModerationSession("owner-delete", 9, "owner", true)
    private val id = "feedback-delete"
    private val snapshot =
        FeedbackDeletionRecovery.snapshot(
            id,
            mapOf(
                "id" to id,
                "userId" to "author",
                "userDisplayName" to "Private",
                "message" to "Private",
                "type" to "question",
                "status" to "open",
                "createdAt" to Instant.parse("2026-09-07T12:00:00Z"),
            ),
        )

    private class Journal : FeedbackDeletionJournal {
        var entries = emptyList<FeedbackDeletionPending>()
        val phases = mutableListOf<FeedbackDeletionPhase>()
        override suspend fun pending(uid: String) = entries
        override suspend fun put(
            uid: String,
            entry: FeedbackDeletionPending,
            expected: FeedbackDeletionPending?,
        ): FeedbackDeletionPending {
            assertEquals(expected, entries.singleOrNull())
            entries = listOf(entry)
            phases += entry.phase
            return entry
        }
        override suspend fun clear(uid: String, expected: FeedbackDeletionPending) {
            assertEquals(expected, entries.single())
            entries = emptyList()
        }
    }

    private class Gate : ModerationDecisionGate {
        override suspend fun <T> withSession(
            session: ModerationSession,
            action: suspend () -> T,
        ): T = action()
    }

    private fun harness(
        journal: Journal,
        live: () -> ModerationSession?,
        mutation: FeedbackDeletionMutationSource,
    ): FeedbackDeletionRepository {
        val gate = Gate()
        val reads =
            FeedbackDeletionReadRepository(
                FeedbackDeletionReadSource { _, _ -> FeedbackDeletionRead.Present(snapshot) },
                journal,
                live,
                gate,
            )
        return FeedbackDeletionRepository(
            reads,
            mutation,
            journal,
            live,
            gate,
            { "00000000-0000-4000-8000-000000000007" },
        )
    }

    @Test
    fun successfulCheckedResponseAdvancesEveryPhaseAndClearsJournal() = runTest {
        val journal = Journal()
        var live: ModerationSession? = actor
        var calls = 0
        val repository =
            harness(journal, { live }) { session, entry, canDispatch ->
                calls++
                assertEquals(actor, session)
                assertEquals(FeedbackDeletionPhase.DISPATCHED, entry.phase)
                assertTrue(canDispatch())
                FeedbackDeletionRecovery.receipt(entry, mapOf("deletedCount" to 1))
            }
        val receipt =
            repository.delete(actor, FeedbackAudience.MANAGEMENT, snapshot.version) { true }
        assertEquals(1, calls)
        assertEquals(64, receipt.requestHash.length)
        assertEquals(
            listOf(
                FeedbackDeletionPhase.PREPARED,
                FeedbackDeletionPhase.DISPATCHED,
                FeedbackDeletionPhase.ACKNOWLEDGED,
            ),
            journal.phases,
        )
        assertTrue(journal.entries.isEmpty())
        live = null
    }

    @Test
    fun uncertainTransportKeepsDispatchedEntryAndNeverRetries() = runTest {
        val journal = Journal()
        var calls = 0
        val repository =
            harness(journal, { actor }) { _, _, _ ->
                calls++
                error("connection lost after dispatch")
            }
        val error =
            runCatching {
                    repository.delete(actor, FeedbackAudience.MANAGEMENT, snapshot.version) { true }
                }
                .exceptionOrNull()
        assertEquals(FeedbackDeletionFailure.UNCONFIRMED, (error as FeedbackDeletionException).failure)
        assertEquals(1, calls)
        assertEquals(FeedbackDeletionPhase.DISPATCHED, journal.entries.single().phase)
    }

    @Test
    fun staleSelectionBeforeDispatchClearsPreparedEntryWithoutCallingServer() = runTest {
        val journal = Journal()
        var checks = 0
        var calls = 0
        val repository = harness(journal, { actor }) { _, _, _ -> calls++; error("must not call") }
        val error =
            runCatching {
                    repository.delete(actor, FeedbackAudience.MANAGEMENT, snapshot.version) {
                        ++checks < 3
                    }
                }
                .exceptionOrNull()
        assertEquals(
            FeedbackDeletionFailure.STALE,
            (error as FeedbackDeletionException).failure,
        )
        assertEquals(0, calls)
        assertTrue(journal.entries.isEmpty())
    }

    @Test
    fun acknowledgedRecoveryClearsWithoutReplayingMutation() = runTest {
        val journal = Journal()
        val prepared =
            FeedbackDeletionRecovery.prepared(
                actor,
                FeedbackAudience.MANAGEMENT,
                snapshot,
                "00000000-0000-4000-8000-000000000007",
            )
        val dispatched = prepared.copy(phase = FeedbackDeletionPhase.DISPATCHED)
        val acknowledged =
            dispatched.copy(
                phase = FeedbackDeletionPhase.ACKNOWLEDGED,
                receipt =
                    FeedbackDeletionRecovery.receipt(
                        dispatched,
                        mapOf("deletedCount" to 1),
                    ),
            )
        journal.entries = listOf(acknowledged)
        var calls = 0
        val repository = harness(journal, { actor }) { _, _, _ -> calls++; error("no replay") }
        val observation =
            repository.reconcile(actor, FeedbackAudience.MANAGEMENT, acknowledged)
        assertEquals(FeedbackDeletionObservation.ACCEPTED_UNCHANGED, observation)
        assertEquals(0, calls)
        assertTrue(journal.entries.isEmpty())
    }
}
