package at.uac.android

import androidx.compose.foundation.layout.Column
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import at.uac.android.design.UacTheme
import at.uac.android.feature.browse.*
import at.uac.android.feature.directory.DirectorySource
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class ExternalLinkAuditUiTest {
    @get:Rule val compose = createComposeRule()

    @Test fun httpBannerActionAndHttpsDirectoryPortReachExplicitConfirmation() {
        var taps = 0
        compose.setContent { UacTheme("light") { Column {
            BannerHero(Banner("http-banner", mapOf("title" to "Banner", "imageURL" to "",
                "actionType" to "externalURL", "externalURL" to "http://example.org/banner")), "de", {}, onTap = { taps++ })
            SafeLink("Directory source", "https://example.org:8443/source", "de",
                policy = WebLinkPolicy.DIRECTORY_SOURCE)
            SafeLink("Unicode source", DirectorySource("IDN", "https://bücher.example:8443/path").safeUrl!!,
                "de", policy = WebLinkPolicy.DIRECTORY_SOURCE)
        } } }
        compose.onNodeWithTag("banner-open").performClick()
        compose.onNodeWithText("http://example.org/banner").assertIsDisplayed()
        assertEquals(1, taps)
        compose.onNodeWithText("Schließen").performClick()
        compose.onNodeWithText("Unicode source").performClick()
        compose.onNodeWithText("https://xn--bcher-kva.example:8443/path").assertIsDisplayed()
        compose.onNodeWithText("Schließen").performClick()
        compose.onNodeWithText("Directory source").performClick()
        compose.onNodeWithText("https://example.org:8443/source").assertIsDisplayed()
        compose.onNodeWithText("Öffnen").assertIsEnabled()
        compose.onNodeWithText("Schließen").performClick()
    }
}
