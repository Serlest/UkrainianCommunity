package at.uac.android.feature.userstatusmanagement

import at.uac.android.core.LocalCallableProtocol
import at.uac.android.core.backend.CompiledBackend
import at.uac.android.feature.moderation.ModerationSession
import com.google.firebase.Timestamp
import java.io.DataOutputStream
import java.io.OutputStream
import java.security.MessageDigest
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlinx.coroutines.flow.Flow

enum class UserStatusAction(val callable: String, val status: String, val messagePrefix: String) {
    WARN("warnUser", "warned", "Your account received a warning. Reason: "),
    SUSPEND("suspendUser", "suspendedUntil", "Your account is temporarily suspended. Reason: "),
    BAN("banUser", "bannedPermanent", "Your account is permanently blocked. Reason: "),
    DEACTIVATE("deactivateUser", "deactivated", "Your account is deactivated. Reason: "),
    RESTORE("restoreUser", "active", "Your account access has been restored. Reason: ");

    val blocked
        get() = this in setOf(SUSPEND, BAN, DEACTIVATE)
}

enum class UserStatusFailure {
    ACCESS,
    STALE,
    INVALID,
    JOURNAL,
    PENDING,
    OFFLINE,
    UNCONFIRMED,
}

class UserStatusException(val failure: UserStatusFailure, cause: Throwable? = null) :
    Exception(failure.name, cause)

enum class UserStatusObservation {
    CONFIRMED_CURRENT,
    CONFIRMED_CHANGED,
    CONFIRMED_UNAVAILABLE,
    OBSERVED_WITHOUT_RECEIPT,
    UNCONFIRMED,
    UNAVAILABLE;

    val confirmed
        get() = this in setOf(CONFIRMED_CURRENT, CONFIRMED_CHANGED, CONFIRMED_UNAVAILABLE)

    // Keep an acknowledged journal when the fresh target cannot yet be read. Recovery is read-only.
    val clearsPending
        get() = this in setOf(CONFIRMED_CURRENT, CONFIRMED_CHANGED)
}

data class UserStatusVersion(
    val targetId: String,
    val fingerprint: String,
    val previousStateHash: String,
    val preservedHash: String,
) {
    override fun toString() = "UserStatusVersion([redacted])"
}

/** Exact status text/times in memory; no trimmed ManagedUser display DTO is a mutation version. */
data class UserStatusSnapshot(
    val version: UserStatusVersion,
    val role: String,
    val accountStatus: String,
    val blockState: String,
    val warningCount: Long,
    val statusReason: String?,
    val statusMessage: String?,
    val banExpiresAt: Instant?,
    val statusUpdatedAt: Instant?,
    val statusAcknowledgedAt: Instant?,
    val statusUpdatedBy: String?,
    /** Display-only labels from the same raw snapshot, never routing or journal fields. */
    val displayName: String? = null,
    val email: String? = null,
) {
    override fun toString() = "UserStatusSnapshot([redacted])"
}

/** Validated own callable response. wireTime is NOT a Firestore commit timestamp or audit ID. */
data class UserStatusReceipt(
    val requestHash: String,
    val responseHash: String,
    val previousStateHash: String,
    val newStateHash: String,
    val wireTime: Instant,
) {
    override fun toString() = "UserStatusReceipt([redacted])"
}

enum class UserStatusPhase {
    PREPARED,
    DISPATCHED,
    ACKNOWLEDGED,
}

/** Only targetId is a raw routing identifier. No raw actor, reason, message, contact or token. */
data class UserStatusPending(
    val accountHash: String,
    val version: UserStatusVersion,
    val action: UserStatusAction,
    val reasonHash: String,
    val messageHash: String,
    val desiredStateHash: String,
    val untilHash: String,
    val operationId: String,
    val issuedRole: String,
    val phase: UserStatusPhase,
    val receipt: UserStatusReceipt? = null,
    val backend: String = CompiledBackend.PROJECT_ID,
) {
    override fun toString() = "UserStatusPending(phase=$phase, [redacted])"
}

interface UserStatusSource {
    /** Fresh server-only raw snapshot after actual privileged access checks. */
    suspend fun read(session: ModerationSession, targetId: String): UserStatusSnapshot

    fun changes(session: ModerationSession, targetId: String): Flow<Unit>

    /**
     * One actual Task only, awaited to settlement. Recheck raw version/privilege and invoke
     * canDispatch immediately before Task creation on the presentation's dispatcher. No server
     * expectedVersion or idempotency support exists; never retry on an unknown response.
     */
    suspend fun send(
        session: ModerationSession,
        entry: UserStatusPending,
        reason: String,
        until: Instant?,
        canDispatch: () -> Boolean,
    ): UserStatusReceipt

    /** Read-only; permission/network failures are unavailable, never absence or own-call proof. */
    suspend fun reconcile(
        session: ModerationSession,
        entry: UserStatusPending,
    ): UserStatusObservation
}

interface UserStatusJournal {
    suspend fun pending(uid: String): List<UserStatusPending>

    /**
     * Exact compare-and-set plus durable read-back; mismatch or uncertain persistence must fail.
     */
    suspend fun put(
        uid: String,
        entry: UserStatusPending,
        expected: UserStatusPending? = null,
    ): UserStatusPending

    suspend fun clear(uid: String, expected: UserStatusPending)
}

object UserStatusContract {
    const val MAX_PENDING = 16
    const val MAX_SAFE_COUNT = 9_007_199_254_740_991L
    const val DEFAULT_SUSPENSION_DAYS = 7
    val suspensionOptions: List<Int>
        get() = listOf(1, 7, 14, 30)

    private val digestPattern = Regex("[a-f0-9]{64}")
    private val canonicalStatuses =
        setOf("active", "warned", "suspendedUntil", "bannedPermanent", "deactivated")
    private val minimumTime = Instant.parse("0001-01-01T00:00:00Z")
    private val maximumTime = Instant.parse("9999-12-31T23:59:59.999999999Z")
    private val changedFields =
        setOf(
            "accountStatus",
            "blockState",
            "warningCount",
            "banExpiresAt",
            "isBlocked",
            "statusReason",
            "statusMessage",
            "statusUpdatedAt",
            "statusUpdatedBy",
            "statusAcknowledgedAt",
            "updatedAt",
        )

    fun fail(reason: UserStatusFailure): Nothing = throw UserStatusException(reason)

    fun id(value: String): Boolean =
        value.length in 1..128 &&
            value !in setOf(".", "..") &&
            value.none { it == '/' || it.isISOControl() } &&
            normalizeText(value) == value &&
            runCatching { rawHash(value) }.isSuccess

    fun hash(value: String): String = rawHash(listOf("uac-user-status-text-v1", value))

    fun accountHash(uid: String): String {
        if (!id(uid)) fail(UserStatusFailure.ACCESS)
        return hash(uid)
    }

    fun requireSession(session: ModerationSession) {
        if (!session.allowed || session.role !in setOf("owner", "admin"))
            fail(UserStatusFailure.ACCESS)
        accountHash(session.uid)
    }

    fun validate(version: UserStatusVersion) {
        if (
            !id(version.targetId) ||
                listOf(version.fingerprint, version.previousStateHash, version.preservedHash).any {
                    !digestPattern.matches(it)
                }
        )
            fail(UserStatusFailure.INVALID)
    }

    fun validate(entry: UserStatusPending) {
        validateCore(entry)
        if ((entry.phase == UserStatusPhase.ACKNOWLEDGED) != (entry.receipt != null))
            fail(UserStatusFailure.INVALID)
        entry.receipt?.let { receipt ->
            if (
                listOf(
                        receipt.requestHash,
                        receipt.responseHash,
                        receipt.previousStateHash,
                        receipt.newStateHash,
                    )
                    .any { !digestPattern.matches(it) } ||
                    receipt.requestHash != bindingHash(entry) ||
                    !validTime(receipt.wireTime) ||
                    receipt.wireTime.nano % 1_000_000 != 0
            )
                fail(UserStatusFailure.INVALID)
        }
    }

    private fun validateCore(entry: UserStatusPending) {
        validate(entry.version)
        if (
            listOf(
                    entry.accountHash,
                    entry.reasonHash,
                    entry.messageHash,
                    entry.desiredStateHash,
                    entry.untilHash,
                )
                .any { !digestPattern.matches(it) } ||
                entry.issuedRole !in setOf("owner", "admin") ||
                entry.backend != CompiledBackend.PROJECT_ID ||
                runCatching { UUID.fromString(entry.operationId).toString() }.getOrNull() !=
                    entry.operationId ||
                ((entry.action == UserStatusAction.SUSPEND) != (entry.untilHash != untilHash(null)))
        )
            fail(UserStatusFailure.INVALID)
    }

    fun requireOwner(session: ModerationSession, entry: UserStatusPending) {
        requireSession(session)
        validate(entry)
        if (entry.accountHash != accountHash(session.uid)) fail(UserStatusFailure.ACCESS)
    }

    fun availableActions(
        session: ModerationSession?,
        snapshot: UserStatusSnapshot,
    ): List<UserStatusAction> {
        if (
            session == null ||
                !session.allowed ||
                !id(session.uid) ||
                snapshot.role !in setOf("owner", "admin", "user") ||
                snapshot.accountStatus !in canonicalStatuses ||
                snapshot.blockState !in canonicalStatuses ||
                snapshot.warningCount !in 0..MAX_SAFE_COUNT ||
                session.uid == snapshot.version.targetId ||
                snapshot.role == "owner" ||
                (snapshot.role == "admin" && session.role != "owner")
        )
            return emptyList()
        return when (snapshot.blockState) {
            "active" ->
                listOf(
                    UserStatusAction.WARN,
                    UserStatusAction.SUSPEND,
                    UserStatusAction.BAN,
                    UserStatusAction.DEACTIVATE,
                )
            "warned" ->
                listOf(UserStatusAction.SUSPEND, UserStatusAction.BAN, UserStatusAction.DEACTIVATE)
            "suspendedUntil" ->
                listOf(UserStatusAction.RESTORE, UserStatusAction.BAN, UserStatusAction.DEACTIVATE)
            "bannedPermanent",
            "deactivated" -> listOf(UserStatusAction.RESTORE)
            else -> emptyList()
        }
    }

    fun requireTarget(
        session: ModerationSession,
        snapshot: UserStatusSnapshot,
        action: UserStatusAction,
    ) {
        requireSession(session)
        validate(snapshot.version)
        if (
            session.uid == snapshot.version.targetId ||
                snapshot.role == "owner" ||
                snapshot.role !in setOf("owner", "admin", "user") ||
                (snapshot.role == "admin" && session.role != "owner")
        )
            fail(UserStatusFailure.ACCESS)
        if (action !in availableActions(session, snapshot)) fail(UserStatusFailure.STALE)
    }

    fun normalizeText(value: String): String {
        if (value.length > LocalCallableProtocol.MAX_REQUEST_BYTES) fail(UserStatusFailure.INVALID)
        return value.trim {
            it in " \t\n\r\u000B\u000C\u00A0\u1680\u2028\u2029\u202F\u205F\u3000\uFEFF" ||
                it in '\u2000'..'\u200A'
        }
    }

    fun suspensionUntil(
        now: Instant,
        days: Int = DEFAULT_SUSPENSION_DAYS,
        zoneId: ZoneId,
    ): Instant {
        if (days !in suspensionOptions || !validTime(now)) fail(UserStatusFailure.INVALID)
        val result = runCatching {
            now.atZone(zoneId).plusDays(days.toLong()).toInstant().truncatedTo(ChronoUnit.MILLIS)
        }
            .getOrElse { throw UserStatusException(UserStatusFailure.INVALID, it) }
        if (!validTime(result) || result <= now) fail(UserStatusFailure.INVALID)
        return result
    }

    fun payload(
        targetId: String,
        action: UserStatusAction,
        reason: String,
        until: Instant?,
    ): Map<String, String> {
        if (!id(targetId)) fail(UserStatusFailure.INVALID)
        val text = normalizeText(reason)
        if (
            text.isEmpty() ||
                text.any { it.isISOControl() && it !in "\n\r\t" } ||
                ((action == UserStatusAction.SUSPEND) != (until != null)) ||
                (until != null && (!validTime(until) || until.nano % 1_000_000 != 0))
        )
            fail(UserStatusFailure.INVALID)
        hash(text) // Reject malformed UTF-16 before JSON can silently replace it.
        val result = buildMap {
            put("targetUserId", targetId)
            put("reason", text)
            until?.let { put("until", it.toString()) }
        }
        try {
            LocalCallableProtocol.request(result)
        } catch (error: Exception) {
            throw UserStatusException(UserStatusFailure.INVALID, error)
        }
        return result
    }

    fun snapshot(targetId: String, fields: Map<String, Any?>): UserStatusSnapshot {
        // Document path is the only routing authority, matching the callable/iOS legacy reader.
        // A missing or mismatched legacy string id is fingerprinted, never used as a redirect.
        if (!id(targetId) || (fields.containsKey("id") && fields["id"] !is String))
            fail(UserStatusFailure.INVALID)
        fun optionalText(key: String): String? =
            fields[key]?.let {
                it as? String ?: fail(UserStatusFailure.INVALID)
            }
        fun status(key: String, fallback: String, block: Boolean): String {
            if (!fields.containsKey(key)) return fallback
            val value = fields[key] as? String ?: fail(UserStatusFailure.INVALID)
            return when {
                value in canonicalStatuses -> value
                !block && value == "temporarilyBanned" -> "suspendedUntil"
                !block && value == "permanentlyBanned" -> "bannedPermanent"
                block && value == "blocked" -> "suspendedUntil"
                else -> fail(UserStatusFailure.INVALID)
            }
        }
        if (fields.containsKey("isBlocked") && fields["isBlocked"] !is Boolean)
            fail(UserStatusFailure.INVALID)
        val block =
            status(
                "blockState",
                if (fields["isBlocked"] == true) "suspendedUntil" else "active",
                true,
            )
        val account = status("accountStatus", block, false)
        val role =
            if (!fields.containsKey("globalRole")) "user"
            else
                when (fields["globalRole"]) {
                    "owner" -> "owner"
                    "admin" -> "admin"
                    "user",
                    "moderator",
                    "topAdmin",
                    "appModerator" -> "user"
                    else -> fail(UserStatusFailure.INVALID)
                }
        val count = if (!fields.containsKey("warningCount")) 0L else count(fields["warningCount"])
        fun time(key: String): Instant? =
            fields[key]?.let { instant(it) ?: fail(UserStatusFailure.INVALID) }
        val expiry = time("banExpiresAt")
        val updated = time("statusUpdatedAt")
        val acknowledged = time("statusAcknowledgedAt")
        time("updatedAt")
        time("createdAt")
        val actor = optionalText("statusUpdatedBy")
        if (actor != null && !id(actor)) fail(UserStatusFailure.INVALID)
        val fingerprint = rawHash(listOf("uac-user-status-version-v1", targetId, fields))
        // Match ManagedUsersContract's displayName/fullName alias and 500-character preview.
        // This projection never trims, replaces, or removes anything in the hashed raw fields.
        fun displayText(key: String): String? {
            val value = (fields[key] as? String).orEmpty()
            val preview =
                if (value.length > 500) {
                    val prefix = value.take(500)
                    // Keep a display-only limit from cutting an emoji's UTF-16 surrogate pair.
                    (if (prefix.last().isHighSurrogate()) prefix.dropLast(1) else prefix) + "…"
                } else value
            return preview.takeUnless { it.isBlank() }
        }
        return UserStatusSnapshot(
            UserStatusVersion(
                targetId,
                fingerprint,
                previousHash(account, block),
                preservedHash(targetId, fields),
            ),
            role,
            account,
            block,
            count,
            optionalText("statusReason"),
            optionalText("statusMessage"),
            expiry,
            updated,
            acknowledged,
            actor,
            displayName = displayText("displayName") ?: displayText("fullName"),
            email = displayText("email"),
        )
    }

    fun prepared(
        session: ModerationSession,
        snapshot: UserStatusSnapshot,
        action: UserStatusAction,
        reason: String,
        until: Instant?,
        operationId: String,
    ): UserStatusPending {
        requireTarget(session, snapshot, action)
        val text = payload(snapshot.version.targetId, action, reason, until).getValue("reason")
        val nextCount =
            if (action == UserStatusAction.WARN) {
                if (snapshot.warningCount >= MAX_SAFE_COUNT) fail(UserStatusFailure.INVALID)
                snapshot.warningCount + 1
            } else snapshot.warningCount
        return UserStatusPending(
                accountHash(session.uid),
                snapshot.version,
                action,
                hash(text),
                hash(action.messagePrefix + text),
                stateHash(action.status, action.status, nextCount, until),
                untilHash(until),
                operationId,
                session.role,
                UserStatusPhase.PREPARED,
            )
            .also(::validate)
    }

    /**
     * Only the response of the actual awaited call may create this receipt. No readback synthesis.
     */
    fun receipt(entry: UserStatusPending, data: Any?): UserStatusReceipt {
        validate(entry)
        if (entry.phase != UserStatusPhase.DISPATCHED) fail(UserStatusFailure.UNCONFIRMED)
        try {
            val map = data as? Map<*, *> ?: fail(UserStatusFailure.UNCONFIRMED)
            if (
                map.keys !=
                    setOf(
                        "targetUserId",
                        "previousAccountStatus",
                        "newAccountStatus",
                        "previousBlockState",
                        "newBlockState",
                        "warningCount",
                        "banExpiresAt",
                        "updatedAt",
                    ) ||
                    map["targetUserId"] != entry.version.targetId ||
                    map["newAccountStatus"] != entry.action.status ||
                    map["newBlockState"] != entry.action.status
            )
                fail(UserStatusFailure.UNCONFIRMED)
            val previousAccount =
                map["previousAccountStatus"] as? String ?: fail(UserStatusFailure.UNCONFIRMED)
            val previousBlock =
                map["previousBlockState"] as? String ?: fail(UserStatusFailure.UNCONFIRMED)
            if (previousAccount !in canonicalStatuses || previousBlock !in canonicalStatuses)
                fail(UserStatusFailure.UNCONFIRMED)
            val nextCount = count(map["warningCount"])
            if (entry.action == UserStatusAction.WARN && nextCount == 0L)
                fail(UserStatusFailure.UNCONFIRMED)
            val expiry = if (map["banExpiresAt"] == null) null else wireInstant(map["banExpiresAt"])
            if (
                (entry.action == UserStatusAction.SUSPEND) != (expiry != null) ||
                    untilHash(expiry) != entry.untilHash
            )
                fail(UserStatusFailure.UNCONFIRMED)
            val time = wireInstant(map["updatedAt"])
            // Server has no CAS: previous states and actual new count can legitimately differ
            // from the reviewed prediction. Preserve that valid own-call acceptance.
            return UserStatusReceipt(
                bindingHash(entry),
                rawHash(listOf("uac-user-status-response-v1", map)),
                previousHash(previousAccount, previousBlock),
                stateHash(entry.action.status, entry.action.status, nextCount, expiry),
                time,
            )
        } catch (error: UserStatusException) {
            if (error.failure == UserStatusFailure.UNCONFIRMED) throw error
            throw UserStatusException(UserStatusFailure.UNCONFIRMED, error)
        }
    }

    fun matches(entry: UserStatusPending, actorUid: String, fields: Map<String, Any?>): Boolean =
        runCatching {
            validate(entry)
            if (accountHash(actorUid) != entry.accountHash) return false
            val current = snapshot(entry.version.targetId, fields)
            if (
                fields["accountStatus"] != entry.action.status ||
                    fields["blockState"] != entry.action.status ||
                    fields["isBlocked"] != entry.action.blocked ||
                    fields["statusUpdatedBy"] != actorUid ||
                    !fields.containsKey("statusAcknowledgedAt") ||
                    fields["statusAcknowledgedAt"] != null ||
                    current.statusReason?.let(::hash) != entry.reasonHash ||
                    current.statusMessage?.let(::hash) != entry.messageHash ||
                    current.statusUpdatedAt == null ||
                    instant(fields["updatedAt"]) != current.statusUpdatedAt ||
                    current.version.preservedHash != entry.version.preservedHash
            )
                return false
            stateHash(
                current.accountStatus,
                current.blockState,
                current.warningCount,
                current.banExpiresAt,
            ) == (entry.receipt?.newStateHash ?: entry.desiredStateHash)
        }
        .getOrDefault(false)

    fun observation(
        entry: UserStatusPending,
        actorUid: String,
        fields: Map<String, Any?>?,
    ): UserStatusObservation {
        validate(entry)
        if (accountHash(actorUid) != entry.accountHash) fail(UserStatusFailure.ACCESS)
        if (fields == null || runCatching { snapshot(entry.version.targetId, fields) }.isFailure)
            return if (entry.receipt != null) UserStatusObservation.CONFIRMED_UNAVAILABLE
            else UserStatusObservation.UNAVAILABLE
        val matches = matches(entry, actorUid, fields)
        return if (entry.receipt != null) {
            if (matches) UserStatusObservation.CONFIRMED_CURRENT
            else UserStatusObservation.CONFIRMED_CHANGED
        } else if (matches) UserStatusObservation.OBSERVED_WITHOUT_RECEIPT
        else UserStatusObservation.UNCONFIRMED
    }

    fun instant(value: Any?): Instant? =
        when (value) {
            is Instant -> value
            is Timestamp -> Instant.ofEpochSecond(value.seconds, value.nanoseconds.toLong())
            else -> null
        }?.takeIf(::validTime)

    fun untilHash(value: Instant?): String = rawHash(listOf("uac-user-status-until-v1", value))

    private fun wireInstant(value: Any?): Instant {
        val text = value as? String ?: fail(UserStatusFailure.UNCONFIRMED)
        val time =
            text.takeIf { it.length <= 40 }?.let { runCatching { Instant.parse(it) }.getOrNull() }
                ?: fail(UserStatusFailure.UNCONFIRMED)
        if (!validTime(time) || time.nano % 1_000_000 != 0) fail(UserStatusFailure.UNCONFIRMED)
        return time
    }

    private fun validTime(value: Instant) = value in minimumTime..maximumTime

    private fun count(value: Any?): Long =
        when (value) {
            is Byte,
            is Short,
            is Int,
            is Long -> (value as Number).toLong().takeIf { it in 0..MAX_SAFE_COUNT }
            is Double ->
                value
                    .takeIf {
                        it.isFinite() &&
                            it >= 0 &&
                            it <= MAX_SAFE_COUNT.toDouble() &&
                            it == it.toLong().toDouble()
                    }
                    ?.toLong()
            else -> null
        } ?: fail(UserStatusFailure.INVALID)

    private fun previousHash(account: String, block: String) =
        rawHash(listOf("uac-user-status-previous-v1", account, block))

    private fun stateHash(account: String, block: String, count: Long, until: Instant?) =
        rawHash(listOf("uac-user-status-state-v1", account, block, count, until))

    private fun preservedHash(id: String, fields: Map<String, Any?>) =
        rawHash(
            listOf("uac-user-status-preserved-v1", id, fields.filterKeys { it !in changedFields })
        )

    private fun bindingHash(entry: UserStatusPending): String {
        validateCore(entry)
        return rawHash(
            listOf(
                "uac-user-status-request-v1",
                entry.backend,
                entry.accountHash,
                entry.version.targetId,
                entry.version.fingerprint,
                entry.version.previousStateHash,
                entry.version.preservedHash,
                entry.action.name,
                entry.reasonHash,
                entry.messageHash,
                entry.desiredStateHash,
                entry.untilHash,
                entry.operationId,
                entry.issuedRole,
            )
        )
    }

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
            if (count < 0 || count > 1_048_576 - bytes) fail(UserStatusFailure.INVALID)
            bytes += count
        }

        private fun text(value: String) {
            if (value.length > 1_048_576) fail(UserStatusFailure.INVALID)
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
                                fail(UserStatusFailure.INVALID)
                            4
                        }
                        c.isLowSurrogate() -> fail(UserStatusFailure.INVALID)
                        else -> 3
                    }
                if (size > 1_048_576 - bytes - 4) fail(UserStatusFailure.INVALID)
            }
            out.writeInt(size)
            out.write(value.toByteArray(Charsets.UTF_8))
        }

        fun value(value: Any?, depth: Int) {
            if (depth > 20 || ++entries > 4096) fail(UserStatusFailure.INVALID)
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
                    if (!value.isFinite()) fail(UserStatusFailure.INVALID)
                    out.writeByte(3)
                    out.writeLong(value.toRawBits())
                }
                is String -> {
                    out.writeByte(4)
                    text(value)
                }
                is Instant,
                is Timestamp -> {
                    val instant = instant(value) ?: fail(UserStatusFailure.INVALID)
                    out.writeByte(5)
                    out.writeLong(instant.epochSecond)
                    out.writeInt(instant.nano)
                }
                is List<*> -> {
                    if (value.size > 4096 - entries) fail(UserStatusFailure.INVALID)
                    out.writeByte(6)
                    out.writeInt(value.size)
                    value.forEach { value(it, depth + 1) }
                }
                is Map<*, *> -> {
                    if (value.size > 4096 - entries || value.keys.any { it !is String })
                        fail(UserStatusFailure.INVALID)
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
                else -> fail(UserStatusFailure.INVALID)
            }
        }

        fun finish(): String =
            digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
    }
}
