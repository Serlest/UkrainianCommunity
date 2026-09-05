package at.uac.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.accountstatus.*
import at.uac.android.feature.auth.*
import com.google.firebase.Timestamp
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.Source
import java.io.IOException
import java.time.Instant
import kotlinx.coroutines.*
import kotlinx.coroutines.tasks.await
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Real named Auth, Firestore transactions and unchanged Rules. No privileged/TOTP positive claims.
 */
@RunWith(AndroidJUnit4::class)
class AccountStatusDeviceTest {
    private fun requireOnline() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("expectEmulator") == "true")
        AccountDeletionFixtures.requireLocalAvd()
    }

    private suspend fun own(user: AccountStatusFixtures.User): Map<String, Any> {
        val snapshot =
            LocalFirebase.firestore(AccountDeletionFixtures.context)
                .document("users/${user.uid}")
                .get(Source.SERVER)
                .await()
        assertTrue(snapshot.exists())
        assertFalse(snapshot.metadata.isFromCache)
        assertFalse(snapshot.metadata.hasPendingWrites())
        return requireNotNull(snapshot.data)
    }

    private fun changed(before: Map<String, Any>, after: Map<String, Any>) =
        (before.keys + after.keys).filter { before[it] != after[it] }.toSet()

    private suspend fun capture(account: AuthStore): AccountStatusSession {
        withContext(Dispatchers.Main) { account.refresh() }.join()
        return requireNotNull(account.state.value.accountStatusScope())
    }

    private suspend fun failure(expected: AccountStatusFailure, action: suspend () -> Unit) {
        try {
            action()
            fail("Expected account-status failure $expected")
        } catch (error: AccountStatusException) {
            assertEquals(expected, error.failure)
        }
    }

    private suspend fun denied(action: suspend () -> Unit) {
        try {
            action()
            fail("Rules must deny this status update")
        } catch (error: FirebaseFirestoreException) {
            assertEquals(FirebaseFirestoreException.Code.PERMISSION_DENIED, error.code)
        }
    }

    @Test
    fun warningRestorationAndLostReceiptUseExactOneFieldAndReadOnlyReconciliation() = runBlocking {
        requireOnline()
        val fixture = AccountStatusFixtures("status-device")
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        var phase = "create own verified fixture"
        var primary: Throwable? = null
        try {
            val user = fixture.create()
            val auth = LocalFirebase.auth(fixture.context)
            val db = LocalFirebase.firestore(fixture.context)
            val account = AuthStore(FirebaseAuthBackend(auth), FirestoreAuthProfiles(db), scope)
            val source = localAccountStatusSource(fixture.context)
            val gate = AuthAccountStatusGate(account)
            val repository = AccountStatusRepository(source, gate, gate)
            fixture.status(
                user,
                "warned",
                reason = "Synthetic raw reason ",
                message = "Synthetic separate message",
            )
            var session = capture(account)
            assertTrue(session.canAcknowledge)
            assertEquals("user", session.role)
            var expected = requireNotNull(session.observation.notice)
            assertEquals("Synthetic raw reason ", expected.reason)
            phase = "warning exact transaction and one-field SERVER read-back"
            var before = own(user)
            val acknowledged = repository.acknowledge(session, expected) { true }
            var after = own(user)
            assertTrue(acknowledged.confirms(expected))
            assertEquals(setOf("statusAcknowledgedAt"), changed(before, after))
            assertTrue(
                (after["statusAcknowledgedAt"] as Timestamp).let {
                    Instant.ofEpochSecond(it.seconds, it.nanoseconds.toLong()) >= expected.updatedAt
                }
            )
            assertNull(source.read(session).notice)
            val duplicateBefore = after
            // Exact already-confirmed receipt is a no-op, not a second timestamp write.
            repository.acknowledge(session, expected) { true }
            assertEquals(duplicateBefore, own(user))

            phase = "restored-active notice remains distinct and exact"
            fixture.status(user, "active", reason = null, message = "Synthetic restoration")
            session = capture(account)
            expected = requireNotNull(session.observation.notice)
            assertEquals(AccountStatusKind.RESTORED, expected.kind)
            before = own(user)
            repository.acknowledge(session, expected) { true }
            after = own(user)
            assertEquals(setOf("statusAcknowledgedAt"), changed(before, after))

            phase = "lost response after real committed SDK transaction"
            fixture.status(
                user,
                "warned",
                reason = "Synthetic lost receipt",
                message = "Do not resend",
            )
            session = capture(account)
            expected = requireNotNull(session.observation.notice)
            var sends = 0
            val lost =
                object : AccountStatusSource by source {
                    override suspend fun acknowledge(
                        session: AccountStatusSession,
                        expected: AccountStatusVersion,
                        canDispatch: () -> Boolean,
                        onDispatch: () -> Unit,
                    ) {
                        sends++
                        source.acknowledge(session, expected, canDispatch, onDispatch)
                        throw IOException("Synthetic lost status receipt")
                    }
                }
            failure(AccountStatusFailure.UNCONFIRMED) {
                AccountStatusRepository(lost, gate, gate).acknowledge(session, expected) { true }
            }
            assertEquals(1, sends)
            val committed = own(user)
            val readOnly =
                object : AccountStatusSource by source {
                    override suspend fun acknowledge(
                        session: AccountStatusSession,
                        expected: AccountStatusVersion,
                        canDispatch: () -> Boolean,
                        onDispatch: () -> Unit,
                    ): Unit = error("Read-only status reconciliation must never send")
                }
            phase = "new read-only repository reconciles the original exact version"
            session = capture(account)
            assertEquals(
                AccountStatusReconciliation.CONFIRMED,
                AccountStatusRepository(readOnly, gate, gate).reconcile(session, expected),
            )
            assertEquals(committed, own(user))
            assertEquals(1, sends)
            println(
                "ACCOUNT_STATUS_SDK_CONFIRMED ackOnlyField=true duplicateNoWrite=true lostReceiptReadOnly=true privilegedPositive=false"
            )
        } catch (error: Throwable) {
            val reported = AssertionError("Account-status SDK phase=$phase", error)
            primary = reported
            throw reported
        } finally {
            scope.cancel()
            fixture.cleanup(primary)
        }
    }

    @Test
    fun changedVersionLegacyIdForeignRestrictedAndUnverifiedCannotAcknowledge() = runBlocking {
        requireOnline()
        val fixture = AccountStatusFixtures("status-negative")
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        var phase = "create exact owned actors"
        var primary: Throwable? = null
        try {
            val foreign = fixture.create()
            fixture.status(foreign, "warned", reason = "Synthetic foreign status")
            val user = fixture.create()
            fixture.status(
                user,
                "warned",
                reason = "Synthetic displayed status",
                message = "Version one",
            )
            val auth = LocalFirebase.auth(fixture.context)
            val db = LocalFirebase.firestore(fixture.context)
            val backend = FirebaseAuthBackend(auth)
            val account = AuthStore(backend, FirestoreAuthProfiles(db), scope)
            val source = localAccountStatusSource(fixture.context)
            val gate = AuthAccountStatusGate(account)
            val repository = AccountStatusRepository(source, gate, gate)
            var session = capture(account)
            val shown = requireNotNull(session.observation.notice)

            phase = "same timestamp but changed full raw message cannot acknowledge unseen version"
            fixture.patch(
                user,
                mapOf("statusMessage" to "Version two changed by synthetic moderator"),
            )
            session = capture(account)
            val staleDisplay = session.copy(observation = AccountStatusObservation(shown, null))
            val beforeChanged = own(user)
            failure(AccountStatusFailure.STALE) {
                repository.acknowledge(staleDisplay, shown) { true }
            }
            assertEquals(beforeChanged, own(user))
            assertEquals(AccountStatusReconciliation.CHANGED, repository.reconcile(session, shown))
            assertNotNull(source.read(session).notice)

            phase = "fresh privacy predicate closed before SDK means no acknowledgement"
            val current = requireNotNull(session.observation.notice)
            failure(AccountStatusFailure.STALE) {
                repository.acknowledge(session, current) { false }
            }
            assertEquals(beforeChanged, own(user))

            phase = "Rules deny extra status field, backdated timestamp and foreign profile"
            val ownReference = db.document("users/${user.uid}")
            denied {
                ownReference
                    .update(
                        mapOf(
                            "statusAcknowledgedAt" to FieldValue.serverTimestamp(),
                            "statusReason" to "forged",
                        )
                    )
                    .await()
            }
            denied { ownReference.update("statusAcknowledgedAt", Timestamp(0, 0)).await() }
            val foreignBefore = fixture.fingerprint(foreign)
            denied {
                db.document("users/${foreign.uid}")
                    .update("statusAcknowledgedAt", FieldValue.serverTimestamp())
                    .await()
            }
            assertEquals(
                foreignBefore,
                fixture.fingerprint(foreign),
            )
            assertEquals(beforeChanged, own(user))

            phase = "legacy missing duplicated id is not silently repaired by acknowledgement"
            fixture.patch(user, mapOf("id" to null))
            session = capture(account)
            val legacyBefore = own(user)
            failure(AccountStatusFailure.INVALID) {
                repository.acknowledge(session, requireNotNull(session.observation.notice)) { true }
            }
            assertEquals(legacyBefore, own(user))
            fixture.patch(user, mapOf("id" to user.uid))

            phase = "restricted user can read notice but both app and Rules deny acknowledgement"
            fixture.status(
                user,
                "suspendedUntil",
                block = "blocked",
                reason = "Synthetic restriction",
                expiresAt = Instant.now().plusSeconds(3600),
            )
            session = capture(account)
            assertFalse(session.canAcknowledge)
            val restriction = requireNotNull(session.observation.notice)
            assertTrue(restriction.requiresSignOut)
            assertEquals(
                AccountStatusReconciliation.NOT_CONFIRMED,
                repository.reconcile(session, restriction),
            )
            failure(AccountStatusFailure.DENIED) {
                repository.acknowledge(session, restriction) { true }
            }
            val restrictedBefore = own(user)
            denied {
                ownReference.update("statusAcknowledgedAt", FieldValue.serverTimestamp()).await()
            }
            assertEquals(restrictedBefore, own(user))

            phase = "unverified account has read-only notice and no direct acknowledgement"
            withContext(Dispatchers.Main) { account.signOut() }.join()
            val unverified = fixture.create(verified = false)
            fixture.status(unverified, "warned", reason = "Synthetic unverified status")
            withContext(Dispatchers.Main) { account.refresh() }.join()
            val verification = account.state.value
            assertEquals(AuthStage.VERIFICATION_PENDING, verification.stage)
            val unverifiedIdentity = requireNotNull(verification.identity)
            assertEquals(unverified.uid, unverifiedIdentity.uid)
            assertFalse(unverifiedIdentity.emailVerified)
            // Production Auth deliberately stops before fetching the profile until email
            // verification. Do not invent a ready UI scope merely to exercise a negative test.
            assertNull(verification.profile)
            assertNull(verification.accountStatusScope())
            var entered = false
            try {
                account.withStatusAcknowledgementSession(unverified.uid, verification.revision) {
                    entered = true
                }
                fail("Actual unverified status-acknowledgement gate must deny")
            } catch (error: AuthException) {
                assertEquals(AuthProblem.PERMISSION_DENIED, error.problem)
            }
            assertFalse(entered)
            // Negative-test/read-only projection, not a product profile or a ready session.
            val readOnly =
                AccountStatusSession(
                    unverified.uid,
                    verification.revision,
                    AccountStatusObservation(null, null),
                    canAcknowledge = false,
                    verified = false,
                )
            val observed = gate.withReadSession(readOnly) { source.read(readOnly) }
            assertEquals(AccountStatusKind.WARNED, observed.notice?.kind)
            session = readOnly.copy(observation = observed)
            assertFalse(session.verified)
            assertFalse(session.canAcknowledge)
            val unverifiedBefore = own(unverified)
            failure(AccountStatusFailure.DENIED) {
                repository.acknowledge(session, requireNotNull(session.observation.notice)) { true }
            }
            denied {
                db.document("users/${unverified.uid}")
                    .update("statusAcknowledgedAt", FieldValue.serverTimestamp())
                    .await()
            }
            assertEquals(unverifiedBefore, own(unverified))
            println(
                "ACCOUNT_STATUS_SDK_NEGATIVES_CONFIRMED staleVersion=true privacy=true foreign=true extraField=true legacyNoRepair=true restricted=true unverified=true"
            )
        } catch (error: Throwable) {
            val reported = AssertionError("Account-status negative SDK phase=$phase", error)
            primary = reported
            throw reported
        } finally {
            scope.cancel()
            fixture.cleanup(primary)
        }
    }
}
