package at.uac.android.feature.safety

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class SafetyViewModel(
    source: SafetySource,
    private val sessionAuthority: (() -> SafetySession?)? = null,
    mutationGate: SafetyMutationGate = DirectSafetyMutationGate,
) : ViewModel() {
    @Volatile private var session: SafetySession? = null

    private fun authority(): SafetySession? =
        if (sessionAuthority == null) session else sessionAuthority.invoke()

    private val repository = SafetyRepository(source, ::authority, mutationGate)
    private val mutable = MutableStateFlow(SafetyState())
    val state = mutable.asStateFlow()
    private val jobs = mutableMapOf<String, Job>()
    private var observer: Job? = null

    fun observeSessions(sessions: Flow<SafetySession?>) {
        observer?.cancel()
        observer =
            viewModelScope.launch(Dispatchers.Main.immediate, start = CoroutineStart.UNDISPATCHED) {
                sessions.collect(::bind)
            }
    }

    fun bind(value: SafetySession?) {
        if (value == session) return
        session = value
        jobs.values.toList().forEach(Job::cancel)
        jobs.clear()
        mutable.value = SafetyState(session = value)
        if (value?.ready == true) refresh()
    }

    private fun run(key: String, operation: suspend () -> Unit) {
        if (authority() != session) {
            bind(authority())
            return
        }
        if (jobs[key]?.isActive == true) return
        val captured = session
        jobs[key] = viewModelScope.launch {
            try {
                operation()
            } finally {
                if (session == captured) jobs.remove(key)
            }
        }
    }

    fun refresh() =
        run("blocks") {
            mutable.update { it.copy(loading = true, error = null, readDiagnostic = null) }
            try {
                val blocks = repository.blocks()
                mutable.update {
                    it.copy(blocks = blocks, loading = false, blockErrors = emptyMap())
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                val reason = safetyFailure(error)
                mutable.update {
                    it.copy(
                        loading = false,
                        error = reason,
                        readDiagnostic = safetyReadDiagnostic(error),
                        blocks = if (reason == SafetyFailure.OFFLINE) it.blocks else null,
                    )
                }
            }
        }

    fun setUser(id: String, blocked: Boolean) =
        setBlock("user:$id") {
            val actual = repository.setUser(id, blocked)
            mutable.update { state ->
                state.copy(
                    blocks =
                        state.blocks?.copy(
                            users =
                                state.blocks.users.filterNot { it.id == id } + listOfNotNull(actual)
                        )
                )
            }
        }

    fun setOrganization(id: String, blocked: Boolean) =
        setBlock("organization:$id") {
            val actual = repository.setOrganization(id, blocked)
            mutable.update { state ->
                state.copy(
                    blocks =
                        state.blocks?.copy(
                            organizations =
                                state.blocks.organizations.filterNot { it.id == id } +
                                    listOfNotNull(actual)
                        )
                )
            }
        }

    private fun setBlock(key: String, operation: suspend () -> Unit) =
        run("blocks") {
            if (mutable.value.blocks == null) return@run
            mutable.update {
                it.copy(pendingBlocks = it.pendingBlocks + key, blockErrors = it.blockErrors - key)
            }
            try {
                operation()
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                val reason = safetyFailure(error)
                mutable.update {
                    it.copy(
                        blockErrors = it.blockErrors + (key to reason),
                        blocks =
                            if (
                                reason in
                                    setOf(
                                        SafetyFailure.OFFLINE,
                                        SafetyFailure.UNKNOWN,
                                        SafetyFailure.UNCONFIRMED,
                                        SafetyFailure.INVALID,
                                    )
                            )
                                null
                            else it.blocks,
                    )
                }
            } finally {
                if (authority() == session)
                    mutable.update { it.copy(pendingBlocks = it.pendingBlocks - key) }
            }
        }

    fun submit(target: SafetyReportTarget, draft: SafetyReportDraft) =
        run("report:${target.key}") {
            val previous = mutable.value.reports[target.key]
            // A receipt or unknown outcome survives closing/reopening the sheet in this account
            // session.
            if (previous?.receipt != null || previous?.error == SafetyFailure.UNCONFIRMED)
                return@run
            mutable.update {
                it.copy(reports = it.reports + (target.key to SafetyReportState(pending = true)))
            }
            try {
                val receipt = repository.submit(target, draft)
                mutable.update {
                    it.copy(
                        reports = it.reports + (target.key to SafetyReportState(receipt = receipt))
                    )
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                mutable.update {
                    it.copy(
                        reports =
                            it.reports +
                                (target.key to SafetyReportState(error = safetyFailure(error)))
                    )
                }
            }
        }
}
