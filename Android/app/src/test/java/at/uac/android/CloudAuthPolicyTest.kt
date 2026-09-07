package at.uac.android

import at.uac.android.feature.auth.emailAllowedForBackend
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CloudAuthPolicyTest {
    @Test
    fun emulatorAcceptsOnlyReservedSyntheticAddresses() {
        assertTrue(emailAllowedForBackend("test@example.invalid", localOnly = true))
        assertFalse(emailAllowedForBackend("person@example.com", localOnly = true))
    }

    @Test
    fun cloudAcceptsRealAccountAddresses() {
        assertTrue(emailAllowedForBackend("person@example.com", localOnly = false))
        assertTrue(emailAllowedForBackend("person@example.invalid", localOnly = false))
        assertFalse(emailAllowedForBackend("", localOnly = false))
    }
}
