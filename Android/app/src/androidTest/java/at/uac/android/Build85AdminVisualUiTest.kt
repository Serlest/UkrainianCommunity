package at.uac.android

import android.graphics.Bitmap
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.design.*
import at.uac.android.feature.moderation.ModerationSession
import at.uac.android.feature.owneranalytics.*
import at.uac.android.feature.systemlogs.*
import java.io.File
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

/** Populated, offline-only visual evidence inside the real shared Android chrome. */
class Build85AdminVisualUiTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val at = Instant.parse("2026-09-10T10:00:00Z")

    @Composable
    private fun Host(language: String, theme: String, content: @Composable () -> Unit) {
        UacTheme(theme) {
            UacPageBackground(Modifier.fillMaxSize(), plain = true) {
                Column(Modifier.fillMaxSize().safeDrawingPadding()) {
                    UacHeader(
                        language,
                        true,
                        { compose.activity.onBackPressedDispatcher.onBackPressed() },
                        {},
                        compact = true,
                    )
                    Box(Modifier.weight(1f).fillMaxWidth().padding(horizontal = 16.dp)) {
                        CompositionLocalProvider(
                            LocalEmbeddedNavigation provides true,
                            content = content,
                        )
                    }
                }
            }
        }
    }

    private fun capture(name: String) {
        compose.waitForIdle()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val bitmap = checkNotNull(instrumentation.uiAutomation.takeScreenshot())
        try {
            File(instrumentation.targetContext.cacheDir, "build85-admin-$name.png")
                .outputStream()
                .use {
                    check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it))
                }
        } finally {
            bitmap.recycle()
        }
    }

    private fun analytics(language: String, theme: String) {
        val session = OwnerAnalyticsSession("synthetic-owner", 85, true)
        val title = "Спільнота Тіролю · Зустріч родин / Begegnung der Familien in Tirol"
        val repository =
            object : OwnerAnalyticsRepository {
                override suspend fun overview(
                    session: OwnerAnalyticsSession,
                    period: AnalyticsPeriod,
                ) =
                    OwnerAnalyticsSnapshot(
                        period,
                        at,
                        mapOf("totalViews" to 1248, "newsViews" to 630, "activeRegions" to 3),
                        mapOf("totalViews" to 940),
                        listOf(
                            "2026-09-09" to mapOf("totalViews" to 180),
                            "2026-09-10" to mapOf("totalViews" to 220),
                        ),
                        listOf(AnalyticsTopItem("news-1", "news", title, 318, 42)),
                        listOf(
                            AnalyticsRegion(
                                "federalState:tirol",
                                "federalState",
                                "tirol",
                                1248,
                                36,
                                mapOf("newsViews" to 630),
                            )
                        ),
                        AnalyticsUsers(total = 184, activeToday = 36),
                    )

                override suspend fun detail(
                    session: OwnerAnalyticsSession,
                    period: AnalyticsPeriod,
                    type: String,
                    id: String,
                ) = AnalyticsDetail(type, id, title, period, mapOf("views" to 318), emptyList())
            }
        val model = OwnerAnalyticsViewModel(repository)
        var parents = 0
        compose.setContent {
            Host(language, theme) { OwnerAnalyticsScreen(model, session, language, { parents++ }) }
        }
        compose.waitForIdle()
        compose.onNodeWithTag("owner-analytics-metric-totalViews").assertIsDisplayed()
        compose.onAllNodesWithTag("back").assertCountEquals(1)
        compose.onNodeWithTag("owner-analytics-back").assertDoesNotExist()
        capture("analytics-top-$language-$theme")
        compose
            .onNodeWithTag("owner-analytics-overview")
            .performScrollToNode(hasTestTag("owner-analytics-top-news-news-1"))
        capture("analytics-content-$language-$theme")
        compose.onNodeWithTag("owner-analytics-top-news-news-1").performClick()
        compose.onNodeWithTag("owner-analytics-detail").assertIsDisplayed()
        compose.onNodeWithTag("owner-analytics-metric-views").assertIsDisplayed()
        capture("analytics-detail-$language-$theme")
        compose.onNodeWithTag("back").performClick()
        compose.onNodeWithTag("owner-analytics-overview").assertIsDisplayed()
        compose.runOnIdle { assertEquals(0, parents) }
        compose.onNodeWithTag("back").performClick()
        compose.runOnIdle { assertEquals(1, parents) }
    }

    @Test fun analyticsUkrainianDark() = analytics("uk", "dark")

    @Test fun analyticsGermanLight() = analytics("de", "light")

    private fun logs(language: String, theme: String) {
        val session = ModerationSession("synthetic-owner", 85, "owner", true)
        val entry =
            SystemLogEntry(
                id = "visual-log",
                createdAt = at,
                category = "diagnostics",
                severity = "critical",
                severityRank = 5,
                eventType = "technicalError",
                actorUserId = null,
                actorDisplayName = "System",
                actorRole = "system",
                targetType = "diagnosticSnapshot",
                targetId = null,
                targetTitle = "Завантаження організацій / Organisationen laden",
                organizationId = null,
                organizationName = null,
                outcome = "failed",
                summary =
                    "Не вдалося оновити список організацій. Verbindung vorübergehend nicht verfügbar.",
                technicalMessage = "Synthetic visual fixture: connection timed out",
                errorCode = "UNAVAILABLE",
                moduleName = "Organizations",
                screenName = "Organisationen",
                operationName = "refresh",
                appVersion = "1.1",
                osVersion = "Android",
                deviceModel = "Synthetic device",
                reviewed = false,
                reviewedAt = null,
                reviewedBy = null,
                metadata = emptyMap(),
                retentionPolicy = "technicalError",
                correlationId = null,
                appAdminReadable = true,
            )
        val source =
            object : SystemLogSource {
                override suspend fun list(
                    session: ModerationSession,
                    access: SystemLogAccess,
                    sort: SystemLogSort,
                ) = listOf(entry)

                override suspend fun find(
                    session: ModerationSession,
                    access: SystemLogAccess,
                    id: String,
                ) = entry

                override suspend fun review(session: ModerationSession, expected: SystemLogEntry) =
                    expected.copy(reviewed = true)

                override suspend fun delete(session: ModerationSession, expected: SystemLogEntry) =
                    error("No mutations in visual test")

                override suspend fun clear(session: ModerationSession) =
                    error("No mutations in visual test")

                override suspend fun testPush(session: ModerationSession) =
                    error("No push in visual test")
            }
        val model = SystemLogsViewModel(SystemLogRepository(source, authority = { session }))
        var parents = 0
        compose.setContent {
            Host(language, theme) { SystemLogsScreen(model, session, language, { parents++ }) }
        }
        compose.waitUntil(5000) {
            model.state.value.logs.isNotEmpty() && !model.state.value.loading
        }
        compose.onAllNodesWithTag("back").assertCountEquals(1)
        compose.onNodeWithTag("system-logs-back").assertDoesNotExist()
        capture("logs-top-$language-$theme")
        compose
            .onNodeWithTag("system-log-list")
            .performScrollToNode(hasTestTag("system-log-row-visual-log"))
        capture("logs-row-$language-$theme")
        compose.onNodeWithTag("system-log-row-visual-log").performClick()
        compose.onNodeWithTag("system-log-detail").assertIsDisplayed()
        capture("logs-detail-$language-$theme")
        compose
            .onNodeWithTag("system-log-detail")
            .performScrollToNode(hasTestTag("system-log-review"))
        compose.onNodeWithTag("system-log-review").assertIsDisplayed()
        capture("logs-actions-$language-$theme")
        compose.onNodeWithTag("back").performClick()
        compose.onNodeWithTag("system-log-list").assertIsDisplayed()
        compose.runOnIdle { assertEquals(0, parents) }
        compose.onNodeWithTag("back").performClick()
        compose.runOnIdle { assertEquals(1, parents) }
    }

    @Test fun logsUkrainianDark() = logs("uk", "dark")

    @Test fun logsGermanLight() = logs("de", "light")
}
