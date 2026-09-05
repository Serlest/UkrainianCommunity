package at.uac.android.core

import androidx.lifecycle.ViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Retained foreground lease; old Activities cannot authorize work after recreation. */
class AppInteractionViewModel : ViewModel() {
    private var activeHost = 0L
    private var resumed = false
    private var frameReady = false
    private val mutable = MutableStateFlow(false)
    val interactive = mutable.asStateFlow()

    fun attach(): Long {
        activeHost++
        resumed = false
        frameReady = false
        mutable.value = false
        return activeHost
    }

    fun resume(host: Long) {
        if (host != activeHost) return
        resumed = true
        mutable.value = frameReady
    }

    fun rendered(host: Long, eligible: Boolean) {
        if (host != activeHost) return
        frameReady = eligible
        mutable.value = resumed && eligible
    }

    fun pause(host: Long) {
        if (host != activeHost) return
        resumed = false
        mutable.value = false
    }

    fun detach(host: Long) {
        if (host != activeHost) return
        activeHost++
        resumed = false
        frameReady = false
        mutable.value = false
    }
}
