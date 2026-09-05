package at.uac.android

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.espresso.Espresso
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.feature.accountstatus.*
import java.time.Instant
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AccountStatusUiTest {
    @get:Rule val compose = createComposeRule()

    private fun version(status: String = "warned") =
        AccountStatusVersion(
            "status-ui",
            status,
            "active",
            Instant.parse("2026-09-03T05:00:00Z"),
            "Exact independent reason",
            "Exact independent message",
            Instant.parse("2026-09-04T05:00:00Z"),
        )

    private fun state(v: AccountStatusVersion = version()) =
        AccountStatusState(
            AccountStatusSession(
                v.uid,
                1,
                AccountStatusObservation(v, null),
                !v.requiresSignOut,
                true,
            ),
            v,
            visible = true,
        )

    @Test
    fun warningShowsBothRawFieldsAndExplicitAcknowledgement() {
        var confirmed = 0
        val current = mutableStateOf(state())
        compose.setContent {
            MaterialTheme {
                AccountStatusDialog(
                    current.value,
                    "de",
                    {
                        confirmed++
                        current.value = current.value.copy(busy = true)
                    },
                    {},
                    {},
                    {},
                )
            }
        }
        compose
            .onNodeWithTag("account-status-message")
            .performScrollTo()
            .assertTextEquals("Exact independent message")
        compose
            .onNodeWithTag("account-status-reason")
            .performScrollTo()
            .assertTextEquals("Exact independent reason")
        compose
            .onNodeWithTag("account-status-acknowledge")
            .performScrollTo()
            .assertIsEnabled()
            .performClick()
            .assertIsNotEnabled()
        compose.runOnIdle { assertEquals(1, confirmed) }
    }

    @Test
    fun restrictedNoticeHasExpiryAndSignOutButNeverAcknowledges() {
        var signedOut = 0
        compose.setContent {
            MaterialTheme {
                AccountStatusDialog(
                    state(version("suspendedUntil")),
                    "uk",
                    { error("No ack") },
                    {},
                    { signedOut++ },
                    {},
                )
            }
        }
        compose.onNodeWithTag("account-status-acknowledge").assertDoesNotExist()
        compose.onNodeWithTag("account-status-expiry").performScrollTo().assertIsDisplayed()
        compose
            .onNodeWithTag("account-status-sign-out")
            .performScrollTo()
            .assertIsEnabled()
            .performClick()
        compose.runOnIdle { assertEquals(1, signedOut) }
    }

    @Test
    fun warnedLegacyBlockedAccountOffersSignOutNotIncorrectEmailVerification() {
        var signedOut = 0
        val notice = version().copy(blockState = "blocked")
        val current = state(notice)
        assertTrue(current.session?.verified == true)
        compose.setContent {
            MaterialTheme {
                AccountStatusDialog(
                    current,
                    "de",
                    { error("Restricted acknowledgement") },
                    {},
                    { signedOut++ },
                    { error("Incorrect email remediation") },
                )
            }
        }
        compose
            .onNodeWithTag("account-status-title")
            .performScrollTo()
            .assertTextEquals("Konto vorübergehend eingeschränkt")
        compose.onNodeWithTag("account-status-acknowledge").assertDoesNotExist()
        compose.onNodeWithTag("account-status-authenticate").assertDoesNotExist()
        compose
            .onNodeWithTag("account-status-sign-out")
            .performScrollTo()
            .assertIsEnabled()
            .performClick()
        compose.runOnIdle { assertEquals(1, signedOut) }
    }

    @Test
    fun unknownReceiptOffersReadOnlyCheckNotAnotherAcknowledgement() {
        var checked = 0
        val pending = state().copy(pending = version(), failure = AccountStatusFailure.UNCONFIRMED)
        compose.setContent {
            MaterialTheme {
                AccountStatusDialog(
                    pending,
                    "de",
                    { error("No blind resend") },
                    { checked++ },
                    {},
                    {},
                )
            }
        }
        compose.onNodeWithTag("account-status-acknowledge").assertDoesNotExist()
        compose.onNodeWithTag("account-status-error").performScrollTo().assertIsDisplayed()
        compose
            .onNodeWithTag("account-status-reconcile")
            .performScrollTo()
            .assertIsEnabled()
            .performClick()
        compose.runOnIdle { assertEquals(1, checked) }
    }

    @Test
    fun unverifiedNoticeHasExplicitAuthenticationEscapeAndSignOut() {
        var escaped = 0
        val value =
            state().let {
                it.copy(session = it.session?.copy(canAcknowledge = false, verified = false))
            }
        compose.setContent {
            MaterialTheme {
                AccountStatusDialog(
                    value,
                    "uk",
                    { error("No unverified ack") },
                    {},
                    {},
                    { escaped++ },
                )
            }
        }
        compose.onNodeWithTag("account-status-acknowledge").assertDoesNotExist()
        compose
            .onNodeWithTag("account-status-authenticate")
            .performScrollTo()
            .assertTextEquals("Підтвердити пошту")
            .performClick()
        compose.onNodeWithTag("account-status-sign-out").performScrollTo().assertIsEnabled()
        compose.runOnIdle { assertEquals(1, escaped) }
    }

    @Test
    fun mfaEscapeIsLabelledAsSecondFactorNotEmail() {
        val value =
            state().let {
                it.copy(session = it.session?.copy(canAcknowledge = false, needsMfa = true))
            }
        compose.setContent { MaterialTheme { AccountStatusDialog(value, "de", {}, {}, {}, {}) } }
        compose
            .onNodeWithTag("account-status-authenticate")
            .performScrollTo()
            .assertTextEquals("Zweiten Faktor bestätigen")
    }

    @Test
    fun obsoleteUidAndHiddenHostDoNotRenderPrivateReason() {
        val current = mutableStateOf(state())
        compose.setContent {
            MaterialTheme { AccountStatusDialog(current.value, "de", {}, {}, {}, {}) }
        }
        compose.onNodeWithTag("account-status-notice").assertIsDisplayed()
        compose.runOnIdle {
            current.value = current.value.copy(session = current.value.session?.copy(uid = "other"))
        }
        compose.onNodeWithTag("account-status-notice").assertDoesNotExist()
        compose.runOnIdle { current.value = state().copy(visible = false) }
        compose.onNodeWithTag("account-status-notice").assertDoesNotExist()
    }

    @Test
    fun backCannotSilentlyDismissStatusNotice() {
        compose.setContent { MaterialTheme { AccountStatusDialog(state(), "de", {}, {}, {}, {}) } }
        compose.onNodeWithTag("account-status-notice").assertIsDisplayed()
        Espresso.pressBackUnconditionally()
        compose.onNodeWithTag("account-status-notice").assertIsDisplayed()
    }

    @Test
    fun pendingActionDisablesEveryMutableEscape() {
        compose.setContent {
            MaterialTheme { AccountStatusDialog(state().copy(busy = true), "uk", {}, {}, {}, {}) }
        }
        compose.onNodeWithTag("account-status-busy").performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("account-status-acknowledge").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithTag("account-status-sign-out").performScrollTo().assertIsNotEnabled()
    }
}
