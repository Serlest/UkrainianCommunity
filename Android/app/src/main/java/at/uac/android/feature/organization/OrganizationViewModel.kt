package at.uac.android.feature.organization

import android.content.Context
import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import at.uac.android.core.DeniedExternalImagePickerAuthorization
import at.uac.android.core.ExternalImagePickerAuthorization
import at.uac.android.core.ExternalImagePickerLease
import at.uac.android.feature.auth.AuthLegalDocument
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class OrganizationState(
    val session: OrganizationSession? = null,
    val visible: Boolean = false,
    val hub: OrganizationHub? = null,
    val rules: AuthLegalDocument? = null,
    val loading: Boolean = false,
    val busy: Boolean = false,
    val imageLoading: Boolean = false,
    val error: OrganizationFailure? = null,
    val confirmedId: String? = null,
    val draft: OrganizationDraft? = null,
    val base: OrganizationRecord? = null,
    val logoSelected: Boolean = false,
    val logoIncomplete: Boolean = false,
    val editorFailure: OrganizationFailure? = null,
    val targetId: String? = null,
    val target: OrganizationRecord? = null,
    val targetFailure: OrganizationFailure? = null,
    val pickerOpen: Boolean = false,
    val logoPreview: OrganizationLogoSelection? = null,
) {
    val editorWritable: Boolean
        get() =
            session?.ready == true &&
                hub != null &&
                !loading &&
                editorFailure == null &&
                !pickerOpen
}

class OrganizationViewModel(
    source: OrganizationSource,
    private val currentSession: () -> OrganizationSession?,
    gate: OrganizationMutationGate,
    private val pickerAuthorization: ExternalImagePickerAuthorization =
        DeniedExternalImagePickerAuthorization,
) : ViewModel() {
    private val repository = OrganizationRepository(source, currentSession, gate)
    private val mutable = MutableStateFlow(OrganizationState(session = currentSession()))
    val state: StateFlow<OrganizationState> = mutable.asStateFlow()
    private var generation = 0L
    private var observer: Job? = null
    private var watch: Job? = null
    private var refresh: Job? = null
    private var mutation: Job? = null
    private var image: Job? = null
    private var logo: ByteArray? = null

    private data class Picker(
        val session: OrganizationSession,
        val draftId: String,
        val lease: ExternalImagePickerLease,
    )

    private var picker: Picker? = null

    private fun cancelPicker() {
        picker?.lease?.cancel()
        picker = null
    }

    fun observeSessions(sessions: Flow<OrganizationSession?>) {
        observer?.cancel()
        observer = viewModelScope.launch {
            sessions.collect { session ->
                if (session != mutable.value.session) {
                    generation++
                    watch?.cancel()
                    refresh?.cancel()
                    image?.cancel()
                    cancelPicker()
                    logo = null
                    mutable.value =
                        OrganizationState(
                            session,
                            visible = mutable.value.visible,
                            targetId = mutable.value.targetId,
                        )
                    if (mutable.value.visible) start()
                }
            }
        }
    }

    fun show(initialRequestId: String? = null) {
        if (
            mutable.value.visible &&
                mutable.value.session == currentSession() &&
                mutable.value.targetId == initialRequestId
        )
            return
        if (
            mutable.value.session != currentSession() || mutable.value.targetId != initialRequestId
        ) {
            generation++
            watch?.cancel()
            refresh?.cancel()
            image?.cancel()
            cancelPicker()
            logo = null
            mutable.value = OrganizationState(currentSession(), targetId = initialRequestId)
        }
        mutable.value = mutable.value.copy(visible = true)
        start()
    }

    fun hide() {
        mutable.value = mutable.value.copy(visible = false)
        watch?.cancel()
        refresh?.cancel()
    }

    private fun start() {
        watch?.cancel()
        val session = mutable.value.session ?: return
        if (!session.ready) return
        val epoch = generation
        watch = viewModelScope.launch {
            repository.changes(session, mutable.value.targetId).collect { result ->
                if (valid(session, epoch)) {
                    if (result.isSuccess) refresh()
                    else {
                        val failure =
                            result.exceptionOrNull()?.let(::organizationFailure)
                                ?: OrganizationFailure.UNKNOWN
                        mutable.value =
                            mutable.value.copy(
                                error = failure,
                                hub = null,
                                editorFailure = if (mutable.value.base != null) failure else null,
                                target = null,
                                targetFailure =
                                    if (mutable.value.targetId != null) failure else null,
                            )
                    }
                }
            }
        }
        refresh()
    }

    private fun valid(session: OrganizationSession?, epoch: Long) =
        generation == epoch && currentSession() == session && mutable.value.session == session

    fun refresh(preserveError: Boolean = false) {
        val session = mutable.value.session ?: return
        if (
            !mutable.value.visible ||
                !session.ready ||
                mutable.value.busy ||
                refresh?.isActive == true
        )
            return
        val epoch = generation
        val targetId = mutable.value.targetId
        mutable.value =
            mutable.value.copy(
                loading = true,
                error = if (preserveError) mutable.value.error else null,
            )
        refresh = viewModelScope.launch {
            try {
                var hub = repository.hub()
                var targetFailure: OrganizationFailure? = null
                val target =
                    if (targetId == null) null
                    else
                        try {
                            repository.request(targetId).also {
                                if (it == null) targetFailure = OrganizationFailure.MISSING
                            }
                        } catch (error: CancellationException) {
                            throw error
                        } catch (error: Exception) {
                            targetFailure = organizationFailure(error)
                            null
                        }
                if (targetId != null) {
                    // The later server-scoped target read wins over an earlier hub snapshot.
                    val withoutTarget = hub.requests.filterNot { it.id == targetId }
                    val ownTarget = target?.takeIf {
                        it.status in OrganizationContract.requestStatuses
                    }
                    val requests = listOfNotNull(ownTarget) + withoutTarget
                    hub =
                        hub.copy(
                            requests = requests.take(50),
                            truncated = hub.truncated || requests.size > 50,
                        )
                }
                // Existing requests remain available if only the new-create rules reader fails.
                val rules =
                    try {
                        repository.rules()
                    } catch (error: CancellationException) {
                        throw error
                    } catch (_: Exception) {
                        null
                    }
                if (valid(session, epoch)) {
                    val draft = mutable.value.draft
                    val base = mutable.value.base
                    val fresh = base?.let { previous ->
                        hub.requests.firstOrNull { it.id == previous.id }
                    }
                    val editorFailure =
                        when {
                            base == null -> null
                            fresh == null -> OrganizationFailure.MISSING
                            fresh != base -> OrganizationFailure.STALE
                            else -> null
                        }
                    mutable.value =
                        mutable.value.copy(
                            hub = hub,
                            rules = rules,
                            loading = false,
                            error =
                                if (rules == null) OrganizationFailure.LEGAL_CHANGED
                                else mutable.value.error,
                            editorFailure = editorFailure,
                            target = target,
                            targetFailure = targetFailure,
                            draft =
                                if (
                                    draft?.acceptedRulesVersion != null &&
                                        draft.acceptedRulesVersion != rules?.version
                                )
                                    draft.copy(acceptedRulesVersion = null)
                                else draft,
                        )
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (valid(session, epoch))
                    mutable.value =
                        mutable.value.copy(
                            loading = false,
                            hub = null,
                            rules = null,
                            error = organizationFailure(error),
                            editorFailure =
                                if (mutable.value.base != null) organizationFailure(error)
                                else null,
                            target = null,
                            targetFailure =
                                if (targetId != null) organizationFailure(error) else null,
                        )
            }
        }
    }

    fun create() {
        if (
            mutable.value.session?.ready != true ||
                mutable.value.session != currentSession() ||
                mutable.value.busy ||
                mutable.value.loading ||
                mutable.value.hub == null
        )
            return
        cancelPicker()
        logo = null
        mutable.value =
            mutable.value.copy(
                draft = OrganizationDraft(),
                base = null,
                confirmedId = null,
                error = null,
                logoSelected = false,
                logoIncomplete = false,
                editorFailure = null,
                pickerOpen = false,
                logoPreview = null,
            )
    }

    fun edit(record: OrganizationRecord) {
        val session = mutable.value.session ?: return
        if (
            session != currentSession() ||
                mutable.value.busy ||
                mutable.value.loading ||
                !record.editable(session) ||
                mutable.value.hub?.requests?.none { it == record } != false
        )
            return
        cancelPicker()
        logo = null
        mutable.value =
            mutable.value.copy(
                draft = OrganizationContract.draft(record),
                base = record,
                error = null,
                confirmedId = null,
                logoSelected = false,
                logoIncomplete = false,
                editorFailure = null,
                pickerOpen = false,
                logoPreview = null,
            )
    }

    fun change(transform: (OrganizationDraft) -> OrganizationDraft) {
        if (
            mutable.value.busy ||
                !mutable.value.editorWritable ||
                mutable.value.session != currentSession()
        )
            return
        val draft = mutable.value.draft ?: return
        val changed = transform(draft)
        if (changed.id != draft.id) return
        mutable.value =
            mutable.value.copy(
                draft =
                    if (changed.name != draft.name) changed.copy(acceptedRulesVersion = null)
                    else changed,
                confirmedId = null,
                error = null,
            )
    }

    fun consent(accepted: Boolean) {
        val version = mutable.value.rules?.version ?: return
        change { it.copy(acceptedRulesVersion = if (accepted) version else null) }
    }

    fun beginPicker(): Boolean {
        val captured = mutable.value
        val session = captured.session ?: return false
        val draft = captured.draft ?: return false
        if (
            !captured.editorWritable ||
                captured.busy ||
                captured.imageLoading ||
                picker != null ||
                session != currentSession()
        )
            return false
        val lease =
            pickerAuthorization.begin(session.uid, session.revision)
                ?: run {
                    mutable.value = captured.copy(error = OrganizationFailure.NOT_READY)
                    return false
                }
        picker = Picker(session, draft.id, lease)
        mutable.value = captured.copy(pickerOpen = true, error = null)
        return true
    }

    fun pickerResult(context: Context, uri: Uri?) {
        val pending = picker ?: return
        picker = null
        pending.lease.finish()
        if (
            mutable.value.session != pending.session ||
                currentSession() != pending.session ||
                mutable.value.draft?.id != pending.draftId
        )
            return
        mutable.value = mutable.value.copy(pickerOpen = false)
        if (uri != null) selectLogo(context, uri)
    }

    fun pickerUnavailable() {
        cancelPicker()
        mutable.value = mutable.value.copy(pickerOpen = false, error = OrganizationFailure.INVALID)
    }

    private fun selectLogo(context: Context, uri: Uri) {
        val captured = mutable.value
        // A foreground server refresh may already be running when the result arrives.
        // Preparation is local only; the unchanged submit gate still requires fresh state.
        if (
            captured.busy ||
                captured.editorFailure != null ||
                captured.session?.ready != true ||
                captured.draft == null ||
                captured.session != currentSession()
        )
            return
        val epoch = generation
        image?.cancel()
        mutable.value = captured.copy(imageLoading = true, error = null)
        image = viewModelScope.launch {
            try {
                val bytes = OrganizationLogo.prepare(context.applicationContext, uri)
                if (
                    valid(captured.session, epoch) && mutable.value.draft?.id == captured.draft.id
                ) {
                    logo = bytes
                    mutable.value =
                        mutable.value.copy(
                            logoSelected = true,
                            imageLoading = false,
                            logoPreview = OrganizationLogoSelection(bytes),
                        )
                }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                if (valid(captured.session, epoch))
                    mutable.value =
                        mutable.value.copy(
                            imageLoading = false,
                            error = OrganizationFailure.INVALID,
                        )
            }
        }
    }

    fun removeLogoSelection() {
        if (!mutable.value.busy) {
            image?.cancel()
            logo = null
            mutable.value =
                mutable.value.copy(logoSelected = false, imageLoading = false, logoPreview = null)
        }
    }

    fun closeDraft() {
        if (!mutable.value.busy) {
            image?.cancel()
            cancelPicker()
            logo = null
            mutable.value =
                mutable.value.copy(
                    draft = null,
                    base = null,
                    logoSelected = false,
                    imageLoading = false,
                    editorFailure = null,
                    pickerOpen = false,
                    logoPreview = null,
                )
        }
    }

    fun submit(language: String) {
        val captured = mutable.value
        val draft = captured.draft ?: return
        val rules = captured.rules
        if (captured.base == null && rules == null) return
        if (captured.imageLoading || !captured.editorWritable) return
        mutate(operation = { repository.submit(draft, rules, captured.base, logo, language) }) {
            result ->
            mutable.value =
                mutable.value.copy(
                    base = result.record,
                    confirmedId = result.record.id,
                    logoIncomplete = result.logoIncomplete,
                    error =
                        if (result.logoIncomplete) OrganizationFailure.LOGO_INCOMPLETE else null,
                )
            if (!result.logoIncomplete) {
                logo = null
                mutable.value = mutable.value.copy(logoSelected = false, logoPreview = null)
            }
        }
    }

    fun discard(record: OrganizationRecord) {
        val session = mutable.value.session ?: return
        if (
            session.globalRole == "owner" ||
                !record.editable(session) ||
                mutable.value.hub?.requests?.none { it.id == record.id } != false
        )
            return
        mutate(operation = { repository.discard(record) }) {
            if (mutable.value.draft?.id == record.id) {
                logo = null
                mutable.value =
                    mutable.value.copy(
                        draft = null,
                        base = null,
                        logoSelected = false,
                        logoPreview = null,
                    )
            }
            mutable.value = mutable.value.copy(confirmedId = record.id)
        }
    }

    private fun <T> mutate(operation: suspend () -> T, apply: (T) -> Unit) {
        val captured = mutable.value
        if (
            !captured.visible ||
                captured.busy ||
                captured.session?.ready != true ||
                currentSession() != captured.session ||
                mutation?.isActive == true
        )
            return
        val epoch = generation
        mutable.value = captured.copy(busy = true, error = null, confirmedId = null)
        mutation = viewModelScope.launch {
            try {
                val result = operation()
                if (valid(captured.session, epoch)) apply(result)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (valid(captured.session, epoch))
                    mutable.value = mutable.value.copy(error = organizationFailure(error))
            } finally {
                if (valid(captured.session, epoch)) {
                    mutable.value = mutable.value.copy(busy = false)
                    refresh(preserveError = true)
                }
            }
        }
    }

    override fun onCleared() {
        cancelPicker()
        logo = null
        super.onCleared()
    }
}
