package at.uac.android.core

import androidx.lifecycle.ViewModel
import at.uac.android.feature.reminders.ReminderTapRequest
import at.uac.android.feature.reminders.reminderOpaque
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

data class ReminderNavigationState(
    val pending: ReminderTapRequest? = null,
    val unavailable: Boolean = false,
    val localTestOpened: Boolean = false,
)

/**
 * Opaque tap intent only. A destination is never trusted or persisted before fresh server
 * verification.
 */
class ReminderNavigationViewModel : ViewModel() {
    private val mutable = MutableStateFlow(ReminderNavigationState())
    val state = mutable.asStateFlow()
    private val handled = linkedSetOf<ReminderTapRequest>()

    fun offer(request: ReminderTapRequest) {
        if (
            !reminderOpaque(request.epoch) ||
                !reminderOpaque(request.token) ||
                request in handled ||
                mutable.value.pending == request
        )
            return
        mutable.value.pending?.let(::rememberHandled)
        mutable.value = ReminderNavigationState(pending = request)
    }

    fun complete(
        request: ReminderTapRequest,
        unavailable: Boolean = false,
        localTestOpened: Boolean = false,
    ): Boolean {
        if (mutable.value.pending != request) return false
        rememberHandled(request)
        mutable.value =
            ReminderNavigationState(unavailable = unavailable, localTestOpened = localTestOpened)
        return true
    }

    fun dismissNotice() {
        mutable.value = mutable.value.copy(unavailable = false, localTestOpened = false)
    }

    private fun rememberHandled(request: ReminderTapRequest) {
        handled += request
        while (handled.size > 16) handled.remove(handled.first())
    }
}
