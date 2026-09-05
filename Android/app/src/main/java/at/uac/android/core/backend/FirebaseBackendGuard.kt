package at.uac.android.core.backend

import android.content.Context
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.storage.FirebaseStorage

/** Checks actual existing handles; never initializes an SDK or logs Firebase options. */
internal object FirebaseBackendGuard {
    private val configuration
        get() = CompiledBackend.configuration

    fun requireApp(context: Context, app: FirebaseApp) {
        configuration.requireAndroidPackage(context.applicationContext.packageName)
        configuration.requireExpectedIdentity(
            androidPackage = app.applicationContext.packageName,
            appName = app.name,
            projectId = app.options.projectId,
            applicationId = app.options.applicationId,
            syntheticKeyMatches = app.options.apiKey == CompiledBackend.SYNTHETIC_API_KEY,
        )
        require(
            FirebaseApp.getApps(app.applicationContext).singleOrNull {
                it.name == configuration.identity.firebaseAppName
            } === app
        ) {
            "LOCAL_BACKEND_APP_NOT_REGISTERED"
        }
    }

    fun requireAuth(auth: FirebaseAuth) {
        configuration.requireLocal(BackendService.AUTH)
        requireApp(auth.app.applicationContext, auth.app)
    }

    fun requireFirestore(db: FirebaseFirestore) {
        configuration.requireLocal(BackendService.FIRESTORE)
        requireApp(db.app.applicationContext, db.app)
    }

    fun requireSameApp(auth: FirebaseAuth, db: FirebaseFirestore) {
        requireAuth(auth)
        requireFirestore(db)
        require(auth.app === db.app) { "LOCAL_BACKEND_MIXED_APPS" }
    }

    fun requireStorage(storage: FirebaseStorage, expectedApp: FirebaseApp) {
        configuration.requireLocal(BackendService.STORAGE)
        requireApp(expectedApp.applicationContext, expectedApp)
        requireApp(storage.app.applicationContext, storage.app)
        require(storage.app === expectedApp) { "LOCAL_BACKEND_MIXED_APPS" }
        configuration.requireBucket(storage.reference.bucket)
    }
}
