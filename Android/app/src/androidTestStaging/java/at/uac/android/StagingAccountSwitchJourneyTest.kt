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
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.personal.PersonalAction
import at.uac.android.feature.personal.PersonalTarget
import at.uac.android.feature.personal.PersonalViewModel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Starts as the second synthetic account and signs into the first through the real login form. */
@RunWith(AndroidJUnit4::class)
class StagingAccountSwitchJourneyTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    @Test fun bookmarksStayWithTheirAccountAfterSwitch() {
        val args = InstrumentationRegistry.getArguments()
        val suffix = args.getString("step8Suffix").orEmpty()
        val email = args.getString("step8Email").orEmpty()
        val password = args.getString("step8Password").orEmpty()
        assumeTrue(suffix.matches(Regex("[a-f0-9]{16}")) &&
            email.matches(Regex("step8-[a-f0-9]{16}@example\\.invalid")) && password.length >= 20)
        val auth = LocalAuthSession.get(compose.activity)
        compose.waitUntil(60_000) {
            auth.state.value.let { it.stage == AuthStage.AUTHENTICATED && it.gate == AuthGate.READY }
        }
        val secondUid = auth.state.value.identity!!.uid
        val browse = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]
        val personal = ViewModelProvider(compose.activity)[PersonalViewModel::class.java]
        val target = PersonalTarget(ContentKind.NEWS, "step8-news-$suffix")

        compose.runOnIdle { browse.navigate("news/${target.id}") }
        compose.waitUntil(60_000) {
            personal.state.value.let { target in it.actions && target !in it.actionsLoading }
        }
        compose.runOnIdle { assertEquals(false, personal.state.value.actions[target]?.selected(PersonalAction.BOOKMARK)) }

        compose.runOnIdle { auth.signOut() }
        compose.waitUntil(60_000) {
            compose.onAllNodesWithTag("auth-login-submit").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("auth-email").performScrollTo().performTextInput(email)
        compose.onNodeWithTag("auth-password").performScrollTo().performTextInput(password)
        compose.onNodeWithTag("auth-login-submit").performScrollTo().performClick()
        compose.waitUntil(60_000) {
            auth.state.value.let { it.stage == AuthStage.AUTHENTICATED && it.gate == AuthGate.READY && it.identity?.uid != secondUid }
        }
        compose.runOnIdle { assertNotEquals(secondUid, auth.state.value.identity!!.uid) }
        compose.runOnIdle { browse.navigate("news/${target.id}") }
        compose.waitUntil(60_000) {
            personal.state.value.let {
                it.session?.uid == auth.state.value.identity?.uid &&
                    target in it.actions && target !in it.actionsLoading
            }
        }
        compose.runOnIdle { assertEquals(true, personal.state.value.actions[target]?.selected(PersonalAction.BOOKMARK)) }
    }
}
