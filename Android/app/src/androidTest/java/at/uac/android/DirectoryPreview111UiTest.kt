package at.uac.android

import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import at.uac.android.design.UacTheme
import at.uac.android.feature.directory.*
import at.uac.android.feature.browse.ReadFailure
import java.time.Instant
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class DirectoryPreview111UiTest {
    @get:Rule val compose = createComposeRule()
    private fun item(id: Int) = DirectoryRecentItem("$id", "topic", "safety", "emergency", null, null,
        Instant.parse("2026-10-18T08:00:00Z"), 1, DirectoryText("Тема $id", "Thema $id"),
        DirectoryText("Тема", "Thema"), DirectoryText("Безпека", "Sicherheit"))

    @Test fun previewLimitsRowsAndOpensFullLoadedFeedWithoutFetching() {
        val preview = mutableStateOf(true)
        var fetches = 0
        val state = DirectoryRecentState((1..20).map(::item), loaded = true)
        compose.setContent { UacTheme("light") {
            LazyColumn(Modifier.testTag("test-list")) {
                directoryRecentItems(state, "uk", { assertEquals("directory/recent", it); preview.value = false },
                    { fetches++ }, {}, {}, preview = preview.value)
            }
        } }
        var fourthFound = false
        try {
            compose.onNodeWithTag("test-list").performScrollToNode(hasTestTag("directory-recent-4"))
            fourthFound = true
        } catch (_: AssertionError) { }
        assertFalse("Preview must not contain a fourth row even after scrolling", fourthFound)
        compose.onNodeWithTag("test-list").performScrollToNode(hasTestTag("directory-recent-show-all"))
        compose.onNodeWithText("Показати більше").assertIsDisplayed().performClick()
        compose.onNodeWithTag("test-list").performScrollToNode(hasTestTag("directory-recent-20"))
        compose.onNodeWithTag("directory-recent-20").assertIsDisplayed()
        assertEquals(0, fetches)
        compose.onNodeWithTag("directory-recent-show-all").assertDoesNotExist()
    }

    @Test fun threeRowsWithServerContinuationShowsMoreAndTerminalPageHidesIt() {
        val state = mutableStateOf(DirectoryRecentState((1..3).map(::item), loaded = true, hasMore = true))
        var opened = ""
        compose.setContent { UacTheme("light") {
            LazyColumn(Modifier.testTag("test-list")) {
                directoryRecentItems(state.value, "de", { opened = it }, {}, {}, {}, preview = true)
            }
        } }
        compose.onNodeWithTag("test-list").performScrollToNode(hasTestTag("directory-recent-show-all"))
        compose.onNodeWithText("Mehr anzeigen").performClick()
        assertEquals("directory/recent", opened)
        compose.onNodeWithTag("directory-recent-more").assertDoesNotExist()
        compose.runOnIdle { state.value = state.value.copy(hasMore = false) }
        compose.onNodeWithTag("directory-recent-show-all").assertDoesNotExist()
        compose.runOnIdle { state.value = DirectoryRecentState(loaded = true) }
        compose.onNodeWithTag("directory-recent-show-all").assertDoesNotExist()
        compose.onNodeWithTag("directory-recent-empty").assertExists()
    }

    @Test fun noWelcomeHeroAndBannerFailureCanRetryWithoutInventedBanner() {
        val failure = mutableStateOf<ReadFailure?>(ReadFailure.OFFLINE)
        var retries = 0
        val recent = DirectoryRecentViewModel { DirectoryRecentPage(emptyList(), null, false) }
        compose.setContent { UacTheme("light") {
            DirectoryDestination("directory", "de", "", {}, {}, { _, _, _ -> }, recentModel = recent,
                bannerFailure = failure.value, onBannerRetry = { retries++; failure.value = null })
        } }
        compose.onNodeWithTag("directory-browse-sections").assertDoesNotExist()
        compose.onNodeWithTag("directory-banner-retry").performClick()
        assertEquals(1, retries)
        compose.onNodeWithTag("directory-banner-error").assertDoesNotExist()
        compose.onNodeWithTag("directory-categories-heading").assertIsDisplayed()
    }
}
