package at.uac.android

import androidx.compose.ui.test.assertIsDisplayed
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
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DirectoryEditorUiTest {
    @get:Rule val compose = createComposeRule()

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
}
