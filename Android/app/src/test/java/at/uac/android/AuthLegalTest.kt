package at.uac.android

import at.uac.android.feature.auth.*
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class AuthLegalTest {
    private val terms =
        AuthLegalDocument(
            "terms",
            "synthetic-terms-current",
            true,
            mapOf("de" to "Terms"),
            mapOf("de" to "Full terms"),
        )
    private val privacy =
        AuthLegalDocument(
            "privacy",
            "synthetic-privacy-current",
            true,
            mapOf("de" to "Privacy"),
            mapOf("de" to "Full privacy"),
        )
    private val identity = AuthIdentity("legal-a", "legal-a@example.invalid", true)
    private val versions
        get() = mapOf(terms.type to terms.version, privacy.type to privacy.version)

    @Test
    fun wirePayloadExplicitlyIdentifiesAndroidAndNeverIncludesIdentityOrSecrets() {
        val payload = legalAcceptancePayload(terms, "uk")
        assertEquals(
            setOf("documentType", "version", "appVersion", "locale", "acceptedFromPlatform"),
            payload.keys,
        )
        assertEquals("android", payload["acceptedFromPlatform"])
        assertEquals("uk", payload["locale"])
        assertEquals("de", legalAcceptancePayload(terms, "unknown")["locale"])
        assertThrows(AuthException::class.java) {
            legalAcceptancePayload(terms.copy(type = "other"), "de")
        }
    }

    @Test
    fun receiptDecoderRejectsWrongVersionTypeOrDateWithoutLocalFallback() {
        val valid =
            mapOf(
                "documentType" to terms.type,
                "version" to terms.version,
                "acceptedAt" to "2026-09-02T22:00:00.123Z",
            )
        assertTrue(decodeLegalAcceptanceResponse(valid, terms) > 0)
        for (bad in
            listOf(
                null,
                "string",
                valid + ("documentType" to "privacy"),
                valid + ("version" to "old"),
                valid + ("acceptedAt" to "not-a-date"),
                valid - "acceptedAt",
            )) {
            assertThrows(AuthException::class.java) { decodeLegalAcceptanceResponse(bad, terms) }
        }
    }

    @Test
    fun verifiedReceiptsAndOwnServerProfileOpenTheGate() = runTest {
        val profiles = Profiles()
        val acceptor = Acceptor(profiles)
        val store = AuthStore(Backend(), profiles, backgroundScope, acceptor)
        store.restore().join()
        assertEquals(AuthGate.LEGAL_REQUIRED, store.state.value.gate)
        store.acceptLegalDocuments(versions, "uk")!!.join()
        assertTrue(store.state.value.readyForActions)
        assertEquals(2, store.state.value.legalReceipts.size)
        assertEquals(listOf("terms", "privacy"), acceptor.calls)
        assertEquals(AuthNotice.LEGAL_ACCEPTED, store.state.value.notice)
    }

    @Test
    fun missingOrInventedConsentCannotCallTheBackend() = runTest {
        val profiles = Profiles()
        val acceptor = Acceptor(profiles)
        val store = AuthStore(Backend(), profiles, backgroundScope, acceptor)
        store.restore().join()
        assertNull(store.acceptLegalDocuments(mapOf("terms" to terms.version), "de"))
        assertNull(store.acceptLegalDocuments(versions + ("privacy" to "different"), "de"))
        assertEquals(AuthProblem.CONSENT_REQUIRED, store.state.value.error)
        assertTrue(acceptor.calls.isEmpty())
        assertFalse(store.state.value.readyForActions)
    }

    @Test
    fun staleConsentRefreshesTextAndCannotBeReusedOrReopenedByProfileWatch() = runTest {
        val profiles = Profiles()
        val acceptor = Acceptor(profiles)
        val store = AuthStore(Backend(), profiles, backgroundScope, acceptor)
        store.restore().join()
        runCurrent()
        val newer = terms.copy(version = "synthetic-newer-terms")
        profiles.documents = listOf(newer, privacy)
        store.acceptLegalDocuments(versions, "de")!!.join()
        assertEquals(AuthProblem.LEGAL_CHANGED, store.state.value.error)
        assertEquals(newer.version, store.state.value.legalDocuments.first().version)
        assertTrue(acceptor.calls.isEmpty())
        profiles.result =
            profiles.result.copy(
                acceptedTermsVersion = terms.version,
                acceptedPrivacyVersion = privacy.version,
            )
        profiles.events.emit(Result.success(profiles.result))
        runCurrent()
        assertEquals(AuthGate.LEGAL_REQUIRED, store.state.value.gate)
        assertFalse(store.state.value.readyForActions)
    }

    @Test
    fun liveLegalPointerChangeRevokesReadyWithoutWaitingForAppResume() = runTest {
        val profiles =
            Profiles().apply {
                result =
                    result.copy(
                        acceptedTermsVersion = terms.version,
                        acceptedPrivacyVersion = privacy.version,
                    )
            }
        val store = AuthStore(Backend(), profiles, backgroundScope, Acceptor(profiles))
        store.restore().join()
        runCurrent()
        assertTrue(store.state.value.readyForActions)
        val oldRevision = store.state.value.revision
        profiles.documents = listOf(terms.copy(version = "synthetic-next-terms"), privacy)
        profiles.legalEvents.emit(
            Result.success(mapOf("terms" to "synthetic-next-terms", "privacy" to privacy.version))
        )
        runCurrent()
        assertTrue(store.state.value.revision > oldRevision)
        assertEquals(AuthGate.LEGAL_REQUIRED, store.state.value.gate)
        assertFalse(store.state.value.readyForActions)
        profiles.legalEvents.emit(Result.failure(AuthException(AuthProblem.NETWORK)))
        runCurrent()
        assertEquals(AuthGate.LEGAL_UNAVAILABLE, store.state.value.gate)
        profiles.events.emit(Result.success(profiles.result))
        runCurrent()
        assertFalse(store.state.value.readyForActions)
    }

    @Test
    fun validPointerWithUnreadableBodyDoesNotStartAnInfiniteRestoreLoop() = runTest {
        val profiles = Profiles().apply { documents = emptyList() }
        val store = AuthStore(Backend(), profiles, backgroundScope, Acceptor(profiles))
        store.restore().join()
        runCurrent()
        val revision = store.state.value.revision
        repeat(2) {
            profiles.legalEvents.emit(Result.success(versions))
            runCurrent()
        }
        assertEquals(revision, store.state.value.revision)
        assertEquals(AuthGate.LEGAL_UNAVAILABLE, store.state.value.gate)
        assertFalse(store.state.value.readyForActions)
    }

    @Test
    fun retryAfterPartialAcceptanceSendsOnlyTheRemainingDocument() = runTest {
        val profiles = Profiles()
        val acceptor = Acceptor(profiles).apply { failType = "privacy" }
        val store = AuthStore(Backend(), profiles, backgroundScope, acceptor)
        store.restore().join()
        store.acceptLegalDocuments(versions, "de")!!.join()
        assertEquals(AuthGate.LEGAL_REQUIRED, store.state.value.gate)
        assertEquals(listOf("terms"), store.state.value.legalReceipts.map { it.type })
        acceptor.failType = null
        store.acceptLegalDocuments(mapOf("privacy" to privacy.version), "de")!!.join()
        assertTrue(store.state.value.readyForActions)
        assertEquals(listOf("terms", "privacy", "privacy"), acceptor.calls)
    }

    @Test
    fun lostResponseDoesNotInventReceiptOrReplayConfirmedServerAcceptance() = runTest {
        val profiles =
            Profiles().apply { documents = listOf(terms, privacy.copy(requiresAcceptance = false)) }
        val acceptor =
            Acceptor(profiles).apply {
                failType = "terms"
                commitBeforeFailure = true
            }
        val store = AuthStore(Backend(), profiles, backgroundScope, acceptor)
        store.restore().join()
        store.acceptLegalDocuments(mapOf("terms" to terms.version), "de")!!.join()
        assertEquals(AuthGate.LEGAL_UNAVAILABLE, store.state.value.gate)
        assertTrue(store.state.value.legalReceipts.isEmpty())
        assertFalse(store.state.value.readyForActions)
        store.refresh().join()
        assertTrue(store.state.value.readyForActions)
        assertEquals(listOf("terms"), acceptor.calls)
    }

    @Test
    fun offlinePreflightCannotCallOrOpenTheLegalGate() = runTest {
        val profiles = Profiles()
        val acceptor = Acceptor(profiles)
        val store = AuthStore(Backend(), profiles, backgroundScope, acceptor)
        store.restore().join()
        profiles.failRead = true
        store.acceptLegalDocuments(versions, "de")!!.join()
        assertEquals(AuthProblem.NETWORK, store.state.value.error)
        assertEquals(AuthGate.LEGAL_UNAVAILABLE, store.state.value.gate)
        assertTrue(acceptor.calls.isEmpty())
        assertTrue(store.state.value.legalReceipts.isEmpty())
    }

    @Test
    fun declineSignsOutWithoutCreatingAnAcceptance() = runTest {
        val profiles = Profiles()
        val acceptor = Acceptor(profiles)
        val backend = Backend()
        val store = AuthStore(backend, profiles, backgroundScope, acceptor)
        store.restore().join()
        store.signOut().join()
        assertNull(backend.current)
        assertEquals(AuthStage.GUEST, store.state.value.stage)
        assertTrue(acceptor.calls.isEmpty())
    }

    @Test
    fun signOutDuringAcceptanceClearsUiImmediatelyAndWaitsForActualCall() = runTest {
        val blocker = CompletableDeferred<Unit>()
        val profiles = Profiles()
        val acceptor = Acceptor(profiles).apply { beforeCall = { blocker.await() } }
        val backend = Backend()
        val store = AuthStore(backend, profiles, backgroundScope, acceptor)
        store.restore().join()
        val acceptance = store.acceptLegalDocuments(versions, "de")!!
        runCurrent()
        val logout = store.signOut()
        assertNull(store.state.value.profile)
        assertTrue(store.state.value.legalReceipts.isEmpty())
        runCurrent()
        assertEquals(identity.uid, backend.current?.uid)
        blocker.complete(Unit)
        logout.join()
        acceptance.join()
        assertEquals(AuthStage.GUEST, store.state.value.stage)
        assertNull(backend.current)
        assertTrue(store.state.value.legalReceipts.isEmpty())
        assertEquals(listOf("terms"), acceptor.calls)
    }

    @Test
    fun serverRestrictionBeforeAcceptanceBlocksItEvenIfUiWasPreviouslyActive() = runTest {
        val profiles = Profiles()
        val acceptor = Acceptor(profiles)
        val store = AuthStore(Backend(), profiles, backgroundScope, acceptor)
        store.restore().join()
        profiles.result = profiles.result.copy(accountStatus = "bannedPermanent")
        store.acceptLegalDocuments(versions, "de")!!.join()
        assertEquals(AuthGate.RESTRICTED, store.state.value.gate)
        assertEquals(AuthProblem.PERMISSION_DENIED, store.state.value.error)
        assertTrue(acceptor.calls.isEmpty())
    }

    @Test
    fun malformedReceiptNeverBecomesClientConsent() = runTest {
        val profiles = Profiles()
        val acceptor = Acceptor(profiles).apply { malformedReceipt = true }
        val store = AuthStore(Backend(), profiles, backgroundScope, acceptor)
        store.restore().join()
        store.acceptLegalDocuments(versions, "de")!!.join()
        assertEquals(AuthProblem.LEGAL_UNCONFIRMED, store.state.value.error)
        assertTrue(store.state.value.legalReceipts.isEmpty())
        assertFalse(store.state.value.readyForActions)
    }

    private inner class Profiles : AuthProfiles {
        var result =
            AuthProfile(
                identity.uid,
                identity.email,
                "Legal test",
                acceptedTermsVersion = "old",
                acceptedPrivacyVersion = "old",
            )
        var documents = listOf(terms, privacy)
        var failRead = false
        val events = MutableSharedFlow<Result<AuthProfile>>(extraBufferCapacity = 2)
        val legalEvents = MutableSharedFlow<Result<Map<String, String>>>(extraBufferCapacity = 2)

        override suspend fun fetch(uid: String): AuthProfile {
            if (failRead) throw AuthException(AuthProblem.NETWORK)
            assertEquals(identity.uid, uid)
            return result
        }

        override suspend fun legalDocuments(): List<AuthLegalDocument> = documents

        override suspend fun create(uid: String, draft: AuthRegistration) = Unit

        override suspend fun ensurePublicProfile(profile: AuthProfile) = Unit

        override fun observe(uid: String) = events

        override fun observeLegalVersions() = legalEvents
    }

    private inner class Acceptor(private val profiles: Profiles) : AuthLegalAcceptor {
        val calls = mutableListOf<String>()
        var failType: String? = null
        var commitBeforeFailure = false
        var malformedReceipt = false
        var beforeCall: suspend () -> Unit = {}

        override suspend fun accept(
            uid: String,
            document: AuthLegalDocument,
            language: String,
        ): AuthLegalReceipt {
            assertEquals(identity.uid, uid)
            calls += document.type
            beforeCall()
            if (document.type != failType || commitBeforeFailure) {
                profiles.result =
                    when (document.type) {
                        "terms" -> profiles.result.copy(acceptedTermsVersion = document.version)
                        else -> profiles.result.copy(acceptedPrivacyVersion = document.version)
                    }
            }
            if (document.type == failType) throw AuthException(AuthProblem.NETWORK)
            return AuthLegalReceipt(
                if (malformedReceipt) "foreign" else document.type,
                document.version,
                1234L,
                1235L,
            )
        }
    }

    private inner class Backend : AuthBackend {
        override var current: AuthIdentity? = identity

        override suspend fun reload() = current ?: throw AuthException(AuthProblem.SESSION_CHANGED)

        override suspend fun refreshToken() = false

        override suspend fun signOut() {
            current = null
        }

        override suspend fun signIn(email: String, password: String) = error("Unused")

        override suspend fun create(email: String, password: String, displayName: String) =
            error("Unused")

        override suspend fun deleteCreatedUser(uid: String) = Unit

        override suspend fun sendVerification(language: String) = Unit

        override suspend fun sendPasswordReset(email: String, language: String) = Unit

        override suspend fun verifyEmailCode(code: String) = Unit

        override suspend fun resetPasswordCode(code: String, password: String) = Unit
    }
}
