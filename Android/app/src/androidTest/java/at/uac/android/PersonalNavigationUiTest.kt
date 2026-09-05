package at.uac.android

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performScrollToNode
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.browse.BrowseViewModel
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PersonalNavigationUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val browse
        get() = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]

    private fun ready() {
        compose.waitUntil(30_000) { !browse.state.value.data.loading }
        compose.waitForIdle()
    }

    @Before
    fun setup() {
        compose.runOnIdle {
            LocalAuthSession.get(compose.activity).signOut()
            browse.preference("language", "de")
            browse.preference("mode", "synthetic")
            browse.navigate("home", true)
        }
        compose.waitUntil(15_000) {
            LocalAuthSession.get(compose.activity).state.value.stage == AuthStage.GUEST
        }
        ready()
    }

    @Test
    fun fullHeightAccountRouteKeepsGuestAuthAndReturnsToPublicDetail() {
        compose.runOnIdle { browse.navigate("news/synthetic-news-01") }
        ready()
        compose.runOnIdle { browse.navigate("profile") }
        ready()
        compose.onNodeWithTag("account-scroll").assertExists()
        compose.onNodeWithTag("guest-sign-in").performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("browse-list").assertDoesNotExist()
        compose.onNodeWithTag("back").performClick()
        ready()
        compose.onNodeWithTag("detail-content").assertExists()
        compose.runOnIdle {
            org.junit.Assert.assertEquals("news/synthetic-news-01", browse.state.value.route)
        }
    }

    @Test
    fun embeddedExamplesNeverExposeMutationControlsEvenAtMatchingIds() {
        compose.runOnIdle { browse.navigate("news/synthetic-news-01") }
        ready()
        compose
            .onNodeWithTag("browse-list")
            .performScrollToNode(hasTestTag("personal-synthetic-readonly"))
        compose.onNodeWithTag("personal-synthetic-readonly").performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("personal-like").assertDoesNotExist()
        compose.onNodeWithTag("personal-bookmark").assertDoesNotExist()
    }
}
