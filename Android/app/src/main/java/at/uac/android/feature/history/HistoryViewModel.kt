package at.uac.android.feature.history

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import at.uac.android.feature.browse.Content
import at.uac.android.feature.community.CommunityRegistrationChange
import at.uac.android.feature.personal.PersonalAction
import at.uac.android.feature.personal.PersonalChangeReceipt
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class HistoryState(
    val session: HistorySession? = null,
    val section: HistorySection = HistorySection.RECENT,
    val visible: Boolean = false,
    val page: HistoryPage? = null,
    val loading: Boolean = false,
    val error: HistoryFailure? = null,
    val filter: HistoryFilter = HistoryFilter.ALL,
    val sort: HistorySort = HistorySort.NEWEST,
    val search: String = "",
    val confirmation: HistoryDelete? = null,
    val deleting: Boolean = false,
    val uncertainDelete: HistoryDelete? = null,
    val pendingWrites: Int = 0,
    val notice: HistoryFailure? = null,
    val reconciled: Boolean = false,
)

fun HistoryState.forSession(authority: HistorySession?, section: HistorySection): HistoryState =
    if (session == authority && this.section == section) this
    else HistoryState(session = authority, section = section)

class HistoryViewModel(
    source: HistorySource,
    private val sessionAuthority: () -> HistorySession?,
    private val visibility: (Content) -> Boolean,
    mutationGate: HistoryMutationGate,
    /**
     * Root supplies resumed + local-lock-unlocked. Default forbids all incidental history writes.
     */
    private val writeEligibility: () -> Boolean = { false },
) : ViewModel() {
    private val repository = HistoryRepository(source, sessionAuthority, visibility, mutationGate)
    private val mutable = MutableStateFlow(HistoryState(session = sessionAuthority()))
    val state = mutable.asStateFlow()
    private var observer: Job? = null
    private var readJob: Job? = null
    private var deleteJob: Job? = null
    private var reconcileJob: Job? = null
    private var epoch = 0L
    private val jobs = mutableSetOf<Job>()
    private val attemptedVisits = linkedSetOf<String>()
    private val pending = linkedMapOf<String, HistoryWrite>()

    fun observeSessions(sessions: Flow<HistorySession?>) {
        observer?.cancel()
        observer =
            viewModelScope.launch(Dispatchers.Main.immediate, start = CoroutineStart.UNDISPATCHED) {
                sessions.collect(::bind)
            }
    }

    fun bind(session: HistorySession?) {
        if (mutable.value.session == session) return
        epoch++
        readJob?.cancel()
        deleteJob?.cancel()
        reconcileJob?.cancel()
        jobs.toList().forEach(Job::cancel)
        jobs.clear()
        attemptedVisits.clear()
        pending.clear()
        val previous = mutable.value
        mutable.value = HistoryState(session, previous.section, previous.visible)
        if (previous.visible && session?.ready == true) refresh()
    }

    private fun synchronize(): Boolean {
        val fresh = sessionAuthority()
        if (fresh != mutable.value.session) {
            bind(fresh)
            return false
        }
        return fresh?.ready == true
    }

    fun show(section: HistorySection) {
        bind(sessionAuthority())
        if (mutable.value.visible && mutable.value.section == section) return
        epoch++
        readJob?.cancel()
        mutable.value =
            mutable.value.copy(
                section = section,
                visible = true,
                page = null,
                error = null,
                filter = HistoryFilter.ALL,
                sort = HistorySort.NEWEST,
                search = "",
                confirmation = null,
            )
        if (mutable.value.session?.ready == true) refresh()
    }

    fun hide() {
        epoch++
        readJob?.cancel()
        mutable.value =
            mutable.value.copy(
                visible = false,
                page = null,
                loading = false,
                confirmation = null,
                search = "",
            )
    }

    fun visibilityChanged() {
        epoch++
        readJob?.cancel()
        mutable.value = mutable.value.copy(page = null, loading = false, confirmation = null)
        if (mutable.value.visible && synchronize()) refresh()
    }

    private fun current(session: HistorySession?, generation: Long) =
        mutable.value.session == session && sessionAuthority() == session && epoch == generation

    fun refresh(more: Boolean = false) {
        if (!synchronize() || !mutable.value.visible || readJob?.isActive == true) return
        val captured = mutable.value
        val previous = if (more) captured.page else null
        if (more && previous?.next == null) return
        val generation = epoch
        mutable.value =
            captured.copy(page = null, loading = true, error = null, confirmation = null)
        readJob = viewModelScope.launch {
            try {
                val page = repository.page(captured.section, previous?.next)
                if (!current(captured.session, generation) || !mutable.value.visible) return@launch
                val entries = previous?.entries.orEmpty() + page.entries
                if (
                    entries.map { it.record.id }.distinct().size != entries.size ||
                        entries.size > captured.section.cap
                )
                    throw HistoryException(HistoryFailure.CONFLICT)
                mutable.value =
                    mutable.value.copy(
                        page =
                            page.copy(
                                entries =
                                    entries.map {
                                        it.copy(content = it.content?.takeIf(visibility))
                                    }
                            ),
                        loading = false,
                    )
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (current(captured.session, generation))
                    mutable.value =
                        mutable.value.copy(
                            page = null,
                            loading = false,
                            error = historyFailure(error),
                        )
            }
        }
    }

    fun filter(value: HistoryFilter) {
        if (synchronize()) mutable.value = mutable.value.copy(filter = value, confirmation = null)
    }

    fun sort(value: HistorySort) {
        if (synchronize()) mutable.value = mutable.value.copy(sort = value)
    }

    fun search(value: String) {
        if (synchronize())
            mutable.value = mutable.value.copy(search = value.take(160), confirmation = null)
    }

    fun requestDelete(ids: Set<String>) {
        if (
            !synchronize() ||
                !mutable.value.visible ||
                mutable.value.loading ||
                mutable.value.deleting ||
                mutable.value.uncertainDelete != null
        )
            return
        val page = mutable.value.page ?: return
        val records = page.entries.filter { it.record.id in ids }.map { it.record }
        if (records.size != ids.size || records.isEmpty()) return
        val intent = HistoryDelete(page.session, page.section, records)
        HistoryContract.delete(intent)
        mutable.value = mutable.value.copy(confirmation = intent, error = null)
    }

    fun cancelDelete() {
        if (!mutable.value.deleting) mutable.value = mutable.value.copy(confirmation = null)
    }

    fun confirmDelete() {
        if (!synchronize() || !mutable.value.visible || deleteJob?.isActive == true) return
        val intent = mutable.value.confirmation ?: return
        if (intent.session != sessionAuthority() || intent.section != mutable.value.section) return
        epoch++
        readJob?.cancel()
        mutable.value =
            mutable.value.copy(
                confirmation = null,
                deleting = true,
                uncertainDelete = intent,
                error = null,
                page = null,
                loading = false,
            )
        deleteJob = viewModelScope.launch {
            try {
                repository.delete(intent)
                if (intent.session == sessionAuthority()) {
                    mutable.value =
                        mutable.value.copy(deleting = false, uncertainDelete = null, page = null)
                    refresh()
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (intent.session == sessionAuthority()) {
                    val reason = historyFailure(error)
                    mutable.value =
                        mutable.value.copy(
                            deleting = false,
                            page = null,
                            error = reason,
                            uncertainDelete =
                                intent.takeIf {
                                    reason in
                                        setOf(HistoryFailure.UNCONFIRMED, HistoryFailure.UNKNOWN)
                                },
                        )
                }
            }
        }
    }

    /**
     * Only a fresh, visible detail may call this. The visit key belongs to a navigation entry,
     * never to a title.
     */
    fun recordView(
        content: Content,
        visitKey: String,
        language: String,
        currentTarget: () -> Boolean,
    ) {
        if (
            !synchronize() ||
                !writeEligibility() ||
                !currentTarget() ||
                !visibility(content) ||
                visitKey.isBlank() ||
                visitKey.length > 160
        )
            return
        if (
            content.kind == at.uac.android.feature.browse.ContentKind.EVENTS &&
                content.fields["cancellationState"] == "cancelled"
        )
            return
        val target =
            runCatching { HistoryTarget(HistoryType.of(content.kind), content.id) }.getOrNull()
                ?: return
        val key = "$visitKey:${target.path}"
        if (!attemptedVisits.add(key)) return
        while (attemptedVisits.size > 128) attemptedVisits.remove(attemptedVisits.first())
        submit(HistoryContract.write(sessionAuthority()!!, target, null, language), currentTarget)
    }

    fun personalChanged(receipt: PersonalChangeReceipt, language: String) {
        val captured = sessionAuthority() ?: return
        if (
            receipt.didChange != true ||
                receipt.session.uid != captured.uid ||
                receipt.session.revision != captured.revision ||
                !receipt.session.ready ||
                !synchronize() ||
                !writeEligibility()
        )
            return
        val type = HistoryType.of(receipt.target.kind)
        val action =
            when (receipt.action) {
                PersonalAction.LIKE -> return // Build 65 has no activity-log action for likes.
                PersonalAction.SUBSCRIBE ->
                    if (receipt.enabled) HistoryAction.FOLLOW else HistoryAction.UNFOLLOW
                PersonalAction.BOOKMARK ->
                    when (type) {
                        HistoryType.NEWS ->
                            if (receipt.enabled) HistoryAction.SAVE_NEWS
                            else HistoryAction.UNSAVE_NEWS
                        HistoryType.EVENT ->
                            if (receipt.enabled) HistoryAction.SAVE_EVENT
                            else HistoryAction.UNSAVE_EVENT
                        HistoryType.ORGANIZATION ->
                            if (receipt.enabled) HistoryAction.SAVE_ORGANIZATION
                            else HistoryAction.UNSAVE_ORGANIZATION
                    }
            }
        submit(
            HistoryContract.write(
                captured,
                HistoryTarget(type, receipt.target.id),
                action,
                language,
            )
        )
    }

    fun registrationChanged(receipt: CommunityRegistrationChange, language: String) {
        val captured = sessionAuthority() ?: return
        if (
            !receipt.didChange ||
                receipt.session.uid != captured.uid ||
                receipt.session.revision != captured.revision ||
                !receipt.session.ready ||
                !synchronize() ||
                !writeEligibility()
        )
            return
        val action =
            if (receipt.participation.registered) HistoryAction.REGISTER
            else HistoryAction.UNREGISTER
        submit(
            HistoryContract.write(
                captured,
                HistoryTarget(HistoryType.EVENT, receipt.target.id),
                action,
                language,
            )
        )
    }

    private fun submit(value: HistoryWrite, targetCurrent: () -> Boolean = { true }) {
        if (pending.containsKey(value.id)) return
        if (pending.size >= 32) {
            mutable.value = mutable.value.copy(notice = HistoryFailure.UNCONFIRMED)
            return
        }
        pending[value.id] = value
        mutable.value = mutable.value.copy(pendingWrites = pending.size, reconciled = false)
        val job = viewModelScope.launch {
            try {
                repository.write(value) { writeEligibility() && targetCurrent() }
                currentCoroutineContext().ensureActive()
                if (sessionAuthority() == value.session) {
                    pending.remove(value.id)
                    mutable.value = mutable.value.copy(pendingWrites = pending.size, notice = null)
                }
            } catch (error: CancellationException) {
                // A submitted SDK task may already have committed. Keep only this account's
                // in-memory reconciliation entry.
                if (sessionAuthority() == value.session)
                    mutable.value = mutable.value.copy(notice = HistoryFailure.UNCONFIRMED)
                throw error
            } catch (error: Exception) {
                if (sessionAuthority() == value.session) {
                    val reason = historyFailure(error)
                    if (reason !in setOf(HistoryFailure.UNCONFIRMED, HistoryFailure.UNKNOWN))
                        pending.remove(value.id)
                    mutable.value =
                        mutable.value.copy(pendingWrites = pending.size, notice = reason)
                }
            }
        }
        jobs.add(job)
        job.invokeOnCompletion { jobs.remove(job) }
    }

    /**
     * Never resubmits a write. For recent views PRESENT only means the current server record is
     * observable.
     */
    fun reconcile() {
        if (
            !synchronize() ||
                reconcileJob?.isActive == true ||
                mutable.value.deleting ||
                jobs.any { it.isActive }
        )
            return
        val captured = sessionAuthority()!!
        val writes = pending.values.toList()
        val deletion = mutable.value.uncertainDelete
        reconcileJob = viewModelScope.launch {
            try {
                writes.forEach { repository.reconcile(it) }
                deletion?.let { repository.reconcile(it) }
                if (sessionAuthority() == captured) {
                    writes.forEach { pending.remove(it.id) }
                    mutable.value =
                        mutable.value.copy(
                            pendingWrites = pending.size,
                            uncertainDelete = null,
                            notice = null,
                            error = null,
                            reconciled = true,
                            page = null,
                        )
                    refresh()
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (sessionAuthority() == captured)
                    mutable.value = mutable.value.copy(notice = historyFailure(error))
            }
        }
    }

    fun canOpen(entry: HistoryEntry): Boolean =
        synchronize() &&
            mutable.value.visible &&
            !mutable.value.loading &&
            mutable.value.page?.entries?.contains(entry) == true &&
            entry.content?.let(visibility) == true
}
