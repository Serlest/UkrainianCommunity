package at.uac.android

import android.content.Context
import android.content.ContextWrapper
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalFirebase
import at.uac.android.core.LocalFunctions
import at.uac.android.core.LocalStorage
import at.uac.android.core.backend.BackendService
import at.uac.android.core.backend.BackendServiceAccess
import at.uac.android.core.backend.CompiledBackend
import at.uac.android.core.backend.FirebaseBackendGuard
import at.uac.android.feature.auth.FirestoreAuthProfiles
import at.uac.android.feature.browse.FirestoreContentSource
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.storage.FirebaseStorage
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** No Activity, account creation, auth transition, backend mutation or system-setting changes. */
@RunWith(AndroidJUnit4::class)
class BackendBindingDeviceTest {
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private fun requireLocalEmulator() {
        check(context.packageName == "at.uac.android.local")
        check(
            (Build.HARDWARE in setOf("ranchu", "goldfish") &&
                Build.MODEL.startsWith("sdk_gphone")) || isExplicitApi26CompatibilityAvd()
        ) {
            "Backend binding checks require the local SDK-phone or explicit compatibility AVD."
        }
    }

    @Test
    fun compiledPolicyLookupDoesNotInitializeFirebase() {
        requireLocalEmulator()
        val before = FirebaseApp.getApps(context).toList()
        val configuration = CompiledBackend.configuration
        assertEquals("demo-uac-android", configuration.identity.projectId)
        for (service in BackendService.entries) configuration.access(service)
        assertTrue(configuration.access(BackendService.PUSH) is BackendServiceAccess.Unavailable)
        val after = FirebaseApp.getApps(context)
        assertEquals(before.size, after.size)
        before.forEach { previous -> assertTrue(after.any { it === previous }) }
        assertTrue(after.none { it.name == FirebaseApp.DEFAULT_APP_NAME })
    }

    @Test
    fun realNamedHandlesAndCachedReturnsKeepExactlyOneBinding() {
        requireLocalEmulator()
        val app = LocalFirebase.app(context)
        val auth = LocalFirebase.auth(context)
        val db = LocalFirebase.firestore(context)
        val storage = LocalStorage.instance(context)
        val callables = LocalFunctions.instance(context)
        FirebaseBackendGuard.requireApp(context, app)
        FirebaseBackendGuard.requireFirestore(db)
        FirebaseBackendGuard.requireSameApp(auth, db)
        FirebaseBackendGuard.requireStorage(storage, app)
        // Constructors only: their guards must accept the actual local handle without a read.
        FirestoreContentSource(db)
        FirestoreAuthProfiles(db)
        assertSame(app, auth.app)
        assertSame(app, db.app)
        assertSame(app, storage.app)
        repeat(3) {
            assertSame(app, LocalFirebase.app(context))
            assertSame(auth, LocalFirebase.auth(context))
            assertSame(db, LocalFirebase.firestore(context))
            assertSame(storage, LocalStorage.instance(context))
            assertSame(callables, LocalFunctions.instance(context))
        }
        assertEquals("uac-local", app.name)
        assertEquals("demo-uac-android.appspot.com", storage.reference.bucket)
        assertTrue(FirebaseApp.getApps(context).none { it.name == FirebaseApp.DEFAULT_APP_NAME })
        // Construct references only: no transport, auth token lookup or mutation.
        callables.getHttpsCallable("createOrganizationPhotoMetadata")
        callables.getHttpsCallable("deleteOrganizationPhotoMetadata")
    }

    @Test
    fun foreignNameWithOtherwiseIdenticalSdkOptionsIsRejected() {
        withTemporaryApp { foreign ->
            assertTrue(foreign.options.projectId == CompiledBackend.PROJECT_ID)
            assertTrue(foreign.options.applicationId == CompiledBackend.FIREBASE_APPLICATION_ID)
            assertTrue(foreign.options.apiKey == CompiledBackend.SYNTHETIC_API_KEY)
            rejected("LOCAL_BACKEND_APP_NAME") {
                FirebaseBackendGuard.requireApp(context, foreign)
            }
        }
    }

    @Test
    fun foreignProjectSdkAppIsRejectedAtTheEarlierNameBoundary() {
        withTemporaryApp({ setProjectId("demo-uac-binding-rejected") }) { foreign ->
            assertTrue(foreign.options.projectId != CompiledBackend.PROJECT_ID)
            // Never replace the real local app to isolate this later predicate. The independent
            // project/key/application-id matrix belongs to BackendConfigurationTest.
            rejected("LOCAL_BACKEND_APP_NAME") {
                FirebaseBackendGuard.requireApp(context, foreign)
            }
        }
    }

    @Test
    fun foreignApplicationIdSdkAppIsRejectedAtTheEarlierNameBoundary() {
        withTemporaryApp({ setApplicationId("1:1234567890:android:1111111111111111111111") }) {
            foreign ->
            assertTrue(foreign.options.applicationId != CompiledBackend.FIREBASE_APPLICATION_ID)
            rejected("LOCAL_BACKEND_APP_NAME") {
                FirebaseBackendGuard.requireApp(context, foreign)
            }
        }
    }

    @Test
    fun foreignSyntheticKeySdkAppIsRejectedAtTheEarlierNameBoundary() {
        withTemporaryApp({ setApiKey("invalid-uac-binding-only-not-a-credential") }) { foreign ->
            assertTrue(foreign.options.apiKey != CompiledBackend.SYNTHETIC_API_KEY)
            rejected("LOCAL_BACKEND_APP_NAME") {
                FirebaseBackendGuard.requireApp(context, foreign)
            }
        }
    }

    @Test
    fun storageFromForeignSdkAppIsRejectedEvenWithTheExpectedBucket() {
        withTemporaryApp { foreign ->
            // Storage 22.0.1 retains its Auth Provider without resolving it. It may initialize
            // App Check bookkeeping, but no provider is installed and no token/read is requested.
            val storage = FirebaseStorage.getInstance(foreign, "gs://${LocalStorage.BUCKET}")
            assertTrue(storage.app === foreign)
            assertEquals(LocalStorage.BUCKET, storage.reference.bucket)
            rejected("LOCAL_BACKEND_APP_NAME") {
                FirebaseBackendGuard.requireStorage(storage, LocalFirebase.app(context))
            }
        }
    }

    @Test
    fun wrongBucketOnCorrectSdkAppIsRejectedWithoutReplacingTheLocalStorageHandle() {
        requireLocalEmulator()
        val app = LocalFirebase.app(context)
        val auth = LocalFirebase.auth(context)
        val originalUser = auth.currentUser
        val correct = LocalStorage.instance(context)
        val foreignBucket = "demo-uac-binding-rejected.appspot.com"
        val storage = FirebaseStorage.getInstance(app, "gs://$foreignBucket")
        // A second reference is cached by the SDK, not by LocalStorage. No transfer is started
        // and neither the existing app nor the existing configured bucket is deleted/rebound.
        assertTrue(storage.app === app)
        assertTrue(storage !== correct)
        assertEquals(foreignBucket, storage.reference.bucket)
        rejected("LOCAL_BACKEND_BUCKET") { FirebaseBackendGuard.requireStorage(storage, app) }
        assertTrue(LocalStorage.instance(context) === correct)
        assertTrue(LocalFirebase.auth(context) === auth)
        assertTrue(auth.currentUser === originalUser)
        assertTrue(LocalFirebase.app(context) === app)
    }

    @Test
    fun wrongCallingContextPackageRejectsTheCorrectRegisteredSdkApp() {
        requireLocalEmulator()
        val app = LocalFirebase.app(context)
        val foreignContext =
            object : ContextWrapper(context.applicationContext) {
                override fun getApplicationContext(): Context = this

                override fun getPackageName(): String = "at.uac.android.local.test"
            }
        rejected("LOCAL_BACKEND_PACKAGE") {
            FirebaseBackendGuard.requireApp(foreignContext, app)
        }
        assertTrue(LocalFirebase.app(context) === app)
        FirebaseBackendGuard.requireApp(context, app)
    }

    private fun rejected(expected: String, action: () -> Unit) {
        val failure = assertThrows(IllegalArgumentException::class.java, action)
        assertEquals(expected, failure.message)
    }

    private fun withTemporaryApp(
        configure: FirebaseOptions.Builder.() -> Unit = {},
        action: (FirebaseApp) -> Unit,
    ) {
        requireLocalEmulator()
        val local = LocalFirebase.app(context)
        val auth = LocalFirebase.auth(context)
        val db = LocalFirebase.firestore(context)
        val storage = LocalStorage.instance(context)
        val originalUser = auth.currentUser
        val before = FirebaseApp.getApps(context).toList()
        assertTrue(before.none { it.name == FirebaseApp.DEFAULT_APP_NAME })
        val name = "uac-binding-rejected-${UUID.randomUUID()}"
        val options = FirebaseOptions.Builder(local.options).apply(configure).build()
        var owned: FirebaseApp? = null
        var primary: Throwable? = null
        fun cleanup(check: () -> Unit) {
            try {
                check()
            } catch (failure: Throwable) {
                val previous = primary
                if (previous == null) primary = failure else previous.addSuppressed(failure)
            }
        }
        try {
            check(before.none { it.name == name })
            // Auth 24.2.0's registrar is lazy. Do not obtain Auth, Firestore, tokens or a
            // callable for this app: Firestore getInstance itself resolves the Auth Provider.
            val temporary = FirebaseApp.initializeApp(context, options, name)
            owned = temporary
            assertTrue(temporary !== local)
            action(temporary)
        } catch (failure: Throwable) {
            primary = failure
        } finally {
            cleanup {
                // initializeApp registers before initializing eager components; an exception in
                // that later step must not leave this exact owned UUID registered.
                val registered =
                    owned ?: FirebaseApp.getApps(context).singleOrNull { it.name == name }
                registered?.let { temporary ->
                    check(temporary !== local && temporary.name == name)
                    check(before.none { it === temporary })
                    check(temporary.options == options)
                    temporary.delete()
                }
            }
            cleanup {
                val after = FirebaseApp.getApps(context)
                assertEquals(before.size, after.size)
                before.forEach { previous -> assertTrue(after.any { it === previous }) }
                assertTrue(
                    after.none { it.name == name || it.name == FirebaseApp.DEFAULT_APP_NAME }
                )
            }
            cleanup {
                assertTrue(LocalFirebase.app(context) === local)
                assertTrue(LocalFirebase.auth(context) === auth)
                assertTrue(LocalFirebase.firestore(context) === db)
                assertTrue(LocalStorage.instance(context) === storage)
                assertTrue(auth.currentUser === originalUser)
            }
        }
        primary?.let { throw it }
    }
}
