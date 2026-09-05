package at.uac.android.feature.moderation

import at.uac.android.feature.auth.AuthSession
import at.uac.android.feature.browse.Fields
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.organizationreview.OrganizationReviewContract
import at.uac.android.feature.organizationreview.OrganizationReviewException
import java.text.Collator
import java.time.Instant
import java.util.Locale

data class ModerationSession(
    val uid: String,
    val revision: Long,
    val role: String,
    val ready: Boolean,
) {
    val allowed: Boolean
        get() = ready && role in setOf("owner", "admin")

    override fun toString() = "ModerationSession([redacted], ready=$ready)"
}

fun AuthSession.moderationScope(): ModerationSession? =
    identity
        ?.takeUnless { it.anonymous }
        ?.let {
            ModerationSession(
                it.uid,
                revision,
                profile?.globalRole.orEmpty(),
                readyForActions &&
                    profile?.active == true &&
                    (!profile.privileged || profile.requiresMultiFactorAuth && totpAuthenticated),
            )
        }

/** Opaque, memory-only ownership of one resumed screen; this never grants Auth authority. */
class ModerationPresentation internal constructor()

enum class ModerationKind(val collection: String) {
    NEWS("news"),
    EVENT("events"),
    ORGANIZATION("organizations"),
}

enum class ModerationSection(val kinds: List<ModerationKind>) {
    CONTENT(listOf(ModerationKind.NEWS, ModerationKind.EVENT)),
    ORGANIZATION_REQUESTS(listOf(ModerationKind.ORGANIZATION)),
}

enum class ModerationSort {
    NEWEST,
    OLDEST,
    NAME_ASCENDING,
    NAME_DESCENDING,
}

enum class ModerationFailure {
    SIGN_IN,
    NOT_READY,
    DENIED,
    OFFLINE,
    INDEX,
    INVALID,
    MISSING,
    STALE,
    UNKNOWN,
}

class ModerationException(val failure: ModerationFailure, cause: Throwable? = null) :
    Exception(failure.name, cause)

data class ModerationTarget(val kind: ModerationKind, val id: String) {
    override fun toString() = "ModerationTarget(kind=$kind, [redacted])"
}

data class ModerationText(val base: String, val uk: String = base, val de: String = base) {
    fun value(language: String) = if (language == "uk") uk else de

    override fun toString() = "ModerationText([redacted])"
}

data class ModerationItem(
    val target: ModerationTarget,
    val title: ModerationText,
    val summary: ModerationText,
    val createdAt: Instant,
    val updatedAt: Instant,
    val status: String,
    val organizationId: String?,
    val submitter: String?,
) {
    override fun toString() = "ModerationItem(kind=${target.kind}, [redacted])"
}

data class ModerationField(val key: String, val text: ModerationText) {
    override fun toString() = "ModerationField(key=$key, [redacted])"
}

data class ModerationPreview(
    val item: ModerationItem,
    val body: ModerationText,
    val fields: List<ModerationField>,
    val images: List<String> = emptyList(),
    val reviewVersion: ModerationReviewVersion? = null,
    /** Exact displayed raw fields for client preflight; the org callable has no server CAS. */
    val organizationReviewFingerprint: String? = null,
) {
    override fun toString() = "ModerationPreview([redacted])"
}

data class ModerationHead(
    val kind: ModerationKind,
    val items: List<ModerationItem>,
    val rawCount: Int,
) {
    val capped
        get() = rawCount == ModerationContract.LIMIT

    override fun toString() = "ModerationHead(kind=$kind, rawCount=$rawCount)"
}

data class ModerationPart(
    val loading: Boolean = false,
    val head: ModerationHead? = null,
    val error: ModerationFailure? = null,
)

data class ModerationState(
    val session: ModerationSession? = null,
    val section: ModerationSection = ModerationSection.CONTENT,
    val visible: Boolean = false,
    val parts: Map<ModerationKind, ModerationPart> = emptyMap(),
    val selected: ModerationTarget? = null,
    val preview: ModerationPreview? = null,
    val previewLoading: Boolean = false,
    val previewError: ModerationFailure? = null,
    val search: String = "",
    val filter: ModerationKind? = null,
    val sort: ModerationSort = ModerationSort.NEWEST,
) {
    fun forSession(
        current: ModerationSession?,
        expected: ModerationSection = section,
    ): ModerationState =
        if (session == current && current?.allowed == true && section == expected) this
        else ModerationState(session = current, section = expected)

    override fun toString() = "ModerationState(section=$section, visible=$visible, [redacted])"
}

object ModerationContract {
    const val LIMIT = 100
    private val statuses =
        setOf(
            "pendingReview",
            "needsRevision",
            "rejected",
            "approved",
            "archived",
            "draft",
            "retentionDeleting",
        )

    fun id(value: String) = Regex("[A-Za-z0-9_-]{1,128}").matches(value)

    fun validate(target: ModerationTarget) {
        if (!id(target.id)) fail(ModerationFailure.INVALID)
    }

    fun requireSession(session: ModerationSession?) {
        if (session == null) fail(ModerationFailure.SIGN_IN)
        if (!session.ready) fail(ModerationFailure.NOT_READY)
        if (!session.allowed || session.uid.isBlank()) fail(ModerationFailure.DENIED)
    }

    fun fail(failure: ModerationFailure): Nothing = throw ModerationException(failure)

    private fun text(value: Any?, maximum: Int = 50_000): String {
        if (value == null) return ""
        val result = value as? String ?: fail(ModerationFailure.INVALID)
        if (
            result.length > maximum ||
                result.any { it.isISOControl() && it != '\n' && it != '\r' && it != '\t' }
        )
            fail(ModerationFailure.INVALID)
        return result.trim()
    }

    private fun localized(
        fields: Fields,
        key: String,
        fallback: String = "",
        maximum: Int = 50_000,
    ): ModerationText {
        val base = text(fields[key], maximum).ifEmpty { fallback }
        val locales = fields["localizations"] as? Map<*, *>
        fun language(code: String) =
            text((locales?.get(code) as? Map<*, *>)?.get(key), maximum).ifEmpty { base }
        return ModerationText(base, language("uk"), language("de"))
    }

    fun item(kind: ModerationKind, row: RawDocument): ModerationItem {
        validate(ModerationTarget(kind, row.id))
        val f = row.fields
        if (f["id"] != row.id) fail(ModerationFailure.INVALID)
        val status = f["moderationStatus"] as? String ?: fail(ModerationFailure.INVALID)
        if (status !in statuses) fail(ModerationFailure.INVALID)
        val org = kind == ModerationKind.ORGANIZATION
        val title = localized(f, if (org) "name" else "title", maximum = 500)
        if (title.base.isBlank()) fail(ModerationFailure.INVALID)
        val summary =
            localized(
                f,
                if (org) "shortDescription"
                else if (kind == ModerationKind.NEWS) "subtitle" else "summary",
                text(f[if (org) "description" else "summary"], 10_000),
                10_000,
            )
        val organizationId =
            if (org) row.id else text(f["organizationId"], 128).takeIf(String::isNotEmpty)
        if (
            !org &&
                (f["sourceType"] != "organization" || organizationId == null || !id(organizationId))
        )
            fail(ModerationFailure.INVALID)
        return ModerationItem(
            ModerationTarget(kind, row.id),
            title,
            summary,
            f["createdAt"] as? Instant ?: fail(ModerationFailure.INVALID),
            f["updatedAt"] as? Instant ?: fail(ModerationFailure.INVALID),
            status,
            organizationId,
            if (org)
                text(f["submittedByDisplayName"], 500)
                    .ifEmpty { text(f["submittedByUserId"], 128) }
                    .takeIf(String::isNotEmpty)
            else null,
        )
    }

    fun head(kind: ModerationKind, rows: List<RawDocument>): ModerationHead {
        if (rows.size > LIMIT || rows.map { it.id }.distinct().size != rows.size)
            fail(ModerationFailure.INVALID)
        var previous: Instant? = null
        val result = rows.mapNotNull { row ->
            if (row.fields["moderationStatus"] != "pendingReview") fail(ModerationFailure.INVALID)
            val time = row.fields["createdAt"] as? Instant ?: fail(ModerationFailure.INVALID)
            previous?.let { if (time > it) fail(ModerationFailure.INVALID) }
            previous = time
            // Preserve the iOS raw 100-document cutoff before this source filter.
            if (
                kind != ModerationKind.ORGANIZATION &&
                    (row.fields["sourceType"] != "organization" ||
                        (row.fields["organizationId"] as? String).isNullOrBlank())
            )
                null
            else item(kind, row)
        }
        return ModerationHead(kind, result, rows.size)
    }

    fun preview(target: ModerationTarget, row: RawDocument): ModerationPreview {
        if (target.id != row.id) fail(ModerationFailure.INVALID)
        val item = item(target.kind, row)
        val f = row.fields
        val org = target.kind == ModerationKind.ORGANIZATION
        val body =
            localized(
                f,
                if (org) "fullDescription"
                else if (target.kind == ModerationKind.NEWS) "body" else "details",
                item.summary.base,
            )
        val fields = mutableListOf<ModerationField>()
        fun add(key: String, value: ModerationText) {
            if (listOf(value.base, value.uk, value.de).any(String::isNotEmpty))
                fields += ModerationField(key, value)
        }
        fun render(value: Any?): String =
            when (value) {
                null -> ""
                is String -> text(value, 10_000)
                is Instant -> value.toString()
                is Boolean,
                is Number -> value.toString()
                is List<*> -> {
                    if (value.size > 50) fail(ModerationFailure.INVALID)
                    value.joinToString("\n") { text(it, 2_000) }
                }
                else -> fail(ModerationFailure.INVALID)
            }
        val keys =
            if (org)
                listOf(
                    "submittedByUserId",
                    "submittedAt",
                    "reviewMessage",
                    "rejectionReason",
                    "reviewedByUserId",
                    "reviewedAt",
                    "organizationType",
                    "city",
                    "federalState",
                    "address",
                    "contactPerson",
                    "email",
                    "contactEmail",
                    "phone",
                    "website",
                    "missionStatement",
                    "languages",
                    "foundedYear",
                    "foundedMonth",
                    "telegramURL",
                    "facebookURL",
                    "instagramURL",
                    "whatsappURL",
                    "youtubeURL",
                    "linkedinURL",
                    "donationURL",
                )
            else
                listOf(
                    "organizationName",
                    "authorName",
                    "publishedAt",
                    "scheduledAt",
                    "sourceName",
                    "sourceURL",
                    "category",
                    "additionalCategories",
                    "tags",
                    "regionScope",
                    "federalState",
                    "city",
                    "venue",
                    "address",
                    "locationNote",
                    "organizerName",
                    "organizerURL",
                    "contactPhone",
                    "contactEmail",
                    "contactURL",
                    "startDate",
                    "endDate",
                    "participationMode",
                    "capacity",
                    "price",
                    "audience",
                    "minimumAge",
                    "maximumAge",
                    "cancelledAt",
                    "cancellationReason",
                )
        for (key in keys) {
            val rendered = render(f[key])
            add(
                key,
                if (f[key] is String) localized(f, key, rendered, 10_000)
                else ModerationText(rendered),
            )
        }
        if (org) {
            val directory = f["directoryProfile"] as? Map<*, *>
            for (key in
                listOf(
                    "profileKind",
                    "secondaryCategories",
                    "serviceModes",
                    "serviceArea",
                    "specialHoursNote",
                    "services",
                    "orderURL",
                    "bookingURL",
                    "currentOfferTitle",
                    "currentOfferDetails",
                    "currentOfferURL",
                    "currentOfferValidUntil",
                )) {
                val value = render(directory?.get(key))
                add(
                    key,
                    ModerationText(
                        value,
                        render(
                                (f["localizations"] as? Map<*, *>)
                                    ?.get("uk")
                                    .let { it as? Map<*, *> }
                                    ?.get(key)
                            )
                            .ifEmpty { value },
                        render(
                                (f["localizations"] as? Map<*, *>)
                                    ?.get("de")
                                    .let { it as? Map<*, *> }
                                    ?.get(key)
                            )
                            .ifEmpty { value },
                    ),
                )
            }
            val hours = directory?.get("regularHours") as? Map<*, *>
            if (hours != null) {
                if (
                    hours.size > 7 ||
                        hours.keys.any {
                            it !in
                                listOf(
                                    "monday",
                                    "tuesday",
                                    "wednesday",
                                    "thursday",
                                    "friday",
                                    "saturday",
                                    "sunday",
                                )
                        }
                )
                    fail(ModerationFailure.INVALID)
                hours.forEach { (day, value) ->
                    add("hours.$day", ModerationText(text(value, 200)))
                }
            }
        } else {
            val pricing = f["pricing"] as? Map<*, *>
            for (key in listOf("kind", "amount", "maximumAmount", "currencyCode", "note")) add(
                "pricing.$key",
                ModerationText(render(pricing?.get(key))),
            )
            val occurrences = f["occurrences"] as? List<*>
            if (occurrences != null) {
                if (occurrences.size > 30) fail(ModerationFailure.INVALID)
                occurrences.forEachIndexed { index, value ->
                    val occurrence = value as? Map<*, *> ?: fail(ModerationFailure.INVALID)
                    val start =
                        occurrence["startDate"] as? Instant ?: fail(ModerationFailure.INVALID)
                    val end = occurrence["endDate"] as? Instant ?: fail(ModerationFailure.INVALID)
                    add(
                        "occurrence.${index + 1}",
                        ModerationText("$start — $end\n${text(occurrence["status"], 80)}"),
                    )
                }
            }
            val action = f["externalAction"] as? Map<*, *>
            add(
                "externalAction",
                ModerationText(
                    listOf(text(action?.get("title"), 500), text(action?.get("url"), 2048))
                        .filter(String::isNotEmpty)
                        .joinToString("\n")
                ),
            )
        }
        val images =
            listOf("coverURL", "imageURL", "logoURL")
                .mapNotNull { key -> text(f[key], 5000).takeIf(String::isNotEmpty) }
                .distinct()
        val version = runCatching { ModerationReviewVersion.from(target, f) }.getOrNull()
        val organizationFingerprint =
            if (org) {
                try {
                    OrganizationReviewContract.fingerprint(target.id, f)
                } catch (_: OrganizationReviewException) {
                    // A readable legacy/approved preview never grants mutation rights by itself.
                    null
                }
            } else null
        return ModerationPreview(
            item,
            body,
            fields.toList(),
            images,
            version,
            organizationFingerprint,
        )
    }

    fun visible(state: ModerationState, language: String): List<ModerationItem> {
        if (!state.visible || state.session?.allowed != true) return emptyList()
        val query = state.search.trim().lowercase(Locale.ROOT)
        val items =
            state.section.kinds
                .flatMap { kind ->
                    state.parts[kind]
                        ?.takeIf { !it.loading && it.error == null }
                        ?.head
                        ?.items
                        .orEmpty()
                }
                .filter { state.filter == null || it.target.kind == state.filter }
                .filter {
                    query.isEmpty() ||
                        listOf(
                                it.title.value(language),
                                it.summary.value(language),
                                it.submitter.orEmpty(),
                                it.target.id,
                            )
                            .any { value -> value.lowercase(Locale.ROOT).contains(query) }
                }
        val collator =
            Collator.getInstance(Locale.forLanguageTag(if (language == "uk") "uk" else "de"))
        return items.sortedWith { a, b ->
            val primary =
                when (state.sort) {
                    ModerationSort.NEWEST -> b.createdAt.compareTo(a.createdAt)
                    ModerationSort.OLDEST -> a.createdAt.compareTo(b.createdAt)
                    ModerationSort.NAME_ASCENDING ->
                        collator.compare(a.title.value(language), b.title.value(language))
                    ModerationSort.NAME_DESCENDING ->
                        collator.compare(b.title.value(language), a.title.value(language))
                }
            primary.takeUnless { it == 0 }
                ?: "${a.target.kind.name}-${a.target.id}"
                    .compareTo("${b.target.kind.name}-${b.target.id}")
        }
    }
}
