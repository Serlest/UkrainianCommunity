package at.uac.android

import android.os.Build
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalEnvironment
import at.uac.android.feature.authoring.*
import at.uac.android.feature.authoring.recovery.*
import at.uac.android.feature.browse.*
import at.uac.android.feature.organization.*
import java.io.File
import java.io.SyncFailedException
import java.security.KeyStore
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

/**
 * Native Android Keystore + AtomicFile proof; never cloud, external storage, real account or shared
 * app journal.
 */
class AuthoringRecoveryDeviceTest {
    private val actor = OrganizationSession("native-recovery-author", 1, true, "Author", "user")
    private val now = Instant.parse("2026-09-03T03:00:00.123456Z")
    private val org
        get() =
            OrganizationDraft(
                    "native-recovery-org",
                    "Native recovery",
                    "Complete synthetic organization",
                    region = "wien",
                    city = "Wien",
                )
                .let {
                    OrganizationContract.record(
                        RawDocument(
                            it.id,
                            OrganizationContract.create(it, actor, now) +
                                mapOf("ownerId" to actor.uid, "moderationStatus" to "approved"),
                        ),
                        actor,
                    )
                }

    private val scope
        get() = AuthoringRecoveryScope(actor.uid, org.id, ContentKind.NEWS)

    private fun draft() =
        AuthoringContract.newDraft(ContentKind.NEWS, org, now)
            .copy(
                title = "PRIVATE-NATIVE-RECOVERY",
                summary = "Synthetic",
                body = "SECRET BODY native-only € 🇺🇦",
            )

    private fun intent(draft: AuthoringDraft) =
        AuthoringContract.submission(draft, org, actor, null, now)

    private fun item(intent: AuthoringSubmission) =
        AuthoringContract.item(
            intent.kind,
            RawDocument(
                intent.id,
                intent.fields.filterValues { it != null } + ("updatedAt" to now),
            ),
            org.id,
            AuthoringStatus.APPROVED,
            actor,
        )

    private suspend fun failure(expected: AuthoringRecoveryFailure, block: suspend () -> Unit) {
        try {
            block()
            fail("Expected $expected")
        } catch (error: AuthoringRecoveryException) {
            assertEquals(expected, error.reason)
        }
    }

    private class Fixture {
        private val context = InstrumentationRegistry.getInstrumentation().targetContext
        private val token = UUID.randomUUID().toString()
        val alias = "uac.test.authoring.recovery.$token"
        val root = File(context.noBackupFilesDir, "authoring-recovery-test-$token").canonicalFile

        init {
            LocalEnvironment.requireSafe()
            check(context.packageName == "at.uac.android.local")
            check(
                (Build.HARDWARE in setOf("ranchu", "goldfish") &&
                    Build.MODEL.startsWith("sdk_gphone")) || isExplicitApi26CompatibilityAvd()
            )
            check(!root.exists())
        }

        fun store(failSync: Boolean = false) =
            FileAuthoringRecoveryStore(
                root,
                AuthoringRecoveryCipher(AndroidRecoveryKeys(alias)),
                sync = {
                    if (failSync) throw SyncFailedException("Synthetic sync failure")
                    else it.fd.sync()
                },
            )

        fun file(scope: AuthoringRecoveryScope, purpose: String) =
            File(File(root, scope.accountHash), "${scope.scopeHash}-$purpose.bin")

        fun deleteKey() {
            KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.deleteEntry(alias)
        }

        fun cleanup() {
            var first: Exception? = null
            fun attempt(action: () -> Unit) {
                try {
                    action()
                } catch (error: Exception) {
                    if (first == null) first = error else first.addSuppressed(error)
                }
            }
            attempt { deleteKey() }
            if (root.exists()) {
                check(
                    root.name == "authoring-recovery-test-$token" &&
                        requireNotNull(root.parentFile).canonicalFile ==
                            context.noBackupFilesDir.canonicalFile
                )
                root.listFiles().orEmpty().forEach { account ->
                    check(
                        account.name.matches(Regex("[a-f0-9]{64}")) &&
                            account.isDirectory &&
                            account.canonicalFile == account.absoluteFile
                    )
                    account.listFiles().orEmpty().forEach { file ->
                        attempt {
                            check(
                                file.name.matches(
                                    Regex("[a-f0-9]{64}-(draft|pending)\\.bin(?:\\.new|\\.bak)?")
                                ) && file.isFile && file.canonicalFile == file.absoluteFile
                            )
                            check(file.delete() && !file.exists())
                        }
                    }
                    attempt { check(account.delete() && !account.exists()) }
                }
                attempt { check(root.delete() && !root.exists()) }
            }
            first?.let { throw it }
        }
    }

    private suspend fun fixture(test: suspend (Fixture) -> Unit) {
        val f = Fixture()
        var original: Throwable? = null
        try {
            test(f)
        } catch (error: Throwable) {
            original = error
            throw error
        } finally {
            try {
                f.cleanup()
            } catch (error: Throwable) {
                if (original == null) throw error else original.addSuppressed(error)
            }
        }
    }

    @Test
    fun nativeKeyAndAtomicReadbackSurviveNewStoreAndNeverWritePlaintext() = runBlocking {
        fixture { f ->
            val d = draft()
            f.store().saveDraft(scope, d, "America/Los_Angeles")
            val recovered = f.store().load(scope)
            assertEquals(d, recovered?.draft)
            assertEquals("America/Los_Angeles", recovered?.draftZoneId)
            val raw = f.file(scope, "draft").readBytes().toString(Charsets.ISO_8859_1)
            assertFalse(raw.contains("SECRET BODY"))
            assertFalse(raw.contains("PRIVATE-NATIVE-RECOVERY"))
            assertFalse(raw.contains(actor.uid))
            assertNull(f.store().load(scope.copy(uid = "other-native-account")))
        }
    }

    @Test
    fun nativeScheduledV2DraftAndExactPendingSurviveNewStoreWithoutRetiming() = runBlocking {
        fixture { f ->
            val d =
                draft()
                    .copy(
                        publicationMode = AuthoringPublicationMode.SCHEDULED,
                        scheduledAt = now.plusSeconds(3_600),
                    )
            val value = intent(d)
            f.store().saveDraft(scope, d, "America/Los_Angeles")
            assertEquals(d, f.store().load(scope)?.draft)
            assertEquals("America/Los_Angeles", f.store().load(scope)?.draftZoneId)
            assertEquals(value, f.store().prepareCreation(scope, value))
            f.store().clearUnsentForAccount(actor.uid)
            val pending = requireNotNull(f.store().load(scope)?.pending)
            assertEquals(value, pending)
            assertFalse(AuthoringPublication.canSend(pending, now.plusSeconds(3_601)))
            val receipt =
                AuthoringContract.item(
                    value.kind,
                    RawDocument(value.id, value.fields.filterValues { it != null }),
                    org.id,
                    AuthoringStatus.SCHEDULED,
                    actor,
                )
            f.store().confirmCreation(scope, value, receipt)
            assertNull(f.store().load(scope))
        }
    }

    @Test
    fun nativePendingSurvivesLogoutAndAllowsOnlyExactReceiptCleanup() = runBlocking {
        fixture { f ->
            val d = draft()
            val value = intent(d)
            val store = f.store()
            store.saveDraft(scope, d, "Europe/Vienna")
            assertEquals(value, store.prepareCreation(scope, value))
            store.clearUnsentForAccount(actor.uid)
            assertNull(f.store().load(scope)?.draft)
            assertEquals(value, f.store().load(scope)?.pending)
            failure(AuthoringRecoveryFailure.PENDING_CONFLICT) {
                f.store().prepareCreation(scope, intent(draft()))
            }
            failure(AuthoringRecoveryFailure.PENDING_CONFLICT) {
                f.store()
                    .confirmCreation(
                        scope,
                        value,
                        item(value).copy(fields = item(value).fields + ("title" to "other")),
                    )
            }
            assertTrue(f.file(scope, "pending").exists())
            f.store().confirmCreation(scope, value, item(value))
            assertNull(f.store().load(scope))
            assertFalse(f.file(scope, "pending").exists())
        }
    }

    @Test
    fun removedKeyLocksExistingJournalAndCannotRegenerateAroundIt() = runBlocking {
        fixture { f ->
            val value = intent(draft())
            f.store().prepareCreation(scope, value)
            val old = f.file(scope, "pending").readBytes()
            f.deleteKey()
            failure(AuthoringRecoveryFailure.LOCKED) { f.store().load(scope) }
            failure(AuthoringRecoveryFailure.LOCKED) {
                f.store()
                    .saveDraft(scope.copy(organizationId = "new-org"), draft(), "Europe/Vienna")
            }
            assertArrayEquals(old, f.file(scope, "pending").readBytes())
            assertFalse(
                KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.containsAlias(f.alias)
            )
        }
    }

    @Test
    fun tamperedDraftIsNotOverwrittenOrUsedToCreateANewRequest() = runBlocking {
        fixture { f ->
            val d = draft()
            f.store().saveDraft(scope, d, "Europe/Vienna")
            val file = f.file(scope, "draft")
            val bad =
                file.readBytes().also { it[it.lastIndex] = (it.last().toInt() xor 1).toByte() }
            file.writeBytes(bad)
            failure(AuthoringRecoveryFailure.LOCKED) { f.store().load(scope) }
            failure(AuthoringRecoveryFailure.LOCKED) {
                f.store().saveDraft(scope, d.copy(title = "replacement"), "Europe/Vienna")
            }
            failure(AuthoringRecoveryFailure.LOCKED) { f.store().prepareCreation(scope, intent(d)) }
            assertArrayEquals(bad, file.readBytes())
            assertFalse(f.file(scope, "pending").exists())
        }
    }

    @Test
    fun interruptedFirstAtomicWriteIsLockedRatherThanReportedAbsent() = runBlocking {
        fixture { f ->
            f.store().load(scope)
            val interrupted = File(f.file(scope, "pending").path + ".new")
            interrupted.writeBytes(byteArrayOf(1, 2, 3))
            failure(AuthoringRecoveryFailure.LOCKED) { f.store().load(scope) }
            failure(AuthoringRecoveryFailure.LOCKED) {
                f.store().prepareCreation(scope, intent(draft()))
            }
            assertArrayEquals(byteArrayOf(1, 2, 3), interrupted.readBytes())
        }
    }

    @Test
    fun explicitFileSyncFailurePreventsDurableReceiptAndPreservesPreviousDraft() = runBlocking {
        fixture { f ->
            val d = draft()
            f.store().saveDraft(scope, d, "Europe/Vienna")
            failure(AuthoringRecoveryFailure.IO) {
                f.store(failSync = true)
                    .saveDraft(scope, d.copy(title = "not durable"), "Europe/Vienna")
            }
            assertEquals(d, f.store().load(scope)?.draft)
            failure(AuthoringRecoveryFailure.IO) {
                f.store(failSync = true).prepareCreation(scope, intent(d))
            }
            assertNull(f.store().load(scope)?.pending)
            assertEquals(d, f.store().load(scope)?.draft)
        }
    }
}
