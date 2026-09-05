package at.uac.android.feature.contentmedia

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import at.uac.android.core.DeniedExternalImagePickerAuthorization
import at.uac.android.core.ExternalImagePickerAuthorization
import at.uac.android.core.ExternalImagePickerLease
import at.uac.android.feature.organization.OrganizationMutationGate
import at.uac.android.feature.organization.OrganizationSession
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class ContentCoverState(
    val session: OrganizationSession? = null,
    val target: ContentCoverTarget? = null,
    val visible: Boolean = false,
    val snapshot: ContentCoverSnapshot? = null,
    val asset: ContentCoverAsset? = null,
    val fresh: Boolean = false,
    val loading: Boolean = false,
    val busy: Boolean = false,
    val preparing: Boolean = false,
    val pickerOpen: Boolean = false,
    val prepared: PreparedContentCover? = null,
    val preparedFor: ContentCoverSnapshot? = null,
    val confirmation: ContentCoverIntent? = null,
    val uncertain: ContentCoverIntent? = null,
    val recoveryChecked: Boolean = false,
    val confirmed: Boolean = false,
    val error: ContentCoverFailure? = null,
    val imageError: ContentCoverFailure? = null,
    val diagnostic: ContentCoverDiagnostic? = null,
) {
    val locked
        get() = busy || preparing || pickerOpen

    val actionable
        get() =
            visible &&
                session?.ready == true &&
                fresh &&
                !loading &&
                !locked &&
                snapshot?.editable == true

    val canChoose
        get() = actionable && uncertain == null && confirmation == null

    val canUpload
        get() =
            canChoose &&
                prepared != null &&
                preparedFor?.item?.fields == snapshot?.item?.fields &&
                preparedFor?.organization?.fields == snapshot?.organization?.fields

    val canRemove
        get() = canChoose && prepared == null && snapshot?.removable == true
}

class ContentCoverViewModel(
    source: ContentCoverSource,
    private val preparation: ContentCoverPreparation,
    private val currentSession: () -> OrganizationSession?,
    gate: OrganizationMutationGate,
    private val pickerAuthorization: ExternalImagePickerAuthorization =
        DeniedExternalImagePickerAuthorization,
) : ViewModel() {
    private val repository = ContentCoverRepository(source, currentSession, gate)
    private val mutable = MutableStateFlow(ContentCoverState(session = currentSession()))
    val state = mutable.asStateFlow()
    private var epoch = 0L
    private var readVersion = 0L
    private var read: Job? = null
    private var watch: Job? = null
    private var sessions: Job? = null
    private var processing: Job? = null
    private var watchedStatus: String? = null
    private var refreshPending = false
    private var inFlight: ContentCoverIntent? = null

    private data class Picker(
        val session: OrganizationSession,
        val snapshot: ContentCoverSnapshot,
        val lease: ExternalImagePickerLease,
    )

    private var pendingPicker: Picker? = null

    private fun same(session: OrganizationSession?, version: Long) =
        epoch == version && currentSession() == session && mutable.value.session == session

    private fun sameRead(session: OrganizationSession?, version: Long, ticket: Long) =
        same(session, version) && readVersion == ticket

    private fun cancelRead() {
        readVersion++
        read?.cancel()
        read = null
    }

    private fun cancelWatch() {
        watch?.cancel()
        watch = null
        watchedStatus = null
    }

    private fun reset(
        session: OrganizationSession?,
        target: ContentCoverTarget?,
        visible: Boolean,
    ) {
        val old = mutable.value
        val sameOwner = session != null && old.session?.uid == session.uid && old.target == target
        epoch++
        cancelRead()
        cancelWatch()
        processing?.cancel()
        refreshPending = false
        pendingPicker?.lease?.cancel()
        pendingPicker = null
        mutable.value =
            if (sameOwner)
                ContentCoverState(
                    session,
                    target,
                    visible,
                    prepared = old.prepared,
                    preparedFor = old.preparedFor,
                    uncertain = old.uncertain ?: inFlight.takeIf { old.busy },
                )
            else ContentCoverState(session, target, visible)
    }

    fun observeSessions(flow: Flow<OrganizationSession?>) {
        sessions?.cancel()
        sessions = viewModelScope.launch {
            flow.collect { session ->
                if (session != mutable.value.session) {
                    reset(session, mutable.value.target, mutable.value.visible)
                    if (mutable.value.visible) refresh()
                }
            }
        }
    }

    fun show(target: ContentCoverTarget) {
        if (mutable.value.target != target || mutable.value.session != currentSession())
            reset(currentSession(), target, true)
        else if (mutable.value.visible) return
        else mutable.value = mutable.value.copy(visible = true)
        refresh()
    }

    fun hide() {
        cancelWatch()
        cancelRead()
        refreshPending = false
        // The external picker lease lives in this ViewModel, not in the disposed Compose screen.
        mutable.value =
            mutable.value.copy(visible = false, fresh = false, loading = false, confirmation = null)
    }

    private fun watch(snapshot: ContentCoverSnapshot, session: OrganizationSession) {
        if (watch?.isActive == true && watchedStatus == snapshot.item.status.wire) return
        cancelWatch()
        watchedStatus = snapshot.item.status.wire
        val version = epoch
        watch = viewModelScope.launch {
            try {
                repository.changes(snapshot, session).collect { result ->
                    if (same(session, version)) {
                        if (result.isSuccess) {
                            if (read?.isActive == true || mutable.value.busy) refreshPending = true
                            else load(clearError = false)
                        } else {
                            cancelRead()
                            cancelWatch()
                            refreshPending = false
                            mutable.value =
                                mutable.value.copy(
                                    fresh = false,
                                    loading = false,
                                    confirmation = null,
                                    asset = null,
                                    error =
                                        result.exceptionOrNull()?.let(::contentCoverFailure)
                                            ?: ContentCoverFailure.UNKNOWN,
                                )
                        }
                    }
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (same(session, version)) {
                    cancelRead()
                    cancelWatch()
                    refreshPending = false
                    mutable.value =
                        mutable.value.copy(
                            fresh = false,
                            loading = false,
                            asset = null,
                            confirmation = null,
                            error = contentCoverFailure(error),
                        )
                }
            }
        }
    }

    fun refresh() = load(clearError = true)

    private fun load(clearError: Boolean) {
        val captured = mutable.value
        val target = captured.target ?: return
        val session = captured.session ?: return
        if (
            !captured.visible ||
                !session.ready ||
                session != currentSession() ||
                captured.busy ||
                read?.isActive == true
        )
            return
        val version = epoch
        val ticket = ++readVersion
        mutable.value =
            captured.copy(
                loading = true,
                fresh = false,
                confirmation = null,
                error = if (clearError) null else captured.error,
            )
        read = viewModelScope.launch {
            try {
                val snapshot = repository.load(target)
                var imageError: ContentCoverFailure? = null
                val image =
                    try {
                        repository.image(snapshot)
                    } catch (error: CancellationException) {
                        throw error
                    } catch (error: Exception) {
                        imageError = contentCoverFailure(error)
                        null
                    }
                if (sameRead(session, version, ticket)) {
                    mutable.value =
                        mutable.value.copy(
                            snapshot = snapshot,
                            asset = image,
                            imageError = imageError,
                            fresh = true,
                            loading = false,
                            confirmed =
                                mutable.value.confirmed &&
                                    mutable.value.snapshot?.imageUrl == snapshot.imageUrl,
                        )
                    watch(snapshot, session)
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (sameRead(session, version, ticket)) {
                    cancelWatch()
                    mutable.value =
                        mutable.value.copy(
                            fresh = false,
                            loading = false,
                            asset = null,
                            error = contentCoverFailure(error),
                        )
                }
            } finally {
                if (sameRead(session, version, ticket)) {
                    read = null
                    if (refreshPending && mutable.value.visible && !mutable.value.busy) {
                        refreshPending = false
                        load(clearError = false)
                    }
                }
            }
        }
    }

    fun beginPicker(): Boolean {
        val value = mutable.value
        val session = value.session ?: return false
        val snapshot = value.snapshot ?: return false
        if (!value.canChoose || session != currentSession()) return false
        val lease =
            pickerAuthorization.begin(session.uid, session.revision)
                ?: run {
                    mutable.value = value.copy(error = ContentCoverFailure.NOT_READY)
                    return false
                }
        pendingPicker = Picker(session, snapshot, lease)
        mutable.value = value.copy(pickerOpen = true, confirmation = null, error = null)
        return true
    }

    fun pickerUnavailable() {
        pendingPicker?.lease?.cancel()
        pendingPicker = null
        mutable.value =
            mutable.value.copy(pickerOpen = false, error = ContentCoverFailure.UNREADABLE)
    }

    fun pickerResult(contentUri: String?) {
        val picker = pendingPicker ?: return
        pendingPicker = null
        picker.lease.finish()
        if (
            picker.session != currentSession() ||
                picker.session != mutable.value.session ||
                picker.snapshot.target != mutable.value.target
        )
            return
        mutable.value = mutable.value.copy(pickerOpen = false)
        if (contentUri == null) return
        val version = epoch
        mutable.value =
            mutable.value.copy(
                preparing = true,
                prepared = null,
                preparedFor = null,
                confirmed = false,
                error = null,
            )
        processing = viewModelScope.launch {
            try {
                val photo = preparation.prepare(contentUri)
                if (same(picker.session, version))
                    mutable.value =
                        mutable.value.copy(
                            prepared = photo,
                            preparedFor = picker.snapshot,
                            preparing = false,
                        )
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (same(picker.session, version))
                    mutable.value =
                        mutable.value.copy(preparing = false, error = contentCoverFailure(error))
            }
        }
    }

    fun discardSelection() {
        val value = mutable.value
        if (value.locked || value.uncertain != null) return
        mutable.value =
            value.copy(
                prepared = null,
                preparedFor = null,
                confirmation = null,
                confirmed = false,
                error = null,
            )
    }

    fun requestUpload() {
        val value = mutable.value
        if (!value.canUpload || value.session != currentSession()) return
        mutable.value =
            value.copy(
                confirmation =
                    ContentCoverIntent.Upload(
                        requireNotNull(value.preparedFor),
                        requireNotNull(value.prepared),
                    ),
                error = null,
            )
    }

    fun requestRemove() {
        val value = mutable.value
        if (!value.canRemove || value.session != currentSession()) return
        mutable.value =
            value.copy(
                confirmation = ContentCoverIntent.Remove(requireNotNull(value.snapshot)),
                error = null,
            )
    }

    fun dismissConfirmation() {
        if (!mutable.value.busy) mutable.value = mutable.value.copy(confirmation = null)
    }

    fun confirm() {
        val value = mutable.value
        val intent = value.confirmation ?: return
        val session = value.session ?: return
        val snapshot = value.snapshot ?: return
        if (
            !value.actionable ||
                session != currentSession() ||
                snapshot.item.fields != intent.snapshot.item.fields ||
                snapshot.organization.fields != intent.snapshot.organization.fields
        )
            return
        val version = epoch
        inFlight = intent
        mutable.value =
            value.copy(
                busy = true,
                confirmation = null,
                error = null,
                confirmed = false,
                recoveryChecked = false,
                diagnostic = null,
            )
        viewModelScope.launch {
            try {
                val result = repository.execute(intent)
                if (same(session, version)) confirmed(result)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (same(session, version)) {
                    val reason = contentCoverFailure(error)
                    mutable.value =
                        mutable.value.copy(
                            busy = false,
                            fresh = false,
                            error = reason,
                            diagnostic = contentCoverDiagnostic(ContentCoverStage.MUTATION, error),
                            uncertain =
                                intent.takeIf {
                                    reason in
                                        setOf(
                                            ContentCoverFailure.UNCONFIRMED,
                                            ContentCoverFailure.UNKNOWN,
                                        )
                                },
                        )
                }
            } finally {
                if (inFlight === intent) inFlight = null
                if (same(session, version)) {
                    mutable.value = mutable.value.copy(busy = false)
                    refreshPending = false
                    load(clearError = false)
                }
            }
        }
    }

    private fun confirmed(result: ContentCoverConfirmation) {
        mutable.value =
            mutable.value.copy(
                snapshot = result.snapshot,
                asset = result.asset,
                prepared = null,
                preparedFor = null,
                uncertain = null,
                confirmation = null,
                busy = false,
                fresh = false,
                confirmed = true,
                recoveryChecked = false,
                error = null,
                imageError = null,
                diagnostic = null,
            )
    }

    fun recover() {
        val value = mutable.value
        val intent = value.uncertain ?: return
        val session = value.session ?: return
        if (
            !value.visible ||
                !session.ready ||
                session != currentSession() ||
                value.loading ||
                value.locked
        )
            return
        val version = epoch
        mutable.value =
            value.copy(busy = true, confirmation = null, error = null, recoveryChecked = false)
        viewModelScope.launch {
            try {
                val result = repository.recover(intent)
                if (same(session, version)) {
                    if (result.confirmed != null) confirmed(result.confirmed)
                    else
                        mutable.value =
                            mutable.value.copy(
                                snapshot = result.current,
                                busy = false,
                                recoveryChecked = true,
                                fresh = false,
                            )
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (same(session, version))
                    mutable.value =
                        mutable.value.copy(busy = false, error = contentCoverFailure(error))
            } finally {
                if (same(session, version)) {
                    mutable.value = mutable.value.copy(busy = false)
                    refreshPending = false
                    load(clearError = false)
                }
            }
        }
    }

    override fun onCleared() {
        pendingPicker?.lease?.cancel()
        sessions?.cancel()
        cancelRead()
        cancelWatch()
        processing?.cancel()
    }
}
