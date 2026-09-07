package at.uac.android.core.backend

import at.uac.android.BuildConfig

/** One fixed APK definition. Reading it has no Android/Firebase, disk or network side effects. */
object CompiledBackend {
    val ANDROID_PACKAGE = BuildConfig.APPLICATION_ID
    val FIREBASE_APP_NAME = BuildConfig.BACKEND_APP_NAME
    val PROJECT_ID = BuildConfig.BACKEND_PROJECT_ID
    val FIREBASE_APPLICATION_ID = BuildConfig.BACKEND_APPLICATION_ID
    internal val SYNTHETIC_API_KEY = BuildConfig.BACKEND_API_KEY
    const val HOST = "10.0.2.2"
    const val AUTH_PORT = 9098
    const val FIRESTORE_PORT = 8088
    const val STORAGE_PORT = 9198
    const val CALLABLE_PORT = 5008
    val STORAGE_BUCKET = BuildConfig.BACKEND_BUCKET
    const val CALLABLE_REGION = "europe-west3"

    val configuration =
        BackendConfiguration(
            identity =
                BackendIdentity(
                    if (BuildConfig.USE_LOCAL_BACKEND) BackendKind.LOCAL_EMULATOR else BackendKind.FIREBASE_CLOUD,
                    ANDROID_PACKAGE,
                    FIREBASE_APP_NAME,
                    PROJECT_ID,
                    FIREBASE_APPLICATION_ID,
                ),
            bucket = STORAGE_BUCKET,
            callableRegion = CALLABLE_REGION,
            services = if (BuildConfig.USE_LOCAL_BACKEND) {
                mapOf(
                    BackendService.AUTH to BackendServiceAccess.LocalEndpoint(HOST, AUTH_PORT),
                    BackendService.FIRESTORE to
                        BackendServiceAccess.LocalEndpoint(HOST, FIRESTORE_PORT),
                    BackendService.STORAGE to
                        BackendServiceAccess.LocalEndpoint(HOST, STORAGE_PORT),
                    BackendService.CALLABLES to
                        BackendServiceAccess.LocalEndpoint(HOST, CALLABLE_PORT),
                    BackendService.PUSH to
                        BackendServiceAccess.Unavailable(
                            BackendUnavailableReason.NOT_INCLUDED_IN_LOCAL_BUILD
                        ),
                )
            } else {
                BackendService.entries.associateWith { BackendServiceAccess.Cloud }
            },
        )
}
