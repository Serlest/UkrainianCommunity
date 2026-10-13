package at.uac.android

import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.feature.bannermeasurement.*
import at.uac.android.feature.owneranalytics.AnalyticsPeriod
import at.uac.android.feature.owneranalytics.OwnerAnalyticsSession
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class BannerReportUiTest {
    @get:Rule val compose = createComposeRule()

    @Test fun ownerSeesTotalsBannerSectionBreakdownAndPeriodSwitch() {
        val periods = mutableListOf<AnalyticsPeriod>()
        val source = object : BannerReportSource {
            override suspend fun load(session: OwnerAnalyticsSession, period: AnalyticsPeriod): BannerReport {
                periods += period
                return bannerReport(listOf(
                    BannerDailyCount("2026-10-13", "banner-a", "home", 7, 3),
                    BannerDailyCount("2026-10-13", "banner-a", "events", 2, 1),
                ), mapOf("banner-a" to "Community"))
            }
        }
        compose.setContent {
            BannerMeasurementReportScreen(source, OwnerAnalyticsSession("owner", 1, true), "de") {}
        }
        compose.waitUntil(10_000) { periods.size == 1 }
        compose.onNodeWithTag("banner-report-list").performScrollToNode(hasText("Community"))
        compose.onNodeWithText("Community").assertIsDisplayed()
        compose.onNodeWithText("banner-a").assertExists()
        compose.onNodeWithTag("banner-report-list")
            .performScrollToNode(hasTestTag("banner-section-banner-a-events"))
        compose.onNodeWithTag("banner-section-banner-a-events").assertIsDisplayed()
        compose.onNodeWithTag("banner-report-list").performScrollToIndex(0)
        val image = compose.onNodeWithTag("banner-report").captureToImage().asAndroidBitmap()
        java.io.File(InstrumentationRegistry.getInstrumentation().targetContext.cacheDir,
            "step6-banner-report.png").outputStream().use {
            image.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
        }
        compose.onNodeWithTag("banner-report-period-THIRTY_DAYS").performClick()
        compose.waitUntil(10_000) { periods.size == 2 }
        compose.runOnIdle { assertEquals(AnalyticsPeriod.THIRTY_DAYS, periods.last()) }
    }
}
