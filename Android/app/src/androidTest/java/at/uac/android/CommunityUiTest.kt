package at.uac.android

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextReplacement
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.community.*
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CommunityUiTest {
    @get:Rule val compose = createComposeRule()
    private val session = CommunitySession("synthetic-community-ui", 1, true, "user")
    private val target = CommunityTarget(ContentKind.NEWS, "synthetic-news-ui")
    private val row =
        CommunityComment(
            "synthetic-comment",
            target,
            session.uid,
            "Synthetic Author",
            "Дякую!",
            Instant.EPOCH,
            null,
        )

    @Test
    fun registrationUsesExplicitStateAndConfirmsCancellation() {
        var changes = 0
        var selected: Boolean? = null
        val state =
            mutableStateOf(
                CommunityState(
                    session,
                    CommunityTarget(ContentKind.EVENTS, "synthetic-event-ui"),
                    true,
                    participation =
                        EventParticipation(
                            "synthetic-event-ui",
                            false,
                            1,
                            1,
                            Instant.now().plusSeconds(3600),
                            false,
                            true,
                            true,
                        ),
                )
            )
        compose.setContent {
            MaterialTheme {
                EventRegistrationPanel(
                    state.value,
                    "uk",
                    {},
                    { value ->
                        changes++
                        selected = value
                        state.value = state.value.copy(registrationBusy = true)
                    },
                    {},
                )
            }
        }
        compose.onNodeWithTag("registration-toggle").assertIsNotEnabled()
        compose.runOnIdle {
            state.value =
                state.value.copy(
                    participation = state.value.participation!!.copy(registered = true)
                )
        }
        compose.onNodeWithTag("registration-toggle").performClick()
        compose.runOnIdle { assertEquals(0, changes) }
        compose.onNodeWithTag("registration-confirm-cancel").performClick()
        compose.onNodeWithTag("registration-toggle").assertIsNotEnabled()
        compose.runOnIdle {
            assertEquals(false, selected)
            assertEquals(1, changes)
        }
    }

    @Test
    fun authorHasNoEditDeleteAndComposerValidatesBeforeSending() {
        var sends = 0
        val state =
            mutableStateOf(
                CommunityState(session, target, true, page = CommentPage(listOf(row), false))
            )
        compose.setContent {
            MaterialTheme {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    CommentsPanel(
                        state.value,
                        "de",
                        { state.value = state.value.copy(draft = it) },
                        {
                            sends++
                            state.value = state.value.copy(sending = true)
                        },
                        {},
                        {},
                        {},
                        {},
                    )
                }
            }
        }
        compose.onNodeWithTag("comment-delete-${row.id}").assertDoesNotExist()
        compose.onNodeWithText("Bearbeiten").assertDoesNotExist()
        compose.onNodeWithTag("comment-send").performScrollTo().assertIsNotEnabled()
        compose
            .onNodeWithTag("comment-draft")
            .performScrollTo()
            .performTextReplacement("x".repeat(1001))
        compose.onNodeWithTag("comment-send").performScrollTo().assertIsNotEnabled()
        compose
            .onNodeWithTag("comment-draft")
            .performScrollTo()
            .performTextReplacement("Дякую за інформацію!")
        compose.onNodeWithTag("comment-send").performScrollTo().performClick()
        compose.onNodeWithTag("comment-send").assertIsNotEnabled()
        compose.runOnIdle { assertEquals(1, sends) }
    }

    @Test
    fun moderatorDeleteRequiresConfirmationAndUncertainSendRequiresFreshPage() {
        var deleted: String? = null
        var acknowledgements = 0
        val state =
            mutableStateOf(
                CommunityState(
                    session,
                    target,
                    true,
                    page = CommentPage(listOf(row), false),
                    canModerate = true,
                )
            )
        compose.setContent {
            MaterialTheme {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    CommentsPanel(
                        state.value,
                        "uk",
                        {},
                        {},
                        { deleted = it },
                        {},
                        { acknowledgements++ },
                        {},
                    )
                }
            }
        }
        compose.onNodeWithTag("comment-delete-${row.id}").performScrollTo().performClick()
        compose.runOnIdle { assertEquals(null, deleted) }
        compose.onNodeWithTag("comment-confirm-delete").performClick()
        compose.runOnIdle {
            assertEquals(row.id, deleted)
            state.value =
                state.value.copy(
                    uncertain = true,
                    draft = "Possible duplicate",
                    page = CommentPage(emptyList(), true),
                )
        }
        compose.onNodeWithTag("comment-send").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithTag("comment-acknowledge").performScrollTo().assertIsNotEnabled()
        compose.runOnIdle { state.value = state.value.copy(page = CommentPage(emptyList(), false)) }
        compose.onNodeWithTag("comment-acknowledge").performScrollTo().performClick()
        compose.runOnIdle { assertEquals(1, acknowledgements) }
    }
}
