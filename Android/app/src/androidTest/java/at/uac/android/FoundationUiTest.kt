package at.uac.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalEnvironment
import com.google.firebase.FirebaseApp
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class FoundationUiTest {
    @get:Rule val compose = createAndroidComposeRule<FoundationActivity>()

    @Test
    fun languageAndActivityRecreation() {
        compose.onNodeWithTag("language-uk").performScrollTo().performClick().assertIsSelected()
        // This retained package-1 diagnostic has explanatory cards before its scrollable content.
        // At actual system font200 the translated title is below the fold, not missing.
        compose.onNodeWithText("Разом в Австрії").performScrollTo().assertIsDisplayed()
        compose.activityRule.scenario.recreate()
        compose.onNodeWithTag("language-uk").performScrollTo().assertIsSelected()
        compose.onNodeWithText("Разом в Австрії").performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("language-de").performScrollTo().performClick().assertIsSelected()
        compose.onNodeWithText("Gemeinsam in Österreich").performScrollTo().assertIsDisplayed()
        val apps = FirebaseApp.getApps(compose.activity)
        assertFalse(apps.any { it.name == FirebaseApp.DEFAULT_APP_NAME })
        assertTrue(apps.all { it.options.projectId == LocalEnvironment.PROJECT_ID })
    }

    @Test
    fun localEmulatorReadOrOfflineRecovery() {
        compose.onNodeWithTag("language-de").performClick()
        compose.onNodeWithTag("mode-emulator").performClick()
        val expectOnline =
            InstrumentationRegistry.getArguments().getString("expectEmulator") == "true"
        if (expectOnline) {
            compose.waitUntil(12_000) {
                compose
                    .onAllNodesWithText("Lokaler Firebase-Test")
                    .fetchSemanticsNodes()
                    .isNotEmpty()
            }
            compose.onNodeWithText("Lokaler Firebase-Test").performScrollTo().assertIsDisplayed()
        } else {
            compose.waitUntil(12_000) {
                compose.onAllNodesWithTag("error").fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithTag("retry").performScrollTo().performClick()
            compose.waitUntil(12_000) {
                compose.onAllNodesWithTag("error").fetchSemanticsNodes().isNotEmpty()
            }
        }
        compose.onNodeWithTag("mode-synthetic").performScrollTo().performClick()
        compose.onNodeWithText("Gemeinsam in Österreich").performScrollTo().assertIsDisplayed()
    }
}
