package at.uac.android

import at.uac.android.feature.auth.AuthLocalUnlockPolicy
import at.uac.android.feature.auth.AuthLocalUnlockToken
import org.junit.Assert.*
import org.junit.Test

class AuthLocalUnlockPolicyTest {
    @Test
    fun onlyOneMatchingPausedResumeIsPreserved() {
        val policy = AuthLocalUnlockPolicy()
        val token = policy.begin("a", 7)!!
        assertNull(policy.begin("a", 7))
        assertFalse(token.toString().contains("uid"))
        policy.onHostPause()
        policy.finish(token)
        assertTrue(policy.consumeResume("a", 7, true))
        assertFalse(policy.consumeResume("a", 7, true))
    }

    @Test
    fun resultAfterResumeCannotExemptAnotherForeground() {
        val policy = AuthLocalUnlockPolicy()
        val token = policy.begin("a", 7)!!
        policy.onHostPause()
        assertTrue(policy.consumeResume("a", 7, true))
        policy.finish(token)
        assertFalse(policy.consumeResume("a", 7, true))
    }

    @Test
    fun synchronousLaunchWithoutPauseNeverExemptsForeground() {
        val policy = AuthLocalUnlockPolicy()
        val token = policy.begin("a", 7)!!
        policy.finish(token)
        policy.onHostPause()
        assertFalse(policy.consumeResume("a", 7, true))
    }

    @Test
    fun wrongAccountRevisionAndUnavailableIdentityFailClosed() {
        for ((uid, revision, valid) in
            listOf(Triple("b", 7L, true), Triple("a", 8L, true), Triple("a", 7L, false))) {
            val policy = AuthLocalUnlockPolicy()
            policy.begin("a", 7)
            policy.onHostPause()
            assertFalse(policy.consumeResume(uid, revision, valid))
            assertFalse(policy.consumeResume("a", 7, true))
        }
    }

    @Test
    fun cancellationAndRepeatedBackgroundInvalidateLease() {
        val cancelled = AuthLocalUnlockPolicy()
        val token = cancelled.begin("a", 7)!!
        cancelled.onHostPause()
        cancelled.cancel(token)
        assertFalse(cancelled.consumeResume("a", 7, true))
        val background = AuthLocalUnlockPolicy()
        background.begin("a", 7)
        background.onHostPause()
        background.onHostPause()
        assertFalse(background.consumeResume("a", 7, true))
        val changed = AuthLocalUnlockPolicy()
        changed.begin("a", 7)
        changed.onHostPause()
        changed.invalidate()
        assertFalse(changed.consumeResume("a", 7, true))
    }

    @Test
    fun forgedCallbackDoesNotReleaseActualNativeLease() {
        val policy = AuthLocalUnlockPolicy()
        policy.begin("a", 7)
        policy.onHostPause()
        val forged = AuthLocalUnlockToken("a", 7)
        policy.cancel(forged)
        policy.finish(forged)
        assertTrue(policy.consumeResume("a", 7, true))
    }
}
