package at.uac.android.feature.profilemedia

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import at.uac.android.core.DeniedExternalImagePickerAuthorization
import at.uac.android.core.ExternalImagePickerAuthorization
import at.uac.android.core.ExternalImagePickerLease
import at.uac.android.core.LocalImageException
import at.uac.android.core.LocalImageFailure
import at.uac.android.feature.personal.DirectPersonalMutationGate
import at.uac.android.feature.personal.PersonalMutationGate
import at.uac.android.feature.personal.PersonalSession
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class ProfileMediaViewModel(
    source: ProfileMediaSource,
    private val preparation: ProfilePhotoPreparation,
    private val sessionAuthority: (() -> PersonalSession?)? = null,
    gate: PersonalMutationGate = DirectPersonalMutationGate,
    private val pickerAuthorization: ExternalImagePickerAuthorization =
        DeniedExternalImagePickerAuthorization,
) : ViewModel() {
    private var session: PersonalSession? = null

    private fun authority(): PersonalSession? =
        sessionAuthority?.invoke() ?: if (sessionAuthority == null) session else null

    private val repository = ProfileMediaRepository(source, ::authority, gate)
    private val mutable = MutableStateFlow(ProfileMediaState())
    val state = mutable.asStateFlow()
    private var job: Job? = null
    private var observer: Job? = null
    private var operation: AvatarOperation? = null
    private var generation = 0L
    private var pendingPicker: Pair<PersonalSession, ExternalImagePickerLease>? = null

    fun observeSessions(values: Flow<PersonalSession?>) {
        observer?.cancel()
        observer =
            viewModelScope.launch(Dispatchers.Main.immediate, start = CoroutineStart.UNDISPATCHED) {
                values.collect(::bind)
            }
    }

    fun bind(value: PersonalSession?) {
        if (session == value) return
        session = value
        generation++
        pendingPicker?.second?.cancel()
        pendingPicker = null
        operation?.cancel()
        job?.cancel()
        job = null
        operation = null
        mutable.value = ProfileMediaState(session = value)
    }

    /**
     * Lives in this Activity ViewModel, so ordinary picker/Activity recreation does not lose its
     * scope.
     */
    fun beginPicker(): Boolean {
        val captured = session ?: return false
        if (captured != authority() || !captured.ready || state.value.busy) return false
        val lease =
            pickerAuthorization.begin(captured.uid, captured.revision)
                ?: run {
                    mutable.update { it.copy(error = ProfileMediaFailure.NOT_READY) }
                    return false
                }
        pendingPicker = captured to lease
        mutable.update { it.copy(pickerOpen = true, error = null) }
        return true
    }

    fun pickerResult(contentUri: String?) {
        val pending = pendingPicker ?: return
        pendingPicker = null
        pending.second.finish()
        if (pending.first != session || pending.first != authority()) return
        mutable.update { it.copy(pickerOpen = false) }
        select(contentUri, pending.first)
    }

    /**
     * A picker result belongs to the session that launched it, never to a newly signed-in account.
     */
    fun select(contentUri: String?, launchedFor: PersonalSession?) {
        if (
            launchedFor == null ||
                launchedFor != session ||
                launchedFor != authority() ||
                !launchedFor.ready ||
                state.value.busy
        )
            return
        if (contentUri == null) return
        val version = ++generation
        mutable.update {
            it.copy(
                selection = null,
                preparing = true,
                confirmed = null,
                confirmationDelivered = false,
                error = null,
                cancelRequested = false,
            )
        }
        job = viewModelScope.launch {
            try {
                val photo = preparation.prepare(contentUri)
                if (current(launchedFor, version))
                    mutable.update { it.copy(selection = photo, preparing = false) }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (current(launchedFor, version))
                    mutable.update { it.copy(preparing = false, error = failure(error)) }
            }
        }
    }

    fun save() {
        val captured = session ?: return
        val selected = state.value.selection ?: return
        if (
            !captured.ready ||
                captured != authority() ||
                state.value.busy ||
                state.value.confirmed != null
        )
            return
        val version = ++generation
        val transfer = AvatarOperation().also { operation = it }
        mutable.update {
            it.copy(
                phase = ProfileMediaPhase.UPLOADING,
                progress = 0f,
                confirmed = null,
                confirmationDelivered = false,
                error = null,
                cancelRequested = false,
            )
        }
        job = viewModelScope.launch {
            try {
                val profile =
                    repository.save(
                        selected,
                        transfer,
                        onPhase = { phase ->
                            if (current(captured, version))
                                mutable.update { it.copy(phase = phase) }
                        },
                        onProgress = { progress ->
                            if (current(captured, version))
                                mutable.update { it.copy(progress = progress.coerceIn(0f, 1f)) }
                        },
                    )
                if (current(captured, version))
                    mutable.update {
                        it.copy(
                            phase = ProfileMediaPhase.IDLE,
                            confirmed = profile,
                            progress = null,
                            cancelRequested = false,
                        )
                    }
            } catch (error: CancellationException) {
                if (current(captured, version))
                    mutable.update {
                        it.copy(
                            phase = ProfileMediaPhase.IDLE,
                            error = ProfileMediaFailure.CANCELLED,
                            progress = null,
                            cancelRequested = false,
                        )
                    }
                throw error
            } catch (error: Exception) {
                if (current(captured, version))
                    mutable.update {
                        it.copy(
                            phase = ProfileMediaPhase.IDLE,
                            error = failure(error),
                            progress = null,
                            cancelRequested = false,
                        )
                    }
            } finally {
                if (current(captured, version)) operation = null
            }
        }
    }

    fun cancel() {
        when (state.value.phase) {
            ProfileMediaPhase.COMMITTING ->
                return // An already submitted database transaction cannot be recalled.
            ProfileMediaPhase.UPLOADING -> {
                operation?.cancel()
                mutable.update { it.copy(cancelRequested = true) }
            }
            ProfileMediaPhase.IDLE -> {
                generation++
                pendingPicker?.second?.cancel()
                pendingPicker = null
                job?.cancel()
                mutable.update { ProfileMediaState(session = it.session) }
            }
        }
    }

    fun pickerUnavailable() {
        pendingPicker?.second?.cancel()
        pendingPicker = null
        if (state.value.phase == ProfileMediaPhase.IDLE && !state.value.preparing)
            mutable.update { it.copy(pickerOpen = false, error = ProfileMediaFailure.UNREADABLE) }
    }

    fun confirmationDelivered() {
        mutable.update { it.copy(confirmationDelivered = true) }
    }

    private fun current(value: PersonalSession, version: Long) =
        value == session && value == authority() && version == generation

    private fun failure(error: Exception): ProfileMediaFailure =
        when (error) {
            is ProfileMediaException -> error.reason
            is LocalImageException ->
                when (error.reason) {
                    LocalImageFailure.INVALID -> ProfileMediaFailure.INVALID
                    LocalImageFailure.TOO_LARGE -> ProfileMediaFailure.TOO_LARGE
                    LocalImageFailure.UNSUPPORTED -> ProfileMediaFailure.UNSUPPORTED
                    LocalImageFailure.UNREADABLE -> ProfileMediaFailure.UNREADABLE
                }
            else -> ProfileMediaFailure.UNCONFIRMED
        }

    override fun onCleared() {
        pendingPicker?.second?.cancel()
        operation?.cancel()
        super.onCleared()
    }
}
