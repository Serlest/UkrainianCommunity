package at.uac.android

import at.uac.android.feature.auth.*
import org.junit.Assert.*
import org.junit.Test

class LegalDocumentDecodeTest {
    private fun document(text: Any?, markdown: Any?) =
        mapOf(
            "status" to "published",
            "version" to "test-v1",
            "locales" to
                mapOf(
                    "de" to
                        mapOf(
                            "title" to "Synthetic reference",
                            "contentText" to text,
                            "contentMarkdown" to markdown,
                        )
                ),
        )

    @Test
    fun emptyOptionalPlainTextUsesTheCompletePublishedMarkdown() {
        for (text in listOf(null, "", "   ", "\n")) {
            assertEquals(
                "# Complete\n\nReference.",
                decodeLegal("terms", "test-v1", document(text, "# Complete\n\nReference."))
                    .text("de"),
            )
        }
    }

    @Test
    fun nonemptyPlainTextKeepsItsPublishedPrecedence() {
        assertEquals(
            "Plain reference",
            decodeLegal("terms", "test-v1", document("Plain reference", "Other markdown"))
                .text("de"),
        )
    }

    @Test
    fun missingBothBodiesNeverCreatesAnAcceptableEmptyDocument() {
        assertThrows(AuthException::class.java) {
            decodeLegal("terms", "test-v1", document("", "  "))
        }
    }
}
