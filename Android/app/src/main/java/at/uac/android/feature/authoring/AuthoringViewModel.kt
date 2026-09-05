package at.uac.android.feature.authoring

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import at.uac.android.feature.authoring.recovery.AuthoringRecoveryException
import at.uac.android.feature.authoring.recovery.AuthoringRecoveryFailure
import at.uac.android.feature.authoring.recovery.AuthoringRecoveryScope
import at.uac.android.feature.authoring.recovery.AuthoringRecoveryStore
import at.uac.android.feature.authoring.recovery.MemoryAuthoringRecoveryStore
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.organization.OrganizationMutationGate
import at.uac.android.feature.organization.OrganizationRecord
import at.uac.android.feature.organization.OrganizationSession
import java.time.ZoneId
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.joinAll
import kotlinx.coroutines.launch

data class AuthoringState(
    val session: OrganizationSession? = null,
    val organizationId: String? = null,
    val visible: Boolean = false,
    val kind: ContentKind = ContentKind.NEWS,
    val status: AuthoringStatus = AuthoringStatus.APPROVED,
    val hub: AuthoringHub? = null,
    val fresh: Boolean = false,
    val loading: Boolean = false,
    val busy: Boolean = false,
    val error: AuthoringFailure? = null,
    val invalidField: String? = null,
    val draft: AuthoringDraft? = null,
    val base: AuthoringItem? = null,
    val draftOrganization: OrganizationRecord? = null,
    val editorFresh: Boolean = false,
    val preview: Boolean = false,
    val confirmation: AuthoringSubmission? = null,
    val uncertain: AuthoringSubmission? = null,
    val recoveryChecked: Boolean = false,
    val recoveryConflict: Boolean = false,
    val confirmed: AuthoringItem? = null,
    val recoveryLoaded: Boolean = false,
    val recoveryError: AuthoringRecoveryFailure? = null,
    val recoveredDraft: AuthoringDraft? = null,
    val draftZoneId: String = ZoneId.systemDefault().id,
    val draftSaved: Boolean = false,
    val unsavedExitCount: Int = 0,
    val exitSaveError: AuthoringRecoveryFailure? = null,
    val failedCurrentDraft: Boolean = false,
) {
    val actionable
        get() = session?.ready == true && fresh && !loading && !busy && hub != null

    val draftWritable
        get() =
            actionable &&
                draft != null &&
                editorFresh &&
                uncertain == null &&
                confirmation == null &&
                draftOrganization?.fields == hub?.organization?.fields

    val canCreate
        get() =
            actionable &&
                recoveryLoaded &&
                recoveryError == null &&
                recoveredDraft == null &&
                uncertain == null &&
                unsavedExitCount < 32
}

class AuthoringViewModel(
    source: AuthoringSource,
    private val currentSession: () -> OrganizationSession?,
    gate: OrganizationMutationGate,
    private val recoveryStore: AuthoringRecoveryStore = MemoryAuthoringRecoveryStore(),
) : ViewModel() {
    private val repository = AuthoringRepository(source, currentSession, gate, recoveryStore)
    private val mutable = MutableStateFlow(AuthoringState(session = currentSession()))
    val state: StateFlow<AuthoringState> = mutable.asStateFlow()
    private var generation = 0L
    private var readVersion = 0L
    private var watch: Job? = null
    private var read: Job? = null
    private var sessions: Job? = null
    private var pendingRefresh = false
    private var inFlight: AuthoringSubmission? = null
    private var requestedKind = ContentKind.NEWS
    private var routeKind: ContentKind? = null
    private var save: Job? = null
    private var saveVersion = 0L
    private val exitSaves = linkedSetOf<Job>()

    private data class FailedExit(
        val draft: AuthoringDraft,
        val zoneId: String,
        val reason: AuthoringRecoveryFailure,
    )

    private val failedExits = linkedMapOf<AuthoringRecoveryScope, FailedExit>()

    private fun cancelSave() {
        saveVersion++
        save?.cancel()
        save = null
    }

    private fun cancelExitSaves() {
        exitSaves.toList().forEach { it.cancel() }
        exitSaves.clear()
    }

    private fun scope(value: AuthoringState): AuthoringRecoveryScope? =
        value.session?.uid?.let { uid ->
            value.organizationId?.let { AuthoringRecoveryScope(uid, it, value.kind) }
        }

    private fun withExitState(value: AuthoringState): AuthoringState {
        val own = failedExits.filterKeys { it.uid == value.session?.uid }
        val selected = scope(value)?.let(own::get)
        return value.copy(
            unsavedExitCount = own.size,
            exitSaveError = selected?.reason ?: own.values.firstOrNull()?.reason,
            failedCurrentDraft = selected != null,
        )
    }

    private fun same(session: OrganizationSession?, epoch: Long) =
        generation == epoch && currentSession() == session && mutable.value.session == session

    private fun sameRead(session: OrganizationSession?, epoch: Long, version: Long) =
        same(session, epoch) && readVersion == version

    private fun cancelRead() {
        readVersion++
        read?.cancel()
        read = null
    }

    private fun cancelWatch() {
        watch?.cancel()
        watch = null
    }

    private fun reset(
        session: OrganizationSession?,
        id: String?,
        kind: ContentKind,
        visible: Boolean,
    ) {
        val old = mutable.value
        val sameAccount = session != null && session.uid == old.session?.uid
        val sameOwner = sameAccount && id == old.organizationId
        // A new organization must not cancel the previous scope's last unsent local write.
        if (sameAccount) flushScopeExit(old)
        else {
            cancelExitSaves()
            failedExits.clear()
        }
        generation++
        cancelWatch()
        cancelRead()
        cancelSave()
        pendingRefresh = false
        // Preserve text, never permission. Any new revision is read-only until its own fresh server
        // checks complete.
        mutable.value =
            withExitState(
                if (sameOwner)
                    AuthoringState(
                        session,
                        id,
                        visible,
                        old.draft?.kind ?: kind,
                        status = old.status,
                        draft = old.draft,
                        base = old.base,
                        draftOrganization = old.draftOrganization,
                        uncertain = old.uncertain ?: inFlight.takeIf { old.busy },
                        draftZoneId = old.draftZoneId,
                        draftSaved = old.draftSaved,
                    )
                else AuthoringState(session, id, visible, kind)
            )
        if (old.session != null && old.session.uid != session?.uid)
            viewModelScope.launch {
                // Logout removes only unsent text. A possibly sent request remains private and
                // encrypted.
                try {
                    recoveryStore.clearUnsentForAccount(old.session.uid)
                } catch (error: Exception) {
                    if (mutable.value.session == session)
                        mutable.value = mutable.value.copy(recoveryError = recoveryFailure(error))
                }
            }
    }

    fun observeSessions(values: Flow<OrganizationSession?>) {
        sessions?.cancel()
        sessions = viewModelScope.launch {
            values.collect { session ->
                if (mutable.value.session != session) {
                    reset(
                        session,
                        mutable.value.organizationId,
                        mutable.value.kind,
                        mutable.value.visible,
                    )
                    if (mutable.value.visible) start()
                }
            }
        }
    }

    fun show(id: String, initialKind: ContentKind = ContentKind.NEWS) {
        if (initialKind !in AuthoringContract.kinds) return
        if (mutable.value.organizationId != id || routeKind != initialKind)
            requestedKind = initialKind
        routeKind = initialKind
        if (mutable.value.organizationId != id || mutable.value.session != currentSession())
            reset(currentSession(), id, requestedKind, true)
        else if (
            mutable.value.visible &&
                (mutable.value.kind == requestedKind || mutable.value.draft != null)
        )
            return
        else {
            val old = mutable.value
            mutable.value =
                if (old.kind != requestedKind && old.draft == null) {
                    generation++
                    cancelRead()
                    pendingRefresh = false
                    old.copy(
                        visible = true,
                        kind = requestedKind,
                        status = AuthoringStatus.APPROVED,
                        hub = null,
                        fresh = false,
                        confirmed = null,
                    )
                } else old.copy(visible = true)
        }
        start()
    }

    fun hide() {
        scheduleSave(immediate = true)
        cancelWatch()
        cancelRead()
        pendingRefresh = false
        mutable.value =
            mutable.value.copy(visible = false, loading = false, fresh = false, confirmation = null)
    }

    private fun watch() {
        cancelWatch()
        val captured = mutable.value
        val session = captured.session ?: return
        val id = captured.organizationId ?: return
        if (!session.ready || !captured.visible) return
        val epoch = generation
        watch = viewModelScope.launch {
            repository
                .changes(id, captured.kind, captured.status, session, captured.base)
                .collect { result ->
                    if (same(session, epoch)) {
                        if (result.isSuccess) {
                            if (read?.isActive == true || mutable.value.busy) pendingRefresh = true
                            else load(false, preserveError = true)
                        } else {
                            // A later listener denial/offline result invalidates even an already
                            // queued successful read.
                            cancelRead()
                            cancelWatch()
                            pendingRefresh = false
                            mutable.value =
                                mutable.value.copy(
                                    fresh = false,
                                    editorFresh = false,
                                    loading = false,
                                    confirmation = null,
                                    error =
                                        result.exceptionOrNull()?.let(::authoringFailure)
                                            ?: AuthoringFailure.UNKNOWN,
                                )
                        }
                    }
                }
        }
    }

    private fun start() = refresh()

    fun select(
        kind: ContentKind = mutable.value.kind,
        status: AuthoringStatus = mutable.value.status,
    ) {
        val value = mutable.value
        if (
            kind !in AuthoringContract.kinds ||
                !value.actionable ||
                value.draft != null ||
                value.uncertain != null ||
                kind == value.kind && status == value.status
        )
            return
        requestedKind = kind
        generation++
        cancelRead()
        pendingRefresh = false
        mutable.value =
            value.copy(
                kind = kind,
                status = status,
                hub = null,
                fresh = false,
                error = null,
                confirmed = null,
                recoveryLoaded = false,
                recoveredDraft = null,
                recoveryError = null,
            )
        start()
    }

    fun refresh() {
        watch()
        load(false)
    }

    fun more() = load(true)

    private fun load(more: Boolean, preserveError: Boolean = false) {
        val captured = mutable.value
        val session = captured.session ?: return
        val id = captured.organizationId ?: return
        if (
            !captured.visible ||
                !session.ready ||
                session != currentSession() ||
                captured.busy ||
                read?.isActive == true
        )
            return
        if (more && (!captured.fresh || captured.hub?.page?.next == null)) return
        val epoch = generation
        val version = ++readVersion
        mutable.value =
            captured.copy(
                loading = true,
                fresh = false,
                confirmation = null,
                error = if (preserveError) captured.error else null,
            )
        read = viewModelScope.launch {
            try {
                val loaded =
                    repository.load(
                        id,
                        captured.kind,
                        captured.status,
                        if (more) captured.hub else null,
                    )
                // Returning quickly to a scope must see its completed exit flush, not an
                // older/absent draft.
                exitSaves.toList().joinAll()
                val recovered =
                    try {
                        recoveryStore.load(AuthoringRecoveryScope(session.uid, id, captured.kind))
                    } catch (error: CancellationException) {
                        throw error
                    } catch (error: Exception) {
                        if (sameRead(session, epoch, version))
                            mutable.value =
                                mutable.value.copy(
                                    recoveryLoaded = false,
                                    recoveryError = recoveryFailure(error),
                                )
                        throw error
                    }
                var editorFresh =
                    captured.draft != null &&
                        captured.draftOrganization?.fields == loaded.organization.fields
                if (captured.base != null) {
                    val current =
                        try {
                            repository.open(id, captured.base.kind, captured.base.id).second
                        } catch (error: CancellationException) {
                            throw error
                        } catch (_: Exception) {
                            null
                        }
                    editorFresh = editorFresh && current?.fields == captured.base.fields
                }
                val failed = failedExits[AuthoringRecoveryScope(session.uid, id, captured.kind)]
                if (sameRead(session, epoch, version))
                    mutable.value =
                        withExitState(
                            mutable.value.copy(
                                hub = loaded,
                                fresh = true,
                                loading = false,
                                editorFresh = editorFresh,
                                recoveryLoaded = true,
                                recoveryError = null,
                                uncertain = recovered?.pending ?: mutable.value.uncertain,
                                recoveredDraft =
                                    (failed?.draft ?: recovered?.draft)?.takeIf {
                                        mutable.value.draft == null && recovered?.pending == null
                                    },
                                draftZoneId =
                                    if (mutable.value.draft == null)
                                        failed?.zoneId
                                            ?: recovered?.draftZoneId
                                            ?: ZoneId.systemDefault().id
                                    else mutable.value.draftZoneId,
                                draftSaved = mutable.value.draftSaved && failed == null,
                            )
                        )
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (sameRead(session, epoch, version))
                    mutable.value =
                        mutable.value.copy(
                            loading = false,
                            fresh = false,
                            editorFresh = false,
                            error = authoringFailure(error),
                        )
            } finally {
                if (sameRead(session, epoch, version)) {
                    read = null
                    if (pendingRefresh && mutable.value.visible && !mutable.value.busy) {
                        pendingRefresh = false
                        load(false, preserveError = true)
                    }
                }
            }
        }
    }

    fun create() {
        val value = mutable.value
        if (!value.canCreate || value.session != currentSession() || value.draft != null) return
        val org = value.hub?.organization ?: return
        mutable.value =
            value.copy(
                draft = AuthoringContract.newDraft(value.kind, org),
                draftOrganization = org,
                base = null,
                editorFresh = true,
                preview = false,
                confirmation = null,
                uncertain = null,
                error = null,
                confirmed = null,
                invalidField = null,
                draftZoneId = ZoneId.systemDefault().id,
                draftSaved = false,
            )
        scheduleSave()
    }

    fun edit(id: String) {
        val value = mutable.value
        val session = value.session ?: return
        val org = value.organizationId ?: return
        if (
            !value.actionable ||
                value.draft != null ||
                value.uncertain != null ||
                session != currentSession() ||
                value.hub?.page?.items?.none { it.id == id && it.editable } != false
        )
            return
        val epoch = generation
        val version = ++readVersion
        mutable.value =
            value.copy(loading = true, confirmation = null, confirmed = null, error = null)
        read = viewModelScope.launch {
            try {
                val (organization, item) = repository.open(org, value.kind, id)
                val draft = AuthoringContract.draft(item)
                if (sameRead(session, epoch, version)) {
                    mutable.value =
                        mutable.value.copy(
                            base = item,
                            draft = draft,
                            draftOrganization = organization,
                            editorFresh = true,
                            loading = false,
                            hub = mutable.value.hub?.copy(organization = organization),
                            preview = false,
                            uncertain = null,
                            invalidField = null,
                        )
                    watch()
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (sameRead(session, epoch, version))
                    mutable.value =
                        mutable.value.copy(loading = false, error = authoringFailure(error))
            } finally {
                if (sameRead(session, epoch, version)) {
                    read = null
                    if (pendingRefresh) {
                        pendingRefresh = false
                        refresh()
                    }
                }
            }
        }
    }

    fun change(transform: (AuthoringDraft) -> AuthoringDraft) {
        val value = mutable.value
        val draft = value.draft ?: return
        if (!value.draftWritable || value.session != currentSession()) return
        val next = transform(draft)
        if (next.id != draft.id || next.kind != draft.kind) return
        mutable.value =
            value.copy(
                draft = next,
                error = null,
                invalidField = null,
                confirmed = null,
                preview = false,
                draftSaved = false,
            )
        scheduleSave()
    }

    private fun scheduleSave(immediate: Boolean = false) {
        cancelSave()
        val value = mutable.value
        val draft = value.draft ?: return
        val capturedScope = scope(value) ?: return
        if (
            value.base != null ||
                value.uncertain != null ||
                value.busy ||
                currentSession()?.uid != capturedScope.uid
        )
            return
        if (failedExits[capturedScope]?.draft == draft)
            return // Restoring/hiding is not an implicit retry of a failed save.
        val version = saveVersion
        save = viewModelScope.launch {
            if (!immediate) delay(650)
            if (saveVersion != version || currentSession()?.uid != capturedScope.uid) return@launch
            try {
                recoveryStore.saveDraft(capturedScope, draft, value.draftZoneId)
                if (
                    saveVersion == version &&
                        scope(mutable.value) == capturedScope &&
                        mutable.value.draft == draft
                ) {
                    if (failedExits[capturedScope]?.draft?.id == draft.id)
                        failedExits.remove(capturedScope)
                    mutable.value =
                        withExitState(mutable.value.copy(draftSaved = true, recoveryError = null))
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (saveVersion == version && scope(mutable.value) == capturedScope)
                    mutable.value =
                        mutable.value.copy(
                            draftSaved = false,
                            recoveryError = recoveryFailure(error),
                        )
            }
        }
    }

    private fun flushScopeExit(value: AuthoringState) {
        val draft = value.draft ?: return
        val capturedScope = scope(value) ?: return
        if (
            value.base != null ||
                value.draftSaved ||
                value.uncertain != null ||
                value.busy ||
                currentSession()?.uid != capturedScope.uid
        )
            return
        if (failedExits[capturedScope]?.draft == draft)
            return // Passive navigation is not an implicit retry.
        val preceding = exitSaves.lastOrNull()
        val task =
            viewModelScope.launch(start = CoroutineStart.LAZY) {
                preceding?.join()
                if (currentSession()?.uid != capturedScope.uid) return@launch
                try {
                    recoveryStore.saveDraft(capturedScope, draft, value.draftZoneId)
                    if (failedExits[capturedScope]?.draft?.id == draft.id)
                        failedExits.remove(capturedScope)
                    if (
                        scope(mutable.value) == capturedScope &&
                            mutable.value.draft == draft &&
                            currentSession()?.uid == capturedScope.uid
                    )
                        mutable.value =
                            withExitState(
                                mutable.value.copy(draftSaved = true, recoveryError = null)
                            )
                    else if (currentSession()?.uid == capturedScope.uid)
                        mutable.value = withExitState(mutable.value)
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Exception) {
                    if (currentSession()?.uid == capturedScope.uid) {
                        failedExits[capturedScope] =
                            FailedExit(draft, value.draftZoneId, recoveryFailure(error))
                        mutable.value = withExitState(mutable.value)
                    }
                }
            }
        exitSaves += task
        task.invokeOnCompletion { exitSaves.remove(task) }
        task.start()
    }

    fun restoreDraft() {
        val value = mutable.value
        val draft = value.recoveredDraft ?: return
        if (
            !value.actionable ||
                value.session != currentSession() ||
                !value.recoveryLoaded ||
                value.recoveryError != null ||
                value.uncertain != null ||
                value.draft != null
        )
            return
        val org = value.hub?.organization ?: return
        mutable.value =
            value.copy(
                draft = draft,
                recoveredDraft = null,
                base = null,
                draftOrganization = org,
                editorFresh = true,
                draftSaved = !value.failedCurrentDraft,
                error = null,
                confirmed = null,
            )
    }

    fun retryFailedLocalSave() {
        val value = mutable.value
        val capturedScope = scope(value) ?: return
        val failed = failedExits[capturedScope] ?: return
        if (
            !value.actionable ||
                value.session != currentSession() ||
                value.uncertain != null ||
                value.recoveryError != null ||
                value.base != null
        )
            return
        val draft = value.draft?.takeIf { it.id == failed.draft.id } ?: failed.draft
        val epoch = generation
        cancelSave()
        mutable.value = value.copy(busy = true)
        viewModelScope.launch {
            try {
                exitSaves.toList().joinAll()
                if (!same(value.session, epoch)) return@launch
                recoveryStore.saveDraft(capturedScope, draft, failed.zoneId)
                if (same(value.session, epoch)) {
                    failedExits.remove(capturedScope)
                    mutable.value =
                        withExitState(
                            mutable.value.copy(
                                busy = false,
                                draftSaved = mutable.value.draft == draft,
                                recoveredDraft = draft.takeIf { mutable.value.draft == null },
                            )
                        )
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (same(value.session, epoch)) {
                    failedExits[capturedScope] =
                        failed.copy(draft = draft, reason = recoveryFailure(error))
                    mutable.value = withExitState(mutable.value.copy(busy = false))
                }
            }
        }
    }

    fun discardRecoveredDraft() {
        val value = mutable.value
        val draft = value.recoveredDraft ?: return
        val capturedScope = scope(value) ?: return
        if (!value.actionable || value.session != currentSession() || value.uncertain != null)
            return
        val epoch = generation
        mutable.value = value.copy(busy = true)
        viewModelScope.launch {
            try {
                recoveryStore.discardUnsent(capturedScope, draft.id)
                if (same(value.session, epoch)) {
                    if (failedExits[capturedScope]?.draft?.id == draft.id)
                        failedExits.remove(capturedScope)
                    mutable.value =
                        withExitState(
                            mutable.value.copy(
                                recoveredDraft = null,
                                recoveryError = null,
                                busy = false,
                            )
                        )
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (same(value.session, epoch))
                    mutable.value =
                        mutable.value.copy(recoveryError = recoveryFailure(error), busy = false)
            }
        }
    }

    fun preview() {
        val value = mutable.value
        if (!value.draftWritable || value.session != currentSession()) return
        try {
            AuthoringContract.submission(
                requireNotNull(value.draft),
                requireNotNull(value.draftOrganization),
                requireNotNull(value.session),
                value.base,
                zone = ZoneId.of(value.draftZoneId),
            )
            mutable.value = value.copy(preview = true, error = null, invalidField = null)
        } catch (error: AuthoringException) {
            mutable.value = value.copy(error = error.failure, invalidField = error.field)
        }
    }

    fun closePreview() {
        mutable.value = mutable.value.copy(preview = false)
    }

    fun closeEditor() {
        val value = mutable.value
        if (value.busy || value.uncertain != null) return
        cancelSave()
        val changedKind = value.kind != requestedKind
        if (changedKind) {
            generation++
            cancelRead()
            pendingRefresh = false
        }
        mutable.value =
            value.copy(
                draft = null,
                base = null,
                draftOrganization = null,
                editorFresh = false,
                preview = false,
                confirmation = null,
                invalidField = null,
                kind = requestedKind,
                status = if (changedKind) AuthoringStatus.APPROVED else value.status,
                hub = if (changedKind) null else value.hub,
                fresh = !changedKind && value.fresh,
            )
        if (changedKind) start() else watch()
    }

    fun requestSubmit() {
        val value = mutable.value
        if (!value.draftWritable || value.session != currentSession()) return
        try {
            val intent =
                AuthoringContract.submission(
                    requireNotNull(value.draft),
                    requireNotNull(value.draftOrganization),
                    requireNotNull(value.session),
                    value.base,
                    zone = ZoneId.of(value.draftZoneId),
                )
            mutable.value =
                value.copy(
                    confirmation = intent,
                    preview = false,
                    error = null,
                    invalidField = null,
                )
        } catch (error: AuthoringException) {
            mutable.value = value.copy(error = error.failure, invalidField = error.field)
        }
    }

    fun dismissConfirmation() {
        if (!mutable.value.busy) mutable.value = mutable.value.copy(confirmation = null)
    }

    fun confirm() {
        val value = mutable.value
        val intent = value.confirmation ?: return
        if (
            !value.actionable ||
                value.session != currentSession() ||
                !value.editorFresh ||
                value.draftOrganization?.fields != value.hub?.organization?.fields
        )
            return
        execute(intent)
    }

    private fun execute(intent: AuthoringSubmission) {
        val value = mutable.value
        val session = value.session ?: return
        val epoch = generation
        if (value.busy || session != currentSession()) return
        cancelSave()
        inFlight = intent
        mutable.value =
            value.copy(busy = true, confirmation = null, error = null, recoveryChecked = false)
        viewModelScope.launch {
            try {
                val saved = repository.submit(intent)
                if (same(session, epoch)) confirmed(saved)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                val reason = authoringFailure(error)
                if (same(session, epoch))
                    mutable.value =
                        mutable.value.copy(
                            busy = false,
                            fresh = false,
                            error = reason,
                            uncertain =
                                value.uncertain
                                    ?: intent.takeIf {
                                        error !is AuthoringRecoveryException &&
                                            reason in
                                                setOf(
                                                    AuthoringFailure.UNCONFIRMED,
                                                    AuthoringFailure.UNKNOWN,
                                                )
                                    },
                            editorFresh = false,
                            invalidField = (error as? AuthoringException)?.field,
                            recoveryError = (error as? AuthoringRecoveryException)?.reason,
                        )
            } finally {
                if (inFlight === intent) inFlight = null
                if (same(session, epoch)) {
                    mutable.value = mutable.value.copy(busy = false)
                    pendingRefresh = false
                    load(false, preserveError = true)
                }
            }
        }
    }

    private fun confirmed(item: AuthoringItem) {
        val captured = mutable.value
        val target = scope(captured)
        if (
            target != null &&
                failedExits[target]?.draft == captured.draft &&
                captured.draft?.id == item.id
        )
            failedExits.remove(target)
        mutable.value =
            withExitState(
                captured.copy(
                    confirmed = item,
                    draft = null,
                    base = null,
                    draftOrganization = null,
                    editorFresh = false,
                    preview = false,
                    uncertain = null,
                    recoveryChecked = false,
                    recoveryConflict = false,
                    confirmation = null,
                    error = null,
                    invalidField = null,
                    status = item.status,
                    hub = null,
                    fresh = false,
                    busy = false,
                    recoveredDraft = null,
                    draftSaved = false,
                    recoveryError = null,
                )
            )
        watch()
    }

    fun recover() {
        val value = mutable.value
        val intent = value.uncertain ?: return
        val session = value.session ?: return
        if (
            !value.visible ||
                value.busy ||
                value.loading ||
                session != currentSession() ||
                !session.ready
        )
            return
        val epoch = generation
        mutable.value = value.copy(busy = true, error = null, recoveryChecked = false)
        viewModelScope.launch {
            try {
                val item = repository.recover(intent)
                if (same(session, epoch)) {
                    if (item != null && AuthoringContract.matches(intent, item)) confirmed(item)
                    else
                        mutable.value =
                            mutable.value.copy(
                                busy = false,
                                recoveryChecked = true,
                                recoveryConflict = item != null,
                            )
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (same(session, epoch))
                    mutable.value =
                        mutable.value.copy(
                            busy = false,
                            error = authoringFailure(error),
                            recoveryChecked = false,
                        )
            } finally {
                if (same(session, epoch)) {
                    mutable.value = mutable.value.copy(busy = false)
                    load(false, preserveError = true)
                }
            }
        }
    }

    fun retryAbsentCreation() {
        val value = mutable.value
        val intent = value.uncertain ?: return
        if (
            !value.actionable ||
                !value.recoveryChecked ||
                value.recoveryConflict ||
                intent.base != null ||
                value.session != currentSession()
        )
            return
        if (!AuthoringPublication.canSend(intent)) {
            mutable.value = value.copy(error = AuthoringFailure.INVALID, invalidField = "schedule")
            return
        }
        // Explicit action only, same immutable payload/UUID; repository rechecks absence and
        // current authority again.
        execute(intent)
    }

    fun discardLocalForm() {
        val value = mutable.value
        if (value.busy || value.uncertain != null) return
        val draft = value.draft ?: return
        val capturedScope = scope(value) ?: return
        cancelSave()
        if (value.base != null) {
            closeEditor()
            return
        }
        val epoch = generation
        mutable.value = value.copy(busy = true)
        viewModelScope.launch {
            try {
                recoveryStore.discardUnsent(capturedScope, draft.id)
                if (same(value.session, epoch)) {
                    if (failedExits[capturedScope]?.draft?.id == draft.id)
                        failedExits.remove(capturedScope)
                    mutable.value =
                        withExitState(mutable.value.copy(busy = false, recoveredDraft = null))
                    closeEditor()
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (same(value.session, epoch))
                    mutable.value =
                        mutable.value.copy(busy = false, recoveryError = recoveryFailure(error))
            }
        }
    }

    private fun recoveryFailure(error: Exception) =
        (error as? AuthoringRecoveryException)?.reason ?: AuthoringRecoveryFailure.IO

    override fun onCleared() {
        sessions?.cancel()
        cancelWatch()
        cancelRead()
        cancelSave()
        cancelExitSaves()
    }
}
