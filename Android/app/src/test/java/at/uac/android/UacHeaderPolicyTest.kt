package at.uac.android

import at.uac.android.design.isCompactHeaderRoute
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UacHeaderPolicyTest {
    @Test
    fun secondaryRoutesUseCompactBranding() {
        for (route in
            listOf(
                "events/example",
                "news",
                "settings",
                "profile/edit",
                "profile/login",
            )) {
            assertTrue(route, isCompactHeaderRoute(route))
        }
    }

    @Test
    fun fiveRootTabsKeepFullBranding() {
        for (route in listOf("home", "events", "organizations", "directory", "profile"))
            assertFalse(route, isCompactHeaderRoute(route))
    }
}
