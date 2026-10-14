package at.uac.android

import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.feature.auth.AuthGate
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.safety.SafetyViewModel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Blocks and unblocks only the exact synthetic staging organization for this run. */
@RunWith(AndroidJUnit4::class)
class StagingSafetyJourneyTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    @Test fun organizationBlockRoundTripsThroughStagingCallable() {
        val suffix = InstrumentationRegistry.getArguments().getString("step8Suffix").orEmpty()
        assumeTrue(suffix.matches(Regex("[a-f0-9]{16}")))
        val id = "step8-org-$suffix"
        val auth = LocalAuthSession.get(compose.activity)
        compose.waitUntil(60_000) {
            auth.state.value.let { it.stage == AuthStage.AUTHENTICATED && it.gate == AuthGate.READY }
        }
        val safety = ViewModelProvider(compose.activity)[SafetyViewModel::class.java]
        compose.waitUntil(60_000) { safety.state.value.blocks != null && !safety.state.value.loading }
        compose.runOnIdle { safety.setOrganization(id, true) }
        compose.waitUntil(60_000) {
            safety.state.value.let { state ->
                "organization:$id" !in state.pendingBlocks &&
                    (state.blocks?.organizations?.any { it.id == id } == true ||
                        state.blockErrors["organization:$id"] != null)
            }
        }
        compose.runOnIdle {
            assertNull("block callable", safety.state.value.blockErrors["organization:$id"])
            assertEquals(true, safety.state.value.blocks?.organizations?.any { it.id == id })
        }
        compose.waitForIdle()
        compose.runOnIdle { safety.setOrganization(id, false) }
        compose.waitUntil(60_000) {
            safety.state.value.let { state ->
                "organization:$id" !in state.pendingBlocks &&
                    (state.blocks?.organizations?.none { it.id == id } == true ||
                        state.blockErrors["organization:$id"] != null)
            }
        }
        compose.runOnIdle {
            assertNull("unblock callable", safety.state.value.blockErrors["organization:$id"])
            assertEquals(true, safety.state.value.blocks?.organizations?.none { it.id == id })
        }
    }
}
