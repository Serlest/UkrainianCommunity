package at.uac.android.core

import at.uac.android.core.backend.CompiledBackend

/** No user input, build property or intent extra can select a cloud endpoint. */
object LocalEnvironment {
    const val PROJECT_ID = CompiledBackend.PROJECT_ID
    const val HOST = CompiledBackend.HOST
    const val FIRESTORE_PORT = CompiledBackend.FIRESTORE_PORT
    const val AUTH_PORT = CompiledBackend.AUTH_PORT
    const val STORAGE_PORT = CompiledBackend.STORAGE_PORT

    fun requireSafe(projectId: String = PROJECT_ID, host: String = HOST) {
        CompiledBackend.configuration.requireLocalTarget(projectId, host)
    }
}
