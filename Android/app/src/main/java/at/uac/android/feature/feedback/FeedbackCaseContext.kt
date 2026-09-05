package at.uac.android.feature.feedback

import java.time.Instant

/** Navigation hint only; fresh own SERVER review independently validates decision and deadline. */
fun FeedbackState.canReviewOwnDecision(): Boolean {
    val item = conversation?.item ?: return false
    return canReadCaseContext() &&
        audience == FeedbackAudience.OWN &&
        item.uid == session?.uid &&
        item.status in setOf(FeedbackStatus.CLOSED, FeedbackStatus.ARCHIVED) &&
        item.caseContext?.status == "decided" &&
        item.caseContext.appeal == null
}

/** Reporter/support projection from feedback only. Never pass this to an author's statement. */
data class FeedbackCaseContext(
    val caseNumber: String,
    val status: String,
    val category: String,
    val exactLocation: String,
    val illegalExplanation: String,
    val legalBasis: String?,
    val evidence: String?,
    val goodFaithConfirmed: Boolean,
    val acknowledgementAt: Instant,
    val preferredLanguage: String,
    val appeal: FeedbackCaseAppeal?,
) {
    override fun toString() = "FeedbackCaseContext(<redacted>)"
}

data class FeedbackCaseAppeal(val status: String, val reason: String, val outcome: String?) {
    override fun toString() = "FeedbackCaseAppeal(<redacted>)"
}

/** A display projection, not decision eligibility or a complete/version-locked case snapshot. */
object FeedbackCaseContextContract {
    const val MAX_TEXT_BYTES = 65_536

    private class Invalid : RuntimeException()

    fun decode(value: Any?): FeedbackCaseContext? =
        try {
            val fields = value as? Map<*, *> ?: throw Invalid()
            var remaining = MAX_TEXT_BYTES
            fun text(map: Map<*, *>, key: String, optional: Boolean = false): String? {
                val raw = map[key]
                if (raw == null && optional) return null
                val result = raw as? String ?: throw Invalid()
                if (result.length > remaining) throw Invalid()
                var index = 0
                while (index < result.length) {
                    val char = result[index++]
                    if (Character.isHighSurrogate(char)) {
                        if (index == result.length || !Character.isLowSurrogate(result[index++]))
                            throw Invalid()
                    } else if (Character.isLowSurrogate(char)) throw Invalid()
                }
                remaining -= result.toByteArray(Charsets.UTF_8).size
                if (remaining < 0) throw Invalid()
                return result
            }
            val caseNumber = text(fields, "caseNumber")!!
            val status = text(fields, "status")!!
            val category = text(fields, "category")!!
            val location = text(fields, "exactLocation")!!
            val explanation = text(fields, "illegalExplanation")!!
            val basis = text(fields, "legalBasis", optional = true)
            val evidence = text(fields, "evidence", optional = true)
            val goodFaith = fields["goodFaithConfirmed"] as? Boolean ?: throw Invalid()
            val acknowledged = fields["acknowledgementAt"] as? Instant ?: throw Invalid()
            val language = text(fields, "preferredLanguage")!!
            val appeal =
                fields["appeal"]?.let { raw ->
                    val map = raw as? Map<*, *> ?: throw Invalid()
                    FeedbackCaseAppeal(
                        text(map, "status")!!,
                        text(map, "reason")!!,
                        text(map, "outcome", optional = true),
                    )
                }
            // Extra server fields (including a decision or contact/token data) are not retained.
            FeedbackCaseContext(
                caseNumber,
                status,
                category,
                location,
                explanation,
                basis,
                evidence,
                goodFaith,
                acknowledged,
                language,
                appeal,
            )
        } catch (_: Invalid) {
            null
        }
}

fun FeedbackState.canReadCaseContext(): Boolean {
    val actor = session ?: return false
    val item = conversation?.item ?: return false
    return actor.ready &&
        !loading &&
        error == null &&
        selectedId == item.id &&
        item.hasDsaCase &&
        when (audience) {
            FeedbackAudience.OWN -> actor.uid == item.uid
            FeedbackAudience.MANAGEMENT -> actor.canManage
        }
}
