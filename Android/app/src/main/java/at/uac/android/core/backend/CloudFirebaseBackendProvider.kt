package at.uac.android.core.backend

import android.content.Context
import android.util.Log
import at.uac.android.BuildConfig
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.appcheck.FirebaseAppCheck
import com.google.firebase.appcheck.debug.DebugAppCheckProviderFactory
import com.google.firebase.appcheck.playintegrity.PlayIntegrityAppCheckProviderFactory
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.functions.FirebaseFunctions
import com.google.firebase.storage.FirebaseStorage

/** Build-selected cloud SDK instances. No runtime endpoint selector or emulator fallback exists. */
internal object CloudFirebaseBackendProvider : FirebaseBackendProvider {
    private const val TAG = "CloudFirebaseBackend"
    override val configuration = CompiledBackend.configuration
    private var configuredAppCheck = false

    /**
     * The staging-only Firebase CI helper replaces the regular debug secret provider and
     * requires a registered instrumentation plus its transient runner argument. A manually
     * launched staging APK has neither, so installing that factory would crash the process.
     */
    private fun hasRegisteredTestInstrumentation(): Boolean =
        runCatching {
            Class.forName("androidx.test.platform.app.InstrumentationRegistry")
                .getMethod("getInstrumentation")
                .invoke(null)
        }.isSuccess

    override fun app(context: Context): FirebaseApp {
        require(!BuildConfig.USE_LOCAL_BACKEND) { "CLOUD_BACKEND_IN_LOCAL_BUILD" }
        require(BuildConfig.BACKEND_PROJECT_ID.isNotBlank()) { "CLOUD_PROJECT_MISSING" }
        require(BuildConfig.BACKEND_APPLICATION_ID.isNotBlank()) { "CLOUD_APPLICATION_ID_MISSING" }
        require(BuildConfig.BACKEND_API_KEY.isNotBlank()) { "CLOUD_API_KEY_MISSING" }
        require(BuildConfig.BACKEND_BUCKET.isNotBlank()) { "CLOUD_BUCKET_MISSING" }
        val appContext = context.applicationContext
        val existing = FirebaseApp.getApps(appContext).firstOrNull { it.name == BuildConfig.BACKEND_APP_NAME }
        val options =
            FirebaseOptions.Builder()
                .setProjectId(BuildConfig.BACKEND_PROJECT_ID)
                .setApplicationId(BuildConfig.BACKEND_APPLICATION_ID)
                .setApiKey(BuildConfig.BACKEND_API_KEY)
                .setStorageBucket(BuildConfig.BACKEND_BUCKET)
                .build()
        val app =
            existing
                ?: if (BuildConfig.BACKEND_APP_NAME == FirebaseApp.DEFAULT_APP_NAME) {
                    FirebaseApp.initializeApp(appContext, options)
                } else {
                    FirebaseApp.initializeApp(appContext, options, BuildConfig.BACKEND_APP_NAME)
                }
        if (!configuredAppCheck) {
            if (BuildConfig.USE_DEBUG_APP_CHECK && !hasRegisteredTestInstrumentation()) {
                // Standalone staging is useful for visual/manual QA. Cloud calls remain
                // fail-closed until the CI helper supplies its registered debug secret.
                Log.w(TAG, "Staging App Check test provider skipped outside instrumentation")
            } else {
                FirebaseAppCheck.getInstance(app).installAppCheckProviderFactory(
                    if (BuildConfig.USE_DEBUG_APP_CHECK) DebugAppCheckProviderFactory.getInstance()
                    else PlayIntegrityAppCheckProviderFactory.getInstance()
                )
            }
            configuredAppCheck = true
        }
        return app.also { FirebaseBackendGuard.requireApp(appContext, it) }
    }

    override fun auth(context: Context): FirebaseAuth =
        FirebaseAuth.getInstance(app(context)).also(FirebaseBackendGuard::requireAuth)

    override fun firestore(context: Context): FirebaseFirestore =
        FirebaseFirestore.getInstance(app(context)).also(FirebaseBackendGuard::requireFirestore)

    override fun storage(context: Context): FirebaseStorage =
        FirebaseStorage.getInstance(app(context), "gs://${BuildConfig.BACKEND_BUCKET}").also {
            FirebaseBackendGuard.requireStorage(it, app(context))
        }

    override fun callables(context: Context): CallableGateway {
        val auth = auth(context)
        val app = app(context)
        return CloudCallableGateway(
            FirebaseFunctions.getInstance(app, configuration.callableRegion),
            auth,
            app,
        )
    }
}
