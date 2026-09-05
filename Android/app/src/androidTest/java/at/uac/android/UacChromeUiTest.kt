package at.uac.android

import android.graphics.Bitmap
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.design.UacBottomNavigation
import at.uac.android.design.UacHeader
import at.uac.android.design.UacPageBackground
import at.uac.android.design.UacTheme
import at.uac.android.feature.browse.PrimaryTab
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class UacChromeUiTest {
    @get:Rule val compose = createComposeRule()
    private val taps = mutableListOf<PrimaryTab>()
    private var expectedScale = 1f

    private fun show(language: String, theme: String, fontScale: Float) {
        expectedScale = fontScale
        val selected = mutableStateOf(PrimaryTab.HOME)
        compose.setContent {
            val density = LocalDensity.current.density
            CompositionLocalProvider(LocalDensity provides Density(density, fontScale)) {
                UacTheme(theme) {
                    UacPageBackground(Modifier.fillMaxSize()) {
                        Box(Modifier.align(Alignment.TopCenter).statusBarsPadding()) {
                            UacHeader(language, true, {}, {})
                        }
                        Box(Modifier.align(Alignment.BottomCenter)) {
                            UacBottomNavigation(selected.value, language) {
                                taps += it
                                selected.value = it
                            }
                        }
                    }
                }
            }
        }
    }

    private fun assertReadableLabelsAndTouchTargets() {
        compose.assertNavigationPresentation(expectedScale)
        val layouts = linkedMapOf<PrimaryTab, TextLayoutResult>()
        PrimaryTab.entries.forEach { tab ->
            compose
                .onNodeWithTag("tab-${tab.route}")
                .assertIsDisplayed()
                .assertHeightIsAtLeast(48.dp)
            val results = mutableListOf<TextLayoutResult>()
            compose
                .onNodeWithTag("tab-label-${tab.route}", useUnmergedTree = true)
                .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(results) }
            assertEquals(1, results.size)
            layouts[tab] = results.single()
            val layout = results.single()
            // Geometry only: this isolated test renders public static labels, never account data.
            println(
                "CHROME_GEOMETRY ${tab.route}: size=${layout.size}, paragraph=${layout.multiParagraph.width}x${layout.multiParagraph.height}, lines=${layout.lineCount}, constraints=${layout.layoutInput.constraints}, bounds=${compose.onNodeWithTag("tab-${tab.route}").fetchSemanticsNode().boundsInRoot}"
            )
        }
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val screenshot = instrumentation.uiAutomation.takeScreenshot()
        val label = layouts.getValue(PrimaryTab.HOME).layoutInput.text.text
        java.io
            .File(
                instrumentation.targetContext.cacheDir,
                "chrome-geometry-${label}-${layouts.getValue(PrimaryTab.HOME).layoutInput.density.fontScale}.png",
            )
            .outputStream()
            .use { screenshot.compress(Bitmap.CompressFormat.PNG, 100, it) }
        screenshot.recycle()
        layouts.forEach { (tab, layout) ->
            assertFalse(
                "${tab.route} label must not clip horizontally: ${layout.size.width} < ${layout.multiParagraph.width}",
                layout.didOverflowWidth,
            )
            assertFalse("${tab.route} label must not clip vertically", layout.didOverflowHeight)
        }
        compose.onNodeWithTag("tab-news").assertDoesNotExist()
        compose.onNodeWithContentDescription("Ukrainian Community").assertIsDisplayed()
    }

    @Test
    fun germanLightFourTabsHaveSelectionAndFullLabels() {
        show("de", "light", 1f)
        assertReadableLabelsAndTouchTargets()
        compose.onNodeWithTag("tab-home").assertIsSelected()
        compose.onNodeWithTag("tab-events").performClick().assertIsSelected()
        compose.onNodeWithTag("tab-home").assertIsNotSelected()
        compose.runOnIdle { assertEquals(listOf(PrimaryTab.EVENTS), taps) }
    }

    @Test
    fun germanDarkAtTwoHundredPercentDoesNotClipLabels() {
        show("de", "dark", 2f)
        assertReadableLabelsAndTouchTargets()
        assertOneCallbackPerRealTabTap()
    }

    @Test
    fun ukrainianLightAtTwoHundredPercentDoesNotClipLabels() {
        show("uk", "light", 2f)
        assertReadableLabelsAndTouchTargets()
        assertOneCallbackPerRealTabTap()
    }

    private fun assertOneCallbackPerRealTabTap() {
        PrimaryTab.entries.forEachIndexed { index, tab ->
            compose.onNodeWithTag("tab-${tab.route}").performClick().assertIsSelected()
            compose.runOnIdle { assertEquals(PrimaryTab.entries.take(index + 1), taps) }
        }
    }
}
