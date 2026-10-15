package at.uac.android

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTextReplacement
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.design.UacTheme
import at.uac.android.feature.directory.DirectoryCatalog
import at.uac.android.feature.directory.DirectoryDraftValidation
import at.uac.android.feature.directory.DirectoryEditorAccess
import at.uac.android.feature.directory.DirectoryEditorScreen
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DirectoryEditorUiTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun normalizationCoversArticleSectionAndRegionalSourcesBeforeValidation() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val category = DirectoryCatalog.bundled(context).first { it.id == "safety" }
        val root = JSONObject(category.rawJson)
        val topic = root.getJSONArray("topics").getJSONObject(0)
        fun source(url: String) = JSONObject().put("name", "Example").put("url", url)
        topic.put("sources", JSONArray().put(source("serlest.com/path?x=1")))
        val section = topic.getJSONArray("sections").getJSONObject(0)
        section.put("source", source("http://serlest.com/section?x=1"))
        val regional = JSONObject(section.toString()).put("id", "regional-source-test")
            .put("source", source("serlest.com/region?next=https://example.com/a"))
        topic.getJSONObject("regionalSections").put("wien", JSONArray().put(regional))

        val normalized = JSONObject(DirectoryDraftValidation.normalizedPayload(root.toString()))
        val normalizedTopic = normalized.getJSONArray("topics").getJSONObject(0)
        assertEquals("https://serlest.com/path?x=1",
            normalizedTopic.getJSONArray("sources").getJSONObject(0).getString("url"))
        assertEquals("https://serlest.com/section?x=1",
            normalizedTopic.getJSONArray("sections").getJSONObject(0).getJSONObject("source").getString("url"))
        assertEquals("https://serlest.com/region?next=https://example.com/a",
            normalizedTopic.getJSONObject("regionalSections").getJSONArray("wien").getJSONObject(0)
                .getJSONObject("source").getString("url"))
        assertNull(DirectoryDraftValidation.firstIssue(normalized.toString()))

        topic.getJSONArray("sources").put(source("https://serlest.com/path?x=1"))
        assertEquals("sources.duplicate:${topic.getString("id")}",
            DirectoryDraftValidation.firstIssue(root.toString()))
    }

    @Test
    fun ownerDraftPublishesBilingualChangeWithExpectedRevision() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val category = DirectoryCatalog.bundled(context).first { it.id == "safety" }
        var submitted: Triple<String, String, Int>? = null
        var destination: String? = null
        val access = object : DirectoryEditorAccess {
            override val uid = "fixture-owner"
            override val owner = true
            override suspend fun publish(categoryId: String, payload: String, expectedRevision: Int): Int {
                submitted = Triple(categoryId, payload, expectedRevision)
                return expectedRevision + 1
            }
            override suspend fun delete(categoryId: String, expectedRevision: Int): Int =
                error("Deletion was not requested")
        }
        compose.setContent {
            UacTheme("light") {
                DirectoryEditorScreen("safety", "de", listOf(category), mapOf("safety" to 4), access) {
                    destination = it
                }
            }
        }
        compose.onNodeWithTag("directory-editor-category-title-de")
            .performTextReplacement("Sicherheit und Schutz")
        compose.waitForIdle()
        compose.onNodeWithTag("directory-editor")
            .performScrollToNode(hasTestTag("directory-publish"))
        compose.onNodeWithTag("directory-publish").performClick()
        compose.waitUntil(10_000) { submitted != null }
        val result = submitted!!
        assertEquals("safety", result.first)
        assertEquals(4, result.third)
        assertNull(DirectoryDraftValidation.firstIssue(result.second))
        assertEquals("Sicherheit und Schutz",
            org.json.JSONObject(result.second).getJSONObject("title").getString("german"))
        compose.waitUntil(10_000) { destination == "directory/manage" }
    }

    @Test
    fun newCategoryRequiresCompleteBilingualGuideAndOfficialSourceBeforePublish() {
        var submitted: Triple<String, String, Int>? = null
        var destination: String? = null
        val access = object : DirectoryEditorAccess {
            override val uid = "fixture-owner"
            override val owner = true
            override suspend fun publish(categoryId: String, payload: String, expectedRevision: Int): Int {
                submitted = Triple(categoryId, payload, expectedRevision)
                return 1
            }
            override suspend fun delete(categoryId: String, expectedRevision: Int): Int =
                error("Deletion was not requested")
        }
        compose.setContent {
            UacTheme("light") {
                DirectoryEditorScreen("new-start", "de", emptyList(), emptyMap(), access) {
                    destination = it
                }
            }
        }
        fun fill(tag: String, value: String) {
            compose.onNodeWithTag("directory-editor").performScrollToNode(hasTestTag(tag))
            compose.onNodeWithTag(tag).performTextReplacement(value)
        }
        fun open(tag: String) {
            compose.onNodeWithTag("directory-editor").performScrollToNode(hasTestTag(tag))
            compose.onNodeWithTag(tag).performClick()
        }
        fill("directory-editor-category-title-uk", "Новий розділ")
        fill("directory-editor-category-title-de", "Neuer Bereich")
        open("directory-publish")
        compose.onNodeWithTag("directory-editor")
            .performScrollToNode(hasTestTag("directory-editor-error"))
        compose.onNodeWithTag("directory-editor-error").assertExists()
        compose.onNodeWithTag("directory-editor-error").assertTextContains("Kurzbeschreibung", substring = true)
        assertNull(submitted)
        fill("directory-editor-category-summary-uk", "Корисна інформація")
        fill("directory-editor-category-summary-de", "Wichtige Informationen")
        open("directory-editor-open-group-0")
        fill("directory-editor-group-title-uk", "Підрозділ")
        fill("directory-editor-group-title-de", "Unterbereich")
        open("directory-editor-category-back")
        open("directory-editor-open-topic-0")
        fill("directory-editor-topic-title-uk", "Нова стаття")
        fill("directory-editor-topic-title-de", "Neuer Beitrag")
        fill("directory-editor-topic-summary-uk", "Вступ до статті")
        fill("directory-editor-topic-summary-de", "Einleitung zum Beitrag")
        open("directory-editor-open-section-0")
        fill("directory-editor-section-title-uk", "Інформація")
        fill("directory-editor-section-title-de", "Information")
        fill("directory-editor-section-body-uk", "Перевірений текст статті.")
        fill("directory-editor-section-body-de", "Geprüfter Beitragstext.")
        fill("directory-editor-section-source-name", "Offizielle Stelle")
        fill("directory-editor-section-source-url", "http://serlest.com/path?x=1")
        fill("directory-editor-section-source-name", "Offizielle Stelle")
        compose.onNodeWithTag("directory-editor-section-source-url")
            .assertTextContains("https://serlest.com/path?x=1", substring = true)
        fill("directory-editor-section-source-url", "serlest.com/path?x=1")
        open("directory-publish")
        compose.waitUntil(10_000) { submitted != null }
        val result = submitted!!
        assertTrue(result.first.startsWith("custom-"))
        assertEquals(0, result.third)
        assertNull(DirectoryDraftValidation.firstIssue(result.second))
        assertEquals(result.first, org.json.JSONObject(result.second).getString("id"))
        assertEquals("https://serlest.com/path?x=1",
            org.json.JSONObject(result.second).getJSONArray("topics").getJSONObject(0)
                .getJSONArray("sections").getJSONObject(0).getJSONObject("source").getString("url"))
        compose.waitUntil(10_000) { destination == "directory/manage" }
    }
}
