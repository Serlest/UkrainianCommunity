package at.uac.android

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.auth.bundledReferenceLegal
import at.uac.android.feature.auth.formatLegalText
import at.uac.android.feature.browse.BrowseViewModel
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AuthUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    private fun scroll(tag: String) {
        compose.onNodeWithTag(tag).performScrollTo()
    }

    private fun readLegal(type: String, language: String) {
        // A connected local Auth store may already have the current server documents.
        // The reference banner exists only for the bundled fallback, not every reader.
        val document = compose.runOnIdle {
            LocalAuthSession.get(compose.activity)
                .state
                .value
                .legalDocuments
                .ifEmpty { bundledReferenceLegal(compose.activity) }
                .single { it.type == type }
        }
        scroll("auth-legal-$type")
        compose.onNodeWithTag("auth-legal-$type").performClick()
        compose.waitUntil(15_000) { compose.onNodeWithTag("legal-close").isDisplayed() }
        compose
            .onNodeWithTag("legal-content")
            .assert(
                SemanticsMatcher.expectValue(
                    SemanticsProperties.PaneTitle,
                    document.title(language),
                )
            )
        val blocks = formatLegalText(document.text(language))
        blocks.forEachIndexed { index, block ->
            compose
                .onNodeWithTag("legal-block-$index")
                .assertTextEquals(block.runs.joinToString("") { it.text })
        }
        compose
            .onNodeWithTag("legal-block-${blocks.lastIndex}")
            .performScrollTo()
            .assertIsDisplayed()
        compose
            .onNodeWithTag("legal-close")
            .assertContentDescriptionEquals(if (language == "de") "Schließen" else "Закрити")
            .assertHeightIsAtLeast(48.dp)
            .assertIsDisplayed()
            .performClick()
        compose.onNodeWithTag("auth-legal-$type").assertExists()
    }

    @Before
    fun showGuestAccount() {
        compose.runOnIdle {
            LocalAuthSession.get(compose.activity).signOut()
            ViewModelProvider(compose.activity)[BrowseViewModel::class.java].apply {
                preference("language", "de")
                navigate("profile", true)
            }
        }
        compose.waitUntil(15_000) {
            LocalAuthSession.get(compose.activity).state.value.stage == AuthStage.GUEST
        }
        compose.waitForIdle()
        compose.openGuestLogin()
    }

    @Test
    fun guestValidationAndCompleteLegalReader() {
        scroll("auth-login-submit")
        compose.onNodeWithTag("auth-login-submit").performClick()
        scroll("auth-error")
        compose
            .onNodeWithTag("auth-error")
            .assertTextContains("gültige E-Mail-Adresse", substring = true)
        scroll("auth-tab-register")
        compose.onNodeWithTag("auth-tab-register").performClick()
        scroll("auth-email")
        compose.onNodeWithTag("auth-email").performTextInput("ui@example.invalid")
        scroll("auth-password")
        compose.onNodeWithTag("auth-password").performTextInput("short")
        scroll("auth-register-submit")
        compose.onNodeWithTag("auth-register-submit").performClick()
        scroll("auth-error")
        compose.onNodeWithTag("auth-error").assertTextContains("10 bis 128", substring = true)
        readLegal("terms", "de")
    }

    @Test
    fun enteredCredentialsAreNotStoredInActivitySavedState() {
        scroll("auth-email")
        compose.onNodeWithTag("auth-email").performTextInput("private-ui@example.invalid")
        scroll("auth-password")
        compose.onNodeWithTag("auth-password").performTextInput("NeverPersistPassword")
        compose.activityRule.scenario.recreate()
        compose.waitForIdle()
        scroll("auth-email")
        compose
            .onNodeWithTag("auth-email")
            .assert(
                SemanticsMatcher.expectValue(SemanticsProperties.EditableText, AnnotatedString(""))
            )
        scroll("auth-password")
        compose
            .onNodeWithTag("auth-password")
            .assert(
                SemanticsMatcher.expectValue(SemanticsProperties.EditableText, AnnotatedString(""))
            )
    }

    @Test
    fun ukrainianValidationAndPrivacyReaderAreReadable() {
        compose.runOnIdle {
            ViewModelProvider(compose.activity)[BrowseViewModel::class.java].preference(
                "language",
                "uk",
            )
        }
        scroll("auth-login-submit")
        compose.onNodeWithTag("auth-login-submit").assertTextContains("Увійти").performClick()
        scroll("auth-error")
        compose.onNodeWithTag("auth-error").assertTextContains("коректну адресу", substring = true)
        readLegal("privacy", "uk")
    }
}
