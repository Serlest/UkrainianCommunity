package at.uac.android

import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import at.uac.android.feature.authoring.*
import at.uac.android.feature.authoring.recovery.AuthoringRecoveryFailure
import at.uac.android.feature.browse.*
import at.uac.android.feature.organization.*
import java.time.Instant
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class AuthoringRecoveryUiTest {
    @get:Rule val compose = createComposeRule()
    private val actor = OrganizationSession("ui-recovery-author", 1, true, "Author", "user")
    private val now = Instant.parse("2026-09-03T03:00:00Z")
    private val org
        get() =
            OrganizationDraft(
                    "ui-recovery-org",
                    "Recovery organization",
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
                .copy(title = "Private recovered headline", summary = "Summary", body = "Body")

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
        )

    @Test
    fun recoveredDraftNeedsExplicitContinueAndPreventsAnotherCreate() {
        var restored = false
        compose.setContent {
            MaterialTheme {
                AuthoringContent(
                    state().copy(recoveredDraft = draft, draftZoneId = "America/Los_Angeles"),
                    "de",
                    AuthoringActions(restoreDraft = { restored = true }),
                )
            }
        }
        assertFalse(restored)
        compose.onNodeWithTag("authoring-title").assertDoesNotExist()
        compose.onNodeWithTag("authoring-create").performScrollTo().assertIsNotEnabled()
        compose
            .onNodeWithTag("authoring-restore-draft")
            .performScrollTo()
            .assertIsEnabled()
            .performClick()
        assertTrue(restored)
    }

    @Test
    fun deletingRecoveredUnsentDraftRequiresProtectedConfirmation() {
        var deleted = false
        compose.setContent {
            MaterialTheme {
                AuthoringContent(
                    state().copy(recoveredDraft = draft),
                    "uk",
                    AuthoringActions(discardRecoveredDraft = { deleted = true }),
                )
            }
        }
        compose.onNodeWithTag("authoring-delete-draft").performScrollTo().performClick()
        assertFalse(deleted)
        compose.onNodeWithTag("authoring-delete-draft-confirm").assertIsDisplayed().performClick()
        assertTrue(deleted)
    }

    @Test
    fun coldPendingWithoutEditorCanOnlyCheckAndCannotBeDiscardedOrRetriedBlindly() {
        val value = AuthoringContract.submission(draft, org, actor, null, now)
        compose.setContent {
            MaterialTheme {
                AuthoringContent(state().copy(uncertain = value), "de", AuthoringActions())
            }
        }
        compose.onNodeWithTag("authoring-uncertain").performScrollTo().assertExists()
        compose.onNodeWithTag("authoring-recover").performScrollTo().assertIsEnabled()
        compose.onNodeWithTag("authoring-create").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithTag("authoring-discard-local").assertDoesNotExist()
        compose.onNodeWithTag("authoring-delete-draft").assertDoesNotExist()
        compose.onNodeWithTag("authoring-retry-same").assertDoesNotExist()
    }

    @Test
    fun missingKeyIsVisibleAndFreshServerAloneDoesNotEnableCreate() {
        compose.setContent {
            MaterialTheme {
                AuthoringContent(
                    state().copy(recoveryError = AuthoringRecoveryFailure.LOCKED),
                    "de",
                    AuthoringActions(),
                )
            }
        }
        compose.onNodeWithTag("authoring-storage-error").performScrollTo().assertExists()
        compose.onNodeWithTag("authoring-create").performScrollTo().assertIsNotEnabled()
    }

    @Test
    fun newAccountWithoutReadyScopeCannotSeeRecoveredPrivateText() {
        compose.setContent {
            MaterialTheme {
                AuthoringContent(
                    state().copy(session = null, recoveredDraft = draft),
                    "uk",
                    AuthoringActions(),
                )
            }
        }
        compose.onNodeWithText("Private recovered headline").assertDoesNotExist()
        compose.onNodeWithTag("authoring-restore-draft").assertDoesNotExist()
    }

    @Test
    fun failedScopeExitWarningSurvivesFreshStateAndOffersOnlyExplicitLocalSave() {
        var saved = false
        compose.setContent {
            MaterialTheme {
                AuthoringContent(
                    state()
                        .copy(
                            recoveredDraft = draft,
                            unsavedExitCount = 1,
                            exitSaveError = AuthoringRecoveryFailure.IO,
                            failedCurrentDraft = true,
                        ),
                    "de",
                    AuthoringActions(retryLocalSave = { saved = true }),
                )
            }
        }
        compose.onNodeWithTag("authoring-exit-save-error").performScrollTo().assertExists()
        assertFalse(saved)
        compose
            .onNodeWithTag("authoring-retry-local-save")
            .performScrollTo()
            .assertIsEnabled()
            .performClick()
        assertTrue(saved)
        compose.onNodeWithTag("authoring-create").performScrollTo().assertIsNotEnabled()
    }

    @Test
    fun pendingDisablesLocalSaveEvenWhenAnUnsentMemoryWarningExists() {
        val intent = AuthoringContract.submission(draft, org, actor, null, now)
        compose.setContent {
            MaterialTheme {
                AuthoringContent(
                    state()
                        .copy(
                            uncertain = intent,
                            unsavedExitCount = 1,
                            exitSaveError = AuthoringRecoveryFailure.IO,
                            failedCurrentDraft = true,
                        ),
                    "uk",
                    AuthoringActions(),
                )
            }
        }
        compose.onNodeWithTag("authoring-retry-local-save").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithTag("authoring-recover").performScrollTo().assertIsEnabled()
        compose.onNodeWithTag("authoring-restore-draft").assertDoesNotExist()
    }
}
