package at.uac.android

import at.uac.android.feature.bannermeasurement.BannerExposureTracker
import org.junit.Assert.*
import org.junit.Test

class BannerExposureTest {
    @Test fun impressionRequiresHalfVisibilityForOneSecondAndRepeatsOnlyAfterNewExposure() {
        var next = 0
        val tracker = BannerExposureTracker { "event-${++next}" }
        assertNull(tracker.observe("banner", "home", .49f, true, 0))
        assertNull(tracker.observe("banner", "home", .5f, true, 100))
        assertNull(tracker.observe("banner", "home", .5f, true, 1_099))
        val first = tracker.observe("banner", "home", .5f, true, 1_100)!!
        assertEquals("impression", first.kind)
        assertEquals("banner", first.bannerId)
        assertEquals("home", first.section)
        assertEquals(setOf("id", "bannerID", "section", "kind", "occurredAtMilliseconds", "consentID"),
            first.payload().keys)
        assertNull(tracker.observe("banner", "home", .5f, true, 2_500))
        tracker.observe(null, "home", 0f, false, 3_000)
        tracker.observe("banner", "home", 1f, true, 4_000)
        assertNull(tracker.observe("banner", "home", 1f, true, 5_000))
        tracker.observe(null, "home", 0f, false, 30_000)
        tracker.observe("banner", "home", 1f, true, 31_100)
        assertNotNull(tracker.observe("banner", "home", 1f, true, 32_100))
    }

    @Test fun deliberateEarlyTapCountsViewThenClickOnce() {
        var next = 0
        val tracker = BannerExposureTracker { "event-${++next}" }
        tracker.observe("banner", "events", .75f, true, 10_000)
        val first = tracker.click("banner", "events", .75f, true, 10_250)
        assertEquals(listOf("impression", "click"), first.map { it.kind })
        assertEquals(listOf("event-1", "event-2"), first.map { it.id })
        assertEquals(emptyList<Any>(), tracker.click("banner", "events", .75f, true, 10_500))
        assertNull(tracker.observe("banner", "events", .75f, true, 11_300))
        assertEquals(listOf("click"), tracker.click("banner", "events", .75f, true, 11_301).map { it.kind })
        assertEquals(emptyList<Any>(), tracker.click("other", "events", 1f, true, 12_500))
    }
}
