package at.uac.android.feature.directory

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import at.uac.android.BuildConfig
import at.uac.android.core.backend.AppBackend
import com.google.firebase.firestore.ListenerRegistration
import kotlinx.coroutines.tasks.await
import com.google.firebase.firestore.Source
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONObject

data class DirectorySnapshot(
    val published: Map<String, DirectoryCategory> = emptyMap(),
    val revisions: Map<String, Int> = emptyMap(),
    val deleted: Set<String> = emptySet(),
    val status: String = "bundled",
    val invalid: Int = 0,
)

/** One public listener for the Activity lifetime; tab changes retain its current snapshot. */
class DirectoryViewModel(application: Application) : AndroidViewModel(application) {
    val bundled = DirectoryCatalog.bundled(application)
    private val mutable = MutableStateFlow(DirectorySnapshot())
    val snapshot = mutable.asStateFlow()
    private var listener: ListenerRegistration? = null

    init {
        if (!BuildConfig.USE_LOCAL_BACKEND) observe()
    }

    fun retry() {
        listener?.remove()
        listener = null
        mutable.value = mutable.value.copy(status = "cached")
        if (!BuildConfig.USE_LOCAL_BACKEND) observe()
    }

    /** Explicit server refresh for a linked target, with no fallback to historical feed content. */
    suspend fun refreshTarget(categoryID: String) {
        require(DirectoryCatalog.validId(categoryID))
        if (BuildConfig.USE_LOCAL_BACKEND) return
        val doc = AppBackend.firestore(getApplication()).collection("directoryCategories")
            .document(categoryID).get(Source.SERVER).await()
        val previous = mutable.value
        if (!doc.exists()) return // Reviewed bundled categories have no cloud override until their first edit.
        if (doc.getBoolean("isDeleted") == true) {
            mutable.value = previous.copy(published = previous.published - categoryID,
                deleted = previous.deleted + categoryID)
            return
        }
        val category = DirectoryCatalog.parseCategory(JSONObject(doc.getString("payload") ?: error("Missing payload")))
        val revision = doc.getLong("revision")?.toInt()?.takeIf { it > 0 } ?: error("Invalid revision")
        require(category.id == categoryID)
        if (revision >= (previous.revisions[categoryID] ?: 0)) {
            mutable.value = previous.copy(published = previous.published + (categoryID to category),
                deleted = previous.deleted - categoryID, revisions = previous.revisions + (categoryID to revision))
        }
    }

    private fun observe() {
        listener = AppBackend.firestore(getApplication()).collection("directoryCategories")
            .addSnapshotListener { result, error ->
                if (error != null) {
                    mutable.value = mutable.value.copy(status = "failed")
                } else if (result != null) {
                    val published = mutableMapOf<String, DirectoryCategory>()
                    val revisions = mutableMapOf<String, Int>()
                    val deleted = mutableSetOf<String>()
                    var invalid = 0
                    result.documents.forEach { doc ->
                        if (doc.getBoolean("isDeleted") == true) {
                            deleted += doc.id
                        } else {
                            val category = runCatching {
                                DirectoryCatalog.parseCategory(JSONObject(doc.getString("payload")!!))
                            }.getOrNull()
                            val revision = doc.getLong("revision")?.toInt()
                            if (category?.id == doc.id && revision != null && revision > 0) {
                                published[doc.id] = category
                                revisions[doc.id] = revision
                            } else invalid++
                        }
                    }
                    mutable.value = DirectorySnapshot(
                        published, revisions, deleted,
                        if (result.metadata.isFromCache || result.metadata.hasPendingWrites()) "cached" else "current",
                        invalid,
                    )
                }
            }
    }

    override fun onCleared() {
        listener?.remove()
        super.onCleared()
    }
}
