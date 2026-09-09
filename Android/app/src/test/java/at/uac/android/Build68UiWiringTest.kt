package at.uac.android

import at.uac.android.feature.analyticsconsent.AnalyticsConsentAuthority
import at.uac.android.feature.analyticsconsent.AnalyticsConsentReceipt
import at.uac.android.feature.analyticsconsent.AnalyticsConsentReceiptStore
import at.uac.android.feature.analyticsconsent.AnalyticsConsentSettingsController
import at.uac.android.feature.analyticsconsent.AnalyticsConsentSynchronizer
import at.uac.android.feature.analyticsconsent.AnalyticsConsentV2
import at.uac.android.feature.analyticsconsent.AnalyticsConsentV2Contract
import at.uac.android.feature.organization.OrganizationInformationRoute
import at.uac.android.feature.organization.organizationInformationRoute
import at.uac.android.feature.organizationaccess.OrganizationAccessRecord
import at.uac.android.feature.organizationaccess.OrganizationAccessSnapshot
import at.uac.android.feature.organizationaccess.OrganizationCommand
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class Build68UiWiringTest {
    private class MemoryReceipts : AnalyticsConsentReceiptStore {
        var value: AnalyticsConsentReceipt? = null
        override fun read(principalId: String) = value
        override fun write(principalId: String, receipt: AnalyticsConsentReceipt) {
            value = receipt
        }
    }

    @Test
    fun analyticsConsentPersistsOnlyAnExactServerReceipt() = runTest {
        val authority = AnalyticsConsentAuthority("user", 4, true)
        val store = MemoryReceipts()
        var sent: AnalyticsConsentV2? = null
        val controller =
            AnalyticsConsentSettingsController(
                AnalyticsConsentSynchronizer {
                    sent = it
                    it.enabled
                },
                store,
                { authority },
            )
        val receipt = controller.change(authority, true, "uk", "1.0.2")
        assertTrue(receipt.enabled)
        assertEquals(receipt, store.value)
        assertEquals(AnalyticsConsentV2Contract.PRIVACY_VERSION, sent?.privacyVersion)
        assertEquals(AnalyticsConsentV2Contract.DISCLOSURE_VERSION, sent?.disclosureVersion)
    }

    @Test
    fun analyticsConsentFailureAndAccountChangeStayFailClosed() = runTest {
        val authority = AnalyticsConsentAuthority("user", 4, true)
        val store = MemoryReceipts()
        val rejected =
            AnalyticsConsentSettingsController(
                AnalyticsConsentSynchronizer { false },
                store,
                { authority },
            )
        var rejectedFailure = false
        try {
            rejected.change(authority, true, "de", "1.0.2")
        } catch (_: IllegalStateException) {
            rejectedFailure = true
        }
        assertTrue(rejectedFailure)
        assertNull(store.value)

        var current = authority
        val changed =
            AnalyticsConsentSettingsController(
                AnalyticsConsentSynchronizer {
                    current = authority.copy(revision = 5)
                    true
                },
                store,
                { current },
            )
        var cancelled = false
        try {
            changed.change(authority, true, "de", "1.0.2")
        } catch (_: CancellationException) {
            cancelled = true
        }
        assertTrue(cancelled)
        assertNull(store.value)
    }

    @Test
    fun organizationUpdateUsesShadowFallbackButEnforcedAccessFailsClosed() {
        fun snapshot(mode: String, command: Boolean, actions: Set<String>) =
            OrganizationAccessSnapshot(
                "user",
                "organization-actions-v1",
                mode == "enforced",
                mapOf("editInfo" to mode),
                mapOf(OrganizationCommand.UPDATE_INFO to command),
                mapOf("org" to OrganizationAccessRecord("org", actions)),
                Instant.MAX,
            )
        assertEquals(
            OrganizationInformationRoute.LEGACY,
            organizationInformationRoute(snapshot("shadow", false, emptySet()), "org"),
        )
        assertEquals(
            OrganizationInformationRoute.DENIED,
            organizationInformationRoute(snapshot("enforced", false, setOf("editInfo")), "org"),
        )
        assertEquals(
            OrganizationInformationRoute.DENIED,
            organizationInformationRoute(snapshot("enforced", true, emptySet()), "org"),
        )
        assertEquals(
            OrganizationInformationRoute.CALLABLE,
            organizationInformationRoute(snapshot("enforced", true, setOf("editInfo")), "org"),
        )
    }
}
