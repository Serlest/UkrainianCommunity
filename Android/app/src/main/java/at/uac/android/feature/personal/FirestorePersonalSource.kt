package at.uac.android.feature.personal

import android.content.Context
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.FirebaseBackendGuard
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.browse.Fields
import at.uac.android.feature.browse.RawDocument
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.DocumentSnapshot
import com.google.firebase.firestore.FieldPath
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.Query
import com.google.firebase.firestore.Source
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeout

/**
 * Every read is server-only; every write uses an online transaction, never an offline mutation
 * queue.
 */
class FirestorePersonalSource(private val db: FirebaseFirestore) : PersonalSource {
    init {
        LocalEnvironment.requireSafe()
        FirebaseBackendGuard.requireFirestore(db)
    }

    private fun convert(value: Any?): Any? =
        when (value) {
            is Timestamp -> Instant.ofEpochSecond(value.seconds, value.nanoseconds.toLong())
            is Map<*, *> -> value.entries.associate { it.key.toString() to convert(it.value) }
            is List<*> -> value.map(::convert)
            else -> value
        }

    @Suppress("UNCHECKED_CAST")
    private fun row(snapshot: DocumentSnapshot): RawDocument? =
        snapshot.data?.let {
            RawDocument(snapshot.id, convert(it) as Fields)
        }

    private suspend fun <T> request(operation: suspend () -> T): T =
        try {
            operation()
        } catch (error: CancellationException) {
            throw error
        } catch (error: PersonalException) {
            throw error
        } catch (error: FirebaseFirestoreException) {
            throw PersonalException(
                when (error.code) {
                    FirebaseFirestoreException.Code.PERMISSION_DENIED,
                    FirebaseFirestoreException.Code.UNAUTHENTICATED -> PersonalFailure.DENIED
                    FirebaseFirestoreException.Code.UNAVAILABLE,
                    FirebaseFirestoreException.Code.DEADLINE_EXCEEDED -> PersonalFailure.OFFLINE
                    FirebaseFirestoreException.Code.NOT_FOUND -> PersonalFailure.MISSING
                    FirebaseFirestoreException.Code.INVALID_ARGUMENT -> PersonalFailure.INVALID
                    else -> PersonalFailure.UNKNOWN
                },
                error,
            )
        }

    override suspend fun profile(uid: String): PersonalProfile = request {
        require(validDocumentId(uid))
        val data =
            row(db.document("users/$uid").get(Source.SERVER).await())
                ?: throw PersonalException(PersonalFailure.MISSING)
        decodePersonalProfile(uid, data.fields)
    }

    override suspend fun saveProfile(
        uid: String,
        draft: ProfileDraft,
        stillCurrent: () -> Boolean,
    ): PersonalProfile = request {
        require(validDocumentId(uid))
        if (!draft.validFor(uid) || draft != draft.normalized())
            throw PersonalException(PersonalFailure.INVALID)
        val user = db.document("users/$uid")
        val public = db.document("publicProfiles/$uid")
        val privateFields =
            mapOf(
                "fullName" to draft.fullName,
                "displayName" to draft.displayName,
                "city" to draft.city,
                "bio" to draft.bio,
                "telegramUsername" to draft.telegramUsername.ifEmpty { null },
                "selectedFederalState" to draft.federalState,
                "avatarURL" to draft.avatarUrl.ifEmpty { null }.let { it ?: FieldValue.delete() },
                "updatedAt" to FieldValue.serverTimestamp(),
            )
        val publicFields =
            mutableMapOf<String, Any>(
                    "id" to uid,
                    "displayName" to draft.displayName,
                    "city" to draft.city,
                    "federalState" to draft.federalState,
                    "updatedAt" to FieldValue.serverTimestamp(),
                )
                .apply { if (draft.avatarUrl.isNotEmpty()) put("avatarURL", draft.avatarUrl) }
        db.runTransaction { transaction ->
                if (!stillCurrent()) throw CancellationException("Account scope changed")
                val previous = transaction.get(user)
                if (!previous.exists()) throw PersonalException(PersonalFailure.MISSING)
                if (previous.getString("id") != uid)
                    throw PersonalException(PersonalFailure.INVALID)
                if (!stillCurrent()) throw CancellationException("Account scope changed")
                // Update only the eight self-editable fields; roles, email, legal receipts and
                // status remain intact.
                transaction.update(user, privateFields)
                transaction.set(public, publicFields)
            }
            .await()
        if (!stillCurrent()) throw CancellationException("Account scope changed")
        val updated = withTimeout(5_000) { profile(uid) }
        val published = withTimeout(5_000) { public.get(Source.SERVER).await() }
        if (
            updated.draft != draft ||
                published.getString("id") != uid ||
                published.getString("displayName") != draft.displayName ||
                published.getString("city") != draft.city ||
                published.getString("federalState") != draft.federalState ||
                published.getString("avatarURL").orEmpty() != draft.avatarUrl
        )
            throw PersonalException(PersonalFailure.UNKNOWN)
        updated
    }

    override suspend fun marker(marker: PersonalMarker): RawDocument? = request {
        row(db.document(marker.path).get(Source.SERVER).await())
    }

    override suspend fun setMarker(
        marker: PersonalMarker,
        enabled: Boolean,
        stillCurrent: () -> Boolean,
    ) {
        setMarkerConfirmed(marker, enabled, stillCurrent)
    }

    override suspend fun setMarkerConfirmed(
        marker: PersonalMarker,
        enabled: Boolean,
        stillCurrent: () -> Boolean,
    ): Boolean = request {
        val reference = db.document(marker.path)
        db.runTransaction { transaction ->
                if (!stillCurrent()) throw CancellationException("Account scope changed")
                val existing = row(transaction.get(reference))
                if (existing != null && !marker.matches(existing))
                    throw PersonalException(PersonalFailure.INVALID)
                if ((existing != null) != enabled) {
                    if (enabled) {
                        val target = transaction.get(db.document(marker.target.key))
                        if (!target.exists()) throw PersonalException(PersonalFailure.MISSING)
                        if (target.getString("moderationStatus") != "approved")
                            throw PersonalException(PersonalFailure.DENIED)
                        if (!stillCurrent()) throw CancellationException("Account scope changed")
                        transaction.set(
                            reference,
                            marker.identityFields() + ("createdAt" to FieldValue.serverTimestamp()),
                        )
                    } else {
                        if (!stillCurrent()) throw CancellationException("Account scope changed")
                        transaction.delete(reference)
                    }
                }
                // Like/subscriber counters are owned by backend triggers, not this client.
                (existing != null) != enabled
            }
            .await()
    }

    private suspend fun page(query: Query, after: String?, size: Int): MarkerPage = request {
        require(size in 1..50)
        require(after == null || validDocumentId(after))
        var ordered = query.orderBy(FieldPath.documentId())
        if (after != null) ordered = ordered.startAfter(after)
        val rows =
            ordered
                .limit((size + 1).toLong())
                .get(Source.SERVER)
                .await()
                .documents
                .mapNotNull(::row)
        val selected = rows.take(size)
        MarkerPage(selected, selected.lastOrNull()?.id ?: after, rows.size > size)
    }

    override suspend fun bookmarkPage(
        uid: String,
        kind: ContentKind,
        after: String?,
        size: Int,
    ): MarkerPage {
        require(validDocumentId(uid))
        val collection = PersonalTarget(kind, "collection-key").bookmarkCollection
        return page(db.collection("users/$uid/$collection"), after, size)
    }

    override suspend fun relationPage(uid: String, after: String?, size: Int): MarkerPage {
        require(validDocumentId(uid))
        return page(db.collection("likes").whereEqualTo("userId", uid), after, size)
    }

    override suspend fun approvedContent(kind: ContentKind, ids: List<String>): List<RawDocument> =
        approvedContentCurrent(kind, ids) { true }

    override suspend fun approvedContentCurrent(
        kind: ContentKind,
        ids: List<String>,
        stillCurrent: () -> Boolean,
    ): List<RawDocument> = request {
        require(ids.size in 1..10 && ids.all(::validDocumentId))
        // The already-validated named app is the only identity source; never access a default
        // Firebase app.
        val auth = FirebaseAuth.getInstance(db.app)
        val uid = auth.currentUser?.uid
        fun current() {
            if (!stillCurrent() || auth.currentUser?.uid != uid)
                throw CancellationException("Account scope changed")
        }
        val rows = mutableListOf<RawDocument>()
        // An orphan document-ID `in` query can be denied by content Rules even when the
        // saved-marker query succeeded.
        // Resolve at most ten targets, sequentially, so one missing/private target cannot hide an
        // approved neighbour.
        for (id in ids.distinct()) {
            current()
            val value =
                try {
                    row(db.collection(kind.collection).document(id).get(Source.SERVER).await())
                } catch (error: FirebaseFirestoreException) {
                    if (
                        error.code in
                            setOf(
                                FirebaseFirestoreException.Code.PERMISSION_DENIED,
                                FirebaseFirestoreException.Code.NOT_FOUND,
                            )
                    )
                        null
                    else throw error
                }
            current()
            if (
                value != null &&
                    value.fields["moderationStatus"] == "approved" &&
                    (kind == ContentKind.ORGANIZATIONS ||
                        value.fields["sourceType"] == "organization")
            )
                rows += value
        }
        rows
    }
}

fun localPersonalSource(context: Context): PersonalSource =
    FirestorePersonalSource(AppBackend.firestore(context))
