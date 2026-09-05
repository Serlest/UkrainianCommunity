package at.uac.android.feature.attendees

import android.content.Context
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.FirebaseBackendGuard
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.organization.OrganizationContract
import at.uac.android.feature.personal.validDocumentId
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.DocumentSnapshot
import com.google.firebase.firestore.FieldPath
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.firestore.MetadataChanges
import com.google.firebase.firestore.Source
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeout

fun localAttendeesSource(context: Context): AttendeesSource =
    FirestoreAttendeesSource(AppBackend.firestore(context), AppBackend.auth(context))

class FirestoreAttendeesSource(private val db: FirebaseFirestore, private val auth: FirebaseAuth) :
    AttendeesSource {
    init {
        LocalEnvironment.requireSafe()
        FirebaseBackendGuard.requireSameApp(auth, db)
    }

    private fun identity(session: AttendeesSession) {
        if (auth.currentUser?.uid != session.uid)
            throw CancellationException("Attendee identity changed")
        if (
            !session.ready ||
                auth.currentUser?.isAnonymous != false ||
                auth.currentUser?.isEmailVerified != true
        )
            throw AttendeesException(AttendeesFailure.NOT_READY)
    }

    private fun raw(document: DocumentSnapshot): RawDocument {
        if (!document.exists()) throw AttendeesException(AttendeesFailure.MISSING)
        return RawDocument(
            document.id,
            document.data.orEmpty().mapValues { (_, value) ->
                if (value is Timestamp)
                    Instant.ofEpochSecond(value.seconds, value.nanoseconds.toLong())
                else value
            },
        )
    }

    private suspend fun <T> read(session: AttendeesSession, action: suspend () -> T): T =
        try {
            identity(session)
            withTimeout(15_000) { action() }.also { identity(session) }
        } catch (error: TimeoutCancellationException) {
            throw AttendeesException(AttendeesFailure.OFFLINE, error)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            throw AttendeesException(attendeesFailure(error), error)
        }

    override suspend fun event(id: String, session: AttendeesSession): RawDocument =
        read(session) {
            if (!AttendeesContract.eventId(id)) throw AttendeesException(AttendeesFailure.INVALID)
            raw(db.collection("events").document(id).get(Source.SERVER).await())
        }

    override suspend fun organization(id: String, session: AttendeesSession): RawDocument? =
        read(session) {
            if (!OrganizationContract.id(id)) throw AttendeesException(AttendeesFailure.INVALID)
            db.collection("organizations")
                .document(id)
                .get(Source.SERVER)
                .await()
                .takeIf { it.exists() }
                ?.let(::raw)
        }

    private fun registrationsQuery(id: String) =
        db.collection("registrations").whereEqualTo("eventId", id).orderBy(FieldPath.documentId())

    override suspend fun registrations(
        id: String,
        after: String?,
        session: AttendeesSession,
    ): AttendeesRawPage =
        read(session) {
            if (!AttendeesContract.eventId(id) || after?.let { !validDocumentId(it) } == true)
                throw AttendeesException(AttendeesFailure.INVALID)
            var query = registrationsQuery(id).limit((AttendeesContract.PAGE_SIZE + 1).toLong())
            if (after != null) query = query.startAfter(after)
            val rows = query.get(Source.SERVER).await().documents.map(::raw)
            val page = rows.take(AttendeesContract.PAGE_SIZE)
            AttendeesRawPage(
                page,
                page.lastOrNull()?.id?.takeIf { rows.size > AttendeesContract.PAGE_SIZE },
            )
        }

    override suspend fun profiles(ids: List<String>, session: AttendeesSession): List<RawDocument> =
        read(session) {
            if (ids.size > AttendeesContract.PAGE_SIZE || ids.any { !AttendeesContract.userId(it) })
                throw AttendeesException(AttendeesFailure.INVALID)
            ids.distinct().chunked(10).flatMap { chunk ->
                db.collection("publicProfiles")
                    .whereIn(FieldPath.documentId(), chunk)
                    .get(Source.SERVER)
                    .await()
                    .documents
                    .map(::raw)
            }
        }

    override fun accessChanges(
        id: String,
        organizationId: String?,
        session: AttendeesSession,
    ): Flow<Result<Unit>> = observeChanges(id, organizationId, session, registrations = false)

    override fun changes(
        id: String,
        organizationId: String?,
        session: AttendeesSession,
    ): Flow<Result<Unit>> = observeChanges(id, organizationId, session, registrations = true)

    private fun observeChanges(
        id: String,
        organizationId: String?,
        session: AttendeesSession,
        registrations: Boolean,
    ): Flow<Result<Unit>> = callbackFlow {
        identity(session)
        if (
            !AttendeesContract.eventId(id) ||
                organizationId?.let { !OrganizationContract.id(it) } == true
        )
            throw AttendeesException(AttendeesFailure.INVALID)
        val listeners = mutableListOf<ListenerRegistration>()
        fun document(path: String) {
            var serverSeen = false
            listeners +=
                db.document(path).addSnapshotListener(MetadataChanges.INCLUDE) { snapshot, error ->
                    when {
                        error != null ->
                            trySend(
                                Result.failure(AttendeesException(attendeesFailure(error), error))
                            )
                        snapshot == null -> Unit
                        snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites() ->
                            if (serverSeen)
                                trySend(
                                    Result.failure(AttendeesException(AttendeesFailure.OFFLINE))
                                )
                            else Unit
                        !snapshot.exists() ->
                            trySend(Result.failure(AttendeesException(AttendeesFailure.MISSING)))
                        else -> {
                            serverSeen = true
                            trySend(Result.success(Unit))
                        }
                    }
                }
        }
        try {
            document("events/$id")
            organizationId?.let { document("organizations/$it") }
            var registrationServerSeen = false
            if (registrations)
                listeners +=
                    registrationsQuery(id)
                        .limit((AttendeesContract.PAGE_SIZE + 1).toLong())
                        .addSnapshotListener(MetadataChanges.INCLUDE) { snapshot, error ->
                            when {
                                error != null ->
                                    trySend(
                                        Result.failure(
                                            AttendeesException(attendeesFailure(error), error)
                                        )
                                    )
                                snapshot == null -> Unit
                                snapshot.metadata.isFromCache ||
                                    snapshot.metadata.hasPendingWrites() ->
                                    if (registrationServerSeen)
                                        trySend(
                                            Result.failure(
                                                AttendeesException(AttendeesFailure.OFFLINE)
                                            )
                                        )
                                    else Unit
                                else -> {
                                    registrationServerSeen = true
                                    trySend(Result.success(Unit))
                                }
                            }
                        }
            awaitClose {}
        } finally {
            listeners.forEach { it.remove() }
        }
    }
}

fun attendeesFailure(error: Throwable): AttendeesFailure =
    when (error) {
        is AttendeesException -> error.failure
        is FirebaseFirestoreException ->
            when (error.code.name) {
                "PERMISSION_DENIED",
                "UNAUTHENTICATED" -> AttendeesFailure.DENIED
                "UNAVAILABLE",
                "DEADLINE_EXCEEDED" -> AttendeesFailure.OFFLINE
                "NOT_FOUND" -> AttendeesFailure.MISSING
                "INVALID_ARGUMENT" -> AttendeesFailure.INVALID
                "FAILED_PRECONDITION" -> AttendeesFailure.INDEX
                else -> AttendeesFailure.UNKNOWN
            }
        else -> AttendeesFailure.UNKNOWN
    }
