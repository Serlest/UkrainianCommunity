package at.uac.android

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class HistoryFixtureCleanupTest {
    @Test
    fun successfulDeleteStillRequiresIndependentAbsence() = runBlocking {
        var reads = 0
        confirmHistoryFixtureAbsent(
            {},
            {
                reads++
                true
            },
            { fail("Unexpected warning") },
        )
        assertEquals(1, reads)
    }

    @Test
    fun failedDeleteIsNotRetriedAndCanOnlyReconcileWithConfirmedAbsence() = runBlocking {
        val original = IllegalStateException("synthetic DELETE HTTP 500")
        var deletes = 0
        var reads = 0
        var warnings = 0
        confirmHistoryFixtureAbsent(
            {
                deletes++
                throw original
            },
            {
                reads++
                true
            },
            {
                assertSame(original, it)
                warnings++
            },
        )
        assertEquals(1, deletes)
        assertEquals(1, reads)
        assertEquals(1, warnings)
    }

    @Test
    fun existingDocumentPreservesOriginalFailure() = runBlocking {
        val original = IllegalStateException("synthetic DELETE HTTP 500")
        val caught = runCatching {
            confirmHistoryFixtureAbsent(
                { throw original },
                { false },
                { fail("Must not reconcile") },
            )
        }
            .exceptionOrNull()
        assertSame(original, caught)
    }

    @Test
    fun successfulTransportDoesNotProveDeletion() = runBlocking {
        assertTrue(
            runCatching {
                confirmHistoryFixtureAbsent({}, { false }, { fail("Must not reconcile") })
            }
                .exceptionOrNull() is IllegalStateException
        )
    }

    @Test
    fun failedReadCannotBeTreatedAsAbsence() = runBlocking {
        val write = IllegalStateException("synthetic write failure")
        val read = IllegalStateException("synthetic read failure")
        val caught = runCatching {
            confirmHistoryFixtureAbsent(
                { throw write },
                { throw read },
                { fail("Must not reconcile") },
            )
        }
            .exceptionOrNull()
        assertSame(read, caught)
        assertSame(write, caught!!.suppressed.single())
    }

    @Test
    fun cancellationDoesNotStartReadback() = runBlocking {
        val cancellation = CancellationException("synthetic cancellation")
        val caught = runCatching {
            confirmHistoryFixtureAbsent(
                { throw cancellation },
                {
                    fail("Must not read")
                    false
                },
                {},
            )
        }
            .exceptionOrNull()
        assertSame(cancellation, caught)
    }
}
