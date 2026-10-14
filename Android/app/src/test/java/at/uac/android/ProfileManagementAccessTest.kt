package at.uac.android

import at.uac.android.feature.personal.ProfileManagementAccess
import org.junit.Assert.*
import org.junit.Test

class ProfileManagementAccessTest {
    private val ownerRoutes =
        listOf(
            "analytics",
            "donation-settings",
            "featured-banners",
            "content-planning",
            "legal-evidence",
            "announcements/manage",
        )
    private val moderatorRoutes =
        listOf("system-logs", "users", "moderation", "organization-review")

    private fun variants(route: String) =
        listOf("profile/$route", "profile/$route/synthetic-detail")

    @Test
    fun guestOrdinaryUserAndRevokedCapabilitiesCannotOpenManagementRoutes() {
        // These identities deliberately have the same empty capability projection.
        listOf("guest", "user", "revoked-admin", "revoked-owner").forEach { identity ->
            val access = ProfileManagementAccess()
            (ownerRoutes + moderatorRoutes + "support" + "administration")
                .flatMap(::variants)
                .forEach {
                    assertFalse("$identity must not access $it", access.allows(it))
                }
        }
    }

    @Test
    fun moderatorCannotUseOwnerOrSupportCapabilitiesImplicitly() {
        val access = ProfileManagementAccess(moderator = true)
        (moderatorRoutes + "administration").flatMap(::variants).forEach {
            assertTrue(it, access.allows(it))
        }
        (ownerRoutes + "support").flatMap(::variants).forEach { assertFalse(it, access.allows(it)) }
    }

    @Test
    fun ownerAndSupportCapabilitiesRemainIndependent() {
        val owner = ProfileManagementAccess(owner = true)
        (ownerRoutes + "administration").flatMap(::variants).forEach {
            assertTrue(it, owner.allows(it))
        }
        (moderatorRoutes + "support").flatMap(::variants).forEach {
            assertFalse(it, owner.allows(it))
        }
        val support = ProfileManagementAccess(support = true)
        (listOf("support", "administration")).flatMap(::variants).forEach {
            assertTrue(it, support.allows(it))
        }
        (ownerRoutes + moderatorRoutes).flatMap(::variants).forEach {
            assertFalse(it, support.allows(it))
        }
        val full = ProfileManagementAccess(owner = true, moderator = true, support = true)
        (ownerRoutes + moderatorRoutes + "support" + "administration").flatMap(::variants).forEach {
            assertTrue(it, full.allows(it))
        }
    }

    @Test
    fun personalRoutesRemainAvailableAfterCapabilitiesAreRevoked() {
        val revoked = ProfileManagementAccess()
        listOf(
                "profile",
                "profile/security",
                "profile/preferences",
                "profile/recent",
                "profile/history",
                "profile/dsa-review/own-report",
                "profile/dsa-statement/own-report",
                "profile/announcements",
                "profile/feedback/synthetic-case",
                "profile/organizations/synthetic-org",
            )
            .forEach {
                assertTrue(it, revoked.allows(it))
            }
    }

    @Test
    fun dsaOwnerRouteRequiresOwnerCapability() {
        assertTrue(ProfileManagementAccess(owner = true).allows("profile/dsa-owner/report"))
        assertFalse(ProfileManagementAccess(moderator = true).allows("profile/dsa-owner/report"))
        assertFalse(ProfileManagementAccess().allows("profile/dsa-owner/report"))
    }
}
