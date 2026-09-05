package at.uac.android

import at.uac.android.feature.auth.*
import com.google.firebase.Timestamp
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

/**
 * Policy/fake-backend tests only. A true test TOTP flag is not real SDK enrollment/sign-in proof.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class AuthStatusAcknowledgementTest {
    private fun identity(uid: String = "a") = AuthIdentity(uid, "$uid@example.invalid", true)

    private fun profile(uid: String = "a") =
        AuthProfile(
            uid,
            "$uid@example.invalid",
            "Synthetic status user",
            accountStatus = "warned",
            blockState = "warned",
            acceptedTermsVersion = "1",
            acceptedPrivacyVersion = "1",
        )

    private fun session() =
        AuthSession(
            AuthStage.AUTHENTICATED,
            identity(),
            profile(),
            revision = 7,
        )

    private fun fields(): Map<String, Any?> =
        mapOf(
            "id" to "a",
            "email" to "a@example.invalid",
            "displayName" to "Synthetic status user",
            "globalRole" to "user",
            "accountStatus" to "warned",
            "blockState" to "warned",
        )

    private fun invalid(fields: Map<String, Any?>) {
        val error = runCatching { decodeProfile("a", fields) }.exceptionOrNull()
        assertEquals(AuthProblem.INVALID_PROFILE, (error as? AuthException)?.problem)
    }

    @Test
    fun exactNanosecondsSurviveAllStatusTimestamps() {
        val updated = Timestamp(1_788_432_123, 123_456_789)
        val acknowledged = Timestamp(1_788_432_123, 123_456_790)
        val expires = Timestamp(1_788_432_999, 987_654_321)
        val decoded =
            decodeProfile(
                "a",
                fields() +
                    mapOf(
                        "statusUpdatedAt" to updated,
                        "statusAcknowledgedAt" to acknowledged,
                        "banExpiresAt" to expires,
                    ),
            )
        assertEquals(Instant.ofEpochSecond(updated.seconds, 123_456_789), decoded.statusUpdatedAt)
        assertEquals(decoded.statusUpdatedAt!!.plusNanos(1), decoded.statusAcknowledgedAt)
        assertEquals(Instant.ofEpochSecond(expires.seconds, 987_654_321), decoded.banExpiresAt)
    }

    @Test
    fun reasonAndMessageRemainIndependentCompleteRawValues() {
        val reason = "  Причина\n" + "Ї".repeat(12_000) + "  "
        val message = " Nachricht\r\n" + "ä".repeat(12_000) + " "
        val decoded =
            decodeProfile(
                "a",
                fields() + mapOf("statusReason" to reason, "statusMessage" to message),
            )
        assertEquals(reason, decoded.statusReason)
        assertEquals(message, decoded.statusMessage)
        val onlyMessage = decodeProfile("a", fields() + mapOf("statusMessage" to message))
        assertNull(onlyMessage.statusReason)
        assertEquals(message, onlyMessage.statusMessage)
    }

    @Test
    fun absentAndNullOptionalStatusMetadataRemainAbsent() {
        for (extras in
            listOf(
                emptyMap(),
                mapOf(
                    "statusReason" to null,
                    "statusMessage" to null,
                    "statusUpdatedAt" to null,
                    "statusAcknowledgedAt" to null,
                    "banExpiresAt" to null,
                ),
            )) {
            val value = decodeProfile("a", fields() + extras)
            assertNull(value.statusReason)
            assertNull(value.statusMessage)
            assertNull(value.statusUpdatedAt)
            assertNull(value.statusAcknowledgedAt)
            assertNull(value.banExpiresAt)
        }
    }

    @Test
    fun malformedStatusTimestampAndTextTypesNeverBecomeAcknowledgementVersions() {
        for (key in listOf("statusUpdatedAt", "statusAcknowledgedAt", "banExpiresAt")) {
            for (value in
                listOf(
                    "2026-09-03T00:00:00Z",
                    123L,
                    Instant.EPOCH,
                    emptyMap<String, Any>(),
                )) invalid(fields() + (key to value))
        }
        for (key in listOf("statusReason", "statusMessage")) {
            for (value in listOf(7, true, emptyList<String>())) invalid(fields() + (key to value))
        }
    }

    @Test
    fun malformedPresentAuthorityFieldsNeverFallBackToActive() {
        for (key in listOf("accountStatus", "blockState")) {
            for (value in listOf(null, 1, true, emptyMap<String, Any>())) invalid(
                fields() + (key to value)
            )
        }
        for (value in listOf(null, "false", 0)) invalid(
            fields().minus("blockState") + ("isBlocked" to value)
        )
    }

    @Test
    fun trulyMissingLegacyAuthorityFieldsKeepCompatibleButRestrictedFallback() {
        val legacy = fields().minus(setOf("accountStatus", "blockState"))
        assertTrue(decodeProfile("a", legacy).active)
        assertFalse(decodeProfile("a", legacy + ("isBlocked" to true)).active)
        assertTrue(decodeProfile("a", legacy + ("isBlocked" to false)).active)
        assertFalse(decodeProfile("a", fields() + ("accountStatus" to "future-status")).active)
        assertFalse(decodeProfile("a", fields() + ("blockState" to "")).active)
    }

    @Test
    fun legacyMissingIdIsReadableButForeignIdRemainsRejected() {
        assertEquals("a", decodeProfile("a", fields().minus("id")).uid)
        invalid(fields() + ("id" to "other"))
        // The transaction source, not this decoder, must reject missing stored id for Rules ack.
    }

    @Test
    fun expiryNeverLocallyRestoresRestrictedAuthority() {
        val value =
            decodeProfile(
                "a",
                fields() +
                    mapOf(
                        "accountStatus" to "suspendedUntil",
                        "blockState" to "suspendedUntil",
                        "banExpiresAt" to Timestamp(0, 0),
                    ),
            )
        assertFalse(value.active)
        assertEquals(AuthGate.RESTRICTED, gateFor(value, false, emptyList()))
    }

    @Test
    fun onlyActiveAndWarnedExactSessionMayAcknowledge() {
        val valid = session()
        assertTrue(valid.canAcknowledgeAccountStatus())
        assertTrue(
            valid
                .copy(profile = profile().copy(accountStatus = "active", blockState = "active"))
                .canAcknowledgeAccountStatus()
        )
        assertFalse(valid.permitsStatusAcknowledgement("other", valid.revision))
        assertFalse(valid.permitsStatusAcknowledgement("a", valid.revision + 1))
        for (bad in
            listOf(
                valid.copy(identity = null),
                valid.copy(profile = null),
                valid.copy(identity = identity("other")),
                valid.copy(profile = profile("other")),
                valid.copy(identity = identity().copy(emailVerified = false)),
                valid.copy(identity = identity().copy(anonymous = true)),
                valid.copy(busy = true),
            )) assertFalse(bad.canAcknowledgeAccountStatus())
        for (stage in AuthStage.entries.filter { it != AuthStage.AUTHENTICATED }) assertFalse(
            valid.copy(stage = stage).canAcknowledgeAccountStatus()
        )
        for (state in
            listOf(
                "suspendedUntil",
                "temporarilyBanned",
                "bannedPermanent",
                "permanentlyBanned",
                "deactivated",
                "blocked",
                "unknown",
            )) {
            assertFalse(
                valid
                    .copy(profile = profile().copy(accountStatus = state))
                    .canAcknowledgeAccountStatus()
            )
            assertFalse(
                valid
                    .copy(profile = profile().copy(blockState = state))
                    .canAcknowledgeAccountStatus()
            )
        }
    }

    @Test
    fun legalIndependenceNeverBypassesRestrictedOrMfaGates() {
        val valid = session()
        for (gate in
            listOf(AuthGate.READY, AuthGate.LEGAL_REQUIRED, AuthGate.LEGAL_UNAVAILABLE)) assertTrue(
            valid.copy(gate = gate).canAcknowledgeAccountStatus()
        )
        for (gate in listOf(AuthGate.RESTRICTED, AuthGate.MFA_REQUIRED)) assertFalse(
            valid.copy(gate = gate).canAcknowledgeAccountStatus()
        )
        assertFalse(valid.copy(mfa = AuthMfaState(challenge = true)).canAcknowledgeAccountStatus())
        assertFalse(
            valid.copy(mfa = AuthMfaState(unconfirmed = true)).canAcknowledgeAccountStatus()
        )
        assertFalse(
            valid
                .copy(mfa = AuthMfaState(setup = AuthTotpSetup("TEST", "otpauth://totp/test", 1)))
                .canAcknowledgeAccountStatus()
        )
    }

    @Test
    fun privilegedPredicateKeepsActivationAndRealClaimRequirementsDistinct() {
        for (role in listOf("admin", "owner")) {
            for (activated in listOf(false, true)) for (totp in listOf(false, true)) {
                val value =
                    session()
                        .copy(
                            profile =
                                profile()
                                    .copy(globalRole = role, requiresMultiFactorAuth = activated),
                            totpAuthenticated = totp,
                        )
                assertEquals(activated && totp, value.canAcknowledgeAccountStatus())
            }
        }
    }

    private class Backend : AuthBackend {
        override var current: AuthIdentity? = AuthIdentity("a", "a@example.invalid", true)
        var totp = false

        override suspend fun reload() = current!!

        override suspend fun refreshToken() = totp

        override suspend fun signIn(email: String, password: String) =
            AuthIdentity(email.substringBefore('@'), email, true).also { current = it }

        override suspend fun signOut() {
            current = null
        }

        override suspend fun create(email: String, password: String, displayName: String) =
            error("Unused")

        override suspend fun deleteCreatedUser(uid: String) = Unit

        override suspend fun sendVerification(language: String) = Unit

        override suspend fun sendPasswordReset(email: String, language: String) = Unit

        override suspend fun verifyEmailCode(code: String) = Unit

        override suspend fun resetPasswordCode(code: String, password: String) = Unit
    }

    private inner class Profiles : AuthProfiles {
        var value = profile()
        var legalRequired = false
        var legalUnavailable = false
        val changes = MutableSharedFlow<Result<AuthProfile>>()

        override suspend fun create(uid: String, draft: AuthRegistration) = error("Unused")

        override suspend fun fetch(uid: String) =
            value.copy(uid = uid, email = "$uid@example.invalid")

        override suspend fun legalDocuments(): List<AuthLegalDocument> {
            if (legalUnavailable) throw AuthException(AuthProblem.NETWORK)
            return listOf("terms", "privacy").map {
                AuthLegalDocument(it, if (legalRequired) "2" else "1", true, emptyMap(), emptyMap())
            }
        }

        override suspend fun ensurePublicProfile(profile: AuthProfile) = Unit

        override fun observe(uid: String) = changes
    }

    @Test
    fun dedicatedGateAllowsLegalRequiredAndUnavailableWithoutOpeningGeneralActions() = runTest {
        for (unavailable in listOf(false, true)) {
            val profiles =
                Profiles().apply {
                    legalRequired = true
                    legalUnavailable = unavailable
                }
            val store = AuthStore(Backend(), profiles, backgroundScope)
            store.restore().join()
            assertEquals(
                if (unavailable) AuthGate.LEGAL_UNAVAILABLE else AuthGate.LEGAL_REQUIRED,
                store.state.value.gate,
            )
            assertFalse(store.state.value.readyForActions)
            assertEquals(
                "confirmed",
                store.withStatusAcknowledgementSession("a", store.state.value.revision) {
                    "confirmed"
                },
            )
            val blocked = runCatching {
                store.withReadySession("a", store.state.value.revision) {
                    fail("Not general authority")
                }
            }
            assertEquals(
                AuthProblem.PERMISSION_DENIED,
                (blocked.exceptionOrNull() as AuthException).problem,
            )
            assertFalse(store.state.value.readyForActions)
        }
    }

    @Test
    fun dedicatedGateDeniesUnverifiedAndRestrictedBeforeAction() = runTest {
        for (mode in listOf("unverified", "restricted", "unavailable")) {
            val backend =
                Backend().apply {
                    if (mode == "unverified") current = current!!.copy(emailVerified = false)
                }
            val profiles =
                Profiles().apply {
                    if (mode == "restricted") value = value.copy(accountStatus = "suspendedUntil")
                }
            val store = AuthStore(backend, profiles, backgroundScope)
            store.restore().join()
            runCurrent()
            if (mode == "unavailable") {
                profiles.changes.emit(Result.failure(AuthException(AuthProblem.PROFILE_MISSING)))
                runCurrent()
            }
            var invoked = false
            val result = runCatching {
                store.withStatusAcknowledgementSession("a", store.state.value.revision) {
                    invoked = true
                }
            }
            assertEquals(
                AuthProblem.PERMISSION_DENIED,
                (result.exceptionOrNull() as AuthException).problem,
            )
            assertFalse(invoked)
        }
    }

    @Test
    fun dedicatedGateDoesNotTreatAnActivatedProfileAsTotpProof() = runTest {
        for (role in listOf("owner", "admin")) for (activated in listOf(false, true)) {
            val profiles =
                Profiles().apply {
                    value = value.copy(globalRole = role, requiresMultiFactorAuth = activated)
                }
            val store = AuthStore(Backend(), profiles, backgroundScope)
            store.restore().join()
            var invoked = false
            val result = runCatching {
                store.withStatusAcknowledgementSession("a", store.state.value.revision) {
                    invoked = true
                }
            }
            assertEquals(
                AuthProblem.PERMISSION_DENIED,
                (result.exceptionOrNull() as AuthException).problem,
            )
            assertFalse(invoked)
        }
    }

    @Test
    fun actualBackendVerificationAndAnonymousStateAreRecheckedBeforeAndAfterAction() = runTest {
        for (anonymous in listOf(false, true)) for (after in listOf(false, true)) {
            val backend = Backend()
            val store = AuthStore(backend, Profiles(), backgroundScope)
            store.restore().join()
            val invalid = backend.current!!.copy(emailVerified = anonymous, anonymous = anonymous)
            if (!after) backend.current = invalid
            var invoked = false
            val result = runCatching {
                store.withStatusAcknowledgementSession("a", store.state.value.revision) {
                    invoked = true
                    backend.current = invalid
                }
            }
            assertEquals(
                AuthProblem.PERMISSION_DENIED,
                (result.exceptionOrNull() as AuthException).problem,
            )
            assertEquals(after, invoked)
        }
    }

    @Test
    fun foreignBackendIdentityCannotEnterOrReturnFromGate() = runTest {
        for (after in listOf(false, true)) {
            val backend = Backend()
            val store = AuthStore(backend, Profiles(), backgroundScope)
            store.restore().join()
            if (!after) backend.current = identity("b")
            var invoked = false
            val result = runCatching {
                store.withStatusAcknowledgementSession("a", store.state.value.revision) {
                    invoked = true
                    backend.current = identity("b")
                }
            }
            assertEquals(
                AuthProblem.SESSION_CHANGED,
                (result.exceptionOrNull() as AuthException).problem,
            )
            assertEquals(after, invoked)
        }
    }

    @Test
    fun profileRestrictionDuringSettlementRejectsLateSuccess() = runTest {
        val profiles = Profiles()
        val store = AuthStore(Backend(), profiles, backgroundScope)
        store.restore().join()
        runCurrent()
        val settled = CompletableDeferred<Unit>()
        val operation = async {
            runCatching {
                store.withStatusAcknowledgementSession("a", store.state.value.revision) {
                    settled.await()
                }
            }
        }
        runCurrent()
        profiles.changes.emit(
            Result.success(
                profiles.value.copy(accountStatus = "deactivated", blockState = "deactivated")
            )
        )
        runCurrent()
        settled.complete(Unit)
        assertEquals(
            AuthProblem.PERMISSION_DENIED,
            (operation.await().exceptionOrNull() as AuthException).problem,
        )
        assertEquals(AuthGate.RESTRICTED, store.state.value.gate)
    }

    @Test
    fun queuedAccountSwitchKeepsOldBackendIdentityUntilActualSettlement() = runTest {
        val backend = Backend()
        val store = AuthStore(backend, Profiles(), backgroundScope)
        store.restore().join()
        val revision = store.state.value.revision
        val settled = CompletableDeferred<Unit>()
        var actorAtSettlement: String? = null
        val operation = async {
            runCatching {
                store.withStatusAcknowledgementSession("a", revision) {
                    settled.await()
                    actorAtSettlement = backend.current?.uid
                }
            }
        }
        runCurrent()
        val login = store.signIn("b@example.invalid", "password")!!
        runCurrent()
        assertEquals("a", backend.current?.uid)
        assertFalse(login.isCompleted)
        settled.complete(Unit)
        assertEquals(
            AuthProblem.SESSION_CHANGED,
            (operation.await().exceptionOrNull() as AuthException).problem,
        )
        login.join()
        assertEquals("a", actorAtSettlement)
        assertEquals("b", backend.current?.uid)
    }

    @Test fun cancelledConsumerStillWaitsForActualSdkSuccess() = cancelledConsumer(sdkFails = false)

    @Test fun cancelledConsumerDoesNotLeakLateSdkFailure() = cancelledConsumer(sdkFails = true)

    private fun cancelledConsumer(sdkFails: Boolean) = runTest {
        val backend = Backend()
        val store = AuthStore(backend, Profiles(), backgroundScope)
        store.restore().join()
        val revision = store.state.value.revision
        val settled = CompletableDeferred<Unit>()
        var actorAtSettlement: String? = null
        var delivered = false
        var completionError: Throwable? = null
        val operation = async {
            store.withStatusAcknowledgementSession("a", revision) {
                settled.await()
                actorAtSettlement = backend.current?.uid
                if (sdkFails) throw AuthException(AuthProblem.NETWORK)
            }
            delivered = true
        }
        operation.invokeOnCompletion { completionError = it }
        runCurrent()
        operation.cancel()
        val out = store.signOut()
        runCurrent()
        assertEquals("a", backend.current?.uid)
        assertFalse(out.isCompleted)
        assertFalse(operation.isCompleted)
        settled.complete(Unit)
        operation.join()
        out.join()
        assertEquals("a", actorAtSettlement)
        assertTrue(operation.isCancelled)
        assertTrue(completionError is CancellationException)
        assertFalse(delivered)
        assertNull(backend.current)
    }

    @Test
    fun cancellationWhileWaitingForMutexNeverStartsTheSecondAction() = runTest {
        val store = AuthStore(Backend(), Profiles(), backgroundScope)
        store.restore().join()
        val revision = store.state.value.revision
        val settled = CompletableDeferred<Unit>()
        val first = async {
            store.withStatusAcknowledgementSession("a", revision) { settled.await() }
        }
        runCurrent()
        var invoked = false
        val queued = async {
            store.withStatusAcknowledgementSession("a", revision) { invoked = true }
        }
        runCurrent()
        queued.cancel()
        settled.complete(Unit)
        first.await()
        queued.join()
        assertFalse(invoked)
    }

    @Test
    fun operationFailureReleasesMutexAndDoesNotChangeAccountAuthority() = runTest {
        val store = AuthStore(Backend(), Profiles(), backgroundScope)
        store.restore().join()
        val before = store.state.value
        val failure = runCatching {
            store.withStatusAcknowledgementSession("a", before.revision) {
                throw AuthException(AuthProblem.NETWORK)
            }
        }
        assertEquals(AuthProblem.NETWORK, (failure.exceptionOrNull() as AuthException).problem)
        assertEquals(before, store.state.value)
        assertEquals(
            "next",
            store.withStatusAcknowledgementSession("a", before.revision) { "next" },
        )
    }
}
