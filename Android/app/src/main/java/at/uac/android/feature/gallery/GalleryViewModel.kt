package at.uac.android.feature.gallery

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import at.uac.android.core.DeniedExternalImagePickerAuthorization
import at.uac.android.core.ExternalImagePickerAuthorization
import at.uac.android.core.ExternalImagePickerLease
import at.uac.android.feature.browse.Content
import at.uac.android.feature.organization.OrganizationContract
import at.uac.android.feature.organization.OrganizationMutationGate
import at.uac.android.feature.organization.OrganizationSession
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

sealed interface GalleryConfirmation {
    data class Upload(val intent: GalleryUploadIntent) : GalleryConfirmation

    data class Remove(val photo: GalleryPhoto) : GalleryConfirmation

    data class Cleanup(val entry: GalleryJournalEntry) : GalleryConfirmation
}

data class GalleryState(
    val session: OrganizationSession? = null,
    val organizationId: String? = null,
    val visible: Boolean = false,
    val snapshot: GallerySnapshot? = null,
    val fresh: Boolean = false,
    val loading: Boolean = false,
    val busy: Boolean = false,
    val pickerOpen: Boolean = false,
    val preparing: Boolean = false,
    val prepared: PreparedGalleryPhoto? = null,
    val caption: String = "",
    val confirmation: GalleryConfirmation? = null,
    val pending: List<GalleryJournalEntry> = emptyList(),
    val recovery: GalleryRecovery? = null,
    val recoveryFor: GalleryJournalEntry? = null,
    val confirmed: Boolean = false,
    val error: GalleryFailure? = null,
    val preview: GalleryBlob? = null,
    val previewPhoto: GalleryPhoto? = null,
) {
    val locked
        get() = busy || preparing || pickerOpen

    val readable
        get() =
            visible && session?.ready == true && fresh && snapshot != null && !loading && !locked

    val actionable
        get() = readable && !snapshot!!.overflow

    val canChoose
        get() =
            actionable &&
                pending.isEmpty() &&
                confirmation == null &&
                snapshot!!.photos.size < GalleryContract.MAX_PHOTOS

    val canUpload
        get() =
            canChoose &&
                prepared != null &&
                runCatching { GalleryContract.caption(caption) }.isSuccess

    fun forSession(current: OrganizationSession?, id: String) =
        if (session == current && organizationId == id) this else GalleryState(current, id)

    override fun toString() =
        "GalleryState(visible=$visible, fresh=$fresh, loading=$loading, busy=$busy, error=$error, redacted)"
}

/**
 * Draft pixels/caption/picker lease are memory-only. A new UID clears them; a fresh revision
 * requires new server authority.
 */
class GalleryViewModel(
    source: GallerySource,
    private val journal: GalleryJournal,
    private val preparation: GalleryPreparation,
    private val currentSession: () -> OrganizationSession?,
    gate: OrganizationMutationGate,
    private val pickerAuthorization: ExternalImagePickerAuthorization =
        DeniedExternalImagePickerAuthorization,
    private val visibleOrganization: (Content) -> Boolean = { true },
) : ViewModel() {
    private val repository =
        GalleryRepository(source, journal, currentSession, gate, visibleOrganization)
    private val mutable = MutableStateFlow(GalleryState(session = currentSession()))
    val state = mutable.asStateFlow()
    private var observer: Job? = null
    private var read: Job? = null
    private var watch: Job? = null
    private var processing: Job? = null
    private var operation: Job? = null
    private var previewRead: Job? = null
    private var epoch = 0L
    private var dirty = false
    private var watchTarget: Pair<OrganizationSession, String>? = null

    private data class Picker(
        val session: OrganizationSession,
        val organizationId: String,
        val lease: ExternalImagePickerLease,
    )

    private var picker: Picker? = null
    private var uploadIntent: GalleryUploadIntent? = null

    fun observeSessions(sessions: Flow<OrganizationSession?>) {
        observer?.cancel()
        observer =
            viewModelScope.launch(Dispatchers.Main.immediate, start = CoroutineStart.UNDISPATCHED) {
                sessions.collect(::bind)
            }
    }

    fun bind(session: OrganizationSession?) {
        if (mutable.value.session == session) return
        reset(session, mutable.value.organizationId, mutable.value.visible)
        if (mutable.value.visible) refresh()
    }

    private fun stopRead() {
        read?.cancel()
        read = null
        previewRead?.cancel()
        previewRead = null
        watch?.cancel()
        watch = null
        watchTarget = null
        dirty = false
    }

    private fun reset(session: OrganizationSession?, id: String?, visible: Boolean) {
        val previous = mutable.value
        val sameOwner =
            session != null && session.uid == previous.session?.uid && id == previous.organizationId
        epoch++
        stopRead()
        processing?.cancel()
        processing = null
        picker?.lease?.cancel()
        picker = null
        if (!sameOwner) uploadIntent = null
        mutable.value =
            GalleryState(
                session,
                id,
                visible,
                busy = operation?.isActive == true,
                prepared = previous.prepared.takeIf { sameOwner },
                caption = previous.caption.takeIf { sameOwner }.orEmpty(),
            )
    }

    fun show(id: String) {
        if (mutable.value.organizationId != id || mutable.value.session != currentSession())
            reset(currentSession(), id, true)
        else if (mutable.value.visible) return
        else mutable.value = mutable.value.copy(visible = true)
        refresh()
    }

    fun hide() {
        stopRead()
        mutable.value =
            mutable.value.copy(
                visible = false,
                fresh = false,
                loading = false,
                confirmation = null,
                preview = null,
                previewPhoto = null,
            )
        // Photo Picker survives normal activity recreation; only identity/target change or clear
        // cancels its lease.
    }

    private fun current(session: OrganizationSession, id: String, version: Long) =
        currentSession() == session &&
            mutable.value.session == session &&
            mutable.value.organizationId == id &&
            epoch == version

    private fun unavailable(error: Throwable) {
        stopRead()
        mutable.value =
            mutable.value.copy(
                snapshot = null,
                fresh = false,
                loading = false,
                confirmation = null,
                preview = null,
                previewPhoto = null,
                error = galleryFailure(error),
            )
    }

    fun visibilityChanged() {
        if (!mutable.value.visible) return
        mutable.value =
            mutable.value.copy(
                fresh = false,
                preview = null,
                previewPhoto = null,
                confirmation = null,
            )
        refresh()
    }

    fun visible(snapshot: GallerySnapshot) = visibleOrganization(snapshot.content)

    fun refresh() {
        val value = mutable.value
        val session = value.session ?: return
        val id = value.organizationId ?: return
        if (
            !value.visible ||
                !session.ready ||
                currentSession() != session ||
                !OrganizationContract.id(id)
        )
            return
        if (operation?.isActive == true) {
            dirty = true
            return
        }
        if (read?.isActive == true) {
            dirty = true
            mutable.value =
                value.copy(fresh = false, loading = true, preview = null, previewPhoto = null)
            return
        }
        val version = epoch
        mutable.value =
            value.copy(
                fresh = false,
                loading = true,
                error = null,
                confirmation = null,
                preview = null,
                previewPhoto = null,
            )
        read = viewModelScope.launch {
            try {
                var repeats = 0
                while (true) {
                    dirty = false
                    val snapshot = repository.load(id)
                    val pending = repository.pending(id)
                    if (!current(session, id, version) || !mutable.value.visible) return@launch
                    if (dirty) {
                        if (++repeats > 2) GalleryContract.fail(GalleryFailure.STALE)
                        continue
                    }
                    mutable.value =
                        mutable.value.copy(
                            snapshot = snapshot,
                            fresh = true,
                            loading = false,
                            pending = pending,
                        )
                    observe(id, session)
                    break
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (current(session, id, version)) unavailable(error)
            } finally {
                if (epoch == version) read = null
            }
        }
    }

    private fun observe(id: String, session: OrganizationSession) {
        val target = session to id
        if (watch?.isActive == true && watchTarget == target) return
        watch?.cancel()
        watchTarget = target
        val version = epoch
        watch = viewModelScope.launch {
            try {
                repository.changes(id, session).collect { result ->
                    if (current(session, id, version) && mutable.value.visible) {
                        mutable.value =
                            mutable.value.copy(
                                fresh = false,
                                confirmation = null,
                                preview = null,
                                previewPhoto = null,
                            )
                        if (result.isSuccess) refresh()
                        else
                            unavailable(
                                result.exceptionOrNull() ?: GalleryException(GalleryFailure.UNKNOWN)
                            )
                    }
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (current(session, id, version)) unavailable(error)
            }
        }
    }

    fun caption(value: String) {
        if (
            !mutable.value.locked &&
                mutable.value.session == currentSession() &&
                mutable.value.pending.isEmpty()
        ) {
            uploadIntent = null
            mutable.value =
                mutable.value.copy(
                    caption = value.take(501),
                    confirmation = null,
                    confirmed = false,
                )
        }
    }

    fun beginPicker(): Boolean {
        val state = mutable.value
        val session = state.session ?: return false
        val id = state.organizationId ?: return false
        if (!state.canChoose || currentSession() != session || operation?.isActive == true)
            return false
        val lease =
            pickerAuthorization.begin(session.uid, session.revision)
                ?: run {
                    mutable.value = state.copy(error = GalleryFailure.NOT_READY)
                    return false
                }
        picker = Picker(session, id, lease)
        mutable.value = state.copy(pickerOpen = true, confirmation = null, error = null)
        return true
    }

    fun pickerUnavailable() {
        picker?.lease?.cancel()
        picker = null
        mutable.value = mutable.value.copy(pickerOpen = false, error = GalleryFailure.UNREADABLE)
    }

    fun pickerResult(uri: String?) {
        val selected = picker ?: return
        picker = null
        selected.lease.finish()
        if (!current(selected.session, selected.organizationId, epoch)) return
        mutable.value = mutable.value.copy(pickerOpen = false)
        if (uri == null) return
        val version = epoch
        uploadIntent = null
        mutable.value =
            mutable.value.copy(
                preparing = true,
                prepared = null,
                confirmation = null,
                confirmed = false,
                error = null,
            )
        processing = viewModelScope.launch {
            try {
                val prepared = preparation.prepare(uri)
                if (current(selected.session, selected.organizationId, version))
                    mutable.value = mutable.value.copy(prepared = prepared, preparing = false)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (current(selected.session, selected.organizationId, version))
                    mutable.value =
                        mutable.value.copy(preparing = false, error = galleryFailure(error))
            }
        }
    }

    fun discard() {
        val state = mutable.value
        if (state.locked || state.pending.isNotEmpty()) return
        uploadIntent = null
        mutable.value =
            state.copy(prepared = null, caption = "", confirmation = null, confirmed = false)
    }

    fun requestUpload() {
        val state = mutable.value
        if (!state.canUpload || state.session != currentSession()) return
        val intent =
            uploadIntent
                ?: GalleryUploadIntent.create(
                        requireNotNull(state.organizationId),
                        state.caption,
                        requireNotNull(state.prepared),
                    )
                    .also { uploadIntent = it }
        mutable.value = state.copy(confirmation = GalleryConfirmation.Upload(intent), error = null)
    }

    fun requestRemove(photo: GalleryPhoto) {
        val state = mutable.value
        if (
            !state.actionable ||
                state.pending.isNotEmpty() ||
                state.session != currentSession() ||
                photo !in state.snapshot!!.photos
        )
            return
        mutable.value = state.copy(confirmation = GalleryConfirmation.Remove(photo), error = null)
    }

    fun requestCleanup(entry: GalleryJournalEntry) {
        val state = mutable.value
        if (
            !state.actionable ||
                state.recovery != GalleryRecovery.CLEANUP_AVAILABLE ||
                state.recoveryFor != entry ||
                entry !in state.pending
        )
            return
        mutable.value = state.copy(confirmation = GalleryConfirmation.Cleanup(entry), error = null)
    }

    fun dismissConfirmation() {
        if (!mutable.value.busy) mutable.value = mutable.value.copy(confirmation = null)
    }

    fun confirm() {
        val action = mutable.value.confirmation ?: return
        perform(clearDraftOnSuccess = action is GalleryConfirmation.Upload) {
            when (action) {
                is GalleryConfirmation.Upload -> repository.upload(action.intent)
                is GalleryConfirmation.Remove -> repository.remove(action.photo)
                is GalleryConfirmation.Cleanup -> repository.cleanup(action.entry)
            }.also { result ->
                if (action is GalleryConfirmation.Upload && result.pending == null)
                    uploadIntent = null
            }
        }
    }

    private fun perform(
        clearDraftOnSuccess: Boolean = false,
        action: suspend () -> GalleryMutationResult,
    ) {
        val value = mutable.value
        val session = value.session ?: return
        val id = value.organizationId ?: return
        val version = epoch
        if (!value.actionable || currentSession() != session || operation?.isActive == true) return
        mutable.value =
            value.copy(
                busy = true,
                confirmation = null,
                confirmed = false,
                error = null,
                preview = null,
                previewPhoto = null,
            )
        operation = viewModelScope.launch {
            try {
                val result = action()
                if (current(session, id, version)) {
                    val pending = repository.pending(id)
                    if (current(session, id, version))
                        mutable.value =
                            mutable.value.copy(
                                snapshot = result.snapshot,
                                fresh = true,
                                pending = pending,
                                confirmed = result.pending == null,
                                error =
                                    if (result.pending == null) null
                                    else GalleryFailure.CLEANUP_PENDING,
                                prepared =
                                    if (clearDraftOnSuccess && result.pending == null) null
                                    else mutable.value.prepared,
                                caption =
                                    if (clearDraftOnSuccess && result.pending == null) ""
                                    else mutable.value.caption,
                                recovery = null,
                                recoveryFor = null,
                            )
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (current(session, id, version)) {
                    val pending =
                        try {
                            journal.pending(session.uid).filter { it.target.organizationId == id }
                        } catch (_: Exception) {
                            mutable.value.pending
                        }
                    if (current(session, id, version))
                        mutable.value =
                            mutable.value.copy(
                                error = galleryFailure(error),
                                pending = pending,
                                fresh = false,
                            )
                }
            } finally {
                operation = null
                mutable.value = mutable.value.copy(busy = false)
                if (mutable.value.visible && (dirty || !current(session, id, version))) {
                    dirty = false
                    refresh()
                }
            }
        }
    }

    fun reconcile(entry: GalleryJournalEntry) {
        val value = mutable.value
        val session = value.session ?: return
        val id = value.organizationId ?: return
        val version = epoch
        if (
            !value.visible ||
                !session.ready ||
                currentSession() != session ||
                value.locked ||
                operation?.isActive == true ||
                entry !in value.pending
        )
            return
        mutable.value =
            value.copy(
                busy = true,
                confirmation = null,
                error = null,
                recovery = null,
                recoveryFor = null,
            )
        operation = viewModelScope.launch {
            try {
                val result = repository.reconcile(entry)
                if (current(session, id, version)) {
                    val confirmedUpload =
                        result.status == GalleryRecovery.PUBLISHED &&
                            uploadIntent?.target == entry.target
                    if (confirmedUpload) uploadIntent = null
                    mutable.value =
                        mutable.value.copy(
                            snapshot = result.snapshot,
                            fresh = true,
                            pending =
                                value.pending.filterNot { it.target == entry.target } +
                                    listOfNotNull(result.pending),
                            recovery = result.status,
                            recoveryFor = result.pending,
                            confirmed =
                                result.status in
                                    setOf(GalleryRecovery.PUBLISHED, GalleryRecovery.REMOVED),
                            prepared = if (confirmedUpload) null else mutable.value.prepared,
                            caption = if (confirmedUpload) "" else mutable.value.caption,
                        )
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (current(session, id, version))
                    mutable.value = mutable.value.copy(error = galleryFailure(error), fresh = false)
            } finally {
                operation = null
                mutable.value = mutable.value.copy(busy = false)
                if (dirty && mutable.value.visible) {
                    dirty = false
                    refresh()
                }
            }
        }
    }

    fun preview(photo: GalleryPhoto) {
        val value = mutable.value
        val session = value.session ?: return
        val id = value.organizationId ?: return
        val version = epoch
        if (!value.readable || currentSession() != session || photo !in value.snapshot!!.photos)
            return
        previewRead?.cancel()
        mutable.value = value.copy(preview = null, previewPhoto = photo)
        previewRead = viewModelScope.launch {
            try {
                val image = repository.image(photo)
                if (
                    current(session, id, version) &&
                        mutable.value.visible &&
                        mutable.value.fresh &&
                        mutable.value.previewPhoto == photo
                )
                    mutable.value = mutable.value.copy(preview = image)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (current(session, id, version))
                    mutable.value =
                        mutable.value.copy(
                            preview = null,
                            previewPhoto = null,
                            error = galleryFailure(error),
                        )
            }
        }
    }

    fun dismissPreview() {
        previewRead?.cancel()
        previewRead = null
        mutable.value = mutable.value.copy(preview = null, previewPhoto = null)
    }

    override fun onCleared() {
        epoch++
        stopRead()
        observer?.cancel()
        processing?.cancel()
        picker?.lease?.cancel()
        picker = null
        uploadIntent = null
        mutable.value = GalleryState()
        super.onCleared()
    }
}
