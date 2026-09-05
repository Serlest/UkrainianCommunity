package at.uac.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalFirebase
import at.uac.android.core.LocalFunctions
import at.uac.android.feature.moderation.*
import at.uac.android.feature.organizationreview.*
import com.google.firebase.FirebaseApp
import java.io.File
import java.io.SyncFailedException
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

internal object OrganizationReviewAndroidFixture {
    val actor = ModerationSession("synthetic-review-admin", 1, "admin", true)
    const val id = "synthetic-review-request"
    const val submitter = "PRIVATE-RECIPIENT-NOT-ON-DISK"
    const val secret = "PRIVATE-REASON-NOT-ON-DISK"
    val time: Instant = Instant.parse("2026-09-03T08:00:00.123456789Z")

    fun fields() =
        mapOf<String, Any?>(
            "id" to id,
            "name" to "Synthetic organization request · Синтетична заявка",
            "submittedByUserId" to submitter,
            "moderationStatus" to "pendingReview",
            "updatedAt" to time,
            "fullDescription" to secret,
        )

    fun snapshot() = OrganizationReviewContract.snapshot(id, fields())

    fun pending(uid: String = actor.uid, target: String = id) =
        OrganizationReviewPending(
            OrganizationReviewContract.accountHash(uid),
            snapshot().version.copy(organizationId = target),
            OrganizationReviewAction.REJECT,
            OrganizationReviewContract.hash(secret),
            UUID.randomUUID().toString(),
            "admin",
            OrganizationReviewPhase.PREPARED,
        )

    fun receipt(entry: OrganizationReviewPending) =
        OrganizationReviewContract.receipt(
            entry,
            mapOf(
                "organizationId" to entry.version.organizationId,
                "moderationStatus" to "rejected",
                "notificationId" to
                    "organizationRequestRejected_${UUID.randomUUID()}_${entry.version.organizationId}_$submitter",
                "updatedAt" to time.minusSeconds(1).toString(),
            ),
        )
}

/** Native local file faults and actual Auth negative proofs, never synthetic positive TOTP. */
@RunWith(AndroidJUnit4::class)
class OrganizationReviewDeviceTest {
    private val f = OrganizationReviewAndroidFixture

    private class Fixture {
        val context = AccountDeletionFixtures.context
        private val token = UUID.randomUUID().toString()
        val directory =
            File(context.noBackupFilesDir, "org-review-journal-test-$token").canonicalFile
        val base
            get() = File(directory, "pending.bin")

        init {
            AccountDeletionFixtures.requireLocalAvd()
            check(!directory.exists() && directory.mkdirs())
        }

        fun store(failSync: Boolean = false) =
            FileOrganizationReviewJournal(directory) {
                if (failSync) throw SyncFailedException("Synthetic fsync failure") else it.fd.sync()
            }

        fun cleanup() {
            AccountDeletionFixtures.requireLocalAvd()
            check(
                directory.parentFile?.canonicalFile == context.noBackupFilesDir.canonicalFile &&
                    directory.name == "org-review-journal-test-$token"
            )
            val failures = mutableListOf<Throwable>()
            directory.listFiles().orEmpty().forEach { file ->
                try {
                    check(
                        file.name in setOf("pending.bin", "pending.bin.new", "pending.bin.bak") &&
                            file.isFile &&
                            file.canonicalFile == file.absoluteFile
                    )
                    check(file.delete() && !file.exists())
                } catch (error: Throwable) {
                    failures += error
                }
            }
            if (failures.isEmpty()) check(directory.delete() && !directory.exists())
            else
                throw AssertionError("Exact journal fixture cleanup failed").also { error ->
                    failures.forEach(error::addSuppressed)
                }
        }
    }

    private suspend fun fixture(action: suspend (Fixture) -> Unit) {
        val f = Fixture()
        var primary: Throwable? = null
        try {
            action(f)
        } catch (error: Throwable) {
            primary = error
            throw error
        } finally {
            try {
                f.cleanup()
            } catch (error: Throwable) {
                if (primary == null) throw error else primary.addSuppressed(error)
            }
        }
    }

    private suspend fun journalFailure(action: suspend () -> Any?) {
        try {
            action()
            fail("Expected journal rejection")
        } catch (error: OrganizationReviewException) {
            assertEquals(OrganizationReviewFailure.JOURNAL, error.failure)
        }
    }

    @Test
    fun nativeDurableReloadReceiptDigestNoPrivateDataAndExactCas() = runBlocking {
        fixture { disk ->
            val prepared = f.pending()
            disk.store().put(f.actor.uid, prepared)
            val dispatched = prepared.copy(phase = OrganizationReviewPhase.DISPATCHED)
            disk.store().put(f.actor.uid, dispatched, prepared)
            val acknowledged =
                dispatched.copy(
                    phase = OrganizationReviewPhase.ACKNOWLEDGED,
                    receipt = f.receipt(dispatched),
                )
            disk.store().put(f.actor.uid, acknowledged, dispatched)
            assertEquals(listOf(acknowledged), disk.store().pending(f.actor.uid))
            assertTrue(disk.store().pending("other-user").isEmpty())
            val bytes = disk.base.readBytes()
            val raw = bytes.toString(Charsets.ISO_8859_1)
            for (secret in
                listOf(
                    f.actor.uid,
                    f.submitter,
                    f.secret,
                    "organizationRequestRejected_",
                )) assertFalse(raw.contains(secret))
            journalFailure { disk.store().clear(f.actor.uid, prepared) }
            journalFailure { disk.store().put(f.actor.uid, dispatched, acknowledged) }
            assertArrayEquals(bytes, disk.base.readBytes())
            disk.store().clear(f.actor.uid, acknowledged)
            assertTrue(disk.store().pending(f.actor.uid).isEmpty())
        }
    }

    @Test
    fun nativeFsyncFailureDoesNotAcknowledgeOrOverwritePhase() = runBlocking {
        fixture { disk ->
            journalFailure { disk.store(true).put(f.actor.uid, f.pending()) }
            assertTrue(disk.store().pending(f.actor.uid).isEmpty())
        }
        fixture { disk ->
            val prepared = f.pending()
            disk.store().put(f.actor.uid, prepared)
            val bytes = disk.base.readBytes()
            journalFailure {
                disk
                    .store(true)
                    .put(
                        f.actor.uid,
                        prepared.copy(phase = OrganizationReviewPhase.DISPATCHED),
                        prepared,
                    )
            }
            assertArrayEquals(bytes, disk.base.readBytes())
            assertEquals(listOf(prepared), disk.store().pending(f.actor.uid))
        }
    }

    @Test
    fun nativeCorruptionOversizeAndOrphanNewFailClosed() = runBlocking {
        for (bytes in
            listOf(
                byteArrayOf(1, 2, 3),
                ByteArray(OrganizationReviewJournalCodec.MAX_BYTES + 1),
            )) fixture { disk ->
            disk.base.writeBytes(bytes)
            journalFailure { disk.store().pending(f.actor.uid) }
            journalFailure { disk.store().put(f.actor.uid, f.pending()) }
            assertArrayEquals(bytes, disk.base.readBytes())
        }
        fixture { disk ->
            val orphan = File(disk.base.path + ".new")
            val bytes = byteArrayOf(1, 2, 3)
            orphan.writeBytes(bytes)
            journalFailure { disk.store().pending(f.actor.uid) }
            journalFailure { disk.store().put(f.actor.uid, f.pending()) }
            assertFalse(disk.base.exists())
            assertArrayEquals(bytes, orphan.readBytes())
        }
    }

    @Test
    fun nativeCapacityKeepsEveryExistingUnresolvedEntry() = runBlocking {
        fixture { disk ->
            repeat(16) { disk.store().put(f.actor.uid, f.pending(target = "request-$it")) }
            val bytes = disk.base.readBytes()
            journalFailure { disk.store().put(f.actor.uid, f.pending(target = "request-overflow")) }
            assertArrayEquals(bytes, disk.base.readBytes())
            assertEquals(16, disk.store().pending(f.actor.uid).size)
        }
    }

    @Test
    fun nativeJournalDoesNotInitializeFirebase() = runBlocking {
        val context = AccountDeletionFixtures.context
        val before = FirebaseApp.getApps(context).map { it.name }.toSet()
        fixture { disk ->
            val entry = f.pending()
            disk.store().put(f.actor.uid, entry)
            disk.store().clear(f.actor.uid, entry)
        }
        assertEquals(before, FirebaseApp.getApps(context).map { it.name }.toSet())
    }

    @Test
    fun actualNamedGatewayBindingAndExplicitBindingVetoWithoutDefaultApp() = runBlocking {
        AccountDeletionFixtures.requireLocalAvd()
        val context = AccountDeletionFixtures.context
        val auth = LocalFirebase.auth(context)
        val db = LocalFirebase.firestore(context)
        val gateway = LocalFunctions.instance(context)
        FirebaseOrganizationReviewSource(db, auth, gateway)
        assertFalse(FirebaseApp.getApps(context).any { it.name == FirebaseApp.DEFAULT_APP_NAME })
        val forgedBinding =
            object : at.uac.android.core.backend.CallableGateway {
                override fun requireBoundTo(auth: com.google.firebase.auth.FirebaseAuth) {
                    throw IllegalArgumentException("Synthetic binding rejection")
                }

                override fun getHttpsCallable(
                    name: String
                ): at.uac.android.core.backend.CallableCall = error("Must not create a call")
            }
        assertTrue(
            runCatching { FirebaseOrganizationReviewSource(db, auth, forgedBinding) }
                .exceptionOrNull() is IllegalArgumentException
        )
    }

    @Test
    fun actualUnverifiedOrdinaryUnactivatedAndNoTotpNeverDispatch() = runBlocking {
        assumeTrue(InstrumentationRegistry.getArguments().getString("expectEmulator") == "true")
        val fixtures = AccountStatusFixtures("status-org-review")
        var primary: Throwable? = null
        try {
            val user = fixtures.create(verified = false)
            val auth = LocalFirebase.auth(fixtures.context)
            val source = localOrganizationReviewSource(fixtures.context)
            val session = f.actor.copy(uid = user.uid)
            val entry = f.pending(user.uid).copy(phase = OrganizationReviewPhase.DISPATCHED)
            var dispatch = 0
            suspend fun denied(expected: ModerationFailure) {
                try {
                    source.send(session, entry, f.secret) {
                        dispatch++
                        true
                    }
                    fail("Expected actual Auth rejection")
                } catch (error: ModerationException) {
                    assertEquals(expected, error.failure)
                }
            }
            denied(ModerationFailure.NOT_READY)
            val actual = checkNotNull(auth.currentUser)
            actual.sendEmailVerification().await()
            auth
                .applyActionCode(AuthEmulatorFixtures.actionCode(user.email, "VERIFY_EMAIL"))
                .await()
            actual.reload().await()
            actual.getIdToken(true).await()
            denied(ModerationFailure.DENIED)
            suspend fun reviewerFixture(activated: Boolean) {
                check(
                    user.email.startsWith("status-org-review-") &&
                        user.email.endsWith("@example.invalid")
                )
                check(
                    fixtures.document(user) != null
                ) // Existing instance validates exact owned UID.
                withContext(Dispatchers.IO) {
                    AuthEmulatorFixtures.adminRequest(
                        8088,
                        AuthEmulatorFixtures.documentPath("users/${user.uid}") +
                            "?updateMask.fieldPaths=globalRole&updateMask.fieldPaths=requiresMultiFactorAuth",
                        "PATCH",
                        mapOf("globalRole" to "admin", "requiresMultiFactorAuth" to activated),
                    )
                }
                val readback = checkNotNull(fixtures.document(user)).getJSONObject("fields")
                check(readback.getJSONObject("globalRole").getString("stringValue") == "admin")
                check(
                    readback.getJSONObject("requiresMultiFactorAuth").getBoolean("booleanValue") ==
                        activated
                )
            }
            reviewerFixture(false)
            denied(ModerationFailure.NOT_READY)
            reviewerFixture(true)
            denied(ModerationFailure.NOT_READY)
            assertNotEquals(
                "totp",
                (actual.getIdToken(false).await().claims["firebase"] as? Map<*, *>)?.get(
                    "sign_in_second_factor"
                ),
            )
            assertEquals(0, dispatch)
            assertFalse(
                FirebaseApp.getApps(fixtures.context).any {
                    it.name == FirebaseApp.DEFAULT_APP_NAME
                }
            )
        } catch (error: Throwable) {
            primary = error
            throw error
        } finally {
            fixtures.cleanup(primary)
        }
    }
}
