package at.uac.android.core.backend

import at.uac.android.core.LocalCallableResult
import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalCallableFailure
import at.uac.android.core.LocalCallableProtocol
import com.google.android.gms.tasks.Task
import com.google.android.gms.tasks.TaskCompletionSource
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.functions.FirebaseFunctions
import com.google.firebase.functions.FirebaseFunctionsException
import java.util.concurrent.TimeUnit

/** Firebase Functions SDK adapter that preserves the app's settled-task callable contract. */
internal class CloudCallableGateway(
    private val functions: FirebaseFunctions,
    private val auth: FirebaseAuth,
    private val app: FirebaseApp,
) : CallableGateway {
    init {
        require(app === auth.app) { "CLOUD_CALLABLE_AUTH_BINDING" }
    }

    override fun requireBoundTo(auth: FirebaseAuth) {
        require(this.auth === auth && app === auth.app) { "CLOUD_CALLABLE_AUTH_BINDING" }
    }

    override fun getHttpsCallable(name: String): CallableCall {
        LocalCallableProtocol.requireAllowed(name)
        return CloudCallableCall(functions, name, 20L, TimeUnit.SECONDS)
    }
}

private class CloudCallableCall(
    private val functions: FirebaseFunctions,
    private val name: String,
    private val timeout: Long,
    private val units: TimeUnit,
) : CallableCall {
    override fun withTimeout(timeout: Long, units: TimeUnit): CallableCall {
        val millis = units.toMillis(timeout)
        require(millis in 100..LocalCallableProtocol.maximumTimeoutMillis(name)) {
            "CLOUD_CALLABLE_TIMEOUT"
        }
        return CloudCallableCall(functions, name, timeout, units)
    }

    override fun call(data: Any?): Task<LocalCallableResult> {
        val completion = TaskCompletionSource<LocalCallableResult>()
        try {
            LocalCallableProtocol.request(name, data)
        } catch (error: Exception) {
            completion.setException(error)
            return completion.task
        }
        functions.getHttpsCallable(name).withTimeout(timeout, units).call(data)
            .addOnSuccessListener { completion.trySetResult(LocalCallableResult(it.data)) }
            .addOnFailureListener { error ->
                val failure = cloudFailure(error)
                val details = (error as? FirebaseFunctionsException)?.details
                completion.trySetException(
                    LocalCallableException(
                        LocalCallableProtocol.transportFailure(name, true, failure),
                        details = details,
                        cause = error,
                    )
                )
            }
        return completion.task
    }

    private fun cloudFailure(error: Exception): LocalCallableFailure {
        val name = (error as? FirebaseFunctionsException)?.code?.name
        return LocalCallableFailure.entries.firstOrNull { it.name == name }
            ?: LocalCallableFailure.UNKNOWN
    }
}
