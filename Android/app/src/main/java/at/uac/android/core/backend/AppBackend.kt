package at.uac.android.core.backend

import android.content.Context
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.storage.FirebaseStorage

/**
 * One immutable backend for this process. No runtime selector, fallback, extra SDK cache or session
 * ownership lives here. Reading configuration does not initialize Firebase.
 */
internal object AppBackend {
    private val provider: FirebaseBackendProvider = LocalFirebaseBackendProvider

    val configuration: BackendConfiguration
        get() = provider.configuration

    private fun checkedContext(context: Context, service: BackendService? = null): Context {
        val appContext = context.applicationContext
        configuration.requireAndroidPackage(appContext.packageName)
        // This seam is still local-only. A future cloud provider requires its own reviewed policy;
        // adding a provider cannot silently bypass this service boundary.
        service?.let(configuration::requireLocal)
        return appContext
    }

    fun app(context: Context): FirebaseApp {
        val appContext = checkedContext(context)
        return provider.app(appContext).also { FirebaseBackendGuard.requireApp(appContext, it) }
    }

    fun auth(context: Context): FirebaseAuth {
        val appContext = checkedContext(context, BackendService.AUTH)
        return provider.auth(appContext).also(FirebaseBackendGuard::requireAuth)
    }

    fun firestore(context: Context): FirebaseFirestore {
        val appContext = checkedContext(context, BackendService.FIRESTORE)
        return provider.firestore(appContext).also {
            FirebaseBackendGuard.requireSameApp(provider.auth(appContext), it)
        }
    }

    fun storage(context: Context): FirebaseStorage {
        val appContext = checkedContext(context, BackendService.STORAGE)
        return provider.storage(appContext).also {
            FirebaseBackendGuard.requireStorage(it, provider.app(appContext))
        }
    }

    fun callables(context: Context): CallableGateway {
        val appContext = checkedContext(context, BackendService.CALLABLES)
        return provider.callables(appContext).also { it.requireBoundTo(provider.auth(appContext)) }
    }
}
