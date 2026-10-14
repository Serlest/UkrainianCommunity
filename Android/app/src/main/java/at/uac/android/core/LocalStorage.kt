package at.uac.android.core

import android.content.Context
import at.uac.android.BuildConfig
import at.uac.android.core.backend.BackendService
import at.uac.android.core.backend.CompiledBackend
import at.uac.android.core.backend.FirebaseBackendGuard
import com.google.firebase.storage.FirebaseStorage
import java.net.URI
import java.net.URLDecoder

/** Each feature validates its own UID/content path; this helper binds the URL to the compiled bucket. */
object LocalStorage {
    val BUCKET = CompiledBackend.STORAGE_BUCKET
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
        val pathMatches = URLDecoder.decode(uri.rawPath, "UTF-8") == "/v0/b/$BUCKET/o/$objectPath"
        val local = BuildConfig.USE_LOCAL_BACKEND && uri.scheme == "http" &&
            uri.host == LocalEnvironment.HOST && uri.port == LocalEnvironment.STORAGE_PORT
        val cloud = !BuildConfig.USE_LOCAL_BACKEND && uri.scheme == "https" &&
            uri.host == "firebasestorage.googleapis.com" && uri.port == -1 &&
            uri.rawQuery?.matches(Regex("alt=media&token=[A-Za-z0-9_-]{20,128}")) == true
        (local || cloud) && pathMatches && uri.userInfo == null && uri.fragment == null
    }
        .getOrDefault(false)
}
