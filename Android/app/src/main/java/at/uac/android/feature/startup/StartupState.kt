package at.uac.android.feature.startup

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlin.math.min
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.takeWhile
import kotlinx.coroutines.launch

/** One launch only. Authentication refresh, login and logout never reopen it. */
data class StartupState(val covered: Boolean = true) {
    fun observe(restoring: Boolean): StartupState =
        if (covered && !restoring) copy(covered = false) else this
}

/**
 * The host passes the actual initial Auth RESTORING flag, not busy/readyForActions. Retain this
 * ViewModel across Activity recreation. No duration or media callback can extend the gate, dismiss
 * it early, or grant account authority.
 */
class StartupViewModel : ViewModel() {
    private val mutable = MutableStateFlow(StartupState())
    private var observation: Job? = null
    val state = mutable.asStateFlow()

    fun observe(restoring: Boolean) {
        mutable.value = state.value.observe(restoring)
    }

    /** Bind once in the host's retained factory; observe before the first composition. */
    fun observeSessions(restoring: Flow<Boolean>) {
        observation?.cancel()
        if (!state.value.covered) return
        observation =
            viewModelScope.launch(Dispatchers.Main.immediate, start = CoroutineStart.UNDISPATCHED) {
                restoring
                    .takeWhile { value ->
                        observe(value)
                        state.value.covered
                    }
                    .collect {}
            }
    }
}

internal data class StartupPlaybackChange(
    val release: Boolean = false,
    val startToken: Long? = null,
)

/** Main-thread player ownership; no Android dependency, credentials or persistence. */
internal class StartupPlaybackPolicy {
    private var sequence = 0L
    private var active: Long? = null
    private var allowed = false
    private var surface = false
    private var failed = false
    private var closed = false

    fun update(allowed: Boolean, surface: Boolean): StartupPlaybackChange {
        this.allowed = allowed
        this.surface = surface
        if (!allowed || !surface || failed || closed) {
            val release = active != null
            active = null
            return StartupPlaybackChange(release = release)
        }
        if (active != null) return StartupPlaybackChange()
        val token = ++sequence
        active = token
        return StartupPlaybackChange(startToken = token)
    }

    fun current(token: Long): Boolean = active == token && allowed && surface && !failed && !closed

    /** A bad codec/asset is decorative failure, never a retry loop or readiness signal. */
    fun fail(token: Long): Boolean {
        if (!current(token)) return false
        failed = true
        active = null
        return true
    }

    fun close() {
        closed = true
        active = null
    }
}

internal data class StartupFit(val scaleX: Float, val scaleY: Float)

/** TextureView initially stretches to its bounds; this returns a centered aspect-fit correction. */
internal fun startupAspectFit(
    viewWidth: Int,
    viewHeight: Int,
    videoWidth: Int,
    videoHeight: Int,
): StartupFit? {
    if (minOf(viewWidth, viewHeight, videoWidth, videoHeight) <= 0) return null
    val scale = min(viewWidth.toDouble() / videoWidth, viewHeight.toDouble() / videoHeight)
    return StartupFit(
        (videoWidth * scale / viewWidth).toFloat(),
        (videoHeight * scale / viewHeight).toFloat(),
    )
}
