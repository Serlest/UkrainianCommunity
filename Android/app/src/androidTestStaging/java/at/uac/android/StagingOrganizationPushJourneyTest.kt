package at.uac.android

import android.Manifest
import android.content.pm.PackageManager
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.core.content.ContextCompat
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.feature.auth.AuthGate
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.inbox.InboxViewModel
import at.uac.android.feature.inbox.inboxScope
import at.uac.android.feature.inbox.resolveInboxNavigation
import at.uac.android.feature.organization.OrganizationManagementViewModel
import at.uac.android.feature.organization.OrganizationTeamRole
import at.uac.android.feature.organization.localOrganizationManagementSource
import at.uac.android.feature.push.PrivatePushOwnershipStore
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.delay
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Disposable accounts and organization created only by test-organization-push-staging.mjs. */
@RunWith(AndroidJUnit4::class)
class StagingOrganizationPushJourneyTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val args get() = InstrumentationRegistry.getArguments()
    private val suffix get() = args.getString("step5Suffix").orEmpty()
    private val memberId get() = args.getString("memberId").orEmpty()
    private val orgId get() = "step5-org-$suffix"

    private fun login(who: String) {
        assertEquals("at.serlest.ukrainiancommunity.staging", compose.activity.packageName)
        assertTrue(suffix.matches(Regex("[a-f0-9]{16}")))
        val email = args.getString("${who}Email").orEmpty()
        val password = args.getString("${who}Password").orEmpty()
        assertEquals("step5-$who-$suffix@example.invalid", email)
        assertTrue(password.length >= 20)
        val auth = LocalAuthSession.get(compose.activity)
        if (auth.state.value.identity?.email == email &&
            auth.state.value.stage == AuthStage.AUTHENTICATED &&
            auth.state.value.gate == AuthGate.READY) return
        compose.runOnIdle { auth.signOut() }
        compose.waitUntil(60_000) { compose.onAllNodesWithTag("auth-login-submit").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("auth-email").performScrollTo().performTextInput(email)
        compose.onNodeWithTag("auth-password").performScrollTo().performTextInput(password)
        compose.onNodeWithTag("auth-login-submit").performScrollTo().performClick()
        compose.waitUntil(60_000) {
            auth.state.value.let { it.stage == AuthStage.AUTHENTICATED && it.gate == AuthGate.READY }
        }
    }

    @Test fun memberEnablesPushThroughUi() {
        login("member")
        val browse = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]
        val inbox = ViewModelProvider(compose.activity)[InboxViewModel::class.java]
        compose.runOnIdle { browse.navigate("profile/inbox-settings") }
        compose.waitUntil(60_000) { inbox.state.value.preferences != null }
        compose.onNodeWithTag("inbox-push-toggle").performScrollTo().assertIsOff().performClick()
        compose.waitUntil(60_000) { inbox.state.value.preferences?.notificationsEnabled == true && !inbox.state.value.mutating }
        assertNull(inbox.state.value.error)
        val uid = LocalAuthSession.get(compose.activity).state.value.identity!!.uid
        val ownership = PrivatePushOwnershipStore(compose.activity)
        runBlocking {
            withTimeout(70_000) {
                while (ownership.load()?.uid != uid) delay(500)
            }
            // Keep the first installation alive while FCM propagates its new FID.
            delay(5_000)
        }
    }

    @Test fun ownerPromotesAndRemovesMemberThroughUi() {
        login("owner")
        val browse = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]
        val management = ViewModelProvider(compose.activity)[OrganizationManagementViewModel::class.java]
        compose.runOnIdle { browse.navigate("profile/organizations/manage/$orgId") }
        compose.waitUntil(60_000) { management.state.value.actionable &&
            management.state.value.snapshot?.members?.any { it.profile.id == memberId } == true }
        assertEquals(OrganizationTeamRole.MODERATOR,
            management.state.value.snapshot?.members?.first { it.profile.id == memberId }?.role)
        val snapshot = management.state.value.snapshot!!.organization
        val fresh = runBlocking {
            localOrganizationManagementSource(compose.activity).organization(orgId, management.state.value.session!!)
        }!!
        assertEquals("Organization changed before role intent", snapshot.updatedAt, fresh.updatedAt)
        assertEquals("Organization fields changed before role intent", snapshot.fields, fresh.fields)
        // Initial server listeners may publish after the first explicit read. Let both settle
        // before interacting with a destructive confirmation dialog.
        Thread.sleep(1_500)
        compose.waitUntil(20_000) { management.state.value.actionable }
        compose.onNodeWithTag("organization-management").performScrollToNode(hasTestTag("organization-team-admin-$memberId"))
        compose.onNodeWithTag("organization-team-admin-$memberId").performClick()
        compose.waitUntil(10_000) { management.state.value.confirmation != null && management.state.value.actionable }
        compose.onNodeWithTag("organization-management-confirm-role").assertIsDisplayed().performClick()
        try {
            compose.waitUntil(60_000) { management.state.value.actionable &&
                management.state.value.snapshot?.members?.firstOrNull { it.profile.id == memberId }?.role == OrganizationTeamRole.ADMIN }
        } catch (error: Throwable) {
            val state = management.state.value
            throw AssertionError("Admin transition state: error=${state.error}, busy=${state.busy}, " +
                "loading=${state.loading}, fresh=${state.fresh}, confirmed=${state.confirmed}, " +
                "role=${state.snapshot?.members?.firstOrNull { it.profile.id == memberId }?.role}", error)
        }
        assertNull(management.state.value.error)
        compose.onNodeWithTag("organization-management").performScrollToNode(hasTestTag("organization-team-remove-$memberId"))
        compose.onNodeWithTag("organization-team-remove-$memberId").performClick()
        compose.onNodeWithTag("organization-management-confirm-role").performClick()
        compose.waitUntil(60_000) { management.state.value.actionable &&
            management.state.value.snapshot?.members?.firstOrNull { it.profile.id == memberId }?.role == OrganizationTeamRole.MEMBER }
        assertNull(management.state.value.error)
    }

    @Test fun memberOpensRoleInboxDestinationThroughUi() {
        login("member")
        val browse = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]
        val inbox = ViewModelProvider(compose.activity)[InboxViewModel::class.java]
        compose.runOnIdle { browse.navigate("profile/inbox") }
        compose.waitUntil(60_000) { inbox.state.value.items.any { it.kind.wire == "organizationRoleAssigned" } }
        val notice = inbox.state.value.items.first { it.kind.wire == "organizationRoleAssigned" }
        val live = LocalAuthSession.get(compose.activity).state.value
        assertTrue("Inbox session changed before navigation", inbox.state.value.session == live.inboxScope())
        assertTrue("Inbox route policy denied own notice",
            resolveInboxNavigation(notice, notice.destination(java.time.Instant.now())!!,
                inbox.state.value.session, live.inboxScope(), false, java.time.Instant.now()) != null)
        compose.onNodeWithTag("inbox-list").performScrollToNode(hasTestTag("inbox-details-${notice.id}"))
        compose.onNodeWithTag("inbox-details-${notice.id}").performClick()
        compose.onNodeWithTag("inbox-list").performScrollToNode(hasTestTag("inbox-open-${notice.id}"))
        compose.waitUntil(10_000) { !inbox.state.value.mutating }
        compose.onNodeWithTag("inbox-open-${notice.id}").assertIsEnabled().performClick()
        try {
            compose.waitUntil(60_000) { browse.state.value.detailId == orgId &&
                browse.state.value.data.detail?.id == orgId }
        } catch (error: Throwable) {
            throw AssertionError("Inbox open did not navigate: route=${browse.state.value.route}, " +
                "destination=${notice.destination(java.time.Instant.now())}, " +
                "inboxError=${inbox.state.value.error}", error)
        }
    }

    @Test fun memberDisablesPushThroughUi() {
        login("member")
        val browse = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]
        val inbox = ViewModelProvider(compose.activity)[InboxViewModel::class.java]
        val uid = LocalAuthSession.get(compose.activity).state.value.identity!!.uid
        val ownership = PrivatePushOwnershipStore(compose.activity)
        compose.runOnIdle { browse.navigate("profile/inbox-settings") }
        compose.waitUntil(60_000) { inbox.state.value.preferences?.notificationsEnabled == true }
        runBlocking { withTimeout(70_000) { while (ownership.load()?.uid != uid) delay(500) } }
        compose.onNodeWithTag("inbox-push-toggle").performScrollTo().assertIsOn().performClick()
        compose.waitUntil(60_000) { inbox.state.value.preferences?.notificationsEnabled == false && !inbox.state.value.mutating }
        runBlocking { withTimeout(70_000) { while (ownership.load() != null) delay(500) } }
        assertNull(inbox.state.value.error)
    }

    @Test fun memberEnablesConsentWithOsPermissionDenied() {
        login("member")
        assertEquals(PackageManager.PERMISSION_DENIED,
            ContextCompat.checkSelfPermission(compose.activity, Manifest.permission.POST_NOTIFICATIONS))
        val browse = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]
        val inbox = ViewModelProvider(compose.activity)[InboxViewModel::class.java]
        val ownership = PrivatePushOwnershipStore(compose.activity)
        compose.runOnIdle { browse.navigate("profile/inbox-settings") }
        compose.waitUntil(60_000) { inbox.state.value.preferences?.notificationsEnabled == false }
        compose.onNodeWithTag("inbox-push-toggle").performScrollTo().assertIsOff().performClick()
        compose.waitUntil(60_000) { inbox.state.value.preferences?.notificationsEnabled == true && !inbox.state.value.mutating }
        runBlocking { delay(3_000); assertNull(ownership.load()) }
        assertNull(inbox.state.value.error)
    }

    @Test fun memberRegistersAfterOsPermissionGranted() {
        login("member")
        assertEquals(PackageManager.PERMISSION_GRANTED,
            ContextCompat.checkSelfPermission(compose.activity, Manifest.permission.POST_NOTIFICATIONS))
        val uid = LocalAuthSession.get(compose.activity).state.value.identity!!.uid
        val ownership = PrivatePushOwnershipStore(compose.activity)
        runBlocking {
            withTimeout(70_000) { while (ownership.load()?.uid != uid) delay(500) }
            delay(5_000)
        }
    }
}
