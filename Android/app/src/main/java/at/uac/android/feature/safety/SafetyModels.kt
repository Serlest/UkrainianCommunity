package at.uac.android.feature.safety

import at.uac.android.feature.browse.Content
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.browse.Fields
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.browse.map
import at.uac.android.feature.browse.string
import java.time.Instant

enum class SafetyAccess {
    READY,
    VERIFY_EMAIL,
    RESTRICTED,
    LEGAL,
    MFA,
    UNAVAILABLE,
}

data class SafetySession(
    val uid: String,
    val revision: Long,
    val ready: Boolean,
    val access: SafetyAccess = if (ready) SafetyAccess.READY else SafetyAccess.UNAVAILABLE,
)

enum class SafetyFailure {
    SIGN_IN,
    NOT_READY,
    DENIED,
    MISSING,
    INVALID,
    OWN_TARGET,
    LIMIT,
    OFFLINE,
    UNCONFIRMED,
    UNKNOWN,
}

enum class SafetyOperation {
    USER_BLOCKS,
    ORGANIZATION_BLOCKS,
    USER_BLOCK,
    REPORT_READ,
    CALLABLE,
}

class SafetyException(
    val failure: SafetyFailure,
    cause: Throwable? = null,
    val operation: SafetyOperation? = null,
) : Exception(failure.name, cause)

/**
 * Structural diagnostics only. Never retain exception messages, identifiers, request bodies or
 * tokens in UI state.
 */
data class SafetyReadDiagnostic(val operation: SafetyOperation?, val causeTypes: List<String>)

fun safetyReadDiagnostic(error: Throwable): SafetyReadDiagnostic {
    val chain = generateSequence(error) { it.cause }.take(5).toList()
    return SafetyReadDiagnostic(
        chain.filterIsInstance<SafetyException>().firstNotNullOfOrNull { it.operation },
        chain.map { it.javaClass.simpleName.take(80) },
    )
}

fun safetyId(value: String, maximum: Int = 256): Boolean =
    value.isNotBlank() &&
        value == value.trim() &&
        value.length <= maximum &&
        value !in setOf(".", "..") &&
        '/' !in value &&
        value.none(Char::isISOControl)

enum class SafetyTargetType(val wire: String) {
    NEWS("news"),
    EVENT("event"),
    ORGANIZATION("organization"),
    COMMENT("comment");

    companion object {
        fun content(kind: ContentKind): SafetyTargetType =
            when (kind) {
                ContentKind.NEWS -> NEWS
                ContentKind.EVENTS -> EVENT
                ContentKind.ORGANIZATIONS -> ORGANIZATION
            }
    }
}

data class SafetyReportTarget(
    val type: SafetyTargetType,
    val id: String,
    val title: String,
    val authorId: String? = null,
    val parentType: SafetyTargetType? = null,
    val parentId: String? = null,
) {
    // Firestore IDs may contain separators; length prefixes prevent different comment paths from
    // aliasing.
    val key
        get() =
            listOf(type.wire, parentType?.wire.orEmpty(), parentId.orEmpty(), id).joinToString(
                "|"
            ) {
                "${it.length}:$it"
            }

    fun valid(): Boolean =
        safetyId(id) &&
            if (type == SafetyTargetType.COMMENT)
                parentType != null &&
                    parentType != SafetyTargetType.COMMENT &&
                    parentId?.let(::safetyId) == true
            else parentType == null && parentId == null

    fun identityFields(): Fields =
        mapOf("targetType" to type.wire, "targetId" to id) +
            if (type == SafetyTargetType.COMMENT)
                mapOf("parentType" to parentType!!.wire, "parentId" to parentId)
            else emptyMap()

    companion object {
        fun content(content: Content, language: String) =
            SafetyReportTarget(
                SafetyTargetType.content(content.kind),
                content.id,
                content.title(language),
                safetyAuthor(content),
            )
    }
}

fun safetyAuthor(content: Content): String? =
    with(content.fields) {
        (if (content.kind == ContentKind.ORGANIZATIONS)
                string("ownerId").ifBlank { string("submittedByUserId") }
            else string("authorId"))
            .takeIf(String::isNotBlank)
    }

enum class SafetyReason(val wire: String, val de: String, val uk: String) {
    HARASSMENT("harassment", "Belästigung", "Переслідування"),
    HATE("hate", "Hassrede", "Мова ворожнечі"),
    VIOLENCE("violence", "Gewalt", "Насильство"),
    SEXUAL("sexual", "Sexuelle Inhalte", "Сексуальний контент"),
    SPAM("spam", "Spam oder Betrug", "Спам або шахрайство"),
    MISINFORMATION("misinformation", "Falschinformationen", "Дезінформація"),
    PRIVACY("privacy", "Privatsphäre", "Порушення приватності"),
    OTHER("other", "Anderer Grund", "Інша причина"),
}

data class SafetyReportDraft(
    val reason: SafetyReason? = null,
    val explanation: String = "",
    val legalBasis: String = "",
    val evidence: String = "",
    val goodFaith: Boolean = false,
) {
    fun normalized() =
        copy(
            explanation = explanation.trim(),
            legalBasis = legalBasis.trim(),
            evidence = evidence.trim(),
        )

    fun valid(): Boolean =
        reason != null &&
            explanation.trim().length in 20..5_000 &&
            legalBasis.trim().length <= 1_000 &&
            evidence.trim().length <= 5_000 &&
            goodFaith

    fun fields(): Fields =
        mapOf(
            "reason" to reason!!.wire,
            "illegalExplanation" to explanation.trim(),
            "goodFaithConfirmed" to goodFaith,
        ) +
            legalBasis
                .trim()
                .takeIf(String::isNotEmpty)
                ?.let { mapOf("legalBasis" to it) }
                .orEmpty() +
            evidence.trim().takeIf(String::isNotEmpty)?.let { mapOf("evidence" to it) }.orEmpty()
}

data class SafetyUserBlock(
    val id: String,
    val name: String,
    val avatarUrl: String?,
    val blockedAt: Instant,
    val updatedAt: Instant,
)

data class SafetyOrganizationBlock(val id: String, val name: String, val blockedAt: Instant)

data class SafetyBlocks(
    val users: List<SafetyUserBlock>,
    val organizations: List<SafetyOrganizationBlock>,
)

/**
 * Access tokens are memory-only and deliberately absent from diagnostics and the rendered success
 * message.
 */
class SafetyReportReceipt(
    val id: String,
    val caseNumber: String,
    val accessToken: String,
    val submittedAt: Instant,
    val acknowledgedAt: Instant,
    val duplicate: Boolean,
) {
    override fun toString() = "SafetyReportReceipt(confirmed=true)"
}

data class SafetyReportState(
    val pending: Boolean = false,
    val receipt: SafetyReportReceipt? = null,
    val error: SafetyFailure? = null,
)

enum class SafetyVisibilityReason {
    CHECKING,
    ACCOUNT_REQUIRED,
    AUTHOR_BLOCKED,
    ORGANIZATION_BLOCKED,
}

data class SafetyProjection(val items: List<Content>, val withheld: Int, val checking: Boolean)

/** Unknown authenticated block state is withheld, not rendered as an empty block list. */
data class SafetyVisibility(
    val blockedUserIds: Set<String> = emptySet(),
    val blockedOrganizationIds: Set<String> = emptySet(),
    val loaded: Boolean = true,
    val access: SafetyAccess? = null,
) {
    fun allowsAuthor(id: String?): Boolean = loaded && (id == null || id !in blockedUserIds)

    fun reason(content: Content): SafetyVisibilityReason? =
        when {
            !loaded && access != null && access != SafetyAccess.READY ->
                SafetyVisibilityReason.ACCOUNT_REQUIRED
            !loaded -> SafetyVisibilityReason.CHECKING
            !allowsAuthor(safetyAuthor(content)) -> SafetyVisibilityReason.AUTHOR_BLOCKED
            (if (content.kind == ContentKind.ORGANIZATIONS) content.id
            else content.fields.string("organizationId")) in blockedOrganizationIds ->
                SafetyVisibilityReason.ORGANIZATION_BLOCKED
            else -> null
        }

    fun allows(content: Content): Boolean = reason(content) == null

    fun project(items: List<Content>): SafetyProjection {
        val visible = items.filter(::allows)
        return SafetyProjection(
            visible,
            items.size - visible.size,
            !loaded && (access == null || access == SafetyAccess.READY),
        )
    }
}

data class SafetyState(
    val session: SafetySession? = null,
    val blocks: SafetyBlocks? = null,
    val loading: Boolean = false,
    val error: SafetyFailure? =
        if (session != null && !session.ready) SafetyFailure.NOT_READY else null,
    val pendingBlocks: Set<String> = emptySet(),
    val blockErrors: Map<String, SafetyFailure> = emptyMap(),
    val reports: Map<String, SafetyReportState> = emptyMap(),
    val readDiagnostic: SafetyReadDiagnostic? = null,
) {
    val visibility
        get() =
            SafetyVisibility(
                blocks?.users.orEmpty().map { it.id }.toSet(),
                blocks?.organizations.orEmpty().map { it.id }.toSet(),
                session == null || blocks != null,
                session?.access,
            )
}

object SafetyContract {
    private fun invalid(): Nothing = throw SafetyException(SafetyFailure.INVALID)

    private fun instant(value: Any?): Instant =
        when (value) {
            is Instant -> value
            is String -> runCatching { Instant.parse(value) }.getOrElse { invalid() }
            else -> invalid()
        }

    private fun label(value: Any?, maximum: Int): String =
        (value as? String ?: invalid())
            .filterNot { it.isISOControl() || it in '\u202A'..'\u202E' || it in '\u2066'..'\u2069' }
            .trim()
            .take(maximum)

    fun user(row: RawDocument): SafetyUserBlock =
        with(row.fields) {
            if (!safetyId(row.id) || this["id"] != row.id || this["targetUserId"] != row.id)
                invalid()
            val avatar = this["avatarURL"]?.let { it as? String ?: invalid() }
            SafetyUserBlock(
                row.id,
                label(this["displayName"], 120),
                avatar,
                instant(this["blockedAt"]),
                instant(this["updatedAt"]),
            )
        }

    fun organization(value: Any?): SafetyOrganizationBlock {
        val f = value as? Map<*, *> ?: invalid()
        val id = f["organizationId"] as? String ?: invalid()
        if (!safetyId(id, 160)) invalid()
        return SafetyOrganizationBlock(id, label(f["name"], 200), instant(f["blockedAt"]))
    }

    fun organizations(value: Any?): List<SafetyOrganizationBlock> {
        val values = (value as? Map<*, *>)?.get("blocks") as? List<*> ?: invalid()
        if (values.size > 500) invalid()
        return values.map(::organization).also {
            if (it.map { row -> row.id }.toSet().size != it.size) invalid()
        }
    }

    fun userReceipt(value: Any?, id: String, blocked: Boolean) {
        val f = value as? Map<*, *> ?: invalid()
        if (f["targetUserId"] != id || f["isBlocked"] != blocked || f["displayName"] !is String)
            invalid()
        instant(f["updatedAt"])
    }

    fun organizationReceipt(value: Any?, id: String, blocked: Boolean) {
        val f = value as? Map<*, *> ?: invalid()
        if (f["organizationId"] != id || f["isBlocked"] != blocked) invalid()
        if (blocked) {
            if (organization(f["block"]).id != id) invalid()
        } else if (f["block"] != null) invalid()
    }

    fun reportReceipt(value: Any?): SafetyReportReceipt {
        val f = value as? Map<*, *> ?: invalid()
        val id = f["reportId"] as? String ?: invalid()
        val case = f["caseNumber"] as? String ?: invalid()
        val token = f["accessToken"] as? String ?: invalid()
        if (
            !safetyId(id) ||
                case.isBlank() ||
                case.length > 200 ||
                case.any(Char::isISOControl) ||
                token.isBlank() ||
                token.length > 512 ||
                f["status"] != "open" ||
                f["wasDuplicate"] !is Boolean
        )
            invalid()
        return SafetyReportReceipt(
            id,
            case,
            token,
            instant(f["submittedAt"]),
            instant(f["acknowledgementAt"]),
            f["wasDuplicate"] as Boolean,
        )
    }

    fun confirmReport(
        row: RawDocument,
        uid: String,
        target: SafetyReportTarget,
        draft: SafetyReportDraft,
        receipt: SafetyReportReceipt,
    ) {
        val f = row.fields
        val context = f.map("reportContext")
        val dsa = f.map("dsaCase")
        if (
            row.id != receipt.id ||
                f["id"] != receipt.id ||
                f["userId"] != uid ||
                f["type"] != "report" ||
                target.identityFields().any { (key, value) -> context[key] != value } ||
                context["parentType"] != target.parentType?.wire ||
                context["parentId"] != target.parentId ||
                context["reason"] != draft.reason?.wire ||
                dsa["caseNumber"] != receipt.caseNumber ||
                dsa["illegalExplanation"] != draft.explanation ||
                dsa["legalBasis"] != draft.legalBasis.takeIf(String::isNotEmpty) ||
                dsa["evidence"] != draft.evidence.takeIf(String::isNotEmpty) ||
                dsa["goodFaithConfirmed"] != true ||
                instant(f["createdAt"]).toEpochMilli() != receipt.submittedAt.toEpochMilli() ||
                instant(dsa["acknowledgementAt"]).toEpochMilli() !=
                    receipt.acknowledgedAt.toEpochMilli()
        )
            invalid()
    }
}
