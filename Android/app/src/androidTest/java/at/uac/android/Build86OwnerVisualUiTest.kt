package at.uac.android

import android.graphics.Bitmap
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.design.*
import at.uac.android.feature.donationsettings.*
import at.uac.android.feature.moderation.ModerationSession
import at.uac.android.feature.owneranalytics.*
import at.uac.android.feature.systemlogs.*
import java.io.File
import java.time.Instant
import org.junit.Rule
import org.junit.Test

/** Every owner branch uses synthetic data. No production reads, pushes or mutations. */
class Build86OwnerVisualUiTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val owner = ModerationSession("synthetic-owner", 86, "owner", true)
    private val now = Instant.parse("2026-09-10T10:00:00Z")

    @Composable
    private fun Host(language: String, theme: String, content: @Composable () -> Unit) {
        SideEffect {
            WindowCompat.getInsetsController(
                    compose.activity.window,
                    compose.activity.window.decorView,
                )
                .apply {
                    isAppearanceLightStatusBars = theme == "light"
                    isAppearanceLightNavigationBars = theme == "light"
                }
        }
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
                    Box(
                        Modifier.weight(1f)
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp)
                            .testTag("visual-body")
                    ) {
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
        val bitmap = compose.onRoot().captureToImage().asAndroidBitmap()
        try {
            File(instrumentation.targetContext.cacheDir, "build86-owner-$name.png")
                .outputStream()
                .use {
                    check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it))
                }
        } finally {
            bitmap.recycle()
        }
    }

    private fun at(list: String, tag: String, name: String) {
        compose.onNodeWithTag(list).performScrollToNode(hasTestTag(tag))
        compose.onNodeWithTag(tag).assertIsDisplayed()
        capture(name)
    }

    private fun donation(language: String, theme: String) {
        val draft = DonationDraft(enabled = true, url = "https://example.org/support")
        val state =
            mutableStateOf(
                DonationSettingsState(
                    session = owner,
                    baseline = DonationSnapshot(draft, now, true),
                    draft = draft,
                )
            )
        compose.setContent {
            Host(language, theme) {
                DonationSettingsContent(
                    state.value,
                    language,
                    { state.value = state.value.copy(draft = it) },
                    {},
                    {},
                    { state.value = state.value.copy(confirmLeave = true) },
                    { state.value = state.value.copy(confirmLeave = false) },
                    { state.value = state.value.copy(confirmLeave = false) },
                )
            }
        }
        val suffix = "$language-$theme"
        capture("donation-top-$suffix")
        for (field in donationTextKeys) at(
            "donation-settings",
            "donation-$field",
            "donation-$field-$suffix",
        )
        compose
            .onNodeWithTag("donation-buttonTitleDE")
            .performTextReplacement("Projekt unterstützen")
        compose.runOnIdle { state.value = state.value.copy(confirmLeave = true) }
        compose.waitForIdle()
        // Protected dialogs are inspected via their Compose root, never weakening FLAG_SECURE.
        val dialog = compose.onNode(isDialog())
        dialog.assertExists()
        val image = dialog.captureToImage()
        val bitmap = image.asAndroidBitmap()
        File(
                InstrumentationRegistry.getInstrumentation().targetContext.cacheDir,
                "build86-owner-donation-discard-$suffix.png",
            )
            .outputStream()
            .use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        val cancelBounds =
            compose
                .onNodeWithTag("donation-continue-editing")
                .assertIsDisplayed()
                .fetchSemanticsNode()
                .boundsInRoot
        val dialogBounds = dialog.fetchSemanticsNode().boundsInRoot
        check(cancelBounds.bottom <= dialogBounds.bottom) {
            "Continue editing must fit inside dialog"
        }
        compose.onNodeWithTag("donation-continue-editing").performClick()
        compose.onNode(isDialog()).assertDoesNotExist()
        for (problem in DonationProblem.entries) {
            compose.runOnIdle {
                state.value =
                    state.value.copy(
                        problem = problem,
                        needsReadback = problem == DonationProblem.UNCONFIRMED,
                    )
            }
            at("donation-settings", "donation-error", "donation-error-${problem.name}-$suffix")
        }
        compose.runOnIdle { state.value = state.value.copy(problem = null, saving = true) }
        at("donation-settings", "donation-save", "donation-saving-$suffix")
        compose.onNodeWithTag("donation-save").assertIsNotEnabled()
    }

    @Test fun donationUkDark() = donation("uk", "dark")

    @Test fun donationDeLight() = donation("de", "light")

    private fun analytics(language: String, theme: String) {
        val session = OwnerAnalyticsSession(owner.uid, 86, true)
        var mode = "populated"
        val regions =
            listOf(
                AnalyticsRegion("tirol", "federalState", "tirol", 1248, 24, mapOf("views" to 1248))
            )
        val top =
            listOf(
                AnalyticsTopItem(
                    "organization",
                    "organization",
                    "Українська громада Тіролю · Ukrainische Gemeinschaft Tirol",
                    1248,
                    1,
                ),
                AnalyticsTopItem(
                    "news",
                    "news",
                    "Допомога родинам та корисні контакти у вашому регіоні",
                    318,
                    2,
                ),
                AnalyticsTopItem(
                    "event",
                    "event",
                    "Begegnung der Familien und offener Austausch in Innsbruck",
                    240,
                    3,
                ),
            )
        val repository =
            object : OwnerAnalyticsRepository {
                override suspend fun overview(
                    session: OwnerAnalyticsSession,
                    period: AnalyticsPeriod,
                ): OwnerAnalyticsSnapshot {
                    if (mode == "error")
                        throw OwnerAnalyticsException(OwnerAnalyticsFailure.OFFLINE)
                    return OwnerAnalyticsSnapshot(
                        period,
                        now,
                        if (mode == "empty") emptyMap()
                        else mapOf("totalViews" to 1248, "newsViews" to 318, "eventViews" to 240),
                        mapOf("totalViews" to 980),
                        if (mode == "empty") emptyList()
                        else
                            listOf(
                                "09.09.2026" to mapOf("totalViews" to 120),
                                "10.09.2026" to mapOf("totalViews" to 180),
                            ),
                        if (mode == "empty") emptyList() else top,
                        if (mode == "empty") emptyList() else regions,
                        if (mode == "empty") AnalyticsUsers()
                        else
                            AnalyticsUsers(
                                total = 184,
                                activeToday = 36,
                                byFederalState = mapOf("tirol" to 184),
                            ),
                        if (mode == "partial") setOf("users") else emptySet(),
                    )
                }

                override suspend fun detail(
                    session: OwnerAnalyticsSession,
                    period: AnalyticsPeriod,
                    type: String,
                    id: String,
                ): AnalyticsDetail =
                    AnalyticsDetail(
                        type,
                        id,
                        top.firstOrNull { it.id == id }?.title ?: id,
                        period,
                        mapOf("views" to 318, "likes" to 18),
                        regions,
                        if (type == "organization") listOf(top[1]) else emptyList(),
                        if (type == "organization") listOf(top[2]) else emptyList(),
                        now,
                        "09.09.2026",
                    )
            }
        val model = OwnerAnalyticsViewModel(repository)
        compose.setContent {
            Host(language, theme) { OwnerAnalyticsScreen(model, session, language, {}) }
        }
        compose.waitUntil(5000) { model.state.value.snapshot != null }
        val suffix = "$language-$theme"
        capture("analytics-overview-$suffix")
        for (period in AnalyticsPeriod.entries) {
            compose
                .onNodeWithTag("owner-analytics-overview")
                .performScrollToNode(hasTestTag("owner-analytics-period-${period.name}"))
            compose.onNodeWithTag("owner-analytics-period-${period.name}").performClick()
            compose.onNodeWithTag("owner-analytics-period-${period.name}").assertIsSelected()
            capture("analytics-period-${period.name}-$suffix")
        }
        at("owner-analytics-overview", "owner-analytics-trend", "analytics-trend-$suffix")
        at("owner-analytics-overview", "owner-analytics-region-tirol", "analytics-regions-$suffix")
        at(
            "owner-analytics-overview",
            "owner-analytics-metric-totalUsers",
            "analytics-users-$suffix",
        )
        for (entry in top) {
            at(
                "owner-analytics-overview",
                "owner-analytics-top-${entry.type}-${entry.id}",
                "analytics-list-${entry.type}-$suffix",
            )
            compose.onNodeWithTag("owner-analytics-top-${entry.type}-${entry.id}").performClick()
            capture("analytics-detail-${entry.type}-$suffix")
            at(
                "owner-analytics-detail",
                "owner-analytics-region-tirol",
                "analytics-detail-region-${entry.type}-$suffix",
            )
            if (entry.type == "organization") {
                for (related in listOf(top[1], top[2])) {
                    at(
                        "owner-analytics-detail",
                        "owner-analytics-related-${related.id}",
                        "analytics-related-${related.id}-$suffix",
                    )
                    compose.onNodeWithTag("owner-analytics-related-${related.id}").performClick()
                    val detailBounds =
                        compose
                            .onNodeWithTag("owner-analytics-detail")
                            .fetchSemanticsNode()
                            .boundsInRoot
                    val periodBounds =
                        compose
                            .onNodeWithTag("owner-analytics-period-TODAY")
                            .assertIsDisplayed()
                            .fetchSemanticsNode()
                            .boundsInRoot
                    check(periodBounds.top >= detailBounds.top) {
                        "New analytics detail must start at the top"
                    }
                    capture("analytics-related-detail-${related.id}-$suffix")
                    compose.runOnIdle { model.open(session, "organization", "organization") }
                }
            }
            compose.onNodeWithTag("back").performClick()
        }
        for (value in listOf("partial", "empty", "error")) {
            compose.runOnIdle {
                mode = value
                model.load(session, true)
            }
            compose.waitForIdle()
            at(
                "owner-analytics-overview",
                if (value == "partial") "owner-analytics-partial"
                else if (value == "empty") "owner-analytics-empty" else "owner-analytics-error",
                "analytics-$value-$suffix",
            )
        }
    }

    @Test fun analyticsUkDark() = analytics("uk", "dark")

    @Test fun analyticsDeLight() = analytics("de", "light")

    private fun logs(language: String, theme: String) {
        var mode = "populated"
        val entry =
            SystemLogEntry(
                "visual-log",
                now,
                "diagnostics",
                "critical",
                5,
                "technicalError",
                null,
                "System",
                "system",
                "diagnosticSnapshot",
                null,
                "Завантаження організацій",
                null,
                null,
                "failed",
                "Не вдалося оновити список організацій. Bitte die Verbindung prüfen und erneut versuchen.",
                "Synthetic connection timeout — no production data",
                "UNAVAILABLE",
                "Organizations",
                "Organizations",
                "refresh",
                "1.1",
                "Android",
                "Synthetic AVD",
                false,
                null,
                null,
                mapOf("source" to "synthetic"),
                "technicalError",
                "synthetic-operation-id",
                true,
            )
        val source =
            object : SystemLogSource {
                override suspend fun list(
                    session: ModerationSession,
                    access: SystemLogAccess,
                    sort: SystemLogSort,
                ): List<SystemLogEntry> {
                    if (mode == "error") throw SystemLogException(SystemLogFailure.OFFLINE)
                    return if (mode == "empty") emptyList() else listOf(entry)
                }

                override suspend fun find(
                    session: ModerationSession,
                    access: SystemLogAccess,
                    id: String,
                ) = entry

                override suspend fun review(session: ModerationSession, expected: SystemLogEntry) =
                    expected.copy(reviewed = true)

                override suspend fun delete(session: ModerationSession, expected: SystemLogEntry) =
                    error("Visual test must not delete")

                override suspend fun clear(session: ModerationSession) =
                    error("Visual test must not clear")

                override suspend fun testPush(session: ModerationSession) =
                    error("Visual test must not send push")
            }
        val model = SystemLogsViewModel(SystemLogRepository(source, authority = { owner }))
        compose.setContent {
            Host(language, theme) { SystemLogsScreen(model, owner, language, {}) }
        }
        compose.waitUntil(5000) { model.state.value.logs.isNotEmpty() }
        val suffix = "$language-$theme"
        capture("logs-list-$suffix")
        at("system-log-list", "system-log-toggle-filters", "logs-filter-entry-$suffix")
        compose.onNodeWithTag("system-log-toggle-filters").performClick()
        at("system-log-list", "system-log-filter-SEVEN_DAYS", "logs-filters-$suffix")
        at("system-log-list", "system-log-row-visual-log", "logs-row-$suffix")
        compose.onNodeWithTag("system-log-row-visual-log").performClick()
        capture("logs-detail-$suffix")
        at("system-log-detail", "system-log-delete", "logs-detail-bottom-$suffix")
        compose.onNodeWithTag("system-log-delete").performClick()
        at("system-log-detail", "system-log-delete-confirm", "logs-delete-confirm-$suffix")
        at("system-log-detail", "system-log-delete-cancel", "logs-delete-cancel-$suffix")
        compose.onNodeWithTag("system-log-delete-cancel").performClick()
        compose.onNodeWithTag("system-log-delete-confirm").assertDoesNotExist()
        compose.onNodeWithTag("back").performClick()
        at("system-log-list", "system-log-test-push", "logs-diagnostics-$suffix")
        compose.onNodeWithTag("system-log-clear").performClick()
        at("system-log-list", "system-log-clear-confirm", "logs-clear-confirm-$suffix")
        at("system-log-list", "system-log-clear-cancel", "logs-clear-cancel-$suffix")
        compose.onNodeWithTag("system-log-clear-cancel").performClick()
        compose.onNodeWithTag("system-log-clear-confirm").assertDoesNotExist()
        for (value in listOf("empty", "error")) {
            compose.runOnIdle {
                mode = value
                model.load(owner)
            }
            compose.waitForIdle()
            at("system-log-list", "system-log-$value", "logs-$value-$suffix")
        }
    }

    @Test fun logsUkDark() = logs("uk", "dark")

    @Test fun logsDeLight() = logs("de", "light")
}
