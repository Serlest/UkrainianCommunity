package at.uac.android.feature.dsaappeal

import at.uac.android.feature.dsastatement.DsaStatementContract
import java.time.Instant
import java.time.format.DateTimeFormatterBuilder

enum class DsaAppealTextFailure {
    INVALID,
    TOO_LONG,
    TOO_SHORT,
    RESPONSE,
}

class DsaAppealTextException(val failure: DsaAppealTextFailure) : Exception(failure.name)

/** Injectable only for deterministic policy tests. Android callers use the ICU adapter. */
fun interface DsaAppealCharacterCounter {
    fun count(text: String): Int
}

class DsaAppealReviewedText
internal constructor(
    val reason: String,
    val logicalCharacters: Int,
    val normalizationChanged: Boolean,
) {
    override fun toString() = "DsaAppealReviewedText(<redacted>)"
}

/** A decoded response is not proof of an owned dispatch or an idempotency receipt. */
data class DsaAppealResponse(
    val reportId: String,
    val caseNumber: String,
    val submittedAt: Instant,
) {
    override fun toString() = "DsaAppealResponse(<redacted>)"
}

/** Pure, inert contract. No SDK, journal, retry, portal or action enablement. */
object DsaAppealContract {
    const val MAX_REASON_UTF16 = 5_000
    const val MAX_RAW_UTF16 = 65_536
    const val MIN_LOGICAL_CHARACTERS = 20
    private val responseKeys = setOf("reportId", "caseNumber", "status", "submittedAt")
    private val wireTime =
        Regex("[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3}Z")
    private val wireFormatter = DateTimeFormatterBuilder().appendInstant(3).toFormatter()
    private val fixedWhitespace =
        setOf(' ', '\u00A0', '\u1680', '\u2028', '\u2029', '\u202F', '\u205F', '\u3000', '\uFEFF')

    private fun fail(value: DsaAppealTextFailure = DsaAppealTextFailure.INVALID): Nothing =
        throw DsaAppealTextException(value)

    private fun validUnicode(text: String): Boolean {
        var index = 0
        while (index < text.length) {
            val char = text[index++]
            if (Character.isHighSurrogate(char)) {
                if (index == text.length || !Character.isLowSurrogate(text[index++])) return false
            } else if (Character.isLowSurrogate(char)) return false
        }
        return true
    }

    // ECMAScript \s, as used by the existing callable, NOT Kotlin Char.isWhitespace.
    private fun serverWhitespace(char: Char): Boolean =
        char in '\u0009'..'\u000D' || char in '\u2000'..'\u200A' || char in fixedWhitespace

    fun normalize(raw: String): String {
        if (raw.length > MAX_RAW_UTF16) fail(DsaAppealTextFailure.TOO_LONG)
        if (!validUnicode(raw)) fail()
        val result = StringBuilder()
        var separator = false
        for (char in raw) {
            if (serverWhitespace(char)) {
                separator = result.isNotEmpty()
            } else {
                // A deliberate stricter client subset: unsupported control characters are never
                // silently removed from a legal explanation.
                if (char.isISOControl()) fail()
                if (separator) result.append(' ')
                separator = false
                result.append(char)
                if (result.length > MAX_REASON_UTF16) fail(DsaAppealTextFailure.TOO_LONG)
            }
        }
        return result.toString().also { if (it.isEmpty()) fail() }
    }

    fun review(raw: String, counter: DsaAppealCharacterCounter): DsaAppealReviewedText {
        val normalized = normalize(raw)
        val characters = counter.count(normalized)
        if (characters !in 1..normalized.codePointCount(0, normalized.length)) fail()
        // Count the exact text the server will store, not whitespace that it will collapse.
        if (characters < MIN_LOGICAL_CHARACTERS) fail(DsaAppealTextFailure.TOO_SHORT)
        return DsaAppealReviewedText(normalized, characters, normalized != raw)
    }

    fun payload(reportId: String, reviewed: DsaAppealReviewedText): Map<String, String> {
        if (
            !DsaStatementContract.validId(reportId) ||
                normalize(reviewed.reason) != reviewed.reason ||
                reviewed.logicalCharacters !in
                    MIN_LOGICAL_CHARACTERS..reviewed.reason.codePointCount(
                            0,
                            reviewed.reason.length,
                        )
        )
            fail()
        return mapOf("reportId" to reportId, "reason" to reviewed.reason)
    }

    fun response(reportId: String, caseNumber: String, data: Any?): DsaAppealResponse {
        fun responseFailure(): Nothing = fail(DsaAppealTextFailure.RESPONSE)
        if (
            !DsaStatementContract.validId(reportId) ||
                caseNumber.isBlank() ||
                caseNumber.length > 200 ||
                !validUnicode(caseNumber) ||
                caseNumber.any(Char::isISOControl)
        )
            responseFailure()
        val fields = data as? Map<*, *> ?: responseFailure()
        if (
            fields.keys != responseKeys ||
                fields["reportId"] != reportId ||
                fields["caseNumber"] != caseNumber ||
                fields["status"] != "appealed"
        )
            responseFailure()
        val time = fields["submittedAt"] as? String ?: responseFailure()
        if (!wireTime.matches(time)) responseFailure()
        val instant =
            try {
                Instant.parse(time)
            } catch (_: Exception) {
                responseFailure()
            }
        if (
            instant < Instant.parse("0001-01-01T00:00:00Z") || wireFormatter.format(instant) != time
        )
            responseFailure()
        return DsaAppealResponse(reportId, caseNumber, instant)
    }
}
