package at.uac.android

import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.organization.*
import java.time.Instant
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class OrganizationManagementUiTest {
    @get:Rule val compose = createComposeRule()
    private val actor = OrganizationSession("synthetic-org-owner", 1, true, "Owner", "user")
    private val target = "synthetic-target"
    private val basics =
        OrganizationDraft(
            "synthetic-approved",
            "Synthetic Organization",
            "A complete synthetic description",
            region = "wien",
            city = "Wien",
        )

    private fun state(
        role: OrganizationAuthority = OrganizationAuthority.OWNER,
        targetRole: OrganizationTeamRole = OrganizationTeamRole.MEMBER,
    ): OrganizationManagementState {
        val session =
            if (role == OrganizationAuthority.PLATFORM_OWNER) actor.copy(globalRole = "owner")
            else actor
        val extra =
            mapOf(
                "moderationStatus" to "approved",
                "ownerId" to if (role == OrganizationAuthority.OWNER) actor.uid else "other-owner",
                "adminIds" to
                    (listOfNotNull(
                        actor.uid.takeIf { role == OrganizationAuthority.ADMIN },
                        target.takeIf { targetRole == OrganizationTeamRole.ADMIN },
                    )),
                "moderatorIds" to
                    (listOfNotNull(
                        actor.uid.takeIf { role == OrganizationAuthority.MODERATOR },
                        target.takeIf { targetRole == OrganizationTeamRole.MODERATOR },
                    )),
            )
        val record =
            OrganizationContract.record(
                RawDocument(
                    basics.id,
                    OrganizationContract.create(
                        basics,
                        actor,
                        Instant.parse("2026-09-03T00:00:00Z"),
                    ) + extra,
                ),
                session,
            )
        val members =
            listOf(
                OrganizationTeamMember(
                    OrganizationPublicMember(target, "Public subscriber", "Wien"),
                    targetRole,
                )
            )
        return OrganizationManagementState(
            session,
            basics.id,
            visible = true,
            snapshot = OrganizationManagementSnapshot(record, members, listOf(target), null),
            fresh = true,
        )
    }

    @Test
    fun ownerCanManageRolesButCannotTransferOwnership() {
        compose.setContent {
            MaterialTheme {
                OrganizationManagementContent(state(), "de", OrganizationManagementActions())
            }
        }
        compose.onNodeWithTag("organization-management-edit").assertExists()
        compose.onNodeWithTag("organization-team-admin-$target").performScrollTo().assertIsEnabled()
        compose.onNodeWithTag("organization-team-moderator-$target").assertExists()
        compose.onNodeWithTag("organization-team-transfer-$target").assertDoesNotExist()
    }

    @Test
    fun moderatorViewNeverExposesInformationOrRoleMutations() {
        compose.setContent {
            MaterialTheme {
                OrganizationManagementContent(
                    state(OrganizationAuthority.MODERATOR),
                    "uk",
                    OrganizationManagementActions(),
                )
            }
        }
        compose.onNodeWithTag("organization-team-$target").performScrollTo().assertExists()
        compose.onNodeWithTag("organization-management-edit").assertDoesNotExist()
        compose.onNodeWithTag("organization-team-admin-$target").assertDoesNotExist()
        compose.onNodeWithTag("organization-team-transfer-$target").assertDoesNotExist()
    }

    @Test
    fun organizationAdminCanEditInfoButCannotChangeTeam() {
        compose.setContent {
            MaterialTheme {
                OrganizationManagementContent(
                    state(OrganizationAuthority.ADMIN),
                    "de",
                    OrganizationManagementActions(),
                )
            }
        }
        compose.onNodeWithTag("organization-management-edit").assertIsEnabled()
        compose.onNodeWithTag("organization-team-admin-$target").assertDoesNotExist()
    }

    @Test
    fun platformOwnerTransferRemainsASeparateExplicitAction() {
        var chosen: OrganizationTeamAction? = null
        compose.setContent {
            MaterialTheme {
                OrganizationManagementContent(
                    state(OrganizationAuthority.PLATFORM_OWNER),
                    "de",
                    OrganizationManagementActions(
                        choose = { id, action ->
                            assertEquals(target, id)
                            chosen = action
                        }
                    ),
                )
            }
        }
        compose.onNodeWithTag("organization-team-transfer-$target").performScrollTo().performClick()
        assertEquals(OrganizationTeamAction.TRANSFER, chosen)
    }

    @Test
    fun removalRequiresVisibleConfirmationAndDescribesFullNonOwnerRoleRemoval() {
        var confirmed = false
        val state =
            state(targetRole = OrganizationTeamRole.ADMIN)
                .copy(
                    confirmation =
                        OrganizationRoleIntent(
                            target,
                            OrganizationTeamAction.REMOVE,
                            OrganizationTeamRole.ADMIN,
                        )
                )
        compose.setContent {
            MaterialTheme {
                OrganizationManagementContent(
                    state,
                    "de",
                    OrganizationManagementActions(confirm = { confirmed = true }),
                )
            }
        }
        assertFalse(confirmed)
        compose
            .onNodeWithText("auch wenn sie seit dem Öffnen geändert wurde", substring = true)
            .assertIsDisplayed()
        compose.onNodeWithTag("organization-management-confirm-role").performClick()
        assertTrue(confirmed)
    }

    @Test
    fun unconfirmedOutcomeDisablesAutomaticRoleRepeatAndRequiresNewDecision() {
        val state =
            state()
                .copy(
                    uncertain =
                        OrganizationRoleIntent(
                            target,
                            OrganizationTeamAction.ADMIN,
                            OrganizationTeamRole.MEMBER,
                        )
                )
        compose.setContent {
            MaterialTheme {
                OrganizationManagementContent(state, "de", OrganizationManagementActions())
            }
        }
        compose.onNodeWithTag("organization-management-uncertain").performScrollTo().assertExists()
        compose
            .onNodeWithTag("organization-team-admin-$target")
            .performScrollTo()
            .assertIsNotEnabled()
        compose.onNodeWithTag("organization-management-new-decision").assertExists()
    }

    @Test
    fun guestReceivesAccountRouteWithoutPrivateNames() {
        compose.setContent {
            MaterialTheme {
                OrganizationManagementContent(
                    OrganizationManagementState(),
                    "uk",
                    OrganizationManagementActions(),
                )
            }
        }
        compose.onNodeWithTag("organization-management-account").assertIsDisplayed()
        compose.onNodeWithText("Public subscriber").assertDoesNotExist()
    }

    @Test
    fun staleInformationFormPreservesTextButSaveIsDisabled() {
        val base = state().snapshot!!.organization
        val state =
            state()
                .copy(
                    base = base,
                    draft =
                        OrganizationManagementContract.draft(base).copy(mission = "Unsaved text"),
                    fresh = false,
                )
        compose.setContent {
            MaterialTheme {
                OrganizationManagementContent(state, "de", OrganizationManagementActions())
            }
        }
        compose.onNodeWithTag("organization-management-readonly").performScrollTo().assertExists()
        compose.onNodeWithTag("organization-name").assertIsNotEnabled()
        compose.onNodeWithTag("organization-management-save").performScrollTo().assertIsNotEnabled()
    }
}
