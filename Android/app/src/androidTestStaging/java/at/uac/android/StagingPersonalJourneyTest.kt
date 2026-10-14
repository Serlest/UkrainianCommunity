package at.uac.android

import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
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
import org.junit.Assert.assertNull
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Writes only personal markers tied to the exact synthetic staging fixtures for this run. */
@RunWith(AndroidJUnit4::class)
class StagingPersonalJourneyTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    @Test fun signedInPersonalActionsPersistThroughTheRealUi() {
        val suffix = InstrumentationRegistry.getArguments().getString("step8Suffix").orEmpty()
        assumeTrue(suffix.matches(Regex("[a-f0-9]{16}")))
        val auth = LocalAuthSession.get(compose.activity)
        compose.waitUntil(60_000) {
            auth.state.value.let { it.stage == AuthStage.AUTHENTICATED && it.gate == AuthGate.READY }
        }
        val browse = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]
        val personal = ViewModelProvider(compose.activity)[PersonalViewModel::class.java]
        for ((kind, id, actions) in listOf(
            Triple(ContentKind.NEWS, "step8-news-$suffix", listOf(PersonalAction.BOOKMARK, PersonalAction.LIKE)),
            Triple(ContentKind.EVENTS, "step8-event-$suffix", listOf(PersonalAction.BOOKMARK, PersonalAction.LIKE)),
            Triple(ContentKind.ORGANIZATIONS, "step8-org-$suffix", listOf(PersonalAction.BOOKMARK, PersonalAction.LIKE, PersonalAction.SUBSCRIBE)),
        )) {
            val target = PersonalTarget(kind, id)
            compose.runOnIdle { browse.navigate("${kind.collection}/$id") }
            compose.waitUntil(60_000) {
                browse.state.value.let { it.detailId == id && !it.data.loading && it.data.detail?.id == id }
            }
            compose.waitUntil(60_000) {
                personal.state.value.let { target in it.actions && target !in it.actionsLoading }
            }
            compose.waitForIdle()
            assertNull("$target initial action load", personal.state.value.actionErrors[target])
            for (action in actions) {
                val tag = "personal-${action.name.lowercase()}"
                val initiallySelected = personal.state.value.actions[target]?.selected(action)
                compose.onNodeWithTag("browse-list").performScrollToNode(hasTestTag(tag))
                if (personal.state.value.actions[target]?.selected(action) == true) {
                    compose.onNodeWithTag(tag).assertIsDisplayed().assertIsEnabled().performClick()
                    compose.waitUntil(60_000) {
                        personal.state.value.let {
                            target !in it.actionsPending && it.actions[target]?.selected(action) == false
                        }
                    }
                    compose.waitForIdle()
                }
                compose.onNodeWithTag(tag).assertIsDisplayed().assertIsEnabled().performClick()
                val completed = runCatching { compose.waitUntil(12_000) {
                    personal.state.value.let {
                        target !in it.actionsPending &&
                            (it.actions[target]?.selected(action) == true || it.actionErrors[target] != null)
                    }
                } }.isSuccess
                assertEquals("$target $action: initial=$initiallySelected; selected=${personal.state.value.actions[target]?.selected(action)}; error=${personal.state.value.actionErrors[target]}", true, completed)
                compose.runOnIdle {
                    assertNull("$target $action write", personal.state.value.actionErrors[target])
                    assertEquals(true, personal.state.value.actions[target]?.selected(action))
                }
                compose.waitForIdle()
            }
        }
    }
}
