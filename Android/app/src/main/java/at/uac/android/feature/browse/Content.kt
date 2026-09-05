package at.uac.android.feature.browse

import java.net.URI
import java.text.Normalizer
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

typealias Fields = Map<String, Any?>

@Suppress("UNCHECKED_CAST") fun Fields.map(key: String): Fields = this[key] as? Fields ?: emptyMap()

fun Fields.string(key: String): String = (this[key] as? String)?.trim().orEmpty()

fun Fields.strings(key: String): List<String> =
    (this[key] as? List<*>)?.filterIsInstance<String>().orEmpty()

fun Fields.time(key: String): Instant? = this[key] as? Instant

fun Fields.count(key: String): Long = (this[key] as? Number)?.toLong()?.coerceAtLeast(0) ?: 0

fun tr(language: String, de: String, uk: String) = if (language == "uk") uk else de

enum class ContentKind(val collection: String, val de: String, val uk: String, val order: String) {
    NEWS("news", "Nachrichten", "Новини", "publishedAt"),
    EVENTS("events", "Veranstaltungen", "Події", "endDate"),
    ORGANIZATIONS("organizations", "Organisationen", "Організації", "createdAt");

    fun label(language: String) = tr(language, de, uk)
}

enum class ReadFailure {
    OFFLINE,
    DENIED,
    INVALID,
    MISSING,
    INDEX,
    UNKNOWN,
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
            (query.audience.isEmpty() || fields.string("audience") == query.audience) &&
            fold(
                    listOf(
                            title(query.language),
                            summary(query.language),
                            body(query.language),
                            fields.string("city"),
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
    val recommendations: Boolean = false,
) {
    val ascending
        get() = kind == ContentKind.EVENTS && !past && !recommendations

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
                (kind != ContentKind.EVENTS ||
                    recommendations ||
                    if (past) time("endDate")!! < now else time("endDate")!! >= now)
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
            sections.all { it in listOf("home", "events", "organizations") } &&
            image.scheme in listOf("https", "http") &&
            !image.host.isNullOrBlank() &&
            fields.string("regionScope") in listOf("allAustria", "federalState") &&
            (fields.string("regionScope") != "federalState" ||
                regions.any { it.first == fields.string("federalState") }) &&
            (action !in listOf("news", "event", "organization") ||
                fields.string("actionTargetID").let { it.isNotBlank() && '/' !in it }) &&
            (action != "externalURL" || safeHttps(fields.string("externalURL")) != null) &&
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
        fields.string(key + if (language == "uk") "UK" else "DE")
}
