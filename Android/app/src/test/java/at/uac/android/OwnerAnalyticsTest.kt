package at.uac.android

import at.uac.android.feature.auth.AuthGate
import at.uac.android.feature.auth.AuthIdentity
import at.uac.android.feature.auth.AuthProfile
import at.uac.android.feature.auth.AuthSession
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.browse.BrowseNavigation
import at.uac.android.feature.browse.PrimaryTab
import at.uac.android.feature.owneranalytics.ownerAnalyticsScope
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class OwnerAnalyticsTest {
    private fun owner() =
        AuthSession(
            stage = AuthStage.AUTHENTICATED,
            identity = AuthIdentity("owner", "owner@example.invalid", true),
            profile =
                AuthProfile(
                    "owner",
                    "owner@example.invalid",
                    "Owner",
                    globalRole = "owner",
                    requiresMultiFactorAuth = true,
                ),
            revision = 68,
            gate = AuthGate.READY,
            totpAuthenticated = true,
        )

    @Test
    fun analyticsScopeRequiresOwnerLegalAndActivatedPrivilegedProof() {
        val session = owner()
        assertTrue(session.ownerAnalyticsScope()!!.ready)
        assertFalse(session.copy(totpAuthenticated = false).ownerAnalyticsScope()!!.ready)
        val passkeyProfile = session.profile!!.copy(passkeyEpoch = "epoch-1")
        assertTrue(session.copy(profile = passkeyProfile, totpAuthenticated = false,
            passkeyProofEpoch = "epoch-1").ownerAnalyticsScope()!!.ready)
        assertFalse(session.copy(profile = passkeyProfile, totpAuthenticated = false,
            passkeyProofEpoch = "old-epoch").ownerAnalyticsScope()!!.ready)
        assertFalse(session.copy(gate = AuthGate.LEGAL_REQUIRED).ownerAnalyticsScope()!!.ready)
        assertNull(
            session
                .copy(profile = passkeyProfile.copy(globalRole = "admin"))
                .ownerAnalyticsScope()
        )
        assertNull(
            session.copy(identity = session.identity!!.copy(anonymous = true)).ownerAnalyticsScope()
        )
    }

    @Test
    fun ownerAnalyticsRouteIsPrivateAndScrubbedOnLogout() {
        val navigation =
            BrowseNavigation.restore().select(PrimaryTab.PROFILE).navigate("profile/analytics")
        assertEquals("profile/analytics", navigation.route)
        assertEquals("profile", navigation.back().route)
        val scrubbed = navigation.scrubPrivateDestinations()
        assertEquals("profile", scrubbed.route)
        assertFalse(scrubbed.canBack)
    }
}
