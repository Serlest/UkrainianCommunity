package at.uac.android

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.feature.dsaappeal.*
import at.uac.android.feature.feedback.*
import java.time.Instant
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DsaAppealReviewUiTest {
    @get:Rule val compose = createComposeRule()
    private val now = Instant.parse("2026-09-03T12:00:01Z")
    private val actor = DsaAppealSession("reporter", 1, "synthetic", true)
    private val decision =
        DsaAppealDecision(
            "noAction",
            "PRIVATE SYNTHETIC FACTS",
            "Synthetic basis",
            "Synthetic terms",
            "AT",
            "Synthetic duration",
            "Synthetic redress",
            false,
            true,
            now.minusSeconds(1),
            now.plusSeconds(10),
        )
    private val context =
        FeedbackCaseContext(
            "SYNTHETIC CASE",
            "decided",
            "other",
            "Synthetic location",
            "Synthetic explanation",
            null,
            null,
            true,
            now.minusSeconds(60),
            "de",
            null,
        )

    private fun state() =
        DsaAppealReviewState(
            actor,
            "report",
            true,
            false,
            DsaAppealReview(
                actor,
                DsaAppealReviewSnapshot("report", actor.uid, context, decision, "a".repeat(64)),
            ),
        )

    private fun scroll(tag: String) {
        compose.onNodeWithTag("dsa-review-list").performScrollToNode(hasTestTag(tag))
        compose.onNodeWithTag(tag).performScrollTo().assertIsDisplayed()
    }

    @Test
    fun germanFullDecisionAndDeadlineAreReadableWithOnlyRefresh() {
        var reads = 0
        compose.setContent {
            MaterialTheme { DsaAppealReviewScreen(state(), "report", "de", now, { reads++ }, {}) }
        }
        for (tag in
            listOf(
                "readonly",
                "case",
                "outcome",
                "facts",
                "legal",
                "terms",
                "territory",
                "duration",
                "redress",
                "automation",
                "human",
                "date",
                "deadline",
                "not-receipt",
                "refresh",
            )) scroll("dsa-review-$tag")
        compose.onNodeWithTag("dsa-review-refresh").performClick()
        compose.runOnIdle { assertEquals(1, reads) }
        compose.onNodeWithText("Beschwerde senden").assertDoesNotExist()
    }

    @Test
    fun ukrainianBooleansRemainHonestAndNoSubmitFieldExists() {
        val review = state().review!!
        compose.setContent {
            MaterialTheme {
                DsaAppealReviewScreen(
                    state()
                        .copy(
                            review =
                                review.copy(
                                    snapshot =
                                        review.snapshot.copy(
                                            decision =
                                                decision.copy(
                                                    automationUsed = true,
                                                    humanReviewConfirmed = false,
                                                )
                                        )
                                )
                        ),
                    "report",
                    "uk",
                    now,
                    {},
                    {},
                )
            }
        }
        scroll("dsa-review-automation")
        compose.onNodeWithTag("dsa-review-automation").assertTextEquals("Так")
        scroll("dsa-review-human")
        compose.onNodeWithTag("dsa-review-human").assertTextEquals("Ні")
        compose.onAllNodes(hasSetTextAction()).assertCountEquals(0)
    }

    @Test
    fun exactDeadlineMasksPrivateReviewImmediately() {
        val time = mutableStateOf(now)
        compose.setContent {
            MaterialTheme { DsaAppealReviewScreen(state(), "report", "de", time.value, {}, {}) }
        }
        scroll("dsa-review-facts")
        compose.runOnIdle { time.value = decision.appealDeadline }
        compose.onNodeWithText("PRIVATE SYNTHETIC FACTS").assertDoesNotExist()
        scroll("dsa-review-error")
        compose
            .onNodeWithTag("dsa-review-error")
            .assertTextEquals("Die in der Entscheidung angegebene Beschwerdefrist ist abgelaufen.")
    }

    @Test
    fun differentScopeRouteLoadingAndErrorDoNotExposePreviousReview() {
        val snapshot = mutableStateOf(state())
        val route = mutableStateOf("report")
        compose.setContent {
            MaterialTheme { DsaAppealReviewScreen(snapshot.value, route.value, "de", now, {}, {}) }
        }
        scroll("dsa-review-facts")
        for (next in
            listOf(
                state().copy(loading = true),
                state().copy(error = DsaAppealReviewFailure.STALE),
                state().copy(visible = false),
                state().forSession(actor.copy(revision = 2), now),
            )) {
            compose.runOnIdle { snapshot.value = next }
            compose.onNodeWithText("PRIVATE SYNTHETIC FACTS").assertDoesNotExist()
        }
        compose.runOnIdle {
            snapshot.value = state()
            route.value = "different"
        }
        compose.onNodeWithText("PRIVATE SYNTHETIC FACTS").assertDoesNotExist()
    }

    @Test
    fun guestHasAccountActionButNoReadOrPrivateDecision() {
        var accounts = 0
        compose.setContent {
            MaterialTheme {
                DsaAppealReviewScreen(
                    state().forSession(null, now),
                    "report",
                    "uk",
                    now,
                    {},
                    { accounts++ },
                )
            }
        }
        scroll("dsa-review-access")
        compose.onNodeWithText("До облікового запису").performScrollTo().performClick()
        compose.runOnIdle { assertEquals(1, accounts) }
        compose.onNodeWithText("PRIVATE SYNTHETIC FACTS").assertDoesNotExist()
        compose.onNodeWithTag("dsa-review-refresh").assertDoesNotExist()
    }
}
