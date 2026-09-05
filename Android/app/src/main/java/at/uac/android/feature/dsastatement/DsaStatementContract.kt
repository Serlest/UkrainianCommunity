package at.uac.android.feature.dsastatement

enum class DsaStatementFailure {
    ACCESS,
    INVALID,
    MISSING,
    OFFLINE,
    UNKNOWN,
}

/** Deliberately does not retain an SDK error, raw response or private request in its cause. */
class DsaStatementException(val failure: DsaStatementFailure) : Exception(failure.name)

enum class DsaStatementStatus {
    SUBMITTED,
    UNDER_REVIEW,
    DECIDED,
    APPEALED,
    APPEAL_DECIDED,
    UNKNOWN,
}

enum class DsaStatementOutcome {
    NO_ACTION,
    RESTRICTED,
    REMOVED,
    UNKNOWN,
}

enum class DsaStatementAppealOutcome {
    UPHELD,
    CHANGED,
    UNKNOWN,
}

data class DsaStatementDecision(
    val rawOutcome: String,
    val factsAndCircumstances: String,
    val legalBasis: String?,
    val termsBasis: String?,
    val territorialScope: String,
    val duration: String,
    val redressInformation: String,
    val automationUsed: Boolean,
) {
    val outcome: DsaStatementOutcome
        get() =
            when (rawOutcome) {
                "noAction" -> DsaStatementOutcome.NO_ACTION
                "restricted" -> DsaStatementOutcome.RESTRICTED
                "removed" -> DsaStatementOutcome.REMOVED
                else -> DsaStatementOutcome.UNKNOWN
            }

    override fun toString() = "DsaStatementDecision([redacted])"
}

data class DsaStatementAppealDecision(
    val rawOutcome: String,
    val reason: String,
    val automationUsed: Boolean,
) {
    val outcome: DsaStatementAppealOutcome
        get() =
            when (rawOutcome) {
                "upheld" -> DsaStatementAppealOutcome.UPHELD
                "changed" -> DsaStatementAppealOutcome.CHANGED
                else -> DsaStatementAppealOutcome.UNKNOWN
            }

    override fun toString() = "DsaStatementAppealDecision([redacted])"
}

/** Sanitized, memory-only projection, not a case file or permission to submit an appeal. */
data class DsaStatement(
    val id: String,
    val caseNumber: String,
    val rawStatus: String,
    val sourceType: String,
    val sourceId: String,
    val decision: DsaStatementDecision?,
    val appealDecision: DsaStatementAppealDecision?,
) {
    val status: DsaStatementStatus
        get() =
            when (rawStatus) {
                "submitted" -> DsaStatementStatus.SUBMITTED
                "underReview" -> DsaStatementStatus.UNDER_REVIEW
                "decided" -> DsaStatementStatus.DECIDED
                "appealed" -> DsaStatementStatus.APPEALED
                "appealDecided" -> DsaStatementStatus.APPEAL_DECIDED
                else -> DsaStatementStatus.UNKNOWN
            }

    override fun toString() = "DsaStatement([redacted])"
}

/** No callable allowlist, transport, SDK or mutation is enabled here. */
object DsaStatementContract {
    const val CALLABLE = "getMyDsaStatement"
    // Local display-data cap, not a legal text limit. Reject oversize; never truncate a decision.
    const val MAX_TEXT_BYTES = 65_536

    fun fail(problem: DsaStatementFailure): Nothing = throw DsaStatementException(problem)

    fun validId(value: String, maximum: Int = 200): Boolean =
        value.length in 1..maximum &&
            value !in setOf(".", "..") &&
            !(value.startsWith("__") && value.endsWith("__")) &&
            value.none { it == '/' || it.isISOControl() || it.isWhitespace() || it == '\uFEFF' } &&
            validUnicode(value)

    fun payload(reportId: String): Map<String, String> {
        if (!validId(reportId)) fail(DsaStatementFailure.INVALID)
        return mapOf("reportId" to reportId)
    }

    fun response(reportId: String, raw: Any?): DsaStatement {
        payload(reportId)
        val budget = TextBudget()
        val map =
            exactMap(
                raw,
                setOf(
                    "id",
                    "caseNumber",
                    "status",
                    "sourceType",
                    "sourceId",
                    "decision",
                    "appealDecision",
                ),
            )
        val id = budget.text(map["id"])
        if (id != reportId) fail(DsaStatementFailure.INVALID)
        val caseNumber = budget.text(map["caseNumber"])
        val status = budget.text(map["status"])
        val sourceType = budget.text(map["sourceType"])
        val sourceId = budget.text(map["sourceId"])
        val decision =
            map["decision"]?.let {
                val d =
                    exactMap(
                        it,
                        setOf(
                            "outcome",
                            "factsAndCircumstances",
                            "legalBasis",
                            "termsBasis",
                            "territorialScope",
                            "duration",
                            "redressInformation",
                            "automationUsed",
                        ),
                    )
                DsaStatementDecision(
                    budget.text(d["outcome"]),
                    budget.text(d["factsAndCircumstances"]),
                    budget.optional(d["legalBasis"]),
                    budget.optional(d["termsBasis"]),
                    budget.text(d["territorialScope"]),
                    budget.text(d["duration"]),
                    budget.text(d["redressInformation"]),
                    boolean(d["automationUsed"]),
                )
            }
        val appeal =
            map["appealDecision"]?.let {
                val a = exactMap(it, setOf("outcome", "reason", "automationUsed"))
                DsaStatementAppealDecision(
                    budget.text(a["outcome"]),
                    budget.text(a["reason"]),
                    boolean(a["automationUsed"]),
                )
            }
        return DsaStatement(id, caseNumber, status, sourceType, sourceId, decision, appeal)
    }

    // Explicit fail-closed shape: future server fields need a reviewed projection, not raw storage.
    private fun exactMap(raw: Any?, keys: Set<String>): Map<*, *> {
        val map = raw as? Map<*, *> ?: fail(DsaStatementFailure.INVALID)
        if (map.size != keys.size || map.keys != keys) fail(DsaStatementFailure.INVALID)
        return map
    }

    private fun boolean(raw: Any?): Boolean = raw as? Boolean ?: fail(DsaStatementFailure.INVALID)

    private class TextBudget {
        private var remaining = MAX_TEXT_BYTES

        fun optional(raw: Any?): String? = raw?.let { text(it) }

        fun text(raw: Any?): String {
            val value = raw as? String ?: fail(DsaStatementFailure.INVALID)
            if (value.length > remaining || !validUnicode(value)) fail(DsaStatementFailure.INVALID)
            remaining -= value.toByteArray(Charsets.UTF_8).size
            if (remaining < 0) fail(DsaStatementFailure.INVALID)
            return value
        }
    }

    private fun validUnicode(value: String): Boolean {
        var i = 0
        while (i < value.length) {
            val c = value[i++]
            if (c.isHighSurrogate()) {
                if (i >= value.length || !value[i++].isLowSurrogate()) return false
            } else if (c.isLowSurrogate()) return false
        }
        return true
    }
}
