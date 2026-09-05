package at.uac.android.core

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.lifecycle.ViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Opaque presentation leases only: no document, account, password or notice payload is stored. */
class AuthRemediationPriority : ViewModel() {
    private var activeHost = 0L
    private var sequence = 0L
    private val leases = mutableSetOf<Long>()
    private val mutable = MutableStateFlow(false)
    val active = mutable.asStateFlow()

    fun attach(host: Long) {
        activeHost = host
        leases.clear()
        mutable.value = false
    }

    fun acquire(host: Long): AutoCloseable {
        if (host != activeHost) return AutoCloseable {}
        val token = ++sequence
        leases += token
        mutable.value = true
        return AutoCloseable {
            if (host == activeHost) {
                leases.remove(token)
                mutable.value = leases.isNotEmpty()
            }
        }
    }
}

data class AuthRemediationHost(val priority: AuthRemediationPriority, val host: Long)

val LocalAuthRemediationHost = staticCompositionLocalOf<AuthRemediationHost?> { null }

/** An already open legal/security surface wins over a newly arriving own-status notice. */
@Composable
fun PreserveAuthRemediationSurface() {
    val owner = LocalAuthRemediationHost.current ?: return
    DisposableEffect(owner) {
        val lease = owner.priority.acquire(owner.host)
        onDispose { lease.close() }
    }
}
