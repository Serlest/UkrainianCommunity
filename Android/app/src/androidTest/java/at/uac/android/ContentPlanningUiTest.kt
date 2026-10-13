package at.uac.android

import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performScrollToIndex
import at.uac.android.feature.contentplanning.*
import at.uac.android.feature.moderation.ModerationSession
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class ContentPlanningUiTest {
    @get:Rule val compose = createComposeRule()
    private val id = "a".repeat(40)
    private val time = Instant.parse("2026-09-07T12:00:00Z")
    private val draft =
        ContentPlanningDraft(
            id,
            3,
            "owner",
            ContentPlanningKind.NEWS,
            ContentPlanningState.ATTENTION,
            "Geprüfter Titel",
            mapOf(
                "title" to "Geprüfter Titel",
                "summary" to "Zusammenfassung",
                "body" to "Vollständiger Text",
                "sourceInput" to "https://example.org",
            ),
            listOf(ContentPlanningSource("https://example.org", "Primärquelle", true, time)),
            listOf("Mit der Primärquelle verglichen"),
            listOf("germanBody"),
            time,
            time,
            null,
            null,
            null,
            "Übersetzung fehlt",
            null,
            null,
            null,
            null,
            null,
            null,
        )

    private fun state(selected: ContentPlanningDraft? = null) =
        ContentPlanningUiState(
            session = ModerationSession("owner", 68, "owner", true),
            visible = true,
            selectedSection = ContentPlanningSection.ATTENTION,
            sections =
                ContentPlanningSection.entries.associateWith {
                    if (it == ContentPlanningSection.ATTENTION)
                        ContentPlanningSectionState(listOf(draft), loaded = true)
                    else ContentPlanningSectionState()
                },
            selected = selected,
        )

    @Test
    fun ownerListShowsFourSectionsAndConcreteMissingField() {
        compose.setContent { ContentPlanningContent(state(), "de") }
        compose.onNodeWithTag("content-planning-section-drafts").assertIsDisplayed()
        compose.onNodeWithTag("content-planning-section-scheduled").assertIsDisplayed()
        compose.onNodeWithTag("content-planning-section-attention").assertIsDisplayed()
        compose.onNodeWithTag("content-planning-sections").performScrollToIndex(3)
        compose.onNodeWithTag("content-planning-section-history").assertIsDisplayed()
        compose.onAllNodesWithText("Fehlt: Deutscher Text").assertCountEquals(1)
    }

    @Test
    fun unknownMissingFieldMessageIsPreserved() {
        val message = "Bitte den Veranstalter kontaktieren"
        compose.setContent {
            ContentPlanningContent(state(draft.copy(missingFields = listOf(message))), "de")
        }
        compose.onAllNodesWithText("• $message").assertCountEquals(1)
    }

    @Test
    fun ukrainianDetailExposesSourceNotesAndExplicitArchiveConfirmation() {
        var archived: ContentPlanningDraft? = null
        compose.setContent {
            ContentPlanningContent(
                state(draft),
                "uk",
                onArchive = { archived = it },
            )
        }
        compose.onNodeWithTag("content-planning-detail").assertIsDisplayed()
        compose.onNodeWithTag("content-planning-source-0").performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("content-planning-detail").performScrollToIndex(5)
        compose.onNodeWithTag("content-planning-archive").performClick()
        compose.onNodeWithTag("content-planning-confirm-archive").assertIsDisplayed().performClick()
        compose.runOnIdle { assertEquals(draft, archived) }
    }

    @Test
    fun uncertainMutationOffersReadOnlyReconciliation() {
        compose.setContent {
            ContentPlanningContent(
                state()
                    .copy(
                        recovery =
                            ContentPlanningRecovery(
                                id,
                                null,
                                null,
                                ContentPlanningRecoveryPhase.DELETE_UNCONFIRMED,
                            ),
                        error = ContentPlanningFailure.UNCONFIRMED,
                    ),
                "uk",
            )
        }
        compose.onNodeWithTag("content-planning-recovery").assertIsDisplayed()
        compose.onNodeWithTag("content-planning-reconcile").assertIsDisplayed()
    }

    @Test
    fun editorRequiresExplicitOrganizationChoice() {
        val ready = draft.copy(state = ContentPlanningState.READY, missingFields = emptyList())
        var selected: String? = null
        compose.setContent {
            ContentPlanningContent(
                state(ready)
                    .copy(
                        organizations =
                            listOf(ContentPlanningOrganization("org-1", "Organisation Eins"))
                    ),
                "de",
                onBegin = { _, organizationId -> selected = organizationId },
            )
        }
        compose.onNodeWithTag("content-planning-detail").performScrollToIndex(4)
        compose.onNodeWithTag("content-planning-review").assertIsNotEnabled()
        compose.onNodeWithTag("content-planning-organization-org-1").performClick()
        compose.onNodeWithTag("content-planning-review").assertIsEnabled().performClick()
        compose.runOnIdle { assertEquals("org-1", selected) }
    }
}
