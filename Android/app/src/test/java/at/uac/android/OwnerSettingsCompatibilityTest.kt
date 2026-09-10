package at.uac.android

import at.uac.android.feature.donationsettings.*
import at.uac.android.feature.owneranalytics.*
import com.google.firebase.Timestamp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.*
import org.junit.Test

class OwnerSettingsCompatibilityTest {
    @Test
    fun analyticsTimeoutBecomesOffline() = runBlocking {
        try {
            ownerAnalyticsRead { withTimeout(1) { delay(1000) } }
            fail("Timeout must be an offline result")
        } catch (error: OwnerAnalyticsException) {
            assertEquals(OwnerAnalyticsFailure.OFFLINE, error.failure)
        }
    }

    @Test
    fun analyticsUserCancellationRemainsCancellation() = runBlocking {
        val cancellation = CancellationException("left screen")
        try {
            ownerAnalyticsRead<Unit> { throw cancellation }
            fail("Cancellation must propagate")
        } catch (error: CancellationException) {
            assertSame(cancellation, error)
        }
    }

    @Test
    fun partialDonationUsesSharedDefaultsWithoutInventingRevision() {
        val result =
            decodeDonationSnapshot(mapOf("isEnabled" to false, "titleDE" to "Eigener Titel"))
        assertEquals("Eigener Titel", result.draft.texts["titleDE"])
        assertEquals(DonationDraft().texts["titleUK"], result.draft.texts["titleUK"])
        assertNull(result.revision)
        assertTrue(result.exists)
    }

    @Test
    fun donationCompareAndSwapDistinguishesMissingExplicitAndUnknownFields() {
        val absent = decodeDonationSnapshot(emptyMap())
        val explicit = decodeDonationSnapshot(mapOf("isEnabled" to false))
        assertEquals(absent.draft, explicit.draft)
        assertNotEquals(absent, explicit)
        assertNotEquals(absent, decodeDonationSnapshot(mapOf("futureField" to "changed")))
        assertNotEquals(absent, decodeDonationSnapshot(null))
        val timestamp = Timestamp(12, 123)
        assertEquals(123, decodeDonationSnapshot(mapOf("updatedAt" to timestamp)).revision!!.nano)
    }

    @Test
    fun malformedPresentFieldsStillFailAndUnsafeLinksCannotSave() {
        listOf(
                "isEnabled" to "true",
                "titleDE" to 42,
                "updatedAt" to "yesterday",
                "donationURL" to null,
            )
            .forEach { (key, value) ->
                try {
                    decodeDonationSnapshot(mapOf(key to value))
                    fail("Malformed $key accepted")
                } catch (error: DonationException) {
                    assertEquals(DonationProblem.INVALID, error.problem)
                }
            }
        assertFalse(
            decodeDonationSnapshot(
                    mapOf("isEnabled" to true, "donationURL" to "javascript:alert(1)")
                )
                .draft
                .valid()
        )
    }
}
