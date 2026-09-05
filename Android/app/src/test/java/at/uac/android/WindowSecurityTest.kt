package at.uac.android

import at.uac.android.core.SecureFlagLeasePool
import org.junit.Assert.*
import org.junit.Test

class WindowSecurityTest {
    private class Target(var flags: Int = 0)

    private val secure = 8

    private fun pool() =
        SecureFlagLeasePool<Target>(
            isSecure = { it.flags and secure != 0 },
            setSecure = { target, value ->
                target.flags = if (value) target.flags or secure else target.flags and secure.inv()
            },
        )

    @Test
    fun overlappingMfaAndAppLockKeepProtectionUntilLastLease() {
        val window = Target()
        val pool = pool()
        val mfa = pool.acquire(window)
        val lock = pool.acquire(window)
        mfa.close()
        assertEquals(secure, window.flags)
        lock.close()
        assertEquals(0, window.flags)
    }

    @Test
    fun preexistingSecureFlagAndOtherFlagsRemainUntouched() {
        val window = Target(secure or 2)
        val pool = pool()
        val first = pool.acquire(window)
        val second = pool.acquire(window)
        second.close()
        first.close()
        assertEquals(secure or 2, window.flags)
        val next = pool.acquire(window)
        next.close()
        assertEquals(secure or 2, window.flags)
    }

    @Test
    fun doubleCloseCannotReleaseAnotherOwnersLease() {
        val window = Target(2)
        val pool = pool()
        val first = pool.acquire(window)
        val second = pool.acquire(window)
        first.close()
        first.close()
        assertEquals(secure or 2, window.flags)
        window.flags = window.flags or 4
        second.close()
        second.close()
        assertEquals(2 or 4, window.flags)
    }

    @Test
    fun windowsOwnIndependentLeasesIncludingNewAcquisitionAfterRelease() {
        val first = Target()
        val second = Target()
        val pool = pool()
        val one = pool.acquire(first)
        val two = pool.acquire(second)
        one.close()
        assertEquals(0, first.flags)
        assertEquals(secure, second.flags)
        val next = pool.acquire(first)
        two.close()
        assertEquals(secure, first.flags)
        assertEquals(0, second.flags)
        next.close()
        assertEquals(0, first.flags)
    }
}
