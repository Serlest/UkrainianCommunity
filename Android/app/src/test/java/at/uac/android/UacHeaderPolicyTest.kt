package at.uac.android

import at.uac.android.design.isCompactAuthHeaderRoute
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UacHeaderPolicyTest {
    @Test
    fun onlyTheThreeExactCanonicalGuestAuthRoutesUseCompactBranding() {
        for (route in listOf("profile/login", "profile/register", "profile/reset")) {
            assertTrue(route, isCompactAuthHeaderRoute(route))
        }
    }

    @Test
    fun publicAccountSecurityAndMalformedNearMatchesKeepTheirExistingPolicy() {
        for (route in
            listOf(
                "",
                "home",
                "events",
                "organizations",
                "news",
                "settings",
                "profile",
                "profile/edit",
                "profile/delete",
                "profile/deleted",
                "profile/history",
                "profile/organizations",
                "profile/login/",
                "profile/login/extra",
                "profile/registering",
                "profile/reset-code",
                "profile/Login",
                "profile%2Flogin",
                "/profile/login",
                "profile/login?next=home",
                "profile/login ",
                "other/profile/login",
            )) {
            assertFalse(route, isCompactAuthHeaderRoute(route))
        }
    }
}
