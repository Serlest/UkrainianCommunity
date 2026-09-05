package at.uac.android.feature.platformrolemanagement

import at.uac.android.core.backend.CompiledBackend
import at.uac.android.feature.moderation.ModerationSession
import com.google.firebase.Timestamp
import java.io.DataOutputStream
import java.io.OutputStream
import java.security.MessageDigest
import java.time.Instant
import java.util.UUID

data class PlatformRoleVersion(
    val targetId: String,
    val fingerprint: String,
    val preservedHash: String,
    val previousRole: String,
) {
    override fun toString() = "PlatformRoleVersion([redacted])"
}

data class PlatformRoleSnapshot(
    val version: PlatformRoleVersion,
    val target: PlatformRoleTarget,
    val displayName: String?,
    val email: String?,
) {
    override fun toString() = "PlatformRoleSnapshot([redacted])"
}

enum class PlatformRolePhase {
    PREPARED,
    DISPATCHED,
    ACKNOWLEDGED,
}

data class PlatformRoleReceipt(
    val requestHash: String,
    val responseHash: String,
    val wireTime: Instant,
) {
    override fun toString() = "PlatformRoleReceipt([redacted])"
}

/** Hash-only durable state, except the explicit routing target. No contact/reason/token. */
data class PlatformRolePending(
    val accountHash: String,
    val version: PlatformRoleVersion,
    val action: PlatformRoleAction,
    val reasonHash: String,
    val operationId: String,
    val phase: PlatformRolePhase,
    val receipt: PlatformRoleReceipt? = null,
    val backend: String = CompiledBackend.PROJECT_ID,
) {
    override fun toString() = "PlatformRolePending(phase=$phase, [redacted])"
}

enum class PlatformRoleObservation {
    CONFIRMED_CURRENT,
    CONFIRMED_CHANGED,
    CONFIRMED_UNAVAILABLE,
    OBSERVED_WITHOUT_RECEIPT,
    UNCONFIRMED,
    UNAVAILABLE;

    val confirmed
        get() = this in setOf(CONFIRMED_CURRENT, CONFIRMED_CHANGED, CONFIRMED_UNAVAILABLE)

    val clearsPending
        get() = this in setOf(CONFIRMED_CURRENT, CONFIRMED_CHANGED)
}

interface PlatformRoleJournal {
    suspend fun pending(uid: String): List<PlatformRolePending>

    suspend fun put(
        uid: String,
        entry: PlatformRolePending,
        expected: PlatformRolePending? = null,
    ): PlatformRolePending

    suspend fun clear(uid: String, expected: PlatformRolePending)
}

/** Pure recovery semantics. A matching profile is never proof of this operation without its ACK. */
object PlatformRoleRecovery {
    const val MAX_PENDING = 16
    private val digestPattern = Regex("[a-f0-9]{64}")
    private val changedFields = setOf("globalRole", "roleUpdatedAt", "roleUpdatedBy")
    private val minimumTime = Instant.parse("0001-01-01T00:00:00Z")
    private val maximumTime = Instant.parse("9999-12-31T23:59:59.999999999Z")

    fun fail(value: PlatformRoleFailure): Nothing = PlatformRoleContract.fail(value)

    fun hash(value: String): String = rawHash(listOf("uac-platform-role-text-v1", value))

    fun accountHash(uid: String): String {
        if (!PlatformRoleContract.id(uid)) fail(PlatformRoleFailure.ACCESS)
        return hash(uid)
    }

    fun validate(version: PlatformRoleVersion) {
        if (
            !PlatformRoleContract.id(version.targetId) ||
                version.previousRole !in setOf("owner", "admin", "user") ||
                !digestPattern.matches(version.fingerprint) ||
                !digestPattern.matches(version.preservedHash)
        )
            fail(PlatformRoleFailure.INVALID)
    }

    private fun validateCore(entry: PlatformRolePending) {
        validate(entry.version)
        if (
            !digestPattern.matches(entry.accountHash) ||
                !digestPattern.matches(entry.reasonHash) ||
                entry.accountHash == accountHash(entry.version.targetId) ||
                entry.version.previousRole != entry.action.previousRole ||
                entry.backend != CompiledBackend.PROJECT_ID ||
                runCatching { UUID.fromString(entry.operationId).toString() }.getOrNull() !=
                    entry.operationId
        )
            fail(PlatformRoleFailure.INVALID)
    }

    fun validate(entry: PlatformRolePending) {
        validateCore(entry)
        if ((entry.phase == PlatformRolePhase.ACKNOWLEDGED) != (entry.receipt != null))
            fail(PlatformRoleFailure.INVALID)
        entry.receipt?.let {
            if (
                it.wireTime !in minimumTime..maximumTime ||
                    it.wireTime.nano % 1_000_000 != 0 ||
                    it.requestHash != bindingHash(entry) ||
                    it.responseHash != responseHash(entry, it.wireTime)
            )
                fail(PlatformRoleFailure.INVALID)
        }
    }

    fun requireOwner(session: ModerationSession, entry: PlatformRolePending) {
        PlatformRoleContract.requireSession(session)
        validate(entry)
        if (entry.accountHash != accountHash(session.uid)) fail(PlatformRoleFailure.ACCESS)
    }

    fun snapshot(targetId: String, fields: Map<String, Any?>): PlatformRoleSnapshot {
        val target = PlatformRoleContract.target(targetId, fields)
        val fingerprint = rawHash(listOf("uac-platform-role-version-v1", targetId, fields))
        fun preview(key: String): String? {
            val text = fields[key] as? String ?: return null
            val result =
                if (text.length > 500) {
                    val prefix = text.take(500)
                    (if (prefix.last().isHighSurrogate()) prefix.dropLast(1) else prefix) + "…"
                } else text
            return result.takeUnless { it.isBlank() }
        }
        return PlatformRoleSnapshot(
            PlatformRoleVersion(
                targetId,
                fingerprint,
                preservedHash(targetId, fields),
                target.role,
            ),
            target,
            preview("displayName") ?: preview("fullName"),
            preview("email"),
        )
    }

    fun prepared(
        session: ModerationSession,
        snapshot: PlatformRoleSnapshot,
        action: PlatformRoleAction,
        reason: String,
        auth: PlatformRoleTargetAuth?,
        operationId: String,
    ): PlatformRolePending {
        validate(snapshot.version)
        if (
            snapshot.target.targetId != snapshot.version.targetId ||
                snapshot.target.role != snapshot.version.previousRole
        )
            fail(PlatformRoleFailure.INVALID)
        PlatformRoleContract.requireTarget(session, snapshot.target, action, auth)
        val text =
            PlatformRoleContract.payload(snapshot.version.targetId, reason).getValue("reason")
        return PlatformRolePending(
                accountHash(session.uid),
                snapshot.version,
                action,
                hash(text),
                operationId,
                PlatformRolePhase.PREPARED,
            )
            .also(::validate)
    }

    /** Call only on actual Task settlement. No profile/audit-to-receipt conversion exists. */
    fun receipt(entry: PlatformRolePending, data: Any?): PlatformRoleReceipt {
        validate(entry)
        if (entry.phase != PlatformRolePhase.DISPATCHED) fail(PlatformRoleFailure.UNCONFIRMED)
        val response = PlatformRoleContract.response(entry.version.targetId, entry.action, data)
        return PlatformRoleReceipt(
            bindingHash(entry),
            responseHash(entry, response.wireTime),
            response.wireTime,
        )
    }

    fun matches(entry: PlatformRolePending, actorUid: String, fields: Map<String, Any?>): Boolean =
        runCatching {
            validate(entry)
            if (accountHash(actorUid) != entry.accountHash) return false
            val current = snapshot(entry.version.targetId, fields)
            fields["globalRole"] == entry.action.newRole &&
                fields["roleUpdatedBy"] == actorUid &&
                instant(fields["roleUpdatedAt"]) != null &&
                current.version.preservedHash == entry.version.preservedHash
        }
        .getOrDefault(false)

    fun observation(
        entry: PlatformRolePending,
        actorUid: String,
        fields: Map<String, Any?>?,
    ): PlatformRoleObservation {
        validate(entry)
        if (accountHash(actorUid) != entry.accountHash) fail(PlatformRoleFailure.ACCESS)
        if (fields == null || runCatching { snapshot(entry.version.targetId, fields) }.isFailure)
            return if (entry.receipt != null) PlatformRoleObservation.CONFIRMED_UNAVAILABLE
            else PlatformRoleObservation.UNAVAILABLE
        val current = matches(entry, actorUid, fields)
        return if (entry.receipt != null) {
            if (current) PlatformRoleObservation.CONFIRMED_CURRENT
            else PlatformRoleObservation.CONFIRMED_CHANGED
        } else if (current) PlatformRoleObservation.OBSERVED_WITHOUT_RECEIPT
        else PlatformRoleObservation.UNCONFIRMED
    }

    fun instant(value: Any?): Instant? =
        when (value) {
            is Instant -> value
            is Timestamp -> Instant.ofEpochSecond(value.seconds, value.nanoseconds.toLong())
            else -> null
        }?.takeIf { it in minimumTime..maximumTime }

    private fun preservedHash(id: String, fields: Map<String, Any?>) =
        rawHash(
            listOf("uac-platform-role-preserved-v1", id, fields.filterKeys { it !in changedFields })
        )

    private fun bindingHash(entry: PlatformRolePending): String {
        validateCore(entry)
        return rawHash(
            listOf(
                "uac-platform-role-request-v1",
                entry.backend,
                entry.accountHash,
                entry.version.targetId,
                entry.version.fingerprint,
                entry.version.preservedHash,
                entry.version.previousRole,
                entry.action.name,
                entry.reasonHash,
                entry.operationId,
            )
        )
    }

    // Typed canonical values of the validated actual response, not its JSON/ISO spelling.
    private fun responseHash(entry: PlatformRolePending, time: Instant) =
        rawHash(
            listOf(
                "uac-platform-role-response-v1",
                entry.version.targetId,
                entry.action.previousRole,
                entry.action.newRole,
                time,
            )
        )

    private fun rawHash(value: Any?): String = Encoder().apply { this.value(value, 0) }.finish()

    /** Bounded typed streaming digest: no full serialized private profile buffer or toString. */
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
            if (count < 0 || count > 1_048_576 - bytes) fail(PlatformRoleFailure.INVALID)
            bytes += count
        }

        private fun text(value: String) {
            if (value.length > 1_048_576) fail(PlatformRoleFailure.INVALID)
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
                                fail(PlatformRoleFailure.INVALID)
                            4
                        }
                        c.isLowSurrogate() -> fail(PlatformRoleFailure.INVALID)
                        else -> 3
                    }
                if (size > 1_048_576 - bytes - 4) fail(PlatformRoleFailure.INVALID)
            }
            out.writeInt(size)
            out.write(value.toByteArray(Charsets.UTF_8))
        }

        fun value(value: Any?, depth: Int) {
            if (depth > 20 || ++entries > 4096) fail(PlatformRoleFailure.INVALID)
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
                    if (!value.isFinite()) fail(PlatformRoleFailure.INVALID)
                    out.writeByte(3)
                    out.writeLong(value.toRawBits())
                }
                is String -> {
                    out.writeByte(4)
                    text(value)
                }
                is Instant,
                is Timestamp -> {
                    val instant = instant(value) ?: fail(PlatformRoleFailure.INVALID)
                    out.writeByte(5)
                    out.writeLong(instant.epochSecond)
                    out.writeInt(instant.nano)
                }
                is List<*> -> {
                    if (value.size > 4096 - entries) fail(PlatformRoleFailure.INVALID)
                    out.writeByte(6)
                    out.writeInt(value.size)
                    value.forEach { value(it, depth + 1) }
                }
                is Map<*, *> -> {
                    if (value.size > 4096 - entries || value.keys.any { it !is String })
                        fail(PlatformRoleFailure.INVALID)
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
                else -> fail(PlatformRoleFailure.INVALID)
            }
        }

        fun finish(): String =
            digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
    }
}
