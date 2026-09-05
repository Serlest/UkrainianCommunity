package at.uac.android.feature.authoring

import at.uac.android.feature.auth.AuthValidation
import at.uac.android.feature.browse.Content
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.browse.Fields
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.browse.map
import at.uac.android.feature.browse.string
import at.uac.android.feature.browse.strings
import at.uac.android.feature.organization.OrganizationAuthority
import at.uac.android.feature.organization.OrganizationContract
import at.uac.android.feature.organization.OrganizationRecord
import at.uac.android.feature.organization.OrganizationSession
import java.net.URI
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.UUID

enum class AuthoringFailure {
    SIGN_IN,
    NOT_READY,
    DENIED,
    INVALID,
    MISSING,
    STALE,
    OFFLINE,
    INDEX,
    UNCONFIRMED,
    UNKNOWN,
}

class AuthoringException(
    val failure: AuthoringFailure,
    val field: String? = null,
    cause: Throwable? = null,
) : Exception(failure.name, cause)

enum class AuthoringStatus(val wire: String) {
    APPROVED("approved"),
    REVIEW("pendingReview"),
    REJECTED("rejected"),
    ARCHIVED("archived"),
    SCHEDULED("draft");

    val editable
        get() = this in setOf(APPROVED, REVIEW, REJECTED)
}

data class AuthoringCursor(val createdAt: Instant, val id: String)

data class AuthoringItem(
    val kind: ContentKind,
    val id: String,
    val organizationId: String,
    val status: AuthoringStatus,
    val fields: Fields,
    val createdAt: Instant,
    val updatedAt: Instant,
) {
    val content
        get() = Content(kind, id, fields)

    val editable
        get() = status.editable && fields["cancellationState"] != "cancelled"
}

data class AuthoringPage(val items: List<AuthoringItem>, val next: AuthoringCursor?)

data class AuthoringHub(
    val organization: OrganizationRecord,
    val kind: ContentKind,
    val status: AuthoringStatus,
    val page: AuthoringPage,
)

data class AuthoringOccurrence(
    val id: String = UUID.randomUUID().toString(),
    val start: Instant,
    val end: Instant,
    val allDay: Boolean = false,
    val endKnown: Boolean = true,
    val status: String = "scheduled",
)

data class AuthoringEventDraft(
    val city: String = "",
    val venue: String = "",
    val address: String = "",
    val locationNote: String = "",
    val organizer: String = "",
    val organizerUrl: String = "",
    val contactPhone: String = "",
    val contactEmail: String = "",
    val contactUrl: String = "",
    val occurrences: List<AuthoringOccurrence> = emptyList(),
    val participation: String = "inAppRegistration",
    val capacity: String = "",
    val priceKind: String = "free",
    val amount: String = "",
    val maximumAmount: String = "",
    val priceNote: String = "",
    val currency: String = "EUR",
    val audience: String = "everyone",
    val minimumAge: String = "",
    val maximumAge: String = "",
)

data class AuthoringDraft(
    val id: String = UUID.randomUUID().toString(),
    val kind: ContentKind = ContentKind.NEWS,
    val title: String = "",
    val summary: String = "",
    val body: String = "",
    val germanTitle: String = "",
    val germanSummary: String = "",
    val germanBody: String = "",
    val category: String = "news",
    val additionalCategories: Set<String> = emptySet(),
    val tags: String = "",
    val regionScope: String = "federalState",
    val source: String = "",
    val actionTitle: String = "",
    val actionUrl: String = "",
    val event: AuthoringEventDraft = AuthoringEventDraft(),
    val publicationMode: AuthoringPublicationMode = AuthoringPublicationMode.NOW,
    val scheduledAt: Instant? = null,
)

/**
 * Immutable intent retained after an uncertain create; a retry never silently allocates another
 * content ID.
 */
data class AuthoringSubmission(
    val kind: ContentKind,
    val id: String,
    val organizationId: String,
    val fields: Fields,
    val base: AuthoringItem?,
)

object AuthoringContract {
    const val PAGE_SIZE = 25
    val kinds = listOf(ContentKind.NEWS, ContentKind.EVENTS)
    val newsCategories =
        listOf(
            "news",
            "event",
            "lawAndDocuments",
            "benefitsAndSupport",
            "financeTaxesAndConsumerRights",
            "health",
            "safetyAndEmergencies",
            "work",
            "education",
            "housing",
            "transport",
            "communityAndIntegration",
            "culture",
            "other",
        )
    val eventCategories =
        listOf(
            "meetups",
            "training",
            "culture",
            "education",
            "childrenAndFamily",
            "sportsAndWellness",
            "excursionsAndNature",
            "music",
            "nightlifeAndParties",
            "foodAndMarket",
            "festivalsAndFairs",
            "businessAndNetworking",
            "volunteering",
            "supportAndIntegration",
            "celebration",
            "saleAndPromotion",
            "other",
        )
    val participationModes =
        listOf("none", "inAppRegistration", "externalRegistration", "externalTickets")
    val priceKinds = listOf("unspecified", "free", "exact", "startingFrom", "range")
    val audiences = listOf("everyone", "families", "children", "teens", "adults", "seniors")
    val immutableFields =
        setOf(
            "id",
            "sourceType",
            "organizationId",
            "authorId",
            "authorName",
            "createdAt",
            "publishedAt",
            "likeCount",
            "viewCount",
            "commentCount",
            "registeredCount",
            "likeState",
            "registrationState",
            "imageURL",
            "mediaMetadata",
            "scheduledAt",
            "cancellationState",
            "cancelledAt",
            "cancelledBy",
            "cancellationReason",
        )
    val editableFields =
        setOf(
            "schemaVersion",
            "localizations",
            "title",
            "subtitle",
            "summary",
            "body",
            "details",
            "category",
            "additionalCategories",
            "tags",
            "regionScope",
            "federalState",
            "organizationName",
            "organizationImageURL",
            "sourceName",
            "sourceURL",
            "externalAction",
            "city",
            "venue",
            "address",
            "locationNote",
            "latitude",
            "longitude",
            "organizerName",
            "organizerURL",
            "contactPhone",
            "contactEmail",
            "contactURL",
            "startDate",
            "endDate",
            "occurrences",
            "isAllDay",
            "requiresRegistration",
            "participationMode",
            "capacity",
            "price",
            "pricing",
            "audience",
            "minimumAge",
            "maximumAge",
            "visibility",
            "moderationStatus",
        )

    fun categories(kind: ContentKind) =
        if (kind == ContentKind.NEWS) newsCategories else eventCategories

    fun id(value: String) = OrganizationContract.id(value)

    fun authority(record: OrganizationRecord, session: OrganizationSession): OrganizationRecord {
        if (!session.ready) fail(AuthoringFailure.NOT_READY)
        val actual =
            try {
                OrganizationContract.record(RawDocument(record.id, record.fields), session)
            } catch (error: Exception) {
                throw AuthoringException(AuthoringFailure.INVALID, cause = error)
            }
        if (
            actual.status != "approved" ||
                actual.authority == OrganizationAuthority.NONE ||
                actual.id == "ukrainian-community" && session.globalRole != "owner"
        )
            fail(AuthoringFailure.DENIED)
        return actual
    }

    fun item(
        kind: ContentKind,
        raw: RawDocument,
        organizationId: String,
        status: AuthoringStatus,
        session: OrganizationSession,
    ): AuthoringItem {
        val f = raw.fields
        if (
            kind !in kinds ||
                !id(raw.id) ||
                f["id"] != raw.id ||
                f["sourceType"] != "organization" ||
                f["organizationId"] != organizationId ||
                f["moderationStatus"] != status.wire ||
                f["title"] !is String ||
                f[if (kind == ContentKind.NEWS) "body" else "details"] !is String
        )
            invalid()
        if (
            status == AuthoringStatus.SCHEDULED &&
                (f["authorId"] != session.uid || f["scheduledAt"] !is Instant)
        )
            fail(AuthoringFailure.DENIED)
        val created = f["createdAt"] as? Instant ?: invalid()
        val updated = f["updatedAt"] as? Instant ?: invalid()
        return AuthoringItem(kind, raw.id, organizationId, status, f, created, updated)
    }

    fun page(
        rows: List<RawDocument>,
        kind: ContentKind,
        organizationId: String,
        status: AuthoringStatus,
        session: OrganizationSession,
        after: AuthoringCursor?,
    ): AuthoringPage {
        if (rows.size > PAGE_SIZE + 1 || rows.map { it.id }.distinct().size != rows.size) invalid()
        val items = rows.map { item(kind, it, organizationId, status, session) }
        var previous = after
        for (item in items) {
            val cursor = AuthoringCursor(item.createdAt, item.id)
            if (previous != null && compare(cursor, previous) >= 0) invalid()
            previous = cursor
        }
        val visible = items.take(PAGE_SIZE)
        return AuthoringPage(
            visible,
            if (items.size > PAGE_SIZE) visible.last().let { AuthoringCursor(it.createdAt, it.id) }
            else null,
        )
    }

    private fun compare(a: AuthoringCursor, b: AuthoringCursor): Int =
        a.createdAt.compareTo(b.createdAt).takeUnless { it == 0 } ?: a.id.compareTo(b.id)

    fun newDraft(
        kind: ContentKind,
        organization: OrganizationRecord,
        now: Instant = Instant.now(),
    ): AuthoringDraft {
        if (kind !in kinds) invalid()
        val start = now.plusSeconds(3_600).truncatedTo(ChronoUnit.MINUTES)
        return AuthoringDraft(
            kind = kind,
            category = if (kind == ContentKind.NEWS) "news" else "meetups",
            event =
                AuthoringEventDraft(
                    city = organization.fields.string("city"),
                    organizer = organization.name,
                    occurrences =
                        listOf(AuthoringOccurrence(start = start, end = start.plusSeconds(3_600))),
                ),
        )
    }

    fun draft(item: AuthoringItem): AuthoringDraft {
        val f = item.fields
        val de = f.map("localizations").map("de")
        val event = item.kind == ContentKind.EVENTS
        val rows =
            (f["occurrences"] as? List<*>)
                ?.map { row ->
                    (row as? Map<*, *> ?: invalid()).entries.associate { (key, value) ->
                        (key as? String ?: invalid()) to value
                    }
                }
                .orEmpty()
        val occurrences =
            if (!event) emptyList()
            else
                (rows.ifEmpty {
                        listOf(
                            mapOf(
                                "id" to UUID.randomUUID().toString(),
                                "startDate" to f["startDate"],
                                "endDate" to f["endDate"],
                                "isAllDay" to f["isAllDay"],
                            )
                        )
                    })
                    .map {
                        val start = it["startDate"] as? Instant ?: invalid()
                        val end = it["endDate"] as? Instant ?: invalid()
                        val allDay = it["isAllDay"] == true
                        AuthoringOccurrence(
                            it.string("id").ifEmpty { UUID.randomUUID().toString() },
                            start,
                            if (allDay && end > start) end.minusNanos(1) else end,
                            allDay,
                            end > start,
                            it.string("status").ifEmpty { "scheduled" },
                        )
                    }
        val pricing = f.map("pricing")
        return AuthoringDraft(
            item.id,
            item.kind,
            f.string("title"),
            f.string(if (event) "summary" else "subtitle"),
            f.string(if (event) "details" else "body"),
            de.string("title"),
            de.string(if (event) "summary" else "subtitle"),
            de.string(if (event) "details" else "body"),
            f.string("category").ifEmpty { if (event) "meetups" else "news" },
            f.strings("additionalCategories").toSet(),
            f.strings("tags").joinToString(", "),
            f.string("regionScope").ifEmpty { "federalState" },
            f.string("sourceURL").ifEmpty { f.string("sourceName") },
            f.map("externalAction").string("title"),
            f.map("externalAction").string("url"),
            AuthoringEventDraft(
                f.string("city"),
                f.string("venue"),
                f.string("address"),
                f.string("locationNote"),
                f.string("organizerName"),
                f.string("organizerURL"),
                f.string("contactPhone"),
                f.string("contactEmail"),
                f.string("contactURL"),
                occurrences,
                f.string("participationMode").ifEmpty {
                    if (f["requiresRegistration"] == false) "none" else "inAppRegistration"
                },
                f["capacity"]?.toString().orEmpty(),
                pricing.string("kind").ifEmpty {
                    if ((f["price"] as? Number)?.toDouble() == 0.0) "free" else "exact"
                },
                (pricing["amount"] ?: f["price"])?.toString().orEmpty(),
                pricing["maximumAmount"]?.toString().orEmpty(),
                pricing.string("note"),
                pricing.string("currencyCode").ifEmpty { "EUR" },
                f.string("audience").ifEmpty { "everyone" },
                f["minimumAge"]?.toString().orEmpty(),
                f["maximumAge"]?.toString().orEmpty(),
            ),
        )
    }

    fun submission(
        draft: AuthoringDraft,
        organization: OrganizationRecord,
        session: OrganizationSession,
        base: AuthoringItem?,
        now: Instant = Instant.now(),
        zone: ZoneId = ZoneId.systemDefault(),
    ): AuthoringSubmission {
        authority(organization, session)
        if (
            !id(draft.id) ||
                draft.kind !in kinds ||
                base != null &&
                    (base.id != draft.id ||
                        base.kind != draft.kind ||
                        base.organizationId != organization.id ||
                        !base.editable)
        )
            invalid()
        AuthoringPublication.validateDraft(draft, base, now)
        val event = draft.kind == ContentKind.EVENTS
        val fields = mutableMapOf<String, Any?>()
        fun put(key: String, value: Any?) {
            fields[key] = value
        }
        val title = text(draft.title, 120, true, "title")
        val summary = text(draft.summary, 200, true, "summary")
        val body = text(draft.body, if (event) 50_000 else 10_000, true, "body")
        val deTitle = text(draft.germanTitle, 120, false, "germanTitle")
        val deSummary = text(draft.germanSummary, 200, false, "germanSummary")
        val deBody = text(draft.germanBody, if (event) 2_000 else 10_000, false, "germanBody")
        val localized = base?.fields?.map("localizations").orEmpty().toMutableMap()
        val summaryKey = if (event) "summary" else "subtitle"
        val bodyKey = if (event) "details" else "body"
        localized["uk"] = mapOf("title" to title, summaryKey to summary, bodyKey to body)
        if (listOf(deTitle, deSummary, deBody).any(String::isNotEmpty))
            localized["de"] =
                mapOf(
                    "title" to deTitle.ifEmpty { title },
                    summaryKey to deSummary.ifEmpty { summary },
                    bodyKey to deBody.ifEmpty { body },
                )
        else localized.remove("de")
        put("schemaVersion", 2L)
        put("title", title)
        put(summaryKey, summary)
        put(bodyKey, body)
        put("localizations", localized)
        if (!event) put("summary", summary)
        val categories = categories(draft.kind)
        if (
            draft.category !in categories ||
                draft.additionalCategories.size > 2 ||
                draft.additionalCategories.any { it !in categories || it == draft.category }
        )
            invalid("category")
        put("category", draft.category)
        put("additionalCategories", draft.additionalCategories.sorted())
        val tags = draft.tags.split(',').map(String::trim).filter(String::isNotEmpty).distinct()
        if (
            tags.size > 8 ||
                tags.any { it.codePointCount(0, it.length) > 30 || it.any(Char::isISOControl) }
        )
            invalid("tags")
        put("tags", tags)
        val region =
            if (base == null) organization.fields.string("federalState")
            else base.fields.string("federalState")
        if (
            draft.regionScope !in setOf("federalState", "austria", "city") ||
                (event || draft.regionScope != "austria") && region !in AuthValidation.regions
        )
            invalid("region")
        put(
            "regionScope",
            if (event) base?.fields?.get("regionScope") ?: "federalState" else draft.regionScope,
        )
        put("federalState", if (!event && draft.regionScope == "austria") null else region)
        put(
            "organizationName",
            if (base == null) organization.name else base.fields["organizationName"],
        )
        put(
            "organizationImageURL",
            if (base == null) organization.fields["imageURL"] ?: organization.fields["logoURL"]
            else base.fields["organizationImageURL"],
        )
        val actionTitle = text(draft.actionTitle, 120, false, "action")
        val actionUrl = web(draft.actionUrl, true, "action")
        if (actionTitle.isNotEmpty() && actionUrl.isEmpty()) invalid("action")
        val usesAction =
            !event || draft.event.participation in setOf("externalRegistration", "externalTickets")
        put(
            "externalAction",
            actionUrl
                .takeIf { it.isNotEmpty() && usesAction }
                ?.let {
                    mapOf("url" to it) +
                        if (actionTitle.isEmpty()) emptyMap() else mapOf("title" to actionTitle)
                },
        )
        if (event)
            eventFields(draft.event, base, now, zone, actionUrl).forEach { (key, value) ->
                put(key, value)
            }
        else {
            val source = text(draft.source, 2_048, false, "source")
            val url = if (source.contains("://")) web(source, false, "source") else ""
            put("sourceURL", url.takeIf(String::isNotEmpty))
            put(
                "sourceName",
                if (url.isEmpty()) source.takeIf(String::isNotEmpty) else URI(url).host,
            )
        }
        val status =
            when {
                base == null && draft.publicationMode == AuthoringPublicationMode.SCHEDULED ->
                    AuthoringStatus.SCHEDULED
                !event &&
                    draft.regionScope == "austria" &&
                    session.globalRole != "owner" &&
                    (base == null || base.status == AuthoringStatus.APPROVED) ->
                    AuthoringStatus.REVIEW
                else -> base?.status ?: AuthoringStatus.APPROVED
            }
        put("moderationStatus", status.wire)
        if (status == AuthoringStatus.SCHEDULED)
            put("scheduledAt", requireNotNull(draft.scheduledAt).truncatedTo(ChronoUnit.MICROS))
        if (base == null) {
            val time = now.truncatedTo(ChronoUnit.MICROS)
            fields +=
                mapOf(
                    "id" to draft.id,
                    "sourceType" to "organization",
                    "organizationId" to organization.id,
                    "authorId" to session.uid,
                    "authorName" to session.name.filterNot(Char::isISOControl).trim().take(160),
                    "createdAt" to time,
                    "updatedAt" to time,
                    "likeCount" to 0L,
                    "viewCount" to 0L,
                    "commentCount" to 0L,
                    "likeState" to "notLiked",
                )
            if (event)
                fields += mapOf("registeredCount" to 0L, "registrationState" to "notRegistered")
            else fields["publishedAt"] = time
        }
        return AuthoringSubmission(draft.kind, draft.id, organization.id, fields.toMap(), base)
    }

    private fun eventFields(
        d: AuthoringEventDraft,
        base: AuthoringItem?,
        now: Instant,
        zone: ZoneId,
        actionUrl: String,
    ): Fields {
        val city = text(d.city, 160, true, "city")
        val venue = text(d.venue, 240, false, "venue")
        val address = text(d.address, 500, false, "address")
        if (venue.isEmpty() && address.isEmpty()) invalid("venue")
        if (
            d.occurrences.size !in 1..30 ||
                d.occurrences.map { it.id }.distinct().size != d.occurrences.size
        )
            invalid("dates")
        val mapped = d.occurrences.map { occurrence(it, base != null, now, zone) }
        val occurrences = mapped.take(1) + mapped.drop(1).sortedBy { it["startDate"] as Instant }
        val first = occurrences.first()
        if (
            d.participation !in participationModes ||
                d.participation in setOf("externalRegistration", "externalTickets") &&
                    actionUrl.isEmpty()
        )
            invalid("participation")
        val capacity =
            if (d.participation == "inAppRegistration")
                integer(d.capacity, 1, Int.MAX_VALUE, "capacity")
            else null
        val registered = (base?.fields?.get("registeredCount") as? Number)?.toLong() ?: 0L
        if (capacity != null && capacity.toLong() < registered) invalid("capacity")
        val minAge = integer(d.minimumAge, 0, 120, "age")
        val maxAge = integer(d.maximumAge, 0, 120, "age")
        if (minAge != null && maxAge != null && minAge > maxAge || d.audience !in audiences)
            invalid("age")
        if (d.priceKind !in priceKinds || !Regex("[A-Z]{3}").matches(d.currency)) invalid("price")
        val amount =
            if (d.priceKind in setOf("exact", "startingFrom", "range")) decimal(d.amount) else null
        val maximum = if (d.priceKind == "range") decimal(d.maximumAmount) else null
        if (maximum != null && maximum < requireNotNull(amount)) invalid("price")
        val pricing: Fields =
            mapOf("kind" to d.priceKind, "currencyCode" to d.currency) +
                listOfNotNull(
                        amount?.let { "amount" to it },
                        maximum?.let { "maximumAmount" to it },
                        text(d.priceNote, 500, false, "price").takeIf(String::isNotEmpty)?.let {
                            "note" to it
                        },
                    )
                    .toMap()
        val email = text(d.contactEmail, 320, false, "contact")
        if (email.isNotEmpty() && (!email.contains('@') || email.any(Char::isWhitespace)))
            invalid("contact")
        val values =
            mutableMapOf<String, Any?>(
                "city" to city,
                "venue" to venue,
                "address" to address.takeIf(String::isNotEmpty),
                "locationNote" to
                    text(d.locationNote, 160, false, "locationNote").takeIf(String::isNotEmpty),
                "organizerName" to
                    text(d.organizer, 160, false, "organizer").takeIf(String::isNotEmpty),
                "organizerURL" to
                    web(d.organizerUrl, false, "organizer").takeIf(String::isNotEmpty),
                "contactPhone" to
                    text(d.contactPhone, 80, false, "contact").takeIf(String::isNotEmpty),
                "contactEmail" to email.takeIf(String::isNotEmpty),
                "contactURL" to web(d.contactUrl, false, "contact").takeIf(String::isNotEmpty),
                "startDate" to first["startDate"],
                "endDate" to first["endDate"],
                "isAllDay" to first["isAllDay"],
                "occurrences" to occurrences,
                "requiresRegistration" to (d.participation == "inAppRegistration"),
                "participationMode" to d.participation,
                "capacity" to capacity?.toLong(),
                "price" to (amount ?: 0.0),
                "pricing" to pricing,
                "audience" to d.audience,
                "minimumAge" to minAge?.toLong(),
                "maximumAge" to maxAge?.toLong(),
                "visibility" to "public",
            )
        if (
            base != null &&
                (base.fields.string("city") != city ||
                    base.fields.string("address") != address ||
                    base.fields.string("venue") != venue)
        ) {
            values["latitude"] = null
            values["longitude"] = null
        }
        return values
    }

    fun occurrence(
        value: AuthoringOccurrence,
        editing: Boolean,
        now: Instant,
        zone: ZoneId,
    ): Fields {
        if (!id(value.id) || value.status !in setOf("scheduled", "cancelled")) invalid("dates")
        val start =
            if (value.allDay) value.start.atZone(zone).toLocalDate().atStartOfDay(zone).toInstant()
            else value.start
        val end =
            if (!value.endKnown) start
            else if (value.allDay)
                value.end.atZone(zone).toLocalDate().plusDays(1).atStartOfDay(zone).toInstant()
            else value.end
        if (
            value.endKnown && end <= start ||
                !editing &&
                    start <
                        (if (value.allDay)
                            now.atZone(zone).toLocalDate().atStartOfDay(zone).toInstant()
                        else now.minusSeconds(60))
        )
            invalid("dates")
        return mapOf(
            "id" to value.id,
            "startDate" to start.truncatedTo(ChronoUnit.MICROS),
            "endDate" to end.truncatedTo(ChronoUnit.MICROS),
            "isAllDay" to value.allDay,
            "status" to value.status,
        )
    }

    fun matches(submission: AuthoringSubmission, actual: AuthoringItem): Boolean =
        actual.kind == submission.kind &&
            actual.id == submission.id &&
            actual.organizationId == submission.organizationId &&
            submission.fields.all { (key, value) ->
                if (key == "updatedAt") true
                else if (value == null) key !in actual.fields || actual.fields[key] == null
                else actual.fields[key] == value
            } &&
            (submission.base == null ||
                immutableFields.all { actual.fields[it] == submission.base.fields[it] })

    fun unchanged(base: AuthoringItem, actual: AuthoringItem) {
        if (
            base.kind != actual.kind ||
                base.id != actual.id ||
                base.fields != actual.fields ||
                base.updatedAt != actual.updatedAt
        )
            fail(AuthoringFailure.STALE)
    }

    private fun text(value: String, maximum: Int, required: Boolean, field: String): String =
        value.trim().also {
            if (
                it.codePointCount(0, it.length) > maximum ||
                    required && it.isEmpty() ||
                    it.any { c -> c.isISOControl() && c != '\n' && c != '\t' }
            )
                invalid(field)
        }

    fun web(value: String, httpsOnly: Boolean, field: String = "link"): String {
        val text = value.trim()
        if (text.isEmpty()) return ""
        val uri = runCatching { URI(text) }.getOrNull() ?: invalid(field)
        if (
            text.length > 2_048 ||
                text.any { it.isWhitespace() || it.isISOControl() } ||
                '\\' in text ||
                uri.host.isNullOrBlank() ||
                uri.userInfo != null ||
                uri.port > 65_535 ||
                uri.scheme?.lowercase() !in
                    if (httpsOnly) setOf("https") else setOf("http", "https")
        )
            invalid(field)
        return text
    }

    private fun integer(value: String, minimum: Int, maximum: Int, field: String): Int? =
        value.trim().takeIf(String::isNotEmpty)?.let { text ->
            if (!Regex("[0-9]+").matches(text)) invalid(field)
            text.toIntOrNull()?.takeIf { it in minimum..maximum } ?: invalid(field)
        }

    private fun decimal(value: String): Double =
        value.trim().replace(',', '.').let { text ->
            if (!Regex("[0-9]+(?:\\.[0-9]{1,2})?").matches(text)) invalid("price")
            text.toDoubleOrNull()?.takeIf { it.isFinite() && it >= 0 && it <= 1_000_000_000 }
                ?: invalid("price")
        }

    fun invalid(field: String? = null): Nothing =
        throw AuthoringException(AuthoringFailure.INVALID, field)

    fun fail(failure: AuthoringFailure): Nothing = throw AuthoringException(failure)
}
