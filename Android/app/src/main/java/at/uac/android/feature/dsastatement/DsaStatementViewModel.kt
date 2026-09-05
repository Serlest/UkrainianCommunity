package at.uac.android.feature.dsastatement

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class DsaStatementState(
    val session: DsaStatementSession? = null,
    val reportId: String? = null,
    val visible: Boolean = false,
    val loading: Boolean = false,
    val statement: DsaStatement? = null,
    val error: DsaStatementFailure? = null,
) {
    override fun toString() = "DsaStatementState([redacted])"
}

fun DsaStatementState.forSession(authority: DsaStatementSession?): DsaStatementState =
    if (session == authority && authority?.ready == true) this
    else DsaStatementState(session = authority)

class DsaStatementViewModel(
    source: DsaStatementSource,
    private val authority: () -> DsaStatementSession?,
    gate: DsaStatementReadGate,
) : ViewModel() {
    private val repository = DsaStatementRepository(source, gate, authority)
    private val mutable = MutableStateFlow(DsaStatementState(session = authority()))
    val state = mutable.asStateFlow()
    private var observer: Job? = null
    private var readJob: Job? = null
    private var epoch = 0L

    fun observeSessions(sessions: Flow<DsaStatementSession?>) {
        observer?.cancel()
        observer =
            viewModelScope.launch(Dispatchers.Main.immediate, start = CoroutineStart.UNDISPATCHED) {
                sessions.collect(::bind)
            }
    }

    fun bind(session: DsaStatementSession?) {
        if (mutable.value.session == session) return
        epoch++
        readJob?.cancel()
        readJob = null
        // No automatic reload into a new account, even if it has the same route restored.
        mutable.value = DsaStatementState(session = session)
    }

    fun show(reportId: String) {
        bind(authority())
        if (mutable.value.visible && mutable.value.reportId == reportId) return
        epoch++
        readJob?.cancel()
        readJob = null
        mutable.value =
            DsaStatementState(session = authority(), reportId = reportId, visible = true)
        refresh()
    }

    fun hide(reportId: String) {
        if (mutable.value.reportId != reportId) return
        epoch++
        readJob?.cancel()
        readJob = null
        mutable.value = DsaStatementState(session = authority())
    }

    fun refresh() {
        if (authority() != mutable.value.session) {
            bind(authority())
            return
        }
        val captured = mutable.value
        if (!captured.visible || readJob?.isActive == true) return
        val session = captured.session
        val reportId = captured.reportId
        if (session?.ready != true) {
            mutable.value =
                captured.copy(statement = null, loading = false, error = DsaStatementFailure.ACCESS)
            return
        }
        if (reportId == null || !DsaStatementContract.validId(reportId)) {
            mutable.value =
                captured.copy(
                    statement = null,
                    loading = false,
                    error = DsaStatementFailure.INVALID,
                )
            return
        }
        val generation = ++epoch
        fun current() =
            epoch == generation &&
                mutable.value.visible &&
                mutable.value.reportId == reportId &&
                mutable.value.session == session &&
                authority() == session
        mutable.value = captured.copy(statement = null, loading = true, error = null)
        readJob = viewModelScope.launch {
            try {
                val statement = repository.read(session, reportId, ::current)
                if (current())
                    mutable.value = mutable.value.copy(statement = statement, loading = false)
            } catch (error: CancellationException) {
                if (current()) mutable.value = mutable.value.copy(statement = null, loading = false)
                throw error
            } catch (error: DsaStatementException) {
                if (current())
                    mutable.value =
                        mutable.value.copy(statement = null, loading = false, error = error.failure)
            }
        }
    }
}
