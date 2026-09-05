package at.uac.android

import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class AuthoringFixtureCleanupTest {
    @Test
    fun firstFailedOwnedDeletionDoesNotSkipRemainingDocumentsOrAccounts() = runBlocking {
        val visited = mutableListOf<String>()
        val first = IllegalStateException("first synthetic cleanup")
        val later = IllegalArgumentException("later synthetic cleanup")
        try {
            cleanupEveryOwnedFixtureItem(
                listOf("document", "profile", "public-profile", "account")
            ) {
                visited += it
                if (it == "document") throw first
                if (it == "public-profile") throw later
            }
            fail("Cleanup failure must remain visible")
        } catch (error: Exception) {
            assertSame(first, error)
            assertEquals(listOf(later), error.suppressed.toList())
        }
        assertEquals(listOf("document", "profile", "public-profile", "account"), visited)
    }

    @Test
    fun originalTestFailureIsPreservedWithEveryCleanupFailureSuppressed() = runBlocking {
        val original = AssertionError("original synthetic test failure")
        val errors = listOf(IllegalStateException("one"), IllegalStateException("two"))
        val visited = mutableListOf<Int>()
        cleanupEveryOwnedFixtureItem(listOf(0, 1, 2), original) {
            visited += it
            errors.getOrNull(it)?.let { error -> throw error }
        }
        assertEquals(listOf(0, 1, 2), visited)
        assertEquals(errors, original.suppressed.toList())
    }

    @Test
    fun successfulCleanupExecutesEachOwnedItemOnceAndPreservesOrder() = runBlocking {
        val visited = mutableListOf<Int>()
        cleanupEveryOwnedFixtureItem(listOf(3, 2, 1)) { visited += it }
        assertEquals(listOf(3, 2, 1), visited)
    }
}
