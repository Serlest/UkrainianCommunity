package at.uac.android.feature.userstatusmanagement

import android.content.Context
import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalCallableFailure
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.CallableGateway
import at.uac.android.core.backend.FirebaseBackendGuard
import at.uac.android.feature.moderation.ModerationAccess
import at.uac.android.feature.moderation.ModerationException
import at.uac.android.feature.moderation.ModerationFailure
import at.uac.android.feature.moderation.ModerationSession
import com.google.firebase.FirebaseNetworkException
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.firestore.MetadataChanges
import com.google.firebase.firestore.Source
import java.io.IOException
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

fun localUserStatusSource(context: Context): UserStatusSource =
    FirebaseUserStatusSource(
        AppBackend.firestore(context),
        AppBackend.auth(context),
        AppBackend.callables(context),
    )

/** Strict Android privilege policy; the server's legacy no-MFA path is not a client bypass. */
class FirebaseUserStatusSource(
    private val db: FirebaseFirestore,
    auth: FirebaseAuth,
    private val gateway: CallableGateway,
) : UserStatusSource {
    private val access = ModerationAccess(db, auth)

    init {
        FirebaseBackendGuard.requireSameApp(auth, db)
        gateway.requireBoundTo(auth)
    }

    private fun ref(targetId: String) =
        db.collection("users")
            .document(
                targetId.also {
                    if (!UserStatusContract.id(it))
                        UserStatusContract.fail(UserStatusFailure.INVALID)
                }
            )

    override suspend fun read(session: ModerationSession, targetId: String): UserStatusSnapshot =
        userStatusReadOperation {
            withTimeout(15_000) {
                UserStatusContract.requireSession(session)
                val target = ref(targetId)
                access.privileged(session)
                val document = target.get(Source.SERVER).await()
                access.identity(session)
                if (
                    !document.exists() ||
                        document.metadata.isFromCache ||
                        document.metadata.hasPendingWrites()
                )
                    UserStatusContract.fail(UserStatusFailure.STALE)
                // The document path is authoritative; a legacy stored id never redirects a
                // mutation.
                UserStatusContract.snapshot(targetId, document.data.orEmpty())
            }
        }

    override fun changes(session: ModerationSession, targetId: String): Flow<Unit> = callbackFlow {
        UserStatusContract.requireSession(session)
        access.identity(session)
        val target = ref(targetId)
        val registrations = mutableListOf<ListenerRegistration>()
        try {
            registrations +=
                target.addSnapshotListener(MetadataChanges.INCLUDE) { _, error ->
                    if (error != null) close(error) else trySend(Unit)
                }
            if (targetId != session.uid) {
                registrations +=
                    db.document("users/${session.uid}").addSnapshotListener(
                        MetadataChanges.INCLUDE
                    ) { _, error ->
                        if (error != null) close(error) else trySend(Unit)
                    }
            }
            awaitClose { registrations.forEach { it.remove() } }
        } finally {
            registrations.forEach { it.remove() }
        }
    }
        .withUserStatusReadErrors()

    override suspend fun send(
        session: ModerationSession,
        entry: UserStatusPending,
        reason: String,
        until: Instant?,
        canDispatch: () -> Boolean,
    ): UserStatusReceipt =
        withContext(Dispatchers.IO) {
            UserStatusContract.requireOwner(session, entry)
            val text = UserStatusContract.normalizeText(reason)
            if (
                entry.phase != UserStatusPhase.DISPATCHED ||
                    entry.issuedRole != session.role ||
                    UserStatusContract.hash(text) != entry.reasonHash ||
                    UserStatusContract.hash(entry.action.messagePrefix + text) !=
                        entry.messageHash ||
                    UserStatusContract.untilHash(until) != entry.untilHash
            )
                UserStatusContract.fail(UserStatusFailure.INVALID)
            val payload =
                UserStatusContract.payload(entry.version.targetId, entry.action, text, until)
            val current = read(session, entry.version.targetId)
            if (current.version != entry.version) UserStatusContract.fail(UserStatusFailure.STALE)
            UserStatusContract.requireTarget(session, current, entry.action)
            if (until != null && until <= Instant.now())
                UserStatusContract.fail(UserStatusFailure.STALE)
            // Fresh local preflight is not server CAS. No retry and no client-generated receipt.
            val task =
                withContext(Dispatchers.Main.immediate) {
                    access.identity(session)
                    if (!canDispatch()) UserStatusContract.fail(UserStatusFailure.STALE)
                    gateway
                        .getHttpsCallable(entry.action.callable)
                        .withTimeout(60, TimeUnit.SECONDS)
                        .call(payload)
                }
            val response = task.await()
            // The repository holds its non-cancellable settlement scope through the durable ACK.
            // Do not lose the actual response merely because the presentation/session has changed.
            UserStatusContract.receipt(entry, response.data)
        }

    override suspend fun reconcile(
        session: ModerationSession,
        entry: UserStatusPending,
    ): UserStatusObservation = userStatusReadOperation {
        withTimeout(15_000) {
            UserStatusContract.requireOwner(session, entry)
            access.privileged(session)
            val document =
                try {
                    ref(entry.version.targetId).get(Source.SERVER).await()
                } catch (error: FirebaseFirestoreException) {
                    if (
                        error.code != FirebaseFirestoreException.Code.PERMISSION_DENIED &&
                            error.code != FirebaseFirestoreException.Code.NOT_FOUND
                    )
                        throw error
                    // Distinguish unavailable target from revoked actor permission before
                    // reporting.
                    access.privileged(session)
                    return@withTimeout UserStatusContract.observation(entry, session.uid, null)
                }
            access.identity(session)
            if (document.metadata.isFromCache || document.metadata.hasPendingWrites())
                UserStatusContract.fail(UserStatusFailure.STALE)
            UserStatusContract.observation(
                entry,
                session.uid,
                document.data?.takeIf { document.exists() },
            )
        }
    }
}

/** Read-only boundary. Never wrap actual caller cancellation or an already typed failure. */
internal suspend fun <T> userStatusReadOperation(action: suspend () -> T): T =
    try {
        action()
    } catch (error: Exception) {
        throw userStatusReadFailure(error)
    }

/** Also covers asynchronous listener failures; downstream/collector cancellation is untouched. */
internal fun <T> Flow<T>.withUserStatusReadErrors(): Flow<T> = catch { error ->
    throw userStatusReadFailure(error)
}

internal fun userStatusReadFailure(error: Throwable): Throwable =
    when (error) {
        is TimeoutCancellationException -> UserStatusException(UserStatusFailure.OFFLINE, error)
        is CancellationException,
        is UserStatusException -> error
        is Exception -> UserStatusException(userStatusFailure(error), error)
        else -> error
    }

fun userStatusFailure(error: Throwable): UserStatusFailure =
    when (error) {
        is UserStatusException -> error.failure
        is ModerationException ->
            when (error.failure) {
                ModerationFailure.OFFLINE -> UserStatusFailure.OFFLINE
                ModerationFailure.INVALID -> UserStatusFailure.INVALID
                ModerationFailure.STALE,
                ModerationFailure.MISSING -> UserStatusFailure.STALE
                else -> UserStatusFailure.ACCESS
            }
        is LocalCallableException ->
            when (error.code) {
                LocalCallableFailure.PERMISSION_DENIED,
                LocalCallableFailure.UNAUTHENTICATED -> UserStatusFailure.ACCESS
                LocalCallableFailure.INVALID_ARGUMENT -> UserStatusFailure.INVALID
                else -> UserStatusFailure.UNCONFIRMED
            }
        is IOException,
        is FirebaseNetworkException,
        is TimeoutCancellationException -> UserStatusFailure.OFFLINE
        is FirebaseFirestoreException -> firestoreUserStatusFailure(error)
        else -> UserStatusFailure.UNCONFIRMED
    }

// Keep Firebase Android enum initialization out of pure protocol failure tests.
private fun firestoreUserStatusFailure(error: FirebaseFirestoreException): UserStatusFailure {
    val code = error.code
    return if (
        code == FirebaseFirestoreException.Code.PERMISSION_DENIED ||
            code == FirebaseFirestoreException.Code.UNAUTHENTICATED
    )
        UserStatusFailure.ACCESS
    else if (
        code == FirebaseFirestoreException.Code.UNAVAILABLE ||
            code == FirebaseFirestoreException.Code.DEADLINE_EXCEEDED
    )
        UserStatusFailure.OFFLINE
    else if (code == FirebaseFirestoreException.Code.NOT_FOUND) UserStatusFailure.STALE
    else UserStatusFailure.UNCONFIRMED
}
