package at.uac.android

import at.uac.android.feature.auth.AuthLegalDocument
import java.security.MessageDigest

internal fun build80LegalFixture(document: AuthLegalDocument): Map<String, Any> {
    fun hash(value: String) =
        MessageDigest.getInstance("SHA-256").digest(value.toByteArray()).joinToString("") {
            "%02x".format(it)
        }
    val locales =
        document.texts.toSortedMap().mapValues { (locale, text) ->
            val markdown = text.replace("\r\n", "\n").trim()
            mapOf(
                "title" to document.title(locale).trim(),
                "contentMarkdown" to markdown,
                "contentText" to text,
                "contentHash" to hash(markdown),
            )
        }
    val canonical =
        locales.entries.joinToString("\n---\n") { (locale, row) ->
            listOf(
                    locale,
                    row.getValue("title"),
                    row.getValue("contentMarkdown"),
                    row.getValue("contentHash"),
                )
                .joinToString("\n")
        }
    return mapOf(
        "version" to document.version,
        "documentType" to document.type,
        "status" to "published",
        "requiresAcceptance" to document.requiresAcceptance,
        "locales" to locales,
        "contentHash" to hash(canonical),
    )
}
