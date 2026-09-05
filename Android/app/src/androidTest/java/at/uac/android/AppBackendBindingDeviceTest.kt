package at.uac.android

import android.content.ContentResolver
import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.content.res.AssetManager
import android.content.res.Resources
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalFirebase
import at.uac.android.core.LocalFunctions
import at.uac.android.core.LocalStorage
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.BackendService
import at.uac.android.core.backend.BackendServiceAccess
import at.uac.android.core.backend.CallableGateway
import at.uac.android.core.backend.CompiledBackend
import com.google.firebase.FirebaseApp
import java.io.File
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Real compiled local provider; no Activity, foreign SDK, auth transition or backend request. */
@RunWith(AndroidJUnit4::class)
class AppBackendBindingDeviceTest {
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private fun requireLocalEmulator() {
        check(context.packageName == "at.uac.android.local")
        check(
            (Build.HARDWARE in setOf("ranchu", "goldfish") &&
                Build.MODEL.startsWith("sdk_gphone")) || isExplicitApi26CompatibilityAvd()
        ) {
            "AppBackend checks require the local SDK-phone or explicit compatibility AVD."
        }
    }

    @Test
    fun configurationIsTheCompiledObjectWithoutInitializingAnApp() {
        requireLocalEmulator()
        val before = FirebaseApp.getApps(context).toList()
        repeat(3) { assertTrue(AppBackend.configuration === CompiledBackend.configuration) }
        assertRegistryUnchanged(before)
    }

    @Test
    fun everyServiceAccessRemainsTheSameCompiledCapabilityWithoutInitializingAnApp() {
        requireLocalEmulator()
        val before = FirebaseApp.getApps(context).toList()
        for (service in BackendService.entries) {
            assertTrue(
                AppBackend.configuration.access(service) ===
                    CompiledBackend.configuration.access(service)
            )
        }
        assertTrue(
            AppBackend.configuration.access(BackendService.PUSH) is BackendServiceAccess.Unavailable
        )
        assertRegistryUnchanged(before)
    }

    @Test
    fun repeatedFacadeAccessReturnsExactlyTheExistingLocalSdkHandlesAndGateway() {
        requireLocalEmulator()
        val app = LocalFirebase.app(context)
        val auth = LocalFirebase.auth(context)
        val db = LocalFirebase.firestore(context)
        val storage = LocalStorage.instance(context)
        val callables = LocalFunctions.instance(context)
        val user = auth.currentUser
        val before = FirebaseApp.getApps(context).toList()
        repeat(3) {
            assertTrue(AppBackend.app(context) === app)
            assertTrue(AppBackend.auth(context) === auth)
            assertTrue(AppBackend.firestore(context) === db)
            assertTrue(AppBackend.storage(context) === storage)
            val gateway: CallableGateway = AppBackend.callables(context)
            assertTrue(gateway === callables)
            gateway.requireBoundTo(auth)
            assertTrue(auth.app === app && db.app === app && storage.app === app)
            assertTrue(auth.currentUser === user)
        }
        assertRegistryUnchanged(before)
    }

    @Test
    fun appRejectsWrongCallingPackageBeforeBackendInitialization() {
        rejectsBeforeBackendInitialization { AppBackend.app(it) }
    }

    @Test
    fun authRejectsWrongCallingPackageBeforeBackendInitialization() {
        rejectsBeforeBackendInitialization { AppBackend.auth(it) }
    }

    @Test
    fun firestoreRejectsWrongCallingPackageBeforeBackendInitialization() {
        rejectsBeforeBackendInitialization { AppBackend.firestore(it) }
    }

    @Test
    fun storageRejectsWrongCallingPackageBeforeBackendInitialization() {
        rejectsBeforeBackendInitialization { AppBackend.storage(it) }
    }

    @Test
    fun callablesRejectWrongCallingPackageBeforeBackendInitialization() {
        rejectsBeforeBackendInitialization { AppBackend.callables(it) }
    }

    private fun rejectsBeforeBackendInitialization(accessor: (Context) -> Any) {
        requireLocalEmulator()
        // Do not warm a provider or erase an existing app to manufacture a cold-state claim.
        // The exact registry comparison also works when earlier SDK tests already ran.
        val before = FirebaseApp.getApps(context).toList()
        val rejectedContext = RejectedPackageContext(context.applicationContext)
        val result = runCatching { accessor(rejectedContext) }
        assertRegistryUnchanged(before)
        assertEquals(
            "No backend context access is allowed before rejection",
            0,
            rejectedContext.backendAccesses,
        )
        val failure = result.exceptionOrNull()
        assertTrue(
            "The compiled package guard must reject the accessor",
            failure is IllegalArgumentException,
        )
        assertEquals("LOCAL_BACKEND_PACKAGE", failure?.message)
    }

    private fun assertRegistryUnchanged(before: List<FirebaseApp>) {
        val after = FirebaseApp.getApps(context)
        assertEquals(before.size, after.size)
        before.forEach { original -> assertTrue(after.any { it === original }) }
        assertTrue(after.none { it.name == FirebaseApp.DEFAULT_APP_NAME })
    }

    /** Only the package preflight is allowed. SDK context access is an observable test failure. */
    private class RejectedPackageContext(base: Context) : ContextWrapper(base) {
        var backendAccesses = 0
            private set

        override fun getApplicationContext(): Context = this

        override fun getPackageName(): String = "at.uac.android.local.test"

        private fun forbidden(method: String): Nothing {
            backendAccesses++
            throw AssertionError("WRONG_PACKAGE_BACKEND_CONTEXT_ACCESS:$method")
        }

        override fun getPackageManager(): PackageManager = forbidden("packageManager")

        override fun getApplicationInfo(): ApplicationInfo = forbidden("applicationInfo")

        override fun getResources(): Resources = forbidden("resources")

        override fun getAssets(): AssetManager = forbidden("assets")

        override fun getContentResolver(): ContentResolver = forbidden("contentResolver")

        override fun getSystemService(name: String): Any? = forbidden("systemService")

        override fun getSharedPreferences(name: String, mode: Int): SharedPreferences =
            forbidden("sharedPreferences")

        override fun getFilesDir(): File = forbidden("filesDir")

        override fun getNoBackupFilesDir(): File = forbidden("noBackupFilesDir")

        override fun getCacheDir(): File = forbidden("cacheDir")

        override fun getCodeCacheDir(): File = forbidden("codeCacheDir")

        override fun getDir(name: String, mode: Int): File = forbidden("dir")

        override fun createDeviceProtectedStorageContext(): Context =
            forbidden("deviceProtectedStorageContext")
    }
}
