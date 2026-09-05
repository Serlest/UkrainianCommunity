package at.uac.android.feature.foundation

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout

enum class DataMode {
    SYNTHETIC,
    EMULATOR,
}

sealed interface LoadState {
    data object Loading : LoadState

    data class Ready(val content: FoundationContent) : LoadState

    data object Unavailable : LoadState

    data object InvalidData : LoadState

    data object AccessDenied : LoadState
}

data class FoundationState(
    val language: String = "de",
    val mode: DataMode = DataMode.SYNTHETIC,
    val load: LoadState = LoadState.Loading,
)

class FoundationViewModel(
    private val synthetic: FoundationRepository,
    private val emulator: FoundationRepository,
    language: String,
    private val saveLanguage: (String) -> Unit,
) : ViewModel() {
    private val mutableState = MutableStateFlow(FoundationState(language = language))
    val state = mutableState.asStateFlow()
    private var loadJob: Job? = null

    init {
        reload()
    }

    fun selectLanguage(language: String) {
        require(language in setOf("de", "uk"))
        saveLanguage(language)
        mutableState.value = mutableState.value.copy(language = language)
    }

    fun selectMode(mode: DataMode) {
        mutableState.value = mutableState.value.copy(mode = mode)
        reload()
    }

    fun reload() {
        loadJob?.cancel()
        val mode = mutableState.value.mode
        mutableState.value = mutableState.value.copy(load = LoadState.Loading)
        loadJob = viewModelScope.launch {
            val result =
                try {
                    val content =
                        withTimeout(5_000) {
                            (if (mode == DataMode.SYNTHETIC) synthetic else emulator).load()
                        }
                    LoadState.Ready(content)
                } catch (_: TimeoutCancellationException) {
                    LoadState.Unavailable
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (_: InvalidFixtureException) {
                    LoadState.InvalidData
                } catch (_: FixtureAccessDeniedException) {
                    LoadState.AccessDenied
                } catch (_: Exception) {
                    LoadState.Unavailable
                }
            mutableState.value = mutableState.value.copy(load = result)
        }
    }
}
