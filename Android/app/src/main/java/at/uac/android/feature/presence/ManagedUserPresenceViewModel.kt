package at.uac.android.feature.presence

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import at.uac.android.feature.moderation.ModerationSession
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class ManagedUserPresenceState(
    val targetUserId: String? = null,
    val loading: Boolean = false,
    val value: ManagedUserPresence? = null,
    val failure: PresenceFailure? = null,
)

class ManagedUserPresenceViewModel(private val repository: ManagedUserPresenceRepository) :
    ViewModel() {
    private val mutable = MutableStateFlow(ManagedUserPresenceState())
    val state = mutable.asStateFlow()
    private var job: Job? = null
    private var generation = 0L

    fun show(session: ModerationSession?, targetUserId: String?) {
        if (session == null || !session.ready || !session.allowed || targetUserId == null) {
            clear()
            return
        }
        if (mutable.value.targetUserId == targetUserId && mutable.value.value != null) return
        load(session, targetUserId)
    }

    fun refresh(session: ModerationSession?, targetUserId: String?) {
        if (session == null || targetUserId == null) return
        load(session, targetUserId)
    }

    fun clear() {
        job?.cancel()
        generation++
        mutable.value = ManagedUserPresenceState()
    }

    private fun load(session: ModerationSession, targetUserId: String) {
        job?.cancel()
        val ticket = ++generation
        val retained = mutable.value.value?.takeIf { it.targetUserId == targetUserId }
        mutable.value = ManagedUserPresenceState(targetUserId, loading = true, value = retained)
        job = viewModelScope.launch {
            try {
                val value = repository.load(session, targetUserId)
                if (ticket == generation)
                    mutable.value = ManagedUserPresenceState(targetUserId, value = value)
            } catch (error: CancellationException) {
                throw error
            } catch (error: PresenceException) {
                if (ticket == generation)
                    mutable.value =
                        ManagedUserPresenceState(
                            targetUserId,
                            value = retained,
                            failure = error.failure,
                        )
            } catch (_: Exception) {
                if (ticket == generation)
                    mutable.value =
                        ManagedUserPresenceState(
                            targetUserId,
                            value = retained,
                            failure = PresenceFailure.UNKNOWN,
                        )
            }
        }
    }
}
