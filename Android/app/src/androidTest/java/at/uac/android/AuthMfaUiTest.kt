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
import at.uac.android.feature.auth.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Pure fake UI evidence. This class never enrolls or proves a real second factor. */
@RunWith(AndroidJUnit4::class)
class AuthMfaUiTest {
    @get:Rule val compose = createComposeRule()
    private val identity = AuthIdentity("mfa-ui", "mfa-ui@example.invalid", true)
    private val factor = AuthTotpFactor("factor-1", "Test authenticator")

    private fun session() =
        AuthSession(
            AuthStage.AUTHENTICATED,
            identity,
            AuthProfile(identity.uid, identity.email, "MFA UI"),
        )

    @Test
    fun challengeRequiresSelectedFactorAndSixDigitsAndClearsCodeAfterSubmit() {
        val state =
            mutableStateOf(
                session()
                    .copy(
                        stage = AuthStage.MFA_CHALLENGE,
                        mfa =
                            AuthMfaState(
                                listOf(factor, factor.copy(id = "backup", name = "Backup")),
                                challenge = true,
                            ),
                    )
            )
        var result: Pair<String, String>? = null
        compose.setContent {
            MaterialTheme {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    MfaChallengeFields(
                        state.value,
                        "de",
                        { id, code ->
                            result = id to code
                            state.value = state.value.copy(busy = true)
                        },
                        {},
                    )
                }
            }
        }
        compose.onNodeWithTag("auth-mfa-submit").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithTag("auth-mfa-code").performScrollTo().performTextInput("123456")
        compose.onNodeWithTag("auth-mfa-submit").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithTag("auth-mfa-factor-factor-1").performScrollTo().performClick()
        compose.onNodeWithTag("auth-mfa-code").performScrollTo().performTextInput("123456")
        compose
            .onNodeWithTag("auth-mfa-submit")
            .performScrollTo()
            .performClick()
            .assertIsNotEnabled()
        compose.runOnIdle { assertEquals(factor.id to "123456", result) }
        compose
            .onNodeWithTag("auth-mfa-code")
            .assert(
                SemanticsMatcher.expectValue(SemanticsProperties.EditableText, AnnotatedString(""))
            )
    }

    @Test
    fun challengeCancelNeverSubmitsAndSessionRevisionClearsOldCode() {
        val state =
            mutableStateOf(
                session()
                    .copy(
                        stage = AuthStage.MFA_CHALLENGE,
                        mfa = AuthMfaState(listOf(factor), challenge = true),
                    )
            )
        var submissions = 0
        var cancellations = 0
        compose.setContent {
            MaterialTheme {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    MfaChallengeFields(
                        state.value,
                        "uk",
                        { _, _ -> submissions++ },
                        { cancellations++ },
                    )
                }
            }
        }
        compose.onNodeWithTag("auth-mfa-code").performScrollTo().performTextInput("123456")
        compose.runOnIdle { state.value = state.value.copy(revision = 2) }
        compose.onNodeWithTag("auth-mfa-submit").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithTag("auth-mfa-cancel").performScrollTo().performClick()
        compose.runOnIdle {
            assertEquals(0, submissions)
            assertEquals(1, cancellations)
        }
    }

    @Test
    fun setupOffersExplicitManualKeyAndSafeNoAuthenticatorFallback() {
        val setup =
            AuthTotpSetup(
                "SYNTHETIC-UI-ONLY",
                "otpauth://totp/UAC:test?secret=SYNTHETIC",
                Long.MAX_VALUE,
            )
        val state = mutableStateOf(session().copy(mfa = AuthMfaState(setup = setup)))
        var opens = 0
        var complete = ""
        compose.setContent {
            MaterialTheme {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    MfaSecurityFields(
                        state.value,
                        "de",
                        {},
                        {},
                        {},
                        { _, _ -> },
                        { complete = it },
                        {},
                        {},
                        {
                            opens++
                            false
                        },
                    )
                }
            }
        }
        compose.onNodeWithTag("auth-mfa-secret").assertDoesNotExist()
        compose.onNodeWithTag("auth-mfa-open-app").performScrollTo().performClick()
        compose.onNodeWithTag("auth-mfa-no-app").performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("auth-mfa-reveal").performScrollTo().performClick()
        compose
            .onNodeWithTag("auth-mfa-secret")
            .performScrollTo()
            .assertTextEquals("SYNTHETIC-UI-ONLY")
        compose.onNodeWithTag("auth-mfa-code").performScrollTo().performTextInput("123456")
        compose.onNodeWithTag("auth-mfa-enroll-submit").performScrollTo().performClick()
        compose.runOnIdle {
            assertEquals(1, opens)
            assertEquals("123456", complete)
        }
    }

    @Test
    fun setupReplacementHidesKeyAndClearsPreviousCode() {
        val setup =
            AuthTotpSetup("SYNTHETIC-A", "otpauth://totp/UAC:a?secret=SYNTHETIC", Long.MAX_VALUE)
        val state = mutableStateOf(session().copy(mfa = AuthMfaState(setup = setup)))
        compose.setContent {
            MaterialTheme {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    MfaSecurityFields(
                        state.value,
                        "uk",
                        {},
                        {},
                        {},
                        { _, _ -> },
                        {},
                        {},
                        {},
                        { false },
                    )
                }
            }
        }
        compose.onNodeWithTag("auth-mfa-reveal").performScrollTo().performClick()
        compose.onNodeWithTag("auth-mfa-code").performScrollTo().performTextInput("123456")
        compose.runOnIdle {
            state.value =
                state.value.copy(
                    mfa =
                        AuthMfaState(
                            setup =
                                AuthTotpSetup(
                                    "SYNTHETIC-B",
                                    "otpauth://totp/UAC:b?secret=SYNTHETIC",
                                    Long.MAX_VALUE,
                                )
                        )
                )
        }
        compose.onNodeWithTag("auth-mfa-secret").assertDoesNotExist()
        compose.onNodeWithTag("auth-mfa-enroll-submit").performScrollTo().assertIsNotEnabled()
    }

    @Test
    fun lastAdminFactorAndUnverifiedActivationRemainDisabled() {
        val state =
            mutableStateOf(
                session()
                    .copy(
                        profile =
                            session()
                                .profile!!
                                .copy(globalRole = "admin", requiresMultiFactorAuth = true),
                        mfa = AuthMfaState(listOf(factor), loaded = true),
                    )
            )
        compose.setContent {
            MaterialTheme {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    MfaSecurityFields(
                        state.value,
                        "de",
                        {},
                        {},
                        {},
                        { _, _ -> },
                        {},
                        {},
                        {},
                        { false },
                    )
                }
            }
        }
        compose
            .onNodeWithTag("auth-mfa-password")
            .performScrollTo()
            .performTextInput("synthetic-password")
        compose.onNodeWithTag("auth-mfa-remove-factor-1").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithTag("auth-mfa-last-factor").performScrollTo().assertIsDisplayed()
        compose.runOnIdle {
            state.value =
                state.value.copy(
                    profile = state.value.profile!!.copy(requiresMultiFactorAuth = false)
                )
        }
        compose.onNodeWithTag("auth-mfa-activate").performScrollTo().assertIsNotEnabled()
    }

    @Test
    fun uncertainMutationOffersReadBackAndNoReplayControls() {
        var reads = 0
        compose.setContent {
            MaterialTheme {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    MfaSecurityFields(
                        session().copy(mfa = AuthMfaState(unconfirmed = true)),
                        "uk",
                        { reads++ },
                        {},
                        {},
                        { _, _ -> },
                        {},
                        {},
                        {},
                        { false },
                    )
                }
            }
        }
        compose.onNodeWithTag("auth-mfa-unconfirmed").performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("auth-mfa-begin").assertDoesNotExist()
        compose.onNodeWithTag("auth-mfa-password").assertDoesNotExist()
        compose.onNodeWithTag("auth-mfa-load").performScrollTo().performClick()
        compose.runOnIdle { assertEquals(1, reads) }
    }
}
