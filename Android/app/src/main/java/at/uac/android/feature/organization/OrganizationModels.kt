package at.uac.android.feature.organization

import at.uac.android.feature.auth.AuthLegalDocument
import at.uac.android.feature.auth.AuthSession
import at.uac.android.feature.auth.AuthValidation
import at.uac.android.feature.browse.Fields
import at.uac.android.feature.browse.RawDocument
import java.net.URI
import java.time.Duration
import java.time.Instant
import java.util.UUID

data class OrganizationSession(
    val uid: String,
    val revision: Long,
    val ready: Boolean,
    val name: String,
    val globalRole: String,
)

fun AuthSession.organizationScope(): OrganizationSession? =
    identity
        ?.takeUnless { it.anonymous }
        ?.let {
            OrganizationSession(
                it.uid,
                revision,
                readyForActions && profile?.active == true,
                profile?.displayName.orEmpty(),
                profile?.globalRole.orEmpty(),
            )
        }

enum class OrganizationFailure {
    SIGN_IN,
    NOT_READY,
    INVALID,
    DENIED,
    OFFLINE,
    MISSING,
    STALE,
    LIMIT,
    LEGAL_CHANGED,
    CONSENT,
    UNCONFIRMED,
    LOGO_INCOMPLETE,
    UNKNOWN,
}

class OrganizationException(val failure: OrganizationFailure, cause: Throwable? = null) :
    Exception(failure.name, cause)

enum class OrganizationAuthority {
    PLATFORM_OWNER,
    OWNER,
    ADMIN,
    MODERATOR,
    NONE,
}

enum class RequestRetention {
    ACTIVE,
    WARNING,
    DUE,
}

data class OrganizationDraft(
    val id: String = UUID.randomUUID().toString(),
    val name: String = "",
    val summary: String = "",
    val details: String = "",
    val germanName: String = "",
    val germanSummary: String = "",
    val germanDetails: String = "",
    val region: String = "",
    val city: String = "",
    val email: String = "",
    val phone: String = "",
    val website: String = "",
    val address: String = "",
    val profileKind: String = "community",
    val acceptedRulesVersion: String? = null,
)

data class OrganizationRecord(
    val id: String,
    val fields: Fields,
    val name: String,
    val status: String,
    val submitter: String?,
    val updatedAt: Instant,
    val createdAt: Instant,
    val authority: OrganizationAuthority,
    val reviewMessage: String?,
    val rejectionReason: String?,
) {
    fun editable(session: OrganizationSession) =
        session.ready && submitter == session.uid && status in OrganizationContract.requestStatuses

    fun retention(now: Instant): RequestRetention {
        if (status !in setOf("needsRevision", "rejected")) return RequestRetention.ACTIVE
        val age = Duration.between(updatedAt, now).toDays()
        return when {
            age >= 30 -> RequestRetention.DUE
            age >= 23 -> RequestRetention.WARNING
            else -> RequestRetention.ACTIVE
        }
    }

    val deletionDueAt: Instant
        get() = updatedAt.plus(Duration.ofDays(30))
}

data class OrganizationHub(
    val requests: List<OrganizationRecord>,
    val managed: List<OrganizationRecord>,
    val truncated: Boolean = false,
)

data class OrganizationSubmitResult(
    val record: OrganizationRecord,
    val logoIncomplete: Boolean = false,
)

/** Prepared local-only preview. Callers cannot mutate the bytes that will be uploaded. */
class OrganizationLogoSelection(bytes: ByteArray) {
    private val encoded = bytes.copyOf()

    fun copyBytes(): ByteArray = encoded.copyOf()
}

object OrganizationContract {
    val requestStatuses = listOf("pendingReview", "needsRevision", "rejected")
    val profileKinds =
        listOf("community", "business", "restaurant", "specialist", "institution", "mediaProject")
    val counterFields =
        listOf(
            "subscriberCount",
            "likeCount",
            "eventsHeldCount",
            "volunteersCount",
            "helpedPeopleCount",
        )

    fun id(value: String) = Regex("[A-Za-z0-9_-]{1,128}").matches(value)

    fun website(value: String): String {
        val text = value.trim()
        if (text.isEmpty()) return ""
        if (text.any { it.isWhitespace() || it.isISOControl() } || '\\' in text) invalid()
        val hasHttpScheme = text.startsWith("http://", true) || text.startsWith("https://", true)
        // Do not turn file:///path (or another explicit scheme) into an HTTPS host.
        // A bare host with a numeric port is still a valid website input.
        val hasScheme = Regex("^[A-Za-z][A-Za-z0-9+.-]*:").containsMatchIn(text)
        val isHostAndPort = Regex("^[A-Za-z0-9.-]+:[0-9]{1,5}(?:[/?#].*)?$").matches(text)
        if (hasScheme && !hasHttpScheme && !isHostAndPort) invalid()
        val normalized = if (hasHttpScheme) text else "https://$text"
        val uri = runCatching { URI(normalized) }.getOrNull() ?: invalid()
        if (
            uri.scheme.lowercase() !in setOf("http", "https") ||
                uri.host.isNullOrBlank() ||
                uri.userInfo != null ||
                uri.port > 65535 ||
                normalized.length > 2048
        )
            invalid()
        return normalized
    }

    fun validate(draft: OrganizationDraft): OrganizationDraft {
        val value =
            draft.copy(
                name = draft.name.trim(),
                summary = draft.summary.trim(),
                details = draft.details.trim(),
                germanName = draft.germanName.trim(),
                germanSummary = draft.germanSummary.trim(),
                germanDetails = draft.germanDetails.trim(),
                city = draft.city.trim(),
                email = draft.email.trim(),
                phone = draft.phone.trim(),
                website = website(draft.website),
                address = draft.address.trim(),
            )
        if (
            !id(value.id) ||
                value.id == "ukrainian-community" ||
                value.name.length !in 1..180 ||
                value.summary.codePointCount(0, value.summary.length) !in 20..160 ||
                value.details.codePointCount(0, value.details.length) > 1200 ||
                value.region !in AuthValidation.regions ||
                value.city.length !in 1..160 ||
                value.email.length > 320 ||
                (value.email.isNotEmpty() &&
                    (!value.email.contains('@') || value.email.any(Char::isWhitespace))) ||
                value.phone.length > 80 ||
                value.address.length > 500 ||
                value.profileKind !in profileKinds ||
                value.germanName.length > 180 ||
                value.germanSummary.codePointCount(0, value.germanSummary.length) > 160 ||
                value.germanDetails.codePointCount(0, value.germanDetails.length) > 1200
        )
            invalid()
        return value
    }

    fun editableFields(draft: OrganizationDraft, original: Fields = emptyMap()): Fields {
        val d = validate(draft)
        val localized =
            (original["localizations"] as? Map<*, *>)
                ?.entries
                ?.associate { it.key.toString() to it.value }
                .orEmpty()
                .toMutableMap()
        fun locale(key: String, name: String, summary: String, details: String) {
            val existing =
                (localized[key] as? Map<*, *>)
                    ?.entries
                    ?.associate { it.key.toString() to it.value }
                    .orEmpty()
            localized[key] =
                existing +
                    mapOf(
                        "name" to name,
                        "shortDescription" to summary,
                        "fullDescription" to details.ifBlank { summary },
                        "services" to (existing["services"] ?: emptyList<String>()),
                    )
        }
        locale("uk", d.name, d.summary, d.details)
        if (listOf(d.germanName, d.germanSummary, d.germanDetails).any(String::isNotBlank))
            locale(
                "de",
                d.germanName.ifBlank { d.name },
                d.germanSummary.ifBlank { d.summary },
                d.germanDetails.ifBlank {
                    d.germanSummary.ifBlank { d.details.ifBlank { d.summary } }
                },
            )
        else if (localized.containsKey("de")) locale("de", d.name, d.summary, d.details)
        val profile =
            (original["directoryProfile"] as? Map<*, *>)
                ?.entries
                ?.associate { it.key.toString() to it.value }
                .orEmpty()
        return mapOf(
            "name" to d.name,
            "description" to d.summary,
            "shortDescription" to d.summary,
            "fullDescription" to d.details.ifBlank { d.summary },
            "localizations" to localized,
            "regionScope" to (original["regionScope"] ?: "federalState"),
            "federalState" to d.region,
            "city" to d.city,
            "email" to d.email.ifEmpty { null },
            "contactEmail" to d.email.ifEmpty { null },
            "phone" to d.phone.ifEmpty { null },
            "website" to d.website.ifEmpty { null },
            "address" to d.address.ifEmpty { null },
            "directoryProfile" to profile + ("profileKind" to d.profileKind),
        )
    }

    fun create(draft: OrganizationDraft, session: OrganizationSession, now: Any): Fields =
        editableFields(draft) +
            mapOf(
                "id" to draft.id,
                "createdAt" to now,
                "updatedAt" to now,
                "submittedAt" to now,
                "submittedByUserId" to session.uid,
                "submittedByDisplayName" to session.name.take(160),
                "moderationStatus" to "pendingReview",
                "adminIds" to emptyList<String>(),
                "moderatorIds" to emptyList<String>(),
                "languages" to emptyList<String>(),
                "socialLinks" to emptyMap<String, String>(),
                "likeState" to "notLiked",
            ) +
            counterFields.associateWith { 0L }

    fun record(row: RawDocument, session: OrganizationSession): OrganizationRecord {
        val f = row.fields
        if (!id(row.id) || f["id"] != row.id) invalid()
        val name =
            (f["name"] as? String)?.takeIf { it.isNotBlank() && it.length <= 180 } ?: invalid()
        val status = f["moderationStatus"] as? String ?: invalid()
        if (status !in requestStatuses + listOf("approved", "archived", "retentionDeleting"))
            invalid()
        val updated = f["updatedAt"] as? Instant ?: invalid()
        val created = f["createdAt"] as? Instant ?: invalid()
        val submitter = f["submittedByUserId"] as? String
        val admins = f["adminIds"] as? List<*> ?: invalid()
        val moderators = f["moderatorIds"] as? List<*> ?: invalid()
        if (admins.any { it !is String } || moderators.any { it !is String }) invalid()
        val authority =
            when {
                !session.ready || status != "approved" -> OrganizationAuthority.NONE
                session.globalRole == "owner" -> OrganizationAuthority.PLATFORM_OWNER
                f["ownerId"] == session.uid -> OrganizationAuthority.OWNER
                session.uid in admins -> OrganizationAuthority.ADMIN
                session.uid in moderators -> OrganizationAuthority.MODERATOR
                else -> OrganizationAuthority.NONE
            }
        return OrganizationRecord(
            row.id,
            f,
            name,
            status,
            submitter,
            updated,
            created,
            authority,
            (f["reviewMessage"] as? String)?.take(4000),
            (f["rejectionReason"] as? String)?.take(4000),
        )
    }

    fun requireEditable(record: OrganizationRecord, session: OrganizationSession) {
        if (!record.editable(session) || record.id == "ukrainian-community")
            throw OrganizationException(OrganizationFailure.DENIED)
        if (
            counterFields.any {
                record.fields[it] !is Number || (record.fields[it] as Number).toDouble() != 0.0
            } ||
                record.fields["likeState"] != "notLiked" ||
                !(record.fields["ownerId"] as? String).isNullOrEmpty() ||
                (record.fields["adminIds"] as? List<*>)?.isNotEmpty() != false ||
                (record.fields["moderatorIds"] as? List<*>)?.isNotEmpty() != false
        )
            invalid()
    }

    fun draft(record: OrganizationRecord): OrganizationDraft {
        val f = record.fields
        val de = (f["localizations"] as? Map<*, *>)?.get("de") as? Map<*, *>
        return OrganizationDraft(
            record.id,
            record.name,
            f["shortDescription"] as? String ?: f["description"] as? String ?: "",
            f["fullDescription"] as? String ?: "",
            de?.get("name") as? String ?: "",
            de?.get("shortDescription") as? String ?: "",
            de?.get("fullDescription") as? String ?: "",
            f["federalState"] as? String ?: "",
            f["city"] as? String ?: "",
            f["email"] as? String ?: f["contactEmail"] as? String ?: "",
            f["phone"] as? String ?: "",
            f["website"] as? String ?: "",
            f["address"] as? String ?: "",
            (f["directoryProfile"] as? Map<*, *>)?.get("profileKind") as? String ?: "community",
        )
    }

    fun acceptancePayload(
        draft: OrganizationDraft,
        rules: AuthLegalDocument,
        language: String,
        appVersion: String,
    ): Fields {
        val d = validate(draft)
        if (
            rules.type != "organizationRules" ||
                rules.version.length !in 1..80 ||
                d.acceptedRulesVersion != rules.version
        )
            throw OrganizationException(OrganizationFailure.CONSENT)
        return mapOf(
            "organizationId" to d.id,
            "organizationName" to d.name,
            "version" to rules.version,
            "appVersion" to appVersion,
            "locale" to if (language == "uk") "uk" else "de",
            "acceptedFromPlatform" to "android",
        )
    }

    fun acceptance(response: Any?, id: String, version: String): Instant {
        val f = response as? Map<*, *> ?: unconfirmed()
        if (f["organizationId"] != id || f["version"] != version) unconfirmed()
        return (f["acceptedAt"] as? String)?.let { runCatching { Instant.parse(it) }.getOrNull() }
            ?: unconfirmed()
    }

    private fun invalid(): Nothing = throw OrganizationException(OrganizationFailure.INVALID)

    private fun unconfirmed(): Nothing =
        throw OrganizationException(OrganizationFailure.UNCONFIRMED)
}
