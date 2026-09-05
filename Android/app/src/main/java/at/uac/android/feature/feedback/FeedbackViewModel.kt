package at.uac.android.feature.feedback

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class FeedbackViewModel(
    source: FeedbackSource,
    private val authority: () -> FeedbackSession?,
    gate: FeedbackMutationGate,
    workScope: CoroutineScope? = null,
) : ViewModel() {
    private val scope = workScope ?: viewModelScope
    private val repository = FeedbackRepository(source, authority, gate)
    private val mutable = MutableStateFlow(FeedbackState())
    val state = mutable.asStateFlow()
    private var visible = false
    private var watch: Job? = null
    private var load: Job? = null
    private var mutation: Job? = null
    private var readRevision = 0L
    private var createAttempt: Pair<String, FeedbackDraft>? = null

    private data class ReplyAttempt(
        val id: String,
        val messageId: String,
        val text: String,
        val audience: FeedbackAudience,
        val close: Boolean,
    )

    private var replyAttempt: ReplyAttempt? = null

    fun observeSessions(sessions: Flow<FeedbackSession?>): Job =
        scope.launch(Dispatchers.Main.immediate, start = CoroutineStart.UNDISPATCHED) {
            sessions.collect(::bind)
        }

    fun bind(session: FeedbackSession?) {
        if (mutable.value.session == session) return
        watch?.cancel()
        load?.cancel()
        mutation?.cancel()
        readRevision++
        createAttempt = null
        replyAttempt = null
        mutable.value = FeedbackState(session = session)
        if (visible && session != null) resume()
    }

    private fun current(actor: FeedbackSession) =
        authority() == actor && state.value.session == actor

    private fun destination() = state.value.audience to state.value.selectedId

    fun show(audience: FeedbackAudience, id: String?) {
        if (authority() != state.value.session) bind(authority())
        if (id != null && !feedbackId(id)) {
            watch?.cancel()
            load?.cancel()
            readRevision++
            visible = false
            mutable.value =
                FeedbackState(
                    session = state.value.session,
                    audience = audience,
                    selectedId = id,
                    error = FeedbackFailure.INVALID,
                )
            return
        }
        val changed = audience != state.value.audience || id != state.value.selectedId
        if (changed) {
            load?.cancel()
            watch?.cancel()
            readRevision++
            if (mutation?.isActive != true) replyAttempt = null
            mutable.value =
                state.value.copy(
                    audience = audience,
                    selectedId = id,
                    page = null,
                    conversation = null,
                    loading = false,
                    error = null,
                    actionError = null,
                    reply = "",
                    confirmedId = null,
                    createRetryPending = createAttempt != null,
                    replyRetryPending = replyAttempt != null,
                    inbox = FeedbackInboxOptions(),
                    inboxQueryRejected = false,
                )
        }
        if (!visible || changed || watch?.isActive != true) {
            visible = true
            resume()
        }
    }

    fun hide(audience: FeedbackAudience, id: String?) {
        if (destination() != audience to id) return
        visible = false
        watch?.cancel()
        watch = null
        load?.cancel()
        readRevision++
        mutable.value =
            state.value.copy(
                loading = false,
                inbox = FeedbackInboxOptions(),
                inboxQueryRejected = false,
            )
        // Submitted writes are deliberately not cancelled on navigation or app backgrounding.
    }

    private fun resume() {
        val actor = state.value.session ?: return
        refresh()
        val target = destination()
        watch?.cancel()
        watch = scope.launch {
            try {
                repository.changes(target.first, target.second).collect {
                    if (
                        current(actor) && visible && destination() == target && !state.value.pending
                    )
                        refresh()
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (current(actor) && destination() == target) fail(error)
            }
        }
    }

    fun refresh(more: Boolean = false): Job? {
        val actor = state.value.session ?: return null
        if (!current(actor) || more && (state.value.loading || state.value.page?.hasMore != true))
            return null
        val target = destination()
        val previous = if (more) state.value.page else null
        val revision = ++readRevision
        load?.cancel()
        mutable.value = state.value.copy(loading = true, error = null)
        return scope
            .launch {
                try {
                    if (target.second != null) {
                        val conversation = repository.conversation(target.second!!, target.first)
                        if (current(actor) && readRevision == revision && destination() == target)
                            mutable.value = state.value.copy(conversation = conversation)
                    } else {
                        val page = repository.page(target.first, previous?.next)
                        if (current(actor) && readRevision == revision && destination() == target)
                            mutable.value =
                                state.value.copy(
                                    page =
                                        page.copy(
                                            items =
                                                (previous?.items.orEmpty() + page.items)
                                                    .distinctBy { it.id },
                                            invalid = (previous?.invalid ?: 0) + page.invalid,
                                        )
                                )
                    }
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Exception) {
                    if (current(actor) && readRevision == revision && destination() == target)
                        fail(error)
                } finally {
                    if (current(actor) && readRevision == revision && destination() == target)
                        mutable.value = state.value.copy(loading = false)
                }
            }
            .also { load = it }
    }

    private fun fail(error: Exception) {
        val reason = (error as? FeedbackException)?.failure ?: FeedbackFailure.UNKNOWN
        mutable.value =
            state.value.copy(
                error = reason,
                page = if (reason == FeedbackFailure.OFFLINE) state.value.page else null,
                conversation =
                    if (reason == FeedbackFailure.OFFLINE) state.value.conversation else null,
                inbox =
                    if (reason == FeedbackFailure.OFFLINE) state.value.inbox
                    else FeedbackInboxOptions(),
                inboxQueryRejected = false,
            )
    }

    private fun canSelectInbox(): Boolean {
        val actor = state.value.session ?: return false
        return visible &&
            current(actor) &&
            actor.canManage &&
            state.value.audience == FeedbackAudience.MANAGEMENT &&
            state.value.selectedId == null
    }

    fun inboxSearch(value: String) {
        if (!canSelectInbox()) return
        if (!FeedbackInboxSelector.validQuery(value)) {
            mutable.value = state.value.copy(inboxQueryRejected = true)
            return
        }
        mutable.value =
            state.value.copy(
                inbox = state.value.inbox.copy(query = value),
                inboxQueryRejected = false,
            )
    }

    fun inboxFilter(value: FeedbackInboxFilter) {
        if (canSelectInbox())
            mutable.value = state.value.copy(inbox = state.value.inbox.copy(filter = value))
    }

    fun inboxSort(value: FeedbackInboxSort) {
        if (canSelectInbox())
            mutable.value = state.value.copy(inbox = state.value.inbox.copy(sort = value))
    }

    fun draft(value: FeedbackDraft) {
        if (!state.value.pending && createAttempt == null && authority() == state.value.session)
            mutable.value = state.value.copy(draft = value, actionError = null, confirmedId = null)
    }

    fun reply(value: String) {
        if (!state.value.pending && replyAttempt == null && authority() == state.value.session)
            mutable.value = state.value.copy(reply = value, actionError = null, confirmedId = null)
    }

    fun submit(): Job? {
        val actor = state.value.session ?: return null
        if (
            !current(actor) ||
                state.value.pending ||
                !state.value.draft.valid() ||
                state.value.audience != FeedbackAudience.OWN
        )
            return null
        val attempt =
            createAttempt
                ?: (UUID.randomUUID().toString() to state.value.draft.normalized()).also {
                    createAttempt = it
                }
        return mutate(actor) {
            val result = repository.create(attempt.first, attempt.second)
            if (current(actor)) {
                createAttempt = null
                mutable.value = state.value.copy(draft = FeedbackDraft(), confirmedId = result.id)
            }
        }
    }

    fun send(close: Boolean = false, closingText: String = ""): Job? {
        val actor = state.value.session ?: return null
        val id = state.value.selectedId ?: return null
        if (!current(actor) || state.value.pending) return null
        val text = if (close) closingText.trim() else state.value.reply.trim()
        if (text.length !in 1..2_000) return null
        val attempt =
            replyAttempt
                ?: ReplyAttempt(id, UUID.randomUUID().toString(), text, state.value.audience, close)
                    .also { replyAttempt = it }
        if (attempt.id != id || attempt.audience != state.value.audience || attempt.close != close)
            return null
        return mutate(actor) {
            val conversation =
                repository.reply(
                    attempt.id,
                    attempt.messageId,
                    attempt.text,
                    attempt.audience,
                    attempt.close,
                )
            if (current(actor)) {
                replyAttempt = null
                if (destination() == attempt.audience to attempt.id)
                    mutable.value =
                        state.value.copy(
                            conversation = conversation,
                            reply = "",
                            confirmedId = attempt.messageId,
                        )
            }
        }
    }

    private fun mutate(actor: FeedbackSession, action: suspend () -> Unit): Job {
        val target = destination()
        mutable.value = state.value.copy(pending = true, actionError = null, confirmedId = null)
        return scope
            .launch {
                try {
                    action()
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Exception) {
                    if (current(actor)) {
                        val reason =
                            (error as? FeedbackException)?.failure ?: FeedbackFailure.UNCONFIRMED
                        // Preserve the exact request ID/payload after uncertain results; a retry
                        // cannot duplicate it.
                        if (
                            reason !in setOf(FeedbackFailure.UNCONFIRMED, FeedbackFailure.OFFLINE)
                        ) {
                            createAttempt = null
                            replyAttempt = null
                        }
                        if (destination() == target)
                            mutable.value = state.value.copy(actionError = reason)
                    }
                } finally {
                    if (current(actor)) {
                        mutable.value =
                            state.value.copy(
                                pending = false,
                                createRetryPending = createAttempt != null,
                                replyRetryPending = replyAttempt != null,
                            )
                        if (visible) refresh()
                    }
                }
            }
            .also { mutation = it }
    }
}
