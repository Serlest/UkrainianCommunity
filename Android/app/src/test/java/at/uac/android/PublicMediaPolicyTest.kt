package at.uac.android

import at.uac.android.feature.browse.PublicMediaPolicy
import java.io.ByteArrayInputStream
import org.junit.Assert.*
import org.junit.Test

class PublicMediaPolicyTest {
    private val local =
        "http://10.0.2.2:9198/v0/b/demo-uac-android.appspot.com/o/news%2Fsynthetic%2Fcover.jpg?alt=media&token=synthetic-token"

    @Test
    fun canonicalDemoCoverOnlyResolvesToTheExactEmulator() {
        assertEquals(local, PublicMediaPolicy.address(local))
        assertEquals(
            local,
            PublicMediaPolicy.address(
                local.replace("http://10.0.2.2:9198", "https://firebasestorage.googleapis.com")
            ),
        )
    }

    @Test
    fun productionHostsBucketsRedirectLikePathsAndCredentialsAreRejected() {
        val rejected =
            listOf(
                local.replace(
                    "demo-uac-android.appspot.com",
                    "ukrainiancommunity-dbd5f.appspot.com",
                ),
                local.replace("10.0.2.2", "10.0.2.2.evil.invalid"),
                local.replace("9198", "8088"),
                local.replace("http://", "http://account@"),
                local + "#fragment",
                local + "&alt=media",
                local.replace("alt=media", "alt=json"),
                local + "&redirect=https%3A%2F%2Fevil.invalid",
                local.replace("news%2Fsynthetic%2Fcover.jpg", "..%2Fprivate"),
                local.replace("%2F", "%252F"),
                local.replace("synthetic%2F", "%00%2F"),
                local.replace("synthetic-token", "bad%20token"),
            )
        rejected.forEach { assertNull(it, PublicMediaPolicy.address(it)) }
    }

    @Test
    fun absentOptionalTokenIsAllowedButAbsentMediaModeIsNot() {
        assertNotNull(PublicMediaPolicy.address(local.substringBefore("&token=")))
        assertNull(PublicMediaPolicy.address(local.substringBefore('?')))
    }

    @Test
    fun completeCoverBudgetAcceptedAndOneByteOverRejected() {
        val cover = ByteArray(PublicMediaPolicy.MAX_BYTES) { 42 }
        assertArrayEquals(cover, PublicMediaPolicy.bytes(ByteArrayInputStream(cover)))
        try {
            PublicMediaPolicy.bytes(ByteArrayInputStream(ByteArray(cover.size + 1)))
            fail("over budget")
        } catch (_: IllegalStateException) {}
    }

    @Test
    fun cancellationIsCheckedBeforeReadingMoreUntrustedBytes() {
        val input = ByteArrayInputStream(ByteArray(16_384))
        var calls = 0
        try {
            PublicMediaPolicy.bytes(input) {
                if (++calls == 2) throw kotlinx.coroutines.CancellationException()
            }
            fail("cancelled read")
        } catch (_: kotlinx.coroutines.CancellationException) {}
        assertEquals(8_192, input.available())
    }

    @Test
    fun decodeBudgetAlwaysUsesPowerOfTwoAndNeverExceedsSixteenHundredPixels() {
        for (size in listOf(1, 900, 1_600, 1_601, 2_001, 4_095, 8_192)) {
            val sample = PublicMediaPolicy.sampleSize(size, size)
            assertEquals(0, sample and (sample - 1))
            assertTrue((size + sample - 1) / sample <= 1_600)
        }
        for (size in listOf(-1, 0, 8_193)) {
            try {
                PublicMediaPolicy.sampleSize(size, 100)
                fail("invalid raster")
            } catch (_: IllegalArgumentException) {}
        }
    }
}
