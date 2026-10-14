package at.uac.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import at.uac.android.feature.dsaowner.*
import at.uac.android.feature.feedback.FeedbackCaseContext
import at.uac.android.feature.moderation.ModerationSession
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class DsaOwnerDecisionUiTest {
    @get:Rule val compose = createComposeRule()
    private val now = Instant.parse("2026-10-14T12:00:00Z")
    private val owner = ModerationSession("owner", 1, "owner", true)
    private fun review(action: DsaOwnerAction) = DsaOwnerReview(
        owner, "report", "DSA-1", FeedbackCaseContext(
            "DSA-1", if (action == DsaOwnerAction.CASE) "submitted" else "appealed",
            "other", "Synthetic location", "Synthetic explanation", null, null,
            true, now, "de", null,
        ), "Synthetic report", action, now, mapOf("status" to action.name))

    @Test fun caseDecisionRequiresHumanReviewAndConfirmation() {
        var calls = 0
        compose.setContent { DsaOwnerDecisionScreen(
            DsaOwnerState(owner, "report", true, review = review(DsaOwnerAction.CASE)),
            "report", "de", {}, { calls++ }) }
        compose.onNodeWithTag("dsa-owner-case").assertExists()
        fun fill(tag: String, text: String) {
            compose.onNodeWithTag("dsa-owner-list").performScrollToNode(hasTestTag(tag))
            compose.onNodeWithTag(tag).performTextInput(text)
        }
        fill("dsa-owner-facts", "Detailed facts that require a human decision")
        fill("dsa-owner-legal", "Legal basis")
        fill("dsa-owner-duration", "Until review")
        fill("dsa-owner-redress", "Internal appeal available")
        compose.onNodeWithTag("dsa-owner-list").performScrollToNode(hasTestTag("dsa-owner-submit"))
        compose.onNodeWithTag("dsa-owner-submit").assertIsNotEnabled()
        compose.onNodeWithTag("dsa-owner-list").performScrollToNode(hasTestTag("dsa-owner-human"))
        compose.onNodeWithTag("dsa-owner-human").performClick()
        compose.onNodeWithTag("dsa-owner-list").performScrollToNode(hasTestTag("dsa-owner-submit"))
        compose.onNodeWithTag("dsa-owner-submit").assertIsEnabled().performClick()
        assertEquals(0, calls)
        compose.onNodeWithTag("dsa-owner-confirm").performClick()
        assertEquals(1, calls)
    }

    @Test fun wrongRoleCannotExposeDecision() {
        compose.setContent { DsaOwnerDecisionScreen(
            DsaOwnerState(owner.copy(role = "admin"), "report", true,
                review = review(DsaOwnerAction.CASE)), "report", "uk", {}, {}) }
        compose.onNodeWithTag("dsa-owner-submit").assertDoesNotExist()
        compose.onNodeWithTag("dsa-owner-case").assertDoesNotExist()
    }
}
