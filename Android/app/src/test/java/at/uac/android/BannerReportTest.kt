package at.uac.android

import at.uac.android.feature.bannermeasurement.BannerDailyCount
import at.uac.android.feature.bannermeasurement.bannerReport
import at.uac.android.feature.personal.ProfileManagementAccess
import at.uac.android.feature.browse.BrowseNavigation
import at.uac.android.feature.browse.PrimaryTab
import org.junit.Assert.*
import org.junit.Test

class BannerReportTest {
    @Test fun reportAggregatesShardsByBannerDayAndSection() {
        val report = bannerReport(listOf(
            BannerDailyCount("2026-10-12", "banner-a", "home", 4, 2),
            BannerDailyCount("2026-10-12", "banner-a", "home", 3, 1),
            BannerDailyCount("2026-10-13", "banner-a", "events", 2, 1),
            BannerDailyCount("2026-10-13", "banner-b", "home", 1, 0),
        ))
        assertEquals(10L, report.totals.impressions)
        assertEquals(4L, report.totals.clicks)
        assertEquals(.4, report.totals.clickRate!!, 0.0001)
        assertEquals(8L, report.sections["home"]!!.impressions)
        assertEquals(7L, report.days["2026-10-12"]!!.impressions)
        assertEquals(9L, report.banners["banner-a"]!!.impressions)
        assertEquals(7L, report.bannerSections["banner-a"]!!["home"]!!.impressions)
        assertEquals(2L, report.bannerSections["banner-a"]!!["events"]!!.impressions)
        assertNull(bannerReport(emptyList()).totals.clickRate)
    }

    @Test fun bannerReportRouteRequiresOwner() {
        assertEquals("profile/banner-report", BrowseNavigation.restore()
            .select(PrimaryTab.PROFILE).navigate("profile/banner-report").route)
        assertFalse(ProfileManagementAccess().allows("profile/banner-report"))
        assertFalse(ProfileManagementAccess(moderator = true).allows("profile/banner-report"))
        assertTrue(ProfileManagementAccess(owner = true).allows("profile/banner-report"))
    }
}
