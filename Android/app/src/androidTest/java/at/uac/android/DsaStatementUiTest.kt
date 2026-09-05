package at.uac.android

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.feature.dsastatement.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DsaStatementUiTest {
    @get:Rule val compose = createComposeRule()
    private val session = DsaStatementSession("synthetic-author", 1, "synthetic-backend", true)
    private val statement =
        DsaStatement(
            "synthetic-report",
            "SYNTHETIC CASE",
            "decided",
            "comment",
            "synthetic-content",
            DsaStatementDecision(
                "removed",
                "PRIVATE SYNTHETIC FACTS",
                "Synthetic basis",
                "Synthetic terms",
                "AT",
                "Synthetic duration",
                "Synthetic redress",
                false,
            ),
            DsaStatementAppealDecision("changed", "SYNTHETIC APPEAL REASON", false),
        )

    private fun state() = DsaStatementState(session, statement.id, true, false, statement)

    private fun scroll(tag: String) {
        compose.onNodeWithTag("dsa-statement-list").performScrollToNode(hasTestTag(tag))
        compose.onNodeWithTag(tag).performScrollTo().assertIsDisplayed()
    }

    @Test
    fun germanLargeTextShowsFullDecisionAndAppealWithOnlyReadAction() {
        var refreshes = 0
        compose.setContent {
            MaterialTheme { DsaStatementScreen(state(), statement.id, "de", { refreshes++ }, {}) }
        }
        for (tag in
            listOf(
                "dsa-case",
                "dsa-status",
                "dsa-facts",
                "dsa-legal-basis",
                "dsa-terms-basis",
                "dsa-territory",
                "dsa-duration",
                "dsa-redress",
                "dsa-automation",
                "dsa-appeal-outcome",
                "dsa-appeal-reason",
                "dsa-privacy-note",
                "dsa-refresh",
            )) scroll(tag)
        compose.onNodeWithTag("dsa-refresh").performClick()
        compose.runOnIdle { assertEquals(1, refreshes) }
        compose.onNodeWithText("Löschen").assertDoesNotExist()
        compose.onNodeWithText("Entscheidung senden").assertDoesNotExist()
    }

    @Test
    fun ukrainianUnknownOutcomesAreExplicitNotInventedLegalDecisions() {
        val unknown =
            statement.copy(
                rawStatus = "future-state",
                decision = statement.decision!!.copy(rawOutcome = "future-outcome"),
                appealDecision = statement.appealDecision!!.copy(rawOutcome = "future-appeal"),
            )
        compose.setContent {
            MaterialTheme {
                DsaStatementScreen(state().copy(statement = unknown), statement.id, "uk", {}, {})
            }
        }
        scroll("dsa-status")
        compose.onNodeWithTag("dsa-status").assertTextContains("Невідомий статус: future-state")
        scroll("dsa-outcome")
        compose
            .onNodeWithTag("dsa-outcome")
            .assertTextContains("Невідомий результат: future-outcome")
        scroll("dsa-appeal-outcome")
        compose
            .onNodeWithTag("dsa-appeal-outcome")
            .assertTextContains("Невідомий результат: future-appeal")
    }

    @Test
    fun sessionChangeImmediatelyMasksSnapshotBeforeObserver() {
        val authority = mutableStateOf<DsaStatementSession?>(session)
        compose.setContent {
            MaterialTheme {
                DsaStatementScreen(state().forSession(authority.value), statement.id, "de", {}, {})
            }
        }
        scroll("dsa-facts")
        compose.runOnIdle { authority.value = session.copy(uid = "another", revision = 2) }
        compose.onNodeWithText("PRIVATE SYNTHETIC FACTS").assertDoesNotExist()
        compose.runOnIdle { authority.value = null }
        compose.onNodeWithTag("dsa-account-gate").assertExists()
    }

    @Test
    fun revokedAccessAndErrorCannotExposeOldStatement() {
        val snapshot = mutableStateOf(state())
        compose.setContent {
            MaterialTheme { DsaStatementScreen(snapshot.value, statement.id, "de", {}, {}) }
        }
        scroll("dsa-facts")
        compose.runOnIdle { snapshot.value = state().copy(error = DsaStatementFailure.ACCESS) }
        compose.onNodeWithText("PRIVATE SYNTHETIC FACTS").assertDoesNotExist()
        scroll("dsa-error")
        compose.runOnIdle { snapshot.value = state().copy(session = session.copy(ready = false)) }
        compose.onNodeWithTag("dsa-account-gate").assertExists()
        compose.onNodeWithText("PRIVATE SYNTHETIC FACTS").assertDoesNotExist()
    }

    @Test
    fun differentRouteAndLoadingNeverRenderPreviousReport() {
        val route = mutableStateOf(statement.id)
        val snapshot = mutableStateOf(state())
        compose.setContent {
            MaterialTheme { DsaStatementScreen(snapshot.value, route.value, "de", {}, {}) }
        }
        scroll("dsa-facts")
        compose.runOnIdle { route.value = "another-report" }
        compose.onNodeWithText("PRIVATE SYNTHETIC FACTS").assertDoesNotExist()
        compose.onNodeWithTag("dsa-loading").assertExists()
        compose.runOnIdle {
            route.value = statement.id
            snapshot.value = state().copy(loading = true)
        }
        compose.onNodeWithText("PRIVATE SYNTHETIC FACTS").assertDoesNotExist()
        compose.onNodeWithTag("dsa-refresh").assertDoesNotExist()
    }

    @Test
    fun noDecisionAndMissingAreDifferentStates() {
        val snapshot =
            mutableStateOf(
                state()
                    .copy(
                        statement =
                            statement.copy(
                                decision = null,
                                appealDecision = null,
                                rawStatus = "underReview",
                            )
                    )
            )
        compose.setContent {
            MaterialTheme { DsaStatementScreen(snapshot.value, statement.id, "uk", {}, {}) }
        }
        scroll("dsa-no-decision")
        compose.onNodeWithTag("dsa-error").assertDoesNotExist()
        compose.runOnIdle {
            snapshot.value = state().copy(statement = null, error = DsaStatementFailure.MISSING)
        }
        scroll("dsa-error")
        compose.onNodeWithTag("dsa-no-decision").assertDoesNotExist()
        compose
            .onNodeWithTag("dsa-error")
            .assertTextContains("Це обґрунтування недоступне для цього облікового запису.")
    }

    @Test
    fun offlineExplainsNoCacheAndRetryIsSingleExplicitAction() {
        var attempts = 0
        val snapshot =
            mutableStateOf(state().copy(statement = null, error = DsaStatementFailure.OFFLINE))
        compose.setContent {
            MaterialTheme {
                DsaStatementScreen(
                    snapshot.value,
                    statement.id,
                    "uk",
                    {
                        attempts++
                        snapshot.value = snapshot.value.copy(loading = true, error = null)
                    },
                    {},
                )
            }
        }
        scroll("dsa-error")
        compose
            .onNodeWithTag("dsa-error")
            .assertTextContains("Сервер недоступний. Збережені приватні дані не показуються.")
        scroll("dsa-refresh")
        compose.onNodeWithTag("dsa-refresh").performClick()
        compose.onNodeWithTag("dsa-refresh").assertDoesNotExist()
        compose.runOnIdle { assertEquals(1, attempts) }
    }
}
