package at.uac.android

import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.design.UacTheme
import at.uac.android.feature.directory.*
import java.time.Instant
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class DirectoryRecentUiTest {
    @get:Rule val compose = createComposeRule()
    private fun item(id: String, region: String? = null) = DirectoryRecentItem(id, "section", "safety",
        "domestic-violence", "regional-protection", region, Instant.parse("2026-10-17T12:00:00Z"), 1,
        DirectoryText("Нова допомога", "Neue Hilfe"), DirectoryText("Домашнє насильство", "Häusliche Gewalt"),
        DirectoryText("Безпека та захист", "Sicherheit & Schutz"))
    private fun screenshot(name: String) {
        compose.waitForIdle()
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        java.io.File(context.cacheDir, name).outputStream().use { output ->
            compose.onRoot().captureToImage().asAndroidBitmap().compress(android.graphics.Bitmap.CompressFormat.PNG, 100, output)
        }
    }
    @Test fun feedShowsLoadingErrorRetryPaginationAndRegionalTargetInGerman() {
        val state = mutableStateOf(DirectoryRecentState(loading = true))
        var opened = ""
        var refreshed = false
        compose.setContent { UacTheme("light") {
            DirectoryRecentScreen(state.value, "de", { opened = it },
                { state.value = state.value.copy(items = state.value.items + item("b", "tirol"), hasMore = false) },
                { state.value = DirectoryRecentState(listOf(item("a", "wien")), loaded = true, hasMore = true) },
                { refreshed = true })
        } }
        compose.onNodeWithTag("directory-recent-loading").assertIsDisplayed()
        compose.onNodeWithTag("directory-recent-empty").assertDoesNotExist()
        compose.runOnIdle { state.value = DirectoryRecentState(failed = true) }
        compose.onNodeWithTag("directory-recent-retry").performClick()
        compose.onNodeWithText("Neuer Abschnitt · Wien").assertIsDisplayed()
        compose.onNodeWithTag("directory-recent-a").performClick()
        assertEquals("directory/safety/domestic-violence?section=regional-protection&region=wien", opened)
        screenshot("directory-recent-de-light.png")
        compose.onNodeWithTag("directory-recent-more").performClick()
        compose.onNodeWithTag("directory-recent-b").assertExists()
        compose.onNodeWithTag("directory-recent-more").assertDoesNotExist()
        compose.onNodeWithTag("directory-recent-refresh").performClick()
        assertTrue(refreshed)
    }
    @Test fun ukrainianDarkEmptyAndHiddenScanContinuationHaveNoInventedHistory() {
        val state = mutableStateOf(DirectoryRecentState(loaded = true))
        compose.setContent { UacTheme("dark") {
            androidx.compose.material3.Surface(color = androidx.compose.material3.MaterialTheme.colorScheme.background) {
                DirectoryRecentScreen(state.value, "uk", {}, {}, {}, {})
            }
        } }
        compose.onNodeWithTag("directory-recent-empty").assertIsDisplayed()
        compose.onNodeWithText("17.10.2026 · 14:00").assertDoesNotExist()
        compose.runOnIdle { state.value = state.value.copy(hasMore = true) }
        compose.onNodeWithTag("directory-recent-empty").assertDoesNotExist()
        compose.onNodeWithTag("directory-recent-more").assertIsDisplayed()
        compose.runOnIdle { state.value = DirectoryRecentState(listOf(item("uk", "wien")), loaded = true) }
        compose.onNodeWithText("Новий блок · Відень").assertIsDisplayed()
        screenshot("directory-recent-uk-dark.png")
    }
    @Test fun rootShowsRecentFeedAfterSafetyAndBeforeStartWithoutChangingGlobalRegion() {
        var global = "tirol"
        val model = DirectoryRecentViewModel { DirectoryRecentPage(listOf(item("root", "wien")), null, false) }
        compose.setContent { UacTheme("light") {
            DirectoryDestination("directory", "de", global, { global = it }, {}, { _, _, _ -> }, recentModel = model)
        } }
        compose.onNodeWithTag("directory-list").performScrollToNode(hasTestTag("directory-recent-heading"))
        compose.onNodeWithTag("directory-recent-heading").assertIsDisplayed()
        assertEquals("tirol", global)
        compose.onNodeWithText("Ankommen in Österreich").assertExists()
        screenshot("directory-recent-root-placement.png")
    }
    @Test fun regionalDeepLinkScrollsToBlockAndKeepsRegionLocal() {
        val global = "tirol"
        var mutations = 0
        compose.setContent { UacTheme("light") {
            DirectoryDestination("directory/safety/domestic-violence?section=regional-protection&region=wien", "de",
                global, { mutations++ }, {}, { _, _, _ -> })
        } }
        compose.waitUntil(10_000) {
            compose.onAllNodesWithTag("directory-section-regional-protection").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("directory-section-regional-protection").assertIsDisplayed()
        assertEquals(0, mutations)
        compose.onNodeWithTag("directory-list").performScrollToNode(hasTestTag("directory-region"))
        compose.onNodeWithTag("directory-region").performClick()
        compose.onNodeWithTag("directory-region-burgenland").performClick()
        assertEquals(0, mutations)
        assertEquals("tirol", global)
        screenshot("directory-recent-region-anchor.png")
    }
    @Test fun removedSectionShowsStaleTargetNoticeInsteadOfHistoricalBody() {
        compose.setContent { UacTheme("light") {
            DirectoryDestination("directory/safety/emergency?section=removed-block", "uk", "", {}, {}, { _, _, _ -> })
        } }
        compose.waitUntil(10_000) { compose.onAllNodesWithTag("directory-target-missing").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("directory-target-missing").assertIsDisplayed()
        compose.onNodeWithTag("directory-section-choose").assertDoesNotExist()
    }
}
