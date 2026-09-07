package at.uac.android.feature.feedbackdeletion

import android.content.Context
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.CallableGateway
import at.uac.android.core.backend.FirebaseBackendGuard
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.moderation.ModerationAccess
import at.uac.android.feature.moderation.ModerationException
import at.uac.android.feature.moderation.ModerationFailure
import at.uac.android.feature.moderation.ModerationSession
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Source
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext

fun localFeedbackDeletionMutationSource(context: Context): FeedbackDeletionMutationSource =
    FirebaseFeedbackDeletionSource(
        AppBackend.firestore(context),
        AppBackend.auth(context),
        AppBackend.callables(context),
    )

fun localFeedbackDeletionReadSource(context: Context): FeedbackDeletionReadSource =
    FirebaseFeedbackDeletionSource(
        AppBackend.firestore(context),
        AppBackend.auth(context),
        AppBackend.callables(context),
    )

class FirebaseFeedbackDeletionSource(
    private val db: FirebaseFirestore,
    auth: FirebaseAuth,
    private val functions: CallableGateway,
) : FeedbackDeletionMutationSource, FeedbackDeletionReadSource {
    private val access = ModerationAccess(db, auth)

    init {
        FirebaseBackendGuard.requireSameApp(auth, db)
        functions.requireBoundTo(auth)
    }

    private suspend fun authorize(session: ModerationSession) {
        try {
            access.privileged(session)
        } catch (error: CancellationException) {
            throw error
        } catch (error: ModerationException) {
            throw FeedbackDeletionException(
                if (error.failure == ModerationFailure.OFFLINE)
                    FeedbackDeletionFailure.OFFLINE
                else FeedbackDeletionFailure.ACCESS,
                error,
            )
        }
    }

    override suspend fun read(
        session: ModerationSession,
        targetId: String,
    ): FeedbackDeletionRead = withContext(Dispatchers.IO) {
        FeedbackDeletionContract.requireSession(session)
        if (!FeedbackDeletionContract.id(targetId))
            FeedbackDeletionRecovery.fail(FeedbackDeletionFailure.INVALID)
        authorize(session)
        val document = db.document("feedback/$targetId").get(Source.SERVER).await()
        access.identity(session)
        if (document.metadata.isFromCache || document.metadata.hasPendingWrites())
            FeedbackDeletionRecovery.fail(FeedbackDeletionFailure.STALE)
        if (!document.exists()) return@withContext FeedbackDeletionRead.Absent
        var nodes = 0
        fun copy(value: Any?, depth: Int = 0): Any? {
            if (++nodes > 4096 || depth > 20)
                FeedbackDeletionRecovery.fail(FeedbackDeletionFailure.INVALID)
            return when (value) {
                is Timestamp -> Instant.ofEpochSecond(value.seconds, value.nanoseconds.toLong())
                is Map<*, *> -> value.entries.associate { (key, child) ->
                    (key as? String ?: FeedbackDeletionRecovery.fail(FeedbackDeletionFailure.INVALID)) to
                        copy(child, depth + 1)
                }
                is List<*> -> value.map { copy(it, depth + 1) }
                null, is Boolean, is String, is Byte, is Short, is Int, is Long, is Double -> value
                else -> FeedbackDeletionRecovery.fail(FeedbackDeletionFailure.INVALID)
            }
        }
        @Suppress("UNCHECKED_CAST")
        val fields = copy(document.data.orEmpty()) as Map<String, Any?>
        FeedbackDeletionRead.Present(FeedbackDeletionRecovery.snapshot(document.id, fields))
    }

    override suspend fun delete(
        session: ModerationSession,
        entry: FeedbackDeletionPending,
        canDispatch: () -> Boolean,
    ): FeedbackDeletionReceipt = withContext(Dispatchers.IO) {
        FeedbackDeletionRecovery.requireOwner(session, entry)
        if (entry.phase != FeedbackDeletionPhase.DISPATCHED)
            FeedbackDeletionRecovery.fail(FeedbackDeletionFailure.INVALID)
        authorize(session)
        val task =
            withContext(Dispatchers.Main.immediate) {
                access.identity(session)
                if (!canDispatch()) FeedbackDeletionRecovery.fail(FeedbackDeletionFailure.STALE)
                functions
                    .getHttpsCallable(FeedbackDeletionContract.CALLABLE)
                    .withTimeout(
                        FeedbackDeletionContract.MAXIMUM_TIMEOUT_MILLIS,
                        TimeUnit.MILLISECONDS,
                    )
                    .call(FeedbackDeletionContract.payload(entry.version.targetId))
            }
        val result = task.await()
        FeedbackDeletionRecovery.receipt(entry, result.data)
    }
}
