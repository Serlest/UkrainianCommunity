package at.uac.android

import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalCallableFailure
import at.uac.android.feature.auth.*
import at.uac.android.feature.dsastatement.*
import java.io.IOException
import org.junit.Assert.*
import org.junit.Test

class DsaStatementIntegrationTest {
    private fun auth() =
        AuthSession(
            stage = AuthStage.AUTHENTICATED,
            identity = AuthIdentity("user-id", "synthetic@example.invalid", true),
            profile = AuthProfile("user-id", "synthetic@example.invalid", "Synthetic"),
            revision = 7,
        )

    private fun profile(role: String = "user") =
        mapOf<String, Any?>(
            "globalRole" to role,
            "accountStatus" to "active",
            "blockState" to "active",
        )

    private fun denied(action: () -> Unit) {
        assertEquals(
            DsaStatementFailure.ACCESS,
            (runCatching(action).exceptionOrNull() as DsaStatementException).failure,
        )
    }

    @Test
    fun ordinaryVerifiedActiveUserGetsReadyScopeWithoutPrivilegedRole() {
        val scope = auth().dsaStatementScope()!!
        assertTrue(scope.ready)
        assertEquals(7L, scope.revision)
        assertEquals(dsaStatementBackendBinding, scope.backend)
    }

    @Test
    fun guestsAndAnonymousHaveNoScope() {
        assertNull(AuthSession().dsaStatementScope())
        assertNull(
            auth().copy(identity = auth().identity!!.copy(anonymous = true)).dsaStatementScope()
        )
    }

    @Test
    fun unreadyAccountStatesCannotGainStatementReadiness() {
        for (state in
            listOf(
                auth().copy(busy = true),
                auth().copy(gate = AuthGate.MFA_REQUIRED),
                auth().copy(gate = AuthGate.LEGAL_REQUIRED),
                auth().copy(stage = AuthStage.VERIFICATION_PENDING),
                auth().copy(identity = auth().identity!!.copy(emailVerified = false)),
                auth().copy(profile = auth().profile!!.copy(accountStatus = "suspended")),
                auth().copy(profile = auth().profile!!.copy(uid = "another")),
            )) assertFalse(state.dsaStatementScope()!!.ready)
    }

    @Test
    fun privilegedProjectionRetainsActivatedTotpRequirement() {
        for (role in listOf("admin", "owner")) {
            val state = auth().copy(profile = auth().profile!!.copy(globalRole = role))
            assertFalse(state.dsaStatementScope()!!.ready)
            assertFalse(state.copy(totpAuthenticated = true).dsaStatementScope()!!.ready)
            assertFalse(
                state
                    .copy(profile = state.profile!!.copy(requiresMultiFactorAuth = true))
                    .dsaStatementScope()!!
                    .ready
            )
            assertTrue(
                state
                    .copy(
                        profile = state.profile!!.copy(requiresMultiFactorAuth = true),
                        totpAuthenticated = true,
                    )
                    .dsaStatementScope()!!
                    .ready
            )
        }
    }

    @Test
    fun ordinarySdkProfileDoesNotRequireSecondFactor() {
        DsaStatementSdkPolicy.requireProfile(profile(), null)
    }

    @Test
    fun warnedSdkProfilesRemainActive() {
        DsaStatementSdkPolicy.requireProfile(
            profile() + mapOf("accountStatus" to "warned", "blockState" to "warned"),
            null,
        )
    }

    @Test
    fun absentMalformedRestrictedAndUnknownRoleSdkProfilesFailClosed() {
        for (value in
            listOf(
                null,
                emptyMap(),
                profile() - "accountStatus",
                profile() + ("blockState" to false),
                profile() + ("accountStatus" to "banned"),
                profile("future"),
            )) denied { DsaStatementSdkPolicy.requireProfile(value, null) }
    }

    @Test
    fun privilegedSdkProfileRequiresBothActivationAndActualTotpClaim() {
        for (role in listOf("admin", "owner")) {
            denied { DsaStatementSdkPolicy.requireProfile(profile(role), "totp") }
            denied {
                DsaStatementSdkPolicy.requireProfile(
                    profile(role) + ("requiresMultiFactorAuth" to true),
                    null,
                )
            }
            denied {
                DsaStatementSdkPolicy.requireProfile(
                    profile(role) + ("requiresMultiFactorAuth" to true),
                    "sms",
                )
            }
            DsaStatementSdkPolicy.requireProfile(
                profile(role) + ("requiresMultiFactorAuth" to true),
                "totp",
            )
        }
    }

    @Test
    fun callableMissingIsNotAccessOrEmptySuccess() {
        assertEquals(
            DsaStatementFailure.MISSING,
            dsaStatementReadFailure(LocalCallableException(LocalCallableFailure.NOT_FOUND)),
        )
        for (failure in
            listOf(
                LocalCallableFailure.UNAUTHENTICATED,
                LocalCallableFailure.PERMISSION_DENIED,
                LocalCallableFailure.FAILED_PRECONDITION,
            )) assertEquals(
            DsaStatementFailure.ACCESS,
            dsaStatementReadFailure(LocalCallableException(failure)),
        )
    }

    @Test
    fun timeoutAndNetworkAreOfflineNotMissing() {
        for (failure in
            listOf(
                LocalCallableFailure.UNAVAILABLE,
                LocalCallableFailure.DEADLINE_EXCEEDED,
                LocalCallableFailure.RESOURCE_EXHAUSTED,
            )) assertEquals(
            DsaStatementFailure.OFFLINE,
            dsaStatementReadFailure(LocalCallableException(failure)),
        )
        assertEquals(DsaStatementFailure.OFFLINE, dsaStatementReadFailure(IOException("private")))
    }

    @Test
    fun invalidAndUnknownErrorsRemainDistinct() {
        assertEquals(
            DsaStatementFailure.INVALID,
            dsaStatementReadFailure(LocalCallableException(LocalCallableFailure.DATA_LOSS)),
        )
        assertEquals(
            DsaStatementFailure.UNKNOWN,
            dsaStatementReadFailure(IllegalArgumentException("private")),
        )
        assertEquals(
            DsaStatementFailure.UNKNOWN,
            dsaStatementReadFailure(LocalCallableException(LocalCallableFailure.UNCONFIRMED)),
        )
    }
}
