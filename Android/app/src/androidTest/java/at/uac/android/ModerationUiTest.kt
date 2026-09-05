package at.uac.android

import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.design.UacTheme
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.moderation.*
import java.time.Instant
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Injected read-only UI states only; none of these tests proves genuine privileged TOTP. */
@RunWith(AndroidJUnit4::class)
class ModerationUiTest {
    @get:Rule val compose = createComposeRule()
    private val actor = ModerationSession("synthetic-reviewer", 1, "admin", true)
    private val target = ModerationTarget(ModerationKind.ORGANIZATION, "synthetic-request")

    private fun preview(): ModerationPreview =
        ModerationContract.preview(
            target,
            RawDocument(
                target.id,
                mapOf(
                    "id" to target.id,
                    "name" to "Private application",
                    "description" to "Private summary",
                    "fullDescription" to "Full private application text. ".repeat(30),
                    "moderationStatus" to "pendingReview",
                    "createdAt" to Instant.parse("2026-09-03T10:00:00Z"),
                    "updatedAt" to Instant.parse("2026-09-03T10:00:00Z"),
                    "submittedByUserId" to "synthetic-applicant",
                    "email" to "synthetic@example.invalid",
                    "reviewMessage" to "Synthetic review note",
                ),
            ),
        )

    @Test
    fun guestCannotSeeInjectedPrivatePreviewOrDecisionButtons() {
        val private = preview()
        compose.setContent {
            UacTheme {
                ModerationContent(
                    ModerationState(visible = true, selected = target, preview = private),
                    "de",
                    ModerationActions(),
                )
            }
        }
        compose.onNodeWithTag("moderation-denied").assertExists()
        compose.onNodeWithTag("moderation-preview-title").assertDoesNotExist()
        compose.onNodeWithText("Private application").assertDoesNotExist()
        compose.onNodeWithText("Genehmigen").assertDoesNotExist()
    }

    @Test
    fun ukrainianPrivatePreviewScrollsToContactAtTwoHundredPercentWithoutMutationControls() {
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
                UacTheme("dark") {
                    ModerationContent(
                        ModerationState(
                            actor,
                            ModerationSection.ORGANIZATION_REQUESTS,
                            true,
                            selected = target,
                            preview = preview(),
                        ),
                        "uk",
                        ModerationActions(),
                    )
                }
            }
        }
        compose
            .onNodeWithTag("moderation-list")
            .performScrollToNode(hasTestTag("moderation-preview-body"))
        compose
            .onNodeWithTag("moderation-preview-body")
            .assertTextContains("Full private application text.", substring = true)
        compose
            .onNodeWithTag("moderation-list")
            .performScrollToNode(hasTestTag("moderation-field-email"))
        compose
            .onNodeWithTag("moderation-field-email")
            .assertTextEquals("synthetic@example.invalid")
        compose.onNodeWithText("Схвалити").assertDoesNotExist()
        compose.onNodeWithText("Відхилити").assertDoesNotExist()
    }

    @Test
    fun exactScopeProjectionRemovesApplicantDataBeforeDelayedRebind() {
        var live by mutableStateOf<ModerationSession?>(actor)
        val stored =
            ModerationState(
                actor,
                ModerationSection.ORGANIZATION_REQUESTS,
                true,
                selected = target,
                preview = preview(),
            )
        compose.setContent {
            UacTheme { ModerationContent(stored.forSession(live), "de", ModerationActions()) }
        }
        compose
            .onNodeWithTag("moderation-list")
            .performScrollToNode(hasTestTag("moderation-preview-title"))
        compose.onNodeWithTag("moderation-preview-title").assertExists()
        compose.runOnIdle { live = actor.copy(revision = 2) }
        compose.onNodeWithText("Private application").assertDoesNotExist()
        compose.onNodeWithTag("moderation-field-email").assertDoesNotExist()
    }

    @Test
    fun cappedHeadAndIndependentSectionErrorHaveHonestReachableRetry() {
        var retry: ModerationKind? = null
        val head = ModerationHead(ModerationKind.NEWS, emptyList(), 100)
        compose.setContent {
            UacTheme {
                ModerationContent(
                    ModerationState(
                        actor,
                        visible = true,
                        parts =
                            mapOf(
                                ModerationKind.NEWS to ModerationPart(head = head),
                                ModerationKind.EVENT to
                                    ModerationPart(error = ModerationFailure.INDEX),
                            ),
                    ),
                    "de",
                    ModerationActions(retry = { retry = it }),
                )
            }
        }
        compose
            .onNodeWithTag("moderation-list")
            .performScrollToNode(hasTestTag("moderation-cap-NEWS"))
        compose
            .onNodeWithTag("moderation-cap-NEWS")
            .assertTextContains("keine vollständige", substring = true)
        compose
            .onNodeWithTag("moderation-list")
            .performScrollToNode(hasTestTag("moderation-retry-EVENT"))
        compose.onNodeWithTag("moderation-retry-EVENT").performClick()
        compose.runOnIdle { assertEquals(ModerationKind.EVENT, retry) }
        compose.onNodeWithTag("moderation-empty").assertDoesNotExist()
    }
}
