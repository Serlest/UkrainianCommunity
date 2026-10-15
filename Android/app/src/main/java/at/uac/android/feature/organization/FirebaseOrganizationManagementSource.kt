package at.uac.android.feature.organization

import android.content.Context
import at.uac.android.BuildConfig
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalCallableFailure
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.CallableGateway
import at.uac.android.core.backend.FirebaseBackendGuard
import at.uac.android.feature.browse.Fields
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.organizationaccess.OrganizationAccessReader
import at.uac.android.feature.organizationaccess.OrganizationAccessSource
import at.uac.android.feature.organizationaccess.OrganizationCommand
import at.uac.android.feature.organizationaccess.OrganizationUpdateAttempt
import at.uac.android.feature.organizationaccess.OrganizationVersion
import at.uac.android.feature.organizationaccess.OrganizationPhotoVersion
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
import java.security.MessageDigest
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeout

internal enum class OrganizationInformationRoute {
    LEGACY,
    CALLABLE,
    DENIED,
}

internal fun organizationInformationRoute(
    snapshot: at.uac.android.feature.organizationaccess.OrganizationAccessSnapshot,
    organizationId: String,
): OrganizationInformationRoute =
    when {
        snapshot.actionModes["editInfo"] != "enforced" -> OrganizationInformationRoute.LEGACY
        snapshot.commands[OrganizationCommand.UPDATE_INFO] == true &&
            snapshot.allows(organizationId, "editInfo") -> OrganizationInformationRoute.CALLABLE
        else -> OrganizationInformationRoute.DENIED
    }

fun localOrganizationManagementSource(context: Context): OrganizationManagementSource =
    FirebaseOrganizationManagementSource(
        AppBackend.firestore(context),
        AppBackend.auth(context),
        AppBackend.callables(context),
        LocalOrganizationStorage.instance(context),
    )

class FirebaseOrganizationManagementSource(
    private val db: FirebaseFirestore,
    private val auth: FirebaseAuth,
    private val functions: CallableGateway,
    private val storage: OrganizationLogoStorage,
) : OrganizationManagementSource {
    init {
        LocalEnvironment.requireSafe()
        FirebaseBackendGuard.requireSameApp(auth, db)
        functions.requireBoundTo(auth)
    }

    private val access =
        OrganizationAccessSource(
            functions,
            object : OrganizationAccessReader {
                override suspend fun read(organizationId: String): OrganizationVersion? {
                    val snapshot =
                        db.document("organizations/$organizationId").get(Source.SERVER).await()
                    if (!snapshot.exists()) return null
                    return OrganizationVersion(
                        organizationId,
                        (snapshot.getTimestamp("updatedAt"))?.let {
                            "${it.seconds}:${it.nanoseconds}"
                        },
                        snapshot.data.orEmpty().mapValues { decoded(it.value) },
                    )
                }

                override suspend fun readPhoto(
                    organizationId: String,
                    photoId: String,
                ): OrganizationPhotoVersion? {
                    val snapshot =
                        db.document("organizations/$organizationId/photos/$photoId")
                            .get(Source.SERVER)
                            .await()
                    if (!snapshot.exists()) return null
                    val image = snapshot.getString("imageURL") ?: return null
                    return OrganizationPhotoVersion(organizationId, photoId, image)
                }
            },
        )

    private fun identity(session: OrganizationSession) {
        if (auth.currentUser?.uid != session.uid)
            throw CancellationException("Organization management identity changed")
        if (
            !session.ready ||
                auth.currentUser?.isEmailVerified != true ||
                auth.currentUser?.isAnonymous != false
        )
            fail(OrganizationManagementFailure.NOT_READY)
    }

    private fun query(id: String): Query {
        if (!OrganizationContract.id(id)) fail(OrganizationManagementFailure.INVALID)
        return db.collection("organizations")
            .whereGreaterThanOrEqualTo(FieldPath.documentId(), id)
            .whereLessThanOrEqualTo(FieldPath.documentId(), id)
            .whereEqualTo("moderationStatus", "approved")
            .limit(1)
    }

    private fun subscribersQuery(id: String): Query =
        db.collection("likes")
            .whereEqualTo("subscribedOrganizationId", id)
            .orderBy("createdAt", Query.Direction.DESCENDING)
            .orderBy(FieldPath.documentId(), Query.Direction.DESCENDING)

    private fun decoded(value: Any?): Any? =
        when (value) {
            is Timestamp -> Instant.ofEpochSecond(value.seconds, value.nanoseconds.toLong())
            is Map<*, *> -> value.entries.associate { it.key.toString() to decoded(it.value) }
            is List<*> -> value.map(::decoded)
            else -> value
        }

    private fun encoded(value: Any?): Any? =
        when (value) {
            is Instant -> Timestamp(value.epochSecond, value.nano)
            is Map<*, *> -> value.entries.associate { it.key.toString() to encoded(it.value) }
            is List<*> -> value.map(::encoded)
            else -> value
        }

    @Suppress("UNCHECKED_CAST")
    private fun raw(snapshot: DocumentSnapshot): RawDocument =
        RawDocument(
            snapshot.id,
            decoded(snapshot.data ?: fail(OrganizationManagementFailure.MISSING)) as Fields,
        )

    private fun record(
        snapshot: DocumentSnapshot,
        session: OrganizationSession,
    ): OrganizationRecord = OrganizationContract.record(raw(snapshot), session)

    private suspend fun <T> read(session: OrganizationSession, action: suspend () -> T): T =
        try {
            identity(session)
            withTimeout(15_000) { action() }.also { identity(session) }
        } catch (error: TimeoutCancellationException) {
            throw OrganizationManagementException(OrganizationManagementFailure.OFFLINE, error)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            throw OrganizationManagementException(organizationManagementFailure(error), error)
        }

    override suspend fun organization(
        id: String,
        session: OrganizationSession,
    ): OrganizationRecord? =
        read(session) {
            query(id).get(Source.SERVER).await().documents.firstOrNull()?.let {
                record(it, session)
            }
        }

    override suspend fun subscribers(
        id: String,
        after: OrganizationSubscriberCursor?,
        session: OrganizationSession,
    ): OrganizationSubscriberPage =
        read(session) {
            if (
                !OrganizationContract.id(id) ||
                    after?.documentId?.let { !OrganizationManagementContract.documentId(it) } ==
                        true
            )
                fail(OrganizationManagementFailure.INVALID)
            var query =
                subscribersQuery(id).limit((OrganizationManagementContract.PAGE_SIZE + 1).toLong())
            if (after != null)
                query =
                    query.startAfter(
                        Timestamp(after.followedAt.epochSecond, after.followedAt.nano),
                        after.documentId,
                    )
            OrganizationManagementContract.page(
                query.get(Source.SERVER).await().documents.map(::raw),
                id,
                after,
            )
        }

    override suspend fun profiles(
        ids: List<String>,
        session: OrganizationSession,
    ): List<OrganizationPublicMember> =
        read(session) {
            if (
                ids.size >
                    OrganizationManagementContract.MAX_TEAM_PROFILES +
                        OrganizationManagementContract.PAGE_SIZE ||
                    ids.any { !OrganizationManagementContract.userId(it) }
            )
                fail(OrganizationManagementFailure.INVALID)
            val rows =
                ids.distinct()
                    .chunked(10)
                    .flatMap { chunk ->
                        db.collection("publicProfiles")
                            .whereIn(FieldPath.documentId(), chunk)
                            .get(Source.SERVER)
                            .await()
                            .documents
                            .map { snapshot ->
                                OrganizationManagementContract.profile(
                                    snapshot.id,
                                    raw(snapshot).fields,
                                )
                            }
                    }
                    .associateBy { it.id }
            ids.distinct().map { rows[it] ?: OrganizationManagementContract.profile(it, null) }
        }

    override fun changes(id: String, session: OrganizationSession): Flow<Result<Unit>> =
        callbackFlow {
            identity(session)
            val registrations =
                listOf(
                        query(id),
                        subscribersQuery(id)
                            .limit(OrganizationManagementContract.PAGE_SIZE.toLong()),
                    )
                    .map { query ->
                        query.addSnapshotListener(MetadataChanges.INCLUDE) { snapshot, error ->
                            if (error != null)
                                trySend(
                                    Result.failure(
                                        OrganizationManagementException(
                                            organizationManagementFailure(error),
                                            error,
                                        )
                                    )
                                )
                            else if (
                                snapshot != null &&
                                    !snapshot.metadata.isFromCache &&
                                    !snapshot.metadata.hasPendingWrites()
                            )
                                trySend(Result.success(Unit))
                        }
                    }
            awaitClose { registrations.forEach { it.remove() } }
        }

    override suspend fun update(
        base: OrganizationRecord,
        fields: Fields,
        session: OrganizationSession,
    ) {
        identity(session)
        if (
            fields.isEmpty() ||
                fields.keys.any {
                    it !in OrganizationManagementContract.safeFields || it == "updatedAt"
                }
        )
            fail(OrganizationManagementFailure.INVALID)
        val command = organizationInformationCommand(base, fields, session)
        if (command) return
        try {
            db.runTransaction { transaction ->
                    identity(session)
                    val actual =
                        record(transaction.get(db.document("organizations/${base.id}")), session)
                    requireUnchangedEditable(base, actual, session)
                    val updates =
                        fields.mapValues { encoded(it.value) } +
                            ("updatedAt" to FieldValue.serverTimestamp())
                    transaction.update(db.document("organizations/${base.id}"), updates)
                }
                .await()
            identity(session)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            throw OrganizationManagementException(organizationManagementFailure(error), error)
        }
    }

    /**
     * Uses the build 68 command only when the server marks this exact action as enforced. Shadow
     * rollout keeps the already-audited Rules transaction. An enforced denial always fails closed.
     */
    private suspend fun organizationInformationCommand(
        base: OrganizationRecord,
        fields: Fields,
        session: OrganizationSession,
    ): Boolean {
        val snapshot =
            try {
                access.access(
                    session.uid,
                    listOf(base.id),
                    mapOf(base.id to mapOf("editInfo" to OrganizationManagementContract.canEdit(base, session))),
                    BuildConfig.VERSION_NAME,
                )
            } catch (error: CancellationException) {
                throw error
            } catch (error: LocalCallableException) {
                // A pre-build-68 emulator/server has no capability endpoint and remains on v1.
                if (error.code == LocalCallableFailure.NOT_FOUND) return false
                throw OrganizationManagementException(organizationManagementFailure(error), error)
            } catch (error: Exception) {
                throw OrganizationManagementException(organizationManagementFailure(error), error)
            }
        identity(session)
        when (organizationInformationRoute(snapshot, base.id)) {
            OrganizationInformationRoute.LEGACY -> return false
            OrganizationInformationRoute.DENIED -> fail(OrganizationManagementFailure.DENIED)
            OrganizationInformationRoute.CALLABLE -> Unit
        }
        val wire = fields.mapValues { callableValue(it.value) }
        val operationId =
            sha256(
                listOf(session.uid, base.id, organizationRevision(base), base.status, stable(wire))
                    .joinToString("\u0000")
            )
        try {
            access.update(
                OrganizationUpdateAttempt(
                    session.uid,
                    base.id,
                    operationId,
                    organizationRevision(base),
                    base.status,
                    wire,
                ),
                BuildConfig.VERSION_NAME,
            )
            identity(session)
            return true
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            throw OrganizationManagementException(organizationManagementFailure(error), error)
        }
    }

    private fun organizationRevision(value: OrganizationRecord) =
        "${value.updatedAt.epochSecond}:${value.updatedAt.nano}"

    private fun callableValue(value: Any?): Any? =
        when (value) {
            is Instant ->
                mapOf(
                    "__timestamp" to
                        mapOf("seconds" to value.epochSecond, "nanoseconds" to value.nano.toLong())
                )
            is Map<*, *> ->
                value.entries.associate { it.key.toString() to callableValue(it.value) }
            is List<*> -> value.map(::callableValue)
            else -> value
        }

    private fun stable(value: Any?): String =
        when (value) {
            null -> "null"
            is String -> "s:${value.length}:$value"
            is Number -> "n:$value"
            is Boolean -> "b:$value"
            is Map<*, *> ->
                value.entries.sortedBy { it.key.toString() }.joinToString("{", "}") {
                    stable(it.key.toString()) + ":" + stable(it.value)
                }
            is List<*> -> value.joinToString("[", "]") { stable(it) }
            else -> throw OrganizationManagementException(OrganizationManagementFailure.INVALID)
        }

    private fun sha256(value: String) =
        MessageDigest.getInstance("SHA-256").digest(value.toByteArray()).joinToString("") {
            "%02x".format(it.toInt() and 255)
        }

    private fun requireUnchangedEditable(
        base: OrganizationRecord,
        actual: OrganizationRecord,
        session: OrganizationSession,
    ) {
        if (!OrganizationManagementContract.canEdit(actual, session))
            fail(OrganizationManagementFailure.DENIED)
        if (
            base.id != actual.id ||
                actual.fields != base.fields ||
                actual.updatedAt != base.updatedAt
        )
            fail(OrganizationManagementFailure.STALE)
    }

    override suspend fun logo(
        base: OrganizationRecord,
        jpeg: ByteArray,
        session: OrganizationSession,
    ): OrganizationRecord {
        val before = organization(base.id, session) ?: fail(OrganizationManagementFailure.MISSING)
        requireUnchangedEditable(base, before, session)
        val url =
            try {
                storage.upload(base.id, jpeg)
            } catch (error: Exception) {
                throw OrganizationManagementException(organizationManagementFailure(error), error)
            }
        identity(session)
        update(before, mapOf("logoURL" to url, "imageURL" to url), session)
        return organization(base.id, session)?.takeIf {
            it.fields["logoURL"] == url && it.fields["imageURL"] == url
        } ?: fail(OrganizationManagementFailure.UNCONFIRMED)
    }

    override suspend fun role(
        base: OrganizationRecord,
        intent: OrganizationRoleIntent,
        session: OrganizationSession,
    ): Any? {
        identity(session)
        val before = organization(base.id, session) ?: fail(OrganizationManagementFailure.MISSING)
        OrganizationManagementContract.requireIntent(before, intent, session)
        if (
            before.fields != base.fields ||
                before.updatedAt != base.updatedAt ||
                OrganizationManagementContract.role(before, intent.targetId) != intent.previousRole
        )
            fail(OrganizationManagementFailure.STALE)
        // Existing server API has no expectedRole/version CAS. Confirmation describes removal of
        // any non-owner role.
        // This call is non-idempotent; the transport never automatically retries it after a send.
        return try {
            functions
                .getHttpsCallable(OrganizationManagementContract.callable(intent))
                .withTimeout(20, TimeUnit.SECONDS)
                .call(OrganizationManagementContract.payload(before, intent))
                .await()
                .data
                .also { identity(session) }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            throw OrganizationManagementException(organizationManagementFailure(error), error)
        }
    }

    override suspend fun delete(base: OrganizationRecord, session: OrganizationSession): Any? {
        identity(session)
        if (session.globalRole != "owner" || base.id == "ukrainian-community")
            fail(OrganizationManagementFailure.DENIED)
        // Destructive callable: one send only. A timeout is reported as uncertain; the client
        // must read server state before deciding whether another action is possible.
        return try {
            functions.getHttpsCallable("deleteOrganization")
                .withTimeout(300, TimeUnit.SECONDS)
                .call(mapOf("organizationId" to base.id))
                .await().data.also { identity(session) }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            throw OrganizationManagementException(organizationManagementFailure(error), error)
        }
    }

    private fun fail(failure: OrganizationManagementFailure): Nothing =
        OrganizationManagementContract.fail(failure)
}

internal fun organizationManagementSdkFailure(error: Throwable): OrganizationManagementFailure =
    when (error) {
        is FirebaseFirestoreException ->
            when (error.code) {
                FirebaseFirestoreException.Code.PERMISSION_DENIED,
                FirebaseFirestoreException.Code.UNAUTHENTICATED ->
                    OrganizationManagementFailure.DENIED
                FirebaseFirestoreException.Code.UNAVAILABLE,
                FirebaseFirestoreException.Code.DEADLINE_EXCEEDED ->
                    OrganizationManagementFailure.OFFLINE
                FirebaseFirestoreException.Code.NOT_FOUND -> OrganizationManagementFailure.MISSING
                FirebaseFirestoreException.Code.ABORTED ->
                    error.cause?.let(::organizationManagementFailure)
                        ?: OrganizationManagementFailure.STALE
                else ->
                    error.cause?.let(::organizationManagementFailure)
                        ?: OrganizationManagementFailure.UNKNOWN
            }
        else -> OrganizationManagementFailure.UNKNOWN
    }
