package at.uac.android.feature.authoring

import android.content.Context
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.FirebaseBackendGuard
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.browse.Fields
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.organization.OrganizationContract
import at.uac.android.feature.organization.OrganizationRecord
import at.uac.android.feature.organization.OrganizationSession
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.DocumentSnapshot
import com.google.firebase.firestore.FieldPath
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.MetadataChanges
import com.google.firebase.firestore.Query
import com.google.firebase.firestore.Source
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeout

fun localAuthoringSource(context: Context): AuthoringSource =
    FirebaseAuthoringSource(AppBackend.firestore(context), AppBackend.auth(context))

class FirebaseAuthoringSource(private val db: FirebaseFirestore, private val auth: FirebaseAuth) :
    AuthoringSource {
    init {
        LocalEnvironment.requireSafe()
        FirebaseBackendGuard.requireSameApp(auth, db)
    }

    private fun identity(session: OrganizationSession) {
        if (auth.currentUser?.uid != session.uid)
            throw CancellationException("Authoring identity changed")
        if (
            !session.ready ||
                auth.currentUser?.isAnonymous != false ||
                auth.currentUser?.isEmailVerified != true
        )
            AuthoringContract.fail(AuthoringFailure.NOT_READY)
    }

    private fun organizationQuery(id: String): Query {
        if (!AuthoringContract.id(id)) AuthoringContract.invalid()
        return db.collection("organizations")
            .whereGreaterThanOrEqualTo(FieldPath.documentId(), id)
            .whereLessThanOrEqualTo(FieldPath.documentId(), id)
            .whereEqualTo("moderationStatus", "approved")
            .limit(1)
    }

    private fun contentQuery(
        id: String,
        kind: ContentKind,
        status: AuthoringStatus,
        session: OrganizationSession,
    ): Query {
        if (!AuthoringContract.id(id) || kind !in AuthoringContract.kinds)
            AuthoringContract.invalid()
        var query: Query =
            db.collection(kind.collection)
                .whereEqualTo("sourceType", "organization")
                .whereEqualTo("organizationId", id)
                .whereEqualTo("moderationStatus", status.wire)
        if (status == AuthoringStatus.SCHEDULED) query = query.whereEqualTo("authorId", session.uid)
        return query
    }

    private fun pageQuery(
        id: String,
        kind: ContentKind,
        status: AuthoringStatus,
        session: OrganizationSession,
    ) =
        contentQuery(id, kind, status, session)
            .orderBy("createdAt", Query.Direction.DESCENDING)
            .orderBy(FieldPath.documentId(), Query.Direction.DESCENDING)

    private fun decoded(value: Any?): Any? =
        when (value) {
            is Timestamp -> Instant.ofEpochSecond(value.seconds, value.nanoseconds.toLong())
            is Map<*, *> -> value.entries.associate { it.key.toString() to decoded(it.value) }
            is List<*> -> value.map(::decoded)
            else -> value
        }

    private fun encoded(value: Any?): Any? =
        when (value) {
            is Instant -> Timestamp(value.epochSecond, value.nano)
            is Map<*, *> -> value.entries.associate { it.key.toString() to encoded(it.value) }
            is List<*> -> value.map(::encoded)
            else -> value
        }

    @Suppress("UNCHECKED_CAST")
    private fun raw(snapshot: DocumentSnapshot) =
        RawDocument(
            snapshot.id,
            decoded(snapshot.data ?: AuthoringContract.fail(AuthoringFailure.MISSING)) as Fields,
        )

    private suspend fun <T> read(session: OrganizationSession, action: suspend () -> T): T =
        try {
            identity(session)
            withTimeout(15_000) { action() }.also { identity(session) }
        } catch (error: TimeoutCancellationException) {
            throw AuthoringException(AuthoringFailure.OFFLINE, cause = error)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            throw AuthoringException(authoringFailure(error), cause = error)
        }

    override suspend fun organization(
        id: String,
        session: OrganizationSession,
    ): OrganizationRecord? =
        read(session) {
            organizationQuery(id).get(Source.SERVER).await().documents.firstOrNull()?.let {
                OrganizationContract.record(raw(it), session)
            }
        }

    override suspend fun page(
        organizationId: String,
        kind: ContentKind,
        status: AuthoringStatus,
        after: AuthoringCursor?,
        session: OrganizationSession,
    ): AuthoringPage =
        read(session) {
            var query =
                pageQuery(organizationId, kind, status, session)
                    .limit((AuthoringContract.PAGE_SIZE + 1).toLong())
            if (after != null) {
                if (!AuthoringContract.id(after.id)) AuthoringContract.invalid()
                query =
                    query.startAfter(
                        Timestamp(after.createdAt.epochSecond, after.createdAt.nano),
                        after.id,
                    )
            }
            AuthoringContract.page(
                query.get(Source.SERVER).await().documents.map(::raw),
                kind,
                organizationId,
                status,
                session,
                after,
            )
        }

    override suspend fun find(
        organizationId: String,
        kind: ContentKind,
        id: String,
        session: OrganizationSession,
    ): AuthoringItem? =
        read(session) {
            if (!AuthoringContract.id(id)) AuthoringContract.invalid()
            // Separate statuses preserve the Rules distinction between team moderation and own-only
            // drafts.
            var result: AuthoringItem? = null
            for (status in AuthoringStatus.entries) {
                val snapshot =
                    contentQuery(organizationId, kind, status, session)
                        .whereGreaterThanOrEqualTo(FieldPath.documentId(), id)
                        .whereLessThanOrEqualTo(FieldPath.documentId(), id)
                        .limit(1)
                        .get(Source.SERVER)
                        .await()
                snapshot.documents.firstOrNull()?.let {
                    result = AuthoringContract.item(kind, raw(it), organizationId, status, session)
                }
                if (result != null) break
            }
            result
        }

    override fun changes(
        organizationId: String,
        kind: ContentKind,
        status: AuthoringStatus,
        session: OrganizationSession,
        target: AuthoringItem?,
    ): Flow<Result<Unit>> = callbackFlow {
        identity(session)
        val queries =
            mutableListOf(
                organizationQuery(organizationId),
                pageQuery(organizationId, kind, status, session)
                    .limit(AuthoringContract.PAGE_SIZE.toLong()),
            )
        if (target != null) {
            if (target.organizationId != organizationId || !AuthoringContract.id(target.id))
                AuthoringContract.invalid()
            queries +=
                contentQuery(organizationId, target.kind, target.status, session)
                    .whereGreaterThanOrEqualTo(FieldPath.documentId(), target.id)
                    .whereLessThanOrEqualTo(FieldPath.documentId(), target.id)
                    .limit(1)
        }
        val listeners = queries.map { query ->
            query.addSnapshotListener(MetadataChanges.INCLUDE) { snapshot, error ->
                if (error != null)
                    trySend(
                        Result.failure(AuthoringException(authoringFailure(error), cause = error))
                    )
                else if (
                    snapshot != null &&
                        !snapshot.metadata.isFromCache &&
                        !snapshot.metadata.hasPendingWrites()
                )
                    trySend(Result.success(Unit))
            }
        }
        awaitClose { listeners.forEach { it.remove() } }
    }

    override suspend fun commit(
        submission: AuthoringSubmission,
        organization: OrganizationRecord,
        session: OrganizationSession,
    ) {
        identity(session)
        if (
            submission.organizationId != organization.id ||
                submission.kind !in AuthoringContract.kinds ||
                !AuthoringContract.id(submission.id)
        )
            AuthoringContract.invalid()
        val base = submission.base
        if (base == null) {
            // New documents are freshly minted UUIDs, never a route/user-entered target. Reuse the
            // same ID on read-back recovery.
            if (
                runCatching { UUID.fromString(submission.id).toString() }.getOrNull() !=
                    submission.id.lowercase() ||
                    submission.fields["authorId"] != session.uid ||
                    submission.fields["id"] != submission.id ||
                    submission.fields["organizationId"] != organization.id ||
                    submission.fields["sourceType"] != "organization" ||
                    listOf("likeCount", "viewCount", "commentCount", "registeredCount").any {
                        submission.fields[it] != null &&
                            (submission.fields[it] as? Number)?.toLong() != 0L
                    }
            )
                AuthoringContract.invalid()
        } else if (submission.fields.keys.any { it !in AuthoringContract.editableFields })
            AuthoringContract.invalid()
        try {
            // An online transaction reads current authority. Do not detach/timeout SDK await under
            // the Auth identity mutex.
            db.runTransaction { transaction ->
                    identity(session)
                    val org =
                        OrganizationContract.record(
                            raw(transaction.get(db.document("organizations/${organization.id}"))),
                            session,
                        )
                    AuthoringContract.authority(org, session)
                    if (org.fields != organization.fields)
                        AuthoringContract.fail(AuthoringFailure.STALE)
                    val reference =
                        db.collection(submission.kind.collection).document(submission.id)
                    if (base == null) {
                        // Rules deliberately deny reads of absent content. iOS uses setData for
                        // creation too.
                        // Repository already performed a bounded scoped absence/recovery read;
                        // cryptographic ID is fixed for this intent.
                        val data =
                            submission.fields
                                .filterValues { it != null }
                                .mapValues { encoded(it.value) } +
                                ("updatedAt" to FieldValue.serverTimestamp())
                        transaction.set(reference, data)
                    } else {
                        val raw = raw(transaction.get(reference))
                        val status =
                            AuthoringStatus.entries.firstOrNull {
                                it.wire == raw.fields["moderationStatus"]
                            } ?: AuthoringContract.invalid()
                        val actual =
                            AuthoringContract.item(
                                submission.kind,
                                raw,
                                organization.id,
                                status,
                                session,
                            )
                        if (!actual.editable) AuthoringContract.fail(AuthoringFailure.DENIED)
                        AuthoringContract.unchanged(base, actual)
                        val updates =
                            submission.fields.mapValues { (_, value) ->
                                if (value == null) FieldValue.delete() else encoded(value)
                            } + ("updatedAt" to FieldValue.serverTimestamp())
                        transaction.update(reference, updates)
                    }
                }
                .await()
            identity(session)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            val failure = authoringFailure(error)
            throw AuthoringException(
                if (failure in setOf(AuthoringFailure.OFFLINE, AuthoringFailure.UNKNOWN))
                    AuthoringFailure.UNCONFIRMED
                else failure,
                cause = error,
            )
        }
    }
}

internal fun authoringSdkFailure(error: Throwable): AuthoringFailure =
    when (error) {
        is FirebaseFirestoreException ->
            when (error.code) {
                FirebaseFirestoreException.Code.PERMISSION_DENIED,
                FirebaseFirestoreException.Code.UNAUTHENTICATED -> AuthoringFailure.DENIED
                FirebaseFirestoreException.Code.UNAVAILABLE,
                FirebaseFirestoreException.Code.DEADLINE_EXCEEDED -> AuthoringFailure.OFFLINE
                FirebaseFirestoreException.Code.NOT_FOUND -> AuthoringFailure.MISSING
                FirebaseFirestoreException.Code.FAILED_PRECONDITION -> AuthoringFailure.INDEX
                FirebaseFirestoreException.Code.ABORTED ->
                    error.cause?.let(::authoringFailure) ?: AuthoringFailure.STALE
                else -> error.cause?.let(::authoringFailure) ?: AuthoringFailure.UNKNOWN
            }
        else -> AuthoringFailure.UNKNOWN
    }
