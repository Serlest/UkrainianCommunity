package at.uac.android.feature.usermanagement

import android.content.Context
import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalCallableFailure
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.CallableGateway
import at.uac.android.core.backend.FirebaseBackendGuard
import at.uac.android.feature.auth.AuthException
import at.uac.android.feature.auth.AuthProblem
import at.uac.android.feature.moderation.ModerationAccess
import at.uac.android.feature.moderation.ModerationException
import at.uac.android.feature.moderation.ModerationFailure
import at.uac.android.feature.moderation.ModerationSession
import com.google.firebase.FirebaseNetworkException
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.DocumentSnapshot
import com.google.firebase.firestore.FieldPath
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.MetadataChanges
import com.google.firebase.firestore.Query
import com.google.firebase.firestore.Source
import java.io.IOException
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.buffer
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.tasks.await

fun localManagedUsersSource(context: Context): ManagedUsersSource =
    FirebaseManagedUsersSource(
        AppBackend.firestore(context),
        AppBackend.auth(context),
        AppBackend.callables(context),
    )

class FirebaseManagedUsersSource(
    private val db: FirebaseFirestore,
    private val auth: FirebaseAuth,
    private val functions: CallableGateway,
) : ManagedUsersSource {
    init {
        FirebaseBackendGuard.requireSameApp(auth, db)
        functions.requireBoundTo(auth)
    }

    private val access = ModerationAccess(db, auth)

    private class Cursor(owner: ModerationSession, consumed: Int, val snapshot: DocumentSnapshot) :
        ManagedUsersCursor(owner, consumed)

    private suspend fun <T> read(session: ModerationSession, operation: suspend () -> T): T =
        try {
            // Caller owns the Auth mutex. No coroutine timeout may detach these actual SDK Tasks.
            access.privileged(session)
            operation().also { access.privileged(session) }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            throw ManagedUsersException(managedUsersFailure(error), error)
        }

    private val fields =
        setOf(
            "displayName",
            "fullName",
            "email",
            "city",
            "selectedFederalState",
            "telegramUsername",
            "globalRole",
            "accountStatus",
            "blockState",
            "isBlocked",
            "warningCount",
            "banExpiresAt",
            "statusReason",
            "createdAt",
            "updatedAt",
        )

    private fun user(snapshot: DocumentSnapshot): ManagedUser =
        ManagedUsersContract.user(
            snapshot.id,
            snapshot.data
                .orEmpty()
                .filterKeys { it in fields }
                .mapValues { (_, value) ->
                    if (value is Timestamp)
                        Instant.ofEpochSecond(value.seconds, value.nanoseconds.toLong())
                    else value
                },
        )

    override suspend fun page(
        session: ModerationSession,
        cursor: ManagedUsersCursor?,
    ): ManagedUsersPage =
        read(session) {
            ManagedUsersContract.cursor(session, cursor)
            if (cursor != null && cursor !is Cursor)
                ManagedUsersContract.fail(ManagedUsersFailure.INVALID)
            var query =
                db.collection("users")
                    .orderBy("createdAt", Query.Direction.DESCENDING)
                    .limit(ManagedUsersContract.PAGE_SIZE.toLong())
            if (cursor is Cursor) query = query.startAfter(cursor.snapshot)
            val docs = query.get(Source.SERVER).await().documents
            access.identity(session)
            val consumed = (cursor?.consumed ?: 0) + docs.size
            val capped = consumed == ManagedUsersContract.MAX_USERS
            ManagedUsersPage(
                docs.map(::user),
                if (docs.size == ManagedUsersContract.PAGE_SIZE && !capped)
                    Cursor(session, consumed, docs.last())
                else null,
                consumed,
                capped,
            )
        }

    override suspend fun search(
        session: ModerationSession,
        query: ManagedUsersQuery,
    ): ManagedUsersSearch =
        read(session) {
            val response =
                functions
                    .getHttpsCallable("searchManagedUsers")
                    .withTimeout(20, TimeUnit.SECONDS)
                    .call(
                        mapOf("query" to query.value, "limit" to ManagedUsersContract.SEARCH_LIMIT)
                    )
                    .await()
            access.identity(session)
            val (ids, total) = ManagedUsersContract.searchIds(response.data)
            val loaded = mutableMapOf<String, ManagedUser>()
            // Manager Rules do not depend on each resource's existence. Missing IDs are simply
            // absent.
            for (batch in ids.chunked(30)) {
                access.identity(session)
                val snapshot =
                    db.collection("users")
                        .whereIn(FieldPath.documentId(), batch)
                        .get(Source.SERVER)
                        .await()
                access.identity(session)
                for (document in snapshot.documents) {
                    if (document.id !in batch)
                        ManagedUsersContract.fail(ManagedUsersFailure.INVALID)
                    loaded[document.id] = user(document)
                }
            }
            ManagedUsersSearch(ids.mapNotNull(loaded::get), total, ids.size - loaded.size)
        }

    override suspend fun user(session: ModerationSession, targetId: String): ManagedUser? =
        read(session) {
            ManagedUsersContract.requireId(targetId)
            db.collection("users")
                .document(targetId)
                .get(Source.SERVER)
                .await()
                .takeIf { it.exists() }
                ?.let(::user)
        }

    override suspend fun security(
        session: ModerationSession,
        targetId: String,
    ): ManagedUserSecurity =
        read(session) {
            ManagedUsersContract.requireId(targetId)
            val response =
                functions
                    .getHttpsCallable("getManagedUserSecurityMetadata")
                    .withTimeout(20, TimeUnit.SECONDS)
                    .call(mapOf("targetUserId" to targetId))
                    .await()
            access.identity(session)
            ManagedUsersContract.security(targetId, response.data)
        }

    override fun invalidations(session: ModerationSession, targetId: String?): Flow<Unit> =
        callbackFlow {
            try {
                access.identity(session)
                targetId?.let(ManagedUsersContract::requireId)
            } catch (error: Exception) {
                close(ManagedUsersException(managedUsersFailure(error), error))
                return@callbackFlow
            }
            val registrations = mutableListOf<com.google.firebase.firestore.ListenerRegistration>()
            fun failure(error: Throwable) {
                close(ManagedUsersException(managedUsersFailure(error), error))
            }
            fun changed() {
                try {
                    access.identity(session)
                    trySend(Unit)
                } catch (error: Exception) {
                    failure(error)
                }
            }
            var actorSeen = false
            var actorState: List<Any?>? = null
            registrations +=
                db.document("users/${session.uid}").addSnapshotListener(MetadataChanges.INCLUDE) {
                    value,
                    error ->
                    if (error != null) failure(error)
                    else if (value != null)
                        try {
                            access.identity(session)
                            if (value.metadata.isFromCache || value.metadata.hasPendingWrites())
                                changed()
                            else {
                                ModerationAccess.requireProfile(session, value.data)
                                val next =
                                    listOf(
                                        value.get("globalRole"),
                                        value.get("accountStatus"),
                                        value.get("blockState"),
                                        value.get("requiresMultiFactorAuth"),
                                    )
                                if (actorSeen && actorState != next) changed()
                                actorSeen = true
                                actorState = next
                            }
                        } catch (error: Exception) {
                            failure(error)
                        }
                }
            targetId?.let { target ->
                var previous: Map<String, Any?>? = null
                var seen = false
                registrations +=
                    db.collection("users").document(target).addSnapshotListener(
                        MetadataChanges.INCLUDE
                    ) { value, error ->
                        if (error != null) failure(error)
                        else if (value != null) {
                            val next = value.data.orEmpty().filterKeys { it in fields }
                            if (
                                !seen ||
                                    previous != next ||
                                    value.metadata.isFromCache ||
                                    value.metadata.hasPendingWrites()
                            )
                                changed()
                            previous = next
                            seen = true
                        }
                    }
            }
            awaitClose { registrations.forEach { it.remove() } }
        }
        .buffer(Channel.CONFLATED)
}

fun managedUsersFailure(error: Throwable): ManagedUsersFailure =
    when (error) {
        is ManagedUsersException -> error.failure
        is CancellationException -> ManagedUsersFailure.STALE
        is AuthException ->
            when (error.problem) {
                AuthProblem.SESSION_CHANGED -> ManagedUsersFailure.STALE
                AuthProblem.NETWORK -> ManagedUsersFailure.OFFLINE
                AuthProblem.PERMISSION_DENIED,
                AuthProblem.DISABLED -> ManagedUsersFailure.DENIED
                AuthProblem.SECOND_FACTOR_REQUIRED,
                AuthProblem.MFA_UNCONFIRMED,
                AuthProblem.VERIFICATION_PENDING,
                AuthProblem.LEGAL_CHANGED,
                AuthProblem.LEGAL_UNCONFIRMED -> ManagedUsersFailure.NOT_READY
                else -> ManagedUsersFailure.UNKNOWN
            }
        is ModerationException ->
            when (error.failure) {
                ModerationFailure.SIGN_IN -> ManagedUsersFailure.SIGN_IN
                ModerationFailure.NOT_READY -> ManagedUsersFailure.NOT_READY
                ModerationFailure.DENIED -> ManagedUsersFailure.DENIED
                ModerationFailure.OFFLINE -> ManagedUsersFailure.OFFLINE
                ModerationFailure.INDEX -> ManagedUsersFailure.INDEX
                ModerationFailure.INVALID -> ManagedUsersFailure.INVALID
                ModerationFailure.MISSING -> ManagedUsersFailure.MISSING
                ModerationFailure.STALE -> ManagedUsersFailure.STALE
                ModerationFailure.UNKNOWN -> ManagedUsersFailure.UNKNOWN
            }
        is FirebaseFirestoreException ->
            when (error.code) {
                FirebaseFirestoreException.Code.PERMISSION_DENIED,
                FirebaseFirestoreException.Code.UNAUTHENTICATED -> ManagedUsersFailure.DENIED
                FirebaseFirestoreException.Code.UNAVAILABLE,
                FirebaseFirestoreException.Code.DEADLINE_EXCEEDED -> ManagedUsersFailure.OFFLINE
                FirebaseFirestoreException.Code.FAILED_PRECONDITION -> ManagedUsersFailure.INDEX
                FirebaseFirestoreException.Code.NOT_FOUND -> ManagedUsersFailure.MISSING
                FirebaseFirestoreException.Code.INVALID_ARGUMENT -> ManagedUsersFailure.INVALID
                else -> ManagedUsersFailure.UNKNOWN
            }
        is LocalCallableException ->
            when (error.code) {
                LocalCallableFailure.UNAUTHENTICATED -> ManagedUsersFailure.SIGN_IN
                LocalCallableFailure.PERMISSION_DENIED -> ManagedUsersFailure.DENIED
                LocalCallableFailure.FAILED_PRECONDITION -> ManagedUsersFailure.NOT_READY
                LocalCallableFailure.NOT_FOUND -> ManagedUsersFailure.MISSING
                LocalCallableFailure.INVALID_ARGUMENT,
                LocalCallableFailure.DATA_LOSS -> ManagedUsersFailure.INVALID
                LocalCallableFailure.UNAVAILABLE,
                LocalCallableFailure.DEADLINE_EXCEEDED -> ManagedUsersFailure.OFFLINE
                else -> ManagedUsersFailure.UNKNOWN
            }
        is FirebaseNetworkException,
        is IOException -> ManagedUsersFailure.OFFLINE
        else -> ManagedUsersFailure.UNKNOWN
    }
