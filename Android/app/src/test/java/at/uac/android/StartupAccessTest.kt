package at.uac.android

import at.uac.android.feature.auth.AuthGate
import at.uac.android.feature.auth.AuthIdentity
import at.uac.android.feature.auth.AuthProfile
import at.uac.android.feature.auth.AuthSession
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.startup.StartupAccess
import at.uac.android.feature.startup.startupAccess
import org.junit.Assert.assertEquals
import org.junit.Test

class StartupAccessTest {
    private val identity = AuthIdentity("u1", "u1@example.invalid", true)
    private val profile = AuthProfile("u1", "u1@example.invalid", "User")
    private val ready = AuthSession(AuthStage.AUTHENTICATED, identity, profile)

    @Test
    fun onlyFullyReadyAccountCanSeeAppShell() {
        assertEquals(StartupAccess.LOADING, startupAccess(AuthSession()))
        assertEquals(StartupAccess.APP, startupAccess(ready))
        for (session in
            listOf(
                AuthSession(AuthStage.GUEST),
                AuthSession(AuthStage.AUTHENTICATING, identity),
                AuthSession(AuthStage.VERIFICATION_PENDING, identity),
                AuthSession(AuthStage.MFA_CHALLENGE, identity),
                AuthSession(AuthStage.SESSION_UNAVAILABLE, identity),
                ready.copy(gate = AuthGate.RESTRICTED),
                ready.copy(gate = AuthGate.MFA_REQUIRED),
                ready.copy(gate = AuthGate.LEGAL_REQUIRED),
                ready.copy(gate = AuthGate.LEGAL_UNAVAILABLE),
                ready.copy(busy = true),
                ready.copy(identity = identity.copy(emailVerified = false)),
            )) {
            assertEquals("${session.stage}/${session.gate}", StartupAccess.ACCOUNT, startupAccess(session))
        }
    }
}
