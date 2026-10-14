package at.uac.android

import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.feature.auth.AuthGate
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.browse.BrowseViewModel
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Grants and revokes optional measurement only for the exact synthetic staging account. */
@RunWith(AndroidJUnit4::class)
class StagingBannerConsentJourneyTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    @Test fun bannerConsentCanBeGrantedAndRevokedThroughSettings() {
        val suffix = InstrumentationRegistry.getArguments().getString("step8Suffix").orEmpty()
        assumeTrue(suffix.matches(Regex("[a-f0-9]{16}")))
        val auth = LocalAuthSession.get(compose.activity)
        compose.waitUntil(60_000) {
            auth.state.value.let { it.stage == AuthStage.AUTHENTICATED && it.gate == AuthGate.READY }
        }
        val browse = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]
        compose.runOnIdle { browse.navigate("profile/preferences") }
        compose.waitUntil(60_000) {
            compose.onAllNodesWithTag("banner-measurement-switch").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("banner-measurement-switch").performScrollTo().assertIsOff().performClick()
        compose.onNodeWithTag("banner-measurement-confirm").performClick()
        compose.waitUntil(60_000) {
            runCatching { compose.onNodeWithTag("banner-measurement-switch").assertIsOn() }.isSuccess
        }
        compose.onNodeWithTag("banner-measurement-switch").performScrollTo().performClick()
        compose.waitUntil(60_000) {
            runCatching { compose.onNodeWithTag("banner-measurement-switch").assertIsOff() }.isSuccess
        }
    }
}
