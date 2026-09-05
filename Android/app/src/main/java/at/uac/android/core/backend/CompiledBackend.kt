package at.uac.android.core.backend

/** One fixed APK definition. Reading it has no Android/Firebase, disk or network side effects. */
object CompiledBackend {
    const val ANDROID_PACKAGE = "at.uac.android.local"
    const val FIREBASE_APP_NAME = "uac-local"
    const val PROJECT_ID = "demo-uac-android"
    const val FIREBASE_APPLICATION_ID = "1:1234567890:android:0000000000000000000000"
    internal const val SYNTHETIC_API_KEY = "synthetic-local-key-not-a-credential"
    const val HOST = "10.0.2.2"
    const val AUTH_PORT = 9098
    const val FIRESTORE_PORT = 8088
    const val STORAGE_PORT = 9198
    const val CALLABLE_PORT = 5008
    const val STORAGE_BUCKET = "demo-uac-android.appspot.com"
    const val CALLABLE_REGION = "europe-west3"

    val configuration =
        BackendConfiguration(
            identity =
                BackendIdentity(
                    BackendKind.LOCAL_EMULATOR,
                    ANDROID_PACKAGE,
                    FIREBASE_APP_NAME,
                    PROJECT_ID,
                    FIREBASE_APPLICATION_ID,
                ),
            bucket = STORAGE_BUCKET,
            callableRegion = CALLABLE_REGION,
            services =
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
                ),
        )
}
