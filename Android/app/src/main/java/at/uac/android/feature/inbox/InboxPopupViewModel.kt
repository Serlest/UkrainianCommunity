package at.uac.android.feature.inbox

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class InboxPopupViewModel(
    private val source: InboxPopupSource,
    private val authority: () -> InboxPopupAccount,
    gate: InboxMutationGate,
    workScope: CoroutineScope? = null,
    private val clock: () -> Instant = Instant::now,
) : ViewModel() {
    private val scope = workScope ?: viewModelScope
    private val coordinator = InboxPopupCoordinator(clock)
    private val repository = InboxPopupRepository(source, authority, gate, clock)
    private val mutable = MutableStateFlow(InboxPopupState())
    val state = mutable.asStateFlow()
    private var watch: Job? = null
    private var expiry: Job? = null
    private var mutation: Job? = null
    private var actionSequence = 0L

    fun observeAccounts(accounts: Flow<InboxPopupAccount>): Job =
        scope.launch(Dispatchers.Main.immediate, start = CoroutineStart.UNDISPATCHED) {
            accounts.collect(::bind)
        }

    fun bind(account: InboxPopupAccount) {
        if (state.value.account == account) return
        watch?.cancel()
        expiry?.cancel()
        mutation?.cancel()
        coordinator.configure(account)
        mutable.value = InboxPopupState(account = account)
        refresh()
    }

    private fun current(account: InboxPopupAccount): Boolean =
        state.value.account == account && authority() == account

    /** Reconnects the head only. Never retries a dismissal or repeats a route. */
    fun refresh(): Job? {
        val account = state.value.account
        val session = account.session ?: return null
        if (!current(account) || session.uid != account.uid) return null
        watch?.cancel()
        expiry?.cancel()
        coordinator.suspendHead()
        publish(error = null)
        return scope
            .launch {
                try {
                    source.popupHeads(session.uid).collect { head ->
                        if (current(account) && coordinator.receive(session, head)) {
                            publish()
                            scheduleExpiry(account)
                        }
                    }
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Exception) {
                    if (current(account)) {
                        coordinator.suspendHead()
                        publish(error = (error as? InboxException)?.reason ?: InboxFailure.UNKNOWN)
                    }
                }
            }
            .also { watch = it }
    }

    fun dismiss(id: String, markRead: Boolean = false, open: Boolean = false): Job? {
        val account = state.value.account
        val session = account.session ?: return null
        if (!current(account) || state.value.mutating) return null
        coordinator.reconcile()
        val notice =
            coordinator.active?.takeIf { it.id == id }
                ?: run {
                    publish()
                    return null
                }
        if (open && notice.destination(clock()) == null) return null
        if (!coordinator.beginDismiss(id)) return null
        mutable.value =
            state.value.copy(
                mutating = true,
                error = null,
                acknowledgementFailed = false,
                action = null,
            )
        publish()
        return scope
            .launch {
                try {
                    val receipt = repository.acknowledge(session, notice, markRead || open)
                    if (current(account) && open && receipt.visible && receipt.archivedAt == null) {
                        receipt.destination(clock())?.let { destination ->
                            mutable.value =
                                state.value.copy(
                                    action =
                                        InboxPopupAction(
                                            ++actionSequence,
                                            session,
                                            receipt,
                                            destination,
                                        )
                                )
                        }
                    }
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Exception) {
                    if (current(account))
                        mutable.value =
                            state.value.copy(
                                error = (error as? InboxException)?.reason ?: InboxFailure.UNKNOWN,
                                acknowledgementFailed = true,
                            )
                } finally {
                    if (current(account)) {
                        coordinator.endDismiss()
                        mutable.value = state.value.copy(mutating = false)
                        publish()
                        scheduleExpiry(account)
                    }
                }
            }
            .also { mutation = it }
    }

    /** Root consumes once, then re-fetches/re-authorizes the destination before navigation. */
    fun takeAction(sequence: Long): InboxPopupAction? {
        val account = state.value.account
        val action = state.value.action ?: return null
        if (action.sequence != sequence) return null
        mutable.value = state.value.copy(action = null)
        if (
            !current(account) ||
                account.session != action.session ||
                action.notice.destination(clock()) != action.destination
        )
            return null
        return action
    }

    fun clearError() {
        mutable.value = state.value.copy(error = null, acknowledgementFailed = false)
    }

    private fun publish(error: InboxFailure? = state.value.error) {
        mutable.value =
            state.value.copy(
                active = coordinator.active,
                queuedCount = coordinator.queuedCount,
                confirmed = coordinator.confirmed,
                error = error,
            )
    }

    private fun scheduleExpiry(account: InboxPopupAccount) {
        expiry?.cancel()
        val next = coordinator.nextExpiry() ?: return
        val wait = Duration.between(clock(), next).toMillis().coerceAtLeast(1)
        expiry = scope.launch {
            delay(wait)
            if (current(account)) {
                coordinator.reconcile()
                publish()
                scheduleExpiry(account)
            }
        }
    }
}
