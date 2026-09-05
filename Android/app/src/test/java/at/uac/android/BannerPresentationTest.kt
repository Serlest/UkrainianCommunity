package at.uac.android

import at.uac.android.feature.browse.bannerRoute
import org.junit.Assert.*
import org.junit.Test

class BannerPresentationTest {
    @Test
    fun canonicalContentRoutesMatchTheNavigationContract() {
        assertEquals("news/новина 1", bannerRoute("news", "новина 1"))
        assertEquals("events/event-a", bannerRoute("event", "event-a"))
        assertEquals("organizations/org_1", bannerRoute("organization", "org_1"))
    }

    @Test
    fun malformedMissingOrOverlongTargetsNeverCreateAClickableRoute() {
        listOf("", " ", ".", "..", "events/other", "line\nbreak", "x".repeat(2_100)).forEach {
            assertNull(bannerRoute("news", it))
            assertNull(bannerRoute("event", it))
        }
        listOf("org:1", "організація", "x".repeat(129)).forEach {
            assertNull(bannerRoute("organization", it))
        }
    }

    @Test
    fun externalUnknownAndPrivilegedActionsCannotBecomeInternalRoutes() {
        listOf("externalURL", "profile", "deleteNews", "settings", "NEWS", "").forEach {
            assertNull(bannerRoute(it, "article"))
        }
        assertNull(bannerRoute("news", "https://example.invalid"))
    }
}
