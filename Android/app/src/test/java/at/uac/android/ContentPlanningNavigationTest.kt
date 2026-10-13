package at.uac.android

import at.uac.android.feature.browse.BrowseNavigation
import at.uac.android.feature.browse.PrimaryTab
import at.uac.android.feature.inbox.InboxDestinationKind
import at.uac.android.feature.inbox.InboxKind
import at.uac.android.feature.inbox.InboxNavigationTarget
import at.uac.android.feature.inbox.InboxNotice
import at.uac.android.feature.inbox.InboxSession
import at.uac.android.feature.inbox.resolveInboxNavigation
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Test

class ContentPlanningNavigationTest {
    @Test
    fun ownerPlanningRouteLivesInPrivateProfileStack() {
        val navigation =
            BrowseNavigation.restore()
                .select(PrimaryTab.PROFILE)
                .navigate("profile/content-planning")
        assertEquals("profile/content-planning", navigation.route)
        assertEquals("profile", navigation.back().route)
        val scrubbed = navigation.scrubPrivateDestinations()
        assertEquals("profile", scrubbed.route)
        assertFalse(scrubbed.canBack)
    }

    @Test
    fun planningAuthorRouteAcceptsOnlyValidatedDraftAndOrganizationIds() {
        val route = "profile/content-planning/author/${"a".repeat(40)}/org-1"
        val navigation = BrowseNavigation.restore().select(PrimaryTab.PROFILE).navigate(route)
        assertEquals(route, navigation.route)
        assertEquals("profile", navigation.scrubPrivateDestinations().route)

        assertThrows(IllegalArgumentException::class.java) {
            BrowseNavigation.restore()
                .select(PrimaryTab.PROFILE)
                .navigate("profile/content-planning/author/not-a-draft/org-1")
        }
    }

    @Test
    fun draftNotificationDeepLinkRequiresLiveOwnerDecision() {
        val session = InboxSession("owner", 68, true)
        val now = Instant.parse("2026-09-07T12:00:00Z")
        val notice =
            InboxNotice(
                "notice",
                "owner",
                InboxKind.DRAFT,
                now,
                false,
                actionType = "openContentPlanning",
                actionTargetId = "a".repeat(40),
            )
        val destination = requireNotNull(notice.destination(now))
        assertEquals(InboxDestinationKind.CONTENT_PLANNING, destination.kind)
        assertEquals(
            InboxNavigationTarget.Route("profile/content-planning/${"a".repeat(40)}"),
            resolveInboxNavigation(notice, destination, session, session, false, now, true),
        )
        assertEquals(
            null,
            resolveInboxNavigation(notice, destination, session, session, false, now, false),
        )
    }
}
