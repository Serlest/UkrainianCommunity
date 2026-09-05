package at.uac.android.feature.feedbackdeletion

import at.uac.android.core.backend.CompiledBackend
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.feedback.FeedbackAudience
import at.uac.android.feature.moderation.ModerationSession
import com.google.firebase.Timestamp
import java.io.DataOutputStream
import java.io.OutputStream
import java.security.MessageDigest
import java.time.Instant
import java.util.UUID

/** Exact full-parent fingerprint, NOT a server CAS token or a snapshot of all child messages. */
data class FeedbackDeletionVersion(val targetId: String, val fingerprint: String) {
    override fun toString() = "FeedbackDeletionVersion([redacted])"
}

data class FeedbackDeletionSnapshot(
    val version: FeedbackDeletionVersion,
    val target: FeedbackDeletionTarget,
) {
    override fun toString() = "FeedbackDeletionSnapshot([redacted])"
}

enum class FeedbackDeletionPhase {
    PREPARED,
    DISPATCHED,
    ACKNOWLEDGED,
}

/** Local binding to the actual awaited response; server returns no target/version/request echo. */
data class FeedbackDeletionReceipt(val requestHash: String, val responseHash: String) {
    override fun toString() = "FeedbackDeletionReceipt([redacted])"
}

/** Future durable state: hashes and an opaque routing ID only; never contact/message/subject. */
data class FeedbackDeletionPending(
    val accountHash: String,
    val version: FeedbackDeletionVersion,
    val operationId: String,
    val phase: FeedbackDeletionPhase,
    val receipt: FeedbackDeletionReceipt? = null,
    val backend: String = CompiledBackend.PROJECT_ID,
) {
    override fun toString() = "FeedbackDeletionPending(phase=" + phase + ", [redacted])"
}

/** Absence must come from an authorized SERVER read, never permission failure or cache. */
sealed interface FeedbackDeletionRead {
    data object Absent : FeedbackDeletionRead

    data object Unavailable : FeedbackDeletionRead

    data class Present(val snapshot: FeedbackDeletionSnapshot) : FeedbackDeletionRead {
        override fun toString() = "FeedbackDeletionRead.Present([redacted])"
    }
}

enum class FeedbackDeletionObservation {
    ACCEPTED_ABSENT,
    ACCEPTED_UNCHANGED,
    ACCEPTED_CHANGED,
    ACCEPTED_UNAVAILABLE,
    ABSENT_WITHOUT_RECEIPT,
    UNCHANGED_WITHOUT_RECEIPT,
    CHANGED_WITHOUT_RECEIPT,
    UNAVAILABLE;

    val hasOwnReceipt: Boolean
        get() =
            this in
                setOf(ACCEPTED_ABSENT, ACCEPTED_UNCHANGED, ACCEPTED_CHANGED, ACCEPTED_UNAVAILABLE)

    val parentAbsent: Boolean
        get() = this in setOf(ACCEPTED_ABSENT, ABSENT_WITHOUT_RECEIPT)

    // The known server aggregation gap is unresolved. Even own ACK + parent absence does not
    // establish that messages/notifications were deleted. Never borrow role-recovery clearance.
    val clearsPending: Boolean
        get() = false

    val allowsReplay: Boolean
        get() = false
}

interface FeedbackDeletionJournal {
    suspend fun pending(uid: String): List<FeedbackDeletionPending>

    suspend fun put(
        uid: String,
        entry: FeedbackDeletionPending,
        expected: FeedbackDeletionPending? = null,
    ): FeedbackDeletionPending

    suspend fun clear(uid: String, expected: FeedbackDeletionPending)
}

/**
 * Inert pure recovery model. No SDK calls, storage writes, timeouts-as-absence or automatic retry.
 */
object FeedbackDeletionRecovery {
    const val MAX_PENDING = 16
    private val digestPattern = Regex("[a-f0-9]{64}")
    private val minimumTime = Instant.parse("0001-01-01T00:00:00Z")
    private val maximumTime = Instant.parse("9999-12-31T23:59:59.999999999Z")

    fun fail(value: FeedbackDeletionFailure): Nothing = FeedbackDeletionContract.fail(value)

    fun accountHash(uid: String): String {
        if (uid.length > 128 || !FeedbackDeletionContract.id(uid))
            fail(FeedbackDeletionFailure.ACCESS)
        return rawHash(listOf("uac-feedback-delete-account-v1", uid))
    }

    internal fun backendBinding(): String =
        rawHash(
            listOf(
                "uac-feedback-delete-backend-v1",
                CompiledBackend.ANDROID_PACKAGE,
                CompiledBackend.FIREBASE_APP_NAME,
                CompiledBackend.PROJECT_ID,
                CompiledBackend.FIREBASE_APPLICATION_ID,
            )
        )

    fun validate(version: FeedbackDeletionVersion) {
        if (
            !FeedbackDeletionContract.id(version.targetId) ||
                !digestPattern.matches(version.fingerprint)
        )
            fail(FeedbackDeletionFailure.INVALID)
    }

    fun validate(snapshot: FeedbackDeletionSnapshot) {
        validate(snapshot.version)
        if (
            snapshot.target.feedbackId != snapshot.version.targetId ||
                snapshot.target.authorId.length > 128 ||
                !FeedbackDeletionContract.id(snapshot.target.authorId)
        )
            fail(FeedbackDeletionFailure.INVALID)
    }

    private fun validateCore(entry: FeedbackDeletionPending) {
        validate(entry.version)
        if (
            !digestPattern.matches(entry.accountHash) ||
                entry.backend != CompiledBackend.PROJECT_ID ||
                runCatching { UUID.fromString(entry.operationId).toString() }.getOrNull() !=
                    entry.operationId
        )
            fail(FeedbackDeletionFailure.INVALID)
    }

    fun validate(entry: FeedbackDeletionPending) {
        validateCore(entry)
        if ((entry.phase == FeedbackDeletionPhase.ACKNOWLEDGED) != (entry.receipt != null))
            fail(FeedbackDeletionFailure.INVALID)
        entry.receipt?.let {
            if (it.requestHash != bindingHash(entry) || it.responseHash != responseHash(entry))
                fail(FeedbackDeletionFailure.INVALID)
        }
    }

    fun requireOwner(session: ModerationSession, entry: FeedbackDeletionPending) {
        FeedbackDeletionContract.requireSession(session)
        validate(entry)
        if (entry.accountHash != accountHash(session.uid)) fail(FeedbackDeletionFailure.ACCESS)
    }

    fun snapshot(targetId: String, fields: Map<String, Any?>): FeedbackDeletionSnapshot {
        if (!FeedbackDeletionContract.id(targetId)) fail(FeedbackDeletionFailure.INVALID)
        // Validate bounded depth/nodes/types/UTF8 before recursive presentation conversion. SDK
        // owns this read's map; no suspension or external data operation occurs between hashes.
        val fingerprint = rawHash(listOf("uac-feedback-delete-version-v1", targetId, fields))
        fun convert(value: Any?): Any? =
            when (value) {
                is Timestamp -> instant(value) ?: fail(FeedbackDeletionFailure.INVALID)
                is Map<*, *> ->
                    value.entries.associate { (key, child) -> key as String to convert(child) }
                is List<*> -> value.map(::convert)
                else -> value
            }
        @Suppress("UNCHECKED_CAST") val previewFields = convert(fields) as Map<String, Any?>
        if (
            rawHash(listOf("uac-feedback-delete-version-v1", targetId, previewFields)) !=
                fingerprint
        )
            fail(FeedbackDeletionFailure.STALE)
        val target = FeedbackDeletionContract.target(RawDocument(targetId, previewFields))
        return FeedbackDeletionSnapshot(FeedbackDeletionVersion(targetId, fingerprint), target)
    }

    fun prepared(
        session: ModerationSession,
        audience: FeedbackAudience,
        snapshot: FeedbackDeletionSnapshot,
        operationId: String,
    ): FeedbackDeletionPending {
        validate(snapshot)
        FeedbackDeletionContract.requireTarget(session, audience, snapshot.target)
        FeedbackDeletionContract.payload(snapshot.version.targetId)
        return FeedbackDeletionPending(
                accountHash(session.uid),
                snapshot.version,
                operationId,
                FeedbackDeletionPhase.PREPARED,
            )
            .also(::validate)
    }

    /** Only actual successful awaited Task data may enter here, never a read-back/audit/error. */
    fun receipt(entry: FeedbackDeletionPending, data: Any?): FeedbackDeletionReceipt {
        validate(entry)
        if (entry.phase != FeedbackDeletionPhase.DISPATCHED)
            fail(FeedbackDeletionFailure.UNCONFIRMED)
        FeedbackDeletionContract.response(data)
        return FeedbackDeletionReceipt(bindingHash(entry), responseHash(entry))
    }

    fun observation(
        entry: FeedbackDeletionPending,
        actorUid: String,
        read: FeedbackDeletionRead,
    ): FeedbackDeletionObservation {
        validate(entry)
        if (entry.accountHash != accountHash(actorUid)) fail(FeedbackDeletionFailure.ACCESS)
        val accepted = entry.receipt != null
        return when (read) {
            FeedbackDeletionRead.Unavailable ->
                if (accepted) FeedbackDeletionObservation.ACCEPTED_UNAVAILABLE
                else FeedbackDeletionObservation.UNAVAILABLE
            FeedbackDeletionRead.Absent ->
                if (accepted) FeedbackDeletionObservation.ACCEPTED_ABSENT
                else FeedbackDeletionObservation.ABSENT_WITHOUT_RECEIPT
            is FeedbackDeletionRead.Present -> {
                validate(read.snapshot)
                if (read.snapshot.version.targetId != entry.version.targetId)
                    fail(FeedbackDeletionFailure.INVALID)
                val unchanged = read.snapshot.version == entry.version
                if (accepted) {
                    if (unchanged) FeedbackDeletionObservation.ACCEPTED_UNCHANGED
                    else FeedbackDeletionObservation.ACCEPTED_CHANGED
                } else {
                    if (unchanged) FeedbackDeletionObservation.UNCHANGED_WITHOUT_RECEIPT
                    else FeedbackDeletionObservation.CHANGED_WITHOUT_RECEIPT
                }
            }
        }
    }

    private fun bindingHash(entry: FeedbackDeletionPending): String {
        validateCore(entry)
        return rawHash(
            listOf(
                "uac-feedback-delete-request-v1",
                backendBinding(),
                entry.backend,
                entry.accountHash,
                entry.version.targetId,
                entry.version.fingerprint,
                FeedbackDeletionContract.CALLABLE,
                entry.operationId,
            )
        )
    }

    private fun responseHash(entry: FeedbackDeletionPending): String =
        rawHash(
            listOf(
                "uac-feedback-delete-response-v1",
                bindingHash(entry),
                mapOf("deletedCount" to 1),
            )
        )

    private fun instant(value: Any?): Instant? =
        when (value) {
            is Instant -> value
            is Timestamp -> Instant.ofEpochSecond(value.seconds, value.nanoseconds.toLong())
            else -> null
        }?.takeIf { it in minimumTime..maximumTime }

    private fun rawHash(value: Any?): String = Encoder().apply { this.value(value, 0) }.finish()

    // Same bounded typed encoding as the reviewed role recovery, with deletion-specific domains.
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

        private fun reserve(count: Int) {
            if (count < 0 || count > 1_048_576 - bytes) fail(FeedbackDeletionFailure.INVALID)
            bytes += count
        }

        private fun text(value: String) {
            if (value.length > 1_048_576) fail(FeedbackDeletionFailure.INVALID)
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
                                fail(FeedbackDeletionFailure.INVALID)
                            4
                        }
                        c.isLowSurrogate() -> fail(FeedbackDeletionFailure.INVALID)
                        else -> 3
                    }
                if (size > 1_048_576 - bytes - 4) fail(FeedbackDeletionFailure.INVALID)
            }
            out.writeInt(size)
            out.write(value.toByteArray(Charsets.UTF_8))
        }

        fun value(value: Any?, depth: Int) {
            if (depth > 20 || ++entries > 4096) fail(FeedbackDeletionFailure.INVALID)
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
                    if (!value.isFinite()) fail(FeedbackDeletionFailure.INVALID)
                    out.writeByte(3)
                    out.writeLong(value.toRawBits())
                }
                is String -> {
                    out.writeByte(4)
                    text(value)
                }
                is Instant,
                is Timestamp -> {
                    val instant = instant(value) ?: fail(FeedbackDeletionFailure.INVALID)
                    out.writeByte(5)
                    out.writeLong(instant.epochSecond)
                    out.writeInt(instant.nano)
                }
                is List<*> -> {
                    if (value.size > 4096 - entries) fail(FeedbackDeletionFailure.INVALID)
                    out.writeByte(6)
                    out.writeInt(value.size)
                    value.forEach { value(it, depth + 1) }
                }
                is Map<*, *> -> {
                    if (value.size > 4096 - entries || value.keys.any { it !is String })
                        fail(FeedbackDeletionFailure.INVALID)
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
                else -> fail(FeedbackDeletionFailure.INVALID)
            }
        }

        fun finish(): String =
            digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
    }
}
