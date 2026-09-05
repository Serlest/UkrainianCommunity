package at.uac.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.AuthRegistration
import at.uac.android.feature.auth.registeredProfileFields
import at.uac.android.feature.moderation.*
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseUser
import com.google.firebase.firestore.FieldValue
import java.io.File
import java.io.SyncFailedException
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

internal object ModerationDecisionAndroidFixture {
    val actor = ModerationSession("synthetic-native-moderation-reviewer", 1, "admin", true)
    private val time = Instant.parse("2026-09-03T10:00:00Z")
    val target = ModerationTarget(ModerationKind.NEWS, "synthetic-native-moderation-target")

    fun fields(): Map<String, Any?> =
        mapOf(
            "id" to target.id,
            "organizationId" to "synthetic-native-org",
            "sourceType" to "organization",
            "moderationStatus" to "pendingReview",
            "updatedAt" to time,
            "createdAt" to time,
            "title" to "Synthetic private preview",
            "summary" to "Synthetic summary",
            "body" to "PRIVATE-BODY-NEVER-ON-DISK",
        )

    fun version() = ModerationReviewVersion.from(target, fields())

    fun pending(
        phase: ModerationDecisionPhase = ModerationDecisionPhase.PREPARED,
        uid: String = actor.uid,
    ) =
        ModerationPending(
            ModerationDecisionContract.accountHash(uid),
            version(),
            UUID.randomUUID().toString(),
            "admin",
            ModerationDecision.APPROVE,
            time,
            phase,
        )
}

/** Native local disk fault checks and actual SDK negative gates. No fabricated TOTP positive. */
@RunWith(AndroidJUnit4::class)
class ModerationDecisionDeviceTest {
    private val uid = ModerationDecisionAndroidFixture.actor.uid

    private class Fixture {
        private val context = AccountDeletionFixtures.context
        private val token = UUID.randomUUID().toString()
        val directory =
            File(context.noBackupFilesDir, "moderation-journal-test-$token").canonicalFile
        val base
            get() = File(directory, "pending.bin")

        init {
            AccountDeletionFixtures.requireLocalAvd()
            check(!directory.exists() && directory.mkdirs())
        }

        fun store(failSync: Boolean = false) =
            FileModerationDecisionJournal(
                directory,
                sync = {
                    if (failSync) throw SyncFailedException("Synthetic moderation fd.sync failure")
                    else it.fd.sync()
                },
            )

        fun cleanup() {
            AccountDeletionFixtures.requireLocalAvd()
            check(
                directory.name == "moderation-journal-test-$token" &&
                    directory.parentFile?.canonicalFile == context.noBackupFilesDir.canonicalFile
            )
            directory.listFiles().orEmpty().forEach { file ->
                check(
                    file.name in setOf("pending.bin", "pending.bin.new", "pending.bin.bak") &&
                        file.isFile &&
                        file.canonicalFile == file.absoluteFile
                )
                check(file.delete() && !file.exists())
            }
            check(directory.delete() && !directory.exists())
        }
    }

    private suspend fun fixture(action: suspend (Fixture) -> Unit) {
        val fixture = Fixture()
        var primary: Throwable? = null
        try {
            action(fixture)
        } catch (error: Throwable) {
            primary = error
            throw error
        } finally {
            try {
                fixture.cleanup()
            } catch (error: Throwable) {
                if (primary == null) throw error else primary.addSuppressed(error)
            }
        }
    }

    private suspend fun journalFailure(action: suspend () -> Any?) {
        try {
            action()
            fail("Expected journal rejection")
        } catch (error: ModerationDecisionException) {
            assertEquals(ModerationDecisionFailure.JOURNAL, error.failure)
        }
    }

    private suspend fun accessFailure(failure: ModerationFailure, action: suspend () -> Any?) {
        try {
            action()
            fail("Expected actual SDK authorization rejection")
        } catch (error: ModerationException) {
            assertEquals(failure, error.failure)
        }
    }

    @Test
    fun nativeDurablePhasesNewInstanceIdentityIsolationAndExactClear() = runBlocking {
        fixture { f ->
            val prepared = ModerationDecisionAndroidFixture.pending()
            f.store().put(uid, prepared)
            val dispatched = prepared.copy(phase = ModerationDecisionPhase.DISPATCHED)
            f.store().put(uid, dispatched, prepared)
            val acknowledged = dispatched.copy(phase = ModerationDecisionPhase.ACKNOWLEDGED)
            f.store().put(uid, acknowledged, dispatched)
            assertEquals(listOf(acknowledged), f.store().pending(uid))
            assertTrue(f.store().pending("synthetic-other-owner").isEmpty())
            val raw = f.base.readBytes()
            assertFalse(raw.toString(Charsets.ISO_8859_1).contains(uid))
            assertFalse(raw.toString(Charsets.ISO_8859_1).contains("PRIVATE-BODY-NEVER-ON-DISK"))
            journalFailure { f.store().put(uid, dispatched, acknowledged) }
            journalFailure { f.store().clear(uid, prepared) }
            assertArrayEquals(raw, f.base.readBytes())
            f.store().clear(uid, acknowledged)
            assertTrue(f.store().pending(uid).isEmpty())
        }
    }

    @Test
    fun nativeSyncFailureNeverAcknowledgesFirstWriteOrReplacesCommittedPhase() = runBlocking {
        fixture { f ->
            journalFailure { f.store(true).put(uid, ModerationDecisionAndroidFixture.pending()) }
            assertTrue(f.store().pending(uid).isEmpty())
        }
        fixture { f ->
            val prepared = ModerationDecisionAndroidFixture.pending()
            f.store().put(uid, prepared)
            val raw = f.base.readBytes()
            journalFailure {
                f.store(true)
                    .put(uid, prepared.copy(phase = ModerationDecisionPhase.DISPATCHED), prepared)
            }
            assertArrayEquals(raw, f.base.readBytes())
            assertEquals(listOf(prepared), f.store().pending(uid))
        }
    }

    @Test
    fun nativeCorruptOrOversizedJournalIsNotEmptyAndCannotBeOverwritten() = runBlocking {
        for (bytes in
            listOf(
                byteArrayOf(1, 2, 3),
                ByteArray(ModerationDecisionJournalCodec.MAX_BYTES + 1),
            )) fixture { f ->
            f.base.writeBytes(bytes)
            journalFailure { f.store().pending(uid) }
            journalFailure { f.store().put(uid, ModerationDecisionAndroidFixture.pending()) }
            assertArrayEquals(bytes, f.base.readBytes())
        }
    }

    @Test
    fun nativeInterruptedFirstWriteRemainsFailClosedWithoutInitialisingFirebase() = runBlocking {
        val before = FirebaseApp.getApps(AccountDeletionFixtures.context).map { it.name }.toSet()
        fixture { f ->
            val interrupted = File(f.base.path + ".new")
            val raw = byteArrayOf(1, 2, 3)
            interrupted.writeBytes(raw)
            journalFailure { f.store().pending(uid) }
            journalFailure { f.store().put(uid, ModerationDecisionAndroidFixture.pending()) }
            assertFalse(f.base.exists())
            assertArrayEquals(raw, interrupted.readBytes())
        }
        assertEquals(
            before,
            FirebaseApp.getApps(AccountDeletionFixtures.context).map { it.name }.toSet(),
        )
    }

    @Test
    fun actualUnverifiedOrdinaryUnactivatedAndNoTotpCannotReachTransactionDispatch() = runBlocking {
        org.junit.Assume.assumeTrue(
            "Actual SDK negative requires explicit local emulator opt-in",
            InstrumentationRegistry.getArguments().getString("expectEmulator") == "true",
        )
        AccountDeletionFixtures.requireLocalAvd()
        val context = AccountDeletionFixtures.context
        val auth = LocalFirebase.auth(context)
        val db = LocalFirebase.firestore(context)
        val source = localModerationDecisionSource(context)
        val email = "moderation-a01b-${UUID.randomUUID()}@example.invalid"
        var user: FirebaseUser? = null
        var primary: Throwable? = null
        var dispatchChecks = 0
        auth.signOut()
        try {
            val created =
                auth
                    .createUserWithEmailAndPassword(email, "Synthetic-moderation-decision-only!")
                    .await()
                    .user!!
            user = created
            db.document("users/${created.uid}")
                .set(
                    registeredProfileFields(
                        created.uid,
                        AuthRegistration(
                            email,
                            "Synthetic moderation decision actor",
                            "wien",
                            acceptedTerms = true,
                            acceptedPrivacy = true,
                            minimumAgeConfirmed = true,
                        ),
                        FieldValue.serverTimestamp(),
                    )
                )
                .await()
            val forged = ModerationSession(created.uid, 1, "admin", true)
            val pending =
                ModerationDecisionAndroidFixture.pending(
                    ModerationDecisionPhase.DISPATCHED,
                    created.uid,
                )
            suspend fun attempt(expected: ModerationFailure) {
                accessFailure(expected) {
                    source.execute(forged, pending) {
                        dispatchChecks++
                        true
                    }
                }
            }
            attempt(ModerationFailure.NOT_READY)
            created.sendEmailVerification().await()
            auth.applyActionCode(AuthEmulatorFixtures.actionCode(email, "VERIFY_EMAIL")).await()
            created.reload().await()
            created.getIdToken(true).await()
            attempt(ModerationFailure.DENIED)
            withContext(Dispatchers.IO) {
                AuthEmulatorFixtures.adminRequest(
                    8088,
                    AuthEmulatorFixtures.documentPath("users/${created.uid}") +
                        "?updateMask.fieldPaths=globalRole&updateMask.fieldPaths=requiresMultiFactorAuth",
                    "PATCH",
                    mapOf("globalRole" to "admin", "requiresMultiFactorAuth" to false),
                )
            }
            attempt(ModerationFailure.NOT_READY)
            withContext(Dispatchers.IO) {
                AuthEmulatorFixtures.adminRequest(
                    8088,
                    AuthEmulatorFixtures.documentPath("users/${created.uid}") +
                        "?updateMask.fieldPaths=requiresMultiFactorAuth",
                    "PATCH",
                    mapOf("requiresMultiFactorAuth" to true),
                )
            }
            attempt(ModerationFailure.NOT_READY)
            accessFailure(ModerationFailure.NOT_READY) { source.reconcile(forged, pending) }
            assertEquals(0, dispatchChecks)
            assertNotEquals(
                "totp",
                (created.getIdToken(false).await().claims["firebase"] as? Map<*, *>)?.get(
                    "sign_in_second_factor"
                ),
            )
            assertFalse(
                FirebaseApp.getApps(context).any { it.name == FirebaseApp.DEFAULT_APP_NAME }
            )
        } catch (error: Throwable) {
            primary = error
            throw error
        } finally {
            val failures = mutableListOf<Throwable>()
            val owned = user
            if (owned != null) {
                try {
                    check(auth.currentUser?.uid == owned.uid)
                    owned.delete().await()
                } catch (error: Throwable) {
                    failures += error
                }
                for (path in listOf("users/${owned.uid}", "publicProfiles/${owned.uid}")) {
                    try {
                        withContext(Dispatchers.IO) {
                            AuthEmulatorFixtures.adminRequest(
                                8088,
                                AuthEmulatorFixtures.documentPath(path),
                                "DELETE",
                            )
                        }
                    } catch (error: Throwable) {
                        failures += error
                    }
                }
            }
            try {
                auth.signOut()
            } catch (error: Throwable) {
                failures += error
            }
            if (failures.isNotEmpty()) {
                val cleanup = AssertionError("Scoped moderation decision fixture cleanup failed")
                failures.forEach(cleanup::addSuppressed)
                if (primary == null) throw cleanup else primary.addSuppressed(cleanup)
            }
        }
    }
}
