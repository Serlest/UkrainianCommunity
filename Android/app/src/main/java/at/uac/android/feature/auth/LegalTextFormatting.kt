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
    for (line in original.lineSequence()) {
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
