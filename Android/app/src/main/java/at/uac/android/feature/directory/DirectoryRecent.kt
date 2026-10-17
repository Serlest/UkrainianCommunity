package at.uac.android.feature.directory

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import at.uac.android.core.backend.AppBackend
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await

data class DirectoryRecentCursor(val seconds: Long, val nanoseconds: Int, val id: String) {
    val time: Instant get() = Instant.ofEpochSecond(seconds, nanoseconds.toLong())
    fun wire() = mapOf("seconds" to seconds, "nanoseconds" to nanoseconds, "id" to id)
}

data class DirectoryRecentItem(val id: String, val kind: String, val categoryID: String,
    val topicID: String, val sectionID: String?, val federalState: String?, val publishedAt: Instant,
    val revision: Int, val title: DirectoryText, val topicTitle: DirectoryText, val categoryTitle: DirectoryText) {
    val destination get() = DirectoryRoute(categoryID, topicID, sectionID, federalState).path
    val cursor get() = DirectoryRecentCursor(publishedAt.epochSecond, publishedAt.nano, id)
}

data class DirectoryRecentPage(val items: List<DirectoryRecentItem>, val nextCursor: DirectoryRecentCursor?, val hasMore: Boolean)

object DirectoryRecentContract {
    const val callable = "getDirectoryRecentAdditions"
    const val limit = 20
    private fun recordId(value: Any?): String = (value as? String)?.takeIf {
        it.matches(Regex("[a-f0-9]{64}"))
    } ?: error("Invalid recent id")
    private fun number(value: Any?, max: Long): Long {
        val n = value as? Number ?: error("Missing integer")
        val long = n.toLong()
        require(long in 0..max && n.toDouble() == long.toDouble())
        return long
    }
    private fun text(value: Any?): DirectoryText {
        val map = value as? Map<*, *> ?: error("Missing translation")
        fun read(key: String) = (map[key] as? String)?.takeIf { it.isNotBlank() && it.length <= 2000 && !it.any { ch -> ch.isISOControl() && ch !in "\n\r\t" } }
            ?: error("Invalid translation")
        return DirectoryText(read("ukrainian"), read("german"))
    }
    fun cursor(value: Any?): DirectoryRecentCursor? {
        if (value == null) return null
        val map = value as? Map<*, *> ?: error("Invalid cursor")
        return DirectoryRecentCursor(number(map["seconds"], 253402300799),
            number(map["nanoseconds"], 999999999).toInt(), recordId(map["id"]))
    }
    fun older(candidate: DirectoryRecentCursor, previous: DirectoryRecentCursor): Boolean =
        candidate.time < previous.time || candidate.time == previous.time && candidate.id < previous.id

    fun decode(value: Any?, after: DirectoryRecentCursor?): DirectoryRecentPage {
        val map = value as? Map<*, *> ?: error("Invalid recent response")
        val raw = map["items"] as? List<*> ?: error("Missing items")
        require(raw.size <= limit)
        val items = raw.map { row ->
            val f = row as? Map<*, *> ?: error("Invalid item")
            fun slug(key: String) = (f[key] as? String)?.takeIf(DirectoryCatalog::validId) ?: error("Invalid $key")
            val kind = f["kind"] as? String
            require(kind in setOf("topic", "section"))
            val section = f["sectionID"]?.let { slug("sectionID") }
            val region = f["federalState"]?.let { it as? String ?: error("Invalid region") }
            require(region == null || region in DirectoryRoute.regions)
            require(if (kind == "topic") section == null && region == null else section != null)
            val published = Instant.parse(f["publishedAt"] as? String ?: error("Missing publication time"))
            require(published.epochSecond in 0..253402300799)
            val revision = number(f["revision"], Int.MAX_VALUE.toLong()).toInt().also { require(it > 0) }
            DirectoryRecentItem(recordId(f["id"]), kind!!, slug("categoryID"), slug("topicID"), section, region,
                published, revision, text(f["title"]), text(f["topicTitle"]), text(f["categoryTitle"]))
                .also { require(DirectoryRoute.parse(it.destination) != null) }
        }
        require(items.map { it.id }.distinct().size == items.size)
        // The callable serializes Date.toISOString() (milliseconds), while cursors preserve nanoseconds.
        // Keep the authoritative server order for equal displayed milliseconds; do not re-sort by id.
        items.zipWithNext().forEach { (a, b) -> require(b.publishedAt <= a.publishedAt) }
        if (after != null) require(items.all { it.publishedAt.toEpochMilli() <= after.time.toEpochMilli() })
        val more = map["hasMore"] as? Boolean ?: error("Missing hasMore")
        val next = cursor(map["nextCursor"])
        require(more == (next != null))
        if (next != null) {
            require(after == null || older(next, after))
            require(items.lastOrNull()?.publishedAt?.let { next.time.toEpochMilli() <= it.toEpochMilli() } != false)
        }
        return DirectoryRecentPage(items, next, more)
    }
}

fun interface DirectoryRecentSource { suspend fun page(cursor: DirectoryRecentCursor?): DirectoryRecentPage }

class FirebaseDirectoryRecentSource(context: Context) : DirectoryRecentSource {
    private val appContext = context.applicationContext
    override suspend fun page(cursor: DirectoryRecentCursor?): DirectoryRecentPage {
        val response = AppBackend.callables(appContext).getHttpsCallable(DirectoryRecentContract.callable)
            .withTimeout(30, TimeUnit.SECONDS).call(mapOf("limit" to DirectoryRecentContract.limit,
                "cursor" to cursor?.wire())).await().data
        return DirectoryRecentContract.decode(response, cursor)
    }
}

data class DirectoryRecentState(val items: List<DirectoryRecentItem> = emptyList(), val loading: Boolean = false,
    val loaded: Boolean = false, val failed: Boolean = false, val nextCursor: DirectoryRecentCursor? = null,
    val hasMore: Boolean = false)

class DirectoryRecentViewModel(private val source: DirectoryRecentSource) : ViewModel() {
    private val mutable = MutableStateFlow(DirectoryRecentState())
    val state = mutable.asStateFlow()
    private var generation = 0L
    private var failedMore = false
    fun ensureLoaded() { if (!state.value.loaded && !state.value.loading && !state.value.failed) load(false) }
    fun refresh() = load(false)
    fun more() { if (state.value.hasMore) load(true) }
    fun retry() = load(failedMore)
    private fun load(more: Boolean) {
        val before = state.value
        if (before.loading) return
        val after = if (more) before.nextCursor ?: return else null
        val request = ++generation
        mutable.value = before.copy(loading = true, failed = false)
        viewModelScope.launch {
            try {
                val page = source.page(after)
                if (request != generation) return@launch
                val rows = if (more) (before.items + page.items).distinctBy { it.id } else page.items
                mutable.value = DirectoryRecentState(rows, loaded = true, nextCursor = page.nextCursor, hasMore = page.hasMore)
            } catch (e: CancellationException) { throw e }
            catch (_: Exception) {
                if (request == generation) {
                    failedMore = more
                    mutable.value = before.copy(loading = false, failed = true)
                }
            }
        }
    }
    companion object {
        fun factory(context: Context) = object : ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST")
            override fun <T : ViewModel> create(modelClass: Class<T>): T =
                DirectoryRecentViewModel(FirebaseDirectoryRecentSource(context)) as T
        }
    }
}
