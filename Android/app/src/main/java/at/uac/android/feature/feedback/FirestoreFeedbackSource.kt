package at.uac.android.feature.feedback

import android.content.Context
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.FirebaseBackendGuard
import at.uac.android.feature.browse.Fields
import at.uac.android.feature.browse.RawDocument
import com.google.firebase.Timestamp
import com.google.firebase.firestore.DocumentSnapshot
import com.google.firebase.firestore.FieldPath
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.MetadataChanges
import com.google.firebase.firestore.Query
import com.google.firebase.firestore.Source
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.tasks.await

/** Demo-only gateway. Real release/staging gateways must be configured separately. */
class FirestoreFeedbackSource(private val db: FirebaseFirestore) : FeedbackSource {
    init {
        LocalEnvironment.requireSafe()
        FirebaseBackendGuard.requireFirestore(db)
    }

    private fun id(value: String) = value.also { require(feedbackId(it)) }

    private fun reference(value: String) = db.collection("feedback").document(id(value))

    private fun query(uid: String?): Query =
        if (uid == null) db.collection("feedback")
        else db.collection("feedback").whereEqualTo("userId", id(uid))

    private fun ordered(uid: String?) =
        query(uid)
            .orderBy("createdAt", Query.Direction.DESCENDING)
            .orderBy(FieldPath.documentId(), Query.Direction.DESCENDING)

    // An equality lookup on __name__ evaluates a missing resource in the Rules emulator.
    // A closed, single-ID range retains query authorization by userId and supports legacy
    // records without a duplicated payload ID. It never broadens the requested path.
    private fun targetQuery(uid: String?, value: String): Query =
        query(uid)
            .whereGreaterThanOrEqualTo(FieldPath.documentId(), id(value))
            .whereLessThanOrEqualTo(FieldPath.documentId(), id(value))
            .limit(1)

    private fun convert(value: Any?): Any? =
        when (value) {
            is Timestamp -> Instant.ofEpochSecond(value.seconds, value.nanoseconds.toLong())
            is Map<*, *> -> value.entries.associate { it.key.toString() to convert(it.value) }
            is List<*> -> value.map(::convert)
            else -> value
        }

    @Suppress("UNCHECKED_CAST")
    private fun row(doc: DocumentSnapshot): RawDocument? =
        doc.data?.let { RawDocument(doc.id, convert(it) as Fields) }

    override suspend fun page(uid: String?, after: FeedbackCursor?, size: Int): FeedbackRawPage =
        request {
            require(size in 1..100)
            var query = ordered(uid)
            if (after != null)
                query =
                    query.startAfter(
                        Timestamp(after.createdAt.epochSecond, after.createdAt.nano),
                        id(after.id),
                    )
            val documents = query.limit((size + 1).toLong()).get(Source.SERVER).await().documents
            val chosen = documents.take(size)
            val cursor =
                chosen.lastOrNull()?.let {
                    val date =
                        it.getTimestamp("createdAt")
                            ?: throw FeedbackException(FeedbackFailure.INVALID)
                    FeedbackCursor(
                        Instant.ofEpochSecond(date.seconds, date.nanoseconds.toLong()),
                        it.id,
                    )
                }
            FeedbackRawPage(chosen.mapNotNull(::row), cursor, documents.size > size)
        }

    // An owned query can prove absence; a direct get of a nonexistent private parent is denied by
    // Rules.
    override suspend fun item(id: String, uid: String?): RawDocument? = request {
        targetQuery(uid, id).get(Source.SERVER).await().documents.singleOrNull()?.let(::row)
    }

    override suspend fun messages(id: String): List<RawDocument> = request {
        reference(id)
            .collection("messages")
            .orderBy("createdAt", Query.Direction.DESCENDING)
            .orderBy(FieldPath.documentId(), Query.Direction.DESCENDING)
            .limit(101)
            .get(Source.SERVER)
            .await()
            .documents
            .mapNotNull(::row)
    }

    override suspend fun message(id: String, messageId: String): RawDocument? = request {
        row(reference(id).collection("messages").document(id(messageId)).get(Source.SERVER).await())
    }

    override suspend fun create(
        id: String,
        session: FeedbackSession,
        draft: FeedbackDraft,
        current: () -> Boolean,
    ): Unit =
        request(writing = true) {
            val parent = reference(id)
            db.runTransaction { transaction ->
                    if (!current()) throw CancellationException("Feedback account scope changed")
                    // Forces an online transaction without reading an unreadable, nonexistent
                    // parent.
                    val actor = transaction.get(db.document("users/${this.id(session.uid)}"))
                    if (!actor.exists()) throw FeedbackException(FeedbackFailure.NOT_READY)
                    if (!current()) throw CancellationException("Feedback account scope changed")
                    // Existing records cannot be overwritten: createdAt and the original message
                    // are immutable in Rules.
                    transaction.set(
                        parent,
                        FeedbackContract.creation(id, session, draft, FieldValue.serverTimestamp()),
                    )
                    Unit
                }
                .await()
        }

    override suspend fun reply(
        id: String,
        messageId: String,
        session: FeedbackSession,
        text: String,
        owner: Boolean,
        close: Boolean,
        current: () -> Boolean,
    ): Unit =
        request(writing = true) {
            val parent = reference(id)
            val child = parent.collection("messages").document(this.id(messageId))
            db.runTransaction { transaction ->
                    if (!current()) throw CancellationException("Feedback account scope changed")
                    val item =
                        row(transaction.get(parent))?.let(FeedbackContract::item)
                            ?: throw FeedbackException(FeedbackFailure.MISSING)
                    val existing =
                        row(transaction.get(child))?.let { FeedbackContract.message(it, id) }
                    if (owner && !session.canManage || !owner && item.uid != session.uid)
                        throw FeedbackException(FeedbackFailure.DENIED)
                    if (existing != null) {
                        if (
                            existing.senderId != session.uid ||
                                existing.text != text ||
                                existing.owner != owner ||
                                existing.system != close
                        )
                            throw FeedbackException(FeedbackFailure.CONFLICT)
                        return@runTransaction Unit // Idempotent retry of this immutable message,
                        // even if the thread is now closed.
                    }
                    if (item.status.closed) throw FeedbackException(FeedbackFailure.CLOSED)
                    if (close && (!owner || item.hasDsaCase))
                        throw FeedbackException(FeedbackFailure.DENIED)
                    val timestamp = FieldValue.serverTimestamp()
                    val role = if (owner) "owner" else "user"
                    val summary =
                        mutableMapOf<String, Any>(
                            "status" to if (close) "closed" else if (owner) "answered" else "open",
                            "updatedAt" to timestamp,
                            "lastMessageAt" to timestamp,
                            "lastMessageText" to text,
                            "lastMessageByUserId" to session.uid,
                            "lastMessageByRole" to role,
                            "unreadForOwner" to !owner,
                            "unreadForUser" to owner,
                        )
                    if (owner && !close)
                        summary.putAll(
                            mapOf(
                                "ownerReply" to text,
                                "repliedAt" to timestamp,
                                "repliedByUserId" to session.uid,
                            )
                        )
                    if (!current()) throw CancellationException("Feedback account scope changed")
                    transaction.set(
                        child,
                        mapOf(
                            "id" to messageId,
                            "feedbackId" to id,
                            "senderId" to session.uid,
                            "senderDisplayName" to session.displayName,
                            "senderRole" to role,
                            "text" to text,
                            "createdAt" to timestamp,
                            "isSystem" to close,
                        ),
                    )
                    transaction.update(parent, summary)
                    Unit
                }
                .await()
        }

    override fun changes(uid: String?, id: String?): Flow<Unit> = callbackFlow {
        val parentQuery = if (id == null) ordered(uid).limit(50) else targetQuery(uid, id)
        val parent =
            parentQuery.addSnapshotListener(MetadataChanges.INCLUDE) { snapshot, error ->
                if (error != null) close(mapped(error, false))
                else if (
                    snapshot != null &&
                        !snapshot.metadata.isFromCache &&
                        !snapshot.metadata.hasPendingWrites()
                )
                    trySend(Unit)
            }
        val children = id?.let { parentId ->
            reference(parentId)
                .collection("messages")
                .orderBy("createdAt", Query.Direction.DESCENDING)
                .limit(100)
                .addSnapshotListener(MetadataChanges.INCLUDE) { snapshot, error ->
                    if (error != null) close(mapped(error, false))
                    else if (
                        snapshot != null &&
                            !snapshot.metadata.isFromCache &&
                            !snapshot.metadata.hasPendingWrites()
                    )
                        trySend(Unit)
                }
        }
        awaitClose {
            parent.remove()
            children?.remove()
        }
    }

    private fun mapped(error: FirebaseFirestoreException, writing: Boolean) =
        FeedbackException(
            when (error.code) {
                FirebaseFirestoreException.Code.PERMISSION_DENIED,
                FirebaseFirestoreException.Code.UNAUTHENTICATED -> FeedbackFailure.DENIED
                FirebaseFirestoreException.Code.UNAVAILABLE,
                FirebaseFirestoreException.Code.DEADLINE_EXCEEDED ->
                    if (writing) FeedbackFailure.UNCONFIRMED else FeedbackFailure.OFFLINE
                FirebaseFirestoreException.Code.NOT_FOUND -> FeedbackFailure.MISSING
                FirebaseFirestoreException.Code.INVALID_ARGUMENT -> FeedbackFailure.INVALID
                else -> if (writing) FeedbackFailure.UNCONFIRMED else FeedbackFailure.UNKNOWN
            },
            error,
        )

    private suspend fun <T> request(writing: Boolean = false, block: suspend () -> T): T =
        try {
            block()
        } catch (error: FirebaseFirestoreException) {
            throw mapped(error, writing)
        }
}

fun localFeedbackSource(context: Context): FeedbackSource =
    FirestoreFeedbackSource(AppBackend.firestore(context))
