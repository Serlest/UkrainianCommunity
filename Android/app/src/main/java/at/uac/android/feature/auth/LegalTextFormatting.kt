package at.uac.android.feature.auth

data class LegalTextRun(val text: String, val strong: Boolean = false)

data class LegalTextBlock(val runs: List<LegalTextRun>, val headingLevel: Int = 0) {
    val text: String
        get() = runs.joinToString("") { it.text }
}

/**
 * Presentation only: headings and paired emphasis, never HTML, URL execution or legal-content
 * rewriting.
 */
fun formatLegalText(original: String): List<LegalTextBlock> {
    if (original.length > 262_144 || original.count { it == '\n' } > 2_000) {
        // Keep the complete original readable rather than truncating a legal document or creating
        // thousands of nodes.
        return listOf(LegalTextBlock(listOf(LegalTextRun(original))))
    }
    val result = mutableListOf<LegalTextBlock>()
    val paragraph = mutableListOf<String>()
    fun flush() {
        if (paragraph.isNotEmpty()) {
            result += LegalTextBlock(legalEmphasis(paragraph.joinToString("\n")))
            paragraph.clear()
        }
    }
    val lines = original.lines()
    var index = 0
    fun cells(line: String): List<String>? {
        val value = line.trim()
        if (!value.startsWith("|") || !value.endsWith("|") || "\\|" in value) return null
        return value.removePrefix("|").removeSuffix("|").split('|').map(String::trim)
    }
    while (index < lines.size) {
        val line = lines[index]
        val headers = cells(line)
        val separator = lines.getOrNull(index + 1)?.let(::cells)
        if (
            headers != null &&
                headers.size > 1 &&
                separator?.size == headers.size &&
                separator.all { it.matches(Regex(":?-{3,}:?")) }
        ) {
            var end = index + 2
            val rows = mutableListOf<List<String>>()
            while (end < lines.size && lines[end].trim().startsWith("|")) {
                rows += cells(lines[end]).orEmpty()
                end++
            }
            if (rows.isNotEmpty() && rows.all { it.size == headers.size }) {
                flush()
                rows.forEach { row ->
                    val runs = mutableListOf<LegalTextRun>()
                    headers.indices.forEach { column ->
                        if (column > 0) runs += LegalTextRun("\n")
                        runs += legalEmphasis(headers[column]).map { it.copy(strong = true) }
                        runs += LegalTextRun(": ")
                        runs += legalEmphasis(row[column])
                    }
                    result += LegalTextBlock(runs)
                }
                index = end
                continue
            }
        }
        index++
        val hashes = line.takeWhile { it == '#' }.length
        val heading =
            hashes in 1..6 && line.getOrNull(hashes) == ' ' && line.drop(hashes + 1).isNotBlank()
        when {
            line.isBlank() -> flush()
            heading -> {
                flush()
                result += LegalTextBlock(legalEmphasis(line.drop(hashes + 1)), hashes)
            }
            else -> paragraph += line
        }
    }
    flush()
    return result.ifEmpty { listOf(LegalTextBlock(listOf(LegalTextRun(original)))) }
}

private fun legalEmphasis(text: String): List<LegalTextRun> {
    val result = mutableListOf<LegalTextRun>()
    var cursor = 0
    while (cursor < text.length) {
        val start = text.indexOf("**", cursor)
        val end = if (start >= 0) text.indexOf("**", start + 2) else -1
        if (start < 0 || end <= start + 2 || '\n' in text.substring(start + 2, end)) {
            result += LegalTextRun(text.substring(cursor))
            break
        }
        if (start > cursor) result += LegalTextRun(text.substring(cursor, start))
        result += LegalTextRun(text.substring(start + 2, end), strong = true)
        cursor = end + 2
    }
    return result
}
