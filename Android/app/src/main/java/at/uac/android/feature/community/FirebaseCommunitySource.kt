package at.uac.android.feature.community

import android.content.Context
import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.CallableGateway
import at.uac.android.core.backend.FirebaseBackendGuard
import at.uac.android.feature.auth.AuthException
import at.uac.android.feature.auth.AuthProblem
import at.uac.android.feature.auth.AuthStore
import at.uac.android.feature.browse.Fields
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.browse.string
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.DocumentSnapshot
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.MetadataChanges
import com.google.firebase.firestore.Query
import com.google.firebase.firestore.Source
import java.io.IOException
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.tasks.await

class AuthCommunityMutationGate(private val auth: AuthStore) : CommunityMutationGate {
    override suspend fun <T> withSession(session: CommunitySession, operation: suspend () -> T): T =
        try {
            auth.withReadySession(session.uid, session.revision, operation)
        } catch (error: AuthException) {
            if (error.problem == AuthProblem.SESSION_CHANGED)
                throw CancellationException("Community session changed")
            throw CommunityException(CommunityFailure.NOT_READY, error)
        }
}

fun localCommunitySource(context: Context): CommunitySource =
    FirebaseCommunitySource(
        AppBackend.firestore(context),
        AppBackend.auth(context),
        AppBackend.callables(context),
    )

/**
 * Public streams and server-only read-back; no queued client creates, edits or registration writes.
 */
class FirebaseCommunitySource(
    private val db: FirebaseFirestore,
    private val auth: FirebaseAuth,
    private val functions: CallableGateway,
) : CommunitySource {
    init {
        LocalEnvironment.requireSafe()
        FirebaseBackendGuard.requireSameApp(auth, db)
        functions.requireBoundTo(auth)
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
        snapshot.data?.let { RawDocument(snapshot.id, convert(it) as Fields) }

    private suspend fun <T> request(action: suspend () -> T): T =
        try {
            action()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            throw CommunityException(communityFailure(error), error)
        }

    private fun requireIdentity(uid: String) {
        val identity = auth.currentUser
        if (identity?.uid != uid) throw CancellationException("Firebase identity changed")
        if (!identity.isEmailVerified || identity.isAnonymous)
            throw CommunityException(CommunityFailure.NOT_READY)
    }

    override suspend fun parent(target: CommunityTarget): RawDocument = request {
        row(db.document(target.path).get(Source.SERVER).await())
            ?: throw CommunityException(CommunityFailure.MISSING)
    }

    override suspend fun registration(eventId: String, uid: String): RawDocument? = request {
        requireIdentity(uid)
        row(
            db.collection("registrations")
                .document(CommunityContract.registrationId(eventId, uid))
                .get(Source.SERVER)
                .await()
        )
    }

    override suspend fun call(name: String, data: Fields, uid: String): Any? = request {
        require(name in setOf("registerForEvent", "unregisterFromEvent", "saveComment"))
        requireIdentity(uid)
        // Deadline belongs to the transport; cancellation must not release the Auth mutex early.
        functions.getHttpsCallable(name).withTimeout(20, TimeUnit.SECONDS).call(data).await().data
    }

    override suspend fun comment(target: CommunityTarget, id: String): RawDocument? = request {
        require(communityId(id))
        row(db.document("${target.path}/comments/$id").get(Source.SERVER).await())
    }

    override fun comments(target: CommunityTarget): Flow<Result<CommentPage>> = callbackFlow {
        val listener =
            db.collection("${target.path}/comments")
                .whereEqualTo("isDeleted", false)
                .orderBy("createdAt", Query.Direction.DESCENDING)
                .limit(100)
                .addSnapshotListener(MetadataChanges.INCLUDE) { snapshot, error ->
                    if (error != null)
                        trySend(Result.failure(CommunityException(communityFailure(error), error)))
                    else if (snapshot != null)
                        trySend(
                            runCatching {
                                var withheld = 0
                                val comments =
                                    snapshot.documents
                                        .mapNotNull { document ->
                                            val decoded =
                                                row(document)?.let {
                                                    CommunityContract.comment(target, it)
                                                }
                                            if (decoded == null) withheld++
                                            decoded
                                        }
                                        .reversed()
                                CommentPage(
                                    comments,
                                    snapshot.metadata.isFromCache ||
                                        snapshot.metadata.hasPendingWrites(),
                                    withheld,
                                )
                            }
                        )
                }
        awaitClose { listener.remove() }
    }

    override suspend fun moderation(target: CommunityTarget, session: CommunitySession): Boolean =
        request {
            requireIdentity(session.uid)
            val parent = parent(target).fields
            val organizationId = parent.string("organizationId")
            val organization =
                if (
                    target.type != "organization" &&
                        session.role !in setOf("owner", "admin") &&
                        parent["sourceType"] == "organization" &&
                        communityId(organizationId)
                )
                    row(db.document("organizations/$organizationId").get(Source.SERVER).await())
                        ?.fields
                else null
            CommunityContract.canModerate(target, parent, organization, session)
        }

    override suspend fun deleteComment(
        target: CommunityTarget,
        id: String,
        uid: String,
        stillCurrent: () -> Boolean,
    ) = request {
        require(communityId(id))
        requireIdentity(uid)
        val reference = db.document("${target.path}/comments/$id")
        db.runTransaction { transaction ->
                if (!stillCurrent()) throw CancellationException("Community session changed")
                requireIdentity(uid)
                val parent = transaction.get(db.document(target.path))
                val existing = row(transaction.get(reference))
                if (!parent.exists()) throw CommunityException(CommunityFailure.MISSING)
                if (existing != null) {
                    // Strict context check also protects against malformed/foreign legacy records.
                    CommunityContract.comment(target, existing)
                    if (!stillCurrent()) throw CancellationException("Community session changed")
                    transaction.delete(
                        reference
                    ) // Exact scoped moderator authority remains enforced by Rules.
                }
            }
            .await()
        Unit
    }
}

fun communityFailure(error: Throwable): CommunityFailure =
    when (error) {
        is CommunityException -> error.failure
        is LocalCallableException ->
            communityCallableFailure(
                error.code.name,
                (error.details as? Map<*, *>)?.get("reason") as? String,
            )
        is FirebaseFirestoreException ->
            when (error.code) {
                FirebaseFirestoreException.Code.UNAUTHENTICATED,
                FirebaseFirestoreException.Code.PERMISSION_DENIED -> CommunityFailure.DENIED
                FirebaseFirestoreException.Code.UNAVAILABLE,
                FirebaseFirestoreException.Code.DEADLINE_EXCEEDED -> CommunityFailure.OFFLINE
                FirebaseFirestoreException.Code.NOT_FOUND -> CommunityFailure.MISSING
                FirebaseFirestoreException.Code.INVALID_ARGUMENT -> CommunityFailure.INVALID
                else -> CommunityFailure.UNKNOWN
            }
        is IOException -> CommunityFailure.OFFLINE
        else -> CommunityFailure.UNKNOWN
    }

fun communityCallableFailure(code: String, reason: String?): CommunityFailure =
    when (code) {
        "UNAUTHENTICATED" -> CommunityFailure.SIGN_IN
        "PERMISSION_DENIED" -> CommunityFailure.DENIED
        "NOT_FOUND" -> CommunityFailure.MISSING
        "UNAVAILABLE",
        "DEADLINE_EXCEEDED" -> CommunityFailure.OFFLINE
        "UNCONFIRMED" -> CommunityFailure.UNCONFIRMED
        "DATA_LOSS" -> CommunityFailure.INVALID
        "RESOURCE_EXHAUSTED" ->
            if (reason == "event-full") CommunityFailure.FULL else CommunityFailure.UNKNOWN
        "INVALID_ARGUMENT" ->
            if (reason == "objectionable-content") CommunityFailure.REJECTED_TEXT
            else CommunityFailure.INVALID
        "FAILED_PRECONDITION" ->
            when (reason) {
                "event-cancelled" -> CommunityFailure.CANCELLED
                "event-past" -> CommunityFailure.PAST
                "registration-not-required" -> CommunityFailure.NOT_REQUIRED
                "event-not-approved" -> CommunityFailure.NOT_APPROVED
                "invalid-registration-config",
                "invalid-registration-counter" -> CommunityFailure.INVALID
                else -> CommunityFailure.NOT_READY
            }
        else -> CommunityFailure.UNKNOWN
    }
