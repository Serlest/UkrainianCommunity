package at.uac.android.feature.contentplanning

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import at.uac.android.feature.moderation.ModerationSession
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class ContentPlanningSectionState(
    val items: List<ContentPlanningDraft> = emptyList(),
    val cursor: ContentPlanningCursor? = null,
    val hasMore: Boolean = false,
    val loaded: Boolean = false,
    val loading: Boolean = false,
    val loadingMore: Boolean = false,
    val error: ContentPlanningFailure? = null,
)

enum class ContentPlanningRecoveryPhase {
    BEGIN_UNCONFIRMED,
    LEASED,
    FINALIZE_UNCONFIRMED,
    FAIL_UNCONFIRMED,
    ARCHIVE_UNCONFIRMED,
    DELETE_UNCONFIRMED,
}

data class ContentPlanningRecovery(
    val draftId: String,
    val attemptId: String?,
    val lease: ContentPlanningLease?,
    val phase: ContentPlanningRecoveryPhase,
) {
    override fun toString() = "ContentPlanningRecovery(phase=$phase, [redacted])"
}

data class ContentPlanningUiState(
    val session: ModerationSession? = null,
    val visible: Boolean = false,
    val selectedSection: ContentPlanningSection = ContentPlanningSection.DRAFTS,
    val sections: Map<ContentPlanningSection, ContentPlanningSectionState> =
        ContentPlanningSection.entries.associateWith { ContentPlanningSectionState() },
    val selected: ContentPlanningDraft? = null,
    val organizations: List<ContentPlanningOrganization> = emptyList(),
    val organizationsLoading: Boolean = false,
    val detailLoading: Boolean = false,
    val busyDraftId: String? = null,
    val recovery: ContentPlanningRecovery? = null,
    val error: ContentPlanningFailure? = null,
    val completion: Long = 0,
) {
    val allowed: Boolean
        get() = session?.let { it.ready && it.role == "owner" } == true

    fun section() = sections[selectedSection] ?: ContentPlanningSectionState()

    override fun toString() =
        "ContentPlanningUiState(visible=$visible, section=$selectedSection, [redacted])"
}

class ContentPlanningViewModel(
    private val repository: ContentPlanningRepository,
    private val workScope: CoroutineScope? = null,
) : ViewModel() {
    private val scope: CoroutineScope
        get() = workScope ?: viewModelScope

    private val mutable = MutableStateFlow(ContentPlanningUiState())
    val state: StateFlow<ContentPlanningUiState> = mutable.asStateFlow()
    private var load: Job? = null
    private var detail: Job? = null
    private var mutation: Job? = null
    private var generation = 0L
    private val attempts = mutableMapOf<String, String>()
    private val leases = mutableMapOf<String, ContentPlanningLease>()
    private val publications = mutableMapOf<String, ContentPlanningPublication>()
    private val failureMessages = mutableMapOf<String, String>()

    fun show(session: ModerationSession?) {
        if (session == mutable.value.session && mutable.value.visible) return
        bind(session, true)
    }

    fun hide() {
        generation++
        load?.cancel()
        detail?.cancel()
        mutable.value = mutable.value.copy(visible = false, detailLoading = false)
    }

    fun bind(session: ModerationSession?, visible: Boolean = mutable.value.visible) {
        val valid = session?.takeIf {
            it.ready && it.role == "owner" && it == repository.currentSession()
        }
        if (valid != null && valid == mutable.value.session) {
            mutable.value = mutable.value.copy(visible = visible)
            if (visible && !mutable.value.sections.getValue(mutable.value.selectedSection).loaded)
                refresh()
            return
        }
        if (valid == mutable.value.session && visible == mutable.value.visible) return
        generation++
        load?.cancel()
        detail?.cancel()
        if (valid?.uid != mutable.value.session?.uid) {
            attempts.clear()
            leases.clear()
            publications.clear()
            failureMessages.clear()
        }
        mutable.value = ContentPlanningUiState(session = valid, visible = visible)
        if (visible && valid != null) refresh()
    }

    fun select(section: ContentPlanningSection) {
        if (section == mutable.value.selectedSection) return
        mutable.value = mutable.value.copy(selectedSection = section, selected = null, error = null)
        if (!mutable.value.sections.getValue(section).loaded) refresh()
    }

    fun refresh() {
        val session = live() ?: return
        val section = mutable.value.selectedSection
        val epoch = generation
        load?.cancel()
        updateSection(section) { it.copy(loading = true, loadingMore = false, error = null) }
        mutable.value =
            mutable.value.copy(organizationsLoading = mutable.value.organizations.isEmpty())
        load = scope.launch {
            try {
                val (page, organizations) =
                    coroutineScope {
                        val page = async { repository.page(session, section) }
                        val organizations = async {
                            if (mutable.value.organizations.isEmpty())
                                repository.organizations(session)
                            else mutable.value.organizations
                        }
                        page.await() to organizations.await()
                    }
                if (!same(session, epoch)) return@launch
                updateSection(section) {
                    ContentPlanningSectionState(page.items, page.cursor, page.hasMore, true)
                }
                mutable.value.selected?.id?.let { selectedId ->
                    page.items
                        .firstOrNull { it.id == selectedId }
                        ?.let { selected ->
                            mutable.value = mutable.value.copy(selected = selected)
                        }
                }
                mutable.value =
                    mutable.value.copy(
                        organizations = organizations,
                        organizationsLoading = false,
                    )
            } catch (error: CancellationException) {
                throw error
            } catch (error: ContentPlanningException) {
                if (same(session, epoch))
                    updateSection(section) {
                        it.copy(loading = false, error = error.failure, loaded = true)
                    }
                mutable.value = mutable.value.copy(organizationsLoading = false)
            }
        }
    }

    fun more() {
        val session = live() ?: return
        val section = mutable.value.selectedSection
        val snapshot = mutable.value.sections.getValue(section)
        val cursor = snapshot.cursor ?: return
        if (!snapshot.hasMore || snapshot.loading || snapshot.loadingMore) return
        val epoch = generation
        updateSection(section) { it.copy(loadingMore = true, error = null) }
        load = scope.launch {
            try {
                val page = repository.page(session, section, cursor)
                if (!same(session, epoch)) return@launch
                updateSection(section) { old ->
                    val ids = old.items.mapTo(mutableSetOf(), ContentPlanningDraft::id)
                    old.copy(
                        items = old.items + page.items.filter { ids.add(it.id) },
                        cursor = page.cursor,
                        hasMore = page.hasMore,
                        loadingMore = false,
                    )
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: ContentPlanningException) {
                if (same(session, epoch))
                    updateSection(section) { it.copy(loadingMore = false, error = error.failure) }
            }
        }
    }

    fun open(draftId: String) {
        val session = live() ?: return
        val epoch = generation
        detail?.cancel()
        mutable.value = mutable.value.copy(detailLoading = true, error = null)
        detail = scope.launch {
            try {
                val draft = repository.draft(session, draftId)
                if (same(session, epoch))
                    mutable.value = mutable.value.copy(selected = draft, detailLoading = false)
            } catch (error: CancellationException) {
                throw error
            } catch (error: ContentPlanningException) {
                if (same(session, epoch))
                    mutable.value = mutable.value.copy(detailLoading = false, error = error.failure)
            }
        }
    }

    fun closeDetail() {
        detail?.cancel()
        mutable.value = mutable.value.copy(selected = null, detailLoading = false, error = null)
    }

    /**
     * Returns a cached lease synchronously or dispatches one request. Call again explicitly after
     * ambiguity.
     */
    fun begin(draft: ContentPlanningDraft, onLease: (ContentPlanningLease) -> Unit = {}) {
        val session = live() ?: return
        leases[draft.id]
            ?.takeIf { it.expiresAt > Instant.now() }
            ?.let {
                mutable.value =
                    mutable.value.copy(
                        error = null,
                        recovery =
                            ContentPlanningRecovery(
                                draft.id,
                                attempts[draft.id],
                                it,
                                ContentPlanningRecoveryPhase.LEASED,
                            ),
                    )
                onLease(it)
                return
            }
        val attempt = attempts.getOrPut(draft.id) { UUID.randomUUID().toString() }
        operate(draft.id) { current, currentCheck ->
            try {
                val lease = repository.begin(current, draft.id, attempt, currentCheck)
                if (!currentCheck()) return@operate
                leases[draft.id] = lease
                mutable.value =
                    mutable.value.copy(
                        recovery =
                            ContentPlanningRecovery(
                                draft.id,
                                attempt,
                                lease,
                                ContentPlanningRecoveryPhase.LEASED,
                            ),
                        error = null,
                    )
                onLease(lease)
            } catch (error: ContentPlanningException) {
                if (!currentCheck()) return@operate
                mutable.value =
                    mutable.value.copy(
                        recovery =
                            if (error.failure == ContentPlanningFailure.UNCONFIRMED)
                                ContentPlanningRecovery(
                                    draft.id,
                                    attempt,
                                    null,
                                    ContentPlanningRecoveryPhase.BEGIN_UNCONFIRMED,
                                )
                            else null,
                        error = error.failure,
                    )
            }
        }
    }

    /** Editor seam: one request, stable attempt ID, exact deterministic content ID. */
    suspend fun beginForEditor(draft: ContentPlanningDraft): ContentPlanningLease {
        val session = ownerSession() ?: ContentPlanningContract.fail(ContentPlanningFailure.DENIED)
        leases[draft.id]
            ?.takeIf { it.expiresAt > Instant.now() }
            ?.let {
                return it
            }
        val attempt = attempts.getOrPut(draft.id) { UUID.randomUUID().toString() }
        return try {
            repository
                .begin(session, draft.id, attempt) { ownerSession() == session }
                .also { lease ->
                    if (ownerSession() != session)
                        ContentPlanningContract.fail(ContentPlanningFailure.DENIED)
                    if (lease.contentId != ContentPlanningContract.reservedContentId(draft.id))
                        ContentPlanningContract.invalid()
                    leases[draft.id] = lease
                    mutable.value =
                        mutable.value.copy(
                            recovery =
                                ContentPlanningRecovery(
                                    draft.id,
                                    attempt,
                                    lease,
                                    ContentPlanningRecoveryPhase.LEASED,
                                ),
                            error = null,
                        )
                }
        } catch (error: ContentPlanningException) {
            mutable.value =
                mutable.value.copy(
                    recovery =
                        if (error.failure == ContentPlanningFailure.UNCONFIRMED)
                            ContentPlanningRecovery(
                                draft.id,
                                attempt,
                                null,
                                ContentPlanningRecoveryPhase.BEGIN_UNCONFIRMED,
                            )
                        else null,
                    error = error.failure,
                )
            throw error
        }
    }

    suspend fun finalizeForEditor(
        draft: ContentPlanningDraft,
        lease: ContentPlanningLease,
        publication: ContentPlanningPublication,
    ) {
        val session = ownerSession() ?: ContentPlanningContract.fail(ContentPlanningFailure.DENIED)
        if (
            leases[draft.id] != lease ||
                publication.kind != lease.kind ||
                publication.contentId != lease.contentId
        )
            ContentPlanningContract.invalid()
        publications[draft.id] = publication
        try {
            repository.finalize(session, draft, lease) { ownerSession() == session }
            if (ownerSession() != session)
                ContentPlanningContract.fail(ContentPlanningFailure.DENIED)
            clearAttempt(draft.id)
            remove(draft.id)
            mutable.value =
                mutable.value.copy(
                    selected = null,
                    recovery = null,
                    error = null,
                    completion = mutable.value.completion + 1,
                )
        } catch (error: ContentPlanningException) {
            mutable.value =
                mutable.value.copy(
                    recovery =
                        ContentPlanningRecovery(
                            draft.id,
                            attempts[draft.id],
                            lease,
                            ContentPlanningRecoveryPhase.FINALIZE_UNCONFIRMED,
                        ),
                    error = error.failure,
                )
            throw error
        }
    }

    suspend fun failForEditor(
        draft: ContentPlanningDraft,
        lease: ContentPlanningLease,
        message: String,
    ) {
        val session = ownerSession() ?: ContentPlanningContract.fail(ContentPlanningFailure.DENIED)
        if (leases[draft.id] != lease) ContentPlanningContract.invalid()
        failureMessages[draft.id] = message
        try {
            repository.fail(session, draft.id, lease.leaseId, message) {
                ownerSession() == session
            }
            if (ownerSession() != session)
                ContentPlanningContract.fail(ContentPlanningFailure.DENIED)
            clearAttempt(draft.id)
            remove(draft.id)
            mutable.value = mutable.value.copy(selected = null, recovery = null, error = null)
        } catch (error: ContentPlanningException) {
            mutable.value =
                mutable.value.copy(
                    recovery =
                        ContentPlanningRecovery(
                            draft.id,
                            attempts[draft.id],
                            lease,
                            ContentPlanningRecoveryPhase.FAIL_UNCONFIRMED,
                        ),
                    error = error.failure,
                )
            throw error
        }
    }

    /** Called only after the editor has read back the exact server-reserved content document. */
    fun finalize(draft: ContentPlanningDraft, publication: ContentPlanningPublication) {
        val lease =
            leases[draft.id]
                ?: run {
                    mutable.value = mutable.value.copy(error = ContentPlanningFailure.INVALID)
                    return
                }
        if (publication.kind != lease.kind || publication.contentId != lease.contentId) {
            mutable.value = mutable.value.copy(error = ContentPlanningFailure.INVALID)
            return
        }
        publications[draft.id] = publication
        operate(draft.id) { session, current ->
            try {
                repository.finalize(session, draft, lease, current)
                if (!current()) return@operate
                clearAttempt(draft.id)
                remove(draft.id)
                mutable.value =
                    mutable.value.copy(
                        selected = null,
                        recovery = null,
                        error = null,
                        completion = mutable.value.completion + 1,
                    )
                refresh()
            } catch (error: ContentPlanningException) {
                if (!current()) return@operate
                mutable.value =
                    mutable.value.copy(
                        recovery =
                            ContentPlanningRecovery(
                                draft.id,
                                attempts[draft.id],
                                lease,
                                ContentPlanningRecoveryPhase.FINALIZE_UNCONFIRMED,
                            ),
                        error = error.failure,
                    )
            }
        }
    }

    fun failPublication(draft: ContentPlanningDraft, message: String) {
        val lease = leases[draft.id] ?: return
        failureMessages[draft.id] = message
        operate(draft.id) { session, current ->
            try {
                repository.fail(session, draft.id, lease.leaseId, message, current)
                if (!current()) return@operate
                clearAttempt(draft.id)
                remove(draft.id)
                mutable.value = mutable.value.copy(selected = null, recovery = null, error = null)
                selectOrRefresh(ContentPlanningSection.ATTENTION)
            } catch (error: ContentPlanningException) {
                if (!current()) return@operate
                mutable.value =
                    mutable.value.copy(
                        recovery =
                            ContentPlanningRecovery(
                                draft.id,
                                attempts[draft.id],
                                lease,
                                ContentPlanningRecoveryPhase.FAIL_UNCONFIRMED,
                            ),
                        error = error.failure,
                    )
            }
        }
    }

    fun archive(draft: ContentPlanningDraft) {
        if (!draft.canArchive) return
        simpleMutation(draft, ContentPlanningRecoveryPhase.ARCHIVE_UNCONFIRMED) { session, current
            ->
            repository.archive(session, draft.id, current)
        }
    }

    fun delete(draft: ContentPlanningDraft) {
        if (!draft.canDelete) return
        simpleMutation(draft, ContentPlanningRecoveryPhase.DELETE_UNCONFIRMED) { session, current ->
            repository.delete(session, draft.id, current)
        }
    }

    /** Read-only reconciliation after any uncertain mutation. It never replays the mutation. */
    fun reconcile() {
        val recovery = mutable.value.recovery ?: return
        val session = live() ?: return
        val epoch = generation
        detail?.cancel()
        mutable.value = mutable.value.copy(detailLoading = true, error = null)
        detail = scope.launch {
            try {
                val draft = repository.draft(session, recovery.draftId)
                if (!same(session, epoch)) return@launch
                val settled =
                    when (recovery.phase) {
                        ContentPlanningRecoveryPhase.ARCHIVE_UNCONFIRMED ->
                            draft.state == ContentPlanningState.ARCHIVED
                        ContentPlanningRecoveryPhase.FINALIZE_UNCONFIRMED ->
                            draft.state in
                                setOf(
                                    ContentPlanningState.SCHEDULED,
                                    ContentPlanningState.COMPLETED,
                                )
                        ContentPlanningRecoveryPhase.FAIL_UNCONFIRMED ->
                            draft.state == ContentPlanningState.FAILED
                        else -> false
                    }
                if (settled) clearAttempt(draft.id)
                mutable.value =
                    mutable.value.copy(
                        selected = draft,
                        detailLoading = false,
                        recovery = if (settled) null else recovery,
                        error = null,
                        completion = mutable.value.completion + if (settled) 1 else 0,
                    )
            } catch (error: CancellationException) {
                throw error
            } catch (error: ContentPlanningException) {
                if (!same(session, epoch)) return@launch
                if (
                    recovery.phase == ContentPlanningRecoveryPhase.DELETE_UNCONFIRMED &&
                        error.failure == ContentPlanningFailure.MISSING
                ) {
                    clearAttempt(recovery.draftId)
                    remove(recovery.draftId)
                    mutable.value =
                        mutable.value.copy(
                            selected = null,
                            detailLoading = false,
                            recovery = null,
                            error = null,
                            completion = mutable.value.completion + 1,
                        )
                } else
                    mutable.value = mutable.value.copy(detailLoading = false, error = error.failure)
            }
        }
    }

    /** User-triggered exact retry. The same attempt/lease is retained; nothing runs on resume. */
    fun retryRecovery() {
        val recovery = mutable.value.recovery ?: return
        val draft =
            mutable.value.selected?.takeIf { it.id == recovery.draftId }
                ?: mutable.value.sections.values
                    .asSequence()
                    .flatMap { it.items.asSequence() }
                    .firstOrNull { it.id == recovery.draftId }
                ?: return
        when (recovery.phase) {
            ContentPlanningRecoveryPhase.BEGIN_UNCONFIRMED -> begin(draft)
            ContentPlanningRecoveryPhase.FINALIZE_UNCONFIRMED ->
                publications[draft.id]?.let { finalize(draft, it) }
            ContentPlanningRecoveryPhase.FAIL_UNCONFIRMED ->
                failureMessages[draft.id]?.let { failPublication(draft, it) }
            ContentPlanningRecoveryPhase.LEASED ->
                recovery.lease?.let { /* editor owns the next step */ }
            ContentPlanningRecoveryPhase.ARCHIVE_UNCONFIRMED,
            ContentPlanningRecoveryPhase.DELETE_UNCONFIRMED -> Unit
        }
    }

    private fun simpleMutation(
        draft: ContentPlanningDraft,
        uncertain: ContentPlanningRecoveryPhase,
        block: suspend (ModerationSession, () -> Boolean) -> Boolean,
    ) =
        operate(draft.id) { session, current ->
            try {
                block(session, current)
                if (!current()) return@operate
                clearAttempt(draft.id)
                remove(draft.id)
                mutable.value =
                    mutable.value.copy(
                        selected = null,
                        recovery = null,
                        error = null,
                        completion = mutable.value.completion + 1,
                    )
                refresh()
            } catch (error: ContentPlanningException) {
                if (!current()) return@operate
                mutable.value =
                    mutable.value.copy(
                        recovery =
                            if (error.failure == ContentPlanningFailure.UNCONFIRMED)
                                ContentPlanningRecovery(draft.id, null, null, uncertain)
                            else mutable.value.recovery,
                        error = error.failure,
                    )
            }
        }

    private fun operate(
        draftId: String,
        block: suspend (ModerationSession, () -> Boolean) -> Unit,
    ) {
        if (mutation?.isActive == true) return
        val session = live() ?: return
        val epoch = generation
        fun current() = same(session, epoch) && mutable.value.busyDraftId == draftId
        mutable.value = mutable.value.copy(busyDraftId = draftId, error = null)
        mutation = scope.launch {
            try {
                block(session, ::current)
            } catch (error: CancellationException) {
                throw error
            } finally {
                if (current()) mutable.value = mutable.value.copy(busyDraftId = null)
            }
        }
    }

    private fun live(): ModerationSession? = ownerSession()?.takeIf { mutable.value.visible }

    private fun ownerSession(): ModerationSession? =
        mutable.value.session?.takeIf {
            it.ready && it.role == "owner" && it == repository.currentSession()
        }

    private fun same(session: ModerationSession, epoch: Long) =
        generation == epoch &&
            mutable.value.session == session &&
            repository.currentSession() == session

    private fun updateSection(
        section: ContentPlanningSection,
        transform: (ContentPlanningSectionState) -> ContentPlanningSectionState,
    ) {
        mutable.value =
            mutable.value.copy(
                sections =
                    mutable.value.sections +
                        (section to transform(mutable.value.sections.getValue(section)))
            )
    }

    private fun clearAttempt(draftId: String) {
        attempts.remove(draftId)
        leases.remove(draftId)
        publications.remove(draftId)
        failureMessages.remove(draftId)
    }

    private fun remove(draftId: String) {
        mutable.value =
            mutable.value.copy(
                sections =
                    mutable.value.sections.mapValues { (_, section) ->
                        section.copy(items = section.items.filterNot { it.id == draftId })
                    }
            )
    }

    private fun selectOrRefresh(section: ContentPlanningSection) {
        if (mutable.value.selectedSection == section) refresh() else select(section)
    }
}
