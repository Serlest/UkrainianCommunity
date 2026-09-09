package at.uac.android

import at.uac.android.feature.auth.*
import org.junit.Assert.*
import org.junit.Test

class LegalDocumentIntegrityTest {
    private fun document(legacy: Boolean = false): Map<String, Any> {
        val locales =
            listOf("de", "uk").associateWith {
                mapOf(
                    "title" to "Title $it",
                    "contentMarkdown" to "Body $it",
                    "contentText" to "Text $it",
                    "contentHash" to LegalDocumentIntegrity.sha256("Body $it"),
                )
            }
        val canonical =
            locales.entries.joinToString("\n---\n") { (key, row) ->
                (listOf(key, row.getValue("title"), row.getValue("contentMarkdown")) +
                        (if (legacy) listOf(row.getValue("contentText")) else emptyList()) +
                        row.getValue("contentHash"))
                    .joinToString("\n")
            }
        return mapOf(
            "documentType" to "terms",
            "version" to "1",
            "status" to "published",
            "locales" to locales,
            "contentHash" to LegalDocumentIntegrity.sha256(canonical),
        )
    }

    private val pointer = mapOf("activeVersion" to "1")

    @Test
    fun currentAndLegacyFormatsAreAcceptedButTamperingIsRejected() {
        for (legacy in listOf(false, true)) {
            val data = document(legacy)
            LegalDocumentIntegrity.validate("terms", "1", pointer, data)
            for (key in listOf("contentHash", "locales", "version", "status", "documentType")) {
                assertThrows(AuthException::class.java) {
                    LegalDocumentIntegrity.validate(
                        "terms",
                        "1",
                        pointer,
                        data + (key to "tampered"),
                    )
                }
            }
            assertThrows(AuthException::class.java) {
                LegalDocumentIntegrity.validate(
                    "terms",
                    "1",
                    pointer + ("contentHash" to "wrong"),
                    data,
                )
            }
            assertThrows(AuthException::class.java) {
                LegalDocumentIntegrity.validate("terms", "1", pointer, data - "contentHash")
            }
        }
    }

    @Test
    fun localeBodyCannotBeChangedUnderTheOriginalHash() {
        val data = document()
        val locales = data["locales"] as Map<String, Map<String, String>>
        val bad = locales + ("de" to (locales.getValue("de") + ("contentMarkdown" to "changed")))
        assertThrows(AuthException::class.java) {
            LegalDocumentIntegrity.validate("terms", "1", pointer, data + ("locales" to bad))
        }
    }

    @Test
    fun shaMatchesKnownUtf8Vector() {
        assertEquals(
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            LegalDocumentIntegrity.sha256("abc"),
        )
    }
}
