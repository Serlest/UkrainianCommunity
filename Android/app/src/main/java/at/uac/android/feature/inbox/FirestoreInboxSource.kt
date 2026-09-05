package at.uac.android.feature.inbox

import android.content.Context
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.FirebaseBackendGuard
import at.uac.android.feature.browse.Fields
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.personal.validDocumentId
import com.google.firebase.Timestamp
import com.google.firebase.firestore.AggregateSource
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

class FirestoreInboxSource(private val db: FirebaseFirestore) : InboxPopupSource {
    init {
        LocalEnvironment.requireSafe()
        FirebaseBackendGuard.requireFirestore(db)
    }

    private fun collection(uid: String) = db.collection("users/${checkedId(uid)}/notificationInbox")

    private fun settings(uid: String) =
        db.document("users/${checkedId(uid)}/notificationPreferences/settings")

    private fun checkedId(id: String): String = id.also { require(validDocumentId(it)) }

    private fun convert(value: Any?): Any? =
        when (value) {
            is Timestamp -> Instant.ofEpochSecond(value.seconds, value.nanoseconds.toLong())
            is Map<*, *> -> value.entries.associate { it.key.toString() to convert(it.value) }
            is List<*> -> value.map(::convert)
            else -> value
        }

    @Suppress("UNCHECKED_CAST")
    private fun fields(doc: DocumentSnapshot): Fields? = doc.data?.let { convert(it) as Fields }

    override suspend fun page(uid: String, after: InboxCursor?, size: Int): InboxRawPage = request {
        require(size in 1..50)
        var query =
            collection(uid)
                .orderBy("createdAt", Query.Direction.DESCENDING)
                .orderBy(FieldPath.documentId(), Query.Direction.DESCENDING)
        if (after != null)
            query =
                query.startAfter(
                    Timestamp(after.createdAt.epochSecond, after.createdAt.nano),
                    checkedId(after.id),
                )
        val documents = query.limit((size + 1).toLong()).get(Source.SERVER).await().documents
        val selected = documents.take(size)
        val next =
            selected.lastOrNull()?.let { doc ->
                val date =
                    doc.getTimestamp("createdAt") ?: throw InboxException(InboxFailure.INVALID)
                InboxCursor(Instant.ofEpochSecond(date.seconds, date.nanoseconds.toLong()), doc.id)
            }
        InboxRawPage(
            selected.mapNotNull { doc -> fields(doc)?.let { RawDocument(doc.id, it) } },
            next,
            documents.size > size,
        )
    }

    override suspend fun unreadCount(uid: String): Long = request {
        collection(uid)
            .whereEqualTo("isRead", false)
            .whereEqualTo("archivedAt", null)
            .whereEqualTo("deletedAt", null)
            .count()
            .get(AggregateSource.SERVER)
            .await()
            .count
    }

    override suspend fun preferences(uid: String): InboxPreferences = request {
        decodeInboxPreferences(fields(settings(uid).get(Source.SERVER).await()))
    }

    override suspend fun mutate(
        uid: String,
        ids: List<String>,
        mutation: InboxMutation,
        stillCurrent: () -> Boolean,
    ): Unit = request {
        require(ids.size in 1..50 && ids.distinct().size == ids.size)
        val references = ids.map { collection(uid).document(checkedId(it)) }
        db.runTransaction { transaction ->
                if (!stillCurrent()) throw CancellationException("Account scope changed")
                val snapshots = references.map { transaction.get(it) }
                if (snapshots.any { !it.exists() }) throw InboxException(InboxFailure.MISSING)
                val update: Map<String, Any> =
                    when (mutation) {
                        InboxMutation.READ ->
                            mapOf("isRead" to true, "readAt" to FieldValue.serverTimestamp())
                        InboxMutation.UNREAD ->
                            mapOf("isRead" to false, "readAt" to FieldValue.delete())
                        InboxMutation.ARCHIVE ->
                            mapOf(
                                "archivedAt" to FieldValue.serverTimestamp(),
                                "isRead" to true,
                                "readAt" to FieldValue.serverTimestamp(),
                            )
                        InboxMutation.DELETE ->
                            mapOf(
                                "deletedAt" to FieldValue.serverTimestamp(),
                                "isRead" to true,
                                "readAt" to FieldValue.serverTimestamp(),
                            )
                        InboxMutation.POPUP_PRESENTED ->
                            mapOf("popupPresentedAt" to FieldValue.serverTimestamp())
                    }
                if (!stillCurrent()) throw CancellationException("Account scope changed")
                references.forEachIndexed { index, reference ->
                    // Never resurrect or change read state on an already soft-deleted item.
                    if (snapshots[index].getTimestamp("deletedAt") == null)
                        transaction.update(reference, update)
                }
                Unit
            }
            .await()
    }

    override suspend fun savePreferences(
        uid: String,
        preferences: InboxPreferences,
        stillCurrent: () -> Boolean,
    ): Unit = request {
        if (!preferences.valid()) throw InboxException(InboxFailure.INVALID)
        val reference = settings(uid)
        db.runTransaction { transaction ->
                if (!stillCurrent()) throw CancellationException("Account scope changed")
                transaction.get(reference)
                if (!stillCurrent()) throw CancellationException("Account scope changed")
                transaction.set(
                    reference,
                    mapOf(
                        "notificationsEnabled" to preferences.notificationsEnabled,
                        "eventRemindersEnabled" to preferences.eventRemindersEnabled,
                        "reminderLeadMinutes" to preferences.reminderLeadMinutes,
                        "updatedAt" to FieldValue.serverTimestamp(),
                    ),
                )
                Unit
            }
            .await()
    }

    override fun changes(uid: String): Flow<Unit> = callbackFlow {
        val listener =
            collection(uid)
                .orderBy("createdAt", Query.Direction.DESCENDING)
                .limit(50)
                .addSnapshotListener(MetadataChanges.INCLUDE) { snapshot, error ->
                    if (error != null) close(mapped(error))
                    else if (
                        snapshot != null &&
                            !snapshot.metadata.isFromCache &&
                            !snapshot.metadata.hasPendingWrites()
                    )
                        trySend(Unit)
                }
        awaitClose { listener.remove() }
    }

    override fun popupHeads(uid: String): Flow<InboxPopupHead> = callbackFlow {
        val listener =
            collection(uid)
                .orderBy("createdAt", Query.Direction.DESCENDING)
                .orderBy(FieldPath.documentId(), Query.Direction.DESCENDING)
                .limit(50)
                .addSnapshotListener(MetadataChanges.INCLUDE) { snapshot, error ->
                    if (error != null) close(mapped(error))
                    else if (snapshot != null)
                        trySend(
                            InboxPopupHead(
                                snapshot.documents.map { doc ->
                                    RawDocument(doc.id, fields(doc).orEmpty())
                                },
                                snapshot.metadata.isFromCache,
                                snapshot.metadata.hasPendingWrites(),
                            )
                        )
                }
        awaitClose { listener.remove() }
    }

    override suspend fun popupNotice(uid: String, id: String): RawDocument? = request {
        val doc = collection(uid).document(checkedId(id)).get(Source.SERVER).await()
        if (doc.metadata.isFromCache || doc.metadata.hasPendingWrites())
            throw InboxException(InboxFailure.OFFLINE)
        if (!doc.exists()) null else RawDocument(doc.id, fields(doc).orEmpty())
    }

    private fun mapped(error: FirebaseFirestoreException): InboxException =
        InboxException(
            when (error.code) {
                FirebaseFirestoreException.Code.PERMISSION_DENIED,
                FirebaseFirestoreException.Code.UNAUTHENTICATED -> InboxFailure.DENIED
                FirebaseFirestoreException.Code.UNAVAILABLE,
                FirebaseFirestoreException.Code.DEADLINE_EXCEEDED -> InboxFailure.OFFLINE
                FirebaseFirestoreException.Code.NOT_FOUND -> InboxFailure.MISSING
                FirebaseFirestoreException.Code.INVALID_ARGUMENT -> InboxFailure.INVALID
                else -> InboxFailure.UNKNOWN
            },
            error,
        )

    private suspend fun <T> request(block: suspend () -> T): T =
        try {
            block()
        } catch (error: FirebaseFirestoreException) {
            throw mapped(error)
        }
}

fun localInboxSource(context: Context): InboxPopupSource =
    FirestoreInboxSource(AppBackend.firestore(context))
