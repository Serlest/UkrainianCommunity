package at.uac.android.core

import android.content.Context

/** Demo-only protocol adapter; not the production Firebase Functions SDK. */
object LocalFunctions {
    private var client: LocalCallableClient? = null

    @Synchronized
    fun instance(context: Context): LocalCallableClient {
        LocalEnvironment.requireSafe()
        return client ?: LocalCallableClient(LocalFirebase.auth(context)).also { client = it }
    }
}
