package at.uac.android.feature.accountdeletion

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import at.uac.android.core.AccountDeletionJournal
import at.uac.android.core.DeletionJournalStatus
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class AccountDeletionViewModel(
    source: AccountDeletionSource,
    journal: AccountDeletionJournal,
    private val sessionAuthority: () -> AccountDeletionSession?,
    gate: AccountDeletionGate,
    private val onConfirmed: (AccountDeletionSession, AccountDeletionReceipt) -> Unit,
    private val clock: () -> Instant = Instant::now,
) : ViewModel() {
    private val repository =
        AccountDeletionRepository(source, journal, sessionAuthority, gate, clock)
    private val mutable = MutableStateFlow(AccountDeletionState())
    val state = mutable.asStateFlow()
    private var session: AccountDeletionSession? = null
    private var generation = 0L
    private var job: Job? = null
    private var observer: Job? = null
    private var attempt: AccountDeletionAttempt? = null
    private var challenge: AccountDeletionChallenge? = null

    fun observeSessions(values: Flow<AccountDeletionSession?>) {
        observer?.cancel()
        observer =
            viewModelScope.launch(Dispatchers.Main.immediate, start = CoroutineStart.UNDISPATCHED) {
                values.collect(::bind)
            }
    }

    fun bind(value: AccountDeletionSession?) {
        if (session == value) return
        session = value
        generation++
        attempt?.cancelBeforeSubmission()
        attempt = null
        challenge = null
        job?.cancel()
        job = null
        mutable.value = AccountDeletionState(session = value)
    }

    private fun current(captured: AccountDeletionSession, version: Long) =
        session == captured && sessionAuthority() == captured && generation == version

    private fun available(): AccountDeletionSession? = session?.takeIf {
        it == sessionAuthority() && job?.isActive != true && state.value.receipt == null
    }

    /** Explicit destination entry, not a hidden read on every sign-in. */
    fun load() {
        val captured = available() ?: return
        if (state.value.phase == AccountDeletionPhase.MFA) return
        val version = generation
        mutable.update {
            it.copy(phase = AccountDeletionPhase.CHECKING, error = null, freshnessDiagnostic = null)
        }
        job = viewModelScope.launch {
            try {
                val (policy, pending) = repository.inspect()
                if (current(captured, version))
                    mutable.update {
                        it.copy(
                            phase = AccountDeletionPhase.IDLE,
                            policy = policy,
                            cancelRequested = false,
                            freshnessDiagnostic = null,
                            submittedAt = pending?.submittedAt,
                            retryAllowed = false,
                            status =
                                if (pending?.status == DeletionJournalStatus.PARTIAL)
                                    AccountDeletionIdentityStatus.PARTIAL
                                else null,
                            error =
                                if (pending != null) AccountDeletionFailure.UNCONFIRMED else null,
                        )
                    }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (current(captured, version))
                    mutable.update {
                        it.copy(
                            phase = AccountDeletionPhase.IDLE,
                            error = accountDeletionFailure(error),
                            freshnessDiagnostic = error.accountDeletionFreshnessDiagnostic(),
                            cancelRequested = false,
                        )
                    }
            }
        }
    }

    fun begin(password: String, confirmed: Boolean) {
        val captured = available() ?: return
        if (
            !confirmed ||
                state.value.policy == null ||
                state.value.unresolved && !state.value.retryAllowed
        )
            return
        val operation = AccountDeletionAttempt().also { attempt = it }
        challenge = null
        execute(captured) { onPhase, onSubmitted ->
            repository.begin(password, operation, onPhase, onSubmitted)
        }
    }

    fun verifySecondFactor(factorId: String, code: String) {
        val captured = available() ?: return
        val resolver = challenge ?: return
        val operation = attempt ?: return
        execute(captured) { onPhase, onSubmitted ->
            repository.completeChallenge(resolver, factorId, code, operation, onPhase, onSubmitted)
        }
    }

    private fun execute(
        captured: AccountDeletionSession,
        action: suspend ((AccountDeletionPhase) -> Unit, (Instant) -> Unit) -> AccountDeletionStep,
    ) {
        val version = generation
        mutable.update {
            it.copy(
                phase = AccountDeletionPhase.CHECKING,
                error = null,
                freshnessDiagnostic = null,
                cancelRequested = false,
                retryAllowed = false,
            )
        }
        job = viewModelScope.launch {
            try {
                val result =
                    action(
                        { phase ->
                            if (current(captured, version))
                                mutable.update { it.copy(phase = phase) }
                        },
                        { date ->
                            if (current(captured, version)) {
                                challenge = null
                                mutable.update {
                                    it.copy(
                                        submittedAt = date,
                                        status = null,
                                        factors = emptyList(),
                                        freshnessDiagnostic = null,
                                    )
                                }
                            }
                        },
                    )
                if (!current(captured, version)) return@launch
                when (result) {
                    is AccountDeletionStep.Challenge -> {
                        challenge = result.value
                        mutable.update {
                            it.copy(
                                phase = AccountDeletionPhase.MFA,
                                factors = result.value.factors,
                                cancelRequested = false,
                                freshnessDiagnostic = null,
                            )
                        }
                    }
                    is AccountDeletionStep.Completed -> completed(captured, result.receipt)
                }
            } catch (error: CancellationException) {
                if (current(captured, version)) {
                    challenge = null
                    mutable.update {
                        it.copy(
                            phase = AccountDeletionPhase.IDLE,
                            factors = emptyList(),
                            cancelRequested = false,
                            freshnessDiagnostic = null,
                            error =
                                if (it.submittedAt != null) AccountDeletionFailure.UNCONFIRMED
                                else null,
                        )
                    }
                }
                throw error
            } catch (error: Exception) {
                if (current(captured, version))
                    mutable.update {
                        it.copy(
                            phase =
                                if (challenge != null) AccountDeletionPhase.MFA
                                else AccountDeletionPhase.IDLE,
                            error = accountDeletionFailure(error),
                            freshnessDiagnostic = error.accountDeletionFreshnessDiagnostic(),
                            cancelRequested = false,
                        )
                    }
            }
        }
    }

    fun reconcile() {
        val captured = available() ?: return
        if (!state.value.unresolved) return
        val version = generation
        challenge = null
        mutable.update {
            it.copy(
                phase = AccountDeletionPhase.RECONCILING,
                error = null,
                freshnessDiagnostic = null,
                factors = emptyList(),
                retryAllowed = false,
            )
        }
        job = viewModelScope.launch {
            try {
                val (status, receipt) = repository.reconcile()
                if (!current(captured, version)) return@launch
                if (receipt != null) completed(captured, receipt)
                else
                    mutable.update {
                        it.copy(
                            phase = AccountDeletionPhase.IDLE,
                            status = status,
                            retryAllowed =
                                it.submittedAt
                                    ?.plusSeconds(AccountDeletionContract.REQUEST_TIMEOUT_SECONDS)
                                    ?.let { deadline -> !clock().isBefore(deadline) } == true,
                        )
                    }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (current(captured, version))
                    mutable.update {
                        it.copy(
                            phase = AccountDeletionPhase.IDLE,
                            error = accountDeletionFailure(error),
                            freshnessDiagnostic = error.accountDeletionFreshnessDiagnostic(),
                        )
                    }
            }
        }
    }

    private fun completed(captured: AccountDeletionSession, receipt: AccountDeletionReceipt) {
        challenge = null
        attempt = null
        mutable.update {
            it.copy(
                phase = AccountDeletionPhase.IDLE,
                receipt = receipt,
                error = null,
                freshnessDiagnostic = null,
                factors = emptyList(),
                retryAllowed = false,
            )
        }
        // Repository and the Auth mutex have both returned. This must never be called from inside
        // their gate.
        onConfirmed(captured, receipt)
    }

    fun cancelBeforeSubmission() {
        if (
            state.value.phase in
                setOf(AccountDeletionPhase.DELETING, AccountDeletionPhase.RECONCILING)
        )
            return
        attempt?.cancelBeforeSubmission()
        challenge = null
        if (state.value.busy) mutable.update { it.copy(cancelRequested = true) }
        else
            mutable.update {
                it.copy(
                    phase = AccountDeletionPhase.IDLE,
                    factors = emptyList(),
                    cancelRequested = false,
                )
            }
    }

    override fun onCleared() {
        attempt?.cancelBeforeSubmission()
        challenge = null
        super.onCleared()
    }
}
