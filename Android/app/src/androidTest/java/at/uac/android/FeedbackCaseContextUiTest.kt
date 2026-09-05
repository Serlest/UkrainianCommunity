package at.uac.android

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.view.Window
import android.view.WindowManager
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.platform.LocalContext
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
class FeedbackCaseContextUiTest {
    @get:Rule val compose = createComposeRule()
    private val actor = FeedbackSession("synthetic-reporter", 1, true, false, "Synthetic")
    private val context =
        FeedbackCaseContext(
            "SYNTHETIC CASE",
            "appealed",
            "other",
            "https://invalid.example/synthetic-only",
            "PRIVATE SYNTHETIC EXPLANATION",
            "SYNTHETIC LEGAL BASIS",
            "SYNTHETIC EVIDENCE",
            true,
            Instant.EPOCH,
            "de",
            FeedbackCaseAppeal("pending", "SYNTHETIC APPEAL REASON", null),
        )
    private val item =
        FeedbackContract.item(
                RawDocument(
                    "report",
                    FeedbackContract.creation(
                        "report",
                        actor,
                        FeedbackDraft(message = "Synthetic original message"),
                        Instant.EPOCH,
                    ),
                )
            )
            .copy(hasDsaCase = true, caseNumber = context.caseNumber, caseContext = context)

    private fun state() =
        FeedbackState(
            session = actor,
            selectedId = item.id,
            conversation = FeedbackConversation(item, emptyList()),
        )

    private fun scroll(tag: String) {
        compose.onNodeWithTag("feedback-conversation").performScrollToNode(hasTestTag(tag))
        compose.onNodeWithTag(tag).performScrollTo().assertIsDisplayed()
    }

    @Test
    fun germanLargeTextShowsAllReadOnlyDetailsAndKeepsReplyReachable() {
        compose.setContent { MaterialTheme { FeedbackDetail(state(), "de", {}, {}, {}, {}, {}) } }
        for (tag in
            listOf("location", "explanation", "basis", "evidence", "appeal", "good-faith")) scroll(
            "feedback-case-$tag"
        )
        compose
            .onNodeWithTag("feedback-case-good-faith")
            .assertTextContains(
                "Die meldende Person hat die Abgabe nach bestem Wissen und Gewissen bestätigt."
            )
        scroll("feedback-send")
        compose.onNodeWithTag("feedback-close").assertDoesNotExist()
        compose.onNodeWithText("Einspruch senden").assertDoesNotExist()
    }

    @Test
    fun ukrainianFalseGoodFaithIsNotPresentedAsConfirmedAndDsaCannotOrdinarilyClose() {
        val snapshot =
            state()
                .copy(
                    audience = FeedbackAudience.MANAGEMENT,
                    session = actor.copy(canManage = true),
                    conversation =
                        FeedbackConversation(
                            item.copy(caseContext = context.copy(goodFaithConfirmed = false)),
                            emptyList(),
                        ),
                )
        compose.setContent { MaterialTheme { FeedbackDetail(snapshot, "uk", {}, {}, {}, {}, {}) } }
        scroll("feedback-case-good-faith")
        compose
            .onNodeWithTag("feedback-case-good-faith")
            .assertTextEquals("Підтвердження добросовісності тут відсутнє.")
        scroll("feedback-send")
        compose.onNodeWithTag("feedback-close").assertDoesNotExist()
    }

    @Test
    fun malformedSummaryHasExplicitWarningWhileConversationRemainsAvailable() {
        val legacy = item.copy(caseContext = null, status = FeedbackStatus.CLOSED)
        val snapshot =
            state()
                .copy(
                    conversation =
                        FeedbackConversation(legacy, FeedbackContract.merge(legacy, emptyList()))
                )
        compose.setContent { MaterialTheme { FeedbackDetail(snapshot, "de", {}, {}, {}, {}, {}) } }
        scroll("feedback-case-invalid")
        compose.onNodeWithTag("feedback-case-explanation").assertDoesNotExist()
        compose.onNodeWithTag("feedback-conversation").performScrollToNode(hasText(legacy.message))
        compose.onNodeWithText(legacy.message).assertIsDisplayed()
        compose.onNodeWithTag("feedback-send").assertDoesNotExist()
    }

    @Test
    fun staleAuthoritySelectionLoadingAndErrorsNeverExposeReporterContext() {
        val snapshot = mutableStateOf(state())
        compose.setContent {
            MaterialTheme { FeedbackDetail(snapshot.value, "de", {}, {}, {}, {}, {}) }
        }
        scroll("feedback-case-explanation")
        for (masked in
            listOf(
                state().copy(session = actor.copy(uid = "other")),
                state().copy(selectedId = "other"),
                state().copy(loading = true),
                state().copy(error = FeedbackFailure.DENIED),
                state().copy(session = actor.copy(ready = false)),
                state().forSession(actor.copy(revision = 2)),
                state().forSession(null),
            )) {
            compose.runOnIdle { snapshot.value = masked }
            compose.onNodeWithTag("feedback-case-context").assertDoesNotExist()
            compose.onNodeWithText(context.illegalExplanation).assertDoesNotExist()
        }
    }

    @Test
    fun actualWindowLeaseProtectsDsaDetailAndRestoresPriorOwnership() {
        val ordinary =
            state()
                .copy(
                    conversation =
                        FeedbackConversation(
                            item.copy(hasDsaCase = false, caseContext = null),
                            emptyList(),
                        )
                )
        val snapshot = mutableStateOf(ordinary)
        var window: Window? = null
        var originalSecure = false
        compose.setContent {
            val local = LocalContext.current
            SideEffect { window = local.activity()?.window }
            MaterialTheme { FeedbackDetail(snapshot.value, "de", {}, {}, {}, {}, {}) }
        }
        compose.runOnIdle {
            originalSecure = requireNotNull(window).secure()
            snapshot.value = state()
        }
        compose.runOnIdle {
            assertTrue(requireNotNull(window).secure())
            snapshot.value = ordinary
        }
        compose.runOnIdle { assertEquals(originalSecure, requireNotNull(window).secure()) }
    }

    private fun Window.secure() = attributes.flags and WindowManager.LayoutParams.FLAG_SECURE != 0

    private fun Context.activity(): Activity? =
        when (this) {
            is Activity -> this
            is ContextWrapper -> baseContext.takeIf { it !== this }?.activity()
            else -> null
        }
}
