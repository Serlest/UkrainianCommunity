package at.uac.android.feature.safety

import android.content.Context
import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.CallableGateway
import at.uac.android.core.backend.FirebaseBackendGuard
import at.uac.android.feature.browse.Fields
import at.uac.android.feature.browse.RawDocument
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.DocumentSnapshot
import com.google.firebase.firestore.FieldPath
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.Source
import java.io.IOException
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.tasks.await

fun localSafetySource(context: Context): SafetySource =
    FirebaseSafetySource(
        AppBackend.firestore(context),
        AppBackend.auth(context),
        AppBackend.callables(context),
    )

/**
 * No direct client block/report writes; every mutation retains the existing callable authorization.
 */
class FirebaseSafetySource(
    private val db: FirebaseFirestore,
    private val auth: FirebaseAuth,
    private val functions: CallableGateway,
) : SafetySource {
    init {
        LocalEnvironment.requireSafe()
        FirebaseBackendGuard.requireSameApp(auth, db)
        functions.requireBoundTo(auth)
    }

    private fun requireIdentity(uid: String) {
        val identity = auth.currentUser
        if (identity?.uid != uid) throw CancellationException("Safety SDK account changed")
        if (!identity.isEmailVerified || identity.isAnonymous)
            throw SafetyException(SafetyFailure.NOT_READY)
    }

    private fun convert(value: Any?): Any? =
        when (value) {
            is Timestamp -> Instant.ofEpochSecond(value.seconds, value.nanoseconds.toLong())
            is Map<*, *> -> value.entries.associate { it.key.toString() to convert(it.value) }
            is List<*> -> value.map(::convert)
            else -> value
        }

    @Suppress("UNCHECKED_CAST")
    private fun row(snapshot: DocumentSnapshot): RawDocument? =
        snapshot.data?.let { RawDocument(snapshot.id, convert(it) as Fields) }

    private suspend fun <T> request(stage: SafetyOperation, operation: suspend () -> T): T =
        try {
            operation()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            throw SafetyException(safetyFailure(error), error, stage)
        }

    override suspend fun userBlocks(uid: String): List<RawDocument> =
        request(SafetyOperation.USER_BLOCKS) {
            requireIdentity(uid)
            val rows = mutableListOf<RawDocument>()
            var cursor: String? = null
            while (true) {
                requireIdentity(uid)
                var query =
                    db.collection("users/$uid/blockedUsers")
                        .orderBy(FieldPath.documentId())
                        .limit(100)
                cursor?.let { query = query.startAfter(it) }
                val page = query.get(Source.SERVER).await()
                rows +=
                    page.documents.map { row(it) ?: throw SafetyException(SafetyFailure.INVALID) }
                if (rows.size > 5_000) throw SafetyException(SafetyFailure.LIMIT)
                if (page.size() < 100) break
                cursor = page.documents.last().id
            }
            rows // No timestamp query: malformed rows cannot silently disappear from the block
            // policy.
        }

    override suspend fun userBlock(uid: String, id: String): RawDocument? =
        request(SafetyOperation.USER_BLOCK) {
            requireIdentity(uid)
            require(safetyId(id))
            row(db.document("users/$uid/blockedUsers/$id").get(Source.SERVER).await())
        }

    override suspend fun report(uid: String, id: String): RawDocument? =
        request(SafetyOperation.REPORT_READ) {
            requireIdentity(uid)
            require(safetyId(id))
            row(db.document("feedback/$id").get(Source.SERVER).await())
        }

    override suspend fun call(name: String, fields: Fields, uid: String): Any? =
        request(
            if (name == "getBlockedOrganizations") SafetyOperation.ORGANIZATION_BLOCKS
            else SafetyOperation.CALLABLE
        ) {
            require(
                name in
                    setOf(
                        "setUserBlocked",
                        "getBlockedOrganizations",
                        "setOrganizationBlocked",
                        "submitContentReport",
                    )
            )
            requireIdentity(uid)
            functions
                .getHttpsCallable(name)
                .withTimeout(20, TimeUnit.SECONDS)
                .call(fields)
                .await()
                .data
        }
}

fun safetyFailure(error: Throwable): SafetyFailure =
    when (error) {
        is SafetyException -> error.failure
        is LocalCallableException ->
            when (error.code.name) {
                "UNAUTHENTICATED" -> SafetyFailure.SIGN_IN
                "PERMISSION_DENIED" -> SafetyFailure.DENIED
                "NOT_FOUND" -> SafetyFailure.MISSING
                "FAILED_PRECONDITION" -> SafetyFailure.NOT_READY
                "INVALID_ARGUMENT" -> SafetyFailure.INVALID
                "RESOURCE_EXHAUSTED" -> SafetyFailure.LIMIT
                "UNAVAILABLE",
                "DEADLINE_EXCEEDED" -> SafetyFailure.OFFLINE
                "UNCONFIRMED" -> SafetyFailure.UNCONFIRMED
                else -> SafetyFailure.UNKNOWN
            }
        is FirebaseFirestoreException ->
            when (error.code) {
                FirebaseFirestoreException.Code.UNAUTHENTICATED,
                FirebaseFirestoreException.Code.PERMISSION_DENIED -> SafetyFailure.DENIED
                FirebaseFirestoreException.Code.UNAVAILABLE,
                FirebaseFirestoreException.Code.DEADLINE_EXCEEDED -> SafetyFailure.OFFLINE
                FirebaseFirestoreException.Code.NOT_FOUND -> SafetyFailure.MISSING
                FirebaseFirestoreException.Code.INVALID_ARGUMENT,
                FirebaseFirestoreException.Code.DATA_LOSS -> SafetyFailure.INVALID
                FirebaseFirestoreException.Code.RESOURCE_EXHAUSTED -> SafetyFailure.LIMIT
                else -> SafetyFailure.UNKNOWN
            }
        is IOException -> SafetyFailure.OFFLINE
        else -> SafetyFailure.UNKNOWN
    }
