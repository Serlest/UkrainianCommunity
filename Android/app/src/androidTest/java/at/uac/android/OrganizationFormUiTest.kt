package at.uac.android

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import at.uac.android.feature.auth.AuthLegalDocument
import at.uac.android.feature.organization.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class OrganizationFormUiTest {
    @get:Rule val compose = createComposeRule()

    private fun assertFieldIssue(tag: String, message: String) {
        // TextField deliberately merges its supporting text into its accessible field node.
        compose
            .onNodeWithTag(tag)
            .assertTextContains(message)
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Error, message))
        compose.onAllNodesWithTag("$tag-issue", useUnmergedTree = true).assertCountEquals(1)
        compose.onNodeWithTag("$tag-issue", useUnmergedTree = true).assertTextEquals(message)
    }

    private fun assertFieldIssueCleared(tag: String) {
        compose.onNodeWithTag("$tag-issue", useUnmergedTree = true).assertDoesNotExist()
        compose.onNodeWithTag(tag).assert(!SemanticsMatcher.keyIsDefined(SemanticsProperties.Error))
    }

    private val actor = OrganizationSession("synthetic-form-ui", 1, true, "Synthetic", "user")
    private val rules =
        AuthLegalDocument(
            "organizationRules",
            "synthetic-form-version",
            true,
            mapOf("de" to "Organisationsregeln", "uk" to "Правила організацій"),
            mapOf("de" to "Synthetic legal text"),
        )
    private val draft =
        OrganizationDraft(
            "synthetic-form-ui-org",
            "Synthetic Form",
            "A complete synthetic description",
            region = "wien",
            city = "Wien",
            acceptedRulesVersion = rules.version,
        )

    private fun initial(d: OrganizationDraft = draft) =
        OrganizationState(
            actor,
            hub = OrganizationHub(emptyList(), emptyList()),
            rules = rules,
            draft = d,
        )

    @Composable
    private fun Content(
        state: OrganizationState,
        language: String = "de",
        change: ((OrganizationDraft) -> OrganizationDraft) -> Unit = {},
        consent: (Boolean) -> Unit = {},
        submit: () -> Unit = {},
    ) {
        MaterialTheme {
            OrganizationContent(
                state,
                language,
                {},
                {},
                {},
                {},
                {},
                {},
                change,
                consent,
                {},
                {},
                {},
                submit,
                {},
            )
        }
    }

    @Test
    fun consentTextIsOneLabelledToggleAndTapDispatchesOnce() {
        var state by mutableStateOf(initial(draft.copy(acceptedRulesVersion = null)))
        var calls = 0
        val text = "Я прочитав(-ла) ці правила організацій і погоджуюся з ними для цієї заявки."
        compose.setContent {
            CompositionLocalProvider(
                LocalDensity provides Density(LocalDensity.current.density, 2f)
            ) {
                Content(
                    state,
                    "uk",
                    consent = { checked ->
                        calls++
                        state =
                            state.copy(
                                draft =
                                    requireNotNull(state.draft)
                                        .copy(
                                            acceptedRulesVersion =
                                                if (checked) rules.version else null
                                        )
                            )
                    },
                )
            }
        }
        val row = compose.onNodeWithTag("organization-consent")
        row.performScrollTo()
            .assertIsOff()
            .assertTextContains(text)
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Checkbox))
        assertTrue(row.getUnclippedBoundsInRoot().let { it.bottom - it.top } >= 48.dp)
        compose.onAllNodes(isToggleable()).assertCountEquals(1)
        compose.onNodeWithText(text, useUnmergedTree = true).performTouchInput { click() }
        row.assertIsOn()
        compose.runOnIdle {
            assertEquals(1, calls)
            state = state.copy(busy = true)
        }
        row.assertIsNotEnabled()
        compose.onNodeWithText(text, useUnmergedTree = true).performTouchInput { click() }
        compose.runOnIdle {
            assertEquals(1, calls)
            state = state.copy(busy = false, editorFailure = OrganizationFailure.STALE)
        }
        row.assertIsNotEnabled()
        compose.onNodeWithTag("organization-submit").performScrollTo().assertIsNotEnabled()
    }

    @Test
    fun translatedChoicesDisplayLabelsButWriteOnlyCanonicalKeysAtLargeText() {
        var state by mutableStateOf(initial())
        var language by mutableStateOf("uk")
        compose.setContent {
            CompositionLocalProvider(
                LocalDensity provides Density(LocalDensity.current.density, 2f)
            ) {
                Content(
                    state,
                    language,
                    change = { transform ->
                        state = state.copy(draft = transform(requireNotNull(state.draft)))
                    },
                )
            }
        }
        compose
            .onNodeWithTag("organization-region")
            .performScrollTo()
            .assertTextContains("Федеральна земля: Відень")
            .performClick()
        compose
            .onNodeWithTag("organization-region-niederoesterreich")
            .performScrollTo()
            .assertTextContains("Нижня Австрія")
            .performClick()
        compose.runOnIdle {
            assertEquals("niederoesterreich", state.draft?.region)
            language = "de"
        }
        compose
            .onNodeWithTag("organization-region")
            .assertTextContains("Bundesland: Niederösterreich")
        compose.onNodeWithTag("organization-profile-kind").performScrollTo().performClick()
        compose
            .onNodeWithTag("organization-profile-kind-mediaProject")
            .performScrollTo()
            .assertTextContains("Medienprojekt")
            .performClick()
        compose.runOnIdle {
            assertEquals("mediaProject", state.draft?.profileKind)
            language = "uk"
        }
        compose
            .onNodeWithTag("organization-profile-kind")
            .assertTextContains("Тип профілю: Медіапроєкт")
        compose.onNodeWithText("mediaProject").assertDoesNotExist()
        compose.onNodeWithText("niederoesterreich").assertDoesNotExist()
    }

    @Test
    fun invalidEmailAndWebsiteExplainDisabledSubmitAndCorrectionRestoresIt() {
        var state by mutableStateOf(initial())
        var submits = 0
        compose.setContent {
            Content(
                state,
                change = { transform ->
                    state = state.copy(draft = transform(requireNotNull(state.draft)))
                },
                submit = { submits++ },
            )
        }
        compose
            .onNodeWithTag("organization-email")
            .performScrollTo()
            .performTextReplacement("bad-email")
        assertFieldIssue(
            "organization-email",
            "E-Mail: @, keine Leerzeichen und höchstens 320 Zeichen; oder leer lassen.",
        )
        compose
            .onNodeWithTag("organization-submit-reason")
            .performScrollTo()
            .assertIsDisplayed()
            .assertTextContains("E-Mail:", substring = true)
        compose.onNodeWithTag("organization-submit").performScrollTo().assertIsNotEnabled()
        compose
            .onNodeWithTag("organization-email")
            .performScrollTo()
            .performTextReplacement("user@example.invalid")
        assertFieldIssueCleared("organization-email")
        compose
            .onNodeWithTag("organization-website")
            .performScrollTo()
            .performTextReplacement("file:///tmp/photo")
        assertFieldIssue(
            "organization-website",
            "Website: eine gültige HTTP-/HTTPS-Adresse ohne Leerzeichen oder Anmeldedaten eingeben; oder leer lassen.",
        )
        compose.onNodeWithTag("organization-submit").performScrollTo().assertIsNotEnabled()
        compose
            .onNodeWithTag("organization-website")
            .performScrollTo()
            .performTextReplacement("example.invalid")
        assertFieldIssueCleared("organization-website")
        compose.onNodeWithTag("organization-submit-reason").assertDoesNotExist()
        compose
            .onNodeWithTag("organization-submit")
            .performScrollTo()
            .assertIsEnabled()
            .performClick()
        compose.runOnIdle { assertEquals(1, submits) }
    }

    @Test
    fun changedEmptyAndOverLimitNameRemainExplainedAtTwoHundredPercent() {
        var state by mutableStateOf(initial())
        compose.setContent {
            CompositionLocalProvider(
                LocalDensity provides Density(LocalDensity.current.density, 2f)
            ) {
                Content(
                    state,
                    "uk",
                    change = { transform ->
                        state = state.copy(draft = transform(requireNotNull(state.draft)))
                    },
                )
            }
        }
        compose.onNodeWithTag("organization-name").performScrollTo().performTextReplacement("")
        assertFieldIssue("organization-name", "Назва: введіть 1–180 символів.")
        compose.onNodeWithTag("organization-name").performTextReplacement("x".repeat(181))
        assertFieldIssue("organization-name", "Назва: введіть 1–180 символів.")
        compose
            .onNodeWithTag("organization-submit-reason")
            .performScrollTo()
            .assertIsDisplayed()
            .assertTextContains("Назва: введіть 1–180 символів.")
        compose.onNodeWithTag("organization-submit").performScrollTo().assertIsNotEnabled()
        compose
            .onNodeWithTag("organization-name")
            .performScrollTo()
            .performTextReplacement("Synthetic corrected")
        assertFieldIssueCleared("organization-name")
        compose.onNodeWithTag("organization-submit").performScrollTo().assertIsEnabled()
    }

    @Test
    fun validationReasonDoesNotReplaceConsentBusyOrAuthorityState() {
        var state by
            mutableStateOf(initial(draft.copy(email = "bad-email", acceptedRulesVersion = null)))
        compose.setContent { Content(state) }
        compose.onNodeWithTag("organization-submit-reason").assertDoesNotExist()
        compose.runOnIdle {
            state =
                state.copy(
                    draft = requireNotNull(state.draft).copy(acceptedRulesVersion = rules.version)
                )
        }
        compose.onNodeWithTag("organization-submit-reason").performScrollTo().assertExists()
        compose.runOnIdle { state = state.copy(busy = true) }
        compose.onNodeWithTag("organization-submit-reason").assertDoesNotExist()
        compose.runOnIdle {
            state = state.copy(busy = false, editorFailure = OrganizationFailure.STALE)
        }
        compose.onNodeWithTag("organization-submit-reason").assertDoesNotExist()
        compose.onNodeWithTag("organization-editor-readonly").performScrollTo().assertExists()
        compose.runOnIdle { state = state.copy(session = actor.copy(ready = false)) }
        compose.onNodeWithTag("organization-submit").assertDoesNotExist()
        compose.onNodeWithTag("organization-email").assertDoesNotExist()
    }

    @Test
    fun unknownChoiceIsVisibleErrorAndNeverAutomaticallyRewritten() {
        val state = initial(draft.copy(region = "unknown", profileKind = "unknown"))
        var changes = 0
        compose.setContent { Content(state, change = { changes++ }) }
        compose
            .onNodeWithTag("organization-region")
            .performScrollTo()
            .assertTextContains("Bundesland: Ungültige Auswahl")
        compose.onNodeWithTag("organization-region-issue").assertExists()
        compose
            .onNodeWithTag("organization-profile-kind")
            .performScrollTo()
            .assertTextContains("Profilart: Ungültige Auswahl")
        compose.onNodeWithTag("organization-profile-kind-issue").assertExists()
        compose.runOnIdle {
            assertEquals(0, changes)
            assertEquals("unknown", state.draft?.region)
        }
        compose.onNodeWithTag("organization-submit").performScrollTo().assertIsNotEnabled()
    }
}
