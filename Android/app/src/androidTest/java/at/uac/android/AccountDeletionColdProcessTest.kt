package at.uac.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.*
import at.uac.android.feature.accountdeletion.*
import at.uac.android.feature.auth.*
import java.io.File
import java.time.Instant
import kotlinx.coroutines.*
import kotlinx.coroutines.tasks.await
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Run the two explicitly selected phases in separate app processes. Marker contains only the
 * journal's hash/time/status.
 */
@RunWith(AndroidJUnit4::class)
class AccountDeletionColdProcessTest {
    private val fixture
        get() = AccountDeletionFixtures

    private val marker
        get() = File(fixture.context.noBackupFilesDir, "synthetic-u06-cold-proof.bin")

    private fun phase(value: String) =
        InstrumentationRegistry.getArguments().getString("deletionColdPhase") == value

    @Test
    fun prepareFreshReauthenticatedPartialCheckpointOnlyWhenExplicitlyRequested() = runBlocking {
        fixture.requireLocalAvd()
        if (!fixture.online() || !phase("prepare")) return@runBlocking
        check(!marker.exists()) {
            "A prior synthetic cold checkpoint must be reconciled before preparing another"
        }
        val user = fixture.create("deletion-cold")
        val auth = LocalFirebase.auth(fixture.context)
        val journal = LocalAccountDeletionJournal.get(fixture.context)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        try {
            val store =
                AuthStore(
                    FirebaseAuthBackend(auth),
                    FirestoreAuthProfiles(LocalFirebase.firestore(fixture.context)),
                    scope,
                    deletionJournal = journal,
                )
            withContext(Dispatchers.Main) { store.restore() }.join()
            val session = store.state.value.accountDeletionScope()!!
            AuthAccountDeletionGate(store).withSession(session) {
                val proof =
                    localAccountDeletionSource(fixture.context)
                        .reauthenticate(user.uid, fixture.PASSWORD)
                assertTrue(proof.recent(Instant.now()))
                val entry = journal.record(user.uid, Instant.now())
                // Explicit synthetic fault fixture: emulate process death after a server cascade
                // removed the private root.
                fixture.remove("users/${user.uid}")
                val partial = journal.markPartial(user.uid, entry.submittedAt)!!
                marker.writeBytes(DeletionJournalCodec.encode(partial))
                assertEquals(
                    partial,
                    DeletionJournalCodec.decode(
                        marker.readBytes(),
                        DeletionJournalCodec.accountHash(user.uid),
                    ),
                )
            }
            assertEquals(user.uid, auth.currentUser?.uid)
            assertNotNull(journal.pending(user.uid))
        } finally {
            scope.cancel()
        } // Deliberately preserve this one synthetic identity for the separate restore process.
    }

    @Test
    fun restoreMissingPrivateProfileAsDeletionOnlyWithoutPublishingReadyThenReadActualStatus() =
        runBlocking {
            fixture.requireLocalAvd()
            if (!fixture.online() || !phase("restore")) return@runBlocking
            check(marker.isFile) { "Explicit synthetic prepare phase is required" }
            val auth = LocalFirebase.auth(fixture.context)
            val current =
                auth.currentUser
                    ?: error("Firebase Auth must restore its persisted synthetic identity")
            check(
                current.email?.startsWith("deletion-cold-") == true &&
                    current.email!!.endsWith("@example.invalid")
            )
            val user = AccountDeletionFixtures.User(current.uid, current.email!!, current)
            val expected =
                DeletionJournalCodec.decode(
                    marker.readBytes(),
                    DeletionJournalCodec.accountHash(user.uid),
                )
            val journal = LocalAccountDeletionJournal.get(fixture.context)
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
            try {
                assertEquals(expected, journal.pending(user.uid))
                val store =
                    AuthStore(
                        FirebaseAuthBackend(auth),
                        FirestoreAuthProfiles(LocalFirebase.firestore(fixture.context)),
                        scope,
                        deletionJournal = journal,
                    )
                withContext(Dispatchers.Main) { store.restore() }.join()
                assertEquals(AuthStage.SESSION_UNAVAILABLE, store.state.value.stage)
                assertEquals(AuthGate.RESTRICTED, store.state.value.gate)
                assertTrue(store.state.value.deletionRecovery)
                assertFalse(store.state.value.readyForActions)
                assertNull(store.state.value.profile)
                assertNull(store.state.value.localPasswordProof)
                assertEquals(user.uid, store.state.value.accountDeletionScope()?.uid)
                val repository =
                    AccountDeletionRepository(
                        localAccountDeletionSource(fixture.context),
                        journal,
                        { store.state.value.accountDeletionScope() },
                        AuthAccountDeletionGate(store),
                    )
                val result = repository.reconcile()
                assertEquals(AccountDeletionIdentityStatus.PARTIAL, result.first)
                assertNull(result.second)
                assertNotNull(journal.pending(user.uid))
                assertNull(fixture.document("users/${user.uid}"))
                assertEquals(user.uid, auth.currentUser?.uid)
                // Cleanup is explicitly outside app behavior: only our synthetic Auth fixture is
                // removed.
                localAccountDeletionSource(fixture.context)
                    .reauthenticate(user.uid, fixture.PASSWORD)
                current.delete().await()
                fixture.assertAuthAbsent(user)
                assertTrue(journal.clearConfirmed(user.uid, expected.submittedAt))
                assertTrue(marker.delete())
            } finally {
                scope.cancel()
                fixture.clean(user)
            }
        }
}
