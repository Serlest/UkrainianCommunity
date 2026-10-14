package at.uac.android

import at.uac.android.core.LocalCallableProtocol
import at.uac.android.feature.feedback.FeedbackFailure
import at.uac.android.feature.feedback.FeedbackInboxClearContract
import at.uac.android.feature.feedback.FeedbackInboxClearJournal
import at.uac.android.feature.feedback.FeedbackInboxClearRepository
import at.uac.android.feature.feedback.FeedbackInboxClearSource
import at.uac.android.feature.feedback.FeedbackInboxClearViewModel
import at.uac.android.feature.moderation.ModerationSession
import at.uac.android.feature.systemlogs.ClientDiagnosticContract
import at.uac.android.feature.systemlogs.ClientDiagnosticOperation
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import org.junit.Assert.*
import org.junit.Test

class FeedbackInboxClearAndDiagnosticTest {
    private val owner = ModerationSession("owner-test", 7, "owner", true)

    private class Journal : FeedbackInboxClearJournal {
        var marked = false
        override fun pending(uid: String) = marked
        override fun mark(uid: String) { marked = true }
        override fun clear(uid: String) { marked = false }
    }

    private class Source : FeedbackInboxClearSource {
        var prepared = 0
        var calls = 0
        var fail = false
        override suspend fun prepare(session: ModerationSession) { prepared++ }
        override suspend fun clear(session: ModerationSession): Int {
            calls++
            if (fail) error("unknown transport result")
            return 2
        }
    }

    @Test fun ownerReceiptAndNoAutomaticReplayAfterUnknownResult() = runTest {
        val source = Source()
        val journal = Journal()
        val repository = FeedbackInboxClearRepository(source, journal) { owner }
        assertEquals(2, repository.clear(owner))
        assertFalse(repository.pending(owner))
        assertEquals(1, source.calls)

        source.fail = true
        assertTrue(runCatching { repository.clear(owner) }.isFailure)
        assertTrue(repository.pending(owner))
        assertTrue(runCatching { repository.clear(owner) }.isFailure)
        assertEquals(2, source.calls)
        repository.acknowledge(owner)
        assertFalse(repository.pending(owner))
    }

    @Test fun otherRoleAndChangedSessionNeverDispatch() = runTest {
        var current = owner
        val source = Source()
        val journal = Journal()
        val repository = FeedbackInboxClearRepository(source, journal) { current }
        assertTrue(runCatching { repository.clear(owner.copy(role = "admin")) }.isFailure)
        current = owner.copy(revision = 8)
        assertTrue(runCatching { repository.clear(owner) }.isFailure)
        assertEquals(0, source.prepared)
        assertEquals(0, source.calls)
        assertFalse(journal.marked)
    }

    @OptIn(ExperimentalCoroutinesApi::class)
    @Test fun oldAccountCompletionCannotShowReceiptToNewAccount() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        try {
            val released = CompletableDeferred<Unit>()
            val source = object : FeedbackInboxClearSource {
                override suspend fun prepare(session: ModerationSession) = Unit
                override suspend fun clear(session: ModerationSession): Int {
                    released.await()
                    return 2
                }
            }
            val journal = object : FeedbackInboxClearJournal {
                private val pending = mutableSetOf<String>()
                override fun pending(uid: String) = uid in pending
                override fun mark(uid: String) { pending += uid }
                override fun clear(uid: String) { pending -= uid }
            }
            var current = owner
            val model = FeedbackInboxClearViewModel(
                FeedbackInboxClearRepository(source, journal) { current }
            )
            var refreshes = 0
            model.bind(owner)
            model.clear(owner) { refreshes++ }
            runCurrent()
            current = owner.copy(uid = "second-owner")
            model.bind(current)
            released.complete(Unit)
            runCurrent()
            assertNull(model.state.value.deletedCount)
            assertEquals(0, refreshes)
            assertFalse(journal.pending(owner.uid))
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test fun receiptMustBeExactAndDiagnosticContainsOnlyFixedTechnicalFields() {
        assertEquals(0, FeedbackInboxClearContract.count(mapOf("deletedCount" to 0)))
        assertEquals(10_000, FeedbackInboxClearContract.count(mapOf("deletedCount" to 10_000L)))
        for (bad in listOf(-1, 10_001, 1.5, "1", null, true))
            assertTrue(runCatching { FeedbackInboxClearContract.count(mapOf("deletedCount" to bad)) }.isFailure)
        assertTrue(runCatching { FeedbackInboxClearContract.count(mapOf("deletedCount" to 1, "id" to "other")) }.isFailure)
        assertTrue(LocalCallableProtocol.nonIdempotent("clearFeedbackInbox"))
        assertTrue(LocalCallableProtocol.nonIdempotent("writeClientDiagnostic"))
        assertEquals(300_000L, LocalCallableProtocol.maximumTimeoutMillis("clearFeedbackInbox"))

        val payload = ClientDiagnosticContract.payload(ClientDiagnosticOperation.FEEDBACK_WRITE, FeedbackFailure.UNCONFIRMED)
        assertEquals(setOf("eventType", "severity", "targetType", "summary", "moduleName", "operationName", "errorCode", "metadata"), payload.keys)
        assertEquals(emptyMap<String, String>(), payload["metadata"])
        val serialized = payload.toString()
        for (privateValue in listOf("owner-test", "email", "messageBody", "token", "targetId", "technicalMessage"))
            assertFalse(serialized.contains(privateValue))
        assertTrue(runCatching { ClientDiagnosticContract.payload(ClientDiagnosticOperation.FEEDBACK_READ, FeedbackFailure.DENIED) }.isFailure)
    }
}
