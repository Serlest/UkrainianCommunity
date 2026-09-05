package at.uac.android

import android.graphics.Bitmap
import android.graphics.Color
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.core.*
import at.uac.android.feature.accountdeletion.*
import at.uac.android.feature.auth.*
import com.google.firebase.storage.StorageException
import com.google.firebase.storage.StorageMetadata
import java.io.ByteArrayOutputStream
import java.io.File
import java.time.Duration
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.*
import kotlinx.coroutines.tasks.await
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AccountDeletionDeviceTest {
    private val fixture
        get() = AccountDeletionFixtures

    private val context
        get() = fixture.context

    private suspend fun restore(scope: CoroutineScope, journal: AccountDeletionJournal): AuthStore {
        val store =
            AuthStore(
                FirebaseAuthBackend(LocalFirebase.auth(context)),
                FirestoreAuthProfiles(LocalFirebase.firestore(context)),
                scope,
                deletionJournal = journal,
            )
        withContext(Dispatchers.Main) { store.restore() }.join()
        return store
    }

    private fun repository(store: AuthStore, journal: AccountDeletionJournal) =
        AccountDeletionRepository(
            localAccountDeletionSource(context),
            journal,
            { store.state.value.accountDeletionScope() },
            AuthAccountDeletionGate(store),
        )

    private suspend fun expect(reason: AccountDeletionFailure, action: suspend () -> Any?) {
        try {
            action()
            fail("Expected $reason")
        } catch (error: AccountDeletionException) {
            if (error.failure != reason) {
                val causes =
                    generateSequence<Throwable>(error) { it.cause }
                        .take(6)
                        .joinToString(" -> ") {
                            val code =
                                when (it) {
                                    is LocalCallableException -> it.code.name
                                    is com.google.firebase.auth.FirebaseAuthException ->
                                        it.errorCode
                                    is com.google.firebase.firestore.FirebaseFirestoreException ->
                                        it.code.name
                                    is AccountDeletionException -> it.failure.name
                                    else -> "none"
                                }
                            "${it.javaClass.simpleName}[$code]@${it.stackTrace.firstOrNull()?.let { frame -> "${frame.className}.${frame.methodName}:${frame.lineNumber}" }}"
                        }
                throw AssertionError(
                    "Expected $reason, actual ${error.failure}; safe classes/codes only: $causes"
                )
            }
        }
    }

    @Test
    fun actualCallableDeletesPrivateDataAnonymizesReferencesAndRemovesAuthLastOrLocalGuard() =
        runBlocking {
            fixture.requireLocalAvd()
            if (!fixture.online()) {
                assertEquals(
                    300_000L,
                    LocalCallableProtocol.maximumTimeoutMillis("deleteOwnAccount"),
                )
                return@runBlocking
            }
            AuthEmulatorFixtures.seedLegalReference()
            val user = fixture.create("deletion-cascade")
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
            val journal = LocalAccountDeletionJournal.get(context)
            val suffix = UUID.randomUUID().toString()
            val news = "news/deletion-news-$suffix"
            val comment = "$news/comments/deletion-comment-$suffix"
            val legal = "legalAcceptanceLogs/deletion-legal-$suffix"
            val ordinaryFeedback = "feedback/deletion-private-$suffix"
            val dsaFeedback = "feedback/deletion-retained-$suffix"
            val privatePaths =
                listOf(
                    "users/${user.uid}/bookmarks/deletion-$suffix",
                    "likes/deletion-$suffix",
                    "registrations/deletion-$suffix",
                    ordinaryFeedback,
                    "$ordinaryFeedback/messages/deletion-$suffix",
                )
            val retained = listOf(news, comment, legal, dsaFeedback)
            val avatar =
                LocalStorage.instance(context)
                    .reference
                    .child("profileImages/${user.uid}/avatar.jpg")
            try {
                for (path in privatePaths) fixture.patch(
                    path,
                    mapOf("userId" to user.uid, "title" to "Synthetic private record"),
                )
                fixture.patch(
                    news,
                    mapOf(
                        "authorId" to user.uid,
                        "authorName" to "Synthetic deletion account",
                        "title" to "Synthetic public content",
                    ),
                )
                fixture.patch(
                    comment,
                    mapOf(
                        "authorId" to user.uid,
                        "authorName" to "Synthetic deletion account",
                        "text" to "Synthetic public comment",
                    ),
                )
                fixture.patch(
                    legal,
                    mapOf(
                        "userId" to user.uid,
                        "documentType" to "terms",
                        "version" to "synthetic",
                        "email" to user.email,
                    ),
                )
                fixture.patch(
                    dsaFeedback,
                    mapOf(
                        "userId" to user.uid,
                        "userDisplayName" to "Synthetic deletion account",
                        "dsaCase" to true,
                    ),
                )
                fixture.patch(
                    "publicProfiles/${user.uid}",
                    mapOf("uid" to user.uid, "displayName" to "Synthetic deletion account"),
                )
                val bitmap = Bitmap.createBitmap(24, 24, Bitmap.Config.ARGB_8888)
                val bytes =
                    try {
                        bitmap.eraseColor(Color.BLUE)
                        ByteArrayOutputStream().use {
                            bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it)
                            it.toByteArray()
                        }
                    } finally {
                        bitmap.recycle()
                    }
                avatar
                    .putBytes(bytes, StorageMetadata.Builder().setContentType("image/jpeg").build())
                    .await()
                assertArrayEquals(bytes, avatar.getBytes(1_000_000).await())
                val store = restore(scope, journal)
                val session = store.state.value.accountDeletionScope()!!
                val result =
                    repository(store, journal)
                        .begin(fixture.PASSWORD, AccountDeletionAttempt(), {}, {})
                        as AccountDeletionStep.Completed
                assertEquals(
                    AccountDeletionConfirmation.SERVER_RECEIPT,
                    result.receipt.confirmation,
                )
                assertTrue(result.receipt.journalCleared)
                assertNull(journal.pending(user.uid))
                // Real profile watch may have seen deactivated/root missing: it must retain
                // deletion identity until receipt.
                assertEquals(session, store.state.value.accountDeletionScope())
                for (path in
                    privatePaths +
                        listOf("users/${user.uid}", "publicProfiles/${user.uid}")) assertNull(
                    path,
                    fixture.document(path),
                )
                assertEquals("deleted", fixture.field(fixture.document(news)!!, "authorId"))
                assertEquals("deleted", fixture.field(fixture.document(comment)!!, "authorId"))
                assertEquals("deleted", fixture.field(fixture.document(legal)!!, "userId"))
                assertEquals("deleted", fixture.field(fixture.document(dsaFeedback)!!, "userId"))
                try {
                    avatar.metadata.await()
                    fail("Canonical avatar must be gone")
                } catch (error: StorageException) {
                    assertEquals(StorageException.ERROR_OBJECT_NOT_FOUND, error.errorCode)
                }
                fixture.assertAuthAbsent(user)
                withContext(Dispatchers.Main) {
                        store.signOutDeletedIdentity(session.uid, session.revision)!!
                    }
                    .join()
                assertEquals(AuthStage.GUEST, store.state.value.stage)
            } finally {
                scope.cancel()
                fixture.clean(user, privatePaths + retained)
            }
        }

    @Test
    fun unverifiedAndDeactivatedAccountsCanDeleteWithoutObtainingNormalActionGateOrLocalGuard() =
        runBlocking {
            fixture.requireLocalAvd()
            if (!fixture.online()) {
                assertNull(AuthSession(AuthStage.GUEST).accountDeletionScope())
                return@runBlocking
            }
            for (verified in listOf(false, true)) {
                val user =
                    fixture.create(
                        if (verified) "deletion-deactivated" else "deletion-unverified",
                        verified,
                    )
                val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
                val journal = LocalAccountDeletionJournal.get(context)
                try {
                    if (verified)
                        fixture.patch(
                            "users/${user.uid}",
                            mapOf(
                                "accountStatus" to "deactivated",
                                "blockState" to "deactivated",
                                "isBlocked" to true,
                            ),
                            true,
                        )
                    val store = restore(scope, journal)
                    assertFalse(store.state.value.readyForActions)
                    assertNotNull(store.state.value.accountDeletionScope())
                    val actual = localAccountDeletionSource(context)
                    var authenticatedAt: Instant? = null
                    var proofAgeAtReturnMs: Long? = null
                    var reauthenticationElapsedMs: Long? = null
                    val observed =
                        object : AccountDeletionSource by actual {
                            override suspend fun reauthenticate(
                                uid: String,
                                password: String,
                            ): AccountDeletionProof {
                                val started = android.os.SystemClock.elapsedRealtime()
                                return actual.reauthenticate(uid, password).also { proof ->
                                    authenticatedAt = proof.authenticatedAt
                                    proofAgeAtReturnMs =
                                        Duration.between(proof.authenticatedAt, Instant.now())
                                            .toMillis()
                                    reauthenticationElapsedMs =
                                        android.os.SystemClock.elapsedRealtime() - started
                                }
                            }
                        }
                    val repository =
                        AccountDeletionRepository(
                            observed,
                            journal,
                            { store.state.value.accountDeletionScope() },
                            AuthAccountDeletionGate(store),
                        )
                    try {
                        assertTrue(
                            repository.begin(fixture.PASSWORD, AccountDeletionAttempt(), {}, {})
                                is AccountDeletionStep.Completed
                        )
                    } catch (error: AccountDeletionException) {
                        // Diagnostics only: use the real proof/clock and never print an identity,
                        // claim, password or token.
                        val failureAgeMs = authenticatedAt?.let {
                            Duration.between(it, Instant.now()).toMillis()
                        }
                        throw AssertionError(
                            "Restricted deletion: verified=$verified, failure=${error.failure}, " +
                                "proofAgeAtReturnMs=$proofAgeAtReturnMs, proofAgeAtFailureMs=$failureAgeMs, " +
                                "reauthenticationElapsedMs=$reauthenticationElapsedMs",
                            error,
                        )
                    }
                    fixture.assertAuthAbsent(user)
                    assertNull(fixture.document("users/${user.uid}"))
                    assertNull(journal.pending(user.uid))
                } finally {
                    scope.cancel()
                    fixture.clean(user)
                }
            }
        }

    @Test
    fun ownerWrongPasswordAndRequiredTotpFailWithoutDeletingOrJournalOrLocalGuard() = runBlocking {
        fixture.requireLocalAvd()
        if (!fixture.online()) {
            assertFalse(
                AccountDeletionProof("synthetic", Instant.EPOCH, false).recent(Instant.now())
            )
            return@runBlocking
        }
        val user = fixture.create("deletion-denied")
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        val journal = LocalAccountDeletionJournal.get(context)
        val org = "organizations/deletion-owned-${UUID.randomUUID()}"
        try {
            val store = restore(scope, journal)
            val repository = repository(store, journal)
            expect(AccountDeletionFailure.INVALID_CREDENTIALS) {
                repository.begin("Not-the-password", AccountDeletionAttempt(), {}, {})
            }
            assertNull(journal.pending(user.uid))
            assertNotNull(fixture.document("users/${user.uid}"))
            fixture.patch(
                "users/${user.uid}",
                mapOf("globalRole" to "owner", "requiresMultiFactorAuth" to false),
                true,
            )
            expect(AccountDeletionFailure.PLATFORM_OWNER) {
                repository.begin(fixture.PASSWORD, AccountDeletionAttempt(), {}, {})
            }
            fixture.patch(
                "users/${user.uid}",
                mapOf("globalRole" to "admin", "requiresMultiFactorAuth" to true),
                true,
            )
            expect(AccountDeletionFailure.MFA_REQUIRED) {
                repository.begin(fixture.PASSWORD, AccountDeletionAttempt(), {}, {})
            }
            fixture.patch(
                "users/${user.uid}",
                mapOf("globalRole" to "user", "requiresMultiFactorAuth" to false),
                true,
            )
            fixture.patch(
                org,
                mapOf(
                    "ownerId" to user.uid,
                    "state" to "draft",
                    "name" to "Synthetic owned organization",
                ),
            )
            expect(AccountDeletionFailure.ORGANIZATION_OWNER) {
                repository.begin(fixture.PASSWORD, AccountDeletionAttempt(), {}, {})
            }
            // Bypass only the optional CLIENT preflight in this test: unchanged server must
            // independently reject ownership.
            val source = localAccountDeletionSource(context)
            val session = store.state.value.accountDeletionScope()!!
            expect(AccountDeletionFailure.PRECONDITION) {
                AuthAccountDeletionGate(store).withSession(session) {
                    source.reauthenticate(user.uid, fixture.PASSWORD)
                    source.delete(user.uid)
                }
            }
            assertNull(journal.pending(user.uid))
            assertNotNull(fixture.document(org))
            assertEquals(
                "user",
                fixture.field(fixture.document("users/${user.uid}")!!, "globalRole"),
            )
            assertNull(fixture.field(fixture.document("users/${user.uid}")!!, "deletionState"))
            user.captured.reload().await()
        } finally {
            scope.cancel()
            fixture.clean(user, listOf(org))
        }
    }

    @Test
    fun atomicFileJournalSurvivesReconstructionAndRejectsCorruptionForeignHashAndStaleClear() =
        runBlocking {
            fixture.requireLocalAvd()
            val directory =
                File(context.noBackupFilesDir, "deletion-journal-test-${UUID.randomUUID()}")
            assertTrue(directory.mkdir())
            val uid = "synthetic-journal-${UUID.randomUUID()}"
            val time = Instant.now()
            try {
                val first = FileAccountDeletionJournal(directory)
                val entry = first.record(uid, time)
                val cold = FileAccountDeletionJournal(directory)
                assertEquals(entry, cold.pending(uid))
                assertNull(cold.pending("foreign-synthetic"))
                val file = directory.listFiles()!!.single()
                assertEquals("${DeletionJournalCodec.accountHash(uid)}.bin", file.name)
                assertFalse(file.readBytes().toString(Charsets.ISO_8859_1).contains(uid))
                assertEquals(
                    DeletionJournalStatus.PARTIAL,
                    cold.markPartial(uid, entry.submittedAt)?.status,
                )
                assertFalse(cold.clearConfirmed(uid, entry.submittedAt.minusMillis(1)))
                file.writeBytes(
                    DeletionJournalCodec.encode(
                        entry.copy(
                            accountHash = DeletionJournalCodec.accountHash("foreign-synthetic")
                        )
                    )
                )
                assertTrue(runCatching { cold.pending(uid) }.isFailure)
                file.writeBytes(byteArrayOf(1, 2, 3))
                assertTrue(
                    runCatching { FileAccountDeletionJournal(directory).pending(uid) }.isFailure
                )
                val replacement = first.record(uid, time.plusSeconds(1))
                assertTrue(cold.clearConfirmed(uid, replacement.submittedAt))
                assertNull(cold.pending(uid))
            } finally {
                // Exact newly created synthetic directory only; no app/account journal directory is
                // recursively cleared.
                directory.listFiles().orEmpty().forEach { assertTrue(it.delete()) }
                assertTrue(directory.delete())
            }
        }
}
