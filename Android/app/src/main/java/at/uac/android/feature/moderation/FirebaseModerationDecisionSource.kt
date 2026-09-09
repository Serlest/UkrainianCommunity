package at.uac.android.feature.moderation

import android.content.Context
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.CallableGateway
import at.uac.android.core.backend.FirebaseBackendGuard
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldPath
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Source
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeout

fun localModerationDecisionSource(context: Context): ModerationDecisionSource =
    FirebaseModerationDecisionSource(
        AppBackend.firestore(context),
        AppBackend.auth(context),
        AppBackend.callables(context),
    )

class FirebaseModerationDecisionSource(
    private val db: FirebaseFirestore,
    auth: FirebaseAuth,
    private val gateway: CallableGateway,
) : ModerationDecisionSource {
    private val access = ModerationAccess(db, auth)

    init {
        FirebaseBackendGuard.requireSameApp(auth, db)
        gateway.requireBoundTo(auth)
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
        val content =
            db.collection(pending.version.target.kind.collection)
                .document(pending.version.target.id)
                .get(Source.SERVER)
                .await()
        val actual = ModerationReviewVersion.from(pending.version.target, content.data.orEmpty())
        if (
            actual != pending.version ||
                content.metadata.isFromCache ||
                content.metadata.hasPendingWrites()
        )
            ModerationDecisionContract.fail(ModerationDecisionFailure.STALE)
        access.identity(session)
        if (!canDispatch()) ModerationDecisionContract.fail(ModerationDecisionFailure.STALE)
        val response =
            gateway
                .getHttpsCallable("reviewContentModeration")
                .withTimeout(60, TimeUnit.SECONDS)
                .call(ModerationBuild80Contract.payload(pending))
                .await()
                .data
        ModerationBuild80Contract.requireReceipt(pending, response)
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
            if (pending.phase == ModerationDecisionPhase.ACKNOWLEDGED) {
                // This durable phase is written only after validating the callable response.
                val content =
                    db.collection(pending.version.target.kind.collection)
                        .document(pending.version.target.id)
                        .get(Source.SERVER)
                        .await()
                access.identity(session)
                if (!content.exists())
                    return@withTimeout ModerationObservation.CONFIRMED_UNAVAILABLE
                val fields = content.data.orEmpty()
                return@withTimeout if (
                    fields["moderationOperationId"] == pending.operationId &&
                        fields["moderatedByUserId"] == session.uid &&
                        fields["moderationStatus"] == pending.decision.wire &&
                        runCatching {
                            ModerationReviewVersion.hash(
                                pending.version.target,
                                fields.filterKeys {
                                    it !in
                                        setOf(
                                            "moderationOperationId",
                                            "moderatedByUserId",
                                            "moderatedAt",
                                        )
                                },
                                true,
                            )
                        }
                            .getOrNull() == pending.version.preservedHash
                )
                    ModerationObservation.CONFIRMED_CURRENT
                else ModerationObservation.CONFIRMED_CHANGED
            }
            // Legacy journals and lost responses retain the original read-only reconciliation.
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
