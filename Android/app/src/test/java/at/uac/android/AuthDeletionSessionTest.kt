package at.uac.android

import at.uac.android.core.*
import at.uac.android.feature.auth.*
import java.time.Instant
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.test.*
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class AuthDeletionSessionTest {
    private class Backend : AuthBackend {
        override var current: AuthIdentity? = AuthIdentity("a", "a@example.invalid", true)
        var signOutCount = 0

        override suspend fun reload() = current!!

        override suspend fun refreshToken() = false

        override suspend fun signIn(email: String, password: String) =
            AuthIdentity(email.substringBefore('@'), email, true).also { current = it }

        override suspend fun signOut() {
            signOutCount++
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

    private class Profiles : AuthProfiles {
        var missing = false
        var restricted = false
        var writes = 0
        var legalReads = 0
        val observed = MutableSharedFlow<Result<AuthProfile>>()

        override suspend fun fetch(uid: String): AuthProfile {
            if (missing) throw AuthException(AuthProblem.PROFILE_MISSING)
            return AuthProfile(
                uid,
                "$uid@example.invalid",
                "Synthetic",
                accountStatus = if (restricted) "blocked" else "active",
            )
        }

        override suspend fun legalDocuments(): List<AuthLegalDocument> {
            legalReads++
            return listOf(
                AuthLegalDocument("terms", "1", false, emptyMap(), emptyMap()),
                AuthLegalDocument("privacy", "1", false, emptyMap(), emptyMap()),
            )
        }

        override fun observe(uid: String) = observed

        override suspend fun create(uid: String, draft: AuthRegistration) {
            writes++
        }

        override suspend fun ensurePublicProfile(profile: AuthProfile) {
            writes++
        }
    }

    private class Journal : AccountDeletionJournal {
        var entry: DeletionJournalEntry? = null
        var corrupt = false

        override suspend fun pending(uid: String): DeletionJournalEntry? {
            if (corrupt) error("Unreadable local record")
            return entry
        }

        override suspend fun record(uid: String, submittedAt: Instant) =
            DeletionJournalEntry(DeletionJournalCodec.accountHash(uid), submittedAt).also {
                entry = it
            }

        override suspend fun markPartial(uid: String, expectedSubmittedAt: Instant) = entry

        override suspend fun clearConfirmed(uid: String, expectedSubmittedAt: Instant): Boolean {
            entry = null
            return true
        }
    }

    @Test
    fun selfDeletionAllowsUnverifiedRestrictedAndUnavailableButNotGeneralActions() = runTest {
        for (mode in listOf("unverified", "restricted", "unavailable")) {
            val backend =
                Backend().apply {
                    if (mode == "unverified") current = current!!.copy(emailVerified = false)
                }
            val profiles = Profiles().apply { restricted = mode == "restricted" }
            val store = AuthStore(backend, profiles, backgroundScope)
            store.restore().join()
            runCurrent()
            if (mode == "unavailable") {
                profiles.observed.emit(Result.failure(AuthException(AuthProblem.PROFILE_MISSING)))
                runCurrent()
            }
            assertFalse(store.state.value.readyForActions)
            assertEquals(
                "allowed",
                store.withAccountDeletionSession("a", store.state.value.revision) { "allowed" },
            )
            assertTrue(
                runCatching {
                    store.withReadySession("a", store.state.value.revision) {
                        error("Must not run")
                    }
                }
                    .isFailure
            )
        }
    }

    @Test
    fun authAbsenceProducedByActualDeletionCheckIsAllowedOnlyAfterAction() = runTest {
        val backend = Backend()
        val store = AuthStore(backend, Profiles(), backgroundScope)
        store.restore().join()
        val revision = store.state.value.revision
        assertEquals(
            "absent",
            store.withAccountDeletionSession("a", revision) {
                backend.current = null
                "absent"
            },
        )
        assertTrue(
            runCatching {
                store.withAccountDeletionSession("a", revision) { error("Must not run") }
            }
                .isFailure
        )
        store.signOutDeletedIdentity("a", revision)!!.join()
        assertEquals(AuthStage.GUEST, store.state.value.stage)
        assertEquals(0, backend.signOutCount)
    }

    @Test
    fun foreignBackendIdentityIsRejectedAtBothBoundaries() = runTest {
        val backend = Backend()
        val store = AuthStore(backend, Profiles(), backgroundScope)
        store.restore().join()
        val revision = store.state.value.revision
        val result = runCatching {
            store.withAccountDeletionSession("a", revision) {
                backend.current = AuthIdentity("b", "b@example.invalid", true)
            }
        }
        assertEquals(
            AuthProblem.SESSION_CHANGED,
            (result.exceptionOrNull() as AuthException).problem,
        )
        assertNull(store.signOutDeletedIdentity("a", revision))
        assertEquals("b", backend.current?.uid)
        assertEquals(0, backend.signOutCount)
    }

    @Test
    fun actualInFlightDeletionKeepsBackendIdentityUntilCompletionDespiteNewLogin() = runTest {
        val backend = Backend()
        val store = AuthStore(backend, Profiles(), backgroundScope)
        store.restore().join()
        val revision = store.state.value.revision
        val gate = CompletableDeferred<Unit>()
        val deletion = async {
            runCatching {
                store.withAccountDeletionSession("a", revision) {
                    gate.await()
                    backend.current!!.uid
                }
            }
        }
        runCurrent()
        val next = store.signIn("b@example.invalid", "password")!!
        runCurrent()
        assertEquals("a", backend.current?.uid)
        assertTrue(store.state.value.busy)
        gate.complete(Unit)
        assertEquals(
            AuthProblem.SESSION_CHANGED,
            (deletion.await().exceptionOrNull() as AuthException).problem,
        )
        next.join()
        assertEquals("b", backend.current?.uid)
        assertNull(store.signOutDeletedIdentity("a", revision))
    }

    @Test
    fun callerCancellationCannotDetachDeletionSdkWait() = runTest {
        val backend = Backend()
        val store = AuthStore(backend, Profiles(), backgroundScope)
        store.restore().join()
        val revision = store.state.value.revision
        val gate = CompletableDeferred<Unit>()
        var completed = false
        val deletion = async {
            store.withAccountDeletionSession("a", revision) {
                gate.await()
                completed = true
            }
        }
        runCurrent()
        deletion.cancel()
        val out = store.signOut()
        runCurrent()
        assertEquals("a", backend.current?.uid)
        assertFalse(completed)
        gate.complete(Unit)
        deletion.join()
        out.join()
        assertTrue(completed)
        assertNull(backend.current)
        assertTrue(deletion.isCancelled)
    }

    @Test
    fun cancelledConsumerWaitsForActualSdkFailureWithoutCrashingNewSession() = runTest {
        val backend = Backend()
        val store = AuthStore(backend, Profiles(), backgroundScope)
        store.restore().join()
        val revision = store.state.value.revision
        val gate = CompletableDeferred<Unit>()
        var settled = false
        val deletion = async {
            store.withAccountDeletionSession("a", revision) {
                gate.await()
                settled = true
                throw AuthException(AuthProblem.NETWORK)
            }
        }
        runCurrent()
        deletion.cancel()
        val next = store.signIn("b@example.invalid", "password")!!
        runCurrent()
        assertEquals("a", backend.current?.uid)
        assertFalse(settled)
        gate.complete(Unit)
        deletion.join()
        next.join()
        assertTrue(settled)
        assertTrue(deletion.isCancelled)
        assertEquals("b", store.state.value.identity?.uid)
    }

    @Test
    fun queuedCompletionNeverInvalidatesNewLoginGeneration() = runTest {
        val backend = Backend()
        val store = AuthStore(backend, Profiles(), backgroundScope)
        store.restore().join()
        val revision = store.state.value.revision
        val completion = store.signOutDeletedIdentity("a", revision)!!
        val newLogin = store.signIn("b@example.invalid", "password")!!
        completion.join()
        newLogin.join()
        assertEquals("b", store.state.value.identity?.uid)
        assertTrue(store.state.value.readyForActions)
    }

    @Test
    fun matchingDurablePartialJournalPreservesOnlyRecoveryIdentityOnColdRestore() = runTest {
        val backend = Backend()
        val profiles = Profiles().apply { missing = true }
        val journal =
            Journal().apply {
                entry =
                    DeletionJournalEntry(
                        DeletionJournalCodec.accountHash("a"),
                        Instant.ofEpochMilli(1000),
                        DeletionJournalStatus.PARTIAL,
                    )
            }
        val store = AuthStore(backend, profiles, backgroundScope, deletionJournal = journal)
        store.restore().join()
        assertEquals("a", backend.current?.uid)
        assertEquals(0, backend.signOutCount)
        assertEquals(AuthStage.SESSION_UNAVAILABLE, store.state.value.stage)
        assertEquals(AuthGate.RESTRICTED, store.state.value.gate)
        assertTrue(store.state.value.deletionRecovery)
        assertFalse(store.state.value.readyForActions)
        assertNull(store.state.value.profile)
        assertNull(store.state.value.localPasswordProof)
        assertEquals(0, profiles.writes)
        assertEquals(0, profiles.legalReads)
        assertEquals(42, store.withAccountDeletionSession("a", store.state.value.revision) { 42 })
    }

    @Test
    fun missingProfileWithoutJournalRetainsExistingSignedOutBehavior() = runTest {
        val backend = Backend()
        val profiles = Profiles().apply { missing = true }
        val store = AuthStore(backend, profiles, backgroundScope, deletionJournal = Journal())
        store.restore().join()
        assertEquals(AuthStage.GUEST, store.state.value.stage)
        assertNull(backend.current)
        assertFalse(store.state.value.deletionRecovery)
        assertEquals(0, profiles.writes)
    }

    @Test
    fun corruptOrForeignJournalNeverPublishesReadyOrCreatesReplacementProfile() = runTest {
        for (corrupt in listOf(true, false)) {
            val backend = Backend()
            val profiles = Profiles().apply { missing = true }
            val journal =
                Journal().apply {
                    this.corrupt = corrupt
                    entry =
                        DeletionJournalEntry(
                            DeletionJournalCodec.accountHash("b"),
                            Instant.ofEpochMilli(1000),
                        )
                }
            val store = AuthStore(backend, profiles, backgroundScope, deletionJournal = journal)
            store.restore().join()
            assertEquals(AuthStage.SESSION_UNAVAILABLE, store.state.value.stage)
            assertFalse(store.state.value.readyForActions)
            assertFalse(store.state.value.deletionRecovery)
            assertEquals(0, profiles.writes)
            assertEquals(0, profiles.legalReads)
        }
    }

    @Test
    fun journalLookupCannotPublishOldRecoveryAfterAccountSwitch() = runTest {
        val backend = Backend()
        val profiles = Profiles().apply { missing = true }
        val blocker = CompletableDeferred<Unit>()
        val journal =
            object : AccountDeletionJournal by Journal() {
                override suspend fun pending(uid: String): DeletionJournalEntry? {
                    blocker.await()
                    return DeletionJournalEntry(
                        DeletionJournalCodec.accountHash(uid),
                        Instant.ofEpochMilli(1000),
                    )
                }
            }
        val store = AuthStore(backend, profiles, backgroundScope, deletionJournal = journal)
        store.restore()
        runCurrent()
        val out = store.signOut()
        blocker.complete(Unit)
        out.join()
        assertEquals(AuthStage.GUEST, store.state.value.stage)
        assertFalse(store.state.value.deletionRecovery)
    }

    @Test
    fun realLocalCredentialRoundTripPreservesExactAuthRevisionOnce() = runTest {
        val backend = Backend()
        val store = AuthStore(backend, Profiles(), backgroundScope)
        store.restore().join()
        val revision = store.state.value.revision
        val token = store.beginLocalUnlock("a", revision)!!
        store.onHostPause()
        store.finishLocalUnlock(token)
        assertNull(store.onForeground())
        assertEquals(revision, store.state.value.revision)
        store.onHostPause()
        store.onForeground()!!.join()
        assertTrue(store.state.value.revision > revision)
    }

    @Test
    fun localCredentialLeaseIsNotReadyAuthorityAndCannotSurviveTransition() = runTest {
        val backend = Backend().apply { current = current!!.copy(emailVerified = false) }
        val store = AuthStore(backend, Profiles(), backgroundScope)
        store.restore().join()
        val revision = store.state.value.revision
        val token = store.beginLocalUnlock("a", revision)!!
        store.onHostPause()
        store.finishLocalUnlock(token)
        assertNull(store.onForeground())
        assertFalse(store.state.value.readyForActions)
        assertNull(store.state.value.localPasswordProof)
        val old = store.beginLocalUnlock("a", revision)!!
        store.onHostPause()
        store.signOut().join()
        store.finishLocalUnlock(old)
        assertNull(store.beginLocalUnlock("a", revision))
        assertEquals(AuthStage.GUEST, store.state.value.stage)
    }
}
