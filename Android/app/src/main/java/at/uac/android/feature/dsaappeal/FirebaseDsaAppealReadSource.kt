package at.uac.android.feature.dsaappeal

import android.content.Context
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.FirebaseBackendGuard
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.dsastatement.DsaStatementContract
import com.google.firebase.FirebaseNetworkException
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseAuthException
import com.google.firebase.firestore.FieldPath
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.Source
import java.io.IOException
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.tasks.await

fun localDsaAppealReadSource(context: Context): DsaAppealReadSource =
    FirebaseDsaAppealReadSource(AppBackend.firestore(context), AppBackend.auth(context))

/**
 * Only own feedback projection. No dsaCases, portal, callable, listener, write or cache fallback.
 */
class FirebaseDsaAppealReadSource(
    private val db: FirebaseFirestore,
    private val auth: FirebaseAuth,
) : DsaAppealReadSource {
    init {
        FirebaseBackendGuard.requireSameApp(auth, db)
    }

    private fun identity(session: DsaAppealSession) {
        FirebaseBackendGuard.requireSameApp(auth, db)
        if (
            !session.ready ||
                session.revision < 0 ||
                session.backend != dsaAppealBackendBinding ||
                !DsaStatementContract.validId(session.uid, 128)
        )
            DsaAppealReviewContract.fail(DsaAppealReviewFailure.ACCESS)
        val user = auth.currentUser
        if (user?.uid != session.uid) throw CancellationException("Appeal SDK account changed")
        if (user.isAnonymous || !user.isEmailVerified)
            DsaAppealReviewContract.fail(DsaAppealReviewFailure.ACCESS)
    }

    override suspend fun read(session: DsaAppealSession, reportId: String): RawDocument? {
        val caller = currentCoroutineContext()
        try {
            caller.ensureActive()
            identity(session)
            if (!DsaStatementContract.validId(reportId))
                DsaAppealReviewContract.fail(DsaAppealReviewFailure.INVALID)
            val user =
                auth.currentUser ?: DsaAppealReviewContract.fail(DsaAppealReviewFailure.ACCESS)
            val profile = db.document("users/${session.uid}").get(Source.SERVER).await()
            val token = user.getIdToken(false).await()
            caller.ensureActive()
            identity(session)
            if (
                !profile.exists() ||
                    profile.metadata.isFromCache ||
                    profile.metadata.hasPendingWrites()
            )
                DsaAppealReviewContract.fail(DsaAppealReviewFailure.ACCESS)
            DsaAppealSdkPolicy.requireProfile(
                profile.data,
                (token.claims["firebase"] as? Map<*, *>)?.get("sign_in_second_factor"),
            )
            // Closed own-UID and ID range proves absence without an unreadable direct missing get.
            // Auth gate keeps identity fixed until each actual SDK Task has completed.
            val result =
                db.collection("feedback")
                    .whereEqualTo("userId", session.uid)
                    .whereGreaterThanOrEqualTo(FieldPath.documentId(), reportId)
                    .whereLessThanOrEqualTo(FieldPath.documentId(), reportId)
                    .limit(1)
                    .get(Source.SERVER)
                    .await()
            caller.ensureActive()
            identity(session)
            DsaAppealSdkPolicy.requireFresh(
                result.metadata.isFromCache,
                result.metadata.hasPendingWrites(),
            )
            if (result.documents.size > 1)
                DsaAppealReviewContract.fail(DsaAppealReviewFailure.INVALID)
            val document = result.documents.singleOrNull() ?: return null
            DsaAppealSdkPolicy.requireFresh(
                document.metadata.isFromCache,
                document.metadata.hasPendingWrites(),
            )
            if (document.id != reportId || document.getString("userId") != session.uid)
                DsaAppealReviewContract.fail(DsaAppealReviewFailure.ACCESS)
            val data = document.data ?: DsaAppealReviewContract.fail(DsaAppealReviewFailure.INVALID)
            var nodes = 0
            fun convert(value: Any?, depth: Int = 0): Any? {
                if (++nodes > 512 || depth > 5)
                    DsaAppealReviewContract.fail(DsaAppealReviewFailure.INVALID)
                return when (value) {
                    is Timestamp -> Instant.ofEpochSecond(value.seconds, value.nanoseconds.toLong())
                    is Map<*, *> -> {
                        if (value.size > 128)
                            DsaAppealReviewContract.fail(DsaAppealReviewFailure.INVALID)
                        value.entries.associate { (key, child) ->
                            (key as? String
                                ?: DsaAppealReviewContract.fail(DsaAppealReviewFailure.INVALID)) to
                                convert(child, depth + 1)
                        }
                    }
                    null,
                    is String,
                    is Boolean,
                    is Number -> value
                    else -> DsaAppealReviewContract.fail(DsaAppealReviewFailure.INVALID)
                }
            }
            // Retain only the parent fields consumed by FeedbackContract and the whole case
            // projection. Unknown case fields are deliberately not filtered before strict review.
            val fields = data.filterKeys { it in parentKeys }.mapValues { convert(it.value) }
            caller.ensureActive()
            identity(session)
            return RawDocument(document.id, fields)
        } catch (failure: CancellationException) {
            throw failure
        } catch (failure: Exception) {
            caller.ensureActive()
            identity(session)
            DsaAppealReviewContract.fail(dsaAppealReadFailure(failure))
        }
    }

    private companion object {
        val parentKeys =
            setOf(
                "id",
                "userId",
                "userDisplayName",
                "type",
                "subject",
                "message",
                "status",
                "createdAt",
                "updatedAt",
                "lastMessageText",
                "unreadForUser",
                "unreadForOwner",
                "ownerReply",
                "repliedAt",
                "repliedByUserId",
                "dsaCase",
                "lastMessageAt",
            )
    }
}

fun dsaAppealReadFailure(error: Throwable): DsaAppealReviewFailure =
    when (error) {
        is DsaAppealReviewException -> error.failure
        is IOException,
        is FirebaseNetworkException -> DsaAppealReviewFailure.OFFLINE
        is FirebaseAuthException -> DsaAppealReviewFailure.ACCESS
        is FirebaseFirestoreException ->
            when (error.code.name) {
                "PERMISSION_DENIED",
                "UNAUTHENTICATED" -> DsaAppealReviewFailure.ACCESS
                "UNAVAILABLE",
                "DEADLINE_EXCEEDED" -> DsaAppealReviewFailure.OFFLINE
                "INVALID_ARGUMENT",
                "DATA_LOSS" -> DsaAppealReviewFailure.INVALID
                else -> DsaAppealReviewFailure.UNKNOWN
            }
        else -> DsaAppealReviewFailure.UNKNOWN
    }
