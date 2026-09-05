package at.uac.android.core.backend

/** This build has one backend. These values are not user/session authorization. */
enum class BackendKind {
    LOCAL_EMULATOR
}

enum class BackendService {
    AUTH,
    FIRESTORE,
    STORAGE,
    CALLABLES,
    PUSH,
}

enum class BackendUnavailableReason {
    NOT_INCLUDED_IN_LOCAL_BUILD
}

class BackendIdentity
internal constructor(
    val kind: BackendKind,
    val androidPackage: String,
    val firebaseAppName: String,
    val projectId: String,
    val firebaseApplicationId: String,
)

sealed interface BackendServiceAccess {
    class LocalEndpoint internal constructor(val host: String, val port: Int) : BackendServiceAccess

    class Unavailable internal constructor(val reason: BackendUnavailableReason) :
        BackendServiceAccess
}

/**
 * Compiled transport policy, not server health, deployment proof, consent or Auth READY. There is
 * no runtime parser, cloud implementation or fallback endpoint.
 */
class BackendConfiguration
internal constructor(
    val identity: BackendIdentity,
    val bucket: String,
    val callableRegion: String,
    services: Map<BackendService, BackendServiceAccess>,
) {
    private val services = services.toMap()

    init {
        require(this.services.keys == BackendService.entries.toSet()) { "LOCAL_BACKEND_SERVICES" }
    }

    fun access(service: BackendService): BackendServiceAccess = services.getValue(service)

    internal fun requireLocal(service: BackendService): BackendServiceAccess.LocalEndpoint =
        access(service) as? BackendServiceAccess.LocalEndpoint
            ?: throw IllegalArgumentException("LOCAL_BACKEND_SERVICE_UNAVAILABLE")

    internal fun requireAndroidPackage(actual: String) {
        require(actual == identity.androidPackage) { "LOCAL_BACKEND_PACKAGE" }
    }

    internal fun requireExpectedIdentity(
        androidPackage: String,
        appName: String,
        projectId: String?,
        applicationId: String?,
        syntheticKeyMatches: Boolean,
    ) {
        requireAndroidPackage(androidPackage)
        require(appName == identity.firebaseAppName) { "LOCAL_BACKEND_APP_NAME" }
        require(projectId == identity.projectId) { "LOCAL_BACKEND_PROJECT" }
        require(applicationId == identity.firebaseApplicationId) { "LOCAL_BACKEND_APPLICATION_ID" }
        require(syntheticKeyMatches) { "LOCAL_BACKEND_KEY_POLICY" }
    }

    internal fun requireLocalTarget(projectId: String, host: String) {
        require(projectId == identity.projectId) { "LOCAL_BACKEND_PROJECT" }
        require(host == requireLocal(BackendService.AUTH).host) { "LOCAL_BACKEND_HOST" }
    }

    internal fun requireEndpoint(service: BackendService, host: String, port: Int) {
        val expected = requireLocal(service)
        require(host == expected.host && port == expected.port) { "LOCAL_BACKEND_ENDPOINT" }
    }

    internal fun requireCallableRegion(actual: String) {
        require(actual == callableRegion) { "LOCAL_BACKEND_REGION" }
    }

    internal fun requireBucket(actual: String) {
        require(actual == bucket) { "LOCAL_BACKEND_BUCKET" }
    }
}

/** A configured flag may only be reused for the exact object it configured. */
internal class BackendInstanceBinding<T : Any> {
    private var bound: T? = null

    @Synchronized
    fun requireCurrentIfBound(actual: T?) {
        val previous = bound
        require(previous == null || previous === actual) { "LOCAL_BACKEND_INSTANCE_CHANGED" }
    }

    @Synchronized
    fun requireSameOrBind(actual: T) {
        requireCurrentIfBound(actual)
        if (bound == null) bound = actual
    }
}
