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
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Injected UI states, not native privileged Auth or TOTP proof. The panel creates no Dialog. */
@RunWith(AndroidJUnit4::class)
class ModerationDecisionUiTest {
    @get:Rule val compose = createComposeRule()
    private val actor = ModerationDecisionAndroidFixture.actor
    private val version = ModerationDecisionAndroidFixture.version()

    private fun largeTextDecision(language: String, decision: ModerationDecision) {
        val preview =
            ModerationContract.preview(
                version.target,
                RawDocument(
                    version.target.id,
                    ModerationDecisionAndroidFixture.fields() +
                        ("body" to
                            "Повний приватний текст · Vollständiger privater Text. ".repeat(160)),
                ),
            )
        var stored by mutableStateOf(ModerationDecisionState(actor, journalReady = true))
        var renderedScale = 0f
        var requests = 0
        var confirms = 0
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
                UacTheme(if (language == "uk") "dark" else "light") {
                    ModerationContent(
                        ModerationState(
                            actor,
                            visible = true,
                            selected = version.target,
                            preview = preview,
                        ),
                        language,
                        ModerationActions(),
                        decisionContent = {
                            val actualScale = LocalDensity.current.fontScale
                            SideEffect { renderedScale = actualScale }
                            ModerationDecisionPanel(
                                stored,
                                preview.reviewVersion,
                                language,
                                ModerationDecisionActions(
                                    request = {
                                        requests++
                                        stored = stored.copy(confirmation = it)
                                    },
                                    confirm = { confirms++ },
                                    cancel = { stored = stored.copy(confirmation = null) },
                                ),
                            )
                        },
                    )
                }
            }
        }
        val tag =
            if (decision == ModerationDecision.APPROVE) "moderation-approve"
            else "moderation-reject"
        compose.onNodeWithTag("moderation-list").performScrollToNode(hasTestTag(tag))
        compose.onNodeWithTag(tag).assertIsDisplayed().performClick()
        compose
            .onNodeWithTag("moderation-list")
            .performScrollToNode(hasTestTag("moderation-decision-confirm"))
        compose.onNodeWithTag("moderation-decision-confirm").assertIsDisplayed().performClick()
        compose.runOnIdle {
            assertEquals(2f, renderedScale, 0.001f)
            assertEquals(decision, stored.confirmation)
            assertEquals(1, requests)
            assertEquals(1, confirms)
        }
    }

    @Test
    fun germanLargePrivateBodyHasReachableExplicitConfirmationAtActualTwoHundredPercent() =
        largeTextDecision("de", ModerationDecision.APPROVE)

    @Test
    fun ukrainianLargePrivateBodyHasReachableExplicitRejectionAtActualTwoHundredPercent() =
        largeTextDecision("uk", ModerationDecision.REJECT)

    @Test
    fun uncertainPendingOffersOnlyReadReconciliationAndNeverAnotherDecision() {
        val pending = ModerationDecisionAndroidFixture.pending(ModerationDecisionPhase.DISPATCHED)
        var reads = 0
        var mutations = 0
        compose.setContent {
            UacTheme {
                ModerationContent(
                    ModerationState(actor, visible = true),
                    "de",
                    ModerationActions(),
                    decisionContent = {
                        ModerationDecisionPanel(
                            ModerationDecisionState(
                                actor,
                                journalReady = true,
                                pending = listOf(pending),
                                observation = ModerationObservation.OBSERVED_WITHOUT_RECEIPT,
                            ),
                            version,
                            "de",
                            ModerationDecisionActions(
                                request = { mutations++ },
                                confirm = { mutations++ },
                                reconcile = { reads++ },
                            ),
                        )
                    },
                )
            }
        }
        compose
            .onNodeWithTag("moderation-list")
            .performScrollToNode(hasTestTag("moderation-reconcile-0"))
        compose.onNodeWithTag("moderation-reconcile-0").performClick()
        compose.onNodeWithTag("moderation-approve").assertDoesNotExist()
        compose.onNodeWithTag("moderation-reject").assertDoesNotExist()
        compose.runOnIdle {
            assertEquals(1, reads)
            assertEquals(0, mutations)
        }
    }

    @Test
    fun exactSessionProjectionMasksPendingConfirmationBeforeDelayedBind() {
        var current by mutableStateOf<ModerationSession?>(actor)
        val stored =
            ModerationDecisionState(
                actor,
                journalReady = true,
                confirmation = ModerationDecision.APPROVE,
            )
        compose.setContent {
            UacTheme {
                ModerationContent(
                    ModerationState(actor, visible = true).forSession(current),
                    "de",
                    ModerationActions(),
                    decisionContent = {
                        ModerationDecisionPanel(
                            stored.forSession(current),
                            version,
                            "de",
                            ModerationDecisionActions(),
                        )
                    },
                )
            }
        }
        compose
            .onNodeWithTag("moderation-list")
            .performScrollToNode(hasTestTag("moderation-decision-confirm"))
        compose.onNodeWithTag("moderation-decision-confirm").assertExists()
        compose.runOnIdle { current = actor.copy(revision = actor.revision + 1) }
        compose.onNodeWithTag("moderation-decisions").assertDoesNotExist()
        compose.runOnIdle { current = actor.copy(uid = "synthetic-new-reviewer") }
        compose.onNodeWithTag("moderation-decisions").assertDoesNotExist()
        compose.runOnIdle { current = null }
        compose.onNodeWithTag("moderation-decision-confirm").assertDoesNotExist()
    }

    @Test
    fun unreadableJournalOnlyAllowsRecoveryReadAndBusyStateBlocksIt() {
        var busy by mutableStateOf(false)
        var journalReads = 0
        compose.setContent {
            UacTheme {
                ModerationContent(
                    ModerationState(actor, visible = true),
                    "uk",
                    ModerationActions(),
                    decisionContent = {
                        ModerationDecisionPanel(
                            ModerationDecisionState(
                                actor,
                                busy = busy,
                                error = ModerationDecisionFailure.JOURNAL,
                            ),
                            version,
                            "uk",
                            ModerationDecisionActions(refreshJournal = { journalReads++ }),
                        )
                    },
                )
            }
        }
        compose
            .onNodeWithTag("moderation-list")
            .performScrollToNode(hasTestTag("moderation-journal-retry"))
        compose.onNodeWithTag("moderation-journal-retry").performClick()
        compose.onNodeWithTag("moderation-approve").assertDoesNotExist()
        compose.runOnIdle {
            assertEquals(1, journalReads)
            busy = true
        }
        compose.onNodeWithTag("moderation-journal-retry").assertDoesNotExist()
        compose.onNodeWithTag("moderation-decision-confirm").assertDoesNotExist()
    }

    @Test
    fun organizationVersionAndAbsentVersionNeverExposeMutationControls() {
        var selected by
            mutableStateOf<ModerationReviewVersion?>(
                version.copy(
                    target = ModerationTarget(ModerationKind.ORGANIZATION, "synthetic-org")
                )
            )
        compose.setContent {
            UacTheme {
                ModerationContent(
                    ModerationState(actor, visible = true),
                    "de",
                    ModerationActions(),
                    decisionContent = {
                        ModerationDecisionPanel(
                            ModerationDecisionState(
                                actor,
                                journalReady = true,
                                confirmation = ModerationDecision.APPROVE,
                            ),
                            selected,
                            "de",
                            ModerationDecisionActions(),
                        )
                    },
                )
            }
        }
        compose.onNodeWithTag("moderation-approve").assertDoesNotExist()
        compose.onNodeWithTag("moderation-decision-confirm").assertDoesNotExist()
        compose.runOnIdle { selected = null }
        compose.onNodeWithTag("moderation-reject").assertDoesNotExist()
    }
}
