package at.uac.android.feature.dsaappeal

import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.dsastatement.DsaStatementContract
import at.uac.android.feature.feedback.FeedbackContract
import at.uac.android.feature.feedback.FeedbackException
import at.uac.android.feature.feedback.FeedbackStatus
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.security.MessageDigest
import java.time.Instant

/** Preparation only. A future server call can race this read; this is not an atomic lease. */
object DsaAppealReviewContract {
    private val caseKeys =
        setOf(
            "caseNumber",
            "status",
            "category",
            "exactLocation",
            "legalBasis",
            "illegalExplanation",
            "evidence",
            "goodFaithConfirmed",
            "acknowledgementAt",
            "preferredLanguage",
            "decision",
            "appeal",
        )
    private val decisionKeys =
        setOf(
            "outcome",
            "factsAndCircumstances",
            "legalBasis",
            "termsBasis",
            "territorialScope",
            "duration",
            "automationUsed",
            "humanReviewConfirmed",
            "actionVerifiedAt",
            "redressInformation",
            "decidedAt",
            "decidedByUserId",
            "appealDeadline",
        )
    private val minimumTime = Instant.parse("0001-01-01T00:00:00Z")
    private val maximumTime = Instant.parse("9999-12-31T23:59:59.999999999Z")

    internal fun fail(value: DsaAppealReviewFailure): Nothing =
        throw DsaAppealReviewException(value)

    private fun invalid(): Nothing = fail(DsaAppealReviewFailure.INVALID)

    private fun date(value: Any?): Instant =
        (value as? Instant ?: invalid()).also {
            if (it < minimumTime || it > maximumTime) invalid()
        }

    private fun text(
        fields: Map<*, *>,
        key: String,
        maximum: Int,
        optional: Boolean = false,
    ): String? {
        val raw = fields[key]
        if (raw == null && optional) return null
        val text = raw as? String ?: invalid()
        if (text.length > maximum || (!optional && text.isBlank())) invalid()
        var index = 0
        while (index < text.length) {
            val char = text[index++]
            if (Character.isHighSurrogate(char)) {
                if (index == text.length || !Character.isLowSurrogate(text[index++])) invalid()
            } else if (Character.isLowSurrogate(char)) invalid()
        }
        return text
    }

    fun snapshot(row: RawDocument, reporterUid: String, now: Instant): DsaAppealReviewSnapshot {
        if (
            !DsaStatementContract.validId(row.id) || !DsaStatementContract.validId(reporterUid, 128)
        )
            invalid()
        if (row.fields.size > 128) invalid()
        val parent = row.fields.toMap()
        // Check ownership before retaining/reporting private case metadata. Public-portal reports
        // and another reporter's case are never made readable by management/author privileges.
        if (parent["userId"] != reporterUid) fail(DsaAppealReviewFailure.ACCESS)
        val rawCase = copyCase(parent["dsaCase"] as? Map<*, *> ?: invalid())
        val item =
            try {
                FeedbackContract.item(RawDocument(row.id, parent + ("dsaCase" to rawCase)))
            } catch (_: FeedbackException) {
                invalid()
            }
        if (item.status !in setOf(FeedbackStatus.CLOSED, FeedbackStatus.ARCHIVED))
            fail(DsaAppealReviewFailure.INELIGIBLE)
        if (!caseKeys.containsAll(rawCase.keys)) invalid()
        if (rawCase["status"] != "decided" || rawCase["appeal"] != null)
            fail(DsaAppealReviewFailure.INELIGIBLE)
        val context = item.caseContext ?: invalid()
        if (
            context.caseNumber.isBlank() ||
                context.caseNumber.length > 200 ||
                context.caseNumber.any(Char::isISOControl)
        )
            invalid()
        date(context.acknowledgementAt)
        val rawDecision = rawCase["decision"] as? Map<*, *> ?: invalid()
        if (!decisionKeys.containsAll(rawDecision.keys)) invalid()
        val outcome = text(rawDecision, "outcome", 80)!!
        if (outcome !in setOf("noAction", "restricted", "removed"))
            fail(DsaAppealReviewFailure.INELIGIBLE)
        val basis = text(rawDecision, "legalBasis", 2_000, optional = true)
        val terms = text(rawDecision, "termsBasis", 2_000, optional = true)
        if (basis.isNullOrBlank() && terms.isNullOrBlank()) invalid()
        val decidedAt = date(rawDecision["decidedAt"])
        val deadline = date(rawDecision["appealDeadline"])
        if (deadline <= decidedAt) invalid()
        date(rawDecision["actionVerifiedAt"])
        if (!DsaStatementContract.validId(text(rawDecision, "decidedByUserId", 128)!!, 128))
            invalid()
        val decision =
            DsaAppealDecision(
                outcome,
                text(rawDecision, "factsAndCircumstances", 5_000)!!,
                basis,
                terms,
                text(rawDecision, "territorialScope", 500)!!,
                text(rawDecision, "duration", 500)!!,
                text(rawDecision, "redressInformation", 2_000)!!,
                rawDecision["automationUsed"] as? Boolean ?: invalid(),
                rawDecision["humanReviewConfirmed"] as? Boolean ?: invalid(),
                decidedAt,
                deadline,
            )
        requireOpenWindow(decision, now)
        val updatedAt = date(parent["updatedAt"])
        val fingerprint = fingerprint(row.id, reporterUid, item.status.wire, updatedAt, rawCase)
        return DsaAppealReviewSnapshot(row.id, reporterUid, context, decision, fingerprint)
    }

    fun requireOpenWindow(decision: DsaAppealDecision, now: Instant) {
        date(now)
        if (now >= decision.appealDeadline) fail(DsaAppealReviewFailure.EXPIRED)
        if (now < decision.decidedAt) fail(DsaAppealReviewFailure.INELIGIBLE)
    }

    // Own a bounded tree before projecting/hash computation. SDK/source backing-map mutation must
    // not change the text after a fingerprint has been calculated.
    private fun copyCase(fields: Map<*, *>): Map<String, Any?> {
        var nodes = 0
        var bytes = 0
        fun copy(value: Any?, depth: Int): Any? {
            if (++nodes > 128 || depth > 4) invalid()
            return when (value) {
                null,
                is Boolean,
                is Instant -> value
                is String -> {
                    if (value.length > 131_072) invalid()
                    bytes += value.toByteArray(Charsets.UTF_8).size
                    if (bytes > 131_072) invalid()
                    value
                }
                is Map<*, *> -> {
                    if (value.size > 32) invalid()
                    value.entries.associate { (key, child) ->
                        (copy(key as? String ?: invalid(), depth + 1) as String) to
                            copy(child, depth + 1)
                    }
                }
                else -> invalid()
            }
        }
        @Suppress("UNCHECKED_CAST")
        return copy(fields, 0) as Map<String, Any?>
    }

    private fun fingerprint(
        id: String,
        uid: String,
        status: String,
        updated: Instant,
        fields: Map<*, *>,
    ): String {
        val bytes = ByteArrayOutputStream()
        val output = DataOutputStream(bytes)
        var nodes = 0
        fun encode(value: Any?, depth: Int = 0) {
            if (++nodes > 128 || depth > 4) invalid()
            when (value) {
                null -> output.writeByte(0)
                is String -> {
                    output.writeByte(1)
                    val utf8 = value.toByteArray(Charsets.UTF_8)
                    if (bytes.size() + utf8.size + 4 > 131_072) invalid()
                    output.writeInt(utf8.size)
                    output.write(utf8)
                }
                is Boolean -> {
                    output.writeByte(2)
                    output.writeBoolean(value)
                }
                is Instant -> {
                    output.writeByte(3)
                    output.writeLong(value.epochSecond)
                    output.writeInt(value.nano)
                }
                is Map<*, *> -> {
                    output.writeByte(4)
                    output.writeInt(value.size)
                    val keys = value.keys.map { it as? String ?: invalid() }.sorted()
                    for (key in keys) {
                        encode(key, depth + 1)
                        encode(value[key], depth + 1)
                    }
                }
                else -> invalid()
            }
        }
        encode("uac-dsa-appeal-review-v1")
        encode(id)
        encode(uid)
        encode(status)
        encode(updated)
        encode(fields)
        output.flush()
        return MessageDigest.getInstance("SHA-256").digest(bytes.toByteArray()).joinToString("") {
            "%02x".format(it)
        }
    }
}
