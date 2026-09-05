package at.uac.android

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.feature.auth.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AuthLegalUiTest {
    @get:Rule val compose = createComposeRule()
    private val terms =
        AuthLegalDocument(
            "terms",
            "synthetic-terms",
            true,
            mapOf("de" to "Bedingungen", "uk" to "Умови"),
            mapOf("de" to "Full text"),
        )
    private val privacy =
        AuthLegalDocument(
            "privacy",
            "synthetic-privacy",
            true,
            mapOf("de" to "Datenschutz", "uk" to "Конфіденційність"),
            mapOf("de" to "Full text"),
        )

    private fun session() =
        AuthSession(
            AuthStage.AUTHENTICATED,
            AuthIdentity("legal-ui", "legal-ui@example.invalid", true),
            AuthProfile("legal-ui", "legal-ui@example.invalid", "Test"),
            gate = AuthGate.LEGAL_REQUIRED,
            legalDocuments = listOf(terms, privacy),
        )

    @Test
    fun explicitConsentForEveryRequiredDocumentIsNecessaryAndReaderKeepsItsVersion() {
        var accepted: Map<String, String>? = null
        var read: AuthLegalDocument? = null
        compose.setContent {
            MaterialTheme {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    LegalAcceptanceFields(session(), "de", { read = it }, { accepted = it }, {})
                }
            }
        }
        compose.onNodeWithTag("auth-legal-submit").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithTag("auth-required-terms-read").performScrollTo().performClick()
        compose.runOnIdle {
            assertEquals(terms, read)
            assertNull(accepted)
        }
        compose.onNodeWithTag("auth-accept-terms").performScrollTo().performClick()
        compose.onNodeWithTag("auth-legal-submit").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithTag("auth-accept-privacy").performScrollTo().performClick()
        compose
            .onNodeWithTag("auth-legal-submit")
            .performScrollTo()
            .assertIsEnabled()
            .performClick()
        compose.runOnIdle {
            assertEquals(mapOf("terms" to terms.version, "privacy" to privacy.version), accepted)
        }
    }

    @Test
    fun documentChangeClearsConsentAndBusyStatePreventsDoubleSubmission() {
        val state = mutableStateOf(session())
        var calls = 0
        compose.setContent {
            MaterialTheme {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    LegalAcceptanceFields(
                        state.value,
                        "uk",
                        {},
                        {
                            calls++
                            state.value = state.value.copy(busy = true)
                        },
                        {},
                    )
                }
            }
        }
        compose.onNodeWithTag("auth-accept-terms").performScrollTo().performClick()
        compose.onNodeWithTag("auth-accept-privacy").performScrollTo().performClick()
        compose.runOnIdle {
            state.value =
                state.value.copy(
                    legalDocuments = listOf(terms.copy(version = "new-local-version"), privacy)
                )
        }
        compose.onNodeWithTag("auth-legal-submit").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithTag("auth-accept-terms").performScrollTo().performClick()
        compose.onNodeWithTag("auth-accept-privacy").performScrollTo().performClick()
        compose
            .onNodeWithTag("auth-legal-submit")
            .performScrollTo()
            .performClick()
            .assertIsNotEnabled()
        compose.runOnIdle { assertEquals(1, calls) }
    }

    @Test
    fun accountChangeDoesNotReuseConsentAndDeclineDoesNotSubmit() {
        val state = mutableStateOf(session())
        var accepted = 0
        var declined = 0
        compose.setContent {
            MaterialTheme {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    LegalAcceptanceFields(state.value, "de", {}, { accepted++ }, { declined++ })
                }
            }
        }
        compose.onNodeWithTag("auth-accept-terms").performScrollTo().performClick()
        compose.onNodeWithTag("auth-accept-privacy").performScrollTo().performClick()
        compose.runOnIdle {
            state.value =
                state.value.copy(identity = AuthIdentity("other", "other@example.invalid", true))
        }
        compose.onNodeWithTag("auth-legal-submit").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithTag("auth-legal-decline").performScrollTo().performClick()
        compose.runOnIdle {
            assertEquals(0, accepted)
            assertEquals(1, declined)
        }
    }
}
