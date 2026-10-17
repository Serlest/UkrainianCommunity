package at.uac.android.feature.directory

import android.content.Context
import at.uac.android.core.backend.AppBackend
import com.google.firebase.firestore.DocumentSnapshot
import com.google.firebase.firestore.MetadataChanges
import com.google.firebase.firestore.QuerySnapshot
import com.google.firebase.firestore.Source
import kotlinx.coroutines.tasks.await
import org.json.JSONObject

fun interface DirectoryCatalogSubscription { fun close() }
data class DirectoryTargetRecord(val category: DirectoryCategory?, val revision: Int?, val deleted: Boolean)

interface DirectoryCatalogSource {
    fun categories(result: (DirectoryBatch) -> Unit, failure: () -> Unit): DirectoryCatalogSubscription
    fun marker(result: (DirectoryCatalogMarker?, Boolean) -> Unit, failure: () -> Unit): DirectoryCatalogSubscription
    suspend fun confirmedCatalog(): DirectoryBatch
    suspend fun target(id: String): DirectoryTargetRecord
}

class FirebaseDirectoryCatalogSource(context: Context) : DirectoryCatalogSource {
    private val appContext = context.applicationContext
    private val database get() = AppBackend.firestore(appContext)
    private val catalog get() = database.collection("directoryCategories")
    private val marker get() = database.collection("appConfig").document("directoryCatalog")

    override fun categories(result: (DirectoryBatch) -> Unit, failure: () -> Unit): DirectoryCatalogSubscription {
        val listener = catalog.addSnapshotListener(MetadataChanges.INCLUDE) { data, error ->
            if (error != null) failure() else if (data != null) result(decode(data))
        }
        return DirectoryCatalogSubscription(listener::remove)
    }
    override fun marker(result: (DirectoryCatalogMarker?, Boolean) -> Unit, failure: () -> Unit): DirectoryCatalogSubscription {
        val listener = marker.addSnapshotListener(MetadataChanges.INCLUDE) { doc, error ->
            if (error != null) failure() else if (doc != null)
                runCatching { marker(doc) }.onSuccess { result(it, doc.metadata.hasPendingWrites()) }.onFailure { failure() }
        }
        return DirectoryCatalogSubscription(listener::remove)
    }
    override suspend fun confirmedCatalog(): DirectoryBatch {
        val current = marker.get(Source.SERVER).await()
        check(!current.metadata.isFromCache && !current.metadata.hasPendingWrites() && marker(current) != null)
        val result = catalog.get(Source.SERVER).await()
        check(!result.metadata.isFromCache && !result.metadata.hasPendingWrites())
        return decode(result)
    }
    override suspend fun target(id: String): DirectoryTargetRecord {
        val doc = catalog.document(id).get(Source.SERVER).await()
        return if (!doc.exists()) DirectoryTargetRecord(null, null, false) else decode(doc)
    }
    private fun marker(doc: DocumentSnapshot): DirectoryCatalogMarker? {
        if (!doc.exists() || doc.getTimestamp("migratedAt") == null) return null
        return DirectoryCatalogMarker.decode(doc.data.orEmpty())
    }
    private fun decode(doc: DocumentSnapshot): DirectoryTargetRecord {
        require(DirectoryCatalog.validId(doc.id))
        val revision = doc.getLong("revision")?.takeIf { it in 1..Int.MAX_VALUE }?.toInt() ?: error("Invalid revision")
        if (doc.getBoolean("isDeleted") == true) return DirectoryTargetRecord(null, revision, true)
        val category = DirectoryCatalog.parseCategory(JSONObject(doc.getString("payload") ?: error("Missing payload")))
        require(category.id == doc.id)
        return DirectoryTargetRecord(category, revision, false)
    }
    private fun decode(result: QuerySnapshot): DirectoryBatch {
        val published = mutableMapOf<String, DirectoryCategory>()
        val revisions = mutableMapOf<String, Int>()
        val deleted = mutableSetOf<String>()
        var invalid = 0
        result.documents.forEach { doc ->
            runCatching { decode(doc) }.onSuccess { record ->
                record.revision?.let { revisions[doc.id] = it }
                if (record.deleted) deleted += doc.id else record.category?.let { published[doc.id] = it }
            }.onFailure { invalid++ }
        }
        return DirectoryBatch(DirectorySnapshot(published, revisions, deleted, invalid = invalid),
            result.metadata.isFromCache, result.metadata.hasPendingWrites())
    }
}
