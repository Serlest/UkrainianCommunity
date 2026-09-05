package at.uac.android

import android.os.SystemClock
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.design.UacTheme
import at.uac.android.feature.organizationreview.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Injected presentation proof; does not claim a real privileged TOTP session. */
@RunWith(AndroidJUnit4::class)
class OrganizationReviewUiTest {
    @get:Rule val compose = createComposeRule()
    private val fixture = OrganizationReviewAndroidFixture

    private fun ready(action: OrganizationReviewAction? = null) =
        OrganizationReviewState(
            session = fixture.actor,
            snapshot = fixture.snapshot(),
            fresh = true,
            journalReady = true,
            confirmation = action,
        )

    private fun settled(tag: String) {
        val node = compose.onNodeWithTag(tag)
        var previous: Rect? = null
        var since = SystemClock.uptimeMillis()
        compose.waitUntil(10_000) {
            val bounds = node.fetchSemanticsNode().boundsInWindow
            if (previous != bounds) {
                previous = bounds
                since = SystemClock.uptimeMillis()
            }
            bounds.width > 0 && bounds.height > 0 && SystemClock.uptimeMillis() - since >= 150
        }
    }

    private fun scroll(tag: String): SemanticsNodeInteraction {
        // Native inset animations are not Compose-clock work. Wait before the one scroll action;
        // do not retry scrolling/clicking until a transient assertion happens to pass.
        settled("organization-review-confirm-scroll")
        val node = compose.onNodeWithTag(tag).performScrollTo()
        settled(tag)
        return node.assertIsDisplayed()
    }

    private fun awaitDockedIme() {
        compose.waitUntil(10_000) {
            compose
                .onNodeWithTag("organization-review-confirm-scroll")
                .fetchSemanticsNode()
                .config[OrganizationReviewDialogImeVisible]
        }
        settled("organization-review-confirm-scroll")
    }

    /** Root runs this class with actual OS font_scale=2.0 on both API26 and API37. */
    @Test
    fun actualNativeFont200LongReasonImeScrollAndBusyFocusClear() {
        val context =
            androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().targetContext
        assertEquals(2f, context.resources.configuration.fontScale, 0.01f)
        val state = mutableStateOf(ready(OrganizationReviewAction.REJECT))
        var sends = 0
        compose.setContent {
            UacTheme("light") {
                OrganizationReviewPanel(
                    state.value,
                    "de",
                    OrganizationReviewActions(
                        editText = { state.value = state.value.copy(text = it) },
                        confirm = {
                            sends++
                            state.value = state.value.copy(busy = true)
                        },
                    ),
                )
            }
        }
        val scrollNode = compose.onNodeWithTag("organization-review-confirm-scroll")
        assertEquals(
            2f,
            scrollNode.fetchSemanticsNode().config[OrganizationReviewDialogFontScale],
            0.01f,
        )
        scroll("organization-review-text").performClick().assertIsFocused()
        awaitDockedIme()
        scroll("organization-review-text")
            .performTextReplacement("Ausführliche synthetische Begründung. ".repeat(250))
        val confirm = scroll("organization-review-confirm").assertIsEnabled()
        assertTrue(
            confirm.fetchSemanticsNode().boundsInRoot.height /
                context.resources.displayMetrics.density >= 48f
        )
        confirm.performClick()
        compose.waitUntil(10_000) {
            !scrollNode.fetchSemanticsNode().config[OrganizationReviewDialogImeVisible]
        }
        // Disabled non-focusable fields omit Focused rather than publishing Focused=false.
        // Check the complete unmerged tree, including the TextField's internal focus target.
        compose.onNodeWithTag("organization-review-text").assertIsNotEnabled()
        compose.onAllNodes(isFocused(), useUnmergedTree = true).assertCountEquals(0)
        scroll("organization-review-text").performClick()
        compose.onAllNodes(isFocused(), useUnmergedTree = true).assertCountEquals(0)
        compose.runOnIdle {
            assertEquals(1, sends)
            assertTrue(state.value.text.length > 5_000)
        }
    }

    @Test
    fun approveExplainsOwnershipAndRequiresExplicitConfirmation() {
        var confirms = 0
        val state = mutableStateOf(ready())
        compose.setContent {
            UacTheme("light") {
                OrganizationReviewPanel(
                    state.value,
                    "de",
                    OrganizationReviewActions(
                        request = { state.value = state.value.copy(confirmation = it) },
                        confirm = { confirms++ },
                    ),
                )
            }
        }
        compose.onNodeWithTag("organization-review-approve").assertIsEnabled().performClick()
        scroll("organization-review-submitter")
            .assertTextContains(fixture.submitter, substring = true)
        scroll("organization-review-owner-effect")
            .assertTextContains("Eigentümer", substring = true)
        compose.runOnIdle { assertEquals(0, confirms) }
        scroll("organization-review-confirm").assertIsEnabled().performClick()
        compose.runOnIdle { assertEquals(1, confirms) }
    }

    @Test
    fun revisionNeedsNonemptyMessageAndPreservesText() {
        val state = mutableStateOf(ready(OrganizationReviewAction.REQUEST_REVISION))
        var confirms = 0
        compose.setContent {
            UacTheme("dark") {
                OrganizationReviewPanel(
                    state.value,
                    "uk",
                    OrganizationReviewActions(
                        editText = { state.value = state.value.copy(text = it) },
                        confirm = { confirms++ },
                    ),
                )
            }
        }
        scroll("organization-review-confirm").assertIsNotEnabled()
        scroll("organization-review-text").performClick().assertIsFocused()
        awaitDockedIme()
        scroll("organization-review-text").performTextReplacement("Додайте години роботи")
        scroll("organization-review-confirm").assertIsEnabled().performClick()
        compose.runOnIdle {
            assertEquals("Додайте години роботи", state.value.text)
            assertEquals(1, confirms)
        }
    }

    @Test
    fun rejectRequiresReasonAndCancelDoesNotSubmit() {
        val state = mutableStateOf(ready(OrganizationReviewAction.REJECT))
        var confirms = 0
        compose.setContent {
            UacTheme("light") {
                OrganizationReviewPanel(
                    state.value,
                    "de",
                    OrganizationReviewActions(
                        editText = { state.value = state.value.copy(text = it) },
                        confirm = { confirms++ },
                        cancel = { state.value = state.value.copy(confirmation = null, text = "") },
                    ),
                )
            }
        }
        scroll("organization-review-confirm").assertIsNotEnabled()
        scroll("organization-review-text").performClick().assertIsFocused()
        awaitDockedIme()
        scroll("organization-review-text").performTextReplacement("Doppelter Antrag")
        scroll("organization-review-cancel").assertIsEnabled().performClick()
        compose.onNodeWithTag("organization-review-confirm-scroll").assertDoesNotExist()
        compose.runOnIdle {
            assertEquals(0, confirms)
            assertEquals("", state.value.text)
        }
    }

    @Test
    fun busyDisablesTextSubmitAndCancel() {
        compose.setContent {
            UacTheme("dark") {
                OrganizationReviewPanel(
                    ready(OrganizationReviewAction.REJECT).copy(text = "Reason", busy = true),
                    "uk",
                    OrganizationReviewActions(),
                )
            }
        }
        scroll("organization-review-text").assertIsNotEnabled()
        scroll("organization-review-confirm").assertIsNotEnabled()
        scroll("organization-review-cancel").assertIsNotEnabled()
    }

    @Test
    fun staleVersionClosesConfirmationAndDisablesAllActions() {
        compose.setContent {
            UacTheme("light") {
                OrganizationReviewPanel(
                    ready(OrganizationReviewAction.APPROVE)
                        .copy(fresh = false, error = OrganizationReviewFailure.STALE),
                    "de",
                    OrganizationReviewActions(),
                )
            }
        }
        compose.onNodeWithTag("organization-review-confirm-scroll").assertDoesNotExist()
        for (action in OrganizationReviewAction.entries) compose
            .onNodeWithTag("organization-review-${action.name.lowercase()}")
            .assertIsNotEnabled()
        compose
            .onNodeWithTag("organization-review-error")
            .assertTextContains("erneut", substring = true)
    }

    @Test
    fun unresolvedPendingAccessibleWithoutSelectedPreviewAndOnlyReads() {
        val entry = fixture.pending().copy(phase = OrganizationReviewPhase.DISPATCHED)
        var reads = 0
        var writes = 0
        compose.setContent {
            UacTheme("light") {
                OrganizationReviewPanel(
                    OrganizationReviewState(
                        session = fixture.actor,
                        journalReady = true,
                        pending = listOf(entry),
                        observation = OrganizationReviewObservation.OBSERVED_WITHOUT_RECEIPT,
                    ),
                    "de",
                    OrganizationReviewActions(
                        reconcile = {
                            assertEquals(entry, it)
                            reads++
                        },
                        confirm = { writes++ },
                    ),
                )
            }
        }
        compose.onNodeWithTag("organization-review-reconcile-0").assertIsEnabled().performClick()
        compose
            .onNodeWithTag("organization-review-observation")
            .assertTextContains("keinen eindeutigen Beleg", substring = true)
        compose.onNodeWithTag("organization-review-approve").assertDoesNotExist()
        compose.runOnIdle {
            assertEquals(1, reads)
            assertEquals(0, writes)
        }
    }

    @Test
    fun privateScopeMaskRemovesAllContentAndDialog() {
        val state =
            mutableStateOf(ready(OrganizationReviewAction.REJECT).copy(text = "PRIVATE-NOTICE"))
        compose.setContent {
            UacTheme("dark") {
                OrganizationReviewPanel(state.value, "uk", OrganizationReviewActions())
            }
        }
        compose.runOnIdle { state.value = OrganizationReviewState() }
        compose.onNodeWithTag("organization-review-actions").assertDoesNotExist()
        compose.onNodeWithTag("organization-review-confirm-scroll").assertDoesNotExist()
        compose.onNodeWithText("PRIVATE-NOTICE").assertDoesNotExist()
    }

    @Test
    fun confirmedChangedCopyDoesNotPromiseUnseenVersionOrInbox() {
        compose.setContent {
            UacTheme("light") {
                OrganizationReviewPanel(
                    ready().copy(observation = OrganizationReviewObservation.CONFIRMED_CHANGED),
                    "uk",
                    OrganizationReviewActions(),
                )
            }
        }
        compose
            .onNodeWithTag("organization-review-observation")
            .assertTextContains("заявка вже змінилася", substring = true)
    }
}
