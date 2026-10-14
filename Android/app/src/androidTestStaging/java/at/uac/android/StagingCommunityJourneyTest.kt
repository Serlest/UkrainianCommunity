package at.uac.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.feature.auth.AuthGate
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.community.CommunityViewModel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Only the disposable step-5 account and content supplied by the staging runner. */
@RunWith(AndroidJUnit4::class)
class StagingCommunityJourneyTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val args get() = InstrumentationRegistry.getArguments()
    private val suffix get() = args.getString("communitySuffix").orEmpty()
    private val eventId get() = "community-step5-event-$suffix"
    private val newsId get() = "community-step5-news-$suffix"

    private fun login() {
        assertEquals("at.serlest.ukrainiancommunity.staging", compose.activity.packageName)
        assertTrue(suffix.matches(Regex("[a-f0-9]{16}")))
        val email = args.getString("communityEmail").orEmpty()
        val password = args.getString("communityPassword").orEmpty()
        assertEquals("community-step5-$suffix@example.invalid", email)
        assertTrue(password.length >= 20)
        val auth = LocalAuthSession.get(compose.activity)
        compose.runOnIdle { auth.signOut() }
        compose.waitUntil(60_000) { compose.onAllNodesWithTag("auth-login-submit").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("auth-email").performScrollTo().performTextInput(email)
        compose.onNodeWithTag("auth-password").performScrollTo().performTextInput(password)
        compose.onNodeWithTag("auth-login-submit").performScrollTo().performClick()
        compose.waitUntil(60_000) {
            auth.state.value.let { it.stage == AuthStage.AUTHENTICATED && it.gate == AuthGate.READY }
        }
    }

    private fun open(path: String, tag: String) {
        val browse = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]
        compose.runOnIdle { browse.navigate(path) }
        compose.waitUntil(60_000) {
            browse.state.value.let { it.detailId == path.substringAfter('/') && !it.data.loading && it.data.detail != null }
        }
        compose.waitUntil(60_000) {
            runCatching { compose.onAllNodesWithTag("browse-list").fetchSemanticsNodes().isNotEmpty() }
                .getOrDefault(false)
        }
        compose.waitUntil(60_000) {
            runCatching { compose.onAllNodesWithTag("community-panel").fetchSemanticsNodes().isNotEmpty() }
                .getOrDefault(false)
        }
        val community = ViewModelProvider(compose.activity)[CommunityViewModel::class.java]
        if (tag == "registration-toggle")
            compose.waitUntil(60_000) { community.state.value.participation != null }
        if (tag == "comment-draft")
            compose.waitUntil(60_000) { community.state.value.page?.cached == false }
        compose.waitForIdle()
        compose.onNodeWithTag("browse-list").performScrollToNode(hasTestTag(tag))
        compose.onNodeWithTag(tag).assertIsDisplayed()
    }

    @Test fun registerAndCommentThroughUi() {
        login()
        val community = ViewModelProvider(compose.activity)[CommunityViewModel::class.java]
        open("events/$eventId", "registration-toggle")
        compose.waitUntil(60_000) { community.state.value.participation != null }
        assertEquals(false, community.state.value.participation?.registered)
        compose.onNodeWithTag("registration-toggle").performClick()
        compose.waitUntil(60_000) {
            community.state.value.let { !it.registrationBusy && it.participation?.registered == true }
        }
        assertNull(community.state.value.registrationError)
        open("news/$newsId", "comment-draft")
        compose.waitUntil(60_000) { community.state.value.page?.cached == false }
        compose.onNodeWithTag("comment-draft").performTextInput("Staging comment $suffix")
        compose.onNodeWithTag("browse-list").performScrollToNode(hasTestTag("comment-send"))
        compose.onNodeWithTag("comment-send").performClick()
        compose.waitUntil(60_000) {
            community.state.value.let { !it.sending && it.sentId != null }
        }
        assertNull(community.state.value.actionError)
    }

    @Test fun cancelRegistrationThroughUi() {
        login()
        val community = ViewModelProvider(compose.activity)[CommunityViewModel::class.java]
        open("events/$eventId", "registration-toggle")
        compose.waitUntil(60_000) { community.state.value.participation?.registered == true }
        compose.onNodeWithTag("registration-toggle").performClick()
        compose.onNodeWithTag("registration-confirm-cancel").performClick()
        compose.waitUntil(60_000) {
            community.state.value.let { !it.registrationBusy && it.participation?.registered == false }
        }
        assertNull(community.state.value.registrationError)
    }

    @Test fun grantAnalyticsConsentThroughUi() {
        login()
        val browse = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]
        compose.runOnIdle { browse.navigate("profile/preferences") }
        compose.waitUntil(60_000) {
            runCatching { compose.onAllNodesWithTag("analytics-consent-switch").fetchSemanticsNodes().isNotEmpty() }
                .getOrDefault(false)
        }
        compose.onNodeWithTag("analytics-consent-switch").performScrollTo().assertIsOff().performClick()
        compose.waitUntil(60_000) {
            runCatching { compose.onNodeWithTag("analytics-consent-switch").assertIsOn() }.isSuccess ||
                compose.onAllNodesWithTag("analytics-consent-error").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("analytics-consent-switch").assertIsOn()
        compose.onNodeWithTag("analytics-consent-error").assertDoesNotExist()
    }

    @Test fun withdrawAnalyticsConsentThroughUi() {
        login()
        val browse = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]
        compose.runOnIdle { browse.navigate("profile/preferences") }
        compose.waitUntil(60_000) {
            runCatching { compose.onNodeWithTag("analytics-consent-switch").assertIsOn() }.isSuccess
        }
        compose.onNodeWithTag("analytics-consent-switch").performScrollTo().performClick()
        compose.waitUntil(60_000) {
            runCatching { compose.onNodeWithTag("analytics-consent-switch").assertIsOff() }.isSuccess
        }
        compose.onNodeWithTag("analytics-consent-error").assertDoesNotExist()
    }

    @Test fun measureBannerImpressionAndClickThroughUi() {
        login()
        val browse = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]
        compose.runOnIdle { browse.navigate("profile/preferences") }
        compose.waitUntil(60_000) {
            runCatching { compose.onAllNodesWithTag("banner-measurement-switch").fetchSemanticsNodes().isNotEmpty() }
                .getOrDefault(false)
        }
        compose.onNodeWithTag("banner-measurement-switch").performScrollTo().assertIsOff().performClick()
        compose.onNodeWithTag("banner-measurement-confirm").performClick()
        compose.waitUntil(60_000) {
            runCatching { compose.onNodeWithTag("banner-measurement-switch").assertIsOn() }.isSuccess ||
                compose.onAllNodesWithTag("banner-measurement-error").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("banner-measurement-switch").assertIsOn()
        compose.runOnIdle { browse.navigate("home") }
        compose.waitUntil(60_000) {
            runCatching { compose.onAllNodesWithTag("browse-list").fetchSemanticsNodes().isNotEmpty() }
                .getOrDefault(false)
        }
        compose.onNodeWithTag("browse-list").performScrollToIndex(0)
        compose.waitUntil(60_000) {
            runCatching { compose.onAllNodesWithTag("banner-open").fetchSemanticsNodes().isNotEmpty() }
                .getOrDefault(false)
        }
        compose.waitUntil(60_000) {
            runCatching { compose.onAllNodesWithTag("loaded-media").fetchSemanticsNodes().isNotEmpty() }
                .getOrDefault(false) ||
                compose.onAllNodesWithTag("public-media-unavailable").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("loaded-media").assertExists()
        compose.onNodeWithTag("banner-open").assertIsDisplayed()
        Thread.sleep(1_400)
        compose.onNodeWithTag("banner-open").performClick()
        val news = newsId
        compose.waitUntil(60_000) { browse.state.value.detailId == news }
    }

    @Test fun withdrawBannerMeasurementThroughUi() {
        login()
        val browse = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]
        compose.runOnIdle { browse.navigate("profile/preferences") }
        compose.waitUntil(60_000) {
            runCatching { compose.onNodeWithTag("banner-measurement-switch").assertIsOn() }.isSuccess
        }
        compose.onNodeWithTag("banner-measurement-switch").performScrollTo().performClick()
        compose.waitUntil(60_000) {
            runCatching { compose.onNodeWithTag("banner-measurement-switch").assertIsOff() }.isSuccess
        }
        compose.onNodeWithTag("banner-measurement-error").assertDoesNotExist()
    }
}
