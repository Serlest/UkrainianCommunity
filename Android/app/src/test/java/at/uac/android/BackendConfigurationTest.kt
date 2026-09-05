package at.uac.android

import at.uac.android.core.LocalCallableFailure
import at.uac.android.core.LocalCallableProtocol
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.LocalImagePolicy
import at.uac.android.core.LocalStorage
import at.uac.android.core.backend.BackendInstanceBinding
import at.uac.android.core.backend.BackendKind
import at.uac.android.core.backend.BackendService
import at.uac.android.core.backend.BackendServiceAccess
import at.uac.android.core.backend.BackendUnavailableReason
import at.uac.android.core.backend.CompiledBackend
import org.junit.Assert.*
import org.junit.Test

class BackendConfigurationTest {
    private val configuration = CompiledBackend.configuration

    private fun identity(
        androidPackage: String = CompiledBackend.ANDROID_PACKAGE,
        appName: String = CompiledBackend.FIREBASE_APP_NAME,
        projectId: String? = CompiledBackend.PROJECT_ID,
        applicationId: String? = CompiledBackend.FIREBASE_APPLICATION_ID,
        syntheticKeyMatches: Boolean = true,
    ) =
        configuration.requireExpectedIdentity(
            androidPackage,
            appName,
            projectId,
            applicationId,
            syntheticKeyMatches,
        )

    private fun denied(action: () -> Unit): IllegalArgumentException =
        assertThrows(IllegalArgumentException::class.java, action)

    @Test
    fun compiledIdentityIsExactlyTheExistingLocalBuild() {
        assertSame(configuration, CompiledBackend.configuration)
        assertEquals(BackendKind.LOCAL_EMULATOR, configuration.identity.kind)
        assertEquals("at.uac.android.local", configuration.identity.androidPackage)
        assertEquals("uac-local", configuration.identity.firebaseAppName)
        assertEquals("demo-uac-android", configuration.identity.projectId)
        assertEquals(
            "1:1234567890:android:0000000000000000000000",
            configuration.identity.firebaseApplicationId,
        )
        assertEquals("demo-uac-android.appspot.com", configuration.bucket)
        assertEquals("europe-west3", configuration.callableRegion)
        identity()
    }

    @Test
    fun allFourConfiguredServicesRemainExactLocalEndpoints() {
        val expected =
            mapOf(
                BackendService.AUTH to 9098,
                BackendService.FIRESTORE to 8088,
                BackendService.STORAGE to 9198,
                BackendService.CALLABLES to 5008,
            )
        expected.forEach { (service, port) ->
            val endpoint = configuration.access(service) as BackendServiceAccess.LocalEndpoint
            assertEquals("10.0.2.2", endpoint.host)
            assertEquals(port, endpoint.port)
            configuration.requireEndpoint(service, endpoint.host, port)
        }
    }

    @Test
    fun pushHasNoEndpointOrSyntheticSuccessCapability() {
        val unavailable =
            configuration.access(BackendService.PUSH) as BackendServiceAccess.Unavailable
        assertEquals(BackendUnavailableReason.NOT_INCLUDED_IN_LOCAL_BUILD, unavailable.reason)
        denied { configuration.requireLocal(BackendService.PUSH) }
        denied { configuration.requireEndpoint(BackendService.PUSH, "10.0.2.2", 5008) }
    }

    @Test
    fun legacyConstantsRemainCompatible() {
        assertEquals(CompiledBackend.PROJECT_ID, LocalEnvironment.PROJECT_ID)
        assertEquals(CompiledBackend.HOST, LocalEnvironment.HOST)
        assertEquals(CompiledBackend.AUTH_PORT, LocalEnvironment.AUTH_PORT)
        assertEquals(CompiledBackend.FIRESTORE_PORT, LocalEnvironment.FIRESTORE_PORT)
        assertEquals(CompiledBackend.STORAGE_PORT, LocalEnvironment.STORAGE_PORT)
        assertEquals(CompiledBackend.STORAGE_BUCKET, LocalStorage.BUCKET)
        LocalEnvironment.requireSafe()
    }

    @Test
    fun productionTestCloudAndForeignDemoProjectsAreRejected() {
        for (project in
            listOf(
                "ukrainiancommunity-dbd5f",
                "uac-android-test-20260903",
                "demo-other",
                "",
                " demo-uac-android",
            )) {
            denied { identity(projectId = project) }
            denied { LocalEnvironment.requireSafe(projectId = project) }
        }
        denied { identity(projectId = null) }
    }

    @Test
    fun defaultAndOtherNamedFirebaseAppsAreRejected() {
        for (name in listOf("[DEFAULT]", "uac-test", "uac-local ", "", "UAC-LOCAL")) denied {
            identity(appName = name)
        }
    }

    @Test
    fun packageMustBeActualLocalApplicationNotTestApkOrProbe() {
        for (name in
            listOf(
                "at.uac.android.local.test",
                "at.serlest.ukrainiancommunity.staging",
                "at.uac.android",
                "",
            )) {
            denied { identity(androidPackage = name) }
            denied { configuration.requireAndroidPackage(name) }
        }
    }

    @Test
    fun firebaseApplicationIdIsCheckedIndependentlyFromProject() {
        for (app in
            listOf(
                "1:966536981122:android:2b617eb5d71f37b8dbe29b",
                "1:1234567890:android:other",
                "",
                " ${CompiledBackend.FIREBASE_APPLICATION_ID}",
            )) {
            denied { identity(applicationId = app) }
        }
        denied { identity(applicationId = null) }
    }

    @Test
    fun mismatchedSyntheticKeyPolicyFailsWithoutEchoingOptions() {
        assertEquals(
            "LOCAL_BACKEND_KEY_POLICY",
            denied { identity(syntheticKeyMatches = false) }.message,
        )
        val untrusted = "private-options-must-not-be-printed"
        val failure = denied { identity(projectId = untrusted) }
        assertEquals("LOCAL_BACKEND_PROJECT", failure.message)
        assertFalse(failure.toString().contains(untrusted))
        assertFalse(configuration.toString().contains(CompiledBackend.SYNTHETIC_API_KEY))
    }

    @Test
    fun localHostIsExactAndNeverNormalizedFromOtherInputs() {
        for (host in
            listOf(
                "localhost",
                "127.0.0.1",
                "10.0.2.2.evil.test",
                "10.0.2.2/",
                "http://10.0.2.2",
                "user@10.0.2.2",
                " 10.0.2.2",
                "",
            )) {
            denied { LocalEnvironment.requireSafe(host = host) }
            BackendService.entries
                .filter { it != BackendService.PUSH }
                .forEach { service ->
                    denied {
                        configuration.requireEndpoint(
                            service,
                            host,
                            configuration.requireLocal(service).port,
                        )
                    }
                }
        }
    }

    @Test
    fun portsCannotBeSubstitutedAcrossServices() {
        for (service in BackendService.entries.filter { it != BackendService.PUSH }) {
            val expected = configuration.requireLocal(service)
            for (port in
                listOf(-1, 0, 443, 5008, 8088, 9098, 9198, 65536).filter { it != expected.port }) {
                denied { configuration.requireEndpoint(service, expected.host, port) }
            }
        }
    }

    @Test
    fun bucketAndRegionRemainExact() {
        configuration.requireBucket(LocalStorage.BUCKET)
        configuration.requireCallableRegion("europe-west3")
        for (bucket in
            listOf(
                "ukrainiancommunity-dbd5f.appspot.com",
                "demo-other.appspot.com",
                "gs://${LocalStorage.BUCKET}",
                "${LocalStorage.BUCKET}/",
                "",
            )) {
            denied { configuration.requireBucket(bucket) }
        }
        for (region in listOf("us-central1", "europe-west3/", "", " europe-west3")) denied {
            configuration.requireCallableRegion(region)
        }
    }

    @Test
    fun instanceBindingAllowsRepeatedActualObject() {
        val binding = BackendInstanceBinding<Any>()
        val first = Any()
        binding.requireCurrentIfBound(null)
        binding.requireCurrentIfBound(first)
        binding.requireSameOrBind(first)
        binding.requireCurrentIfBound(first)
        binding.requireSameOrBind(first)
    }

    @Test
    fun equalValuedReplacementIsNotTheConfiguredInstance() {
        data class Handle(val appName: String)
        val first = Handle("uac-local")
        val replacement = Handle("uac-local")
        val binding = BackendInstanceBinding<Handle>()
        binding.requireSameOrBind(first)
        assertEquals(first, replacement)
        denied { binding.requireCurrentIfBound(replacement) }
        denied { binding.requireSameOrBind(replacement) }
        binding.requireSameOrBind(first)
    }

    @Test
    fun missingBoundAppFailsBeforeAnyReplacementInitialization() {
        val binding = BackendInstanceBinding<Any>()
        binding.requireSameOrBind(Any())
        var initializerReached = false
        denied {
            binding.requireCurrentIfBound(null)
            initializerReached = true
        }
        assertFalse(initializerReached)
    }

    @Test
    fun eachServiceKeepsItsOwnConfiguredInstanceBinding() {
        val auth = BackendInstanceBinding<Any>()
        val firestore = BackendInstanceBinding<Any>()
        val authHandle = Any()
        val firestoreHandle = Any()
        auth.requireSameOrBind(authHandle)
        firestore.requireSameOrBind(firestoreHandle)
        denied { auth.requireSameOrBind(firestoreHandle) }
        denied { firestore.requireSameOrBind(authHandle) }
        auth.requireSameOrBind(authHandle)
        firestore.requireSameOrBind(firestoreHandle)
    }

    @Test
    fun callableEndpointStillRejectsOtherPortRegionAndUnknownName() {
        assertEquals(
            "http://10.0.2.2:5008/demo-uac-android/europe-west3/saveComment",
            LocalCallableProtocol.endpoint("saveComment"),
        )
        denied { LocalCallableProtocol.endpoint("saveComment", port = 443) }
        denied { LocalCallableProtocol.endpoint("saveComment", region = "us-central1") }
        denied { LocalCallableProtocol.endpoint("updateAnalyticsConsent") }
        denied { LocalCallableProtocol.endpoint("trackAnalyticsEvent") }
    }

    @Test
    fun bothGalleryMutationsAndPhotoPolicySurviveTheSeam() {
        for (name in listOf("createOrganizationPhotoMetadata", "deleteOrganizationPhotoMetadata")) {
            assertTrue(LocalCallableProtocol.endpoint(name).endsWith("/$name"))
            assertTrue(LocalCallableProtocol.nonIdempotent(name))
            assertEquals(65_536, LocalCallableProtocol.maximumRequestBytes(name))
            assertEquals(60_000L, LocalCallableProtocol.maximumTimeoutMillis(name))
            assertEquals(
                LocalCallableFailure.UNCONFIRMED,
                LocalCallableProtocol.transportFailure(
                    name,
                    true,
                    LocalCallableFailure.UNAVAILABLE,
                ),
            )
        }
        assertEquals("GALLERY_PHOTO", LocalImagePolicy.GALLERY_PHOTO.name)
        assertEquals(
            4 * 1_024 * 1_024,
            LocalCallableProtocol.maximumRequestBytes("uploadOrganizationContentCover"),
        )
        assertEquals(
            120_000L,
            LocalCallableProtocol.maximumTimeoutMillis("uploadOrganizationContentCover"),
        )
        assertEquals(262_144, LocalCallableProtocol.MAX_RESPONSE_BYTES)
    }
}
