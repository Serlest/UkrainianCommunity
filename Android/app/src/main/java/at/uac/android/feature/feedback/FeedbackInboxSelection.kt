package at.uac.android.feature.feedback

import java.text.Normalizer
import java.util.Locale

enum class FeedbackInboxFilter {
    OPEN,
    ANSWERED,
    CLOSED,
    UNKNOWN,
    ALL;

    fun includes(status: FeedbackStatus): Boolean =
        when (this) {
            OPEN -> status == FeedbackStatus.OPEN
            ANSWERED -> status == FeedbackStatus.ANSWERED || status == FeedbackStatus.REVIEWED
            CLOSED -> status == FeedbackStatus.CLOSED || status == FeedbackStatus.ARCHIVED
            UNKNOWN -> status == FeedbackStatus.UNKNOWN
            ALL -> true
        }
}

enum class FeedbackInboxSort {
    NEWEST,
    OLDEST,
}

/** Memory-only query; never saved, logged, sent to Firebase, or used to construct a cursor. */
data class FeedbackInboxOptions(
    val query: String = "",
    val filter: FeedbackInboxFilter = FeedbackInboxFilter.OPEN,
    val sort: FeedbackInboxSort = FeedbackInboxSort.NEWEST,
) {
    override fun toString() = "FeedbackInboxOptions(filter=$filter, sort=$sort, query=[redacted])"
}

/** Counts and order refer ONLY to loaded rows, not global inbox totals or a server snapshot. */
data class FeedbackInboxSelection(
    val items: List<FeedbackItem>,
    val counts: Map<FeedbackInboxFilter, Int>,
    val loadedCount: Int,
    val hasMore: Boolean,
    val invalidCount: Int,
) {
    override fun toString() =
        "FeedbackInboxSelection(loaded=$loadedCount, hasMore=$hasMore, [redacted])"
}

object FeedbackInboxSelector {
    const val MAX_QUERY_LENGTH = 200
    private val marks = Regex("\\p{M}+")
    private val separators = Regex("[^\\p{L}\\p{N}]+")

    fun validQuery(value: String): Boolean {
        if (value.length > MAX_QUERY_LENGTH) return false
        var index = 0
        while (index < value.length) {
            val c = value[index++]
            if (c.isHighSurrogate()) {
                if (index == value.length || !value[index++].isLowSurrogate()) return false
            } else if (c.isLowSurrogate()) return false
        }
        return true
    }

    // Mirrors iOS token-AND, case/diacritic/width-insensitive matching without changing stored
    // text.
    private fun normalized(value: String): String =
        Normalizer.normalize(value, Normalizer.Form.NFKD)
            .lowercase(Locale.ROOT)
            .replace(marks, "")
            .replace(separators, " ")
            .trim()

    fun select(
        page: FeedbackPage?,
        options: FeedbackInboxOptions,
        language: String,
    ): FeedbackInboxSelection {
        require(validQuery(options.query))
        val all = page?.items.orEmpty()
        val tokens = normalized(options.query).split(' ').filter(String::isNotEmpty).distinct()
        val matched = all.filter { item ->
            options.filter.includes(item.status) &&
                (tokens.isEmpty() ||
                    run {
                        val text =
                            normalized(
                                listOf(
                                        item.name,
                                        item.uid,
                                        item.type?.label(language).orEmpty(),
                                        item.message,
                                        item.preview,
                                        item.id,
                                    )
                                    .joinToString(" ")
                            )
                        tokens.all(text::contains)
                    })
        }
        val comparator =
            if (options.sort == FeedbackInboxSort.OLDEST)
                compareBy<FeedbackItem> { it.lastMessageAt ?: it.updatedAt }.thenBy { it.id }
            else
                compareByDescending<FeedbackItem> { it.lastMessageAt ?: it.updatedAt }
                    .thenBy { it.id }
        return FeedbackInboxSelection(
            matched.sortedWith(comparator),
            FeedbackInboxFilter.entries.associateWith { filter ->
                all.count { filter.includes(it.status) }
            },
            all.size,
            page?.hasMore == true,
            page?.invalid ?: 0,
        )
    }
}
