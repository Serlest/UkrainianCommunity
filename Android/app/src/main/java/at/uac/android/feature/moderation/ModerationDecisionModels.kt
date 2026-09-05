package at.uac.android.feature.moderation

import at.uac.android.core.backend.CompiledBackend
import java.security.MessageDigest
import java.time.Instant
import java.util.UUID

enum class ModerationDecision(val wire: String) {
    APPROVE("approved"),
    REJECT("rejected"),
}

enum class ModerationDecisionPhase {
    PREPARED,
    DISPATCHED,
    ACKNOWLEDGED,
}

enum class ModerationDecisionFailure {
    ACCESS,
    STALE,
    INVALID,
    JOURNAL,
    PENDING,
    OFFLINE,
    UNCONFIRMED,
    CONFLICT,
}

class ModerationDecisionException(
    val failure: ModerationDecisionFailure,
    cause: Throwable? = null,
) : Exception(failure.name, cause)

enum class ModerationObservation {
    CONFIRMED_CURRENT,
    CONFIRMED_CHANGED,
    CONFIRMED_UNAVAILABLE,
    OBSERVED_WITHOUT_RECEIPT,
    UNCONFIRMED,
    CONFLICT,
    AUTHORITY_LIMITED;

    val confirmed
        get() = this in setOf(CONFIRMED_CURRENT, CONFIRMED_CHANGED, CONFIRMED_UNAVAILABLE)
}

data class ModerationPending(
    val accountHash: String,
    val version: ModerationReviewVersion,
    val operationId: String,
    val issuedRole: String,
    val decision: ModerationDecision,
    val issuedAt: Instant,
    val phase: ModerationDecisionPhase,
    val backend: String = CompiledBackend.PROJECT_ID,
) {
    override fun toString() = "ModerationPending(phase=$phase, [redacted])"
}

interface ModerationDecisionSource {
    suspend fun authorize(session: ModerationSession)

    suspend fun execute(
        session: ModerationSession,
        pending: ModerationPending,
        canDispatch: () -> Boolean,
    )

    suspend fun reconcile(
        session: ModerationSession,
        pending: ModerationPending,
    ): ModerationObservation
}

interface ModerationDecisionGate {
    suspend fun <T> withSession(session: ModerationSession, action: suspend () -> T): T
}

interface ModerationDecisionJournal {
    suspend fun pending(uid: String): List<ModerationPending>

    suspend fun put(
        uid: String,
        entry: ModerationPending,
        expected: ModerationPending? = null,
    ): ModerationPending

    suspend fun clear(uid: String, expected: ModerationPending)
}

object ModerationDecisionContract {
    fun fail(value: ModerationDecisionFailure): Nothing = throw ModerationDecisionException(value)

    fun accountHash(uid: String): String {
        if (uid.isBlank() || uid.length > 128) fail(ModerationDecisionFailure.ACCESS)
        return MessageDigest.getInstance("SHA-256")
            .digest(uid.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
    }

    fun validate(entry: ModerationPending) {
        entry.version.validate()
        if (
            !Regex("[a-f0-9]{64}").matches(entry.accountHash) ||
                entry.backend != CompiledBackend.PROJECT_ID ||
                entry.issuedRole !in setOf("owner", "admin") ||
                runCatching { UUID.fromString(entry.operationId).toString() }.getOrNull() !=
                    entry.operationId
        )
            fail(ModerationDecisionFailure.INVALID)
    }

    fun requireSession(session: ModerationSession?) {
        if (session?.allowed != true || session.uid.isBlank())
            fail(ModerationDecisionFailure.ACCESS)
    }

    fun requireOwner(session: ModerationSession, entry: ModerationPending) {
        requireSession(session)
        validate(entry)
        if (accountHash(session.uid) != entry.accountHash) fail(ModerationDecisionFailure.ACCESS)
    }

    /** Exact immutable audit fields; values intentionally match the existing iOS DTO/schema. */
    fun receiptFields(entry: ModerationPending, actorUid: String): Map<String, Any> {
        validate(entry)
        if (accountHash(actorUid) != entry.accountHash) fail(ModerationDecisionFailure.ACCESS)
        val event = entry.version.target.kind == ModerationKind.EVENT
        val approved = entry.decision == ModerationDecision.APPROVE
        return mapOf(
            "id" to entry.operationId,
            "correlationId" to entry.operationId,
            "category" to "moderation",
            "severity" to "notice",
            "severityRank" to 2L,
            "eventType" to if (approved) "contentApproved" else "contentRejected",
            "actorUserId" to actorUid,
            "actorRole" to entry.issuedRole,
            "targetType" to if (event) "event" else "newsPost",
            "targetId" to entry.version.target.id,
            "moduleName" to "Moderation",
            "operationName" to
                "${if (approved) "approve" else "reject"}${if (event) "Event" else "NewsPost"}",
            "outcome" to entry.decision.wire,
            "summary" to
                "${if (event) "Подію" else "Новину"} ${if (approved) "схвалено" else "відхилено"}",
            "isAppAdminReadable" to (entry.issuedRole != "owner"),
            "retentionPolicy" to "moderationDispute",
            "metadata" to
                mapOf(
                    "schemaVersion" to "1",
                    "clientPath" to "androidAtomicModeration",
                    "previousStatus" to "pendingReview",
                    "newStatus" to entry.decision.wire,
                    "reviewHash" to entry.version.reviewHash,
                    "preservedHash" to entry.version.preservedHash,
                ),
        )
    }

    fun receiptTime(entry: ModerationPending, uid: String, fields: Map<String, Any?>): Instant? {
        val expected = receiptFields(entry, uid)
        if (
            fields.keys.any {
                it !in expected.keys &&
                    it !in setOf("createdAt", "isReviewed", "reviewedAt", "reviewedByUserId")
            } ||
                expected.any { (key, value) -> fields[key] != value } ||
                fields["isReviewed"] !is Boolean
        )
            return null
        if (
            fields["isReviewed"] == false &&
                fields.keys.any { it == "reviewedAt" || it == "reviewedByUserId" }
        )
            return null
        if (
            fields["isReviewed"] == true &&
                (ModerationReviewVersion.instant(fields["reviewedAt"]) == null ||
                    (fields["reviewedByUserId"] as? String).isNullOrBlank())
        )
            return null
        return ModerationReviewVersion.instant(fields["createdAt"])
    }
}
