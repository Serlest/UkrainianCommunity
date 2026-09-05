package at.uac.android

import at.uac.android.core.AuthRemediationPriority
import org.junit.Assert.*
import org.junit.Test

class AuthRemediationPriorityTest {
    @Test
    fun nestedReadersReleaseOnlyTheirOwnLease() {
        val priority = AuthRemediationPriority()
        priority.attach(1)
        val legal = priority.acquire(1)
        val security = priority.acquire(1)
        assertTrue(priority.active.value)
        legal.close()
        legal.close()
        assertTrue(priority.active.value)
        security.close()
        assertFalse(priority.active.value)
    }

    @Test
    fun obsoleteActivityCannotAcquireOrReleaseNewPresentation() {
        val priority = AuthRemediationPriority()
        priority.attach(1)
        val old = priority.acquire(1)
        priority.attach(2)
        assertFalse(priority.active.value)
        val stale = priority.acquire(1)
        assertFalse(priority.active.value)
        val current = priority.acquire(2)
        old.close()
        stale.close()
        assertTrue(priority.active.value)
        current.close()
        assertFalse(priority.active.value)
    }
}
