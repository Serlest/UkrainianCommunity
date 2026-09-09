package at.uac.android

import at.uac.android.core.LocalCallableFailure
import at.uac.android.core.LocalCallableProtocol
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReleaseCallableAllowlistTest {
    private val reads = listOf("getManagedUserPresence")
    private val mutations =
        listOf(
            "updateUserPresence",
            "saveFeaturedBanner",
            "setFeaturedBannerActive",
            "deleteFeaturedBanner",
            "deleteSystemLog",
            "clearSystemLogs",
            "sendTestPushNotification",
        )

    @Test
    fun releaseFeatureCallablesAreActuallyReachableThroughTheGuard() {
        (reads + mutations).forEach { name ->
            assertTrue(LocalCallableProtocol.endpoint(name).endsWith("/$name"))
        }
        reads.forEach { assertFalse(LocalCallableProtocol.nonIdempotent(it)) }
    }

    @Test
    fun releaseMutationsBecomeUnconfirmedAfterAmbiguousSubmission() {
        mutations.forEach { name ->
            assertTrue(LocalCallableProtocol.nonIdempotent(name))
            assertEquals(
                LocalCallableFailure.UNCONFIRMED,
                LocalCallableProtocol.transportFailure(
                    name,
                    requestStarted = true,
                    failure = LocalCallableFailure.UNAVAILABLE,
                ),
            )
        }
        assertEquals(300_000, LocalCallableProtocol.maximumTimeoutMillis("clearSystemLogs"))
    }
}
