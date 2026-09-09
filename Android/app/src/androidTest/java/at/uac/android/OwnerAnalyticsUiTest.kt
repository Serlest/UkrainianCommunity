package at.uac.android

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performScrollToNode
import at.uac.android.design.UacTheme
import at.uac.android.feature.owneranalytics.AnalyticsDetail
import at.uac.android.feature.owneranalytics.AnalyticsPeriod
import at.uac.android.feature.owneranalytics.AnalyticsRegion
import at.uac.android.feature.owneranalytics.AnalyticsTopItem
import at.uac.android.feature.owneranalytics.AnalyticsUsers
import at.uac.android.feature.owneranalytics.OwnerAnalyticsRepository
import at.uac.android.feature.owneranalytics.OwnerAnalyticsScreen
import at.uac.android.feature.owneranalytics.OwnerAnalyticsSession
import at.uac.android.feature.owneranalytics.OwnerAnalyticsSnapshot
import at.uac.android.feature.owneranalytics.OwnerAnalyticsViewModel
import java.time.Instant
import org.junit.Rule
import org.junit.Test

class OwnerAnalyticsUiTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    private val session = OwnerAnalyticsSession("owner", 68, true)
    private val repository =
        object : OwnerAnalyticsRepository {
            override suspend fun overview(
                session: OwnerAnalyticsSession,
                period: AnalyticsPeriod,
            ) =
                OwnerAnalyticsSnapshot(
                    period,
                    Instant.parse("2026-09-07T12:00:00Z"),
                    mapOf("totalViews" to 12, "newsViews" to 12, "activeRegions" to 1),
                    mapOf("totalViews" to 7),
                    listOf("2026-09-07" to mapOf("totalViews" to 12)),
                    listOf(AnalyticsTopItem("news-1", "news", "Hilfsangebot", 12, 1)),
                    listOf(
                        AnalyticsRegion(
                            "federalState:wien",
                            "federalState",
                            "wien",
                            12,
                            1,
                            mapOf("newsViews" to 12),
                        )
                    ),
                    AnalyticsUsers(total = 5, activeToday = 2),
                )

            override suspend fun detail(
                session: OwnerAnalyticsSession,
                period: AnalyticsPeriod,
                type: String,
                id: String,
            ) =
                AnalyticsDetail(
                    type,
                    id,
                    "Hilfsangebot",
                    period,
                    mapOf("views" to 12),
                    emptyList(),
                )
        }

    @Test
    fun missingDailyCoverageDoesNotDisplayInventedZeroMetrics() {
        val partial =
            object : OwnerAnalyticsRepository by repository {
                override suspend fun overview(
                    session: OwnerAnalyticsSession,
                    period: AnalyticsPeriod,
                ) = repository.overview(session, period).copy(unavailable = setOf("daily"))
            }
        val model = OwnerAnalyticsViewModel(partial)
        compose.setContent { UacTheme("light") { OwnerAnalyticsScreen(model, session, "de", {}) } }
        compose.waitForIdle()
        compose.onNodeWithTag("owner-analytics-overview").assertIsDisplayed()
        compose.onNodeWithTag("owner-analytics-metric-totalViews").assertDoesNotExist()
    }

    @Test
    fun ownerCanInspectOverviewAndOpenContentDetail() {
        val model = OwnerAnalyticsViewModel(repository)
        compose.setContent {
            UacTheme("light") { OwnerAnalyticsScreen(model, session, "de", {}) }
        }
        compose.waitForIdle()
        compose.onNodeWithTag("owner-analytics-overview").assertIsDisplayed()
        compose.onNodeWithTag("owner-analytics-metric-totalViews").assertIsDisplayed()
        compose
            .onNodeWithTag("owner-analytics-overview")
            .performScrollToNode(hasTestTag("owner-analytics-top-news-news-1"))
        compose.onNodeWithTag("owner-analytics-top-news-news-1").performScrollTo().performClick()
        compose.waitForIdle()
        compose.onNodeWithTag("owner-analytics-detail").assertIsDisplayed()
        compose.onNodeWithTag("owner-analytics-metric-views").assertIsDisplayed()
    }
}
