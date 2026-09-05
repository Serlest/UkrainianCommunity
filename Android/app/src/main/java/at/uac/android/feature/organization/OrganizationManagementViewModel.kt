package at.uac.android.feature.organization

import android.content.Context
import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import at.uac.android.core.DeniedExternalImagePickerAuthorization
import at.uac.android.core.ExternalImagePickerAuthorization
import at.uac.android.core.ExternalImagePickerLease
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class OrganizationManagementState(
    val session: OrganizationSession? = null,
    val organizationId: String? = null,
    val visible: Boolean = false,
    val snapshot: OrganizationManagementSnapshot? = null,
    val fresh: Boolean = false,
    val loading: Boolean = false,
    val busy: Boolean = false,
    val error: OrganizationManagementFailure? = null,
    val base: OrganizationRecord? = null,
    val draft: OrganizationInformationDraft? = null,
    val confirmation: OrganizationRoleIntent? = null,
    val uncertain: OrganizationRoleIntent? = null,
    val confirmed: Boolean = false,
    val logoIncomplete: Boolean = false,
    val pickerOpen: Boolean = false,
    val imageLoading: Boolean = false,
    val logoPreview: OrganizationLogoSelection? = null,
) {
    val actionable: Boolean
        get() =
            fresh && !loading && !busy && !pickerOpen && session?.ready == true && snapshot != null

    val editable: Boolean
        get() =
            actionable &&
                session != null &&
                snapshot?.organization?.let {
                    OrganizationManagementContract.canEdit(it, session)
                } == true

    val draftWritable: Boolean
        get() = editable && base != null && snapshot?.organization?.fields == base.fields
}

class OrganizationManagementViewModel(
    source: OrganizationManagementSource,
    private val currentSession: () -> OrganizationSession?,
    gate: OrganizationMutationGate,
    private val pickerAuthorization: ExternalImagePickerAuthorization =
        DeniedExternalImagePickerAuthorization,
) : ViewModel() {
    private val repository = OrganizationManagementRepository(source, currentSession, gate)
    private val mutable = MutableStateFlow(OrganizationManagementState(session = currentSession()))
    val state: StateFlow<OrganizationManagementState> = mutable.asStateFlow()
    private var generation = 0L
    private var sessions: Job? = null
    private var watch: Job? = null
    private var read: Job? = null
    private var mutation: Job? = null
    private var image: Job? = null

    private data class Picker(
        val session: OrganizationSession,
        val id: String,
        val lease: ExternalImagePickerLease,
    )

    private var picker: Picker? = null

    private fun cancelPicker() {
        picker?.lease?.cancel()
        picker = null
    }

    private fun same(session: OrganizationSession?, epoch: Long) =
        epoch == generation && session == currentSession() && session == mutable.value.session

    private fun reset(session: OrganizationSession?, id: String?, visible: Boolean) {
        generation++
        watch?.cancel()
        read?.cancel()
        image?.cancel()
        cancelPicker()
        mutable.value =
            OrganizationManagementState(session = session, organizationId = id, visible = visible)
    }

    fun observeSessions(values: Flow<OrganizationSession?>) {
        sessions?.cancel()
        sessions = viewModelScope.launch {
            values.collect { value ->
                if (value != mutable.value.session) {
                    reset(value, mutable.value.organizationId, mutable.value.visible)
                    if (mutable.value.visible) start()
                }
            }
        }
    }

    fun show(id: String) {
        if (
            mutable.value.visible &&
                mutable.value.session == currentSession() &&
                mutable.value.organizationId == id
        )
            return
        if (mutable.value.session != currentSession() || mutable.value.organizationId != id)
            reset(currentSession(), id, true)
        else mutable.value = mutable.value.copy(visible = true)
        start()
    }

    fun hide() {
        mutable.value = mutable.value.copy(visible = false)
        watch?.cancel()
        read?.cancel()
    }

    private fun start() {
        watch?.cancel()
        val captured = mutable.value
        val session = captured.session ?: return
        val id = captured.organizationId ?: return
        if (!session.ready) return
        if (!OrganizationContract.id(id)) {
            mutable.value = captured.copy(error = OrganizationManagementFailure.INVALID)
            return
        }
        val epoch = generation
        watch = viewModelScope.launch {
            repository.changes(id, session).collect { result ->
                if (same(session, epoch)) {
                    if (result.isSuccess) refresh()
                    else
                        mutable.value =
                            mutable.value.copy(
                                fresh = false,
                                confirmation = null,
                                error =
                                    result.exceptionOrNull()?.let(::organizationManagementFailure)
                                        ?: OrganizationManagementFailure.UNKNOWN,
                            )
                }
            }
        }
        refresh()
    }

    fun refresh() = load(more = false)

    fun more() = load(more = true)

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
        if (more && (!captured.fresh || captured.snapshot?.next == null)) return
        val epoch = generation
        mutable.value =
            captured.copy(
                loading = true,
                fresh = false,
                confirmation = null,
                error = if (preserveError) captured.error else null,
            )
        read = viewModelScope.launch {
            try {
                val loaded = repository.load(id, if (more) captured.snapshot else null)
                if (same(session, epoch)) {
                    val uncertain = mutable.value.uncertain
                    val recovered =
                        uncertain != null &&
                            OrganizationManagementContract.role(
                                loaded.organization,
                                uncertain.targetId,
                            ) == OrganizationManagementContract.desired(uncertain)
                    mutable.value =
                        mutable.value.copy(
                            snapshot = loaded,
                            fresh = true,
                            loading = false,
                            uncertain = uncertain.takeUnless { recovered },
                            confirmed = mutable.value.confirmed || recovered,
                            error = if (recovered) null else mutable.value.error,
                        )
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (same(session, epoch))
                    mutable.value =
                        mutable.value.copy(
                            fresh = false,
                            loading = false,
                            confirmation = null,
                            error = organizationManagementFailure(error),
                        )
            }
        }
    }

    fun edit() {
        val captured = mutable.value
        if (captured.session != currentSession() || !captured.editable) return
        val record = captured.snapshot?.organization ?: return
        cancelPicker()
        image?.cancel()
        mutable.value =
            captured.copy(
                base = record,
                draft = OrganizationManagementContract.draft(record),
                error = null,
                confirmed = false,
                logoPreview = null,
                logoIncomplete = false,
                pickerOpen = false,
                imageLoading = false,
                confirmation = null,
            )
    }

    fun change(transform: (OrganizationInformationDraft) -> OrganizationInformationDraft) {
        val captured = mutable.value
        val draft = captured.draft ?: return
        if (!captured.draftWritable || captured.session != currentSession()) return
        val changed = transform(draft)
        if (changed.basics.id != draft.basics.id) return
        mutable.value = captured.copy(draft = changed, error = null, confirmed = false)
    }

    fun closeEditor() {
        if (mutable.value.busy) return
        cancelPicker()
        image?.cancel()
        mutable.value =
            mutable.value.copy(
                base = null,
                draft = null,
                logoPreview = null,
                pickerOpen = false,
                imageLoading = false,
                logoIncomplete = false,
            )
    }

    fun beginPicker(): Boolean {
        val captured = mutable.value
        val session = captured.session ?: return false
        val id = captured.organizationId ?: return false
        if (
            !captured.draftWritable ||
                captured.imageLoading ||
                picker != null ||
                session != currentSession()
        )
            return false
        val lease =
            pickerAuthorization.begin(session.uid, session.revision)
                ?: run {
                    mutable.value = captured.copy(error = OrganizationManagementFailure.NOT_READY)
                    return false
                }
        picker = Picker(session, id, lease)
        mutable.value = captured.copy(pickerOpen = true, error = null)
        return true
    }

    fun pickerResult(context: Context, uri: Uri?) {
        val pending = picker ?: return
        picker = null
        pending.lease.finish()
        if (
            pending.session != currentSession() ||
                mutable.value.session != pending.session ||
                mutable.value.organizationId != pending.id
        )
            return
        mutable.value = mutable.value.copy(pickerOpen = false)
        val captured = mutable.value
        if (
            uri == null ||
                captured.draft == null ||
                captured.busy ||
                captured.session?.ready != true ||
                captured.snapshot?.organization?.fields != captured.base?.fields
        )
            return
        val epoch = generation
        image?.cancel()
        mutable.value = captured.copy(imageLoading = true)
        image = viewModelScope.launch {
            try {
                val bytes = OrganizationLogo.prepare(context.applicationContext, uri)
                if (same(pending.session, epoch) && mutable.value.draft?.basics?.id == pending.id)
                    mutable.value =
                        mutable.value.copy(
                            logoPreview = OrganizationLogoSelection(bytes),
                            imageLoading = false,
                        )
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                if (same(pending.session, epoch))
                    mutable.value =
                        mutable.value.copy(
                            imageLoading = false,
                            error = OrganizationManagementFailure.INVALID,
                        )
            }
        }
    }

    fun pickerUnavailable() {
        cancelPicker()
        mutable.value =
            mutable.value.copy(pickerOpen = false, error = OrganizationManagementFailure.INVALID)
    }

    fun removeLogo() {
        if (!mutable.value.busy) {
            image?.cancel()
            mutable.value = mutable.value.copy(logoPreview = null, imageLoading = false)
        }
    }

    fun save() {
        val captured = mutable.value
        val base = captured.base ?: return
        val draft = captured.draft ?: return
        if (!captured.draftWritable || captured.imageLoading) return
        mutate({ repository.save(base, draft, captured.logoPreview?.copyBytes()) }) { result ->
            mutable.value =
                mutable.value.copy(
                    base = result.organization,
                    confirmed = true,
                    logoIncomplete = result.logoIncomplete,
                    logoPreview = if (result.logoIncomplete) mutable.value.logoPreview else null,
                )
        }
    }

    fun choose(memberId: String, action: OrganizationTeamAction) {
        val captured = mutable.value
        val session = captured.session ?: return
        val snapshot = captured.snapshot ?: return
        if (!captured.actionable || captured.uncertain != null || session != currentSession())
            return
        val member = snapshot.members.firstOrNull { it.profile.id == memberId } ?: return
        val intent = OrganizationRoleIntent(memberId, action, member.role)
        if (
            runCatching {
                OrganizationManagementContract.requireIntent(
                    snapshot.organization,
                    intent,
                    session,
                )
            }
                .isFailure ||
                OrganizationManagementContract.desired(intent) == member.role ||
                (action != OrganizationTeamAction.REMOVE && member.profile.displayName == null)
        )
            return
        mutable.value = captured.copy(confirmation = intent, error = null, confirmed = false)
    }

    fun dismissConfirmation() {
        if (!mutable.value.busy) mutable.value = mutable.value.copy(confirmation = null)
    }

    fun confirm() {
        val captured = mutable.value
        val intent = captured.confirmation ?: return
        val record = captured.snapshot?.organization ?: return
        if (!captured.actionable || captured.uncertain != null) return
        mutable.value = captured.copy(confirmation = null)
        mutate(
            { repository.apply(record, intent) },
            onFailure = { failure ->
                if (
                    failure in
                        setOf(
                            OrganizationManagementFailure.UNCONFIRMED,
                            OrganizationManagementFailure.UNKNOWN,
                        )
                )
                    mutable.value = mutable.value.copy(uncertain = intent)
            },
        ) {
            mutable.value = mutable.value.copy(confirmed = true)
        }
    }

    /**
     * Only after a new server read may the user explicitly make a fresh decision. Never resends the
     * old intent.
     */
    fun acknowledgeUncertain() {
        val captured = mutable.value
        if (captured.actionable && captured.session == currentSession())
            mutable.value = captured.copy(uncertain = null, confirmation = null, confirmed = false)
    }

    private fun <T> mutate(
        operation: suspend () -> T,
        onFailure: (OrganizationManagementFailure) -> Unit = {},
        apply: (T) -> Unit,
    ) {
        val captured = mutable.value
        if (
            !captured.visible ||
                !captured.actionable ||
                captured.session != currentSession() ||
                mutation?.isActive == true
        )
            return
        val epoch = generation
        mutable.value = captured.copy(busy = true, error = null, confirmed = false)
        mutation = viewModelScope.launch {
            try {
                val result = operation()
                if (same(captured.session, epoch)) apply(result)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (same(captured.session, epoch)) {
                    val failure = organizationManagementFailure(error)
                    mutable.value = mutable.value.copy(error = failure)
                    onFailure(failure)
                }
            } finally {
                if (same(captured.session, epoch)) {
                    mutable.value = mutable.value.copy(busy = false)
                    load(more = false, preserveError = true)
                }
            }
        }
    }

    override fun onCleared() {
        cancelPicker()
        super.onCleared()
    }
}
