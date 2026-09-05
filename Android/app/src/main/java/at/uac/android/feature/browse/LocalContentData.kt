package at.uac.android.feature.browse

import android.content.Context
import android.util.AtomicFile
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.FirebaseBackendGuard
import com.google.firebase.Timestamp
import com.google.firebase.firestore.FieldPath
import com.google.firebase.firestore.Filter
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.Query
import com.google.firebase.firestore.Source
import java.io.File
import java.security.MessageDigest
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

object ContentJson {
    fun decode(value: Any?): Any? =
        when (value) {
            JSONObject.NULL,
            null -> null
            is JSONObject ->
                if (value.has("\$date")) Instant.parse(value.getString("\$date"))
                else value.keys().asSequence().associateWith { decode(value.get(it)) }
            is JSONArray -> (0 until value.length()).map { decode(value.get(it)) }
            else -> value
        }

    fun encode(value: Any?): Any =
        when (value) {
            null -> JSONObject.NULL
            is Instant -> JSONObject().put("\$date", value.toString())
            is Map<*, *> ->
                JSONObject().also { json ->
                    value.forEach { (key, item) -> json.put(key.toString(), encode(item)) }
                }
            is List<*> -> JSONArray().also { json -> value.forEach { json.put(encode(it)) } }
            else -> value
        }

    @Suppress("UNCHECKED_CAST") fun fields(json: JSONObject) = decode(json) as Fields

    fun fixtures(context: Context): Map<String, RawDocument> {
        val json =
            JSONObject(
                context.assets.open("content-fixtures.json").bufferedReader().use { it.readText() }
            )
        return json.keys().asSequence().associateWith { path ->
            RawDocument(path.substringAfterLast('/'), fields(json.getJSONObject(path)))
        }
    }
}

/** Public local-demo snapshots only. Disabled OS backup; bounded and atomic, no credentials. */
class DiskContentCache(context: Context) : ContentCache {
    private val directory = File(context.applicationContext.filesDir, "demo-public-cache-v2")
    private val mutex = Mutex()

    private fun file(key: String) =
        File(
            directory,
            MessageDigest.getInstance("SHA-256").digest(key.toByteArray()).joinToString("") {
                "%02x".format(it)
            } + ".json",
        )

    override suspend fun get(key: String): CachedRows? =
        withContext(Dispatchers.IO) {
            mutex.withLock {
                runCatching {
                    val json =
                        JSONObject(
                            AtomicFile(file(key)).openRead().bufferedReader().use { it.readText() }
                        )
                    val rows = json.getJSONArray("rows")
                    CachedRows(
                        (0 until rows.length()).map {
                            val row = rows.getJSONObject(it)
                            RawDocument(
                                row.getString("id"),
                                ContentJson.fields(row.getJSONObject("fields")),
                            )
                        },
                        Instant.parse(json.getString("at")),
                    )
                }
                    .getOrNull()
            }
        }

    override suspend fun put(key: String, value: CachedRows) =
        withContext(Dispatchers.IO) {
            mutex.withLock {
                // Cache storage failure must not turn a successful server read into an error.
                runCatching {
                    directory.mkdirs()
                    val json =
                        JSONObject()
                            .put("at", value.at.toString())
                            .put(
                                "rows",
                                JSONArray().also { array ->
                                    value.rows.forEach {
                                        array.put(
                                            JSONObject()
                                                .put("id", it.id)
                                                .put("fields", ContentJson.encode(it.fields))
                                        )
                                    }
                                },
                            )
                    val atomic = AtomicFile(file(key))
                    val stream = atomic.startWrite()
                    try {
                        stream.write(json.toString().toByteArray())
                        atomic.finishWrite(stream)
                    } catch (e: Exception) {
                        atomic.failWrite(stream)
                        throw e
                    }
                    directory
                        .listFiles()
                        ?.filter { it.extension == "json" }
                        ?.sortedByDescending(File::lastModified)
                        ?.drop(200)
                        ?.forEach(File::delete)
                }
                Unit
            }
        }

    override suspend fun clear() =
        withContext(Dispatchers.IO) {
            mutex.withLock {
                directory.listFiles()?.forEach(File::delete)
                Unit
            }
        }
}

class FirestoreContentSource(private val db: FirebaseFirestore) : ContentSource {
    init {
        FirebaseBackendGuard.requireFirestore(db)
    }

    private fun convert(value: Any?): Any? =
        when (value) {
            is Timestamp -> Instant.ofEpochSecond(value.seconds, value.nanoseconds.toLong())
            is Map<*, *> -> value.entries.associate { it.key.toString() to convert(it.value) }
            is List<*> -> value.map(::convert)
            else -> value
        }

    @Suppress("UNCHECKED_CAST")
    private fun row(id: String, data: Map<String, Any>) = RawDocument(id, convert(data) as Fields)

    private suspend fun <T> request(block: suspend () -> T): T =
        try {
            block()
        } catch (e: CancellationException) {
            throw e
        } catch (e: FirebaseFirestoreException) {
            throw ReadException(
                when (e.code) {
                    FirebaseFirestoreException.Code.PERMISSION_DENIED,
                    FirebaseFirestoreException.Code.UNAUTHENTICATED -> ReadFailure.DENIED
                    FirebaseFirestoreException.Code.UNAVAILABLE,
                    FirebaseFirestoreException.Code.DEADLINE_EXCEEDED -> ReadFailure.OFFLINE
                    FirebaseFirestoreException.Code.NOT_FOUND -> ReadFailure.MISSING
                    FirebaseFirestoreException.Code.FAILED_PRECONDITION -> ReadFailure.INDEX
                    FirebaseFirestoreException.Code.INVALID_ARGUMENT -> ReadFailure.INVALID
                    else -> ReadFailure.UNKNOWN
                },
                e,
            )
        }

    override suspend fun page(
        query: ContentQuery,
        after: ContentCursor?,
        limit: Int,
    ): List<RawDocument> = request {
        var ref: Query =
            db.collection(query.kind.collection).whereEqualTo("moderationStatus", "approved")
        if (query.kind != ContentKind.ORGANIZATIONS)
            ref = ref.whereEqualTo("sourceType", "organization")
        if (query.region.isNotEmpty())
            ref =
                ref.where(
                    Filter.or(
                        Filter.equalTo("regionScope", "austria"),
                        Filter.equalTo("federalState", query.region),
                    )
                )
        if (query.organizationId.isNotEmpty())
            ref = ref.whereEqualTo("organizationId", query.organizationId)
        if (query.recommendations) ref = ref.whereEqualTo("category", query.category)
        if (query.kind == ContentKind.EVENTS && !query.recommendations) {
            val time = Timestamp(query.now.epochSecond, query.now.nano)
            ref =
                if (query.past) ref.whereLessThan("endDate", time)
                else ref.whereGreaterThanOrEqualTo("endDate", time)
        }
        val direction =
            if (query.ascending) Query.Direction.ASCENDING else Query.Direction.DESCENDING
        ref = ref.orderBy(query.orderField, direction).orderBy(FieldPath.documentId(), direction)
        if (after != null)
            ref = ref.startAfter(Timestamp(after.time.epochSecond, after.time.nano), after.id)
        ref.limit(limit.toLong()).get(Source.SERVER).await().documents.map { row(it.id, it.data!!) }
    }

    override suspend fun document(path: String): RawDocument = request {
        val doc = db.document(path).get(Source.SERVER).await()
        doc.data?.let { row(doc.id, it) } ?: throw ReadException(ReadFailure.MISSING)
    }

    override suspend fun auxiliary(path: String, section: String): List<RawDocument> = request {
        var ref: Query = db.collection(path)
        ref =
            if (path == "featuredBanners")
                ref.whereEqualTo("isActive", true)
                    .whereIn("actionType", bannerActions)
                    .whereArrayContains("visibleSections", section)
            else ref.orderBy("createdAt", Query.Direction.DESCENDING).limit(30)
        ref.get(Source.SERVER).await().documents.map { row(it.id, it.data!!) }
    }
}

fun localContentRepositories(context: Context): Pair<ContentRepository, ContentRepository> =
    ContentRepository(
        SyntheticContentSource(ContentJson.fixtures(context)),
        MemoryContentCache(),
    ) to
        ContentRepository(
            FirestoreContentSource(AppBackend.firestore(context)),
            DiskContentCache(context),
        )
