package at.uac.android

import android.graphics.Bitmap
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.design.*
import at.uac.android.feature.directory.*
import java.io.File
import java.time.Instant
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class DirectoryCompact112UiTest {
    @get:Rule val compose = createComposeRule()
    private val longUk = "Екстрена допомога та важливі контакти для вашої безпеки в Австрії"
    private val longDe = "Notfallhilfe und wichtige Kontakte für Ihre Sicherheit in Österreich"
    private fun entry(id: Int) = DirectoryRecentItem("compact$id", "topic", "safety", "emergency", null, null,
        Instant.parse("2026-10-18T08:00:00Z"), 1,
        DirectoryText(if (id == 1) longUk else "Важливі контакти $id", if (id == 1) longDe else "Wichtige Kontakte $id"),
        DirectoryText("Екстрена допомога", "Notfallhilfe"), DirectoryText("Безпека", "Sicherheit"))

    @Test fun compactRowsThemesLanguagesAndRealReaderRoundTrip() {
        val language = mutableStateOf("uk")
        val theme = mutableStateOf("light")
        val route = mutableStateOf("directory")
        val history = mutableListOf<String>()
        var requests = 0
        val model = DirectoryRecentViewModel { requests++; DirectoryRecentPage((1..4).map(::entry), null, false) }
        compose.setContent { UacTheme(theme.value) {
            UacPageBackground(Modifier.fillMaxSize()) {
                Column(Modifier.fillMaxSize()) {
                    TextButton({ route.value = history.removeAt(history.lastIndex) }, enabled = history.isNotEmpty(),
                        modifier = Modifier.testTag("test-back")) { Text("Back") }
                    Box(Modifier.weight(1f)) {
                        DirectoryDestination(route.value, language.value, "", {}, {
                            history.add(route.value); route.value = it
                        }, { _, _, _ -> }, recentModel = model)
                    }
                }
            }
        } }
        compose.waitUntil(10_000) { model.state.value.loaded }
        for (lang in listOf("uk", "de")) for (appearance in listOf("light", "dark")) {
            compose.runOnIdle { language.value = lang; theme.value = appearance }
            compose.onNodeWithTag("directory-list").performScrollToNode(hasTestTag("directory-recent-show-all"))
            compose.onNodeWithTag("directory-recent-preview").assertIsDisplayed()
            for (id in 1..3) compose.onNodeWithTag("directory-recent-compact$id").assertIsDisplayed().assertHeightIsAtLeast(48.dp)
            compose.onNodeWithTag("directory-recent-compact4").assertDoesNotExist()
            val title = if (lang == "uk") longUk else longDe
            compose.onNodeWithTag("directory-recent-compact1").assert(
                SemanticsMatcher.expectValue(SemanticsProperties.Text, listOf(androidx.compose.ui.text.AnnotatedString(title))))
            val layouts = mutableListOf<TextLayoutResult>()
            compose.onNodeWithText(title, useUnmergedTree = true).performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            assertEquals(1, layouts.single().lineCount)
            assertTrue("Long title should be ellipsized", layouts.single().isLineEllipsized(0))
            compose.onNodeWithTag("directory-recent-show-all").assertHeightIsAtLeast(48.dp)
            compose.onNodeWithTag("directory-recent-refresh").assertDoesNotExist()
            compose.onNodeWithText("18.10.2026 · 10:00").assertDoesNotExist()
            capture("compact112-$lang-$appearance.png")
        }
        // A compact row opens the actual reader, Back restores the same preview.
        compose.onNodeWithTag("directory-recent-compact1").performClick()
        compose.waitUntil(10_000) { compose.onAllNodesWithTag("directory-section-choose").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("directory-section-choose").assertExists()
        compose.onNodeWithTag("test-back").performClick()
        compose.onNodeWithTag("directory-list").performScrollToNode(hasTestTag("directory-recent-show-all"))
        compose.onNodeWithTag("directory-recent-show-all").performClick()
        compose.onNodeWithTag("directory-recent-list").performScrollToNode(hasTestTag("directory-recent-compact4"))
        compose.onNodeWithTag("directory-recent-compact4").assertIsDisplayed().performClick()
        compose.waitUntil(10_000) { compose.onAllNodesWithTag("directory-section-choose").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("test-back").performClick()
        compose.onNodeWithTag("directory-recent-list").assertExists()
        assertEquals(1, requests)
        compose.onNodeWithTag("test-back").performClick()
        compose.onNodeWithTag("directory-list").assertExists()
    }
    private fun capture(name: String) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        File(context.cacheDir, name).outputStream().use {
            compose.onRoot().captureToImage().asAndroidBitmap().compress(Bitmap.CompressFormat.PNG, 100, it)
        }
    }
}
