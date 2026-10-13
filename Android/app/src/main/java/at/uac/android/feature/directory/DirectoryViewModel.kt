package at.uac.android.feature.directory

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import at.uac.android.BuildConfig
import at.uac.android.core.backend.AppBackend
import com.google.firebase.firestore.ListenerRegistration
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
