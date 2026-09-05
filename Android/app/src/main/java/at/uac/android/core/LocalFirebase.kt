package at.uac.android.core

import android.content.Context
import at.uac.android.core.backend.BackendInstanceBinding
import at.uac.android.core.backend.BackendService
import at.uac.android.core.backend.CompiledBackend
import at.uac.android.core.backend.FirebaseBackendGuard
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreSettings
import com.google.firebase.firestore.MemoryCacheSettings

object LocalFirebase {
    private val appBinding = BackendInstanceBinding<FirebaseApp>()
    private val authBinding = BackendInstanceBinding<FirebaseAuth>()
    private val firestoreBinding = BackendInstanceBinding<FirebaseFirestore>()
    private var firestoreConfigured = false
    private var authConfigured = false

    @Synchronized
    fun app(context: Context): FirebaseApp {
        LocalEnvironment.requireSafe()
        val appContext = context.applicationContext
        CompiledBackend.configuration.requireAndroidPackage(appContext.packageName)
        val existing =
            FirebaseApp.getApps(appContext).firstOrNull {
                it.name == CompiledBackend.FIREBASE_APP_NAME
            }
        // A deleted/replaced app must not inherit the old config-once flags.
        appBinding.requireCurrentIfBound(existing)
        val app =
            existing
                ?: FirebaseApp.initializeApp(
                    appContext,
                    FirebaseOptions.Builder()
                        .setProjectId(LocalEnvironment.PROJECT_ID)
                        .setApplicationId(CompiledBackend.FIREBASE_APPLICATION_ID)
                        .setApiKey(CompiledBackend.SYNTHETIC_API_KEY)
                        .build(),
                    CompiledBackend.FIREBASE_APP_NAME,
                )
        FirebaseBackendGuard.requireApp(appContext, app)
        appBinding.requireSameOrBind(app)
        return app
    }

    @Synchronized
    fun auth(context: Context): FirebaseAuth {
        CompiledBackend.configuration.requireLocal(BackendService.AUTH)
        val auth = FirebaseAuth.getInstance(app(context))
        FirebaseBackendGuard.requireAuth(auth)
        authBinding.requireSameOrBind(auth)
        if (!authConfigured) {
            auth.useEmulator(LocalEnvironment.HOST, LocalEnvironment.AUTH_PORT)
            authConfigured = true
        }
        return auth
    }

    @Synchronized
    fun firestore(context: Context): FirebaseFirestore {
        CompiledBackend.configuration.requireLocal(BackendService.FIRESTORE)
        val app = app(context)
        // Auth must be configured before Firestore first requests an identity token.
        val auth = auth(context)
        val db = FirebaseFirestore.getInstance(app)
        FirebaseBackendGuard.requireSameApp(auth, db)
        firestoreBinding.requireSameOrBind(db)
        if (firestoreConfigured) return db
        return db.apply {
            firestoreSettings =
                FirebaseFirestoreSettings.Builder()
                    .setLocalCacheSettings(MemoryCacheSettings.newBuilder().build())
                    .build()
            useEmulator(LocalEnvironment.HOST, LocalEnvironment.FIRESTORE_PORT)
            firestoreConfigured = true
        }
    }
}
