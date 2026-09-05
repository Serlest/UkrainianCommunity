package at.uac.android.feature.history

import at.uac.android.feature.auth.AuthSession
import at.uac.android.feature.browse.Content
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.browse.Fields
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.browse.decodeContent
import at.uac.android.feature.browse.fold
import at.uac.android.feature.browse.string
import at.uac.android.feature.community.communityId
import at.uac.android.feature.personal.validDocumentId
import java.time.Instant
import java.util.UUID

data class HistorySession(val uid: String, val revision: Long, val ready: Boolean) {
    override fun toString() = "HistorySession([redacted], revision=$revision, ready=$ready)"
}

fun AuthSession.historyScope(): HistorySession? =
    identity
        ?.takeUnless { it.anonymous }
        ?.let {
            HistorySession(it.uid, revision, readyForActions && profile?.uid == it.uid)
        }

enum class HistorySection(
    val collection: String,
    val dateField: String,
    val cap: Int,
    val pageSize: Int,
) {
    RECENT("recentViews", "viewedAt", 30, 15),
    ACTIVITY("activityLog", "createdAt", 100, 25),
}

enum class HistoryType(val wire: String, val kind: ContentKind) {
    NEWS("news", ContentKind.NEWS),
    EVENT("event", ContentKind.EVENTS),
    ORGANIZATION("organization", ContentKind.ORGANIZATIONS);

    companion object {
        fun of(kind: ContentKind) = entries.single { it.kind == kind }
    }
}

data class HistoryTarget(val type: HistoryType, val id: String) {
    init {
        require(communityId(id, 512) && validDocumentId("${type.wire}_$id"))
    }

    val path
        get() = "${type.kind.collection}/$id"

    val recentId
        get() = "${type.wire}_$id"

    override fun toString() = "HistoryTarget(${type.wire}, [redacted])"
}

enum class HistoryAction(val wire: String, val type: HistoryType, val saved: Boolean = false) {
    REGISTER("registeredForEvent", HistoryType.EVENT),
    UNREGISTER("canceledEventRegistration", HistoryType.EVENT),
    FOLLOW("followedOrganization", HistoryType.ORGANIZATION),
    UNFOLLOW("unfollowedOrganization", HistoryType.ORGANIZATION),
    SAVE_NEWS("savedNews", HistoryType.NEWS, true),
    UNSAVE_NEWS("unsavedNews", HistoryType.NEWS, true),
    SAVE_EVENT("savedEvent", HistoryType.EVENT, true),
    UNSAVE_EVENT("unsavedEvent", HistoryType.EVENT, true),
    SAVE_ORGANIZATION("savedOrganization", HistoryType.ORGANIZATION, true),
    UNSAVE_ORGANIZATION("unsavedOrganization", HistoryType.ORGANIZATION, true),
}

enum class HistoryFailure {
    SIGN_IN,
    NOT_READY,
    DENIED,
    INVALID,
    MISSING,
    OFFLINE,
    INDEX,
    CONFLICT,
    UNCONFIRMED,
    UNKNOWN,
}

class HistoryException(val failure: HistoryFailure, cause: Throwable? = null) :
    Exception(failure.name, cause)

enum class HistoryFilter {
    ALL,
    NEWS,
    EVENTS,
    ORGANIZATIONS,
    SAVED,
}

enum class HistorySort {
    NEWEST,
    OLDEST,
    NAME_ASCENDING,
    NAME_DESCENDING,
}

/**
 * Snapshot text is private. It is never rendered without fresh target resolution and current safety
 * policy.
 */
data class HistoryRecord(
    val id: String,
    val section: HistorySection,
    val target: HistoryTarget,
    val action: HistoryAction?,
    val title: String,
    val subtitle: String?,
    val imageUrl: String?,
    val at: Instant,
) {
    override fun toString() = "HistoryRecord(${section.name}, [redacted])"
}

data class HistoryEntry(val record: HistoryRecord, val content: Content?) {
    override fun toString() = "HistoryEntry([redacted], available=${content != null})"
}

data class HistoryCursor(
    val session: HistorySession,
    val section: HistorySection,
    val at: Instant,
    val id: String,
    val consumed: Int,
) {
    override fun toString() = "HistoryCursor(${section.name}, consumed=$consumed)"
}

data class HistoryRawPage(val rows: List<RawDocument>, val hasMore: Boolean)

data class HistoryPage(
    val session: HistorySession,
    val section: HistorySection,
    val entries: List<HistoryEntry>,
    val next: HistoryCursor?,
    val capped: Boolean,
    val consumed: Int,
)

data class HistoryWrite(
    val session: HistorySession,
    val section: HistorySection,
    val id: String,
    val target: HistoryTarget,
    val action: HistoryAction?,
    val language: String,
) {
    override fun toString() = "HistoryWrite(${section.name}, [redacted])"
}

data class HistoryDelete(
    val session: HistorySession,
    val section: HistorySection,
    val records: List<HistoryRecord>,
) {
    override fun toString() = "HistoryDelete(${section.name}, count=${records.size})"
}

data class HistoryWriteReceipt(val record: HistoryRecord, val markerCreated: Boolean)

enum class HistoryReconciliation {
    PRESENT,
    ABSENT,
}

object HistoryContract {
    private val recentFields =
        setOf("itemId", "itemType", "title", "subtitle", "imageURL", "viewedAt")
    private val activityFields =
        setOf(
            "id",
            "targetId",
            "targetType",
            "actionType",
            "title",
            "subtitle",
            "imageURL",
            "createdAt",
        )

    private fun invalid(): Nothing = throw HistoryException(HistoryFailure.INVALID)

    fun ready(session: HistorySession) {
        if (!validDocumentId(session.uid) || session.uid.length > 128) invalid()
        if (!session.ready) throw HistoryException(HistoryFailure.NOT_READY)
    }

    fun record(section: HistorySection, row: RawDocument): HistoryRecord {
        val f = row.fields
        if (
            !validDocumentId(row.id) ||
                f.keys.any {
                    it !in if (section == HistorySection.RECENT) recentFields else activityFields
                }
        )
            invalid()
        val typeField = if (section == HistorySection.RECENT) "itemType" else "targetType"
        val idField = if (section == HistorySection.RECENT) "itemId" else "targetId"
        val type = HistoryType.entries.singleOrNull { it.wire == f[typeField] } ?: invalid()
        val target =
            try {
                HistoryTarget(type, f[idField] as? String ?: invalid())
            } catch (_: IllegalArgumentException) {
                invalid()
            }
        val action =
            if (section == HistorySection.ACTIVITY) {
                if (f["id"] != row.id) invalid()
                HistoryAction.entries.singleOrNull { it.wire == f["actionType"] && it.type == type }
                    ?: invalid()
            } else {
                if (row.id != target.recentId) invalid()
                null
            }
        val title = f["title"] as? String ?: invalid()
        val subtitle = f["subtitle"]?.let { it as? String ?: invalid() }
        val image = f["imageURL"]?.let { it as? String ?: invalid() }
        if (title.length > 2_000 || (subtitle?.length ?: 0) > 4_000 || (image?.length ?: 0) > 8_192)
            invalid()
        return HistoryRecord(
            row.id,
            section,
            target,
            action,
            title,
            subtitle,
            image,
            f[section.dateField] as? Instant ?: invalid(),
        )
    }

    fun fields(
        target: HistoryTarget,
        action: HistoryAction?,
        title: String,
        subtitle: String?,
        imageUrl: String?,
        id: String,
        date: Any,
    ): Fields {
        val base = mutableMapOf<String, Any?>("title" to title.take(2_000))
        subtitle?.take(4_000)?.let { base["subtitle"] = it }
        imageUrl?.take(8_192)?.let { base["imageURL"] = it }
        if (action == null) {
            require(id == target.recentId)
            base.putAll(
                mapOf("itemId" to target.id, "itemType" to target.type.wire, "viewedAt" to date)
            )
        } else {
            require(action.type == target.type && validDocumentId(id))
            base.putAll(
                mapOf(
                    "id" to id,
                    "targetId" to target.id,
                    "targetType" to target.type.wire,
                    "actionType" to action.wire,
                    "createdAt" to date,
                )
            )
        }
        return base
    }

    fun write(
        session: HistorySession,
        target: HistoryTarget,
        action: HistoryAction?,
        language: String,
    ): HistoryWrite {
        ready(session)
        require(action == null || action.type == target.type)
        return HistoryWrite(
            session,
            if (action == null) HistorySection.RECENT else HistorySection.ACTIVITY,
            if (action == null) target.recentId else UUID.randomUUID().toString(),
            target,
            action,
            if (language == "uk") "uk" else "de",
        )
    }

    fun validate(write: HistoryWrite) {
        ready(write.session)
        if (write.section == HistorySection.RECENT) {
            if (write.action != null || write.id != write.target.recentId) invalid()
        } else if (
            write.action?.type != write.target.type ||
                runCatching { UUID.fromString(write.id).toString() == write.id }
                    .getOrDefault(false)
                    .not()
        )
            invalid()
    }

    fun delete(value: HistoryDelete) {
        ready(value.session)
        if (
            value.records.size !in 1..value.section.cap ||
                value.records.map { it.id }.distinct().size != value.records.size ||
                value.records.any { it.section != value.section || !validDocumentId(it.id) }
        )
            invalid()
    }

    fun content(target: HistoryTarget, row: RawDocument): Content {
        if (row.id != target.id || row.fields["id"]?.let { it != row.id } == true) invalid()
        val content = decodeContent(target.type.kind, row)
        if (
            target.type != HistoryType.ORGANIZATION &&
                row.fields.string("sourceType") != "organization"
        )
            throw HistoryException(HistoryFailure.DENIED)
        return content
    }

    fun compare(at: Instant, id: String, otherAt: Instant, otherId: String): Int =
        otherAt.compareTo(at).takeIf { it != 0 } ?: -compareIds(id, otherId)

    private fun compareIds(a: String, b: String): Int {
        val x = a.toByteArray(Charsets.UTF_8)
        val y = b.toByteArray(Charsets.UTF_8)
        for (i in 0 until minOf(x.size, y.size)) {
            val result = (x[i].toInt() and 255).compareTo(y[i].toInt() and 255)
            if (result != 0) return result
        }
        return x.size.compareTo(y.size)
    }

    fun selected(
        entries: List<HistoryEntry>,
        filter: HistoryFilter,
        sort: HistorySort,
        search: String,
        language: String,
    ): List<HistoryEntry> =
        entries
            .filter { entry ->
                val target = entry.record.target.type
                val matches =
                    when (filter) {
                        HistoryFilter.ALL -> true
                        HistoryFilter.NEWS -> target == HistoryType.NEWS
                        HistoryFilter.EVENTS -> target == HistoryType.EVENT
                        HistoryFilter.ORGANIZATIONS -> target == HistoryType.ORGANIZATION
                        HistoryFilter.SAVED -> entry.record.action?.saved == true
                    }
                // Hidden snapshot text must not leak through search results or alphabetical
                // ordering.
                matches &&
                    (search.isBlank() ||
                        entry.content?.let {
                            fold(it.title(language)).contains(fold(search.trim()))
                        } == true)
            }
            .sortedWith { a, b ->
                val result =
                    when (sort) {
                        HistorySort.NEWEST -> b.record.at.compareTo(a.record.at)
                        HistorySort.OLDEST -> a.record.at.compareTo(b.record.at)
                        HistorySort.NAME_ASCENDING ->
                            fold(a.content?.title(language).orEmpty())
                                .compareTo(fold(b.content?.title(language).orEmpty()))
                        HistorySort.NAME_DESCENDING ->
                            fold(b.content?.title(language).orEmpty())
                                .compareTo(fold(a.content?.title(language).orEmpty()))
                    }
                result.takeIf { it != 0 } ?: compareIds(a.record.id, b.record.id)
            }
}
