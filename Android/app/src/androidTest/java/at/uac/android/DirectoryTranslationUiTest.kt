package at.uac.android

import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import at.uac.android.design.UacTheme
import at.uac.android.feature.translation.ContentTranslationButton
import at.uac.android.feature.translation.ContentTranslationSource
import at.uac.android.feature.translation.TranslationField
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class DirectoryTranslationUiTest {
    @get:Rule val compose = createComposeRule()

    @Test fun germanDirectoryTextIsReviewedBeforeUkrainianDraftChanges() {
        var request: Triple<String, String, List<String>>? = null
        var applied: Map<String, String>? = null
        val source = object : ContentTranslationSource {
            override suspend fun translate(kind: String, texts: List<String>, sourceLanguage: String): List<String> {
                request = Triple(kind, sourceLanguage, texts)
                return listOf("Назва")
            }
        }
        compose.setContent {
            UacTheme("light") {
                ContentTranslationButton(
                    kind = "directory", language = "de",
                    fields = listOf(TranslationField("title", "Titel", "Name", "", 100)),
                    enabled = true, sourceLanguage = "de", translationSource = source,
                ) { applied = it }
            }
        }
        compose.onNodeWithTag("translate-directory").performClick()
        compose.waitUntil(5_000) { request != null }
        assertEquals(Triple("directory", "de", listOf("Name")), request)
        assertEquals(null, applied)
        compose.onNodeWithTag("translation-apply").performClick()
        compose.waitUntil(5_000) { applied != null }
        assertEquals(mapOf("title" to "Назва"), applied)
    }
}
