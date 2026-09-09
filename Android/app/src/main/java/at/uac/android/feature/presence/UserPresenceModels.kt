package at.uac.android.feature.presence

import at.uac.android.feature.auth.AuthSession
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.personal.validDocumentId
import java.time.Instant

data class UserPresenceUpdate(
    val userId: String,
    val sessionId: String,
    val sequence: Long,
    val active: Boolean,
)

data class ManagedUserPresence(
    val targetUserId: String,
    val lastSeenAt: Instant?,
    private val onlineDeadlineNanos: Long,
) {
    fun isOnline(monotonicNanos: Long = System.nanoTime()): Boolean =
        monotonicNanos < onlineDeadlineNanos

    override fun toString() = "ManagedUserPresence([redacted], online=${isOnline()})"
}

enum class PresenceFailure {
    SIGN_IN,
    NOT_READY,
    DENIED,
    OFFLINE,
    INVALID,
    MISSING,
    UNKNOWN,
}

class PresenceException(val failure: PresenceFailure, cause: Throwable? = null) :
    Exception(failure.name, cause)

object UserPresenceContract {
    const val HEARTBEAT_MILLIS = 90_000L
    const val MAX_LEASE_MILLIS = 180_000L
    private val sessionId = Regex("^[a-f0-9-]{36}$", RegexOption.IGNORE_CASE)

    fun eligibleUser(session: AuthSession): String? {
        val identity = session.identity ?: return null
        val profile = session.profile ?: return null
        return identity.uid.takeIf {
            session.stage == AuthStage.AUTHENTICATED &&
                !session.busy &&
                !identity.anonymous &&
                identity.emailVerified &&
                profile.uid == identity.uid &&
                profile.active &&
                validDocumentId(identity.uid)
        }
    }

    fun validate(update: UserPresenceUpdate) {
        if (
            !validDocumentId(update.userId) ||
                !sessionId.matches(update.sessionId) ||
                update.sequence < 1
        )
            throw PresenceException(PresenceFailure.INVALID)
    }

    fun acknowledgement(data: Any?) {
        val body = data as? Map<*, *> ?: throw PresenceException(PresenceFailure.INVALID)
        if (body["accepted"] != true) throw PresenceException(PresenceFailure.INVALID)
    }

    fun snapshot(
        targetUserId: String,
        data: Any?,
        requestStartedNanos: Long,
    ): ManagedUserPresence {
        if (!validDocumentId(targetUserId)) throw PresenceException(PresenceFailure.INVALID)
        val body = data as? Map<*, *> ?: throw PresenceException(PresenceFailure.INVALID)
        if (body["targetUserId"] != targetUserId) throw PresenceException(PresenceFailure.INVALID)
        fun exactMillis(key: String): Long? {
            val value = body[key] ?: return null
            val number = value as? Number ?: throw PresenceException(PresenceFailure.INVALID)
            val millis = number.toLong()
            if (number.toDouble() != millis.toDouble() || millis < 0)
                throw PresenceException(PresenceFailure.INVALID)
            return millis
        }
        val server = exactMillis("serverTime") ?: throw PresenceException(PresenceFailure.INVALID)
        val online = exactMillis("onlineUntil")
        val remaining = ((online ?: server) - server).coerceIn(0, MAX_LEASE_MILLIS)
        return ManagedUserPresence(
            targetUserId,
            exactMillis("lastSeenAt")?.let(Instant::ofEpochMilli),
            requestStartedNanos + remaining * 1_000_000,
        )
    }
}
