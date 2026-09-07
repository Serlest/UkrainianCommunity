package at.uac.android.feature.presence

import at.uac.android.feature.moderation.ModerationDecisionGate
import at.uac.android.feature.moderation.ModerationSession
import at.uac.android.feature.personal.validDocumentId
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch

interface UserPresenceSource {
    suspend fun update(value: UserPresenceUpdate)

    suspend fun managed(session: ModerationSession, targetUserId: String): ManagedUserPresence
}

/** Privileged read is independently gated; knowing a target UID grants no presence access. */
class ManagedUserPresenceRepository(
    private val source: UserPresenceSource,
    private val authority: () -> ModerationSession?,
    private val gate: ModerationDecisionGate,
) {
    suspend fun load(session: ModerationSession, targetUserId: String): ManagedUserPresence {
        requireCurrent(session)
        val result =
            gate.withSession(session) {
                requireCurrent(session)
                source.managed(session, targetUserId).also { snapshot ->
                    requireCurrent(session)
                    if (snapshot.targetUserId != targetUserId)
                        throw PresenceException(PresenceFailure.INVALID)
                }
            }
        requireCurrent(session)
        return result
    }

    private fun requireCurrent(session: ModerationSession) {
        if (authority() != session) throw CancellationException("Presence session changed")
        if (!session.ready) throw PresenceException(PresenceFailure.NOT_READY)
        if (!session.allowed) throw PresenceException(PresenceFailure.DENIED)
        if (!validDocumentId(session.uid)) throw PresenceException(PresenceFailure.INVALID)
    }
}

/**
 * Process-scoped foreground lease. It has no disk queue and never retries a failed send. A UID is
 * captured in every update, so delayed work cannot be retargeted to a later account.
 */
class UserPresenceService(
    private val source: UserPresenceSource,
    private val authority: () -> String?,
    private val scope: CoroutineScope,
    private val intervalMillis: Long = UserPresenceContract.HEARTBEAT_MILLIS,
    private val newSessionId: () -> String = { UUID.randomUUID().toString() },
) {
    private var userId: String? = null
    private var sessionId = ""
    private var sequence = 0L
    private var hostActive = false
    private var active = false
    private var heartbeat: Job? = null
    private var observer: Job? = null

    fun bind(users: Flow<String?>): Job {
        observer?.cancel()
        return scope.launch { users.collect { update(it, hostActive) } }.also { observer = it }
    }

    fun update(nextUserId: String?, isActive: Boolean) {
        hostActive = isActive
        val nextActive = nextUserId != null && isActive
        if (nextUserId == userId && nextActive == active) return
        heartbeat?.cancel()
        heartbeat = null
        val previousActive = active
        val sameUser = nextUserId == userId
        if (!sameUser) {
            if (previousActive) publish(userId, false)
            userId = nextUserId
            sessionId = newSessionId()
            sequence = 0
        }
        active = nextActive
        if (nextActive || sameUser && previousActive) publish(userId, nextActive)
        if (nextActive) {
            heartbeat = scope.launch {
                while (true) {
                    delay(intervalMillis)
                    if (!active || userId != nextUserId) return@launch
                    publish(nextUserId, true)
                }
            }
        }
    }

    fun close() {
        heartbeat?.cancel()
        heartbeat = null
        observer?.cancel()
        observer = null
        if (active) publish(userId, false)
        hostActive = false
        active = false
        userId = null
    }

    private fun publish(capturedUserId: String?, nextActive: Boolean) {
        if (capturedUserId == null) return
        val update =
            UserPresenceUpdate(capturedUserId, sessionId, ++sequence, nextActive)
                .also(UserPresenceContract::validate)
        scope.launch {
            // A logout/account switch makes queued work a no-op. Lease expiry is the fallback.
            if (authority() != update.userId) return@launch
            runCatching { source.update(update) }
        }
    }
}
