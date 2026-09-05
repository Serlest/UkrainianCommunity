package at.uac.android.core

import android.content.Context
import at.uac.android.core.backend.BackendService
import at.uac.android.core.backend.CompiledBackend
import at.uac.android.core.backend.FirebaseBackendGuard
import com.google.firebase.storage.FirebaseStorage
import java.net.URI
import java.net.URLDecoder

/** Shared named demo SDK only. Each feature must validate its own UID/content path before use. */
object LocalStorage {
    const val BUCKET = CompiledBackend.STORAGE_BUCKET
    private var configured: FirebaseStorage? = null

    @Synchronized
    fun instance(context: Context): FirebaseStorage {
        LocalEnvironment.requireSafe()
        CompiledBackend.configuration.requireLocal(BackendService.STORAGE)
        LocalFirebase.auth(context)
        val app = LocalFirebase.app(context)
        configured?.let {
            FirebaseBackendGuard.requireStorage(it, app)
            return it
        }
        return FirebaseStorage.getInstance(app, "gs://$BUCKET")
            .apply {
                FirebaseBackendGuard.requireStorage(this, app)
                useEmulator(LocalEnvironment.HOST, LocalEnvironment.STORAGE_PORT)
                maxUploadRetryTimeMillis = 20_000
                maxDownloadRetryTimeMillis = 15_000
                maxOperationRetryTimeMillis = 15_000
            }
            .also { configured = it }
    }

    fun urlMatches(value: String, objectPath: String): Boolean = runCatching {
        if (
            objectPath.split('/').any { it.isBlank() || it in setOf(".", "..") } ||
                objectPath.any(Char::isISOControl)
        )
            return false
        val uri = URI(value)
        uri.scheme == "http" &&
            uri.host == LocalEnvironment.HOST &&
            uri.port == LocalEnvironment.STORAGE_PORT &&
            uri.userInfo == null &&
            uri.fragment == null &&
            URLDecoder.decode(uri.rawPath, "UTF-8") == "/v0/b/$BUCKET/o/$objectPath"
    }
        .getOrDefault(false)
}
