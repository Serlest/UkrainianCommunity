package at.uac.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.feature.browse.BrowseViewModel
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class BrowseUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val online
        get() = InstrumentationRegistry.getArguments().getString("expectEmulator") == "true"

    private fun ready() {
        val model = compose.runOnIdle {
            ViewModelProvider(compose.activity)[BrowseViewModel::class.java]
        }
        compose.waitUntil(35_000) { !model.state.value.data.loading }
        compose.waitForIdle()
    }

    private fun top() {
        compose.onNodeWithTag("browse-list").performScrollToIndex(0)
    }

    private fun scroll(tag: String) {
        compose.onNodeWithTag("browse-list").performScrollToNode(hasTestTag(tag))
        compose.onNodeWithTag(tag).performScrollTo()
    }

    private fun tab(kind: String) {
        if (kind == "news") {
            compose.onNodeWithTag("tab-home").performClick()
            ready()
            scroll("tab-news")
        }
        compose.onNodeWithTag("tab-$kind").performClick()
        ready()
    }

    @Before
    fun localSetup() {
        ready()
        compose.onNodeWithTag("settings").performClick()
        scroll("browse-language-de")
        compose.onNodeWithTag("browse-language-de").performClick()
        scroll("browse-mode-${if (online) "emulator" else "synthetic"}")
        compose
            .onNodeWithTag("browse-mode-${if (online) "emulator" else "synthetic"}")
            .performClick()
        compose.onNodeWithTag("back").performClick()
        ready()
        scroll("region")
        compose.onNodeWithTag("region").performClick()
        compose.onNodeWithTag("region-").performClick()
        ready()
    }

    @Test
    fun newsPagingSearchDetailAndRecreation() {
        tab("news")
        scroll("load-more")
        compose.onNodeWithTag("load-more").performClick()
        ready()
        scroll("card-synthetic-news-07")
        compose.onNodeWithTag("card-synthetic-news-07").assertIsDisplayed()
        top()
        scroll("search")
        compose.onNodeWithTag("search").performTextReplacement("Suchziel")
        ready()
        scroll("card-synthetic-news-01")
        compose.onNodeWithTag("card-synthetic-news-01").performClick()
        ready()
        compose.onNodeWithText("Beispielnachricht 01").performScrollTo().assertIsDisplayed()
        compose.activityRule.scenario.recreate()
        ready()
        compose.onNodeWithText("Beispielnachricht 01").performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("back").performClick()
        ready()
        top()
        scroll("search")
        compose.onNodeWithTag("search").assertTextContains("Suchziel")
        compose.onNodeWithTag("search").performTextReplacement("does-not-exist")
        ready()
        scroll("empty")
        compose.onNodeWithTag("empty").assertIsDisplayed()
    }

    @Test
    fun eventUpcomingPastAudienceAndCancelled() {
        tab("events")
        scroll("card-synthetic-event-03")
        compose.onNodeWithTag("card-synthetic-event-03").performClick()
        ready()
        compose.onNodeWithText("Abgesagt", substring = false).performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("back").performClick()
        ready()
        top()
        scroll("past")
        compose.onNodeWithTag("past").performClick()
        ready()
        scroll("card-synthetic-event-18")
        compose.onNodeWithTag("card-synthetic-event-18").assertIsDisplayed()
        top()
        scroll("upcoming")
        compose.onNodeWithTag("upcoming").performClick()
        ready()
        scroll("audience")
        compose.onNodeWithTag("audience").performClick()
        compose.onNodeWithTag("audience-families").performClick()
        ready()
        scroll("card-synthetic-event-02")
        compose.onNodeWithTag("card-synthetic-event-02").performClick()
        ready()
        compose.onNodeWithText("Ausgebucht").performScrollTo().assertIsDisplayed()
    }

    @Test
    fun organizationPublicTeamPhotosAndRelatedNews() {
        tab("organizations")
        scroll("search")
        compose.onNodeWithTag("search").performTextReplacement("01")
        ready()
        scroll("card-synthetic-org-01")
        compose.onNodeWithTag("card-synthetic-org-01").performClick()
        ready()
        compose.onNodeWithText("Demo · Олена").performScrollTo().assertIsDisplayed()
        compose
            .onNodeWithContentDescription("Demo · Приклад")
            .performScrollTo()
            .assertIsDisplayed()
            .performClick()
        compose.onNodeWithText("Demo · Приклад").assertIsDisplayed()
        compose.onNodeWithTag("public-gallery-done").assertIsDisplayed().performClick()
        compose.onNodeWithTag("public-gallery-viewer").assertDoesNotExist()
        compose.onNodeWithTag("organization-news").performScrollTo().performClick()
        ready()
        scroll("card-synthetic-news-18")
        compose.onNodeWithTag("card-synthetic-news-18").assertIsDisplayed()
        compose.onNodeWithTag("back").performClick()
        ready()
        compose.onNodeWithText("Beispielverein 01").performScrollTo().assertIsDisplayed()
    }

    @Test
    fun languageRegionThemeAndBannerNavigation() {
        tab("home")
        scroll("banner-open")
        compose.onNodeWithTag("banner-open").performClick()
        ready()
        compose.onNodeWithText("Beispielnachricht 01").performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("back").performClick()
        ready()
        compose.onNodeWithTag("settings").performClick()
        scroll("browse-language-uk")
        compose.onNodeWithTag("browse-language-uk").performClick()
        scroll("theme")
        compose.onNodeWithTag("theme").performClick()
        compose.onNodeWithTag("theme-dark").performClick()
        compose.onNodeWithTag("back").performClick()
        ready()
        scroll("banner-text")
        compose.onNodeWithText("Перегляньте локальні приклади").assertIsDisplayed()
        tab("news")
        scroll("region")
        compose.onNodeWithTag("region").performClick()
        compose.onNodeWithTag("region-wien").performScrollTo().performClick()
        ready()
        scroll("search")
        compose.onNodeWithTag("search").performTextReplacement("18")
        ready()
        compose.runOnIdle {
            val state = ViewModelProvider(compose.activity)[BrowseViewModel::class.java].state.value
            org.junit.Assert.assertTrue(
                "region=${state.region}, search=${state.search}, route=${state.route}, items=${state.data.items.map { it.id }}, error=${state.data.error}",
                state.data.items.isEmpty() && state.region == "wien" && state.search == "18",
            )
        }
        scroll("empty")
        compose.onNodeWithTag("empty").assertIsDisplayed()
        compose.activityRule.scenario.recreate()
        ready()
        top()
        scroll("search")
        compose.onNodeWithTag("search").assertTextContains("18")
    }
}
