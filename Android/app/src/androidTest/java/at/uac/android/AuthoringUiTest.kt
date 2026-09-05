package at.uac.android

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import at.uac.android.feature.authoring.*
import at.uac.android.feature.browse.*
import at.uac.android.feature.organization.*
import java.time.Instant
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class AuthoringUiTest {
    @get:Rule val compose = createComposeRule()
    private val actor = OrganizationSession("synthetic-author", 1, true, "Author", "user")
    private val basics =
        OrganizationDraft(
            "synthetic-author-org",
            "Synthetic Authoring Organization",
            "A complete synthetic description",
            region = "wien",
            city = "Wien",
        )
    private val now = Instant.parse("2026-09-03T02:00:00Z")

    private fun organization() =
        OrganizationContract.record(
            RawDocument(
                basics.id,
                OrganizationContract.create(basics, actor, now) +
                    mapOf("ownerId" to actor.uid, "moderationStatus" to "approved"),
            ),
            actor,
        )

    private fun state(
        status: AuthoringStatus = AuthoringStatus.APPROVED,
        editor: Boolean = false,
    ): AuthoringState {
        val org = organization()
        val draft =
            AuthoringContract.newDraft(ContentKind.NEWS, org, now)
                .copy(title = "Synthetic private draft", summary = "Summary", body = "Body")
        return AuthoringState(
            actor,
            org.id,
            true,
            status = status,
            hub = AuthoringHub(org, ContentKind.NEWS, status, AuthoringPage(emptyList(), null)),
            fresh = true,
            draft = draft.takeIf { editor },
            draftOrganization = org.takeIf { editor },
            editorFresh = editor,
            recoveryLoaded = true,
        )
    }

    @Test
    fun categoryLabelTogglesOnceAndPreservesTwoCategoryLimitAndFreshness() {
        var value by mutableStateOf(state(editor = true))
        var changes = 0
        val draft = requireNotNull(value.draft)
        val candidates =
            AuthoringContract.categories(draft.kind).filterNot { it == draft.category }.take(3)
        compose.setContent {
            MaterialTheme {
                AuthoringContent(
                    value,
                    "de",
                    AuthoringActions(
                        change = { transform ->
                            changes++
                            value = value.copy(draft = transform(requireNotNull(value.draft)))
                        }
                    ),
                )
            }
        }
        compose.onNodeWithTag("authoring-section-1").performScrollTo().performClick()
        fun clickLabel(category: String) {
            val label =
                compose
                    .onNodeWithTag("authoring-additional-category-$category")
                    .fetchSemanticsNode()
                    .config[SemanticsProperties.Text]
                    .single()
                    .text
            assertTrue(label.isNotBlank())
            compose.onNodeWithText(label, useUnmergedTree = true).performTouchInput { click() }
        }
        fun toggle(category: String) {
            val row = compose.onNodeWithTag("authoring-additional-category-$category")
            row.performScrollTo()
                .assertIsEnabled()
                .assertIsOff()
                .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Checkbox))
            clickLabel(category)
            row.assertIsOn()
        }
        toggle(candidates[0])
        compose.runOnIdle { assertEquals(1, changes) }
        toggle(candidates[1])
        compose.runOnIdle {
            assertEquals(2, changes)
            assertEquals(candidates.take(2).toSet(), value.draft?.additionalCategories)
        }
        compose
            .onNodeWithTag("authoring-additional-category-${candidates[2]}")
            .performScrollTo()
            .assertIsNotEnabled()
            .assertIsOff()
        clickLabel(candidates[2])
        compose.runOnIdle {
            assertEquals(2, changes)
            value = value.copy(fresh = false)
        }
        compose
            .onNodeWithTag("authoring-additional-category-${candidates[0]}")
            .performScrollTo()
            .assertIsNotEnabled()
            .assertIsOn()
        clickLabel(candidates[0])
        compose.runOnIdle { assertEquals(2, changes) }
    }

    @Test
    fun eventDateLabelsAreSingleAccessibleTogglesAtTwoHundredPercent() {
        var value by
            mutableStateOf(
                state(editor = true).let {
                    it.copy(
                        kind = ContentKind.EVENTS,
                        hub = requireNotNull(it.hub).copy(kind = ContentKind.EVENTS),
                        draft = AuthoringContract.newDraft(ContentKind.EVENTS, organization(), now),
                    )
                }
            )
        var changes = 0
        val occurrenceId = requireNotNull(value.draft).event.occurrences.single().id
        compose.setContent {
            CompositionLocalProvider(
                LocalDensity provides Density(LocalDensity.current.density, 2f)
            ) {
                MaterialTheme {
                    AuthoringContent(
                        value,
                        "uk",
                        AuthoringActions(
                            change = { transform ->
                                changes++
                                value = value.copy(draft = transform(requireNotNull(value.draft)))
                            }
                        ),
                    )
                }
            }
        }
        compose.onNodeWithTag("authoring-section-2").performScrollTo().performClick()
        val allDay = compose.onNodeWithTag("authoring-all-day-$occurrenceId")
        allDay
            .performScrollTo()
            .assertIsOff()
            .assertTextContains("Увесь день")
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Checkbox))
        assertTrue(allDay.getUnclippedBoundsInRoot().let { it.bottom - it.top } >= 48.dp)
        compose.onAllNodes(isToggleable()).assertCountEquals(2)
        compose.onNodeWithText("Увесь день", useUnmergedTree = true).performTouchInput { click() }
        allDay.assertIsOn()
        compose.runOnIdle {
            assertEquals(1, changes)
            assertTrue(requireNotNull(value.draft).event.occurrences.single().allDay)
        }
        val end = compose.onNodeWithTag("authoring-end-known-$occurrenceId")
        end.performScrollTo().assertIsOn().assertTextContains("Час завершення відомий")
        assertTrue(end.getUnclippedBoundsInRoot().let { it.bottom - it.top } >= 48.dp)
        compose.onNodeWithText("Час завершення відомий", useUnmergedTree = true).performTouchInput {
            click()
        }
        end.assertIsOff()
        compose.runOnIdle {
            assertEquals(2, changes)
            value = value.copy(fresh = false)
        }
        end.assertIsNotEnabled()
        compose.onNodeWithText("Час завершення відомий", useUnmergedTree = true).performTouchInput {
            click()
        }
        compose.runOnIdle { assertEquals(2, changes) }
    }

    @Test
    fun guestCannotSeePrivateDraftOrWriteControls() {
        compose.setContent {
            MaterialTheme { AuthoringContent(AuthoringState(), "de", AuthoringActions()) }
        }
        compose.onNodeWithTag("authoring-account").assertIsDisplayed()
        compose.onNodeWithTag("authoring-create").assertDoesNotExist()
        compose.onNodeWithText("Synthetic private draft").assertDoesNotExist()
    }

    @Test
    fun freshOrganizationHasCreateAndExplicitStatusControl() {
        var created = false
        compose.setContent {
            MaterialTheme {
                AuthoringContent(state(), "de", AuthoringActions(create = { created = true }))
            }
        }
        compose.onNodeWithTag("authoring-create").performScrollTo().assertIsEnabled().performClick()
        assertTrue(created)
        compose.onNodeWithTag("authoring-kind-events").assertExists()
    }

    @Test
    fun staleDraftPreservesTextButDisablesMutation() {
        compose.setContent {
            MaterialTheme {
                AuthoringContent(state(editor = true).copy(fresh = false), "uk", AuthoringActions())
            }
        }
        compose
            .onNodeWithTag("authoring-title")
            .assertTextContains("Synthetic private draft")
            .assertIsNotEnabled()
        compose.onNodeWithTag("authoring-readonly").performScrollTo().assertExists()
        compose.onNodeWithTag("authoring-submit").performScrollTo().assertIsNotEnabled()
    }

    @Test
    fun austriaSubmissionLabelsModerationNotImmediatePublication() {
        val value =
            state(editor = true).let { it.copy(draft = it.draft!!.copy(regionScope = "austria")) }
        compose.setContent { MaterialTheme { AuthoringContent(value, "de", AuthoringActions()) } }
        compose
            .onNodeWithTag("authoring-submit")
            .performScrollTo()
            .assertTextContains("Zur Prüfung einreichen")
        compose.onNodeWithText("Jetzt veröffentlichen").assertDoesNotExist()
    }

    @Test
    fun scheduledServerDraftHasNoEditOrPublishAction() {
        val value = state(AuthoringStatus.SCHEDULED)
        val fields =
            AuthoringContract.submission(
                    AuthoringContract.newDraft(ContentKind.NEWS, organization(), now)
                        .copy(title = "Planned", summary = "Summary", body = "Body"),
                    organization(),
                    actor,
                    null,
                    now,
                )
                .fields +
                mapOf("moderationStatus" to "draft", "scheduledAt" to now.plusSeconds(600))
        val item =
            AuthoringContract.item(
                ContentKind.NEWS,
                RawDocument(fields["id"] as String, fields),
                basics.id,
                AuthoringStatus.SCHEDULED,
                actor,
            )
        compose.setContent {
            MaterialTheme {
                AuthoringContent(
                    value.copy(hub = value.hub!!.copy(page = AuthoringPage(listOf(item), null))),
                    "de",
                    AuthoringActions(),
                )
            }
        }
        compose.onNodeWithTag("authoring-scheduled-readonly").performScrollTo().assertExists()
        compose.onNodeWithTag("authoring-edit-${item.id}").assertDoesNotExist()
        compose.onNodeWithTag("authoring-submit").assertDoesNotExist()
    }

    @Test
    fun publishingRequiresProtectedExplicitConfirmation() {
        val value = state(editor = true)
        val intent = AuthoringContract.submission(value.draft!!, organization(), actor, null, now)
        var confirmed = false
        compose.setContent {
            MaterialTheme {
                AuthoringContent(
                    value.copy(confirmation = intent),
                    "de",
                    AuthoringActions(confirm = { confirmed = true }),
                )
            }
        }
        assertFalse(confirmed)
        compose.onNodeWithTag("authoring-confirm").assertIsDisplayed().performClick()
        assertTrue(confirmed)
    }

    @Test
    fun unconfirmedOutcomeNeverOffersUnverifiedRepeat() {
        val value = state(editor = true)
        val intent = AuthoringContract.submission(value.draft!!, organization(), actor, null, now)
        compose.setContent {
            MaterialTheme {
                AuthoringContent(value.copy(uncertain = intent), "uk", AuthoringActions())
            }
        }
        compose.onNodeWithTag("authoring-submit").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithTag("authoring-recover").performScrollTo().assertIsEnabled()
        compose.onNodeWithTag("authoring-retry-same").assertDoesNotExist()
    }

    @Test
    fun localPreviewExplicitlyStatesNoPublication() {
        compose.setContent {
            MaterialTheme {
                AuthoringContent(
                    state(editor = true).copy(preview = true),
                    "de",
                    AuthoringActions(),
                )
            }
        }
        compose.onNodeWithText("Lokale Vorschau · nicht gesendet").assertIsDisplayed()
        compose
            .onAllNodesWithText("Synthetic private draft", useUnmergedTree = true)
            .onLast()
            .assertIsDisplayed()
    }

    @Test
    fun eventParticipationSectionRemainsReachableAtTwoHundredPercentText() {
        val value =
            state(editor = true).let {
                it.copy(
                    kind = ContentKind.EVENTS,
                    hub = it.hub!!.copy(kind = ContentKind.EVENTS),
                    draft = AuthoringContract.newDraft(ContentKind.EVENTS, organization(), now),
                )
            }
        compose.setContent {
            CompositionLocalProvider(
                LocalDensity provides Density(LocalDensity.current.density, 2f)
            ) {
                MaterialTheme { AuthoringContent(value, "de", AuthoringActions()) }
            }
        }
        compose
            .onNodeWithTag("authoring-section-3")
            .performScrollTo()
            .assertIsDisplayed()
            .assertIsEnabled()
            .performClick()
            .assertIsSelected()
        compose
            .onNodeWithTag("authoring-capacity")
            .performScrollTo()
            .assertIsDisplayed()
            .assertIsEnabled()
        compose
            .onNodeWithTag("authoring-section-2")
            .performScrollTo()
            .assertIsDisplayed()
            .performClick()
            .assertIsSelected()
        compose.onNodeWithTag("authoring-venue").performScrollTo().assertIsDisplayed()
    }
}
