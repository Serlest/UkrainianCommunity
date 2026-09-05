package at.uac.android

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import at.uac.android.feature.authoring.*
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.contentlifecycle.*
import at.uac.android.feature.organization.*
import java.time.Instant
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class ContentLifecycleUiTest {
    @get:Rule val compose = createComposeRule()
    private val actor = OrganizationSession("lifecycle-ui-owner", 1, true, "Owner", "user")
    private val now = Instant.parse("2026-09-03T03:00:00Z")

    private fun snapshot(kind: ContentKind = ContentKind.NEWS): ContentLifecycleSnapshot {
        val draft =
            OrganizationDraft(
                "lifecycle-ui-org",
                "Lifecycle organization",
                "A synthetic organization",
                region = "wien",
                city = "Wien",
            )
        val org =
            OrganizationContract.record(
                RawDocument(
                    draft.id,
                    OrganizationContract.create(draft, actor, now) +
                        mapOf("ownerId" to actor.uid, "moderationStatus" to "approved"),
                ),
                actor,
            )
        val content =
            AuthoringContract.newDraft(kind, org, now)
                .copy(
                    id = "lifecycle-ui-content",
                    title = "Private lifecycle title",
                    summary = "Summary",
                    body = "Body",
                )
                .let {
                    if (kind == ContentKind.EVENTS) it.copy(event = it.event.copy(venue = "Hall"))
                    else it
                }
        val item =
            AuthoringContract.item(
                kind,
                RawDocument(
                    content.id,
                    AuthoringContract.submission(content, org, actor, null, now).fields,
                ),
                org.id,
                AuthoringStatus.APPROVED,
                actor,
            )
        return ContentLifecycleSnapshot(ContentLifecycleTarget(org.id, kind, item.id), org, item)
    }

    private fun state(value: ContentLifecycleSnapshot = snapshot()) =
        ContentLifecycleState(actor, value.target, true, value, true)

    @Test
    fun guestCannotSeePriorContentOrActions() {
        compose.setContent {
            MaterialTheme {
                ContentLifecycleContent(
                    state().copy(session = null),
                    "de",
                    ContentLifecycleActions(),
                )
            }
        }
        compose.onNodeWithTag("content-lifecycle-account").assertIsDisplayed()
        compose.onNodeWithText("Private lifecycle title").assertDoesNotExist()
        compose.onNodeWithTag("content-lifecycle-request").assertDoesNotExist()
    }

    @Test
    fun initialRequestDoesNotExecuteWithoutProtectedConfirmation() {
        var requested = false
        var sent = false
        compose.setContent {
            MaterialTheme {
                ContentLifecycleContent(
                    state(),
                    "de",
                    ContentLifecycleActions(
                        request = { requested = true },
                        confirm = { sent = true },
                    ),
                )
            }
        }
        compose
            .onNodeWithTag("content-lifecycle-request")
            .performScrollTo()
            .assertIsEnabled()
            .performClick()
        assertTrue(requested)
        assertFalse(sent)
        compose.onNodeWithTag("content-lifecycle-confirm").assertDoesNotExist()
    }

    @Test
    fun staleConfirmationCannotExecute() {
        val value = state()
        var sent = false
        compose.setContent {
            MaterialTheme {
                ContentLifecycleContent(
                    value.copy(
                        fresh = false,
                        confirmation = ContentLifecycleIntent(requireNotNull(value.snapshot)),
                    ),
                    "de",
                    ContentLifecycleActions(confirm = { sent = true }),
                )
            }
        }
        compose.onNodeWithTag("content-lifecycle-confirm").assertIsDisplayed().assertIsNotEnabled()
        assertFalse(sent)
    }

    @Test
    fun uncertainDeletionOffersReadOnlyCheckAndNoEnabledReplay() {
        val value = state()
        compose.setContent {
            MaterialTheme {
                ContentLifecycleContent(
                    value.copy(
                        uncertain = ContentLifecycleIntent(requireNotNull(value.snapshot)),
                        observed = ContentLifecycleObserved.UNAVAILABLE_CLEANUP_UNCONFIRMED,
                    ),
                    "de",
                    ContentLifecycleActions(),
                )
            }
        }
        compose.onNodeWithTag("content-lifecycle-recover").performScrollTo().assertIsEnabled()
        compose
            .onNodeWithTag("content-lifecycle-observed")
            .performScrollTo()
            .assertTextContains("vollständige Bereinigung bleibt unbestätigt", substring = true)
        compose.onNodeWithTag("content-lifecycle-request").performScrollTo().assertIsNotEnabled()
    }

    @Test
    fun missingTargetDoesNotPretendAnOldRequestSucceeded() {
        compose.setContent {
            MaterialTheme {
                ContentLifecycleContent(
                    state(snapshot().copy(item = null)),
                    "uk",
                    ContentLifecycleActions(),
                )
            }
        }
        compose.onNodeWithTag("content-lifecycle-missing").performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("content-lifecycle-confirmed").assertDoesNotExist()
        compose.onNodeWithTag("content-lifecycle-request").performScrollTo().assertIsNotEnabled()
    }

    @Test
    fun eventExplainsBothServerBranchesInsteadOfTrustingCounter() {
        compose.setContent {
            MaterialTheme {
                ContentLifecycleContent(
                    state(snapshot(ContentKind.EVENTS)),
                    "de",
                    ContentLifecycleActions(),
                )
            }
        }
        compose
            .onNodeWithText("Ohne Anmeldungen wird die Veranstaltung gelöscht", substring = true)
            .performScrollTo()
            .assertIsDisplayed()
        compose.onNodeWithTag("content-lifecycle-request").performScrollTo().assertIsEnabled()
    }

    @Test
    fun confirmedDeletionHasNoSecondDestructiveButton() {
        val value = snapshot()
        val after = value.copy(item = null)
        compose.setContent {
            MaterialTheme {
                ContentLifecycleContent(
                    state(after)
                        .copy(
                            confirmed =
                                ContentLifecycleConfirmation(
                                    after,
                                    ContentLifecycleReceipt.Deleted(value.target, now),
                                )
                        ),
                    "de",
                    ContentLifecycleActions(),
                )
            }
        }
        compose.onNodeWithTag("content-lifecycle-confirmed").performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("content-lifecycle-request").assertDoesNotExist()
    }

    @Test
    fun longConfirmationFlowIsReachableAtTwoHundredPercent() {
        compose.setContent {
            CompositionLocalProvider(
                LocalDensity provides Density(LocalDensity.current.density, 2f)
            ) {
                MaterialTheme {
                    ContentLifecycleContent(
                        state(snapshot(ContentKind.EVENTS)),
                        "uk",
                        ContentLifecycleActions(),
                    )
                }
            }
        }
        compose
            .onNodeWithTag("content-lifecycle-request")
            .performScrollTo()
            .assertIsDisplayed()
            .assertIsEnabled()
        compose.onNodeWithTag("content-lifecycle-refresh").performScrollTo().assertIsDisplayed()
    }
}
