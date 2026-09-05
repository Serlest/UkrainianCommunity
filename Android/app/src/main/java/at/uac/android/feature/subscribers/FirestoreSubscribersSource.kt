package at.uac.android.feature.subscribers

import android.content.Context
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.FirebaseBackendGuard
import at.uac.android.feature.browse.RawDocument
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.DocumentSnapshot
import com.google.firebase.firestore.FieldPath
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.firestore.MetadataChanges
import com.google.firebase.firestore.Query
import com.google.firebase.firestore.Source
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeout

fun localSubscribersSource(context: Context, current: () -> SubscriberSession?): SubscribersSource =
    FirestoreSubscribersSource(
        AppBackend.firestore(context),
        AppBackend.auth(context),
        current,
    )

/** No callable, write, private user document, default Firebase app, or cloud fallback. */
class FirestoreSubscribersSource(
    private val db: FirebaseFirestore,
    private val auth: FirebaseAuth,
    private val current: () -> SubscriberSession?,
) : SubscribersSource {
    init {
        LocalEnvironment.requireSafe()
        FirebaseBackendGuard.requireSameApp(auth, db)
    }

    private fun identity(session: SubscriberSession) {
        if (current() != session || auth.currentUser?.uid != session.uid)
            throw CancellationException("Subscriber identity changed")
        if (
            !session.ready ||
                auth.currentUser?.isAnonymous != false ||
                auth.currentUser?.isEmailVerified != true
        )
            SubscribersContract.fail(SubscribersFailure.NOT_READY)
    }

    private fun decode(value: Any?): Any? =
        when (value) {
            is Timestamp -> Instant.ofEpochSecond(value.seconds, value.nanoseconds.toLong())
            is Map<*, *> -> value.entries.associate { it.key.toString() to decode(it.value) }
            is List<*> -> value.map(::decode)
            else -> value
        }

    private fun raw(snapshot: DocumentSnapshot) =
        RawDocument(snapshot.id, snapshot.data.orEmpty().mapValues { decode(it.value) })

    private suspend fun <T> read(session: SubscriberSession, action: suspend () -> T): T =
        try {
            identity(session)
            withTimeout(15_000) { action() }.also { identity(session) }
        } catch (error: TimeoutCancellationException) {
            throw SubscribersException(SubscribersFailure.OFFLINE, error)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            throw SubscribersException(subscribersFailure(error), error)
        }

    override suspend fun organization(id: String, session: SubscriberSession): RawDocument? =
        read(session) {
            if (!SubscribersContract.organizationId(id))
                SubscribersContract.fail(SubscribersFailure.INVALID)
            db.collection("organizations")
                .document(id)
                .get(Source.SERVER)
                .await()
                .takeIf { it.exists() }
                ?.let(::raw)
        }

    private fun query(id: String) =
        db.collection("likes")
            .whereEqualTo("subscribedOrganizationId", id)
            .orderBy("createdAt", Query.Direction.DESCENDING)
            .orderBy(FieldPath.documentId(), Query.Direction.DESCENDING)

    override suspend fun page(
        id: String,
        after: SubscriberCursor?,
        session: SubscriberSession,
    ): List<RawDocument> =
        read(session) {
            if (
                !SubscribersContract.organizationId(id) ||
                    !SubscribersContract.validCursor(id, after)
            )
                SubscribersContract.fail(SubscribersFailure.INVALID)
            var query = query(id).limit((SubscribersContract.PAGE_SIZE + 1).toLong())
            if (after != null)
                query =
                    query.startAfter(
                        Timestamp(after.createdAt.epochSecond, after.createdAt.nano),
                        after.documentId,
                    )
            query.get(Source.SERVER).await().documents.map(::raw)
        }

    override suspend fun profiles(
        ids: List<String>,
        session: SubscriberSession,
    ): List<RawDocument> =
        read(session) {
            if (
                ids.isEmpty() ||
                    ids.size > 10 ||
                    ids.distinct().size != ids.size ||
                    ids.any { !SubscribersContract.userId(it) }
            )
                SubscribersContract.fail(SubscribersFailure.INVALID)
            db.collection("publicProfiles")
                .whereIn(FieldPath.documentId(), ids)
                .get(Source.SERVER)
                .await()
                .documents
                .map(::raw)
        }

    override fun changes(id: String, session: SubscriberSession): Flow<Result<Unit>> =
        callbackFlow {
            identity(session)
            if (!SubscribersContract.organizationId(id))
                SubscribersContract.fail(SubscribersFailure.INVALID)
            val listeners = mutableListOf<ListenerRegistration>()
            fun send(result: Result<Unit>) {
                try {
                    identity(session)
                    trySend(result)
                } catch (error: CancellationException) {
                    close(error)
                } catch (error: Exception) {
                    trySend(Result.failure(error))
                }
            }
            var organizationServerSeen = false
            var lastOrganization: RawDocument? = null
            var referencesServerSeen = false
            var lastReferences: List<RawDocument>? = null
            try {
                listeners +=
                    db.collection("organizations").document(id).addSnapshotListener(
                        MetadataChanges.INCLUDE
                    ) { value, error ->
                        when {
                            error != null ->
                                send(
                                    Result.failure(
                                        SubscribersException(subscribersFailure(error), error)
                                    )
                                )
                            value == null -> Unit
                            value.metadata.isFromCache || value.metadata.hasPendingWrites() ->
                                if (organizationServerSeen)
                                    // Metadata alone does not prove a network outage. This is only
                                    // an invalidation:
                                    // the consumer hides its previous rows and rechecks bounded
                                    // SERVER reads.
                                    send(Result.success(Unit))
                                else Unit
                            !value.exists() ->
                                send(
                                    Result.failure(SubscribersException(SubscribersFailure.MISSING))
                                )
                            else -> {
                                val fresh = raw(value)
                                if (fresh.fields["moderationStatus"] != "approved")
                                    send(
                                        Result.failure(
                                            SubscribersException(SubscribersFailure.DENIED)
                                        )
                                    )
                                else if (!organizationServerSeen || lastOrganization != fresh)
                                    send(Result.success(Unit))
                                organizationServerSeen = true
                                lastOrganization = fresh
                            }
                        }
                    }
                listeners +=
                    query(id)
                        .limit((SubscribersContract.MAX_SUBSCRIBERS + 1).toLong())
                        .addSnapshotListener(MetadataChanges.INCLUDE) { value, error ->
                            when {
                                error != null ->
                                    send(
                                        Result.failure(
                                            SubscribersException(subscribersFailure(error), error)
                                        )
                                    )
                                value == null -> Unit
                                value.metadata.isFromCache || value.metadata.hasPendingWrites() ->
                                    if (referencesServerSeen) send(Result.success(Unit)) else Unit
                                else -> {
                                    val fresh = value.documents.map(::raw)
                                    if (!referencesServerSeen || lastReferences != fresh)
                                        send(Result.success(Unit))
                                    referencesServerSeen = true
                                    lastReferences = fresh
                                }
                            }
                        }
                awaitClose {}
            } finally {
                listeners.forEach { it.remove() }
            }
        }
}

fun subscribersFailure(error: Throwable): SubscribersFailure =
    when (error) {
        is SubscribersException -> error.failure
        is FirebaseFirestoreException ->
            when (error.code.name) {
                "PERMISSION_DENIED",
                "UNAUTHENTICATED" -> SubscribersFailure.DENIED
                "NOT_FOUND" -> SubscribersFailure.MISSING
                "UNAVAILABLE",
                "DEADLINE_EXCEEDED" -> SubscribersFailure.OFFLINE
                "FAILED_PRECONDITION" -> SubscribersFailure.INDEX
                "INVALID_ARGUMENT" -> SubscribersFailure.INVALID
                else -> SubscribersFailure.UNKNOWN
            }
        else -> SubscribersFailure.UNKNOWN
    }
