package at.uac.android

import android.util.Log
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.feature.auth.AuthGate
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.browse.BrowseViewModel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Host adds/removes an HTTPS block for this staging app UID at the two log markers. */
@RunWith(AndroidJUnit4::class)
class StagingOfflineJourneyTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    @Test fun disconnectedPublicFeedRetriesAfterReconnect() {
        val suffix = InstrumentationRegistry.getArguments().getString("step8Suffix").orEmpty()
        assumeTrue(suffix.matches(Regex("[a-f0-9]{16}")))
        val auth = LocalAuthSession.get(compose.activity)
        compose.waitUntil(60_000) {
            auth.state.value.let { it.stage == AuthStage.AUTHENTICATED && it.gate == AuthGate.READY }
        }
        val model = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]
        compose.runOnIdle { model.navigate("home", true); model.refresh() }
        compose.waitUntil(60_000) { !model.state.value.data.loading }
        compose.runOnIdle { assertEquals(null, model.state.value.data.error) }
        Log.i("UACStep8Offline", "BLOCK_NOW")
        Thread.sleep(8_000)
        compose.runOnIdle { model.refresh() }
        compose.waitUntil(60_000) { !model.state.value.data.loading }
        compose.runOnIdle { assertNotNull("Offline feed error", model.state.value.data.error) }
        compose.onNodeWithTag("browse-error").assertExists()
        compose.onNodeWithTag("browse-retry").assertExists()
        Log.i("UACStep8Offline", "UNBLOCK_NOW")
        Thread.sleep(8_000)
        compose.onNodeWithTag("browse-retry").performClick()
        compose.waitUntil(60_000) { !model.state.value.data.loading && model.state.value.data.error == null }
        compose.runOnIdle {
            assertEquals(true, model.state.value.data.items.any { it.id == "step8-news-$suffix" })
        }
    }
}
