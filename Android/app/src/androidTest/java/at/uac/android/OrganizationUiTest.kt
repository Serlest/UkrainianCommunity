package at.uac.android

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import at.uac.android.feature.auth.AuthLegalDocument
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.organization.*
import java.time.Instant
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class OrganizationUiTest {
    @get:Rule val compose = createComposeRule()
    private val session = OrganizationSession("synthetic-ui", 1, true, "Test", "user")
    private val rules =
        AuthLegalDocument(
            "organizationRules",
            "existing-ui",
            true,
            mapOf("de" to "Organisationsregeln"),
            mapOf("de" to "Existing synthetic legal text"),
        )
    private val draft =
        OrganizationDraft(
            "synthetic-ui-org",
            "Synthetic Community",
            "A sufficiently long description",
            region = "wien",
            city = "Wien",
        )

    private fun record(status: String = "pendingReview") =
        OrganizationContract.record(
            RawDocument(
                draft.id,
                OrganizationContract.create(draft, session, Instant.now()) +
                    ("moderationStatus" to status),
            ),
            session,
        )

    @Composable
    private fun Content(
        state: OrganizationState,
        consent: (Boolean) -> Unit = {},
        submit: () -> Unit = {},
        discard: (OrganizationRecord) -> Unit = {},
    ) {
        MaterialTheme {
            OrganizationContent(
                state,
                "de",
                {},
                {},
                {},
                {},
                {},
                {},
                {},
                consent,
                {},
                {},
                {},
                submit,
                discard,
            )
        }
    }

    @Test
    fun guestCannotSeePrivateRequestsOrMutationControls() {
        compose.setContent { Content(OrganizationState()) }
        compose.onNodeWithTag("organization-account").assertIsDisplayed()
        compose.onNodeWithTag("organization-create").assertDoesNotExist()
        compose.onNodeWithTag("organization-submit").assertDoesNotExist()
    }

    @Test
    fun validFormStillRequiresExplicitCurrentVersionConsentAndBusyDisablesSubmit() {
        var state by
            mutableStateOf(
                OrganizationState(
                    session,
                    hub = OrganizationHub(emptyList(), emptyList()),
                    rules = rules,
                    draft = draft,
                )
            )
        var submits = 0
        compose.setContent {
            Content(
                state,
                consent = {
                    state =
                        state.copy(
                            draft =
                                draft.copy(acceptedRulesVersion = if (it) rules.version else null)
                        )
                },
                submit = {
                    submits++
                    state = state.copy(busy = true)
                },
            )
        }
        compose.onNodeWithTag("organization-submit").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithTag("organization-consent").performScrollTo().performClick()
        compose
            .onNodeWithTag("organization-submit")
            .performScrollTo()
            .assertIsEnabled()
            .performClick()
        compose.onNodeWithTag("organization-submit").assertIsNotEnabled()
        compose.runOnIdle { assertEquals(1, submits) }
    }

    @Test
    fun discardRequiresConfirmationAndRetainsSubmitterScope() {
        val row = record("needsRevision")
        var deleted = 0
        compose.setContent {
            Content(
                OrganizationState(session, hub = OrganizationHub(listOf(row), emptyList())),
                discard = { deleted++ },
            )
        }
        compose.onNodeWithTag("organization-discard-${row.id}").performScrollTo().performClick()
        compose.runOnIdle { assertEquals(0, deleted) }
        compose.onNodeWithTag("organization-confirm-discard").assertIsDisplayed().performClick()
        compose.runOnIdle { assertEquals(1, deleted) }
    }

    @Test
    fun ownerDoesNotReceiveBroadDeleteActionAndPartialLogoIsHonest() {
        val owner = session.copy(globalRole = "owner")
        val row = record()
        compose.setContent {
            Content(
                OrganizationState(
                    owner,
                    hub = OrganizationHub(listOf(row), emptyList()),
                    rules = rules,
                    draft = draft,
                    base = row,
                    confirmedId = row.id,
                    logoIncomplete = true,
                )
            )
        }
        compose.onNodeWithTag("organization-discard-${row.id}").assertDoesNotExist()
        compose
            .onNodeWithText(
                "Der Antrag ist gespeichert, das Logo aber noch nicht bestätigt.",
                substring = true,
            )
            .performScrollTo()
            .assertIsDisplayed()
        compose.onNodeWithTag("organization-confirmed").performScrollTo().assertIsDisplayed()
    }

    @Test
    fun staleServerRequestKeepsInputsVisibleButDisablesEditingAndSubmit() {
        compose.setContent {
            Content(
                OrganizationState(
                    session,
                    hub = OrganizationHub(emptyList(), emptyList()),
                    rules = rules,
                    draft = draft,
                    base = record(),
                    editorFailure = OrganizationFailure.STALE,
                )
            )
        }
        compose.onNodeWithTag("organization-editor-readonly").performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("organization-name").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithTag("organization-logo").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithTag("organization-submit").performScrollTo().assertIsNotEnabled()
    }

    @Test
    fun approvedNotificationTargetHasPublicReadOnlyActionWithoutEditor() {
        val approved = record("approved")
        compose.setContent {
            Content(
                OrganizationState(
                    session,
                    hub = OrganizationHub(emptyList(), emptyList()),
                    targetId = approved.id,
                    target = approved,
                )
            )
        }
        compose.onNodeWithTag("organization-target-approved").performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("organization-target-public").performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("organization-target-edit").assertDoesNotExist()
        compose.onNodeWithTag("organization-submit").assertDoesNotExist()
    }

    @Test
    fun missingNotificationTargetIsExplicitlyUnavailable() {
        compose.setContent {
            Content(
                OrganizationState(
                    session,
                    hub = OrganizationHub(emptyList(), emptyList()),
                    targetId = "removed-request",
                    targetFailure = OrganizationFailure.MISSING,
                )
            )
        }
        compose
            .onNodeWithTag("organization-target-unavailable")
            .performScrollTo()
            .assertIsDisplayed()
        compose.onNodeWithTag("organization-target-edit").assertDoesNotExist()
        compose.onNodeWithTag("organization-target-public").assertDoesNotExist()
    }
}
