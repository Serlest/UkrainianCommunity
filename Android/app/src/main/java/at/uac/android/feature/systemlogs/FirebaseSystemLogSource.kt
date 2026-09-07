package at.uac.android.feature.systemlogs

import android.content.Context
import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalCallableFailure
import at.uac.android.core.LocalCallableProtocol
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.CallableGateway
import at.uac.android.core.backend.FirebaseBackendGuard
import at.uac.android.feature.moderation.ModerationSession
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.DocumentSnapshot
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.Query
import com.google.firebase.firestore.Source
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

fun localSystemLogSource(context: Context): SystemLogSource = FirebaseSystemLogSource(
    AppBackend.firestore(context), AppBackend.auth(context), AppBackend.callables(context)
)

class FirebaseSystemLogSource(
    private val db: FirebaseFirestore,
    private val auth: FirebaseAuth,
    private val functions: CallableGateway,
) : SystemLogSource {
    init { FirebaseBackendGuard.requireSameApp(auth, db); functions.requireBoundTo(auth) }

    private fun identity(session: ModerationSession, access: SystemLogAccess = SystemLogContract.access(session)) {
        if (SystemLogContract.access(session) != access || auth.currentUser?.uid != session.uid || auth.currentUser?.isEmailVerified != true || auth.currentUser?.isAnonymous != false) SystemLogContract.fail(SystemLogFailure.ACCESS)
    }

    override suspend fun list(session: ModerationSession, access: SystemLogAccess, sort: SystemLogSort): List<SystemLogEntry> = read {
        identity(session, access)
        var query: Query = db.collection("systemLogs")
        if (access == SystemLogAccess.APP_ADMIN) query = query.whereEqualTo("isAppAdminReadable", true)
        query = when (sort) {
            SystemLogSort.NEWEST -> query.orderBy("createdAt", Query.Direction.DESCENDING)
            SystemLogSort.OLDEST -> query.orderBy("createdAt", Query.Direction.ASCENDING)
            SystemLogSort.SEVERITY_HIGH -> query.orderBy("severityRank", Query.Direction.DESCENDING).orderBy("createdAt", Query.Direction.DESCENDING)
            SystemLogSort.SEVERITY_LOW -> query.orderBy("severityRank", Query.Direction.ASCENDING).orderBy("createdAt", Query.Direction.DESCENDING)
            SystemLogSort.CATEGORY -> query.orderBy("category").orderBy("createdAt", Query.Direction.DESCENDING)
        }
        val result = withTimeout(20_000) { query.limit(100).get(Source.SERVER).await() }
        identity(session, access)
        if (result.metadata.isFromCache || result.metadata.hasPendingWrites()) SystemLogContract.fail(SystemLogFailure.OFFLINE)
        result.documents.map(::parse)
    }

    override suspend fun find(session: ModerationSession, access: SystemLogAccess, id: String): SystemLogEntry? = read {
        identity(session, access)
        if (!SystemLogContract.id(id)) SystemLogContract.fail(SystemLogFailure.INVALID)
        val doc = withTimeout(15_000) { db.document("systemLogs/$id").get(Source.SERVER).await() }
        identity(session, access)
        if (doc.metadata.isFromCache || doc.metadata.hasPendingWrites()) SystemLogContract.fail(SystemLogFailure.OFFLINE)
        if (doc.exists()) parse(doc) else null
    }

    override suspend fun review(session: ModerationSession, expected: SystemLogEntry): SystemLogEntry = read {
        val access = SystemLogContract.access(session)
        identity(session, access)
        val ref = db.document("systemLogs/${expected.id}")
        db.runTransaction { transaction ->
            identity(session, access)
            val current = parse(transaction.get(ref))
            if (current != expected) SystemLogContract.fail(SystemLogFailure.CONFLICT)
            transaction.update(ref, mapOf("isReviewed" to true, "reviewedAt" to FieldValue.serverTimestamp(), "reviewedByUserId" to session.uid))
        }.await()
        find(session, access, expected.id)?.takeIf { it.reviewed && it.reviewedBy == session.uid } ?: SystemLogContract.fail(SystemLogFailure.UNCONFIRMED)
    }

    override suspend fun delete(session: ModerationSession, expected: SystemLogEntry): Int {
        identity(session, SystemLogAccess.OWNER)
        val fresh = find(session, SystemLogAccess.OWNER, expected.id) ?: SystemLogContract.fail(SystemLogFailure.MISSING)
        if (fresh != expected) SystemLogContract.fail(SystemLogFailure.CONFLICT)
        return mutate("deleteSystemLog", SystemLogContract.deletePayload(expected.id)) { SystemLogContract.deleted(it, 1) }
    }

    override suspend fun clear(session: ModerationSession): Int {
        identity(session, SystemLogAccess.OWNER)
        return mutate("clearSystemLogs", SystemLogContract.clearPayload(), SystemLogContract::deleted)
    }

    override suspend fun testPush(session: ModerationSession): TestPushReceipt {
        identity(session, SystemLogAccess.OWNER)
        return mutate("sendTestPushNotification", emptyMap<String, Any?>(), SystemLogContract::pushReceipt)
    }

    /** Actual callable errors are ambiguous and never converted into authorization to replay. */
    private suspend fun <T> mutate(name: String, payload: Map<String, *>, parse: (Any?) -> T): T = withContext(Dispatchers.IO) {
        try {
            val data =
                functions
                    .getHttpsCallable(name)
                    .withTimeout(
                        LocalCallableProtocol.maximumTimeoutMillis(name),
                        TimeUnit.MILLISECONDS,
                    )
                    .call(payload)
                    .await()
                    .data
            parse(data)
        } catch (error: CancellationException) { throw error } catch (error: SystemLogException) { throw error } catch (error: LocalCallableException) {
            val failure =
                when (error.code) {
                    LocalCallableFailure.PERMISSION_DENIED,
                    LocalCallableFailure.UNAUTHENTICATED -> SystemLogFailure.ACCESS
                    LocalCallableFailure.INVALID_ARGUMENT,
                    LocalCallableFailure.DATA_LOSS -> SystemLogFailure.INVALID
                    LocalCallableFailure.NOT_FOUND -> SystemLogFailure.MISSING
                    LocalCallableFailure.ABORTED,
                    LocalCallableFailure.FAILED_PRECONDITION -> SystemLogFailure.CONFLICT
                    LocalCallableFailure.UNAVAILABLE,
                    LocalCallableFailure.DEADLINE_EXCEEDED -> SystemLogFailure.OFFLINE
                    else -> SystemLogFailure.UNCONFIRMED
                }
            throw SystemLogException(failure, error)
        } catch (error: Exception) {
            throw SystemLogException(SystemLogFailure.UNCONFIRMED, error)
        }
    }

    private fun parse(doc: DocumentSnapshot): SystemLogEntry {
        if (!doc.exists()) SystemLogContract.fail(SystemLogFailure.MISSING)
        val f = doc.data ?: SystemLogContract.fail(SystemLogFailure.INVALID)
        fun text(key: String, max: Int = 500): String? = (f[key] as? String)?.let { SystemLogContract.sanitize(key, it, max) }?.takeIf(String::isNotEmpty)
        val created = (f["createdAt"] as? Timestamp)?.toDate()?.toInstant() ?: SystemLogContract.fail(SystemLogFailure.INVALID)
        val rawMetadata = f["metadata"] as? Map<*, *> ?: emptyMap<Any?, Any?>()
        val metadata = rawMetadata.entries.sortedBy { it.key.toString() }.take(40).associate { entry ->
            val key = (entry.key as? String)?.take(120) ?: SystemLogContract.fail(SystemLogFailure.INVALID)
            key to SystemLogContract.sanitize(key, entry.value as? String ?: SystemLogContract.fail(SystemLogFailure.INVALID))
        }
        val severity = text("severity", 40) ?: "info"
        val rank = (f["severityRank"] as? Number)?.toInt() ?: SystemLogContract.severities.indexOf(severity).coerceAtLeast(0)
        return SystemLogEntry(
            doc.id, created, text("category", 60) ?: "unknown", severity, rank, text("eventType", 80) ?: "unknown",
            text("actorUserId", 200), text("actorDisplayName", 200), text("actorRole", 60) ?: "unknown",
            text("targetType", 80) ?: "unknown", text("targetId", 200), text("targetTitle", 500), text("organizationId", 200), text("organizationName", 500), text("outcome", 60),
            text("summary", 500).orEmpty(), text("technicalMessage", 1500), text("errorCode", 200), text("moduleName", 200), text("screenName", 200), text("operationName", 200), text("appVersion", 100), text("osVersion", 100), text("deviceModel", 200),
            f["isReviewed"] as? Boolean ?: false, (f["reviewedAt"] as? Timestamp)?.toDate()?.toInstant(), text("reviewedByUserId", 200), metadata,
            text("retentionPolicy", 80), text("correlationId", 200), f["isAppAdminReadable"] as? Boolean ?: false,
        )
    }

    private suspend fun <T> read(block: suspend () -> T): T = try { block() } catch (error: TimeoutCancellationException) {
        throw SystemLogException(SystemLogFailure.OFFLINE, error)
    } catch (error: CancellationException) { throw error } catch (error: SystemLogException) { throw error } catch (error: Exception) {
        val denied = error is FirebaseFirestoreException && error.code in setOf(FirebaseFirestoreException.Code.PERMISSION_DENIED, FirebaseFirestoreException.Code.UNAUTHENTICATED)
        throw SystemLogException(if (denied) SystemLogFailure.ACCESS else SystemLogFailure.OFFLINE, error)
    }
}
