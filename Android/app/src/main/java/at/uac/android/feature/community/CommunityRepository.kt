package at.uac.android.feature.community

import at.uac.android.feature.browse.Fields
import at.uac.android.feature.browse.RawDocument
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

interface CommunitySource {
    suspend fun parent(target: CommunityTarget): RawDocument

    suspend fun registration(eventId: String, uid: String): RawDocument?

    suspend fun call(name: String, data: Fields, uid: String): Any?

    suspend fun comment(target: CommunityTarget, id: String): RawDocument?

    fun comments(target: CommunityTarget): Flow<Result<CommentPage>>

    suspend fun moderation(target: CommunityTarget, session: CommunitySession): Boolean

    suspend fun deleteComment(
        target: CommunityTarget,
        id: String,
        uid: String,
        stillCurrent: () -> Boolean,
    )
}

interface CommunityMutationGate {
    suspend fun <T> withSession(session: CommunitySession, operation: suspend () -> T): T
}

data class CommunityRegistrationChange(
    val session: CommunitySession,
    val target: CommunityTarget,
    val participation: EventParticipation,
    val didChange: Boolean,
)

/** Test-only default; the app factory must provide the shared AuthStore identity mutex. */
object DirectCommunityMutationGate : CommunityMutationGate {
    override suspend fun <T> withSession(session: CommunitySession, operation: suspend () -> T): T =
        withContext(NonCancellable) { operation() }
}

class CommunityRepository(
    private val source: CommunitySource,
    private val currentSession: () -> CommunitySession?,
    private val mutations: CommunityMutationGate = DirectCommunityMutationGate,
) {
    private fun capture(): CommunitySession =
        (currentSession() ?: throw CommunityException(CommunityFailure.SIGN_IN)).also {
            if (!it.ready) throw CommunityException(CommunityFailure.NOT_READY)
            if (!communityId(it.uid, 128)) throw CommunityException(CommunityFailure.INVALID)
        }

    private fun ensureCurrent(session: CommunitySession?) {
        if (currentSession() != session) throw CancellationException("Community session changed")
    }

    private suspend fun <T> read(session: CommunitySession?, operation: suspend () -> T): T =
        try {
            ensureCurrent(session)
            withTimeout(15_000) { operation() }.also { ensureCurrent(session) }
        } catch (error: TimeoutCancellationException) {
            ensureCurrent(session)
            throw CommunityException(CommunityFailure.OFFLINE, error)
        } catch (error: Exception) {
            ensureCurrent(session)
            throw error
        }

    private suspend fun <T> mutate(session: CommunitySession, operation: suspend () -> T): T =
        try {
            ensureCurrent(session)
            mutations.withSession(session, operation).also { ensureCurrent(session) }
        } catch (error: Exception) {
            ensureCurrent(session)
            throw error
        }

    suspend fun participation(target: CommunityTarget): EventParticipation {
        require(target.type == "event")
        val session = capture()
        return read(session) { participation(target, session) }
    }

    private suspend fun participation(
        target: CommunityTarget,
        session: CommunitySession,
    ): EventParticipation =
        CommunityContract.participation(
            source.parent(target),
            source.registration(target.id, session.uid),
            session.uid,
        )

    /** Desired state is explicit and server-idempotent. Counts are never written by this client. */
    suspend fun setRegistration(target: CommunityTarget, registered: Boolean): EventParticipation =
        setRegistrationConfirmed(target, registered).participation

    suspend fun setRegistrationConfirmed(
        target: CommunityTarget,
        registered: Boolean,
    ): CommunityRegistrationChange {
        require(target.type == "event")
        val session = capture()
        return mutate(session) {
            val raw =
                source.call(
                    if (registered) "registerForEvent" else "unregisterFromEvent",
                    mapOf("eventId" to target.id),
                    session.uid,
                )
            val receipt = CommunityContract.receipt(raw, target.id)
            if (receipt.registered != registered)
                throw CommunityException(CommunityFailure.UNCONFIRMED)
            ensureCurrent(session)
            // Another attendee may change the count between receipt and read-back: use fresh count.
            val actual = read(session) { participation(target, session) }
            if (actual.registered != registered)
                throw CommunityException(CommunityFailure.UNCONFIRMED)
            CommunityRegistrationChange(session, target, actual, receipt.didChange)
        }
    }

    fun comments(target: CommunityTarget): Flow<Result<CommentPage>> = source.comments(target)

    suspend fun moderation(target: CommunityTarget): Boolean {
        val session = currentSession() ?: return false
        if (!session.ready) return false
        return read(session) { source.moderation(target, session) }
    }

    /** saveComment has no idempotency key. Never automatically retry an unknown outcome. */
    suspend fun addComment(target: CommunityTarget, draft: String): CommunityComment {
        if (!target.acceptsNewComments) throw CommunityException(CommunityFailure.INVALID)
        val text = CommunityContract.text(draft)
        val session = capture()
        return mutate(session) {
            val result =
                try {
                    source.call(
                        "saveComment",
                        mapOf("parentType" to target.type, "parentId" to target.id, "text" to text),
                        session.uid,
                    )
                } catch (error: CommunityException) {
                    if (error.failure in setOf(CommunityFailure.OFFLINE, CommunityFailure.UNKNOWN))
                        throw CommunityException(CommunityFailure.UNCONFIRMED, error)
                    throw error
                }
            ensureCurrent(session)
            try {
                val fields =
                    result as? Map<*, *> ?: throw CommunityException(CommunityFailure.UNCONFIRMED)
                val id =
                    fields["id"] as? String
                        ?: throw CommunityException(CommunityFailure.UNCONFIRMED)
                @Suppress("UNCHECKED_CAST")
                val receipt =
                    CommunityContract.comment(
                        target,
                        RawDocument(id, fields as Fields),
                        response = true,
                    ) ?: throw CommunityException(CommunityFailure.UNCONFIRMED)
                if (receipt.authorId != session.uid || receipt.text != text)
                    throw CommunityException(CommunityFailure.UNCONFIRMED)
                val row =
                    read(session) { source.comment(target, id) }
                        ?: throw CommunityException(CommunityFailure.UNCONFIRMED)
                val actual =
                    CommunityContract.comment(target, row, response = true)
                        ?: throw CommunityException(CommunityFailure.UNCONFIRMED)
                if (
                    actual.authorId != session.uid ||
                        actual.text != text ||
                        actual.target != target ||
                        actual.id != id ||
                        actual.authorName != receipt.authorName ||
                        actual.createdAt.toEpochMilli() != receipt.createdAt.toEpochMilli()
                )
                    throw CommunityException(CommunityFailure.UNCONFIRMED)
                actual
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                throw CommunityException(CommunityFailure.UNCONFIRMED, error)
            }
        }
    }

    suspend fun deleteComment(target: CommunityTarget, id: String) {
        if (!communityId(id)) throw CommunityException(CommunityFailure.INVALID)
        val session = capture()
        mutate(session) {
            if (!source.moderation(target, session))
                throw CommunityException(CommunityFailure.DENIED)
            ensureCurrent(session)
            source.deleteComment(target, id, session.uid) { currentSession() == session }
            ensureCurrent(session)
            if (read(session) { source.comment(target, id) } != null)
                throw CommunityException(CommunityFailure.UNCONFIRMED)
        }
    }
}
