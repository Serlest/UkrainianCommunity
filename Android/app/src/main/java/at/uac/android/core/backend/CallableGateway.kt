package at.uac.android.core.backend

import at.uac.android.core.LocalCallableResult
import com.google.android.gms.tasks.Task
import com.google.firebase.auth.FirebaseAuth
import java.util.concurrent.TimeUnit

/** Firebase transport seam, not user authorization or a confirmed server receipt. */
interface CallableGateway {
    /** Equal UID/app labels do not replace the actual SDK Auth object binding. */
    fun requireBoundTo(auth: FirebaseAuth)

    fun getHttpsCallable(name: String): CallableCall
}

interface CallableCall {
    /** Immutable reference; this is a transport, not coroutine, deadline. */
    fun withTimeout(timeout: Long, units: TimeUnit): CallableCall

    /**
     * Settles only when the underlying operation finishes. Never wrap in an early result, retry a
     * mutation or detach the Task from the caller's Auth gate. Historical result/error classes
     * remain unchanged across this seam.
     */
    fun call(data: Any? = null): Task<LocalCallableResult>
}
