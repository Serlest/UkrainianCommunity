package at.uac.android.feature.organizationreview

import at.uac.android.core.LocalCallableProtocol
import at.uac.android.core.backend.CompiledBackend
import at.uac.android.feature.moderation.ModerationSession
import com.google.firebase.Timestamp
import java.io.DataOutputStream
import java.io.OutputStream
import java.security.MessageDigest
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.flow.Flow

enum class OrganizationReviewAction(
    val callable: String,
    val status: String,
    val textField: String?,
) {
    APPROVE("approveOrganization", "approved", null),
    REQUEST_REVISION("requestOrganizationRevision", "needsRevision", "message"),
    REJECT("rejectOrganization", "rejected", "reason"),
}

enum class OrganizationReviewFailure {
    ACCESS,
    STALE,
    INVALID,
    JOURNAL,
    PENDING,
    OFFLINE,
    UNCONFIRMED,
}

class OrganizationReviewException(
    val failure: OrganizationReviewFailure,
    cause: Throwable? = null,
) : Exception(failure.name, cause)

enum class OrganizationReviewObservation {
    CONFIRMED_CURRENT,
    CONFIRMED_CHANGED,
    CONFIRMED_UNAVAILABLE,
    OBSERVED_WITHOUT_RECEIPT,
    UNCONFIRMED,
    UNAVAILABLE;

    val confirmed
        get() = this in setOf(CONFIRMED_CURRENT, CONFIRMED_CHANGED, CONFIRMED_UNAVAILABLE)
}

data class OrganizationReviewVersion(
    val organizationId: String,
    val fingerprint: String,
    val preservedApprovalHash: String,
    val preservedOtherHash: String,
    val submitterHash: String,
) {
    override fun toString() = "OrganizationReviewVersion([redacted])"
}

data class OrganizationReviewSnapshot(
    val version: OrganizationReviewVersion,
    val name: String,
    val status: String,
    val submitterId: String,
) {
    override fun toString() = "OrganizationReviewSnapshot([redacted])"
}

/** Wire time is NOT a Firestore commit timestamp. No equality with reviewedAt is implied. */
data class OrganizationReviewReceipt(val notificationDigest: String, val wireTime: Instant) {
    override fun toString() = "OrganizationReviewReceipt([redacted])"
}

enum class OrganizationReviewPhase {
    PREPARED,
    DISPATCHED,
    ACKNOWLEDGED,
}

data class OrganizationReviewPending(
    val accountHash: String,
    val version: OrganizationReviewVersion,
    val action: OrganizationReviewAction,
    val textHash: String,
    val operationId: String,
    val issuedRole: String,
    val phase: OrganizationReviewPhase,
    val receipt: OrganizationReviewReceipt? = null,
    val backend: String = CompiledBackend.PROJECT_ID,
) {
    override fun toString() = "OrganizationReviewPending(phase=$phase, [redacted])"
}

interface OrganizationReviewSource {
    suspend fun read(session: ModerationSession, organizationId: String): OrganizationReviewSnapshot

    fun changes(session: ModerationSession, organizationId: String): Flow<Unit>

    suspend fun send(
        session: ModerationSession,
        entry: OrganizationReviewPending,
        text: String,
        canDispatch: () -> Boolean,
    ): OrganizationReviewReceipt

    suspend fun reconcile(
        session: ModerationSession,
        entry: OrganizationReviewPending,
    ): OrganizationReviewObservation
}

interface OrganizationReviewJournal {
    suspend fun pending(uid: String): List<OrganizationReviewPending>

    suspend fun put(
        uid: String,
        entry: OrganizationReviewPending,
        expected: OrganizationReviewPending? = null,
    ): OrganizationReviewPending

    suspend fun clear(uid: String, expected: OrganizationReviewPending)
}

object OrganizationReviewContract {
    private val digestPattern = Regex("[a-f0-9]{64}")
    private val idPattern = Regex("[A-Za-z0-9_-]{1,128}")
    private val changed =
        setOf(
            "moderationStatus",
            "reviewedByUserId",
            "reviewedAt",
            "updatedAt",
            "reviewMessage",
            "rejectionReason",
        )
    private val reviewable = setOf("pendingReview", "needsRevision", "rejected")

    fun fail(reason: OrganizationReviewFailure): Nothing = throw OrganizationReviewException(reason)

    fun id(value: String) = idPattern.matches(value)

    fun hash(value: String): String =
        MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8)).joinToString(
            ""
        ) {
            "%02x".format(it)
        }

    fun accountHash(uid: String): String {
        if (uid.isBlank() || uid.length > 128) fail(OrganizationReviewFailure.ACCESS)
        return hash(uid)
    }

    fun requireSession(session: ModerationSession) {
        if (!session.allowed || session.role !in setOf("owner", "admin"))
            fail(OrganizationReviewFailure.ACCESS)
        accountHash(session.uid)
    }

    fun validate(version: OrganizationReviewVersion) {
        if (
            !id(version.organizationId) ||
                listOf(
                        version.fingerprint,
                        version.preservedApprovalHash,
                        version.preservedOtherHash,
                        version.submitterHash,
                    )
                    .any { !digestPattern.matches(it) }
        )
            fail(OrganizationReviewFailure.INVALID)
    }

    fun validate(entry: OrganizationReviewPending) {
        validate(entry.version)
        if (
            !digestPattern.matches(entry.accountHash) ||
                !digestPattern.matches(entry.textHash) ||
                entry.issuedRole !in setOf("owner", "admin") ||
                entry.backend != CompiledBackend.PROJECT_ID ||
                runCatching { UUID.fromString(entry.operationId).toString() }.getOrNull() !=
                    entry.operationId ||
                (entry.phase == OrganizationReviewPhase.ACKNOWLEDGED) != (entry.receipt != null)
        )
            fail(OrganizationReviewFailure.INVALID)
        entry.receipt?.let {
            if (!digestPattern.matches(it.notificationDigest))
                fail(OrganizationReviewFailure.INVALID)
        }
    }

    fun requireOwner(session: ModerationSession, entry: OrganizationReviewPending) {
        requireSession(session)
        validate(entry)
        if (entry.accountHash != accountHash(session.uid)) fail(OrganizationReviewFailure.ACCESS)
    }

    fun normalizeText(value: String): String {
        if (value.length > LocalCallableProtocol.MAX_REQUEST_BYTES)
            fail(OrganizationReviewFailure.INVALID)
        // ECMAScript String.trim, matching the actual callable rather than display normalization.
        return value.trim {
            it in " \t\n\r\u000B\u000C\u00A0\u1680\u2028\u2029\u202F\u205F\u3000\uFEFF" ||
                it in '\u2000'..'\u200A'
        }
    }

    fun payload(id: String, action: OrganizationReviewAction, text: String): Map<String, String> {
        if (!OrganizationReviewContract.id(id)) fail(OrganizationReviewFailure.INVALID)
        val normalized = normalizeText(text)
        if (action.textField != null && normalized.isEmpty())
            fail(OrganizationReviewFailure.INVALID)
        if (action.textField == null && normalized.isNotEmpty())
            fail(OrganizationReviewFailure.INVALID)
        val payload = buildMap {
            put("organizationId", id)
            action.textField?.let { put(it, normalized) }
        }
        try {
            LocalCallableProtocol.request(payload)
        } catch (error: Exception) {
            throw OrganizationReviewException(OrganizationReviewFailure.INVALID, error)
        }
        return payload
    }

    fun instant(value: Any?): Instant? =
        when (value) {
            is Instant -> value
            is Timestamp -> Instant.ofEpochSecond(value.seconds, value.nanoseconds.toLong())
            else -> null
        }

    /** Strict raw fingerprint for the exact existing moderation preview; not a server CAS token. */
    fun fingerprint(id: String, fields: Map<String, Any?>): String =
        snapshot(id, fields).version.fingerprint

    fun snapshot(id: String, fields: Map<String, Any?>): OrganizationReviewSnapshot {
        val submitter =
            fields["submittedByUserId"] as? String ?: fail(OrganizationReviewFailure.INVALID)
        val name = fields["name"] as? String ?: fail(OrganizationReviewFailure.INVALID)
        val status =
            fields["moderationStatus"] as? String ?: fail(OrganizationReviewFailure.INVALID)
        if (
            !OrganizationReviewContract.id(id) ||
                fields["id"] != id ||
                submitter.isBlank() ||
                submitter.length > 128 ||
                normalizeText(submitter) != submitter ||
                name.isBlank() ||
                name.length > 5_000 ||
                status !in reviewable ||
                instant(fields["updatedAt"]) == null
        )
            fail(OrganizationReviewFailure.INVALID)
        return OrganizationReviewSnapshot(
            OrganizationReviewVersion(
                id,
                rawHash(id, fields),
                preservedHash(id, fields, OrganizationReviewAction.APPROVE),
                preservedHash(id, fields, OrganizationReviewAction.REJECT),
                hash(submitter),
            ),
            name,
            status,
            submitter,
        )
    }

    fun preservedHash(
        id: String,
        fields: Map<String, Any?>,
        action: OrganizationReviewAction,
    ): String =
        rawHash(
            id,
            fields.filterKeys {
                it !in changed && (action != OrganizationReviewAction.APPROVE || it != "ownerId")
            },
        )

    fun rawHash(id: String, fields: Map<String, Any?>): String {
        if (!OrganizationReviewContract.id(id)) fail(OrganizationReviewFailure.INVALID)
        return Encoder()
            .apply { value(listOf("uac-organization-review-v1", id, fields), 0) }
            .finish()
    }

    fun receipt(entry: OrganizationReviewPending, data: Any?): OrganizationReviewReceipt {
        val map = data as? Map<*, *> ?: fail(OrganizationReviewFailure.UNCONFIRMED)
        if (
            map.keys !=
                setOf("organizationId", "moderationStatus", "notificationId", "updatedAt") ||
                map["organizationId"] != entry.version.organizationId ||
                map["moderationStatus"] != entry.action.status
        )
            fail(OrganizationReviewFailure.UNCONFIRMED)
        val notification =
            map["notificationId"] as? String ?: fail(OrganizationReviewFailure.UNCONFIRMED)
        val time =
            (map["updatedAt"] as? String)
                ?.takeIf { it.length <= 80 }
                ?.let { runCatching { Instant.parse(it) }.getOrNull() }
                ?: fail(OrganizationReviewFailure.UNCONFIRMED)
        validateNotification(entry, notification)
        return OrganizationReviewReceipt(hash(notification), time)
    }

    private fun validateNotification(entry: OrganizationReviewPending, notification: String) {
        val type =
            when (entry.action) {
                OrganizationReviewAction.APPROVE -> "organizationRequestApproved"
                OrganizationReviewAction.REQUEST_REVISION -> "organizationRequestNeedsRevision"
                OrganizationReviewAction.REJECT -> "organizationRequestRejected"
            }
        val rest = notification.removePrefix("${type}_")
        if (rest == notification || rest.length !in 39..512)
            fail(OrganizationReviewFailure.UNCONFIRMED)
        val uuid = rest.take(36)
        val suffix = "_${entry.version.organizationId}_"
        val recipient = rest.drop(36 + suffix.length)
        // Server can race the displayed submitter: that is a confirmed changed result, not a lost
        // receipt.
        if (
            runCatching { UUID.fromString(uuid).toString() }.getOrNull() != uuid ||
                !rest.drop(36).startsWith(suffix) ||
                recipient.isBlank() ||
                recipient.length > 128 ||
                normalizeText(recipient) != recipient
        )
            fail(OrganizationReviewFailure.UNCONFIRMED)
    }

    fun matches(
        entry: OrganizationReviewPending,
        actorUid: String,
        fields: Map<String, Any?>,
    ): Boolean {
        if (
            fields["id"] != entry.version.organizationId ||
                fields["moderationStatus"] != entry.action.status ||
                fields["reviewedByUserId"] != actorUid ||
                (fields["submittedByUserId"] as? String)?.let(::hash) != entry.version.submitterHash
        )
            return false
        val reviewed = instant(fields["reviewedAt"]) ?: return false
        if (instant(fields["updatedAt"]) != reviewed) return false
        when (entry.action) {
            OrganizationReviewAction.APPROVE ->
                if (
                    (fields["ownerId"] as? String)?.let(::hash) != entry.version.submitterHash ||
                        "reviewMessage" in fields ||
                        "rejectionReason" in fields
                )
                    return false
            OrganizationReviewAction.REQUEST_REVISION ->
                if (
                    (fields["reviewMessage"] as? String)?.let(::hash) != entry.textHash ||
                        "rejectionReason" in fields
                )
                    return false
            OrganizationReviewAction.REJECT ->
                if (
                    (fields["rejectionReason"] as? String)?.let(::hash) != entry.textHash ||
                        "reviewMessage" in fields
                )
                    return false
        }
        val expected =
            if (entry.action == OrganizationReviewAction.APPROVE)
                entry.version.preservedApprovalHash
            else entry.version.preservedOtherHash
        return runCatching {
                preservedHash(entry.version.organizationId, fields, entry.action) == expected
            }
            .getOrDefault(false)
    }

    private class Encoder {
        private val digest = MessageDigest.getInstance("SHA-256")
        private var bytes = 0
        private var entries = 0
        private val out =
            DataOutputStream(
                object : OutputStream() {
                    override fun write(value: Int) {
                        reserve(1)
                        digest.update(value.toByte())
                    }

                    override fun write(value: ByteArray, offset: Int, count: Int) {
                        reserve(count)
                        digest.update(value, offset, count)
                    }
                }
            )

        private fun reserve(n: Int) {
            if (n < 0 || n > 1_048_576 - bytes) fail(OrganizationReviewFailure.INVALID)
            bytes += n
        }

        private fun text(value: String) {
            if (value.length > 1_048_576) fail(OrganizationReviewFailure.INVALID)
            var index = 0
            var size = 0
            while (index < value.length) {
                val c = value[index++]
                size +=
                    when {
                        c.code < 0x80 -> 1
                        c.code < 0x800 -> 2
                        c.isHighSurrogate() -> {
                            if (index >= value.length || !value[index++].isLowSurrogate())
                                fail(OrganizationReviewFailure.INVALID)
                            4
                        }
                        c.isLowSurrogate() -> fail(OrganizationReviewFailure.INVALID)
                        else -> 3
                    }
                if (size > 1_048_576 - bytes - 4) fail(OrganizationReviewFailure.INVALID)
            }
            out.writeInt(size)
            out.write(value.toByteArray(Charsets.UTF_8))
        }

        fun value(value: Any?, depth: Int) {
            if (depth > 20 || ++entries > 4096) fail(OrganizationReviewFailure.INVALID)
            when (value) {
                null -> out.writeByte(0)
                is Boolean -> {
                    out.writeByte(1)
                    out.writeBoolean(value)
                }
                is Byte,
                is Short,
                is Int,
                is Long -> {
                    out.writeByte(2)
                    out.writeLong((value as Number).toLong())
                }
                is Double -> {
                    if (!value.isFinite()) fail(OrganizationReviewFailure.INVALID)
                    out.writeByte(3)
                    out.writeLong(value.toRawBits())
                }
                is String -> {
                    out.writeByte(4)
                    text(value)
                }
                is Instant,
                is Timestamp -> {
                    val time = instant(value) ?: fail(OrganizationReviewFailure.INVALID)
                    out.writeByte(5)
                    out.writeLong(time.epochSecond)
                    out.writeInt(time.nano)
                }
                is List<*> -> {
                    if (value.size > 4096 - entries) fail(OrganizationReviewFailure.INVALID)
                    out.writeByte(6)
                    out.writeInt(value.size)
                    value.forEach { value(it, depth + 1) }
                }
                is Map<*, *> -> {
                    if (value.size > 4096 - entries || value.keys.any { it !is String })
                        fail(OrganizationReviewFailure.INVALID)
                    out.writeByte(7)
                    out.writeInt(value.size)
                    value.keys
                        .map { it as String }
                        .sorted()
                        .forEach {
                            text(it)
                            value(value[it], depth + 1)
                        }
                }
                else -> fail(OrganizationReviewFailure.INVALID)
            }
        }

        fun finish() = digest.digest().joinToString("") { "%02x".format(it) }
    }
}
