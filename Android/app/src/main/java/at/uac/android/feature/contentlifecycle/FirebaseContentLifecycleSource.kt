package at.uac.android.feature.contentlifecycle

import android.content.Context
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.CallableGateway
import at.uac.android.core.backend.FirebaseBackendGuard
import at.uac.android.feature.authoring.AuthoringContract
import at.uac.android.feature.authoring.AuthoringStatus
import at.uac.android.feature.authoring.FirebaseAuthoringSource
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.organization.OrganizationContract
import at.uac.android.feature.organization.OrganizationSession
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.AggregateSource
import com.google.firebase.firestore.DocumentSnapshot
import com.google.firebase.firestore.FieldPath
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.Query
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

fun localContentLifecycleSource(context: Context): ContentLifecycleSource =
    FirebaseContentLifecycleSource(
        AppBackend.firestore(context),
        AppBackend.auth(context),
        AppBackend.callables(context),
    )

class FirebaseContentLifecycleSource(
    private val db: FirebaseFirestore,
    private val auth: FirebaseAuth,
    private val functions: CallableGateway,
) : ContentLifecycleSource {
    private val authoring = FirebaseAuthoringSource(db, auth)

    init {
        LocalEnvironment.requireSafe()
        FirebaseBackendGuard.requireSameApp(auth, db)
        functions.requireBoundTo(auth)
    }

    private fun identity(session: OrganizationSession) {
        if (auth.currentUser?.uid != session.uid)
            throw CancellationException("Lifecycle identity changed")
        if (
            !session.ready ||
                auth.currentUser?.isEmailVerified != true ||
                auth.currentUser?.isAnonymous != false
        )
            ContentLifecycleContract.fail(ContentLifecycleFailure.NOT_READY)
    }

    private fun query(
        target: ContentLifecycleTarget,
        status: AuthoringStatus,
        session: OrganizationSession,
    ): Query {
        var query =
            db.collection(target.kind.collection)
                .whereEqualTo("sourceType", "organization")
                .whereEqualTo("organizationId", target.organizationId)
                .whereEqualTo("moderationStatus", status.wire)
                .whereGreaterThanOrEqualTo(FieldPath.documentId(), target.contentId)
                .whereLessThanOrEqualTo(FieldPath.documentId(), target.contentId)
                .limit(1)
        if (status == AuthoringStatus.SCHEDULED) query = query.whereEqualTo("authorId", session.uid)
        return query
    }

    private fun raw(snapshot: DocumentSnapshot): RawDocument =
        RawDocument(
            snapshot.id,
            (snapshot.data ?: ContentLifecycleContract.fail(ContentLifecycleFailure.MISSING))
                .mapValues { decode(it.value) },
        )

    private fun decode(value: Any?): Any? =
        when (value) {
            is Timestamp -> Instant.ofEpochSecond(value.seconds, value.nanoseconds.toLong())
            is Map<*, *> -> value.entries.associate { it.key.toString() to decode(it.value) }
            is List<*> -> value.map(::decode)
            else -> value
        }

    override suspend fun snapshot(
        target: ContentLifecycleTarget,
        session: OrganizationSession,
    ): ContentLifecycleSnapshot =
        try {
            identity(session)
            withTimeout(20_000) {
                val orgReference = db.document("organizations/${target.organizationId}")
                val org =
                    db.runTransaction { transaction ->
                            identity(session)
                            ContentLifecycleContract.authority(
                                OrganizationContract.record(
                                    raw(transaction.get(orgReference)),
                                    session,
                                ),
                                session,
                            )
                        }
                        .await()
                var present = false
                for (status in AuthoringStatus.entries) {
                    // Aggregation is a server round trip, independent of an existing document/query
                    // listener.
                    val count =
                        query(target, status, session)
                            .count()
                            .get(AggregateSource.SERVER)
                            .await()
                            .count
                    identity(session)
                    if (count !in 0L..1L)
                        ContentLifecycleContract.fail(ContentLifecycleFailure.INVALID)
                    if (count == 1L) {
                        present = true
                        break
                    }
                }
                val current =
                    db.runTransaction { transaction ->
                            identity(session)
                            val currentOrg =
                                ContentLifecycleContract.authority(
                                    OrganizationContract.record(
                                        raw(transaction.get(orgReference)),
                                        session,
                                    ),
                                    session,
                                )
                            if (org.fields != currentOrg.fields)
                                ContentLifecycleContract.fail(ContentLifecycleFailure.STALE)
                            // Missing direct documents are Rules-denied. A scoped server count
                            // handles absence first.
                            val item =
                                if (!present) null
                                else {
                                    val document =
                                        raw(
                                            transaction.get(
                                                db.collection(target.kind.collection)
                                                    .document(target.contentId)
                                            )
                                        )
                                    val status =
                                        AuthoringStatus.entries.firstOrNull {
                                            it.wire == document.fields["moderationStatus"]
                                        }
                                            ?: ContentLifecycleContract.fail(
                                                ContentLifecycleFailure.INVALID
                                            )
                                    AuthoringContract.item(
                                        target.kind,
                                        document,
                                        target.organizationId,
                                        status,
                                        session,
                                    )
                                }
                            ContentLifecycleSnapshot(target, currentOrg, item).also {
                                ContentLifecycleContract.validate(it, target, session)
                            }
                        }
                        .await()
                identity(session)
                current
            }
        } catch (error: TimeoutCancellationException) {
            throw ContentLifecycleException(ContentLifecycleFailure.OFFLINE, error)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            throw ContentLifecycleException(contentLifecycleFailure(error), error)
        }

    override fun changes(snapshot: ContentLifecycleSnapshot, session: OrganizationSession) =
        authoring.changes(
            snapshot.target.organizationId,
            snapshot.target.kind,
            snapshot.item?.status ?: AuthoringStatus.APPROVED,
            session,
            snapshot.item,
        )

    override suspend fun execute(
        intent: ContentLifecycleIntent,
        session: OrganizationSession,
    ): ContentLifecycleReceipt =
        withContext(Dispatchers.IO) {
            identity(session)
            ContentLifecycleContract.validate(intent.snapshot, intent.snapshot.target, session)
            if (!ContentLifecycleContract.actionable(intent.snapshot, session))
                ContentLifecycleContract.fail(ContentLifecycleFailure.READ_ONLY)
            val target = intent.snapshot.target
            val news = target.kind == ContentKind.NEWS
            try {
                val response =
                    functions
                        .getHttpsCallable(if (news) "deleteNews" else "cancelEvent")
                        .withTimeout(if (news) 300_000 else 60_000, TimeUnit.MILLISECONDS)
                        .call(mapOf((if (news) "newsId" else "eventId") to target.contentId))
                        .await()
                        .data
                identity(session)
                ContentLifecycleContract.receipt(response, target)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                val reason = contentLifecycleFailure(error)
                // INTERNAL/EOF/deadline can follow a partially completed cascade or an
                // already-written cancellation.
                throw ContentLifecycleException(
                    if (
                        reason in
                            setOf(ContentLifecycleFailure.OFFLINE, ContentLifecycleFailure.UNKNOWN)
                    )
                        ContentLifecycleFailure.UNCONFIRMED
                    else reason,
                    error,
                )
            }
        }
}

internal fun contentLifecycleSdkFailure(error: Throwable): ContentLifecycleFailure =
    when (error) {
        is FirebaseFirestoreException ->
            when (error.code) {
                FirebaseFirestoreException.Code.PERMISSION_DENIED,
                FirebaseFirestoreException.Code.UNAUTHENTICATED -> ContentLifecycleFailure.DENIED
                FirebaseFirestoreException.Code.UNAVAILABLE,
                FirebaseFirestoreException.Code.DEADLINE_EXCEEDED -> ContentLifecycleFailure.OFFLINE
                FirebaseFirestoreException.Code.NOT_FOUND -> ContentLifecycleFailure.MISSING
                FirebaseFirestoreException.Code.FAILED_PRECONDITION -> ContentLifecycleFailure.INDEX
                FirebaseFirestoreException.Code.ABORTED ->
                    error.cause?.let(::contentLifecycleFailure) ?: ContentLifecycleFailure.STALE
                else ->
                    error.cause?.let(::contentLifecycleFailure) ?: ContentLifecycleFailure.UNKNOWN
            }
        else -> ContentLifecycleFailure.UNKNOWN
    }
