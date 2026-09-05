package at.uac.android

import at.uac.android.feature.auth.*
import at.uac.android.feature.dsaappeal.*
import java.io.IOException
import org.junit.Assert.*
import org.junit.Test

class DsaAppealIntegrationTest {
    private fun auth() =
        AuthSession(
            stage = AuthStage.AUTHENTICATED,
            identity = AuthIdentity("reporter", "synthetic@example.invalid", true),
            profile = AuthProfile("reporter", "synthetic@example.invalid", "Synthetic"),
            revision = 8,
        )

    private fun profile(role: String = "user") =
        mapOf<String, Any?>(
            "globalRole" to role,
            "accountStatus" to "active",
            "blockState" to "active",
        )

    private fun denied(action: () -> Unit) {
        val error = runCatching(action).exceptionOrNull() as DsaAppealReviewException
        assertEquals(DsaAppealReviewFailure.ACCESS, error.failure)
        assertNull(error.cause)
    }

    @Test
    fun ordinaryVerifiedReporterHasExactReadyScope() {
        val scope = auth().dsaAppealScope()!!
        assertTrue(scope.ready)
        assertEquals(8L, scope.revision)
        assertEquals(dsaAppealBackendBinding, scope.backend)
        assertFalse(scope.toString().contains("reporter"))
    }

    @Test
    fun guestAndAnonymousCannotAcquireScope() {
        assertNull(AuthSession().dsaAppealScope())
        assertNull(
            auth().copy(identity = auth().identity!!.copy(anonymous = true)).dsaAppealScope()
        )
    }

    @Test
    fun busyLegalMfaUnverifiedAndMismatchedProfilesRemainUnready() {
        for (state in
            listOf(
                auth().copy(busy = true),
                auth().copy(gate = AuthGate.LEGAL_REQUIRED),
                auth().copy(gate = AuthGate.MFA_REQUIRED),
                auth().copy(stage = AuthStage.VERIFICATION_PENDING),
                auth().copy(identity = auth().identity!!.copy(emailVerified = false)),
                auth().copy(profile = auth().profile!!.copy(uid = "another")),
                auth().copy(profile = auth().profile!!.copy(accountStatus = "banned")),
            )) assertFalse(state.dsaAppealScope()!!.ready)
    }

    @Test
    fun privilegedScopeNeedsBothActivationAndTotp() {
        for (role in listOf("admin", "owner")) {
            val state = auth().copy(profile = auth().profile!!.copy(globalRole = role))
            assertFalse(state.dsaAppealScope()!!.ready)
            assertFalse(state.copy(totpAuthenticated = true).dsaAppealScope()!!.ready)
            val activated =
                state.copy(profile = state.profile!!.copy(requiresMultiFactorAuth = true))
            assertFalse(activated.dsaAppealScope()!!.ready)
            assertTrue(activated.copy(totpAuthenticated = true).dsaAppealScope()!!.ready)
        }
    }

    @Test
    fun actualOrdinaryAndWarnedProfilesAreAllowed() {
        DsaAppealSdkPolicy.requireProfile(profile(), null)
        DsaAppealSdkPolicy.requireProfile(
            profile() + mapOf("accountStatus" to "warned", "blockState" to "warned"),
            null,
        )
    }

    @Test
    fun malformedOrRestrictedActualProfileFailsClosed() {
        for (value in
            listOf(
                null,
                emptyMap(),
                profile() - "blockState",
                profile("unknown"),
                profile() + ("blockState" to false),
                profile() + ("accountStatus" to "suspended"),
            )) denied { DsaAppealSdkPolicy.requireProfile(value, null) }
    }

    @Test
    fun privilegedActualProfileCannotReplaceTotpWithLocalFlagOrSms() {
        for (role in listOf("owner", "admin")) {
            denied { DsaAppealSdkPolicy.requireProfile(profile(role), "totp") }
            val activated = profile(role) + ("requiresMultiFactorAuth" to true)
            for (factor in listOf(null, false, "sms", "TOTP")) denied {
                DsaAppealSdkPolicy.requireProfile(activated, factor)
            }
            DsaAppealSdkPolicy.requireProfile(activated, "totp")
        }
    }

    @Test
    fun cachedAndPendingReadsNeverBecomeFreshReview() {
        DsaAppealSdkPolicy.requireFresh(false, false)
        for ((cache, pending) in listOf(true to false, false to true, true to true)) {
            val error =
                runCatching { DsaAppealSdkPolicy.requireFresh(cache, pending) }.exceptionOrNull()
                    as DsaAppealReviewException
            assertEquals(DsaAppealReviewFailure.STALE, error.failure)
        }
    }

    @Test
    fun errorsNeverTurnIntoMissingOrExposeCause() {
        assertEquals(DsaAppealReviewFailure.OFFLINE, dsaAppealReadFailure(IOException("PRIVATE")))
        assertEquals(
            DsaAppealReviewFailure.UNKNOWN,
            dsaAppealReadFailure(IllegalStateException("PRIVATE")),
        )
        val failure =
            runCatching { DsaAppealReviewContract.fail(DsaAppealReviewFailure.EXPIRED) }
                .exceptionOrNull()!!
        assertEquals(DsaAppealReviewFailure.EXPIRED, dsaAppealReadFailure(failure))
    }
}
