package at.uac.android.feature.organizationreview

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
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

fun localOrganizationReviewSource(context: Context): OrganizationReviewSource =
    FirebaseOrganizationReviewSource(
        AppBackend.firestore(context),
        AppBackend.auth(context),
        AppBackend.callables(context),
    )

class FirebaseOrganizationReviewSource(
    private val db: FirebaseFirestore,
    auth: FirebaseAuth,
    private val gateway: CallableGateway,
) : OrganizationReviewSource {
    private val access = ModerationAccess(db, auth)

    init {
        FirebaseBackendGuard.requireSameApp(auth, db)
        gateway.requireBoundTo(auth)
    }

    private fun ref(id: String) =
        db.collection("organizations")
            .document(
                id.also {
                    if (!OrganizationReviewContract.id(it))
                        OrganizationReviewContract.fail(OrganizationReviewFailure.INVALID)
                }
            )

    override suspend fun read(
        session: ModerationSession,
        organizationId: String,
    ): OrganizationReviewSnapshot =
        withTimeout(15_000) {
            access.privileged(session)
            val document = ref(organizationId).get(Source.SERVER).await()
            access.identity(session)
            if (
                !document.exists() ||
                    document.metadata.isFromCache ||
                    document.metadata.hasPendingWrites()
            )
                OrganizationReviewContract.fail(OrganizationReviewFailure.STALE)
            OrganizationReviewContract.snapshot(organizationId, document.data.orEmpty())
        }

    override fun changes(session: ModerationSession, organizationId: String): Flow<Unit> =
        callbackFlow {
            access.identity(session)
            val registrations = mutableListOf<ListenerRegistration>()
            try {
                registrations +=
                    ref(organizationId).addSnapshotListener(MetadataChanges.INCLUDE) { _, error ->
                        if (error != null) close(error) else trySend(Unit)
                    }
                registrations +=
                    db.document("users/${session.uid}").addSnapshotListener(
                        MetadataChanges.INCLUDE
                    ) { _, error ->
                        if (error != null) close(error) else trySend(Unit)
                    }
                awaitClose { registrations.forEach { it.remove() } }
            } finally {
                registrations.forEach { it.remove() }
            }
        }

    override suspend fun send(
        session: ModerationSession,
        entry: OrganizationReviewPending,
        text: String,
        canDispatch: () -> Boolean,
    ): OrganizationReviewReceipt =
        withContext(Dispatchers.IO) {
            OrganizationReviewContract.requireOwner(session, entry)
            if (
                entry.phase != OrganizationReviewPhase.DISPATCHED ||
                    entry.issuedRole != session.role ||
                    OrganizationReviewContract.hash(text) != entry.textHash
            )
                OrganizationReviewContract.fail(OrganizationReviewFailure.INVALID)
            val payload =
                OrganizationReviewContract.payload(entry.version.organizationId, entry.action, text)
            if (read(session, entry.version.organizationId).version != entry.version)
                OrganizationReviewContract.fail(OrganizationReviewFailure.STALE)
            // Latest local preflight only. The server does NOT support compare-and-set of this
            // version.
            val task =
                withContext(Dispatchers.Main.immediate) {
                    // Presentation leases are main-confined. No suspension between the final veto
                    // and Task creation.
                    access.identity(session)
                    if (!canDispatch())
                        OrganizationReviewContract.fail(OrganizationReviewFailure.STALE)
                    gateway
                        .getHttpsCallable(entry.action.callable)
                        .withTimeout(60, TimeUnit.SECONDS)
                        .call(payload)
                }
            val response = task.await()
            // Capture/validate receipt even if the UI/auth projection changed while SDK settled.
            OrganizationReviewContract.receipt(entry, response.data)
        }

    override suspend fun reconcile(
        session: ModerationSession,
        entry: OrganizationReviewPending,
    ): OrganizationReviewObservation =
        withTimeout(15_000) {
            OrganizationReviewContract.requireOwner(session, entry)
            access.privileged(session)
            val document =
                try {
                    ref(entry.version.organizationId).get(Source.SERVER).await()
                } catch (error: FirebaseFirestoreException) {
                    if (
                        error.code != FirebaseFirestoreException.Code.PERMISSION_DENIED &&
                            error.code != FirebaseFirestoreException.Code.NOT_FOUND
                    )
                        throw error
                    // Reauthorize to distinguish lost privilege from a target now
                    // hidden/unavailable.
                    access.privileged(session)
                    return@withTimeout if (entry.receipt != null)
                        OrganizationReviewObservation.CONFIRMED_UNAVAILABLE
                    else OrganizationReviewObservation.UNAVAILABLE
                }
            access.identity(session)
            if (document.metadata.isFromCache || document.metadata.hasPendingWrites())
                OrganizationReviewContract.fail(OrganizationReviewFailure.STALE)
            if (!document.exists())
                return@withTimeout if (entry.receipt != null)
                    OrganizationReviewObservation.CONFIRMED_UNAVAILABLE
                else OrganizationReviewObservation.UNAVAILABLE
            val matches =
                OrganizationReviewContract.matches(entry, session.uid, document.data.orEmpty())
            if (entry.receipt == null) {
                if (matches) OrganizationReviewObservation.OBSERVED_WITHOUT_RECEIPT
                else OrganizationReviewObservation.UNCONFIRMED
            } else if (matches) OrganizationReviewObservation.CONFIRMED_CURRENT
            else OrganizationReviewObservation.CONFIRMED_CHANGED
        }
}

fun organizationReviewFailure(error: Throwable): OrganizationReviewFailure =
    when (error) {
        is OrganizationReviewException -> error.failure
        is ModerationException ->
            when (error.failure) {
                ModerationFailure.OFFLINE -> OrganizationReviewFailure.OFFLINE
                ModerationFailure.INVALID -> OrganizationReviewFailure.INVALID
                ModerationFailure.STALE,
                ModerationFailure.MISSING -> OrganizationReviewFailure.STALE
                else -> OrganizationReviewFailure.ACCESS
            }
        is LocalCallableException ->
            when (error.code) {
                LocalCallableFailure.PERMISSION_DENIED,
                LocalCallableFailure.UNAUTHENTICATED -> OrganizationReviewFailure.ACCESS
                LocalCallableFailure.INVALID_ARGUMENT -> OrganizationReviewFailure.INVALID
                else -> OrganizationReviewFailure.UNCONFIRMED
            }
        is IOException,
        is FirebaseNetworkException,
        is TimeoutCancellationException -> OrganizationReviewFailure.OFFLINE
        is FirebaseFirestoreException -> firestoreReviewFailure(error)
        else -> OrganizationReviewFailure.UNCONFIRMED
    }

// Keep Android SDK enum static initialization out of pure protocol failure tests.
private fun firestoreReviewFailure(error: FirebaseFirestoreException): OrganizationReviewFailure {
    val code = error.code
    return if (
        code == FirebaseFirestoreException.Code.PERMISSION_DENIED ||
            code == FirebaseFirestoreException.Code.UNAUTHENTICATED
    )
        OrganizationReviewFailure.ACCESS
    else if (
        code == FirebaseFirestoreException.Code.UNAVAILABLE ||
            code == FirebaseFirestoreException.Code.DEADLINE_EXCEEDED
    )
        OrganizationReviewFailure.OFFLINE
    else if (code == FirebaseFirestoreException.Code.NOT_FOUND) OrganizationReviewFailure.STALE
    else OrganizationReviewFailure.UNCONFIRMED
}
