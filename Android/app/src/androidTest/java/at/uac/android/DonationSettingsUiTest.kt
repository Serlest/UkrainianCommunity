package at.uac.android

import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import at.uac.android.design.UacTheme
import at.uac.android.feature.donationsettings.*
import at.uac.android.feature.moderation.ModerationSession
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class DonationSettingsUiTest {
    @get:Rule val compose = createComposeRule()
    private val owner = ModerationSession("synthetic-owner", 1, "owner", true)

    private fun capture(name: String) {
        compose.waitForIdle()
        val instrumentation =
            androidx.test.platform.app.InstrumentationRegistry.getInstrumentation()
        val screenshot = instrumentation.uiAutomation.takeScreenshot()
        java.io
            .File(instrumentation.targetContext.cacheDir, "build80-donation-$name.png")
            .outputStream()
            .use {
                screenshot.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
            }
        screenshot.recycle()
    }

    @Test
    fun editorKeepsBothLanguagesReachableAndDisablesRepeatSave() {
        val snapshot = DonationSnapshot(DonationDraft(), null, false)
        val state = mutableStateOf(DonationSettingsState(session = owner, baseline = snapshot))
        var writes = 0
        compose.setContent {
            UacTheme("dark") {
                DonationSettingsContent(
                    state.value,
                    "uk",
                    { state.value = state.value.copy(draft = it) },
                    {
                        writes++
                        state.value = state.value.copy(saving = true)
                    },
                    {},
                    {},
                    {},
                    {},
                )
            }
        }
        capture("uk-dark-top")
        compose
            .onNodeWithTag("donation-settings")
            .performScrollToNode(hasTestTag("donation-titleUK"))
        compose.onNodeWithTag("donation-titleUK").performTextReplacement("Підтримка проєкту")
        compose
            .onNodeWithTag("donation-settings")
            .performScrollToNode(hasTestTag("donation-titleDE"))
        compose.onNodeWithTag("donation-titleDE").performTextReplacement("Projekt unterstützen")
        compose.onNodeWithTag("donation-settings").performScrollToNode(hasTestTag("donation-save"))
        compose.onNodeWithTag("donation-save").performClick().assertIsNotEnabled()
        compose.runOnIdle { assertEquals(1, writes) }
    }

    @Test
    fun uncertainResultExposesReadbackAndBlocksAnotherSave() {
        val snapshot = DonationSnapshot(DonationDraft(), null, false)
        compose.setContent {
            UacTheme("light") {
                DonationSettingsContent(
                    DonationSettingsState(
                        session = owner,
                        baseline = snapshot,
                        draft = DonationDraft(url = "https://example.org"),
                        needsReadback = true,
                        problem = DonationProblem.UNCONFIRMED,
                    ),
                    "de",
                    {},
                    {},
                    {},
                    {},
                    {},
                    {},
                )
            }
        }
        compose.onNodeWithTag("donation-error").assertIsDisplayed()
        capture("de-light-readback")
        compose.onNodeWithTag("donation-settings").performScrollToNode(hasTestTag("donation-save"))
        compose.onNodeWithTag("donation-save").assertIsNotEnabled()
        compose
            .onNodeWithTag("donation-settings")
            .performScrollToNode(hasTestTag("donation-refresh"))
        compose.onNodeWithTag("donation-refresh").assertIsEnabled()
    }
}
