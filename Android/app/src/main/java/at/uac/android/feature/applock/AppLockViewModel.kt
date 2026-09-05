package at.uac.android.feature.applock

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import at.uac.android.feature.auth.AuthPasswordProof
import at.uac.android.feature.auth.AuthSession
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** Main-thread local UI gate. It neither changes nor replaces the AuthStore generation. */
class AppLockViewModel(
    private val preferences: AppLockPreferences,
    val authentication: AppLockAuthenticating,
    workScope: CoroutineScope? = null,
) : ViewModel() {
    private val scope = workScope ?: viewModelScope
    private val mutable = MutableStateFlow(AppLockState())
    val state = mutable.asStateFlow()
    private var generation = 0L
    private var pending: AppLockAttempt? = null
    private var evaluation: Job? = null

    /** Native host installs/removes its window cover synchronously after a state mutation. */
    var protectionChanged: (() -> Unit)? = null

    fun observeAuth(sessions: Flow<AuthSession>): Job =
        scope.launch(Dispatchers.Main.immediate, start = CoroutineStart.UNDISPATCHED) {
            sessions.collect { bind(it.appLockSession(), it.localPasswordProof) }
        }

    fun bind(session: AppLockSession?, passwordProof: AuthPasswordProof? = null) {
        if (session != state.value.session) {
            val sameUid = session?.uid != null && session.uid == state.value.session?.uid
            cancelAuthentication()
            val old = state.value
            var error: AppLockProblem? = null
            val enabled =
                try {
                    session?.let { preferences.enabled(it.uid) } ?: false
                } catch (_: Exception) {
                    error = AppLockProblem.STORAGE
                    session != null
                }
            publish(
                old.copy(
                    session = session,
                    enabled = enabled,
                    unlocked = error == null && sameUid && old.unlocked && old.foreground,
                    error = error,
                )
            )
        }
        if (session != null && passwordProof?.consume(session.uid, session.revision) == true) {
            // A password result received in background is consumed, never deferred into an unlock.
            if (state.value.foreground) publish(state.value.copy(unlocked = true, error = null))
        }
    }

    fun enterForeground() {
        publish(state.value.copy(foreground = true, availability = availability()))
    }

    /** Only the exact adapter-owned legacy credential launch may retain its one pending request. */
    fun enterBackground(retaining: AppLockAttempt? = null) {
        if (retaining == null || retaining !== pending) cancelAuthentication()
        publish(state.value.copy(foreground = false, unlocked = false))
    }

    fun lock() {
        cancelAuthentication()
        publish(state.value.copy(unlocked = false))
    }

    fun cancelAuthentication() {
        generation++
        val attempt = pending
        pending = null
        if (attempt != null) authentication.cancel(attempt)
        evaluation?.cancel()
        evaluation = null
        publish(state.value.copy(authenticating = false, error = null))
    }

    fun unlock(language: String): Job? = if (!state.value.locked) null else evaluate(null, language)

    fun setEnabled(enabled: Boolean, language: String): Job? {
        if (state.value.enabled == enabled || state.value.session == null) return null
        return evaluate(enabled, language)
    }

    fun signOutFailed() {
        publish(state.value.copy(error = AppLockProblem.SIGN_OUT))
    }

    private fun evaluate(changePreference: Boolean?, language: String): Job? {
        val before = state.value
        val session = before.session ?: return null
        if (before.authenticating || !before.foreground) return null
        val available = availability()
        if (!available.available) {
            publish(before.copy(availability = available, error = AppLockProblem.UNAVAILABLE))
            return null
        }
        val attempt = AppLockAttempt(session, ++generation)
        pending = attempt
        publish(before.copy(authenticating = true, availability = available, error = null))
        return scope
            .launch {
                try {
                    val result = authentication.authenticate(attempt, language)
                    if (!current(attempt)) return@launch
                    if (result == AppLockResult.ACCEPTED && state.value.foreground) {
                        if (changePreference != null)
                            preferences.setEnabled(session.uid, changePreference)
                        publish(
                            state.value.copy(
                                enabled = changePreference ?: state.value.enabled,
                                unlocked = true,
                                error = null,
                            )
                        )
                    } else
                        publish(
                            state.value.copy(
                                error =
                                    when (result) {
                                        AppLockResult.ACCEPTED,
                                        AppLockResult.CANCELLED -> null
                                        AppLockResult.UNAVAILABLE -> AppLockProblem.UNAVAILABLE
                                        AppLockResult.LOCKED_OUT -> AppLockProblem.LOCKED_OUT
                                        else -> AppLockProblem.FAILED
                                    }
                            )
                        )
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Exception) {
                    if (current(attempt)) {
                        val reason = (error as? AppLockException)?.reason ?: AppLockProblem.FAILED
                        publish(
                            state.value.copy(
                                error = reason,
                                enabled =
                                    if (reason == AppLockProblem.STORAGE) true
                                    else state.value.enabled,
                                unlocked =
                                    if (reason == AppLockProblem.STORAGE) false
                                    else state.value.unlocked,
                            )
                        )
                    }
                } finally {
                    if (current(attempt)) {
                        pending = null
                        publish(
                            state.value.copy(authenticating = false, availability = availability())
                        )
                    }
                }
            }
            .also { evaluation = it }
    }

    private fun current(attempt: AppLockAttempt): Boolean =
        pending === attempt &&
            attempt.generation == generation &&
            state.value.session == attempt.session

    private fun availability(): AppLockAvailability =
        try {
            authentication.availability()
        } catch (_: Exception) {
            AppLockAvailability()
        }

    private fun publish(next: AppLockState) {
        mutable.value = next
        protectionChanged?.invoke()
    }

    override fun onCleared() {
        cancelAuthentication()
        protectionChanged = null
        super.onCleared()
    }
}
