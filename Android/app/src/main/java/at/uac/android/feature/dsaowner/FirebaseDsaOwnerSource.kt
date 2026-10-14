package at.uac.android.feature.dsaowner

import android.content.Context
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.CallableGateway
import at.uac.android.core.backend.FirebaseBackendGuard
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.moderation.ModerationAccess
import at.uac.android.feature.moderation.ModerationSession
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldPath
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Source
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.tasks.await

fun localDsaOwnerSource(context: Context): DsaOwnerSource = FirebaseDsaOwnerSource(
    AppBackend.firestore(context), AppBackend.callables(context), AppBackend.auth(context))

class FirebaseDsaOwnerSource(
    private val db: FirebaseFirestore,
    private val functions: CallableGateway,
    private val auth: FirebaseAuth,
) : DsaOwnerSource {
    init {
        FirebaseBackendGuard.requireSameApp(auth, db)
        functions.requireBoundTo(auth)
    }

    private val access = ModerationAccess(db, auth)

    private fun owner(session: ModerationSession) {
        if (!session.ready || session.role != "owner") throw DsaOwnerException(DsaOwnerFailure.ACCESS)
        access.identity(session)
    }

    private fun convert(value: Any?): Any? = when (value) {
        is Timestamp -> Instant.ofEpochSecond(value.seconds, value.nanoseconds.toLong())
        is Map<*, *> -> value.entries.associate { it.key.toString() to convert(it.value) }
        is List<*> -> value.map(::convert)
        else -> value
    }

    override suspend fun read(session: ModerationSession, reportId: String): RawDocument? {
        owner(session)
        access.privileged(session)
        owner(session)
        // A bounded query can prove absence without a denied missing direct get.
        val result = db.collection("feedback")
            .whereGreaterThanOrEqualTo(FieldPath.documentId(), reportId)
            .whereLessThanOrEqualTo(FieldPath.documentId(), reportId)
            .limit(1).get(Source.SERVER).await()
        owner(session)
        if (result.metadata.isFromCache || result.metadata.hasPendingWrites())
            throw DsaOwnerException(DsaOwnerFailure.STALE)
        val document = result.documents.singleOrNull() ?: return null
        if (document.id != reportId || document.metadata.isFromCache ||
            document.metadata.hasPendingWrites()) throw DsaOwnerException(DsaOwnerFailure.STALE)
        @Suppress("UNCHECKED_CAST")
        return RawDocument(document.id, convert(document.data.orEmpty()) as Map<String, Any?>)
    }

    override suspend fun call(
        session: ModerationSession,
        action: DsaOwnerAction,
        payload: Map<String, Any?>,
    ): Any? {
        owner(session)
        access.privileged(session)
        owner(session)
        functions.requireBoundTo(auth)
        val name = if (action == DsaOwnerAction.CASE) "decideDsaCase" else "decideDsaAppeal"
        val result = functions.getHttpsCallable(name).call(payload).await().data
        if (auth.currentUser?.uid != session.uid)
            throw CancellationException("DSA owner account changed after callable")
        return result
    }
}
