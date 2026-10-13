package at.uac.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.browse.NewsOrder
import at.uac.android.feature.browse.NewsPeriod
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

    private fun openSearch() {
        if (compose.onAllNodesWithTag("header-search-field").fetchSemanticsNodes().isEmpty())
            compose.onNodeWithTag("header-search-toggle").performClick()
    }

    private fun openSettings() {
        compose.onNodeWithTag("tab-profile").performClick()
        ready()
        compose.onNodeWithTag("settings").performClick()
    }

    private fun scrollPrimary(tag: String) {
        scroll(tag)
    }

    private fun tab(kind: String) {
        if (kind == "news") {
            compose.onNodeWithTag("tab-home").performClick()
            ready()
            return
        }
        compose.onNodeWithTag("tab-$kind").performClick()
        ready()
    }

    @Before
    fun localSetup() {
        ready()
        openSettings()
        scroll("browse-language-de")
        compose.onNodeWithTag("browse-language-de").performClick()
        scroll("browse-mode-${if (online) "emulator" else "synthetic"}")
        compose
            .onNodeWithTag("browse-mode-${if (online) "emulator" else "synthetic"}")
            .performClick()
        compose.onNodeWithTag("back").performClick()
        ready()
        compose.onNodeWithTag("tab-home").performClick()
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
        openSearch()
        compose.onNodeWithTag("header-search-field").performTextReplacement("Suchziel")
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
        openSearch()
        compose.onNodeWithTag("header-search-field").assertTextContains("Suchziel")
        compose.onNodeWithTag("header-search-field").performTextReplacement("does-not-exist")
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
        scrollPrimary("news-filters")
        compose.onNodeWithTag("news-filters").performClick()
        compose.onNodeWithTag("past").performScrollTo()
        compose.onNodeWithTag("past").performClick()
        compose.onNodeWithTag("content-filter-done").performScrollTo().performClick()
        ready()
        scroll("card-synthetic-event-18")
        compose.onNodeWithTag("card-synthetic-event-18").assertIsDisplayed()
        top()
        scrollPrimary("news-filters")
        compose.onNodeWithTag("news-filters").performClick()
        compose.onNodeWithTag("upcoming").performScrollTo()
        compose.onNodeWithTag("upcoming").performClick()
        compose.onNodeWithTag("content-filter-done").performScrollTo().performClick()
        ready()
        scrollPrimary("news-filters")
        compose.onNodeWithTag("news-filters").performClick()
        compose.onNodeWithTag("audience-families").performScrollTo().performClick()
        compose.onNodeWithTag("content-filter-done").performScrollTo().performClick()
        ready()
        scroll("card-synthetic-event-02")
        compose.onNodeWithTag("card-synthetic-event-02").performClick()
        ready()
        compose.onNodeWithText("Ausgebucht").performScrollTo().assertIsDisplayed()
    }

    @Test
    fun organizationPublicTeamPhotosAndRelatedNews() {
        tab("organizations")
        openSearch()
        compose.onNodeWithTag("header-search-field").performTextReplacement("01")
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
        openSettings()
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
        openSearch()
        compose.onNodeWithTag("header-search-field").performTextReplacement("18")
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
        openSearch()
        compose.onNodeWithTag("header-search-field").assertTextContains("18")
    }

    @Test
    fun publicChromeKeepsHeroBeforeCompactFiltersAndSearchOnDemand() {
        tab("home")
        top()
        compose.onNodeWithTag("browse-pull-refresh").assertExists()
        compose.onNodeWithTag("refresh").assertDoesNotExist()
        val heroTop = compose.onNodeWithTag("banner-hero").fetchSemanticsNode().boundsInRoot.top
        val controlsTop =
            compose.onNodeWithTag("primary-filter-row").fetchSemanticsNode().boundsInRoot.top
        org.junit.Assert.assertTrue("hero=$heroTop controls=$controlsTop", heroTop < controlsTop)
        scrollPrimary("news-quick-source-SAVED")
        compose.onNodeWithTag("news-quick-source-SAVED").assertExists()

        tab("news")
        top()
        compose.onNodeWithTag("header-search-field").assertDoesNotExist()
        compose.onNodeWithTag("header-search-toggle").performClick()
        compose.onNodeWithTag("header-search-field").assertIsDisplayed()
        compose.onNodeWithTag("news-quick-source-SAVED").assertExists()

        tab("events")
        scrollPrimary("event-quick-scope-REGISTERED")
        compose.onNodeWithTag("event-quick-scope-REGISTERED").assertExists()
        tab("organizations")
        scrollPrimary("organization-quick-scope-SUBSCRIBED")
        compose.onNodeWithTag("organization-quick-scope-SUBSCRIBED").assertExists()
    }

    @Test
    fun newsPeriodAndOrderApplyTogetherWhileCancelKeepsSelection() {
        tab("news")
        scrollPrimary("news-filters")
        compose.onNodeWithTag("news-filters").performClick()
        compose.onNodeWithTag("news-period-SEVEN_DAYS").performScrollTo().performClick()
        compose.onNodeWithTag("news-order-OLDEST").performScrollTo().performClick()
        compose.onNodeWithTag("news-filter-apply").performScrollTo().performClick()
        ready()
        compose.runOnIdle {
            val state = ViewModelProvider(compose.activity)[BrowseViewModel::class.java].state.value
            org.junit.Assert.assertEquals(NewsPeriod.SEVEN_DAYS, state.newsPeriod)
            org.junit.Assert.assertEquals(NewsOrder.OLDEST, state.newsOrder)
        }

        scrollPrimary("news-filters")
        compose.onNodeWithTag("news-filters").performClick()
        compose.onNodeWithTag("news-period-ALL").performScrollTo().performClick()
        compose.onNodeWithText("Abbrechen").performScrollTo().performClick()
        compose.runOnIdle {
            val state = ViewModelProvider(compose.activity)[BrowseViewModel::class.java].state.value
            org.junit.Assert.assertEquals(NewsPeriod.SEVEN_DAYS, state.newsPeriod)
            org.junit.Assert.assertEquals(NewsOrder.OLDEST, state.newsOrder)
        }
    }
}
