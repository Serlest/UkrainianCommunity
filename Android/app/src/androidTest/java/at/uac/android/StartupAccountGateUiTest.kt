package at.uac.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.LocalAuthSession
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class StartupAccountGateUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    @Test
    fun signedOutLaunchShowsOnlyAccountFlowAndDoesNotOfferStaleLegalConsent() {
        compose.runOnIdle { LocalAuthSession.get(compose.activity).signOut() }
        compose.waitUntil(15_000) {
            LocalAuthSession.get(compose.activity).state.value.stage == AuthStage.GUEST
        }
        compose.onNodeWithTag("startup-account-gate").assertExists()
        compose.onNodeWithTag("account-screen").assertExists()
        compose.onNodeWithTag("tab-home").assertDoesNotExist()
        compose.onNodeWithTag("tab-events").assertDoesNotExist()

        compose.onNodeWithTag("auth-tab-register").performScrollTo().performClick()
        compose.waitUntil(15_000) {
            !LocalAuthSession.get(compose.activity).registrationLegal.value.loading
        }
        val legal = LocalAuthSession.get(compose.activity).registrationLegal.value
        if (legal.ready) {
            // A running emulator may have published its isolated legal fixture.
            compose.onNodeWithTag("auth-register-submit").performScrollTo().assertExists()
            org.junit.Assert.assertTrue(legal.documents.all { it.contentHash?.length == 64 })
        } else {
            compose.onNodeWithTag("auth-registration-legal-unavailable")
                .performScrollTo().assertExists()
            compose.onNodeWithTag("auth-register-submit").assertDoesNotExist()
        }
    }
}
