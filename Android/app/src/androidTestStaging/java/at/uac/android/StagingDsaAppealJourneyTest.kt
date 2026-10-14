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
import org.junit.Assert.assertEquals
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** One synthetic own case, through the real staging app UI and callable. */
@RunWith(AndroidJUnit4::class)
class StagingDsaAppealJourneyTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    @Test fun reporterSubmitsAppealAndSeesConfirmedReceipt() {
        val args = InstrumentationRegistry.getArguments()
        val email = args.getString("dsaSmokeEmail").orEmpty()
        val password = args.getString("dsaSmokePassword").orEmpty()
        val reportId = args.getString("dsaSmokeReportId").orEmpty()
        assumeTrue(email.matches(Regex("dsa-smoke-[a-f0-9]{16}-1@example\\.invalid")) &&
            password.length >= 20 &&
            reportId.matches(Regex("dsa-appeal-smoke-[a-f0-9]{16}")))
        assertEquals("at.serlest.ukrainiancommunity.staging", compose.activity.packageName)

        val auth = LocalAuthSession.get(compose.activity)
        compose.runOnIdle { auth.signOut() }
        compose.waitUntil(60_000) {
            compose.onAllNodesWithTag("auth-login-submit").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("auth-email").performScrollTo().performTextInput(email)
        compose.onNodeWithTag("auth-password").performScrollTo().performTextInput(password)
        compose.onNodeWithTag("auth-login-submit").performScrollTo().performClick()
        compose.waitUntil(60_000) {
            auth.state.value.let { it.stage == AuthStage.AUTHENTICATED && it.gate == AuthGate.READY }
        }

        val browse = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]
        compose.runOnIdle { browse.navigate("profile/dsa-review/$reportId") }
        compose.waitUntil(60_000) {
            compose.onAllNodesWithTag("dsa-review-case").fetchSemanticsNodes().isNotEmpty() ||
                compose.onAllNodesWithTag("dsa-review-error").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("dsa-review-case").performScrollTo().assertExists()
        compose.onNodeWithTag("dsa-review-list")
            .performScrollToNode(hasTestTag("dsa-review-reason"))
        compose.onNodeWithTag("dsa-review-reason")
            .performTextInput("Synthetic staging appeal: the reviewed decision needs another human check.")
        compose.onNodeWithTag("dsa-review-list")
            .performScrollToNode(hasTestTag("dsa-review-submit"))
        compose.onNodeWithTag("dsa-review-submit").performClick()
        compose.onNodeWithTag("dsa-review-confirm").performClick()
        compose.waitUntil(60_000) {
            compose.onAllNodesWithTag("dsa-review-receipt").fetchSemanticsNodes().isNotEmpty() ||
                compose.onAllNodesWithTag("dsa-review-submit-error").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("dsa-review-receipt").assertExists()
        compose.runOnIdle { auth.signOut() }
        compose.waitUntil(60_000) {
            compose.onAllNodesWithTag("auth-login-submit").fetchSemanticsNodes().isNotEmpty()
        }
    }
}
