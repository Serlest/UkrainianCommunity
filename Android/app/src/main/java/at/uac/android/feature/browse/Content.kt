package at.uac.android.feature.browse

import java.net.URI
import java.text.Normalizer
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

typealias Fields = Map<String, Any?>

@Suppress("UNCHECKED_CAST") fun Fields.map(key: String): Fields = this[key] as? Fields ?: emptyMap()

fun Fields.string(key: String): String = (this[key] as? String)?.trim().orEmpty()

fun Fields.strings(key: String): List<String> =
    (this[key] as? List<*>)?.filterIsInstance<String>().orEmpty()

/** Mirrors Organization's iOS normalization while preserving cover-first detail presentation. */
fun organizationImageUrl(fields: Fields, preferCover: Boolean): String {
    val keys =
        if (preferCover) listOf("coverURL", "imageURL", "logoURL")
        else listOf("logoURL", "imageURL", "coverURL")
    return keys.firstNotNullOfOrNull { key -> fields.string(key).takeIf(String::isNotBlank) }
        .orEmpty()
}

fun Fields.time(key: String): Instant? = this[key] as? Instant

fun Fields.count(key: String): Long = (this[key] as? Number)?.toLong()?.coerceAtLeast(0) ?: 0

data class FeedEventOccurrence(
    val start: Instant,
    val end: Instant,
    val allDay: Boolean,
    val cancelled: Boolean,
)

fun Fields.eventOccurrences(): List<FeedEventOccurrence> {
    val explicit = (this["occurrences"] as? List<*>)
        ?.filterIsInstance<Map<*, *>>()
        ?.mapNotNull { row ->
            val start = row["startDate"] as? Instant ?: return@mapNotNull null
            val end = row["endDate"] as? Instant ?: return@mapNotNull null
            if (end < start) return@mapNotNull null
            FeedEventOccurrence(start, end, row["isAllDay"] == true,
                row["status"] == "cancelled")
        }
        .orEmpty()
        .sortedBy(FeedEventOccurrence::start)
    if (explicit.isNotEmpty()) return explicit
    val start = time("startDate") ?: return emptyList()
    val end = time("endDate") ?: return emptyList()
    return if (end >= start) listOf(FeedEventOccurrence(
        start, end, this["isAllDay"] == true, false
    )) else emptyList()
}

fun Fields.nextEventOccurrence(now: Instant): FeedEventOccurrence? =
    eventOccurrences().firstOrNull { !it.cancelled && it.end >= now }

fun Fields.displayEventOccurrence(now: Instant): FeedEventOccurrence? =
    nextEventOccurrence(now) ?: eventOccurrences().firstOrNull()

fun tr(language: String, de: String, uk: String) = if (language == "uk") uk else de

enum class ContentKind(val collection: String, val de: String, val uk: String, val order: String) {
    NEWS("news", "Nachrichten", "Новини", "publishedAt"),
    EVENTS("events", "Veranstaltungen", "Події", "endDate"),
    ORGANIZATIONS("organizations", "Organisationen", "Організації", "createdAt");

    fun label(language: String) = tr(language, de, uk)
}

enum class EventPeriod { ALL, TODAY, THIS_WEEK }

enum class EventScope { ALL, SAVED, REGISTERED }

enum class EventAge(val lower: Int, val upper: Int) {
    ANY(0, 120), CHILD(0, 12), TEEN(13, 17), ADULT(18, 120),
}

enum class OrganizationScope { ALL, SUBSCRIBED, BOOKMARKED }

enum class ReadFailure {
    OFFLINE,
    DENIED,
    INVALID,
    MISSING,
    INDEX,
    UNKNOWN,
}

enum class NewsPeriod {
    ALL,
    TODAY,
    SEVEN_DAYS,
    THIRTY_DAYS,
    CUSTOM,
}

enum class NewsOrder {
    NEWEST,
    OLDEST,
}

enum class NewsSource {
    ALL,
    SAVED,
    SUBSCRIBED,
}

data class NewsDateRange(val startInclusive: Instant?, val endExclusive: Instant?)

fun newsDateRange(
    period: NewsPeriod,
    now: Instant,
    zone: ZoneId = ZoneId.of("Europe/Vienna"),
    customStart: LocalDate? = null,
    customEnd: LocalDate? = null,
): NewsDateRange {
    val today = now.atZone(zone).toLocalDate()
    val dates =
        when (period) {
            NewsPeriod.ALL -> return NewsDateRange(null, null)
            NewsPeriod.TODAY -> today to today
            NewsPeriod.SEVEN_DAYS -> today.minusDays(6) to today
            NewsPeriod.THIRTY_DAYS -> today.minusDays(29) to today
            NewsPeriod.CUSTOM -> {
                val start = requireNotNull(customStart)
                val end = requireNotNull(customEnd)
                require(!end.isBefore(start))
                start to end
            }
        }
    return NewsDateRange(
        dates.first.atStartOfDay(zone).toInstant(),
        dates.second.plusDays(1).atStartOfDay(zone).toInstant(),
    )
}

class ReadException(val reason: ReadFailure, cause: Throwable? = null) :
    Exception(reason.name, cause)

data class RawDocument(val id: String, val fields: Fields)

data class Content(val kind: ContentKind, val id: String, val fields: Fields) {
    fun localization(language: String): Fields {
        val all = fields.map("localizations")
        return all.map(language)
            .ifEmpty { all.map("uk") }
            .ifEmpty {
                all.keys
                    .sorted()
                    .firstNotNullOfOrNull { key -> all.map(key).takeIf { it.isNotEmpty() } }
                    .orEmpty()
            }
    }

    fun text(key: String, language: String, vararg legacy: String): String =
        localization(language).string(key).ifEmpty {
            (listOf(key) + legacy)
                .firstNotNullOfOrNull { fields.string(it).takeIf(String::isNotBlank) }
                .orEmpty()
        }

    fun title(language: String) =
        text(if (kind == ContentKind.ORGANIZATIONS) "name" else "title", language)

    fun summary(language: String) =
        when (kind) {
            ContentKind.NEWS -> text("subtitle", language, "summary")
            ContentKind.EVENTS -> text("summary", language)
            ContentKind.ORGANIZATIONS -> text("shortDescription", language, "description")
        }

    fun body(language: String) =
        when (kind) {
            ContentKind.NEWS -> text("body", language)
            ContentKind.EVENTS -> text("details", language)
            ContentKind.ORGANIZATIONS ->
                text("fullDescription", language, "description", "shortDescription")
        }

    val publishedAt: Instant
        get() = fields.time("publishedAt") ?: fields.time("createdAt")!!

    val category: String
        get() =
            fields.string("category").ifEmpty {
                fields.map("directoryProfile").string("profileKind").ifEmpty { "community" }
            }

    fun matches(query: ContentQuery): Boolean {
        val categories =
            listOf(category) +
                fields.strings("additionalCategories") +
                fields.map("directoryProfile").strings("secondaryCategories")
        return (query.category.isEmpty() || query.category in categories) &&
            (query.audience.isEmpty() || fields.string("audience") in setOf("everyone", query.audience)) &&
            (kind != ContentKind.EVENTS || query.matchesEventDiscovery(fields)) &&
            fold(
                    listOf(
                            title(query.language),
                            summary(query.language),
                            body(query.language),
                            fields.string("city"),
                            fields.string("authorDisplayName"),
                            fields.string("authorName"),
                            fields.string("organizationName"),
                            fields.string("publisherName"),
                            kind.label(query.language),
                            fields.strings("tags").joinToString(" "),
                        )
                        .joinToString(" ")
                )
                .contains(fold(query.search.trim()))
    }
}

fun decodeContent(kind: ContentKind, document: RawDocument): Content {
    val f = document.fields
    if (f.string("moderationStatus") != "approved") throw ReadException(ReadFailure.DENIED)
    val required =
        when (kind) {
            ContentKind.NEWS -> listOf("title", "body")
            ContentKind.EVENTS -> listOf("title", "summary", "details")
            ContentKind.ORGANIZATIONS -> listOf("name", "city")
        }
    if (
        document.id.isBlank() ||
            required.any { f[it] !is String } ||
            f.time("createdAt") == null ||
            f.time("updatedAt") == null ||
            (kind == ContentKind.ORGANIZATIONS &&
                listOf("description", "shortDescription", "fullDescription").none {
                    f[it] is String
                })
    )
        throw ReadException(ReadFailure.INVALID)
    if (kind == ContentKind.EVENTS) {
        val start = f.time("startDate") ?: throw ReadException(ReadFailure.INVALID)
        val end = f.time("endDate") ?: throw ReadException(ReadFailure.INVALID)
        if (end < start) throw ReadException(ReadFailure.INVALID)
    }
    return Content(kind, document.id, f)
}

fun fold(value: String): String =
    Normalizer.normalize(value.lowercase(Locale.ROOT), Normalizer.Form.NFD)
        .replace(Regex("\\p{M}+"), "")

/** Never derive the cursor from a localized or client-filtered sort. Nanoseconds are retained. */
data class ContentCursor(val time: Instant, val id: String)

data class ContentQuery(
    val kind: ContentKind,
    val region: String = "",
    val search: String = "",
    val category: String = "",
    val language: String = "de",
    val past: Boolean = false,
    val organizationId: String = "",
    val now: Instant = Instant.now(),
    val audience: String = "",
    val eventPeriod: EventPeriod = EventPeriod.ALL,
    val eventAge: EventAge = EventAge.ANY,
    val eventScope: EventScope = EventScope.ALL,
    val organizationScope: OrganizationScope = OrganizationScope.ALL,
    val recommendations: Boolean = false,
    val newsPeriod: NewsPeriod = NewsPeriod.ALL,
    val newsOrder: NewsOrder = NewsOrder.NEWEST,
    val newsSource: NewsSource = NewsSource.ALL,
    val customStart: LocalDate? = null,
    val customEnd: LocalDate? = null,
    val allowedNewsIds: Set<String>? = null,
    val allowedEventIds: Set<String>? = null,
    val allowedOrganizationIds: Set<String>? = null,
) {
    fun matchesEventDiscovery(fields: Fields): Boolean {
        if (recommendations) return true
        val start = fields.displayEventOccurrence(now)?.start ?: return false
        val date = start.atZone(java.time.ZoneId.systemDefault()).toLocalDate()
        val today = now.atZone(java.time.ZoneId.systemDefault()).toLocalDate()
        val periodMatches = when (if (past) EventPeriod.ALL else eventPeriod) {
            EventPeriod.ALL -> true
            EventPeriod.TODAY -> date == today
            EventPeriod.THIS_WEEK -> {
                val firstDay = java.time.temporal.WeekFields.of(Locale.getDefault()).firstDayOfWeek
                val first = today.with(java.time.temporal.TemporalAdjusters.previousOrSame(firstDay))
                date >= first && date < first.plusWeeks(1)
            }
        }
        val min = (fields["minimumAge"] as? Number)?.toInt() ?: 0
        val max = (fields["maximumAge"] as? Number)?.toInt() ?: 120
        return periodMatches && min <= eventAge.upper && max >= eventAge.lower
    }

    val newsDates: NewsDateRange
        get() = newsDateRange(newsPeriod, now, customStart = customStart, customEnd = customEnd)

    val ascending
        get() =
            if (kind == ContentKind.NEWS && !recommendations) newsOrder == NewsOrder.OLDEST
            else kind == ContentKind.EVENTS && !past && !recommendations

    val orderField
        get() = if (recommendations && kind == ContentKind.EVENTS) "createdAt" else kind.order

    fun cursor(doc: RawDocument): ContentCursor =
        ContentCursor(
            doc.fields.time(orderField) ?: throw ReadException(ReadFailure.INVALID),
            doc.id,
        )

    fun compare(a: ContentCursor, b: ContentCursor): Int {
        val result = a.time.compareTo(b.time).takeIf { it != 0 } ?: a.id.compareTo(b.id)
        return if (ascending) result else -result
    }

    fun acceptsRaw(doc: RawDocument): Boolean =
        with(doc.fields) {
            string("moderationStatus") == "approved" &&
                (kind == ContentKind.ORGANIZATIONS || string("sourceType") == "organization") &&
                (region.isEmpty() ||
                    string("regionScope") == "austria" ||
                    string("federalState") == region) &&
                (organizationId.isEmpty() || string("organizationId") == organizationId) &&
                (!recommendations || string("category") == category) &&
                time(orderField) != null &&
                (kind != ContentKind.NEWS ||
                    (newsDates.startInclusive?.let { time("publishedAt")!! >= it } ?: true) &&
                        (newsDates.endExclusive?.let { time("publishedAt")!! < it } ?: true) &&
                        when (newsSource) {
                            NewsSource.ALL -> true
                            NewsSource.SAVED -> allowedNewsIds?.contains(doc.id) == true
                            NewsSource.SUBSCRIBED ->
                                allowedOrganizationIds?.contains(string("organizationId")) == true
                        }) &&
                (kind != ContentKind.ORGANIZATIONS || organizationScope == OrganizationScope.ALL ||
                    allowedOrganizationIds?.contains(doc.id) == true) &&
                (kind != ContentKind.EVENTS ||
                    recommendations ||
                    ((if (past) nextEventOccurrence(now) == null else nextEventOccurrence(now) != null) &&
                        (eventScope == EventScope.ALL || allowedEventIds?.contains(doc.id) == true)))
        }
}

fun safeHttps(value: String, allowBareHost: Boolean = false): String? = runCatching {
    val trimmed = value.trim()
    if (
        trimmed.isEmpty() ||
            trimmed.any { it.isWhitespace() || it.isISOControl() } ||
            '\\' in trimmed
    )
        return null
    val normalized = if (allowBareHost && !trimmed.contains("://")) "https://$trimmed" else trimmed
    val uri = URI(normalized)
    if (
        uri.scheme != "https" ||
            uri.host.isNullOrBlank() ||
            uri.rawUserInfo != null ||
            uri.port !in listOf(-1, 443)
    )
        null
    else uri.toASCIIString()
}
    .getOrNull()

/** Browser destinations use their content contract, independently of media/donation policies. */
enum class WebLinkPolicy { STRICT_HTTPS, DIRECTORY_SOURCE, BANNER_ACTION }

fun safeWebLink(value: String, policy: WebLinkPolicy): String? {
    if (policy == WebLinkPolicy.STRICT_HTTPS) return safeHttps(value)
    return runCatching {
        val text = value.trim()
        if (text.isEmpty() || text.length > 2048 || text.any { it.isWhitespace() || it.isISOControl() } || '\\' in text) return null
        val uri = URI(text)
        val schemes = if (policy == WebLinkPolicy.DIRECTORY_SOURCE) setOf("https") else setOf("http", "https")
        if (uri.scheme?.lowercase() !in schemes || uri.host.isNullOrBlank() || uri.rawUserInfo != null ||
            uri.port !in -1..65535) null else uri.toASCIIString()
    }.getOrNull()
}

fun displayTime(
    value: Instant,
    language: String,
    allDay: Boolean = false,
    zone: ZoneId = ZoneId.systemDefault(),
): String =
    DateTimeFormatter.ofPattern(
            if (allDay) "dd MMM yyyy" else "dd MMM yyyy, HH:mm z",
            Locale.forLanguageTag(language),
        )
        .withZone(zone)
        .format(value)

data class Banner(val id: String, val fields: Fields) {
    fun valid(): Boolean {
        val action = fields.string("actionType")
        val sections = fields.strings("visibleSections")
        val localized = fields.map("localizations")
        val duration = (fields["displayDurationSeconds"] as? Number)?.toInt() ?: return false
        val priority = (fields["priority"] as? Number)?.toInt() ?: return false
        val image = runCatching { URI(fields.string("imageURL")) }.getOrNull() ?: return false
        return fields.string("id") == id &&
            fields.string("createdBy").isNotBlank() &&
            fields.keys.all { it in bannerFields } &&
            fields.time("createdAt") != null &&
            fields.time("updatedAt") != null &&
            duration in 3..12 &&
            priority in 0..1000 &&
            fields.string("title").length <= 120 &&
            fields.string("subtitle").length <= 240 &&
            fields.string("internalName").length <= 120 &&
            sections.isNotEmpty() &&
            sections.all { it in bannerSections } &&
            image.scheme in listOf("https", "http") &&
            !image.host.isNullOrBlank() &&
            fields.string("regionScope") in listOf("allAustria", "federalState") &&
            (fields.string("regionScope") != "federalState" ||
                regions.any { it.first == fields.string("federalState") }) &&
            (action !in listOf("news", "event", "organization") ||
                fields.string("actionTargetID").let { it.isNotBlank() && '/' !in it }) &&
            (action != "externalURL" || safeWebLink(fields.string("externalURL"), WebLinkPolicy.BANNER_ACTION) != null) &&
            (fields.time("startsAt") == null ||
                fields.time("endsAt") == null ||
                fields.time("startsAt")!! < fields.time("endsAt")!!) &&
            localized.keys.all { it in listOf("de", "uk") } &&
            localized.keys.all {
                localized.map(it).string("title").length <= 120 &&
                    localized.map(it).string("subtitle").length <= 240
            }
    }

    fun text(key: String, language: String): String {
        val all = fields.map("localizations")
        return all.map(language)
            .string(key)
            .ifEmpty { all.map("uk").string(key) }
            .ifEmpty {
                all.keys
                    .sorted()
                    .firstNotNullOfOrNull { all.map(it).string(key).takeIf(String::isNotEmpty) }
                    .orEmpty()
            }
            .ifEmpty { fields.string(key) }
    }

    fun visible(section: String, region: String, now: Instant): Boolean =
        valid() &&
            fields["isActive"] == true &&
            fields.string("actionType") in bannerActions &&
            section in fields.strings("visibleSections") &&
            (fields.time("startsAt")?.let { now >= it } ?: true) &&
            (fields.time("endsAt")?.let { now <= it } ?: true) &&
            (region.isEmpty() ||
                fields.string("regionScope") == "allAustria" ||
                fields.string("federalState") == region)
}

val bannerActions = listOf("none", "news", "event", "organization", "externalURL")
val bannerSections = setOf("home", "events", "organizations", "directory")
private val bannerFields =
    setOf(
        "id",
        "internalName",
        "localizations",
        "title",
        "subtitle",
        "imageURL",
        "actionType",
        "actionTargetID",
        "externalURL",
        "regionScope",
        "federalState",
        "visibleSections",
        "displayDurationSeconds",
        "priority",
        "isActive",
        "startsAt",
        "endsAt",
        "createdAt",
        "updatedAt",
        "createdBy",
        "updatedBy",
    )

fun visibleBanners(
    rows: List<RawDocument>,
    section: String,
    region: String,
    now: Instant,
): List<Banner> =
    rows
        .map { Banner(it.id, it.fields) }
        .filter { it.visible(section, region, now) }
        .sortedWith(
            compareByDescending<Banner> { it.fields.count("priority") }
                .thenByDescending { it.fields.time("updatedAt") }
                .thenBy { it.id }
        )

data class Donation(val fields: Fields) {
    val url
        get() =
            if (fields["isEnabled"] == true)
                safeHttps(fields.string("donationURL"), true)?.takeIf {
                    URI(it).host.split('.').let { labels ->
                        labels.size >= 2 &&
                            labels.all { label ->
                                label.isNotEmpty() &&
                                    label.all { c -> c.isLetterOrDigit() || c == '-' }
                            }
                    }
                }
            else null

    fun text(key: String, language: String) =
        fields.string(key + if (language == "uk") "UK" else "DE").trim().ifEmpty {
            donationDefaultText(key, language)
        }
}

fun donationDefaultText(key: String, language: String): String =
    when (key) {
        "title" -> tr(language, "Projekt unterstützen", "Підтримати проєкт")
        "buttonTitle" -> tr(language, "Unterstützen", "Підтримати")
        "message" ->
            tr(
                language,
                "Ukrainian Community ist ein nicht-kommerzielles Projekt zur Unterstützung von Ukrainerinnen und Ukrainern in Österreich. Wenn Sie die Weiterentwicklung und den Betrieb der App unterstützen möchten, können Sie freiwillig spenden.",
                "Ukrainian Community — некомерційний проєкт, створений для підтримки українців в Австрії. Якщо ви хочете допомогти з розвитком і підтримкою додатку, можете зробити добровільний внесок.",
            )
        else -> ""
    }
