package at.uac.android

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.isFocused
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextReplacement
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.feature.safety.*
import java.time.Instant
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SafetyUiTest {
    @get:Rule val compose = createComposeRule()
    private val session = SafetySession("synthetic-safety-ui", 1, true)
    private val ready = SafetyState(session, SafetyBlocks(emptyList(), emptyList()))
    private val target =
        SafetyReportTarget(SafetyTargetType.NEWS, "news", "Synthetic example", "author")

    @Test
    fun reportRequiresReasonExplanationDeclarationAndSuppressesPendingSubmit() {
        var submitted: SafetyReportDraft? = null
        var sends = 0
        val state = mutableStateOf(ready)
        compose.setContent {
            MaterialTheme {
                SafetyReportDialog(
                    target,
                    state.value,
                    "uk",
                    {
                        sends++
                        submitted = it
                        state.value =
                            state.value.copy(
                                reports = mapOf(target.key to SafetyReportState(pending = true))
                            )
                    },
                    {},
                )
            }
        }
        compose.onNodeWithTag("safety-report-submit").assertIsNotEnabled()
        compose.onNodeWithTag("safety-reason-spam").performScrollTo().performClick()
        compose.onNodeWithTag("safety-reason-spam").assertIsSelected()
        compose
            .onNodeWithTag("safety-explanation")
            .performScrollTo()
            .performTextReplacement("  Це вигадане пояснення для локальної перевірки.  ")
        compose
            .onNodeWithTag("safety-explanation")
            .assertTextContains("  Це вигадане пояснення для локальної перевірки.  ")
        compose.onNodeWithTag("safety-good-faith").performScrollTo().performClick()
        compose.onNodeWithTag("safety-good-faith").assertIsOn()
        compose.runOnIdle { assertEquals(0, sends) }
        compose
            .onNodeWithTag("safety-report-submit")
            .assertIsDisplayed()
            .assertIsEnabled()
            .performClick()
        compose.runOnIdle {
            assertEquals("One explicit submit must invoke one callback", 1, sends)
            assertNotNull("The submit callback must have delivered a draft", submitted)
            assertEquals(SafetyReason.SPAM, submitted?.reason)
            assertEquals("Це вигадане пояснення для локальної перевірки.", submitted?.explanation)
            assertTrue(submitted?.goodFaith == true)
        }
        compose.onNodeWithTag("safety-report-submit").assertIsNotEnabled()
        compose.onNodeWithTag("safety-report-submit").performClick()
        compose.runOnIdle { assertEquals("Pending submit must not send again", 1, sends) }
        compose.onNodeWithTag("safety-report-close").assertIsNotEnabled()
        compose.onNodeWithTag("safety-explanation").assertIsNotEnabled()
        // A non-focusable disabled field has no Focused property at all. Inspect every
        // unmerged descendant so neither a true child focus nor an absent parent can hide it.
        compose.onAllNodes(isFocused(), useUnmergedTree = true).assertCountEquals(0)
        compose.onNodeWithTag("safety-explanation").performClick()
        compose.onAllNodes(isFocused(), useUnmergedTree = true).assertCountEquals(0)
    }

    @Test
    fun reportDraftSurvivesNativeImeCloseReopenAndEveryFieldLosesPendingFocus() {
        AccountDeletionFixtures.requireLocalAvd()
        val current = mutableStateOf(ready)
        var submitted: SafetyReportDraft? = null
        var sends = 0
        compose.setContent {
            MaterialTheme {
                SafetyReportDialog(
                    target,
                    current.value,
                    "de",
                    {
                        sends++
                        submitted = it
                        current.value =
                            current.value.copy(
                                reports = mapOf(target.key to SafetyReportState(pending = true))
                            )
                    },
                    {},
                )
            }
        }
        compose.onNodeWithTag("safety-reason-spam").performScrollTo().performClick()
        val explanation = "Synthetische Begründung für einen lokalen Test."
        compose
            .onNodeWithTag("safety-explanation")
            .performScrollTo()
            .performTextReplacement(explanation)
        InstrumentationRegistry.getInstrumentation()
            .sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK)
        compose.waitForIdle()
        compose.onNodeWithTag("safety-explanation").performScrollTo().performClick()
        compose
            .onNodeWithTag("safety-explanation")
            .performTextReplacement("$explanation Ergänzung.")
        compose
            .onNodeWithTag("safety-legal-basis")
            .performScrollTo()
            .performTextReplacement("Synthetic legal basis")
        compose
            .onNodeWithTag("safety-evidence")
            .performScrollTo()
            .performTextReplacement("https://example.invalid/synthetic-evidence")
        compose.onNodeWithTag("safety-good-faith").performScrollTo().performClick()
        compose.onNodeWithTag("safety-report-submit").performClick()
        compose.runOnIdle {
            assertEquals(1, sends)
            assertEquals("$explanation Ergänzung.", submitted?.explanation)
            assertEquals("Synthetic legal basis", submitted?.legalBasis)
            assertEquals("https://example.invalid/synthetic-evidence", submitted?.evidence)
        }
        for (tag in listOf("safety-explanation", "safety-legal-basis", "safety-evidence")) {
            compose.onNodeWithTag(tag).performScrollTo().assertIsNotEnabled().performClick()
            compose.onAllNodes(isFocused(), useUnmergedTree = true).assertCountEquals(0)
        }
        compose.onNodeWithTag("safety-report-submit").assertIsNotEnabled()
    }

    @Test
    fun unconfirmedReportShowsWarningAndCannotBeResubmitted() {
        compose.setContent {
            MaterialTheme {
                SafetyReportDialog(
                    target,
                    ready.copy(
                        reports =
                            mapOf(
                                target.key to SafetyReportState(error = SafetyFailure.UNCONFIRMED)
                            )
                    ),
                    "de",
                    {},
                    {},
                )
            }
        }
        compose.onNodeWithTag("safety-report-error").performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("safety-report-submit").assertIsNotEnabled()
        compose.onNodeWithTag("safety-explanation").performScrollTo().assertIsNotEnabled()
    }

    @Test
    fun blockingNeedsExplicitConfirmationWithDesiredState() {
        var change: Pair<String, Boolean>? = null
        compose.setContent {
            MaterialTheme {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    SafetyActions(
                        target,
                        ready,
                        "de",
                        {},
                        { id, blocked -> change = id to blocked },
                        { _, _ -> },
                        {},
                    )
                }
            }
        }
        compose.onNodeWithTag("safety-block-user").performScrollTo().performClick()
        compose.runOnIdle { assertNull(change) }
        compose.onNodeWithTag("safety-block-confirm").performClick()
        compose.runOnIdle { assertEquals("author" to true, change) }
    }

    @Test
    fun accountSwitchMasksPrivateBlockedListImmediately() {
        val authority = mutableStateOf<SafetySession?>(session)
        val state =
            ready.copy(
                blocks =
                    SafetyBlocks(
                        listOf(
                            SafetyUserBlock(
                                "author",
                                "Private blocked name",
                                null,
                                Instant.EPOCH,
                                Instant.EPOCH,
                            )
                        ),
                        emptyList(),
                    )
            )
        compose.setContent {
            MaterialTheme {
                SafetyBlockedScreen(
                    state.forSession(authority.value),
                    "de",
                    {},
                    { _, _ -> },
                    { _, _ -> },
                )
            }
        }
        compose.onNodeWithText("Private blocked name").assertExists()
        compose.runOnIdle { authority.value = session.copy(uid = "other", revision = 2) }
        compose.onNodeWithText("Private blocked name").assertDoesNotExist()
        compose.onNodeWithTag("safety-no-blocks").assertDoesNotExist()
    }

    @Test
    fun unverifiedAvailabilityOffersAccountWithoutSpinnerOrRetryLoop() {
        var account = false
        val state =
            SafetyState(session = session.copy(ready = false, access = SafetyAccess.VERIFY_EMAIL))
        compose.setContent {
            MaterialTheme { SafetyAvailabilityNotice(state, "de", {}, { account = true }) }
        }
        compose
            .onNodeWithText(safetyAccessText(SafetyAccess.VERIFY_EMAIL, "de"))
            .assertIsDisplayed()
        compose.onNodeWithTag("safety-availability-retry").assertDoesNotExist()
        compose.onNodeWithTag("safety-availability-account").performClick()
        compose.runOnIdle { assertTrue(account) }
    }
}
