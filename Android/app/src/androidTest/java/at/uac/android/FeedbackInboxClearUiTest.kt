package at.uac.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.design.UacTheme
import at.uac.android.feature.feedback.*
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class FeedbackInboxClearUiTest {
    @get:Rule val compose = createComposeRule()
    private val sample = FeedbackItem(
        "sample", "author", "Synthetic author", FeedbackType.QUESTION, "Synthetic subject",
        "Synthetic message", FeedbackStatus.OPEN, Instant.EPOCH, Instant.EPOCH,
        "Synthetic preview", false, false, null, null, null, null, false,
    )
    private fun state() = FeedbackState(
        session = FeedbackSession("owner", 1, true, true, "Owner"),
        audience = FeedbackAudience.MANAGEMENT,
        page = FeedbackPage(listOf(sample), null, false),
    )

    @Test fun ownerConfirmsBulkClearAndSeesExactReceipt() {
        var calls = 0
        compose.setContent { UacTheme("light") {
            FeedbackList(state(), "de", {}, {}, {}, {}, {},
                canClearInbox = true, clearState = FeedbackInboxClearState(deletedCount = 2),
                onClearInbox = { calls++ })
        } }
        compose.onNodeWithTag("feedback-clear-receipt").assertTextContains("2 Anfragen", substring = true)
        compose.onNodeWithTag("feedback-list").performScrollToNode(hasTestTag("feedback-clear-inbox"))
        compose.onNodeWithTag("feedback-clear-inbox").performClick()
        compose.onNodeWithTag("feedback-clear-cancel").assertExists()
        compose.onNodeWithText("Gewöhnliche Anfragen und ihre Nachrichten werden unwiderruflich gelöscht. DSA-Fälle bleiben bis zum Ende ihrer Aufbewahrungsfrist erhalten.").assertExists()
        compose.onNodeWithTag("feedback-clear-confirm").performClick()
        assertEquals(1, calls)
    }

    @Test fun administratorNeverSeesOwnerClear() {
        compose.setContent { UacTheme("light") {
            FeedbackList(state(), "uk", {}, {}, {}, {}, {}, canClearInbox = false)
        } }
        compose.onNodeWithTag("feedback-clear-inbox").assertDoesNotExist()
        compose.onNodeWithTag("feedback-clear-pending").assertDoesNotExist()
    }

    @Test fun pendingResultBlocksAnotherSubmit() {
        compose.setContent { UacTheme("light") {
            FeedbackList(state(), "uk", {}, {}, {}, {}, {}, canClearInbox = true,
                clearState = FeedbackInboxClearState(pending = true))
        } }
        compose.onNodeWithTag("feedback-clear-pending").assertExists()
        compose.onNodeWithTag("feedback-clear-inbox").assertDoesNotExist()
        compose.onNodeWithTag("feedback-clear-acknowledge").assertExists()
    }
}
