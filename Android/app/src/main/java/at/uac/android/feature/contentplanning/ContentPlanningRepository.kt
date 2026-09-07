package at.uac.android.feature.contentplanning

import android.content.Context
import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalCallableFailure
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.CallableGateway
import at.uac.android.core.backend.FirebaseBackendGuard
import at.uac.android.feature.moderation.ModerationSession
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.DocumentSnapshot
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.Query
import com.google.firebase.firestore.Source
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext

fun contentPlanningRepository(
    context: Context,
    current: () -> ModerationSession?,
): ContentPlanningRepository =
    FirebaseContentPlanningRepository(
        AppBackend.firestore(context),
        AppBackend.auth(context),
        AppBackend.callables(context),
        current,
    )

interface ContentPlanningRepository {
    fun currentSession(): ModerationSession?

    suspend fun organizations(session: ModerationSession): List<ContentPlanningOrganization>

    suspend fun page(
        session: ModerationSession,
        section: ContentPlanningSection,
        after: ContentPlanningCursor? = null,
        limit: Int = ContentPlanningContract.PAGE_SIZE,
    ): ContentPlanningPage

    suspend fun draft(session: ModerationSession, draftId: String): ContentPlanningDraft

    /** Never retried here. An ambiguous response is surfaced for an explicit same-attempt retry. */
    suspend fun begin(
        session: ModerationSession,
        draftId: String,
        attemptId: String,
        canDispatch: () -> Boolean,
    ): ContentPlanningLease

    /**
     * Safe only with the exact retained lease; the server makes exact terminal retry idempotent.
     */
    suspend fun finalize(
        session: ModerationSession,
        draft: ContentPlanningDraft,
        lease: ContentPlanningLease,
        canDispatch: () -> Boolean,
    ): ContentPlanningState

    suspend fun fail(
        session: ModerationSession,
        draftId: String,
        leaseId: String,
        message: String,
        canDispatch: () -> Boolean,
    )

    suspend fun archive(
        session: ModerationSession,
        draftId: String,
        canDispatch: () -> Boolean,
    ): Boolean

    suspend fun delete(
        session: ModerationSession,
        draftId: String,
        canDispatch: () -> Boolean,
    ): Boolean
}

class FirebaseContentPlanningRepository(
    private val db: FirebaseFirestore,
    private val auth: FirebaseAuth,
    private val callables: CallableGateway,
    private val authority: () -> ModerationSession?,
) : ContentPlanningRepository {
    init {
        FirebaseBackendGuard.requireSameApp(auth, db)
        callables.requireBoundTo(auth)
    }

    override fun currentSession() = authority()

    override suspend fun organizations(
        session: ModerationSession
    ): List<ContentPlanningOrganization> =
        withContext(Dispatchers.IO) {
            require(session)
            try {
                val result =
                    db.collection("organizations")
                        .whereEqualTo("moderationStatus", "approved")
                        .limit(51)
                        .get(Source.SERVER)
                        .await()
                require(session)
                if (result.metadata.isFromCache)
                    ContentPlanningContract.fail(ContentPlanningFailure.OFFLINE)
                if (result.size() > 50) ContentPlanningContract.fail(ContentPlanningFailure.INVALID)
                result.documents
                    .map { document ->
                        val name = document.getString("name")?.trim().orEmpty()
                        if (
                            !at.uac.android.feature.organization.OrganizationContract.id(
                                document.id
                            ) || name.isEmpty() || name.length > 200 || name.any(Char::isISOControl)
                        )
                            ContentPlanningContract.invalid()
                        ContentPlanningOrganization(document.id, name)
                    }
                    .sortedBy { it.name.lowercase() }
            } catch (error: CancellationException) {
                throw error
            } catch (error: ContentPlanningException) {
                throw error
            } catch (error: Exception) {
                throw mapped(error)
            }
        }

    private fun require(session: ModerationSession) {
        ContentPlanningContract.requireOwner(session.uid, session.role, session.ready)
        if (authority() != session || auth.currentUser?.uid != session.uid)
            ContentPlanningContract.fail(ContentPlanningFailure.DENIED)
    }

    override suspend fun page(
        session: ModerationSession,
        section: ContentPlanningSection,
        after: ContentPlanningCursor?,
        limit: Int,
    ): ContentPlanningPage =
        withContext(Dispatchers.IO) {
            require(session)
            if (
                limit !in 1..50 ||
                    after?.let { !ContentPlanningContract.validDraftId(it.documentId) } == true
            )
                ContentPlanningContract.invalid()
            var query: Query = db.collection("users/${session.uid}/contentPlanningDrafts")
            query =
                if (section.states.size == 1)
                    query.whereEqualTo("state", section.states.single().wire)
                else query.whereIn("state", section.states.map(ContentPlanningState::wire))
            query =
                query
                    .orderBy(
                        section.sortField,
                        if (section.ascending) Query.Direction.ASCENDING
                        else Query.Direction.DESCENDING,
                    )
                    .orderBy(
                        com.google.firebase.firestore.FieldPath.documentId(),
                        if (section.ascending) Query.Direction.ASCENDING
                        else Query.Direction.DESCENDING,
                    )
                    .limit((limit + 1).toLong())
            if (after != null)
                query =
                    query.startAfter(
                        Timestamp(after.sortDate.epochSecond, after.sortDate.nano),
                        after.documentId,
                    )
            try {
                val result = query.get(Source.SERVER).await()
                require(session)
                if (result.metadata.isFromCache)
                    ContentPlanningContract.fail(ContentPlanningFailure.OFFLINE)
                val selected = result.documents.take(limit)
                val items = selected.map { parse(it, session.uid) }
                val cursor =
                    selected.lastOrNull()?.let { document ->
                        ContentPlanningCursor(document.instant(section.sortField), document.id)
                    }
                ContentPlanningPage(items, cursor, result.size() > limit)
            } catch (error: CancellationException) {
                throw error
            } catch (error: ContentPlanningException) {
                throw error
            } catch (error: Exception) {
                throw mapped(error)
            }
        }

    override suspend fun draft(session: ModerationSession, draftId: String): ContentPlanningDraft =
        withContext(Dispatchers.IO) {
            require(session)
            if (!ContentPlanningContract.validDraftId(draftId)) ContentPlanningContract.invalid()
            try {
                val result =
                    db.document("users/${session.uid}/contentPlanningDrafts/$draftId")
                        .get(Source.SERVER)
                        .await()
                require(session)
                if (result.metadata.isFromCache)
                    ContentPlanningContract.fail(ContentPlanningFailure.OFFLINE)
                if (!result.exists()) ContentPlanningContract.fail(ContentPlanningFailure.MISSING)
                parse(result, session.uid)
            } catch (error: CancellationException) {
                throw error
            } catch (error: ContentPlanningException) {
                throw error
            } catch (error: Exception) {
                throw mapped(error)
            }
        }

    override suspend fun begin(
        session: ModerationSession,
        draftId: String,
        attemptId: String,
        canDispatch: () -> Boolean,
    ): ContentPlanningLease =
        mutation(session, canDispatch) {
            val raw =
                call(
                    ContentPlanningContract.BEGIN,
                    ContentPlanningContract.beginPayload(draftId, attemptId),
                )
            ContentPlanningContract.lease(raw, draftId)
        }

    override suspend fun finalize(
        session: ModerationSession,
        draft: ContentPlanningDraft,
        lease: ContentPlanningLease,
        canDispatch: () -> Boolean,
    ): ContentPlanningState =
        mutation(session, canDispatch) {
            val raw =
                call(
                    ContentPlanningContract.FINALIZE,
                    ContentPlanningContract.finalizePayload(draft, lease),
                )
            ContentPlanningContract.finalized(raw, lease)
        }

    override suspend fun fail(
        session: ModerationSession,
        draftId: String,
        leaseId: String,
        message: String,
        canDispatch: () -> Boolean,
    ) {
        mutation(session, canDispatch) {
            val raw =
                call(
                    ContentPlanningContract.FAIL,
                    ContentPlanningContract.failPayload(draftId, leaseId, message),
                )
            if (!ContentPlanningContract.acknowledged(raw, "failed"))
                ContentPlanningContract.invalid()
        }
    }

    override suspend fun archive(
        session: ModerationSession,
        draftId: String,
        canDispatch: () -> Boolean,
    ): Boolean =
        mutation(session, canDispatch) {
            ContentPlanningContract.acknowledged(
                call(
                    ContentPlanningContract.ARCHIVE,
                    ContentPlanningContract.draftPayload(draftId),
                ),
                "archived",
            )
        }

    override suspend fun delete(
        session: ModerationSession,
        draftId: String,
        canDispatch: () -> Boolean,
    ): Boolean =
        mutation(session, canDispatch) {
            ContentPlanningContract.acknowledged(
                call(ContentPlanningContract.DELETE, ContentPlanningContract.draftPayload(draftId)),
                "deleted",
            )
        }

    private suspend fun <T> mutation(
        session: ModerationSession,
        canDispatch: () -> Boolean,
        block: suspend () -> T,
    ): T =
        withContext(Dispatchers.IO) {
            require(session)
            if (!canDispatch()) ContentPlanningContract.fail(ContentPlanningFailure.DENIED)
            try {
                block().also { require(session) }
            } catch (error: CancellationException) {
                throw error
            } catch (error: ContentPlanningException) {
                throw error
            } catch (error: Exception) {
                throw mapped(error)
            }
        }

    private suspend fun call(name: String, payload: Map<String, Any?>): Any? =
        callables
            .getHttpsCallable(name)
            .withTimeout(60, TimeUnit.SECONDS)
            .call(payload)
            .await()
            .data

    private fun parse(document: DocumentSnapshot, expectedOwner: String): ContentPlanningDraft {
        val data = document.data ?: ContentPlanningContract.invalid()
        val kind = ContentPlanningContract.kind(data.string("kind"))
        val state =
            ContentPlanningState.parse(data.string("state")) ?: ContentPlanningContract.invalid()
        val payload = data["payload"].toPlanningMap()
        val sources =
            (data["sources"] as? List<*>)?.map { source ->
                val value = source.record()
                ContentPlanningSource(
                    value.string("url"),
                    value.optionalString("title"),
                    value["isPrimary"] as? Boolean ?: ContentPlanningContract.invalid(),
                    value.optionalTimestamp("checkedAt"),
                )
            } ?: ContentPlanningContract.invalid()
        val outcomeValue = data.optionalString("publicationOutcome")
        val outcome = outcomeValue?.let {
            ContentPlanningOutcome.parse(it) ?: ContentPlanningContract.invalid()
        }
        val draft =
            ContentPlanningDraft(
                document.id,
                (data["schemaVersion"] as? Number)?.toInt() ?: ContentPlanningContract.invalid(),
                data.string("ownerUserId"),
                kind,
                state,
                data.string("title"),
                payload,
                sources,
                data.stringList("verificationNotes"),
                data.stringList("missingFields"),
                document.instant("createdAt"),
                document.instant("updatedAt"),
                data.optionalTimestamp("scheduledAt"),
                data.optionalTimestamp("completedAt"),
                data.optionalTimestamp("archivedAt"),
                data.optionalString("failureMessage"),
                data.optionalTimestamp("publicationLeaseExpiresAt"),
                data.optionalString("publishedContentId"),
                data.optionalString("publishedContentKind")?.let(ContentPlanningContract::kind),
                data.optionalString("publishedOrganizationId"),
                data.optionalString("publishedOrganizationName"),
                outcome,
            )
        ContentPlanningContract.validateDraft(draft, expectedOwner)
        return draft
    }

    private fun mapped(error: Exception): ContentPlanningException {
        val failure =
            when (error) {
                is LocalCallableException ->
                    when (error.code) {
                        LocalCallableFailure.UNAUTHENTICATED -> ContentPlanningFailure.SIGN_IN
                        LocalCallableFailure.PERMISSION_DENIED -> ContentPlanningFailure.DENIED
                        LocalCallableFailure.NOT_FOUND -> ContentPlanningFailure.MISSING
                        LocalCallableFailure.ABORTED,
                        LocalCallableFailure.FAILED_PRECONDITION -> ContentPlanningFailure.CONFLICT
                        LocalCallableFailure.UNAVAILABLE,
                        LocalCallableFailure.DEADLINE_EXCEEDED -> ContentPlanningFailure.OFFLINE
                        LocalCallableFailure.UNCONFIRMED -> ContentPlanningFailure.UNCONFIRMED
                        LocalCallableFailure.INVALID_ARGUMENT,
                        LocalCallableFailure.DATA_LOSS -> ContentPlanningFailure.INVALID
                        else -> ContentPlanningFailure.UNKNOWN
                    }
                is FirebaseFirestoreException ->
                    when (error.code) {
                        FirebaseFirestoreException.Code.PERMISSION_DENIED ->
                            ContentPlanningFailure.DENIED
                        FirebaseFirestoreException.Code.UNAUTHENTICATED ->
                            ContentPlanningFailure.SIGN_IN
                        FirebaseFirestoreException.Code.UNAVAILABLE,
                        FirebaseFirestoreException.Code.DEADLINE_EXCEEDED ->
                            ContentPlanningFailure.OFFLINE
                        FirebaseFirestoreException.Code.FAILED_PRECONDITION ->
                            ContentPlanningFailure.INDEX
                        FirebaseFirestoreException.Code.NOT_FOUND -> ContentPlanningFailure.MISSING
                        else -> ContentPlanningFailure.UNKNOWN
                    }
                else -> ContentPlanningFailure.UNKNOWN
            }
        return ContentPlanningException(failure, error)
    }
}

private fun DocumentSnapshot.instant(key: String): Instant =
    (get(key) as? Timestamp)?.let { Instant.ofEpochSecond(it.seconds, it.nanoseconds.toLong()) }
        ?: ContentPlanningContract.invalid()

private fun Map<String, Any?>.optionalTimestamp(key: String): Instant? =
    when (val value = this[key]) {
        null -> null
        is Timestamp -> Instant.ofEpochSecond(value.seconds, value.nanoseconds.toLong())
        else -> ContentPlanningContract.invalid()
    }

private fun Map<String, Any?>.stringList(key: String): List<String> =
    (this[key] as? List<*>)?.map { it as? String ?: ContentPlanningContract.invalid() }
        ?: emptyList()

private fun Any?.toPlanningMap(): Map<String, Any?> =
    record().mapValues { (_, value) -> planningValue(value, 0) }

private fun planningValue(value: Any?, depth: Int): Any? {
    if (depth > 16) ContentPlanningContract.invalid()
    return when (value) {
        null,
        is String,
        is Boolean,
        is Byte,
        is Short,
        is Int,
        is Long,
        is Float,
        is Double -> value
        is Timestamp -> Instant.ofEpochSecond(value.seconds, value.nanoseconds.toLong())
        is Map<*, *> ->
            value.entries.associate { (key, child) ->
                (key as? String ?: ContentPlanningContract.invalid()) to
                    planningValue(child, depth + 1)
            }
        is List<*> -> value.map { planningValue(it, depth + 1) }
        else -> ContentPlanningContract.invalid()
    }
}
