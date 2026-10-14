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
import at.uac.android.feature.safety.SafetyViewModel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Reads only the exact synthetic staging documents created for this run. */
@RunWith(AndroidJUnit4::class)
class StagingContentJourneyTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    @Test fun sharedFirestoreFeedsAndBannerReachTheSignedInClient() {
        val suffix = InstrumentationRegistry.getArguments().getString("step8Suffix").orEmpty()
        assumeTrue(suffix.matches(Regex("[a-f0-9]{16}")))
        val auth = LocalAuthSession.get(compose.activity)
        compose.waitUntil(60_000) {
            auth.state.value.let { it.stage == AuthStage.AUTHENTICATED && it.gate == AuthGate.READY }
        }
        val safety = ViewModelProvider(compose.activity)[SafetyViewModel::class.java]
        compose.waitUntil(60_000) { !safety.state.value.loading && safety.state.value.blocks != null || safety.state.value.error != null }
        compose.runOnIdle {
            val state = safety.state.value
            assertEquals("safety read: ${state.readDiagnostic}; error=${state.error}", true, state.blocks != null)
        }
        val model = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]
        for ((route, id) in listOf(
            "home" to "step8-news-$suffix",
            "events" to "step8-event-$suffix",
            "organizations" to "step8-org-$suffix",
        )) {
            compose.runOnIdle { model.navigate(route, true) }
            compose.waitUntil(60_000) {
                model.state.value.let { it.route == route && !it.data.loading }
            }
            compose.runOnIdle {
                val state = model.state.value
                assertEquals("emulator", state.mode)
                assertNull("$route server query", state.data.error)
                assertEquals("$route exact test entry", true, state.data.items.any { it.id == id })
                assertEquals("$route exact test banner; warnings=${state.data.warnings}; ids=${state.data.banners.map { it.id }}", true,
                    state.data.banners.any { it.id == "step8-banner-$suffix" })
            }
            compose.onNodeWithTag("browse-list").performScrollToNode(hasTestTag("card-$id"))
            compose.onNodeWithTag("card-$id").assertIsDisplayed().performClick()
            compose.waitUntil(60_000) {
                model.state.value.let { it.detailId == id && !it.data.loading }
            }
            compose.onNodeWithTag("detail-content").assertExists()
        }
    }
}
