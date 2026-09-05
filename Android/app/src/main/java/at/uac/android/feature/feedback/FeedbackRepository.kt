package at.uac.android.feature.feedback

import at.uac.android.feature.browse.RawDocument
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

interface FeedbackSource {
    suspend fun page(uid: String?, after: FeedbackCursor?, size: Int): FeedbackRawPage

    suspend fun item(id: String, uid: String?): RawDocument?

    suspend fun messages(id: String): List<RawDocument>

    suspend fun message(id: String, messageId: String): RawDocument?

    suspend fun create(
        id: String,
        session: FeedbackSession,
        draft: FeedbackDraft,
        current: () -> Boolean,
    )

    suspend fun reply(
        id: String,
        messageId: String,
        session: FeedbackSession,
        text: String,
        owner: Boolean,
        close: Boolean,
        current: () -> Boolean,
    )

    fun changes(uid: String?, id: String?): Flow<Unit>
}

interface FeedbackMutationGate {
    suspend fun <T> withSession(session: FeedbackSession, operation: suspend () -> T): T
}

object DirectFeedbackMutationGate : FeedbackMutationGate {
    override suspend fun <T> withSession(session: FeedbackSession, operation: suspend () -> T): T =
        withContext(NonCancellable) { operation() }
}

class FeedbackRepository(
    private val source: FeedbackSource,
    private val authority: () -> FeedbackSession?,
    private val gate: FeedbackMutationGate = DirectFeedbackMutationGate,
) {
    private fun capture(audience: FeedbackAudience, write: Boolean = false): FeedbackSession {
        val actor = authority() ?: throw FeedbackException(FeedbackFailure.SIGN_IN)
        if (!feedbackId(actor.uid)) throw FeedbackException(FeedbackFailure.INVALID)
        if (write && !actor.ready) throw FeedbackException(FeedbackFailure.NOT_READY)
        if (audience == FeedbackAudience.MANAGEMENT && !actor.canManage)
            throw FeedbackException(FeedbackFailure.DENIED)
        return actor
    }

    private fun current(actor: FeedbackSession) {
        if (authority() != actor) throw CancellationException("Feedback account scope changed")
    }

    private fun uid(actor: FeedbackSession, audience: FeedbackAudience) =
        actor.uid.takeIf { audience == FeedbackAudience.OWN }

    private suspend fun <T> read(actor: FeedbackSession, action: suspend () -> T): T {
        current(actor)
        return try {
            withTimeout(15_000) { action() }.also { current(actor) }
        } catch (error: TimeoutCancellationException) {
            current(actor)
            throw FeedbackException(FeedbackFailure.OFFLINE, error)
        } catch (error: Exception) {
            current(actor)
            throw error
        }
    }

    private suspend fun <T> write(actor: FeedbackSession, action: suspend () -> T): T {
        current(actor)
        return try {
            gate.withSession(actor, action).also { current(actor) }
        } catch (error: Exception) {
            current(actor)
            throw error
        }
    }

    suspend fun page(audience: FeedbackAudience, after: FeedbackCursor? = null): FeedbackPage {
        val actor = capture(audience)
        return read(actor) {
            val raw = source.page(uid(actor, audience), after, 50)
            var invalid = 0
            val items =
                raw.rows.mapNotNull { row ->
                    val item =
                        try {
                            FeedbackContract.item(row)
                        } catch (_: FeedbackException) {
                            invalid++
                            null
                        }
                    if (item != null && audience == FeedbackAudience.OWN && item.uid != actor.uid)
                        throw FeedbackException(FeedbackFailure.DENIED)
                    item
                }
            if (raw.hasMore && (raw.next == null || raw.next == after))
                throw FeedbackException(FeedbackFailure.INVALID)
            FeedbackPage(items, raw.next, raw.hasMore, invalid)
        }
    }

    suspend fun conversation(id: String, audience: FeedbackAudience): FeedbackConversation {
        val actor = capture(audience)
        if (!feedbackId(id)) throw FeedbackException(FeedbackFailure.INVALID)
        return read(actor) {
            val row =
                source.item(id, uid(actor, audience))
                    ?: throw FeedbackException(FeedbackFailure.MISSING)
            val item = FeedbackContract.item(row)
            if (item.id != id || (audience == FeedbackAudience.OWN && item.uid != actor.uid))
                throw FeedbackException(FeedbackFailure.DENIED)
            val raw = source.messages(id)
            var invalid = 0
            val messages =
                raw.take(100).mapNotNull { value ->
                    try {
                        FeedbackContract.message(value, id)
                    } catch (_: FeedbackException) {
                        invalid++
                        null
                    }
                }
            FeedbackConversation(
                item,
                FeedbackContract.merge(item, messages),
                invalid,
                raw.size > 100,
            )
        }
    }

    suspend fun create(id: String, draft: FeedbackDraft): FeedbackItem {
        val actor = capture(FeedbackAudience.OWN, write = true)
        val normalized = draft.normalized()
        if (!feedbackId(id) || !normalized.valid()) throw FeedbackException(FeedbackFailure.INVALID)
        return write(actor) {
            val existing = read(actor) { source.item(id, actor.uid) }?.let(FeedbackContract::item)
            if (existing != null) {
                if (existing.id != id || !FeedbackContract.matches(existing, actor, normalized))
                    throw FeedbackException(FeedbackFailure.CONFLICT)
                existing
            } else {
                source.create(id, actor, normalized) { authority() == actor }
                val stored =
                    read(actor) { source.item(id, actor.uid) }?.let(FeedbackContract::item)
                        ?: throw FeedbackException(FeedbackFailure.UNCONFIRMED)
                if (stored.id != id || !FeedbackContract.matches(stored, actor, normalized))
                    throw FeedbackException(FeedbackFailure.CONFLICT)
                stored
            }
        }
    }

    suspend fun reply(
        id: String,
        messageId: String,
        text: String,
        audience: FeedbackAudience,
        close: Boolean = false,
    ): FeedbackConversation {
        val actor = capture(audience, write = true)
        val trimmed = text.trim()
        if (!feedbackId(id) || !feedbackId(messageId) || trimmed.length !in 1..2_000)
            throw FeedbackException(FeedbackFailure.INVALID)
        val manager = audience == FeedbackAudience.MANAGEMENT
        if (close && !manager) throw FeedbackException(FeedbackFailure.DENIED)
        return write(actor) {
            source.reply(id, messageId, actor, trimmed, manager, close) { authority() == actor }
            val receipt =
                read(actor) { source.message(id, messageId) }
                    ?.let { FeedbackContract.message(it, id) }
            if (
                receipt == null ||
                    receipt.id != messageId ||
                    receipt.senderId != actor.uid ||
                    receipt.text != trimmed ||
                    receipt.owner != manager ||
                    receipt.system != close
            )
                throw FeedbackException(FeedbackFailure.UNCONFIRMED)
            val confirmed = conversation(id, audience)
            confirmed
        }
    }

    fun changes(audience: FeedbackAudience, id: String?): Flow<Unit> {
        val actor = capture(audience)
        if (id != null && !feedbackId(id)) throw FeedbackException(FeedbackFailure.INVALID)
        return source.changes(uid(actor, audience), id)
    }
}
