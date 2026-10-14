package at.uac.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.LocalAuthSession
import org.junit.Assert.assertEquals
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Explicit, one-use staging journey. The caller owns exact-UID cleanup after server read-back. */
@RunWith(AndroidJUnit4::class)
class StagingRegistrationJourneyTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    @Test fun createsUnverifiedAccountWithCurrentLegalDocuments() {
        val args = InstrumentationRegistry.getArguments()
        val email = args.getString("step8Email").orEmpty()
        val password = args.getString("step8Password").orEmpty()
        assumeTrue(email.matches(Regex("step8-[a-f0-9]{16}@example\\.invalid")) && password.length >= 20)
        assertEquals("at.serlest.ukrainiancommunity.staging", compose.activity.packageName)

        compose.runOnIdle { LocalAuthSession.get(compose.activity).signOut() }
        compose.waitUntil(60_000) {
            compose.onAllNodesWithTag("startup-account-gate").fetchSemanticsNodes().isNotEmpty() &&
                compose.onAllNodesWithTag("auth-tab-register").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("auth-tab-register").performScrollTo().performClick()
        compose.waitUntil(60_000) {
            compose.onAllNodesWithTag("auth-register-submit").fetchSemanticsNodes().isNotEmpty()
        }
        fun input(tag: String, value: String) {
            compose.onNodeWithTag(tag).performScrollTo().performTextInput(value)
        }
        input("auth-email", email)
        input("auth-password", password)
        input("auth-password-repeat", password)
        input("auth-name", "UAC Step 8 Test")
        compose.onNodeWithTag("auth-region").performScrollTo().performClick()
        compose.onNodeWithTag("auth-region-tirol").performClick()
        for (tag in listOf("auth-terms", "auth-privacy", "auth-age"))
            compose.onNodeWithTag(tag).performScrollTo().performClick()
        compose.onNodeWithTag("auth-register-submit").performScrollTo().performClick()

        compose.waitUntil(60_000) {
            LocalAuthSession.get(compose.activity).state.value.stage == AuthStage.VERIFICATION_PENDING ||
                compose.onAllNodesWithTag("auth-error").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("auth-verification-email").assertTextEquals(email)
        compose.onNodeWithTag("tab-home").assertDoesNotExist()
    }
}
