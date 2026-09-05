package at.uac.android.feature.moderation

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class ModerationViewModel(
    source: ModerationSource,
    private val authority: () -> ModerationSession?,
    workScope: CoroutineScope? = null,
) : ViewModel() {
    private val scope = workScope ?: viewModelScope
    private val repository = ModerationRepository(source, authority)
    private val mutable = MutableStateFlow(ModerationState())
    val state = mutable.asStateFlow()
    private var observer: Job? = null
    private val loads = mutableMapOf<ModerationKind, Job>()
    private val watches = mutableMapOf<ModerationKind, Job>()
    private val dirty = mutableSetOf<ModerationKind>()
    private var previewJob: Job? = null
    private var generation = 0L
    private var previewGeneration = 0L
    private var routeRequest: String? = null
    private var presentation: ModerationPresentation? = null

    fun observeSessions(sessions: Flow<ModerationSession?>) {
        observer?.cancel()
        observer =
            scope.launch(Dispatchers.Main.immediate, start = CoroutineStart.UNDISPATCHED) {
                sessions.collect(::bind)
            }
    }

    fun snapshot(current: ModerationSession?, section: ModerationSection): ModerationState =
        if (authority() == current) mutable.value.forSession(current, section)
        else ModerationState(section = section)

    fun isCurrent(session: ModerationSession?, section: ModerationSection) =
        session?.allowed == true &&
            authority() == session &&
            mutable.value.session == session &&
            mutable.value.section == section &&
            mutable.value.visible

    fun owns(token: ModerationPresentation?) =
        token != null &&
            presentation === token &&
            mutable.value.visible &&
            authority() == mutable.value.session

    fun present(
        section: ModerationSection,
        requestedOrganizationId: String? = null,
    ): ModerationPresentation {
        show(section, requestedOrganizationId)
        val token = ModerationPresentation()
        presentation = token
        if (mutable.value.previewError != ModerationFailure.INVALID) refresh()
        return token
    }

    fun dismiss(token: ModerationPresentation) {
        if (presentation === token) hide()
    }

    fun bind(session: ModerationSession?) {
        if (session == mutable.value.session) return
        val visible = mutable.value.visible
        val section = mutable.value.section
        presentation = null
        stop()
        routeRequest = null
        mutable.value = ModerationState(session = session, section = section, visible = visible)
        if (visible && session?.allowed == true) resume()
    }

    fun show(section: ModerationSection, requestedOrganizationId: String? = null) {
        bind(authority())
        if (
            mutable.value.visible &&
                mutable.value.section == section &&
                routeRequest == requestedOrganizationId
        )
            return
        presentation = null
        stop()
        routeRequest = requestedOrganizationId
        mutable.value = ModerationState(session = authority(), section = section, visible = true)
        if (
            requestedOrganizationId != null &&
                (section != ModerationSection.ORGANIZATION_REQUESTS ||
                    !ModerationContract.id(requestedOrganizationId))
        ) {
            mutable.value = mutable.value.copy(previewError = ModerationFailure.INVALID)
            return
        }
        resume()
        if (requestedOrganizationId != null && mutable.value.session?.allowed == true)
            select(ModerationTarget(ModerationKind.ORGANIZATION, requestedOrganizationId))
    }

    fun hide() {
        presentation = null
        stop()
        routeRequest = null
        mutable.value = ModerationState(session = authority(), section = mutable.value.section)
    }

    private fun stop() {
        generation++
        previewGeneration++
        loads.values.forEach { it.cancel() }
        loads.clear()
        watches.values.forEach { it.cancel() }
        watches.clear()
        dirty.clear()
        previewJob?.cancel()
        previewJob = null
    }

    private fun current(session: ModerationSession, version: Long) =
        generation == version &&
            authority() == session &&
            mutable.value.session == session &&
            session.allowed &&
            mutable.value.visible

    private fun resume() {
        if (mutable.value.session?.allowed != true) return
        mutable.value.section.kinds.forEach {
            refresh(it)
            watch(it)
        }
    }

    fun refresh() {
        if (authority() != mutable.value.session) {
            bind(authority())
            return
        }
        mutable.value.section.kinds.forEach { refresh(it) }
        mutable.value.selected?.let(::loadPreview)
    }

    fun refresh(kind: ModerationKind) {
        val session = mutable.value.session ?: return
        val version = generation
        if (!current(session, version) || kind !in mutable.value.section.kinds) return
        part(kind, ModerationPart(loading = true))
        if (loads[kind]?.isActive == true) {
            dirty += kind
            return
        }
        loads[kind] = scope.launch {
            try {
                var attempts = 0
                while (true) {
                    dirty.remove(kind)
                    val head = repository.head(kind)
                    if (!current(session, version)) return@launch
                    if (dirty.remove(kind)) {
                        if (++attempts >= 3) ModerationContract.fail(ModerationFailure.STALE)
                        continue
                    }
                    part(kind, ModerationPart(head = head))
                    if (watches[kind]?.isActive != true) watch(kind)
                    break
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (current(session, version)) fail(kind, moderationFailure(error))
            } finally {
                if (generation == version) loads.remove(kind)
            }
        }
    }

    private fun part(kind: ModerationKind, value: ModerationPart) {
        mutable.value = mutable.value.copy(parts = mutable.value.parts + (kind to value))
    }

    private fun fail(kind: ModerationKind, failure: ModerationFailure) {
        part(kind, ModerationPart(error = failure))
        if (mutable.value.selected?.kind == kind) {
            previewGeneration++
            previewJob?.cancel()
            mutable.value =
                mutable.value.copy(preview = null, previewLoading = false, previewError = failure)
        }
    }

    private fun watch(kind: ModerationKind) {
        val session = mutable.value.session ?: return
        val version = generation
        if (!current(session, version)) return
        watches.remove(kind)?.cancel()
        val target = mutable.value.selected?.takeIf { it.kind == kind }
        watches[kind] = scope.launch {
            try {
                repository.changes(kind, target).collect {
                    if (current(session, version)) {
                        refresh(kind)
                        mutable.value.selected?.takeIf { it.kind == kind }?.let(::loadPreview)
                    }
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (current(session, version)) fail(kind, moderationFailure(error))
            }
        }
    }

    fun select(target: ModerationTarget) {
        val actor = mutable.value.session ?: return
        if (!current(actor, generation) || target.kind !in mutable.value.section.kinds) return
        if (!ModerationContract.id(target.id)) {
            mutable.value = mutable.value.copy(previewError = ModerationFailure.INVALID)
            return
        }
        mutable.value = mutable.value.copy(selected = target, preview = null, previewError = null)
        loadPreview(target)
        watch(target.kind)
    }

    private fun loadPreview(target: ModerationTarget) {
        val actor = mutable.value.session ?: return
        val version = generation
        if (!current(actor, version) || mutable.value.selected != target) return
        previewJob?.cancel()
        val expectedPreview = ++previewGeneration
        mutable.value =
            mutable.value.copy(preview = null, previewLoading = true, previewError = null)
        previewJob = scope.launch {
            try {
                val preview = repository.preview(target)
                if (
                    current(actor, version) &&
                        previewGeneration == expectedPreview &&
                        mutable.value.selected == target
                )
                    mutable.value =
                        mutable.value.copy(
                            preview = preview,
                            previewLoading = false,
                            previewError = if (preview == null) ModerationFailure.MISSING else null,
                        )
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (
                    current(actor, version) &&
                        previewGeneration == expectedPreview &&
                        mutable.value.selected == target
                )
                    mutable.value =
                        mutable.value.copy(
                            preview = null,
                            previewLoading = false,
                            previewError = moderationFailure(error),
                        )
            }
        }
    }

    fun closePreview() {
        val kind = mutable.value.selected?.kind
        previewGeneration++
        previewJob?.cancel()
        mutable.value =
            mutable.value.copy(
                selected = null,
                preview = null,
                previewLoading = false,
                previewError = null,
            )
        kind?.let(::watch)
    }

    fun search(value: String) {
        if (authority() == mutable.value.session)
            mutable.value = mutable.value.copy(search = value.take(160))
    }

    fun filter(kind: ModerationKind?) {
        if (
            authority() == mutable.value.session &&
                (kind == null || kind in mutable.value.section.kinds)
        )
            mutable.value = mutable.value.copy(filter = kind)
    }

    fun sort(value: ModerationSort) {
        if (authority() == mutable.value.session) mutable.value = mutable.value.copy(sort = value)
    }

    override fun onCleared() {
        presentation = null
        stop()
        observer?.cancel()
        mutable.value = ModerationState()
        super.onCleared()
    }
}
