package at.uac.android

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.AnnotatedString
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.feature.accountdeletion.*
import java.time.Instant
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AccountDeletionUiTest {
    @get:Rule val compose = createComposeRule()
    private val alice = AccountDeletionSession("synthetic-deletion-ui-a", 1)
    private val ready =
        AccountDeletionState(alice, policy = AccountDeletionPolicy(false, false, false))

    private fun show(
        state: androidx.compose.runtime.State<AccountDeletionState>,
        language: String = "de",
        submit: (String, Boolean) -> Unit = { _, _ -> },
        mfa: (String, String) -> Unit = { _, _ -> },
        reconcile: () -> Unit = {},
    ) {
        compose.setContent {
            MaterialTheme {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    AccountDeletionControls(
                        state.value,
                        language,
                        {},
                        submit,
                        mfa,
                        reconcile,
                        {},
                        {},
                        {},
                    )
                }
            }
        }
    }

    @Test
    fun typedAcknowledgementAndCurrentPasswordRequiredThenBusyCannotRepeatOrCancel() {
        val state = mutableStateOf(ready)
        var submissions = 0
        show(
            state,
            submit = { password, confirmed ->
                assertEquals("Synthetic-only", password)
                assertTrue(confirmed)
                submissions++
                state.value =
                    state.value.copy(
                        phase = AccountDeletionPhase.DELETING,
                        submittedAt = Instant.now(),
                    )
            },
        )
        compose.onNodeWithTag("account-delete-open").performScrollTo().performClick()
        compose.onNodeWithTag("account-delete-submit").assertIsNotEnabled()
        compose
            .onNodeWithTag("account-delete-password")
            .performScrollTo()
            .performTextReplacement("Synthetic-only")
        compose
            .onNodeWithTag("account-delete-confirmation")
            .performScrollTo()
            .performTextReplacement("wrong")
        compose.onNodeWithTag("account-delete-acknowledge").performScrollTo().performClick()
        compose.onNodeWithTag("account-delete-submit").assertIsNotEnabled()
        compose
            .onNodeWithTag("account-delete-confirmation")
            .performScrollTo()
            .performTextReplacement("LÖSCHEN")
        compose.onNodeWithTag("account-delete-submit").assertIsEnabled().performClick()
        compose.onNodeWithTag("account-delete-check").assertIsNotEnabled()
        compose.onNodeWithTag("account-delete-cancel").assertIsNotEnabled()
        compose.runOnIdle { assertEquals(1, submissions) }
    }

    @Test
    fun unresolvedColdStateOffersStatusCheckNotDestructiveReplay() {
        val state =
            mutableStateOf(
                ready.copy(submittedAt = Instant.now(), error = AccountDeletionFailure.UNCONFIRMED)
            )
        var checks = 0
        var submissions = 0
        show(state, submit = { _, _ -> submissions++ }, reconcile = { checks++ })
        compose.onNodeWithTag("account-delete-open").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithTag("account-delete-check").performScrollTo().performClick()
        compose.runOnIdle {
            assertEquals(1, checks)
            assertEquals(0, submissions)
        }
    }

    @Test
    fun ukrainianDialogUsesRealFactorChoiceAndClearCodeAfterSubmit() {
        val state = mutableStateOf(ready)
        var proof: Pair<String, String>? = null
        show(
            state,
            "uk",
            mfa = { id, code ->
                proof = id to code
                state.value = state.value.copy(phase = AccountDeletionPhase.REAUTHENTICATING)
            },
        )
        compose.onNodeWithTag("account-delete-open").performScrollTo().performClick()
        compose.runOnIdle {
            state.value =
                ready.copy(
                    phase = AccountDeletionPhase.MFA,
                    factors = listOf(AccountDeletionFactor("opaque", "Test authenticator")),
                )
        }
        compose.onNodeWithTag("account-delete-mfa-submit").assertIsNotEnabled()
        compose
            .onNodeWithTag("account-delete-code")
            .performScrollTo()
            .performTextReplacement("123456")
        compose.onNodeWithTag("account-delete-mfa-submit").assertIsEnabled().performClick()
        compose.runOnIdle { assertEquals("opaque" to "123456", proof) }
        compose.onNodeWithTag("account-delete-code").assertDoesNotExist()
        compose.onNodeWithTag("account-delete-submit").assertIsNotEnabled()
    }

    @Test
    fun accountSwitchClosesSecureDialogAndRemovesCredentialsAndFactorNames() {
        val state = mutableStateOf(ready)
        show(state)
        compose.onNodeWithTag("account-delete-open").performScrollTo().performClick()
        compose
            .onNodeWithTag("account-delete-password")
            .performScrollTo()
            .performTextReplacement("Sensitive-test-only")
        compose.runOnIdle {
            state.value = ready.copy(session = AccountDeletionSession("synthetic-deletion-ui-b", 2))
        }
        compose.onNodeWithTag("account-delete-dialog").assertDoesNotExist()
        compose.onNodeWithTag("account-delete-open").performScrollTo().performClick()
        compose
            .onNodeWithTag("account-delete-password")
            .performScrollTo()
            .assert(
                SemanticsMatcher.expectValue(SemanticsProperties.EditableText, AnnotatedString(""))
            )
        compose.onNodeWithTag("account-delete-submit").assertIsNotEnabled()
    }
}
