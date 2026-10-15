package at.uac.android

import android.graphics.Bitmap
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.design.UacTheme
import at.uac.android.feature.directory.DirectoryCatalog
import at.uac.android.feature.directory.DirectoryDestination
import at.uac.android.feature.directory.DirectoryDraftValidation
import at.uac.android.feature.directory.directoryIcon
import at.uac.android.design.UacIcon
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DirectoryReaderUiTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun bundledCatalogMatchesCurrentIosSourceAndEveryVisibleGuideHasSources() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val categories = DirectoryCatalog.bundled(context)
        assertEquals(25, categories.size)
        assertEquals(145, categories.sumOf { it.topics.size })
        assertEquals(663, categories.sumOf { c -> c.topics.sumOf { it.sections.size } })
        assertTrue(categories.all { it.visible })
        assertEquals(25, categories.map { it.symbol }.distinct().size)
        assertEquals(25, categories.map { directoryIcon(it.symbol) }.distinct().size)
        val managed = DirectoryCatalog.parseCategory(JSONObject(categories.first().rawJson)
            .put("symbol", "new.future.symbol"))
        assertEquals("new.future.symbol", managed.symbol)
        assertEquals(UacIcon.DIRECTORY, directoryIcon(managed.symbol))
        categories.forEach { category ->
            assertEquals(category.id, null, DirectoryDraftValidation.firstIssue(category.rawJson))
            category.visibleGroups.forEach { group ->
                category.visibleTopics(group.id).forEach { topic ->
                    assertTrue("${category.id}/${topic.id}", topic.sections.any { !it.hidden })
                    assertTrue("${category.id}/${topic.id}", topic.sources.any { it.safeUrl != null })
                }
            }
        }
    }

    @Test
    fun opensCategoryGuideAndRegionalContentWithIndependentSearch() {
        val route = mutableStateOf("directory")
        val region = mutableStateOf("")
        compose.setContent {
            UacTheme("light") {
                DirectoryDestination(route.value, "uk", region.value,
                    { region.value = it }, { route.value = it }, { _, _, _ -> })
            }
        }
        screenshot("directory-root-api26.png")
        compose.onNodeWithTag("directory-list")
            .performScrollToNode(androidx.compose.ui.test.hasTestTag("directory-category-safety"))
        compose.onNodeWithTag("directory-category-safety").performClick()
        compose.onNodeWithTag("directory-list")
            .performScrollToNode(androidx.compose.ui.test.hasTestTag("directory-topic-emergency"))
        compose.onNodeWithText("Читати").assertDoesNotExist()
        compose.onNodeWithTag("directory-topic-emergency").performClick()
        compose.onNodeWithTag("directory-section-choose").assertExists()
        screenshot("directory-guide-api26.png")
    }

    @Test
    fun searchFindsGuideAndRegionShowsLocalSection() {
        val route = mutableStateOf("directory")
        val region = mutableStateOf("")
        compose.setContent {
            UacTheme("light") {
                DirectoryDestination(route.value, "de", region.value,
                    { region.value = it }, { route.value = it }, { _, _, _ -> },
                    searchVisible = true)
            }
        }
        compose.onNodeWithTag("directory-search").performTextInput("Gewalt")
        compose.onNodeWithTag("directory-browse-sections").assertDoesNotExist()
        compose.onNodeWithText("Häusliche Gewalt · Sicherheit & Schutz").performClick()
        assertEquals("directory/safety/domestic-violence", route.value)
        compose.onNodeWithTag("directory-list")
            .performScrollToNode(androidx.compose.ui.test.hasTestTag("directory-region"))
        compose.onNodeWithTag("directory-region").performClick()
        compose.onNodeWithTag("directory-region-burgenland").performClick()
        assertEquals("burgenland", region.value)
        compose.onNodeWithTag("directory-list")
            .performScrollToNode(androidx.compose.ui.test.hasTestTag("directory-section-regional-protection"))
    }

    private fun screenshot(name: String) {
        compose.waitForIdle()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val bitmap = compose.onRoot().captureToImage().asAndroidBitmap()
        java.io.File(instrumentation.targetContext.cacheDir, name).outputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        }
        bitmap.recycle()
    }
}
