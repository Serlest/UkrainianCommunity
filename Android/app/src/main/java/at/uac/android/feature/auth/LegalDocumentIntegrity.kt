package at.uac.android.feature.auth

import java.security.MessageDigest

/** Both canonical formats are used by published UAC legal documents. */
internal object LegalDocumentIntegrity {
    fun sha256(text: String): String =
        MessageDigest.getInstance("SHA-256").digest(text.toByteArray(Charsets.UTF_8)).joinToString(
            ""
        ) {
            "%02x".format(it)
        }

    fun validate(
        type: String,
        version: String,
        pointer: Map<String, Any?>,
        data: Map<String, Any?>,
    ) {
        fun requireValid(value: Boolean) {
            if (!value) throw AuthException(AuthProblem.INVALID_PROFILE)
        }
        requireValid(pointer["activeVersion"] == version)
        val parts = version.split('.')
        val numericVersion =
            if (Regex("[0-9]{4}\\.[1-9][0-9]?").matches(version))
                parts[0].toLong() * 100 + parts[1].toLong()
            else null
        requireValid(
            numericVersion != null &&
                (pointer["versionNumber"] as? Number)?.toLong() == numericVersion &&
                (data["versionNumber"] as? Number)?.toLong() == numericVersion
        )
        for (fields in listOf(pointer, data)) {
            requireValid(fields["documentType"] == null || fields["documentType"] == type)
            requireValid(fields["status"] == null || fields["status"] == "published")
        }
        requireValid(data["status"] == "published" && data["version"] == version)
        for (key in listOf("versionNumber", "requiresAcceptance", "defaultLocale", "contentHash")) {
            requireValid(pointer[key] == null || pointer[key] == data[key])
        }
        val locales =
            data["locales"] as? Map<*, *> ?: throw AuthException(AuthProblem.INVALID_PROFILE)
        val keys = locales.keys.filterIsInstance<String>().sorted()
        requireValid(keys.size == locales.size && keys.containsAll(listOf("de", "uk")))
        requireValid(keys.all { it == it.lowercase() })
        requireValid((data["defaultLocale"] ?: "uk") in keys)
        requireValid(data["canonicalLocale"] == null || data["canonicalLocale"] in keys)
        val current = mutableListOf<String>()
        val legacy = mutableListOf<String>()
        for (key in keys) {
            val locale =
                locales[key] as? Map<*, *> ?: throw AuthException(AuthProblem.INVALID_PROFILE)
            val title = (locale["title"] as? String).orEmpty().trim()
            val markdown =
                (locale["contentMarkdown"] as? String).orEmpty().replace("\r\n", "\n").trim()
            val hash = sha256(markdown)
            requireValid(
                title.isNotBlank() && markdown.isNotBlank() && locale["contentHash"] == hash
            )
            current += listOf(key, title, markdown, hash).joinToString("\n")
            legacy +=
                listOf(key, title, markdown, (locale["contentText"] as? String).orEmpty(), hash)
                    .joinToString("\n")
        }
        requireValid(
            data["contentHash"] in
                setOf(
                    sha256(current.joinToString("\n---\n")),
                    sha256(legacy.joinToString("\n---\n")),
                )
        )
    }
}
