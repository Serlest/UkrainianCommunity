package at.uac.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.AuthGate
import at.uac.android.feature.auth.LocalAuthSession
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Continues only the exact synthetic account left signed in by StagingRegistrationJourneyTest. */
@RunWith(AndroidJUnit4::class)
class StagingVerifiedAccountJourneyTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    @Test fun serverVerifiedUserPassesGateAndOpensFiveRoots() {
        assertEquals("at.serlest.ukrainiancommunity.staging", compose.activity.packageName)
        compose.waitUntil(60_000) {
            LocalAuthSession.get(compose.activity).state.value.stage in
                setOf(AuthStage.VERIFICATION_PENDING, AuthStage.AUTHENTICATED)
        }
        if (LocalAuthSession.get(compose.activity).state.value.stage == AuthStage.VERIFICATION_PENDING)
            compose.onNodeWithTag("auth-check-verification").performScrollTo().performClick()
        compose.waitUntil(60_000) {
            LocalAuthSession.get(compose.activity).state.value.let {
                it.stage == AuthStage.AUTHENTICATED && it.gate == AuthGate.READY
            } &&
                compose.onAllNodesWithTag("tab-home").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("startup-account-gate").assertDoesNotExist()
        for (route in listOf("home", "events", "organizations", "directory", "profile")) {
            compose.onNodeWithTag("tab-$route").assertIsDisplayed().performClick()
            compose.onNodeWithTag("tab-$route").assertIsDisplayed()
        }
        compose.onNodeWithTag("auth-ready").assertExists()
    }
}
