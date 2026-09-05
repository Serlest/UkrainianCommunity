package at.uac.android

import android.graphics.Bitmap
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.design.UacTheme
import at.uac.android.feature.auth.AuthLegalDocument
import at.uac.android.feature.auth.AuthLegalReader
import at.uac.android.feature.auth.formatLegalText
import java.io.File
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class LegalReaderFormattingUiTest {
    @get:Rule val compose = createComposeRule()

    private fun show(language: String, theme: String) {
        val heading =
            if (language == "uk") "Ваші права та приватність" else "Ihre Rechte und Privatsphäre"
        val paragraph =
            if (language == "uk") "Повний юридичний текст без скорочень."
            else "Vollständiger rechtlicher Text ohne Kürzung."
        val body =
            "# $heading\n\n**$paragraph**\n\n## Reference\n\n" +
                ("$paragraph\n").repeat(16) +
                "\nFinal reference."
        val document =
            AuthLegalDocument(
                "terms",
                "test-only-v1",
                true,
                mapOf(language to "Synthetic document"),
                mapOf(language to body),
            )
        var dismissed = 0
        compose.setContent {
            UacTheme(theme) {
                AuthLegalReader(document, language, reference = true) { dismissed++ }
            }
        }
        compose.waitUntil(15_000) { compose.onNodeWithTag("legal-close").isDisplayed() }
        compose
            .onNodeWithTag("legal-block-0")
            .performScrollTo()
            .assertTextEquals(heading)
            .assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
        compose.onNodeWithTag("legal-block-1").performScrollTo().assertTextEquals(paragraph)
        for (index in 0..4) {
            val layouts = mutableListOf<TextLayoutResult>()
            compose.onNodeWithTag("legal-block-$index").performScrollTo().performSemanticsAction(
                SemanticsActions.GetTextLayoutResult
            ) {
                it(layouts)
            }
            assertFalse(layouts.single().didOverflowWidth)
            assertFalse(layouts.single().didOverflowHeight)
            assertActualSystemFont(layouts.single())
        }
        compose
            .onNodeWithTag("legal-block-4")
            .assertTextEquals("Final reference.")
            .assertIsDisplayed()
        compose
            .onNodeWithTag("legal-close")
            .assertHeightIsAtLeast(48.dp)
            .assertIsDisplayed()
            .performClick()
        assertEquals(1, dismissed)
    }

    @Test fun germanLightDocumentKeepsSelectableCompleteParagraphs() = show("de", "light")

    @Test fun germanDarkDocumentRemainsCompleteAtActualSystemFont() = show("de", "dark")

    @Test fun ukrainianDocumentRemainsCompleteAtActualSystemFont() = show("uk", "light")

    private fun assertActualSystemFont(layout: TextLayoutResult) {
        val expected =
            InstrumentationRegistry.getInstrumentation()
                .targetContext
                .resources
                .configuration
                .fontScale
        assertEquals(
            "Dialog text must honor the actual Android font setting",
            expected,
            layout.layoutInput.density.fontScale,
            0.01f,
        )
        println("LEGAL_ACTUAL_FONT scale=${layout.layoutInput.density.fontScale}")
    }

    @Test
    fun veryLongDocumentTitleScrollsAwayWithoutObscuringTheLastParagraph() {
        val title = "Ausführliche Nutzungsbedingungen für die UkrainianCommunity ".repeat(4).trim()
        // A document shorter than the viewport legitimately leaves the end of its title visible.
        // Use a long body to prove that the title participates in the same scroll container.
        val body =
            "# Inhalt\n\n" +
                List(40) { "Vollständiger rechtlicher Absatz ${it + 1} ohne Kürzung." }
                    .joinToString("\n\n") +
                "\n\nLetzter Absatz."
        val lastBlock = formatLegalText(body).lastIndex
        val document =
            AuthLegalDocument(
                "terms",
                "test-only-v1",
                true,
                mapOf("de" to title),
                mapOf("de" to body),
            )
        var closed = false
        compose.setContent {
            UacTheme("light") {
                AuthLegalReader(document, "de", reference = false) { closed = true }
            }
        }
        compose.waitUntil(15_000) { compose.onNodeWithTag("legal-close").isDisplayed() }
        compose.onNodeWithTag("legal-document-title").assertTextEquals(title)
        val titleLayouts = mutableListOf<TextLayoutResult>()
        compose.onNodeWithTag("legal-document-title").performSemanticsAction(
            SemanticsActions.GetTextLayoutResult
        ) {
            it(titleLayouts)
        }
        assertActualSystemFont(titleLayouts.single())
        compose
            .onNodeWithTag("legal-block-$lastBlock")
            .performScrollTo()
            .assertTextEquals("Letzter Absatz.")
            .assertIsDisplayed()
        try {
            compose.onNodeWithTag("legal-document-title").assertIsNotDisplayed()
        } catch (error: AssertionError) {
            val titleBounds =
                compose.onNodeWithTag("legal-document-title").getUnclippedBoundsInRoot()
            val lastBounds =
                compose.onNodeWithTag("legal-block-$lastBlock").getUnclippedBoundsInRoot()
            val viewport = compose.onNodeWithTag("legal-content").getUnclippedBoundsInRoot()
            val instrumentation = InstrumentationRegistry.getInstrumentation()
            instrumentation.uiAutomation.takeScreenshot()?.let { bitmap ->
                try {
                    File(
                            instrumentation.targetContext.externalCacheDir,
                            "legal-long-title-diagnostic.png",
                        )
                        .outputStream()
                        .use {
                            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
                        }
                } finally {
                    bitmap.recycle()
                }
            }
            throw AssertionError(
                "Legal title scroll geometry title=$titleBounds last=$lastBounds viewport=$viewport",
                error,
            )
        }
        compose
            .onNodeWithTag("legal-close")
            .assertHeightIsAtLeast(48.dp)
            .assertIsDisplayed()
            .performClick()
        assertTrue(closed)
    }
}
