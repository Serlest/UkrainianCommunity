package at.uac.android

import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onAllNodesWithTag
import at.uac.android.feature.analyticsconsent.AnalyticsConsentAuthority
import at.uac.android.feature.analyticsconsent.AnalyticsConsentReceipt
import at.uac.android.feature.analyticsconsent.AnalyticsConsentReceiptStore
import at.uac.android.feature.analyticsconsent.AnalyticsConsentSettings
import at.uac.android.feature.analyticsconsent.AnalyticsConsentSettingsController
import at.uac.android.feature.analyticsconsent.AnalyticsConsentSynchronizer
import at.uac.android.feature.analyticsconsent.AnalyticsConsentV2Contract
import at.uac.android.feature.legalevidence.LegalEvidenceContent
import at.uac.android.feature.legalevidence.LegalEvidenceEvent
import java.time.Instant
import org.junit.Rule
import org.junit.Test

class Build68PrivacyLegalUiTest {
    @get:Rule val compose = createComposeRule()

    private class ReceiptStore(var value: AnalyticsConsentReceipt? = null) :
        AnalyticsConsentReceiptStore {
        override fun read(principalId: String) = value
        override fun write(principalId: String, receipt: AnalyticsConsentReceipt) {
            value = receipt
        }
    }

    @Test
    fun analyticsStartsFailClosedAndCannotChangeWithoutReadyAuthority() {
        val authority = AnalyticsConsentAuthority("user", 1, false)
        val controller =
            AnalyticsConsentSettingsController(
                AnalyticsConsentSynchronizer { error("must not send") },
                ReceiptStore(),
                { authority },
            )
        compose.setContent { AnalyticsConsentSettings(authority, "de", "1.0.2", controller) }
        compose.onNodeWithTag("analytics-consent-switch").assertIsOff().assertIsNotEnabled()
        compose.onAllNodesWithTag("analytics-consent-error").assertCountEquals(0)
    }

    @Test
    fun analyticsRendersOnlyConfirmedLocalReceiptAsEnabled() {
        val authority = AnalyticsConsentAuthority("user", 1, true)
        val store =
            ReceiptStore(
                AnalyticsConsentReceipt(
                    true,
                    "00000000-0000-0000-0000-000000000001",
                    AnalyticsConsentV2Contract.PRIVACY_VERSION,
                    AnalyticsConsentV2Contract.DISCLOSURE_VERSION,
                )
            )
        val controller =
            AnalyticsConsentSettingsController(
                AnalyticsConsentSynchronizer { it.enabled },
                store,
                { authority },
            )
        compose.setContent { AnalyticsConsentSettings(authority, "uk", "1.0.2", controller) }
        compose.onNodeWithTag("analytics-consent-switch").assertIsOn()
    }

    @Test
    fun legalEvidenceIsOwnerOnly() {
        compose.setContent {
            LegalEvidenceContent("target", false, emptyList(), false, "de")
        }
        compose.onNodeWithTag("legal-evidence-denied").assertIsDisplayed()
        compose.onAllNodesWithTag("legal-evidence-empty").assertCountEquals(0)
    }

    @Test
    fun legalEvidenceShowsDecodedEvents() {
        compose.setContent {
            LegalEvidenceContent(
                "target",
                true,
                listOf(
                    LegalEvidenceEvent(
                        "event-1",
                        "target",
                        "analyticsGranted",
                        Instant.parse("2026-09-07T12:00:00Z"),
                        "analyticsConsent",
                        emptyMap(),
                    )
                ),
                false,
                "uk",
            )
        }
        compose.onNodeWithTag("legal-evidence-event-event-1").assertIsDisplayed()
    }
}
