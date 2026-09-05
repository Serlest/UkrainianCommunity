package at.uac.android.feature.moderation

import android.content.Context
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.FirebaseBackendGuard
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldPath
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Source
import com.google.firebase.firestore.TransactionOptions
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeout

fun localModerationDecisionSource(context: Context): ModerationDecisionSource =
    FirebaseModerationDecisionSource(AppBackend.firestore(context), AppBackend.auth(context))

class FirebaseModerationDecisionSource(private val db: FirebaseFirestore, auth: FirebaseAuth) :
    ModerationDecisionSource {
    private val access = ModerationAccess(db, auth)

    init {
        FirebaseBackendGuard.requireSameApp(auth, db)
    }

    override suspend fun authorize(session: ModerationSession) {
        withTimeout(15_000) { access.privileged(session) }
    }

    override suspend fun execute(
        session: ModerationSession,
        pending: ModerationPending,
        canDispatch: () -> Boolean,
    ) {
        ModerationDecisionContract.requireOwner(session, pending)
        if (
            pending.phase != ModerationDecisionPhase.DISPATCHED ||
                pending.issuedRole != session.role
        )
            ModerationDecisionContract.fail(ModerationDecisionFailure.INVALID)
        authorize(session)
        val target =
            db.collection(pending.version.target.kind.collection)
                .document(pending.version.target.id)
        val profile = db.document("users/${session.uid}")
        val log = db.collection("systemLogs").document(pending.operationId)
        val receipt =
            ModerationDecisionContract.receiptFields(pending, session.uid) +
                mapOf("createdAt" to FieldValue.serverTimestamp(), "isReviewed" to false)
        // Async profile/token reads above may outlive the screen or an Auth generation.
        if (!canDispatch()) ModerationDecisionContract.fail(ModerationDecisionFailure.STALE)
        // No timeout around this Task. The repository keeps actual settlement inside the Auth
        // mutex.
        db.runTransaction(TransactionOptions.Builder().setMaxAttempts(5).build()) { transaction ->
                val actor = transaction.get(profile)
                val content = transaction.get(target)
                ModerationAccess.requireProfile(session, actor.data)
                val actual = runCatching {
                    ModerationReviewVersion.from(pending.version.target, content.data.orEmpty())
                }
                    .getOrNull()
                if (actual != pending.version)
                    ModerationDecisionContract.fail(ModerationDecisionFailure.STALE)
                // Pure retried callback: all identity, UUID, journal and UI work happened outside
                // it.
                transaction.update(
                    target,
                    mapOf(
                        "moderationStatus" to pending.decision.wire,
                        "updatedAt" to FieldValue.serverTimestamp(),
                    ),
                )
                // Existing UUID cannot be overwritten: unchanged Rules allow review-only updates.
                transaction.set(log, receipt)
                Unit
            }
            .await()
        access.identity(session)
    }

    override suspend fun reconcile(
        session: ModerationSession,
        pending: ModerationPending,
    ): ModerationObservation =
        withTimeout(15_000) {
            ModerationDecisionContract.requireOwner(session, pending)
            access.privileged(session)
            if (pending.issuedRole == "owner" && session.role != "owner")
                return@withTimeout ModerationObservation.AUTHORITY_LIMITED
            val log =
                if (session.role == "owner")
                    db.collection("systemLogs")
                        .document(pending.operationId)
                        .get(Source.SERVER)
                        .await()
                        .takeIf { it.exists() }
                else
                    db.collection("systemLogs")
                        .whereGreaterThanOrEqualTo(FieldPath.documentId(), pending.operationId)
                        .whereLessThanOrEqualTo(FieldPath.documentId(), pending.operationId)
                        .whereEqualTo("isAppAdminReadable", true)
                        .limit(1)
                        .get(Source.SERVER)
                        .await()
                        .documents
                        .singleOrNull()
            access.identity(session)
            val content =
                db.collection(pending.version.target.kind.collection)
                    .document(pending.version.target.id)
                    .get(Source.SERVER)
                    .await()
            access.identity(session)
            val fields = content.data
            if (log == null)
                return@withTimeout if (fields?.get("moderationStatus") == pending.decision.wire)
                    ModerationObservation.OBSERVED_WITHOUT_RECEIPT
                else ModerationObservation.UNCONFIRMED
            val receiptTime =
                ModerationDecisionContract.receiptTime(pending, session.uid, log.data.orEmpty())
                    ?: return@withTimeout ModerationObservation.CONFLICT
            if (fields == null) return@withTimeout ModerationObservation.CONFIRMED_UNAVAILABLE
            val preserved = runCatching {
                ModerationReviewVersion.hash(pending.version.target, fields, true)
            }
                .getOrNull()
            if (
                fields["moderationStatus"] == pending.decision.wire &&
                    preserved == pending.version.preservedHash &&
                    ModerationReviewVersion.instant(fields["updatedAt"]) == receiptTime
            )
                ModerationObservation.CONFIRMED_CURRENT
            else ModerationObservation.CONFIRMED_CHANGED
        }
}
