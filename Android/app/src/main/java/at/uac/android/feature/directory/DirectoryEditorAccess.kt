package at.uac.android.feature.directory

import android.content.Context
import at.uac.android.core.backend.AppBackend
import at.uac.android.feature.auth.AuthStore
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.tasks.await

/** The visible editor grant is only a UI hint. Both callables enforce the current role and MFA. */
interface DirectoryEditorAccess {
    val uid: String
    val owner: Boolean
    suspend fun publish(categoryId: String, payload: String, expectedRevision: Int): Int
    suspend fun delete(categoryId: String, expectedRevision: Int): Int
}

class FirebaseDirectoryEditorAccess(
    context: Context,
    private val auth: AuthStore,
    override val uid: String,
    private val sessionRevision: Long,
    override val owner: Boolean,
) : DirectoryEditorAccess {
    private val appContext = context.applicationContext

    override suspend fun publish(categoryId: String, payload: String, expectedRevision: Int): Int =
        auth.withReadySession(uid, sessionRevision) {
            require(DirectoryCatalog.validId(categoryId) && expectedRevision >= 0)
            require(DirectoryCatalog.parseCategory(org.json.JSONObject(payload)).id == categoryId)
            val result = AppBackend.callables(appContext).getHttpsCallable("saveDirectoryCategory")
                .withTimeout(30, TimeUnit.SECONDS)
                .call(mapOf("categoryId" to categoryId, "payload" to payload,
                    "expectedRevision" to expectedRevision)).await().data as? Map<*, *>
                ?: error("Invalid directory publication response")
            require(result["categoryId"] == categoryId)
            (result["revision"] as? Number)?.toInt()?.takeIf { it == expectedRevision + 1 }
                ?: error("Invalid directory publication revision")
        }

    override suspend fun delete(categoryId: String, expectedRevision: Int): Int =
        auth.withReadySession(uid, sessionRevision) {
            require(categoryId.startsWith("custom-") && expectedRevision > 0)
            val result = AppBackend.callables(appContext).getHttpsCallable("deleteDirectoryCategory")
                .withTimeout(30, TimeUnit.SECONDS)
                .call(mapOf("categoryId" to categoryId,
                    "expectedRevision" to expectedRevision)).await().data as? Map<*, *>
                ?: error("Invalid directory deletion response")
            require(result["categoryId"] == categoryId)
            (result["revision"] as? Number)?.toInt()?.takeIf { it == expectedRevision + 1 }
                ?: error("Invalid directory deletion revision")
        }
}
