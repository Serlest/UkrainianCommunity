package at.uac.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.moderation.ModerationViewModel
import at.uac.android.feature.platformrolemanagement.PlatformRoleViewModel
import at.uac.android.feature.usermanagement.ManagedUsersViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

/**
 * A real guest Main route cannot manufacture a privileged session or expose a pending-review
 * preview.
 */
class ModerationEntryJourneyUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    @Test
    fun guestAccountHasNoReviewActionsAndDirectPrivateRoutesRemainClosed() {
        AccountDeletionFixtures.requireLocalAvd()
        val auth = LocalAuthSession.get(compose.activity)
        val browse = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]
        val moderation = ViewModelProvider(compose.activity)[ModerationViewModel::class.java]
        val users = ViewModelProvider(compose.activity)[ManagedUsersViewModel::class.java]
        val roles = ViewModelProvider(compose.activity)[PlatformRoleViewModel::class.java]
        runBlocking { withContext(Dispatchers.Main) { auth.signOut() }.join() }
        compose.waitUntil(20_000) { auth.state.value.stage == AuthStage.GUEST }
        compose.runOnIdle { browse.navigate("profile", true) }
        compose.onNodeWithTag("guest-welcome").assertExists()
        compose.onNodeWithTag("account-open-moderation").assertDoesNotExist()
        compose.onNodeWithTag("account-open-users").assertDoesNotExist()
        compose.onNodeWithTag("account-open-organization-review").assertDoesNotExist()
        try {
            compose.runOnIdle { browse.navigate("profile/users") }
            compose.waitUntil(15_000) {
                compose.onNodeWithTag("managed-users-access").isDisplayed()
            }
            compose.onNodeWithTag("managed-users-search").assertDoesNotExist()
            compose.onNodeWithTag("platform-role-panel").assertDoesNotExist()
            compose.onNodeWithTag("platform-role-confirm-scroll").assertDoesNotExist()
            compose.runOnIdle {
                assertTrue(users.state.value.users.isEmpty())
                assertNull(users.state.value.detail)
                assertNull(users.state.value.security)
                assertNull(users.state.value.next)
                assertNull(roles.state.value.session)
                assertNull(roles.state.value.snapshot)
                assertNull(roles.state.value.targetAuth)
                assertNull(roles.state.value.confirmation)
                assertTrue(roles.state.value.pending.isEmpty())
                assertNull(LocalFirebase.auth(compose.activity).currentUser)
            }
            compose.onNodeWithTag("managed-users-back").performScrollTo().performClick()
            compose.waitUntil(15_000) { browse.state.value.route == "profile" }
            for (route in
                listOf(
                    "profile/moderation",
                    "profile/organization-review",
                    "profile/organization-review/synthetic-request",
                )) {
                compose.runOnIdle { browse.navigate(route) }
                // At the real 200% system font, the explanatory header can fill the viewport.
                // Scroll the actual list to the denial; do not assume its first-frame placement.
                compose
                    .onNodeWithTag("moderation-list")
                    .performScrollToNode(hasTestTag("moderation-denied"))
                compose.onNodeWithTag("moderation-denied").assertIsDisplayed()
                compose.onNodeWithTag("moderation-preview-title").assertDoesNotExist()
                assertTrue(moderation.state.value.parts.isEmpty())
                assertNull(moderation.state.value.preview)
                assertNull(LocalFirebase.auth(compose.activity).currentUser)
                compose.onNodeWithTag("moderation-back").performScrollTo().performClick()
                compose.waitUntil(15_000) { browse.state.value.route == "profile" }
            }
        } finally {
            compose.runOnIdle {
                moderation.hide()
                browse.navigate("profile", true)
            }
        }
    }
}
