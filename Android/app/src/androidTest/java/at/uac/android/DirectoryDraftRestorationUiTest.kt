package at.uac.android

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.design.UacTheme
import at.uac.android.feature.directory.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

/** Android counterpart gate for adaptive draft preservation; no cloud publication or OS font changes. */
class DirectoryDraftRestorationUiTest {
    @get:Rule val compose = createComposeRule()
    private fun open(tag: String) {
        compose.onNodeWithTag("directory-editor").performScrollToNode(hasTestTag(tag))
        compose.onNodeWithTag(tag).performClick()
    }
    @Test fun editedSectionAndRevisionSurviveWidthChangeAndSavedStateRestorationBeforePublish() {
        val app = InstrumentationRegistry.getInstrumentation().targetContext
        val category = DirectoryCatalog.bundled(app).first { it.id == "safety" }
        val width = mutableStateOf(360.dp)
        var submitted: String? = null
        val access = object : DirectoryEditorAccess {
            override val uid = "release-fixture-editor"
            override val owner = false
            override suspend fun publish(categoryId: String, payload: String, expectedRevision: Int): Int {
                assertEquals("safety", categoryId)
                assertEquals(7, expectedRevision)
                submitted = payload
                return 8
            }
            override suspend fun delete(categoryId: String, expectedRevision: Int): Int = error("not requested")
        }
        val restoration = StateRestorationTester(compose)
        restoration.setContent { UacTheme("light") {
            Box(Modifier.width(width.value).fillMaxHeight()) {
                DirectoryEditorScreen("safety", "de", listOf(category), mapOf("safety" to 7), access) {}
            }
        } }
        open("directory-editor-open-topic-0")
        open("directory-editor-open-section-0")
        val field = "directory-editor-section-body-de"
        val value = "Testentwurf 110: Der eingegebene Text bleibt beim Ändern der Breite und nach Wiederherstellung erhalten."
        compose.onNodeWithTag("directory-editor").performScrollToNode(hasTestTag(field))
        compose.onNodeWithTag(field).performTextReplacement(value)
        compose.runOnIdle { width.value = 300.dp }
        compose.onNodeWithTag(field).assertTextContains(value)
        assertNull(submitted)
        restoration.emulateSavedInstanceStateRestore()
        compose.onNodeWithTag("directory-editor").performScrollToNode(hasTestTag(field))
        compose.onNodeWithTag(field).assertTextContains(value)
        assertNull(submitted)
        compose.runOnIdle { width.value = 360.dp }
        open("directory-publish")
        compose.waitUntil(10_000) { submitted != null }
        assertNull(DirectoryDraftValidation.firstIssue(submitted!!))
        val restored = DirectoryCatalog.parseCategory(JSONObject(submitted))
        assertEquals(value, restored.topics.first().sections.first().body.german)
    }
}
