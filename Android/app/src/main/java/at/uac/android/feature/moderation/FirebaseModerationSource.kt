package at.uac.android.feature.moderation

import android.content.Context
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.FirebaseBackendGuard
import at.uac.android.feature.browse.Fields
import at.uac.android.feature.browse.RawDocument
import com.google.firebase.FirebaseNetworkException
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
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeout

fun localModerationSource(context: Context): ModerationSource =
    FirebaseModerationSource(AppBackend.firestore(context), AppBackend.auth(context))

class FirebaseModerationSource(private val db: FirebaseFirestore, private val auth: FirebaseAuth) :
    ModerationSource {
    init {
        FirebaseBackendGuard.requireSameApp(auth, db)
    }

    private val access = ModerationAccess(db, auth)

    private fun identity(session: ModerationSession) = access.identity(session)

    private suspend fun privileged(session: ModerationSession) = access.privileged(session)

    private fun query(kind: ModerationKind): Query =
        db.collection(kind.collection)
            .whereEqualTo("moderationStatus", "pendingReview")
            .orderBy("createdAt", Query.Direction.DESCENDING)
            .limit(ModerationContract.LIMIT.toLong())

    private fun convert(value: Any?): Any? =
        when (value) {
            is Timestamp -> Instant.ofEpochSecond(value.seconds, value.nanoseconds.toLong())
            is Map<*, *> -> value.entries.associate { it.key.toString() to convert(it.value) }
            is List<*> -> value.map(::convert)
            else -> value
        }

    @Suppress("UNCHECKED_CAST")
    private fun raw(document: DocumentSnapshot) =
        RawDocument(document.id, convert(document.data.orEmpty()) as Fields)

    private suspend fun <T> read(session: ModerationSession, operation: suspend () -> T): T =
        try {
            withTimeout(15_000) {
                privileged(session)
                operation().also { identity(session) }
            }
        } catch (error: TimeoutCancellationException) {
            throw ModerationException(ModerationFailure.OFFLINE, error)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            throw ModerationException(moderationFailure(error), error)
        }

    override suspend fun head(session: ModerationSession, kind: ModerationKind): List<RawDocument> =
        read(session) {
            query(kind).get(Source.SERVER).await().documents.map(::raw)
        }

    override suspend fun preview(
        session: ModerationSession,
        target: ModerationTarget,
    ): RawDocument? =
        read(session) {
            ModerationContract.validate(target)
            db.collection(target.kind.collection)
                .document(target.id)
                .get(Source.SERVER)
                .await()
                .takeIf { it.exists() }
                ?.let(::raw)
        }

    override fun changes(
        session: ModerationSession,
        kind: ModerationKind,
        selected: ModerationTarget?,
    ): Flow<Unit> = flow {
        selected?.let {
            ModerationContract.validate(it)
            if (it.kind != kind) ModerationContract.fail(ModerationFailure.INVALID)
        }
        read(session) { Unit }
        emitAll(
            callbackFlow {
                fun failure(error: Throwable) {
                    close(ModerationException(moderationFailure(error), error))
                }
                fun changed() {
                    try {
                        identity(session)
                        trySend(Unit)
                    } catch (error: Exception) {
                        close(error)
                    }
                }
                val registrations =
                    mutableListOf<com.google.firebase.firestore.ListenerRegistration>()
                registrations +=
                    query(kind).addSnapshotListener(MetadataChanges.INCLUDE) { snapshot, error ->
                        if (error != null) failure(error)
                        else if (
                            snapshot != null &&
                                !snapshot.metadata.isFromCache &&
                                !snapshot.metadata.hasPendingWrites()
                        )
                            changed()
                    }
                registrations +=
                    db.document("users/${session.uid}").addSnapshotListener(
                        MetadataChanges.INCLUDE
                    ) { snapshot, error ->
                        if (error != null) failure(error)
                        else if (
                            snapshot != null &&
                                !snapshot.metadata.isFromCache &&
                                !snapshot.metadata.hasPendingWrites()
                        )
                            changed()
                    }
                selected?.let { target ->
                    registrations +=
                        db.collection(kind.collection).document(target.id).addSnapshotListener(
                            MetadataChanges.INCLUDE
                        ) { snapshot, error ->
                            if (error != null) failure(error)
                            else if (
                                snapshot != null &&
                                    !snapshot.metadata.isFromCache &&
                                    !snapshot.metadata.hasPendingWrites()
                            )
                                changed()
                        }
                }
                awaitClose { registrations.forEach { it.remove() } }
            }
        )
    }
}

/** One actual SDK authorization policy shared by read-only preview and decision paths. */
internal class ModerationAccess(private val db: FirebaseFirestore, private val auth: FirebaseAuth) {
    fun identity(session: ModerationSession) {
        FirebaseBackendGuard.requireSameApp(auth, db)
        ModerationContract.requireSession(session)
        val user = auth.currentUser
        if (user?.uid != session.uid) throw CancellationException("Moderation identity changed")
        if (user.isAnonymous || !user.isEmailVerified)
            ModerationContract.fail(ModerationFailure.NOT_READY)
    }

    suspend fun privileged(session: ModerationSession) {
        identity(session)
        val user = auth.currentUser ?: ModerationContract.fail(ModerationFailure.SIGN_IN)
        val profile = db.document("users/${session.uid}").get(Source.SERVER).await()
        val token = user.getIdToken(false).await()
        identity(session)
        requireProfile(session, profile.data)
        if ((token.claims["firebase"] as? Map<*, *>)?.get("sign_in_second_factor") != "totp")
            ModerationContract.fail(ModerationFailure.NOT_READY)
    }

    companion object {
        fun requireProfile(session: ModerationSession, profile: Map<String, Any?>?) {
            if (
                profile == null ||
                    profile["globalRole"] != session.role ||
                    profile["accountStatus"] !in setOf("active", "warned") ||
                    profile["blockState"] !in setOf("active", "warned")
            )
                ModerationContract.fail(ModerationFailure.DENIED)
            if (profile["requiresMultiFactorAuth"] != true)
                ModerationContract.fail(ModerationFailure.NOT_READY)
        }
    }
}

fun moderationFailure(error: Throwable): ModerationFailure =
    when (error) {
        is ModerationException -> error.failure
        is TimeoutCancellationException,
        is IOException,
        is FirebaseNetworkException -> ModerationFailure.OFFLINE
        is FirebaseFirestoreException ->
            when (error.code) {
                FirebaseFirestoreException.Code.PERMISSION_DENIED,
                FirebaseFirestoreException.Code.UNAUTHENTICATED -> ModerationFailure.DENIED
                FirebaseFirestoreException.Code.UNAVAILABLE,
                FirebaseFirestoreException.Code.DEADLINE_EXCEEDED -> ModerationFailure.OFFLINE
                FirebaseFirestoreException.Code.FAILED_PRECONDITION -> ModerationFailure.INDEX
                FirebaseFirestoreException.Code.NOT_FOUND -> ModerationFailure.MISSING
                else -> ModerationFailure.UNKNOWN
            }
        else -> ModerationFailure.UNKNOWN
    }
