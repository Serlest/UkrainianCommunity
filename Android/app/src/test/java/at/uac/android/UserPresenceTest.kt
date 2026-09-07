package at.uac.android

import at.uac.android.feature.auth.AuthIdentity
import at.uac.android.feature.auth.AuthProfile
import at.uac.android.feature.auth.AuthSession
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.moderation.ModerationDecisionGate
import at.uac.android.feature.moderation.ModerationSession
import at.uac.android.feature.presence.*
import java.time.Instant
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class UserPresenceTest {
    private val sessionId = "11111111-1111-4111-8111-111111111111"

    @Test
    fun presenceEligibilityRequiresVerifiedNonAnonymousActiveProfile() {
        val identity = AuthIdentity("user", "user@example.invalid", true)
        val profile = AuthProfile("user", "user@example.invalid", "User")
        val ready = AuthSession(AuthStage.AUTHENTICATED, identity, profile)
        assertEquals("user", UserPresenceContract.eligibleUser(ready))
        assertNull(
            UserPresenceContract.eligibleUser(
                ready.copy(identity = identity.copy(emailVerified = false))
            )
        )
        assertNull(
            UserPresenceContract.eligibleUser(
                ready.copy(profile = profile.copy(blockState = "blocked"))
            )
        )
        assertNull(
            UserPresenceContract.eligibleUser(
                ready.copy(identity = identity.copy(anonymous = true))
            )
        )
    }

    @Test
    fun activeLifecycleSendsImmediateHeartbeatPeriodicHeartbeatAndOffline() = runTest {
        val source = FakeSource()
        var uid: String? = "user-1"
        val service =
            UserPresenceService(source, { uid }, this, 90_000, newSessionId = { sessionId })
        service.update(uid, true)
        runCurrent()
        advanceTimeBy(90_000)
        runCurrent()
        service.update(uid, false)
        runCurrent()
        assertEquals(listOf(true, true, false), source.updates.map { it.active })
        assertEquals(listOf(1L, 2L, 3L), source.updates.map { it.sequence })
        assertTrue(source.updates.all { it.userId == "user-1" && it.sessionId == sessionId })
    }

    @Test
    fun logoutAttemptsCleanupButCapturedUidCannotWriteAsANewAccount() = runTest {
        val source = FakeSource()
        var uid: String? = "old-user"
        val service =
            UserPresenceService(source, { uid }, this, 90_000, newSessionId = { sessionId })
        service.update(uid, true)
        runCurrent()
        uid = null
        service.update(null, false)
        runCurrent()
        // The old account's offline send was queued, then correctly failed closed after logout.
        assertEquals(listOf(true), source.updates.map { it.active })
        advanceTimeBy(180_000)
        runCurrent()
        assertEquals(1, source.updates.size)
    }

    @Test
    fun accountSwitchUsesANewSessionAndNeverRetargetsOldQueuedUpdate() = runTest {
        var uid: String? = "one"
        val source = FakeSource()
        var ids = listOf(sessionId, "22222222-2222-4222-8222-222222222222").iterator()
        val service =
            UserPresenceService(source, { uid }, this, 90_000, newSessionId = { ids.next() })
        service.update(uid, true)
        runCurrent()
        uid = "two"
        service.update(uid, true)
        runCurrent()
        assertEquals(listOf("one", "two"), source.updates.map { it.userId })
        assertEquals(listOf(1L, 1L), source.updates.map { it.sequence })
        assertNotEquals(source.updates[0].sessionId, source.updates[1].sessionId)
        service.close()
        runCurrent()
    }

    @Test
    fun loginWhileHostRemainsResumedStartsPresenceWithoutAnotherResumeEvent() = runTest {
        val users = kotlinx.coroutines.flow.MutableStateFlow<String?>(null)
        var uid: String? = null
        val source = FakeSource()
        val service =
            UserPresenceService(source, { uid }, this, 90_000, newSessionId = { sessionId })
        service.bind(users)
        service.update(null, true)
        uid = "signed-in"
        users.value = uid
        runCurrent()
        assertEquals(listOf("signed-in"), source.updates.map { it.userId })
        assertEquals(listOf(true), source.updates.map { it.active })
        service.update(uid, false)
        runCurrent()
        service.close()
    }

    @Test
    fun managedResponseUsesServerClockAndCapsLease() {
        val started = 5_000_000_000L
        val snapshot =
            UserPresenceContract.snapshot(
                "target",
                mapOf(
                    "targetUserId" to "target",
                    "lastSeenAt" to 1_700_000_000_000L,
                    "onlineUntil" to 1_000_000L,
                    "serverTime" to 1L,
                ),
                started,
            )
        assertEquals(Instant.ofEpochMilli(1_700_000_000_000L), snapshot.lastSeenAt)
        assertTrue(snapshot.isOnline(started + 179_999_000_000L))
        assertFalse(snapshot.isOnline(started + 180_000_000_000L))
    }

    @Test
    fun privilegedReadFailsClosedAndRejectsMismatchedResponse() = runTest {
        val allowed = ModerationSession("admin", 4, "admin", true)
        var current: ModerationSession? = allowed
        val source = FakeSource(managedTarget = "other")
        val repository = ManagedUserPresenceRepository(source, { current }, passthroughGate())
        val mismatch = runCatching { repository.load(allowed, "target") }.exceptionOrNull()
        assertEquals(PresenceFailure.INVALID, (mismatch as PresenceException).failure)

        current = ModerationSession("user", 5, "user", true)
        val denied = runCatching { repository.load(current, "target") }.exceptionOrNull()
        assertEquals(PresenceFailure.DENIED, (denied as PresenceException).failure)
    }

    private fun passthroughGate() =
        object : ModerationDecisionGate {
            override suspend fun <T> withSession(
                session: ModerationSession,
                action: suspend () -> T,
            ): T = action()
        }

    private class FakeSource(private val managedTarget: String = "target") : UserPresenceSource {
        val updates = mutableListOf<UserPresenceUpdate>()

        override suspend fun update(value: UserPresenceUpdate) {
            updates += value
        }

        override suspend fun managed(
            session: ModerationSession,
            targetUserId: String,
        ) = ManagedUserPresence(managedTarget, null, Long.MIN_VALUE)
    }
}
