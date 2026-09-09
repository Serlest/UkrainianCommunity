package at.uac.android.feature.systemlogs

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import at.uac.android.feature.moderation.ModerationSession
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class SystemLogsViewModel(private val repository: SystemLogRepository) : ViewModel() {
    private val mutable = MutableStateFlow(SystemLogsState())
    val state: StateFlow<SystemLogsState> = mutable.asStateFlow()

    fun load(session: ModerationSession?) {
        val access = runCatching { SystemLogContract.access(session) }.getOrElse { mutable.value = SystemLogsState(failure = SystemLogFailure.ACCESS); return }
        val captured = requireNotNull(session)
        mutable.update { it.copy(principal = captured.uid to captured.revision, access = access, loading = true, failure = null) }
        viewModelScope.launch {
            try {
                val logs = repository.list(captured, mutable.value.sort)
                val pending = repository.reconcilePending(captured)
                mutable.update { current -> if (current.principal == (captured.uid to captured.revision)) current.copy(loading = false, logs = logs, failure = null, unconfirmedAction = pending) else current }
            } catch (error: CancellationException) { throw error } catch (error: SystemLogException) { mutable.update { it.copy(loading = false, failure = error.failure) } }
        }
    }

    fun select(id: String?) = mutable.update { it.copy(selectedId = id) }
    fun search(value: String) = mutable.update { it.copy(search = value.take(500)) }
    fun category(value: String?) = mutable.update { it.copy(category = value) }
    fun severity(value: String?) = mutable.update { it.copy(severity = value) }
    fun reviewFilter(value: Boolean?) = mutable.update { it.copy(review = value) }
    fun toggle(filter: SystemLogQuickFilter) = mutable.update { it.copy(quick = if (filter in it.quick) it.quick - filter else it.quick + filter) }
    fun sort(value: SystemLogSort, session: ModerationSession?) { mutable.update { it.copy(sort = value) }; load(session) }

    fun visible(now: Instant = Instant.now()): List<SystemLogEntry> {
        val s = mutable.value
        val query = s.search.trim().lowercase()
        val filtered = s.logs.filter { log ->
            (s.category == null || log.category == s.category) &&
                (s.severity == null || log.severity == s.severity) &&
                (s.review == null || log.reviewed == s.review) &&
                (SystemLogQuickFilter.UNREVIEWED !in s.quick || !log.reviewed) &&
                (SystemLogQuickFilter.CRITICAL !in s.quick || log.severity == "critical") &&
                (SystemLogQuickFilter.TODAY !in s.quick || log.createdAt >= now.minusSeconds(86_400)) &&
                (SystemLogQuickFilter.SEVEN_DAYS !in s.quick || log.createdAt >= now.minusSeconds(604_800)) &&
                (query.isEmpty() || listOfNotNull(log.summary, log.technicalMessage, log.category, log.severity, log.eventType, log.actorDisplayName, log.targetTitle, log.moduleName, log.operationName).any { it.lowercase().contains(query) })
        }
        return when (s.sort) {
            SystemLogSort.NEWEST -> filtered.sortedByDescending { it.createdAt }
            SystemLogSort.OLDEST -> filtered.sortedBy { it.createdAt }
            SystemLogSort.SEVERITY_HIGH -> filtered.sortedWith(compareByDescending<SystemLogEntry> { it.severityRank }.thenByDescending { it.createdAt })
            SystemLogSort.SEVERITY_LOW -> filtered.sortedWith(compareBy<SystemLogEntry> { it.severityRank }.thenByDescending { it.createdAt })
            SystemLogSort.CATEGORY -> filtered.sortedWith(compareBy<SystemLogEntry> { it.category }.thenByDescending { it.createdAt })
        }
    }

    fun metrics() = SystemLogContract.metrics(mutable.value.logs)
    fun selected() = mutable.value.selectedId?.let { id -> mutable.value.logs.firstOrNull { it.id == id } }

    fun review(session: ModerationSession?, entry: SystemLogEntry) = mutate(session) { owner ->
        val confirmed = repository.review(owner, entry)
        mutable.update { it.copy(logs = it.logs.map { value -> if (value.id == confirmed.id) confirmed else value }) }
    }

    fun delete(session: ModerationSession?, entry: SystemLogEntry) = mutate(session) { owner ->
        repository.delete(owner, entry)
        mutable.update { it.copy(logs = it.logs.filterNot { value -> value.id == entry.id }, selectedId = null) }
    }

    fun clear(session: ModerationSession?) = mutate(session) { owner -> repository.clear(owner); mutable.update { it.copy(logs = emptyList(), selectedId = null) } }

    fun testPush(session: ModerationSession?) = mutate(session) { owner -> val receipt = repository.testPush(owner); mutable.update { it.copy(pushReceipt = receipt) } }

    fun acknowledgeUnconfirmed(session: ModerationSession?) {
        val captured = session ?: return failure(SystemLogFailure.ACCESS)
        repository.acknowledgeUnconfirmed(captured)
        mutable.update { it.copy(unconfirmedAction = null, failure = null) }
        load(session)
    }

    private fun mutate(session: ModerationSession?, action: suspend (ModerationSession) -> Unit) {
        val captured = session ?: return failure(SystemLogFailure.ACCESS)
        if (mutable.value.mutating) return failure(SystemLogFailure.BUSY)
        mutable.update { it.copy(mutating = true, failure = null, pushReceipt = null) }
        viewModelScope.launch {
            try {
                action(captured)
                mutable.update { it.copy(mutating = false, failure = null) }
            } catch (error: CancellationException) { throw error } catch (error: SystemLogException) {
                mutable.update { it.copy(mutating = false, failure = error.failure, unconfirmedAction = repository.pendingUnconfirmed(captured)) }
            }
        }
    }

    private fun failure(reason: SystemLogFailure) { mutable.update { it.copy(failure = reason) } }
}
