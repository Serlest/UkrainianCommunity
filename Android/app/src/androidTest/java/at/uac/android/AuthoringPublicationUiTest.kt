package at.uac.android

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import at.uac.android.feature.authoring.*
import at.uac.android.feature.browse.*
import at.uac.android.feature.organization.*
import java.time.Instant
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class AuthoringPublicationUiTest {
    @get:Rule val compose = createComposeRule()
    private val actor = OrganizationSession("ui-scheduled-author", 1, true, "Author", "user")
    private val now = Instant.now()
    private val org
        get() =
            OrganizationDraft(
                    "ui-scheduled-org",
                    "Scheduled organization",
                    "Complete synthetic description",
                    region = "wien",
                    city = "Wien",
                )
                .let {
                    OrganizationContract.record(
                        RawDocument(
                            it.id,
                            OrganizationContract.create(it, actor, now) +
                                mapOf("ownerId" to actor.uid, "moderationStatus" to "approved"),
                        ),
                        actor,
                    )
                }

    private val draft
        get() =
            AuthoringContract.newDraft(ContentKind.NEWS, org, now)
                .copy(title = "Scheduled UI title", summary = "Summary", body = "Body")

    private fun state() =
        AuthoringState(
            actor,
            org.id,
            true,
            hub =
                AuthoringHub(
                    org,
                    ContentKind.NEWS,
                    AuthoringStatus.APPROVED,
                    AuthoringPage(emptyList(), null),
                ),
            fresh = true,
            recoveryLoaded = true,
            draft = draft,
            draftOrganization = org,
            editorFresh = true,
            draftZoneId = "Europe/Vienna",
        )

    private fun scheduled() =
        draft.copy(
            publicationMode = AuthoringPublicationMode.SCHEDULED,
            scheduledAt = now.plusSeconds(3_600),
        )

    private fun intent() = AuthoringContract.submission(scheduled(), org, actor, null, now)

    @Test
    fun newFormDefaultsToNowAndChangingModeDoesNotSend() {
        var value by mutableStateOf(state())
        var sends = 0
        compose.setContent {
            MaterialTheme {
                AuthoringContent(
                    value,
                    "de",
                    AuthoringActions(
                        change = { value = value.copy(draft = it(requireNotNull(value.draft))) },
                        submit = { sends++ },
                    ),
                )
            }
        }
        compose.onNodeWithTag("authoring-publication-now").performScrollTo().assertIsSelected()
        compose
            .onNodeWithTag("authoring-publication-scheduled")
            .performScrollTo()
            .assertIsEnabled()
            .performClick()
        compose
            .onNodeWithTag("authoring-publication-zone")
            .performScrollTo()
            .assertTextContains("Europe/Vienna", substring = true)
        compose
            .onNodeWithTag("authoring-submit")
            .performScrollTo()
            .assertIsEnabled()
            .assertTextContains("Veröffentlichung planen")
        assertEquals(0, sends)
        assertNotNull(value.draft?.scheduledAt)
    }

    @Test
    fun staleScheduleDisablesSubmitButDateCanStillBeCorrectedExplicitly() {
        compose.setContent {
            MaterialTheme {
                AuthoringContent(
                    state().copy(draft = scheduled().copy(scheduledAt = now)),
                    "uk",
                    AuthoringActions(),
                )
            }
        }
        compose.onNodeWithTag("authoring-submit").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithTag("authoring-preview").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithTag("authoring-publication-date").performScrollTo().assertIsEnabled()
        compose
            .onNodeWithTag("authoring-schedule-validation")
            .performScrollTo()
            .assertTextContains("п’ять хвилин", substring = true)
    }

    @Test
    fun editingExistingContentNeverOffersPublicationTiming() {
        val d = draft
        val value = AuthoringContract.submission(d, org, actor, null, now)
        val item =
            AuthoringContract.item(
                value.kind,
                RawDocument(value.id, value.fields),
                org.id,
                AuthoringStatus.APPROVED,
                actor,
            )
        compose.setContent {
            MaterialTheme {
                AuthoringContent(state().copy(draft = d, base = item), "de", AuthoringActions())
            }
        }
        compose.onNodeWithTag("authoring-publication-now").assertDoesNotExist()
        compose.onNodeWithTag("authoring-publication-scheduled").assertDoesNotExist()
        compose
            .onNodeWithTag("authoring-submit")
            .performScrollTo()
            .assertTextContains("Änderungen speichern")
    }

    @Test
    fun scheduleConfirmationNamesTimeZoneAndDoesNotClaimPublished() {
        var confirmed = false
        compose.setContent {
            MaterialTheme {
                AuthoringContent(
                    state().copy(draft = scheduled(), confirmation = intent()),
                    "de",
                    AuthoringActions(confirm = { confirmed = true }),
                )
            }
        }
        compose.onNodeWithText("Ein geplanter Server-Entwurf", substring = true).assertExists()
        compose
            .onAllNodesWithText("Europe/Vienna", substring = true)
            .filterToOne(hasAnyAncestor(isDialog()))
            .assertExists()
        assertFalse(confirmed)
        compose.onNodeWithTag("authoring-confirm").assertIsEnabled().performClick()
        assertTrue(confirmed)
    }

    @Test
    fun expiredConfirmationCannotBeSentAfterTimePasses() {
        val value = intent().let { it.copy(fields = it.fields + ("scheduledAt" to now)) }
        compose.setContent {
            MaterialTheme {
                AuthoringContent(
                    state().copy(draft = scheduled(), confirmation = value),
                    "uk",
                    AuthoringActions(),
                )
            }
        }
        compose.onNodeWithTag("authoring-confirm").assertIsNotEnabled()
    }

    @Test
    fun expiredPendingRetainsReadOnlyRecoveryAndNeverOffersNewId() {
        val value =
            intent().let { it.copy(fields = it.fields + ("scheduledAt" to now.minusSeconds(1))) }
        compose.setContent {
            MaterialTheme {
                AuthoringContent(
                    state().copy(draft = null, uncertain = value, recoveryChecked = true),
                    "de",
                    AuthoringActions(),
                )
            }
        }
        compose.onNodeWithTag("authoring-expired-pending").performScrollTo().assertExists()
        compose.onNodeWithTag("authoring-retry-same").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithTag("authoring-recover").performScrollTo().assertIsEnabled()
        compose.onNodeWithTag("authoring-create").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithTag("authoring-discard-local").assertDoesNotExist()
    }

    @Test
    fun confirmedScheduledItemHasNoEditCoverOrLifecycleAction() {
        val value = intent()
        val item =
            AuthoringContract.item(
                value.kind,
                RawDocument(value.id, value.fields),
                org.id,
                AuthoringStatus.SCHEDULED,
                actor,
            )
        compose.setContent {
            MaterialTheme {
                AuthoringContent(
                    state()
                        .copy(
                            draft = null,
                            confirmed = item,
                            status = AuthoringStatus.SCHEDULED,
                            hub =
                                AuthoringHub(
                                    org,
                                    ContentKind.NEWS,
                                    AuthoringStatus.SCHEDULED,
                                    AuthoringPage(listOf(item), null),
                                ),
                        ),
                    "uk",
                    AuthoringActions(cover = {}, lifecycle = {}),
                )
            }
        }
        compose.onNodeWithTag("authoring-confirmed").performScrollTo().assertExists()
        compose.onNodeWithTag("authoring-edit-${item.id}").assertDoesNotExist()
        compose.onNodeWithTag("authoring-cover-${item.id}").assertDoesNotExist()
        compose.onNodeWithTag("authoring-lifecycle-${item.id}").assertDoesNotExist()
    }

    @Test
    fun unverifiedSessionDoesNotExposeSavedPublicationTime() {
        compose.setContent {
            MaterialTheme {
                AuthoringContent(
                    state().copy(session = actor.copy(ready = false), draft = scheduled()),
                    "de",
                    AuthoringActions(),
                )
            }
        }
        compose.onNodeWithTag("authoring-account").assertExists()
        compose.onNodeWithTag("authoring-publication-date").assertDoesNotExist()
        compose.onNodeWithText("Scheduled UI title").assertDoesNotExist()
    }
}
