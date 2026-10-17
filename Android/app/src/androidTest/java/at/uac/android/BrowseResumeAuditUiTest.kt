package at.uac.android

import androidx.activity.compose.setContent
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.SavedStateHandle
import at.uac.android.feature.browse.*
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class BrowseResumeAuditUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    @Test fun temporaryPauseRevalidatesDataAndKeepsTheReadingPosition() = verifyResume(insertNews = false)
    @Test fun newNewsDuringPauseDoesNotMoveTheReadingAnchor() = verifyResume(insertNews = true)

    private fun verifyResume(insertNews: Boolean) {
        val context = compose.activity
        val fixtures = ContentJson.fixtures(context).toMutableMap()
        val repo = ContentRepository(SyntheticContentSource(fixtures), MemoryContentCache())
        val vm = compose.runOnIdle { BrowseViewModel(repo, repo, SavedStateHandle(), "de", "", "light", { _, _ -> }) }
        compose.runOnIdle { compose.activity.setContent { BrowseScreen(vm.state.collectAsState().value, vm, {}) } }
        compose.waitUntil(15_000) { !vm.state.value.data.loading }
        compose.runOnIdle { vm.more() }
        compose.waitUntil(15_000) { !vm.state.value.data.loading }
        compose.onNodeWithTag("browse-list").performScrollToNode(hasTestTag("card-synthetic-news-12"))
        compose.onNodeWithTag("card-synthetic-news-12").assertIsDisplayed()
        val originalTop = compose.onNodeWithTag("card-synthetic-news-12").getUnclippedBoundsInRoot().top
        compose.activityRule.scenario.moveToState(Lifecycle.State.STARTED)
        compose.waitForIdle()
        if (insertNews) {
            val sample = fixtures.getValue("news/synthetic-news-18")
            fixtures["news/inserted-while-paused"] = sample.copy(id = "inserted-while-paused",
                fields = sample.fields + ("publishedAt" to Instant.now()))
        }
        compose.activityRule.scenario.moveToState(Lifecycle.State.RESUMED)
        compose.waitUntil(15_000) { !vm.state.value.data.loading }
        compose.onNodeWithTag("card-synthetic-news-12").assertIsDisplayed()
        assertEquals(originalTop.value,
            compose.onNodeWithTag("card-synthetic-news-12").getUnclippedBoundsInRoot().top.value, 2f)
    }
}
