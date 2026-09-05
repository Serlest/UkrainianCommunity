package at.uac.android

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.feedback.*
import java.time.Instant
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class FeedbackUiTest {
    @get:Rule val compose = createComposeRule()
    private val actor = FeedbackSession("synthetic-feedback-ui", 1, true, false, "Synthetic")
    private val item =
        FeedbackContract.item(
            RawDocument(
                "request",
                FeedbackContract.creation(
                    "request",
                    actor,
                    FeedbackDraft(message = "Synthetic original message"),
                    Instant.EPOCH,
                ),
            )
        )

    private fun scroll(list: String, tag: String) {
        compose.onNodeWithTag(list).performScrollToNode(hasTestTag(tag))
        compose.onNodeWithTag(tag).performScrollTo()
    }

    @Test
    fun largeTextComposerSubmitsOnceAndKeepsConfirmedLinkReachable() {
        val state =
            mutableStateOf(
                FeedbackState(
                    session = actor,
                    draft = FeedbackDraft(message = "Synthetic local request"),
                )
            )
        var sends = 0
        var opened: String? = null
        compose.setContent {
            MaterialTheme {
                FeedbackList(
                    state.value,
                    "uk",
                    { state.value = state.value.copy(draft = it) },
                    {
                        sends++
                        state.value = state.value.copy(pending = true)
                    },
                    {},
                    { opened = it },
                    {},
                )
            }
        }
        scroll("feedback-list", "feedback-submit")
        compose.onNodeWithTag("feedback-submit").performClick()
        compose.onNodeWithTag("feedback-submit").assertIsNotEnabled()
        compose.runOnIdle {
            assertEquals(1, sends)
            state.value = state.value.copy(pending = false, confirmedId = "request")
        }
        scroll("feedback-list", "feedback-open-confirmed")
        compose.onNodeWithTag("feedback-open-confirmed").performClick()
        compose.runOnIdle { assertEquals("request", opened) }
    }

    @Test
    fun closedConversationHasNoReplyOrDeleteAndLogoutHidesItsContents() {
        val authority = mutableStateOf<FeedbackSession?>(actor)
        val snapshot =
            FeedbackState(
                session = actor,
                selectedId = item.id,
                conversation =
                    FeedbackConversation(
                        item.copy(status = FeedbackStatus.CLOSED),
                        FeedbackContract.merge(item, emptyList()),
                    ),
            )
        compose.setContent {
            MaterialTheme {
                FeedbackDetail(snapshot.forSession(authority.value), "de", {}, {}, {}, {}, {})
            }
        }
        compose.onNodeWithTag("feedback-conversation").performScrollToNode(hasText(item.message))
        compose.onNodeWithText(item.message).assertIsDisplayed()
        compose.onNodeWithTag("feedback-send").assertDoesNotExist()
        compose.onNodeWithTag("feedback-close").assertDoesNotExist()
        compose.runOnIdle { authority.value = null }
        compose.onNodeWithText(item.message).assertDoesNotExist()
    }

    @Test
    fun managementCloseRequiresConfirmationAndDsaCannotUseOrdinaryClose() {
        val manager = actor.copy(canManage = true)
        val state =
            mutableStateOf(
                FeedbackState(
                    session = manager,
                    audience = FeedbackAudience.MANAGEMENT,
                    selectedId = item.id,
                    conversation = FeedbackConversation(item, emptyList()),
                )
            )
        var closed = false
        compose.setContent {
            MaterialTheme { FeedbackDetail(state.value, "uk", {}, {}, { closed = true }, {}, {}) }
        }
        scroll("feedback-conversation", "feedback-close")
        compose.onNodeWithTag("feedback-close").performClick()
        compose.runOnIdle { assertFalse(closed) }
        compose.onNodeWithTag("feedback-confirm-close").performClick()
        compose.runOnIdle {
            assertTrue(closed)
            state.value =
                state.value.copy(
                    conversation = FeedbackConversation(item.copy(hasDsaCase = true), emptyList())
                )
        }
        compose.onNodeWithTag("feedback-close").assertDoesNotExist()
    }
}
