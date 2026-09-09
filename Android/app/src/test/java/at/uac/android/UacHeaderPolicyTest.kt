package at.uac.android

import at.uac.android.design.isCompactHeaderRoute
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UacHeaderPolicyTest {
    @Test
    fun everySecondaryRouteUsesCompactBranding() {
        for (route in
            listOf(
                "events",
                "events/example",
                "organizations",
                "news",
                "settings",
                "profile",
                "profile/edit",
                "profile/login",
            )) {
            assertTrue(route, isCompactHeaderRoute(route))
        }
    }

    @Test
    fun homeIsTheOnlyLargeBrandRoute() {
        assertFalse(isCompactHeaderRoute("home"))
    }
}
