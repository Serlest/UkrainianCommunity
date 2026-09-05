package at.uac.android.feature.organization

import android.content.Context
import at.uac.android.BuildConfig
import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.CallableGateway
import at.uac.android.core.backend.FirebaseBackendGuard
import at.uac.android.feature.auth.AuthException
import at.uac.android.feature.auth.AuthLegalDocument
import at.uac.android.feature.auth.AuthProblem
import at.uac.android.feature.auth.AuthStore
import at.uac.android.feature.auth.decodeLegal
import at.uac.android.feature.browse.Fields
import at.uac.android.feature.browse.RawDocument
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.DocumentSnapshot
import com.google.firebase.firestore.FieldPath
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.MetadataChanges
import com.google.firebase.firestore.Query
import com.google.firebase.firestore.Source
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeout

class AuthOrganizationMutationGate(private val auth: AuthStore) : OrganizationMutationGate {
    override suspend fun <T> withSession(
        session: OrganizationSession,
        operation: suspend () -> T,
    ): T =
        try {
            auth.withReadySession(session.uid, session.revision, operation)
        } catch (error: AuthException) {
            if (error.problem == AuthProblem.SESSION_CHANGED)
                throw CancellationException("Organization session changed")
            throw OrganizationException(OrganizationFailure.NOT_READY, error)
        }
}

fun localOrganizationSource(context: Context): OrganizationSource =
    FirebaseOrganizationSource(
        AppBackend.firestore(context),
        AppBackend.auth(context),
        AppBackend.callables(context),
        LocalOrganizationStorage.instance(context),
    )

class FirebaseOrganizationSource(
    private val db: FirebaseFirestore,
    private val auth: FirebaseAuth,
    private val functions: CallableGateway,
    private val storage: OrganizationLogoStorage,
) : OrganizationSource {
    init {
        LocalEnvironment.requireSafe()
        FirebaseBackendGuard.requireSameApp(auth, db)
        functions.requireBoundTo(auth)
    }

    private fun identity(session: OrganizationSession) {
        if (auth.currentUser?.uid != session.uid)
            throw CancellationException("Organization identity changed")
        if (
            !session.ready ||
                auth.currentUser?.isEmailVerified != true ||
                auth.currentUser?.isAnonymous != false
        )
            throw OrganizationException(OrganizationFailure.NOT_READY)
    }

    private fun ownQuery(uid: String): Query =
        db.collection("organizations")
            .whereEqualTo("submittedByUserId", uid)
            .whereIn("moderationStatus", OrganizationContract.requestStatuses)
            .orderBy("submittedAt", Query.Direction.DESCENDING)
            .limit(51)

    private fun requestQuery(id: String, uid: String): Query =
        db.collection("organizations")
            // Equality on a missing document evaluates null resource in the existing Rules.
            // This exact inclusive range remains a list query; UID and status constraints are
            // unchanged.
            .whereGreaterThanOrEqualTo(FieldPath.documentId(), id)
            .whereLessThanOrEqualTo(FieldPath.documentId(), id)
            .whereEqualTo("submittedByUserId", uid)
            .whereIn("moderationStatus", OrganizationContract.requestStatuses + "approved")
            .limit(1)

    private fun managedQueries(session: OrganizationSession): List<Query> {
        val approved = db.collection("organizations").whereEqualTo("moderationStatus", "approved")
        return if (session.globalRole == "owner") listOf(approved.limit(51))
        else
            listOf(
                approved.whereEqualTo("ownerId", session.uid).limit(51),
                approved.whereArrayContains("adminIds", session.uid).limit(51),
                approved.whereArrayContains("moderatorIds", session.uid).limit(51),
            )
    }

    private fun convert(value: Any?): Any? =
        when (value) {
            is Timestamp -> Instant.ofEpochSecond(value.seconds, value.nanoseconds.toLong())
            is Map<*, *> -> value.entries.associate { it.key.toString() to convert(it.value) }
            is List<*> -> value.map(::convert)
            else -> value
        }

    @Suppress("UNCHECKED_CAST")
    private fun record(
        snapshot: DocumentSnapshot,
        session: OrganizationSession,
    ): OrganizationRecord =
        OrganizationContract.record(
            RawDocument(
                snapshot.id,
                convert(snapshot.data ?: throw OrganizationException(OrganizationFailure.MISSING))
                    as Fields,
            ),
            session,
        )

    private suspend fun <T> read(action: suspend () -> T): T =
        try {
            withTimeout(15_000) { action() }
        } catch (error: TimeoutCancellationException) {
            throw OrganizationException(OrganizationFailure.OFFLINE, error)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            throw OrganizationException(organizationFailure(error), error)
        }

    override suspend fun hub(session: OrganizationSession): OrganizationHub = read {
        identity(session)
        val requests = ownQuery(session.uid).get(Source.SERVER).await()
        val managedSnapshots = managedQueries(session).map { it.get(Source.SERVER).await() }
        identity(session)
        val own =
            requests.documents.take(50).map {
                record(it, session).also { r ->
                    if (
                        r.submitter != session.uid ||
                            r.status !in OrganizationContract.requestStatuses
                    )
                        throw OrganizationException(OrganizationFailure.INVALID)
                }
            }
        val managed =
            managedSnapshots
                .flatMap { it.documents.take(50) }
                .distinctBy { it.id }
                .map { record(it, session) }
                .filter { it.authority != OrganizationAuthority.NONE }
        OrganizationHub(
            own,
            managed,
            requests.size() > 50 || managedSnapshots.any { it.size() > 50 },
        )
    }

    override suspend fun rules(): AuthLegalDocument = read {
        val ref = db.document("legalDocuments/organizationRules")
        val pointer = ref.get(Source.SERVER).await()
        val version =
            pointer.getString("activeVersion")?.takeIf { it.length in 1..80 && '/' !in it }
                ?: throw OrganizationException(OrganizationFailure.LEGAL_CHANGED)
        val content = ref.collection("versions").document(version).get(Source.SERVER).await()
        decodeLegal(
            "organizationRules",
            version,
            content.data ?: throw OrganizationException(OrganizationFailure.LEGAL_CHANGED),
        )
    }

    override fun changes(session: OrganizationSession, requestId: String?): Flow<Result<Unit>> =
        callbackFlow {
            identity(session)
            val target =
                requestId
                    ?.takeIf(OrganizationContract::id)
                    ?.let { listOf(requestQuery(it, session.uid)) }
                    .orEmpty()
            val registrations =
                (listOf(ownQuery(session.uid)) + managedQueries(session) + target).map { query ->
                    query.addSnapshotListener(MetadataChanges.INCLUDE) { snapshot, error ->
                        if (error != null)
                            trySend(
                                Result.failure(
                                    OrganizationException(organizationFailure(error), error)
                                )
                            )
                        else if (
                            snapshot != null &&
                                !snapshot.metadata.isFromCache &&
                                !snapshot.metadata.hasPendingWrites()
                        )
                            trySend(Result.success(Unit))
                    }
                } +
                    db.document("legalDocuments/organizationRules").addSnapshotListener(
                        MetadataChanges.INCLUDE
                    ) { snapshot, error ->
                        if (error != null)
                            trySend(
                                Result.failure(
                                    OrganizationException(organizationFailure(error), error)
                                )
                            )
                        else if (snapshot != null && !snapshot.metadata.isFromCache)
                            trySend(Result.success(Unit))
                    }
            awaitClose { registrations.forEach { it.remove() } }
        }

    override suspend fun request(id: String, session: OrganizationSession): OrganizationRecord? =
        own(id, session)

    private suspend fun own(id: String, session: OrganizationSession): OrganizationRecord? = read {
        identity(session)
        if (!OrganizationContract.id(id)) throw OrganizationException(OrganizationFailure.MISSING)
        val result = requestQuery(id, session.uid).get(Source.SERVER).await()
        identity(session)
        result.documents.firstOrNull()?.let { record(it, session) }
    }

    override suspend fun create(
        draft: OrganizationDraft,
        rules: AuthLegalDocument,
        session: OrganizationSession,
        language: String,
    ): OrganizationRecord {
        identity(session)
        val fields = OrganizationContract.editableFields(draft)
        own(draft.id, session)?.let { existing ->
            if (fields.any { (key, value) -> existing.fields[key] != value })
                throw OrganizationException(OrganizationFailure.STALE)
            return existing // A previously uncertain create is recovered, never overwritten.
        }
        if (this.rules().version != rules.version)
            throw OrganizationException(OrganizationFailure.LEGAL_CHANGED)
        val payload =
            OrganizationContract.acceptancePayload(draft, rules, language, BuildConfig.VERSION_NAME)
        try {
            val response =
                functions
                    .getHttpsCallable("acceptOrganizationRules")
                    .withTimeout(20, TimeUnit.SECONDS)
                    .call(payload)
                    .await()
                    .data
            val accepted = OrganizationContract.acceptance(response, draft.id, rules.version)
            val receipts = read {
                db.collection("legalAcceptanceLogs")
                    .whereEqualTo("userId", session.uid)
                    .whereEqualTo("organizationId", draft.id)
                    .limit(20)
                    .get(Source.SERVER)
                    .await()
            }
            if (
                receipts.documents.none {
                    it.getString("documentType") == "organizationRules" &&
                        it.getString("version") == rules.version &&
                        it.getString("organizationName") == draft.name &&
                        it.getString("acceptedFromPlatform") == "android" &&
                        it.getTimestamp("acceptedAt")?.toDate()?.time?.let { timestamp ->
                            timestamp in
                                (accepted.toEpochMilli() - 1_000)..(accepted.toEpochMilli() +
                                        60_000)
                        } == true
                }
            )
                throw OrganizationException(OrganizationFailure.UNCONFIRMED)
            identity(session)
            db.runTransaction { transaction ->
                    identity(session)
                    // Forces an online transaction without attempting a denied read of an absent
                    // organization.
                    val user = transaction.get(db.document("users/${session.uid}"))
                    if (!user.exists()) throw OrganizationException(OrganizationFailure.NOT_READY)
                    transaction.set(
                        db.document("organizations/${draft.id}"),
                        OrganizationContract.create(draft, session, FieldValue.serverTimestamp()),
                    )
                }
                .await()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            throw OrganizationException(organizationFailure(error), error)
        }
        return own(draft.id, session)?.takeIf {
            it.status == "pendingReview" && fields.all { (key, value) -> it.fields[key] == value }
        } ?: throw OrganizationException(OrganizationFailure.UNCONFIRMED)
    }

    override suspend fun revise(
        base: OrganizationRecord,
        draft: OrganizationDraft,
        session: OrganizationSession,
    ): OrganizationRecord {
        identity(session)
        try {
            db.runTransaction { transaction ->
                    identity(session)
                    val actual =
                        record(transaction.get(db.document("organizations/${base.id}")), session)
                    OrganizationContract.requireEditable(actual, session)
                    if (actual.updatedAt != base.updatedAt || actual.status != base.status)
                        throw OrganizationException(OrganizationFailure.STALE)
                    val updates =
                        OrganizationContract.editableFields(draft, actual.fields).toMutableMap()
                    updates["updatedAt"] = FieldValue.serverTimestamp()
                    if (actual.status in setOf("needsRevision", "rejected")) {
                        updates["moderationStatus"] = "pendingReview"
                        updates["submittedAt"] = FieldValue.serverTimestamp()
                        updates["reviewMessage"] = FieldValue.delete()
                        updates["rejectionReason"] = FieldValue.delete()
                    }
                    transaction.update(db.document("organizations/${base.id}"), updates)
                }
                .await()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            throw OrganizationException(organizationFailure(error), error)
        }
        val actual =
            own(base.id, session) ?: throw OrganizationException(OrganizationFailure.UNCONFIRMED)
        val fields = OrganizationContract.editableFields(draft, base.fields)
        if (
            actual.status != "pendingReview" ||
                fields.any { (key, value) -> actual.fields[key] != value } ||
                (base.status != "pendingReview" &&
                    (actual.reviewMessage != null || actual.rejectionReason != null))
        )
            throw OrganizationException(OrganizationFailure.UNCONFIRMED)
        return actual
    }

    override suspend fun discard(base: OrganizationRecord, session: OrganizationSession) {
        identity(session)
        // The owner's existing callable branch is a broader O09 operation, not applicant discard.
        if (session.globalRole == "owner") throw OrganizationException(OrganizationFailure.DENIED)
        own(base.id, session)?.let { OrganizationContract.requireEditable(it, session) }
        val response =
            try {
                functions
                    .getHttpsCallable("deleteOrganization")
                    .withTimeout(60, TimeUnit.SECONDS)
                    .call(mapOf("organizationId" to base.id))
                    .await()
                    .data as? Map<*, *>
            } catch (error: Exception) {
                throw OrganizationException(organizationFailure(error), error)
            }
        if (
            response?.get("status") !in setOf("deleted", "alreadyDeleted") ||
                (response?.get("deletedAt") as? String)?.let {
                    runCatching { Instant.parse(it) }.getOrNull()
                } == null ||
                own(base.id, session) != null
        )
            throw OrganizationException(OrganizationFailure.UNCONFIRMED)
    }

    override suspend fun logo(
        base: OrganizationRecord,
        jpeg: ByteArray,
        session: OrganizationSession,
    ): OrganizationRecord {
        identity(session)
        val actual =
            own(base.id, session) ?: throw OrganizationException(OrganizationFailure.MISSING)
        OrganizationContract.requireEditable(actual, session)
        val url = storage.upload(base.id, jpeg)
        identity(session)
        try {
            db.runTransaction { transaction ->
                    identity(session)
                    val current =
                        record(transaction.get(db.document("organizations/${base.id}")), session)
                    OrganizationContract.requireEditable(current, session)
                    if (current.updatedAt != actual.updatedAt || current.status != actual.status)
                        throw OrganizationException(OrganizationFailure.STALE)
                    transaction.update(
                        db.document("organizations/${base.id}"),
                        mapOf(
                            "logoURL" to url,
                            "imageURL" to url,
                            "updatedAt" to FieldValue.serverTimestamp(),
                        ),
                    )
                }
                .await()
        } catch (error: Exception) {
            throw OrganizationException(organizationFailure(error), error)
        }
        return own(base.id, session)?.takeIf {
            it.fields["logoURL"] == url && it.fields["imageURL"] == url
        } ?: throw OrganizationException(OrganizationFailure.UNCONFIRMED)
    }
}

fun organizationFailure(error: Throwable): OrganizationFailure =
    when (error) {
        is OrganizationException -> error.failure
        is LocalCallableException ->
            when (error.code.name) {
                "PERMISSION_DENIED",
                "UNAUTHENTICATED" -> OrganizationFailure.DENIED
                "UNAVAILABLE",
                "DEADLINE_EXCEEDED" -> OrganizationFailure.OFFLINE
                "FAILED_PRECONDITION" -> OrganizationFailure.LEGAL_CHANGED
                "RESOURCE_EXHAUSTED" -> OrganizationFailure.LIMIT
                "INVALID_ARGUMENT" -> OrganizationFailure.INVALID
                "NOT_FOUND" -> OrganizationFailure.MISSING
                "UNCONFIRMED" -> OrganizationFailure.UNCONFIRMED
                else -> OrganizationFailure.UNKNOWN
            }
        is FirebaseFirestoreException ->
            when (error.code) {
                FirebaseFirestoreException.Code.PERMISSION_DENIED,
                FirebaseFirestoreException.Code.UNAUTHENTICATED -> OrganizationFailure.DENIED
                FirebaseFirestoreException.Code.UNAVAILABLE,
                FirebaseFirestoreException.Code.DEADLINE_EXCEEDED -> OrganizationFailure.OFFLINE
                FirebaseFirestoreException.Code.NOT_FOUND -> OrganizationFailure.MISSING
                FirebaseFirestoreException.Code.ABORTED ->
                    (error.cause as? OrganizationException)?.failure ?: OrganizationFailure.STALE
                else ->
                    (error.cause as? OrganizationException)?.failure ?: OrganizationFailure.UNKNOWN
            }
        else -> OrganizationFailure.UNKNOWN
    }
