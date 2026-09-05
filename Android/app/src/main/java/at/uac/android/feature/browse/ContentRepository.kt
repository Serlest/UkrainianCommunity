package at.uac.android.feature.browse

import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.withTimeout

interface ContentSource {
    suspend fun page(query: ContentQuery, after: ContentCursor?, limit: Int): List<RawDocument>

    suspend fun document(path: String): RawDocument

    suspend fun auxiliary(path: String, section: String = ""): List<RawDocument>
}

data class CachedRows(val rows: List<RawDocument>, val at: Instant)

interface ContentCache {
    suspend fun get(key: String): CachedRows?

    suspend fun put(key: String, value: CachedRows)

    suspend fun clear()
}

class MemoryContentCache : ContentCache {
    private val entries = mutableMapOf<String, CachedRows>()

    override suspend fun get(key: String) = entries[key]

    override suspend fun put(key: String, value: CachedRows) {
        entries[key] = value
    }

    override suspend fun clear() {
        entries.clear()
    }
}

data class ReadResult<T>(val value: T, val cachedAt: Instant? = null)

data class ContentPage(
    val items: List<Content>,
    val next: ContentCursor?,
    val hasMore: Boolean,
    val invalidCount: Int,
)

class ContentRepository(
    private val source: ContentSource,
    private val cache: ContentCache,
    private val clock: () -> Instant = Instant::now,
) {
    private suspend fun read(
        key: String,
        load: suspend () -> List<RawDocument>,
    ): ReadResult<List<RawDocument>> {
        return try {
            val rows = withTimeout(5_000) { load() }
            cache.put(key, CachedRows(rows, clock()))
            ReadResult(rows)
        } catch (failure: Exception) {
            val reason =
                when (failure) {
                    is TimeoutCancellationException -> ReadFailure.OFFLINE
                    is CancellationException -> throw failure
                    is ReadException -> failure.reason
                    else -> ReadFailure.UNKNOWN
                }
            if (reason == ReadFailure.OFFLINE) {
                // Only explicit network failure may fall back. Permissions/deletion never do.
                cache
                    .get(key)
                    ?.takeIf { it.at.plusSeconds(86_400) >= clock() }
                    ?.let {
                        return ReadResult(it.rows, it.at)
                    }
            } else if (
                reason in setOf(ReadFailure.DENIED, ReadFailure.MISSING, ReadFailure.INVALID)
            )
                cache.clear()
            throw ReadException(reason, failure)
        }
    }

    suspend fun page(
        query: ContentQuery,
        after: ContentCursor? = null,
        size: Int = 6,
    ): ReadResult<ContentPage> {
        require(size in 1..50)
        var cursor = after
        var cachedAt: Instant? = null
        var invalid = 0
        val found = mutableListOf<Content>()
        // Search/category filters scan backend pages, including pages with zero matches.
        // Bound the work; expose continuation instead of claiming an incomplete scan is empty.
        repeat(20) {
            val key =
                "page:${query.kind}:${query.region}:${query.past}:${query.organizationId}:${query.recommendations}:${if (query.recommendations) query.category else ""}:$cursor:$size"
            val read = read(key) { source.page(query, cursor, size + 1) }
            cachedAt = listOfNotNull(cachedAt, read.cachedAt).minOrNull()
            val rows = read.value
            for ((index, row) in rows.withIndex()) {
                cursor = query.cursor(row)
                val item =
                    try {
                        decodeContent(query.kind, row)
                    } catch (e: ReadException) {
                        if (e.reason == ReadFailure.INVALID) {
                            invalid++
                            null
                        } else {
                            cache.clear()
                            throw e
                        }
                    }
                if (item != null && query.acceptsRaw(row) && item.matches(query)) found.add(item)
                if (found.size == size)
                    return ReadResult(
                        ContentPage(
                            found,
                            cursor,
                            index < rows.lastIndex || rows.size == size + 1,
                            invalid,
                        ),
                        cachedAt,
                    )
            }
            if (rows.size < size + 1)
                return ReadResult(ContentPage(found, cursor, false, invalid), cachedAt)
        }
        return ReadResult(ContentPage(found, cursor, true, invalid), cachedAt)
    }

    suspend fun detail(kind: ContentKind, id: String): ReadResult<Content> {
        require('/' !in id && id.isNotBlank())
        val read =
            read("doc:${kind.collection}/$id") { listOf(source.document("${kind.collection}/$id")) }
        val item =
            try {
                decodeContent(kind, read.value.single())
            } catch (e: ReadException) {
                cache.clear()
                throw e
            }
        return ReadResult(item, read.cachedAt)
    }

    suspend fun banners(section: String, region: String): ReadResult<List<Banner>> {
        val read = read("banners:$section") { source.auxiliary("featuredBanners", section) }
        if (read.value.isNotEmpty() && read.value.none { Banner(it.id, it.fields).valid() })
            throw ReadException(ReadFailure.INVALID)
        return ReadResult(visibleBanners(read.value, section, region, clock()), read.cachedAt)
    }

    suspend fun donation(): ReadResult<Donation> {
        val read = read("donation") { listOf(source.document("appConfig/donation")) }
        return ReadResult(Donation(read.value.single().fields), read.cachedAt)
    }

    suspend fun photos(organizationId: String): ReadResult<List<RawDocument>> {
        val result =
            read("photos:$organizationId") {
                source.auxiliary("organizations/$organizationId/photos")
            }
        if (
            result.value.any {
                it.fields.string("imageURL").isBlank() ||
                    it.fields.string("uploadedBy").isBlank() ||
                    it.fields.time("createdAt") == null
            }
        ) {
            cache.clear()
            throw ReadException(ReadFailure.INVALID)
        }
        return result
    }

    suspend fun profile(id: String) =
        read("profile:$id") { listOf(source.document("publicProfiles/$id")) }
}

class SyntheticContentSource(private val documents: Map<String, RawDocument>) : ContentSource {
    override suspend fun page(query: ContentQuery, after: ContentCursor?, limit: Int) =
        documents
            .filterKeys { it.substringBeforeLast('/') == query.kind.collection }
            .values
            .filter(query::acceptsRaw)
            .sortedWith { a, b -> query.compare(query.cursor(a), query.cursor(b)) }
            .filter { after == null || query.compare(query.cursor(it), after) > 0 }
            .take(limit)

    override suspend fun document(path: String): RawDocument {
        val document = documents[path] ?: throw ReadException(ReadFailure.MISSING)
        if (
            path.substringBefore('/') in ContentKind.entries.map { it.collection } &&
                path.count { it == '/' } == 1 &&
                document.fields.string("moderationStatus") != "approved"
        )
            throw ReadException(ReadFailure.DENIED)
        return document
    }

    override suspend fun auxiliary(path: String, section: String) =
        documents
            .filterKeys { it.substringBeforeLast('/') == path }
            .values
            .filter {
                path != "featuredBanners" ||
                    (it.fields["isActive"] == true &&
                        it.fields.string("actionType") in bannerActions &&
                        section in it.fields.strings("visibleSections"))
            }
            .sortedByDescending { it.fields.time("createdAt") }
            .take(if (path.endsWith("/photos")) 30 else 100)
}
