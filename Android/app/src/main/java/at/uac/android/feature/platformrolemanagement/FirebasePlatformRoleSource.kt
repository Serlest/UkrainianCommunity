package at.uac.android.feature.platformrolemanagement

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

fun localPlatformRoleSource(context: Context): PlatformRoleSource =
    FirebasePlatformRoleSource(
        AppBackend.firestore(context),
        AppBackend.auth(context),
        AppBackend.callables(context),
    )

/** Strict Android privilege policy; the server's legacy no-MFA path is not a client bypass. */
class FirebasePlatformRoleSource(
    private val db: FirebaseFirestore,
    auth: FirebaseAuth,
    private val gateway: CallableGateway,
) : PlatformRoleSource {
    private val access = ModerationAccess(db, auth)

    init {
        FirebaseBackendGuard.requireSameApp(auth, db)
        gateway.requireBoundTo(auth)
    }

    private fun ref(targetId: String) =
        db.collection("users")
            .document(
                targetId.also {
                    if (!PlatformRoleContract.id(it))
                        PlatformRoleRecovery.fail(PlatformRoleFailure.INVALID)
                }
            )

    override suspend fun read(session: ModerationSession, targetId: String): PlatformRoleSnapshot =
        platformRoleReadOperation {
            withTimeout(15_000) {
                PlatformRoleContract.requireSession(session)
                val target = ref(targetId)
                access.privileged(session)
                val document = target.get(Source.SERVER).await()
                access.identity(session)
                if (
                    !document.exists() ||
                        document.metadata.isFromCache ||
                        document.metadata.hasPendingWrites()
                )
                    PlatformRoleRecovery.fail(PlatformRoleFailure.STALE)
                // The document path is authoritative; a legacy stored id never redirects a
                // mutation.
                PlatformRoleRecovery.snapshot(targetId, document.data.orEmpty())
            }
        }

    override fun changes(session: ModerationSession, targetId: String): Flow<Unit> = callbackFlow {
        PlatformRoleContract.requireSession(session)
        withTimeout(15_000) { access.privileged(session) }
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
        .withPlatformRoleReadErrors()

    override suspend fun targetAuth(
        session: ModerationSession,
        targetId: String,
    ): PlatformRoleTargetAuth = platformRoleReadOperation {
        withTimeout(15_000) {
            PlatformRoleContract.requireSession(session)
            if (!PlatformRoleContract.id(targetId))
                PlatformRoleRecovery.fail(PlatformRoleFailure.INVALID)
            access.privileged(session)
            val payload = mapOf("targetUserId" to targetId)
            val result =
                gateway
                    .getHttpsCallable("getManagedUserSecurityMetadata")
                    .withTimeout(15, TimeUnit.SECONDS)
                    .call(payload)
                    .await()
            access.identity(session)
            PlatformRoleContract.targetAuth(targetId, result.data)
        }
    }

    override suspend fun send(
        session: ModerationSession,
        entry: PlatformRolePending,
        reason: String,
        canDispatch: () -> Boolean,
    ): PlatformRoleReceipt =
        withContext(Dispatchers.IO) {
            PlatformRoleRecovery.requireOwner(session, entry)
            val text = PlatformRoleContract.normalizeReason(reason)
            if (
                entry.phase != PlatformRolePhase.DISPATCHED ||
                    PlatformRoleRecovery.hash(text) != entry.reasonHash
            )
                PlatformRoleRecovery.fail(PlatformRoleFailure.INVALID)
            val payload = PlatformRoleContract.payload(entry.version.targetId, text)
            val initial = read(session, entry.version.targetId)
            if (initial.version != entry.version)
                PlatformRoleRecovery.fail(PlatformRoleFailure.STALE)
            PlatformRoleContract.requireTargetRole(session, initial.target, entry.action)
            val metadata =
                if (entry.action == PlatformRoleAction.ASSIGN)
                    targetAuth(session, entry.version.targetId)
                else null
            // Metadata is a separate read. Detect intervening raw-profile changes before dispatch.
            val current = if (metadata != null) read(session, entry.version.targetId) else initial
            if (current.version != entry.version)
                PlatformRoleRecovery.fail(PlatformRoleFailure.STALE)
            PlatformRoleContract.requireTarget(session, current.target, entry.action, metadata)
            platformRoleReadOperation { withTimeout(15_000) { access.privileged(session) } }
            // These fresh client checks are NOT server CAS or transactionally locked Auth state.
            val task =
                withContext(Dispatchers.Main.immediate) {
                    PlatformRoleContract.requireSession(session)
                    access.identity(session)
                    if (!canDispatch()) PlatformRoleRecovery.fail(PlatformRoleFailure.STALE)
                    gateway
                        .getHttpsCallable(entry.action.callable)
                        .withTimeout(60, TimeUnit.SECONDS)
                        .call(payload)
                }
            val response = task.await()
            // Do not discard actual settlement on a presentation change: repository persists ACK
            // first.
            PlatformRoleRecovery.receipt(entry, response.data)
        }

    override suspend fun reconcile(
        session: ModerationSession,
        entry: PlatformRolePending,
    ): PlatformRoleObservation = platformRoleReadOperation {
        withTimeout(15_000) {
            PlatformRoleRecovery.requireOwner(session, entry)
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
                    return@withTimeout PlatformRoleRecovery.observation(entry, session.uid, null)
                }
            access.identity(session)
            if (document.metadata.isFromCache || document.metadata.hasPendingWrites())
                PlatformRoleRecovery.fail(PlatformRoleFailure.STALE)
            PlatformRoleRecovery.observation(
                entry,
                session.uid,
                document.data?.takeIf { document.exists() },
            )
        }
    }
}

/** Read-only boundary. Never wrap actual caller cancellation or an already typed failure. */
internal suspend fun <T> platformRoleReadOperation(action: suspend () -> T): T =
    try {
        action()
    } catch (error: Exception) {
        throw platformRoleReadFailure(error)
    }

/** Also covers asynchronous listener failures; downstream/collector cancellation is untouched. */
internal fun <T> Flow<T>.withPlatformRoleReadErrors(): Flow<T> = catch { error ->
    throw platformRoleReadFailure(error)
}

internal fun platformRoleReadFailure(error: Throwable): Throwable =
    when (error) {
        is TimeoutCancellationException -> PlatformRoleException(PlatformRoleFailure.OFFLINE, error)
        is CancellationException,
        is PlatformRoleException -> error
        is Exception -> PlatformRoleException(platformRoleFailure(error), error)
        else -> error
    }

fun platformRoleFailure(error: Throwable): PlatformRoleFailure =
    when (error) {
        is PlatformRoleException -> error.failure
        is ModerationException ->
            when (error.failure) {
                ModerationFailure.OFFLINE -> PlatformRoleFailure.OFFLINE
                ModerationFailure.INVALID -> PlatformRoleFailure.INVALID
                ModerationFailure.STALE,
                ModerationFailure.MISSING -> PlatformRoleFailure.STALE
                else -> PlatformRoleFailure.ACCESS
            }
        is LocalCallableException ->
            when (error.code) {
                LocalCallableFailure.PERMISSION_DENIED,
                LocalCallableFailure.UNAUTHENTICATED -> PlatformRoleFailure.ACCESS
                LocalCallableFailure.INVALID_ARGUMENT -> PlatformRoleFailure.INVALID
                LocalCallableFailure.UNAVAILABLE,
                LocalCallableFailure.DEADLINE_EXCEEDED -> PlatformRoleFailure.OFFLINE
                LocalCallableFailure.NOT_FOUND,
                LocalCallableFailure.FAILED_PRECONDITION -> PlatformRoleFailure.STALE
                else -> PlatformRoleFailure.UNCONFIRMED
            }
        is IOException,
        is FirebaseNetworkException,
        is TimeoutCancellationException -> PlatformRoleFailure.OFFLINE
        is FirebaseFirestoreException -> firestorePlatformRoleFailure(error)
        else -> PlatformRoleFailure.UNCONFIRMED
    }

// Keep Firebase Android enum initialization out of pure protocol failure tests.
private fun firestorePlatformRoleFailure(error: FirebaseFirestoreException): PlatformRoleFailure {
    val code = error.code
    return if (
        code == FirebaseFirestoreException.Code.PERMISSION_DENIED ||
            code == FirebaseFirestoreException.Code.UNAUTHENTICATED
    )
        PlatformRoleFailure.ACCESS
    else if (
        code == FirebaseFirestoreException.Code.UNAVAILABLE ||
            code == FirebaseFirestoreException.Code.DEADLINE_EXCEEDED
    )
        PlatformRoleFailure.OFFLINE
    else if (code == FirebaseFirestoreException.Code.NOT_FOUND) PlatformRoleFailure.STALE
    else PlatformRoleFailure.UNCONFIRMED
}
