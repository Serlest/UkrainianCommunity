package at.uac.android

import at.uac.android.feature.auth.*
import org.junit.Assert.*
import org.junit.Test

class LegalTextFormattingTest {
    @Test
    fun headingAndEmphasisKeepTheLegalWordsAndPunctuation() {
        val blocks =
            formatLegalText(
                "# Bedingungen\n\n## Anbieter\n\nKontakt: **Synthetic Owner**, Wien.\nZweite Zeile."
            )
        assertEquals(
            listOf("Bedingungen", "Anbieter", "Kontakt: Synthetic Owner, Wien.\nZweite Zeile."),
            blocks.map { it.text },
        )
        assertEquals(listOf(1, 2, 0), blocks.map { it.headingLevel })
        assertEquals("Synthetic Owner", blocks.last().runs.single { it.strong }.text)
    }

    @Test
    fun ukrainianTextAndMultipleEmphasisRangesRemainComplete() {
        val body = "Важливо: **ваші права** та **ваша приватність**."
        val block = formatLegalText(body).single()
        assertEquals("Важливо: ваші права та ваша приватність.", block.text)
        assertEquals(
            listOf("ваші права", "ваша приватність"),
            block.runs.filter { it.strong }.map { it.text },
        )
    }

    @Test
    fun plainTextAndUnmatchedMarkersAreNotDiscarded() {
        for (text in
            listOf(
                "Plain reference.",
                "#not-a-heading",
                "####### Seven",
                "Keep **unclosed",
                "Keep **** literal",
                "**across\nlines**",
            )) {
            assertEquals(text, formatLegalText(text).single().text)
        }
    }

    @Test
    fun urlsHtmlAndCodeStayInertLiteralText() {
        val text = "[External](https://example.invalid/path) <script>no()</script> `literal`"
        assertEquals(text, formatLegalText(text).single().text)
    }

    @Test
    fun limitsKeepTheFullOriginalInsteadOfTruncatingLegalContent() {
        for (text in listOf("# Header\n" + "x".repeat(262_144), "line\n".repeat(2_001))) {
            val blocks = formatLegalText(text)
            assertEquals(1, blocks.size)
            assertEquals(text, blocks.single().text)
            assertEquals(0, blocks.single().headingLevel)
        }
    }

    @Test
    fun emptyAndWhitespaceOnlyDocumentsAreNotInvented() {
        for (text in listOf("", "  ", "\n\n")) assertEquals(
            text,
            formatLegalText(text).single().text,
        )
    }
}
