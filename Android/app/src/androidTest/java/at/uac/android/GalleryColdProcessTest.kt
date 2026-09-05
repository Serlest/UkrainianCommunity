package at.uac.android

import android.util.AtomicFile
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.gallery.*
import at.uac.android.feature.organization.OrganizationMutationGate
import at.uac.android.feature.organization.OrganizationSession
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Three explicitly selected phases; root controls process death between prepare and the read-only
 * inspector. No ActivityScenario, Compose rule, AuthStore refresh, sign-in or UI initialization is
 * used by the inspector.
 */
@RunWith(AndroidJUnit4::class)
class GalleryColdProcessTest {
    private val context
        get() = AccountDeletionFixtures.context

    private val scopeFile
        get() = AtomicFile(File(context.noBackupFilesDir, "synthetic-gallery-cold-scope.bin"))

    private val gate =
        object : OrganizationMutationGate {
            override suspend fun <T> withSession(
                session: OrganizationSession,
                operation: suspend () -> T,
            ): T = operation()
        }

    private fun phase(expected: String) {
        AccountDeletionFixtures.requireLocalAvd()
        assumeTrue(
            "Explicit controlled Gallery cold-process phase required",
            AccountDeletionFixtures.online() &&
                InstrumentationRegistry.getArguments().getString("galleryColdPhase") == expected,
        )
    }

    @Test
    fun prepareDurablePendingCommit() = runBlocking {
        phase("prepare")
        check(!scopeExists()) { "A prior exact Gallery cold-test scope requires inspection first" }
        AuthEmulatorFixtures.seedLegalReference()
        val user = AccountDeletionFixtures.create("deletion-gallery-cold")
        val fixture = GalleryDeviceTest.Fixture(user, "gallery-cold-${UUID.randomUUID()}")
        val target = fixture.target()
        // Test-only recovery address, committed before organization/blob mutations; no caption,
        // URI, pixels or raw UID.
        saveScope(user.uid, target)
        try {
            fixture.seed()
            val session = OrganizationSession(user.uid, 1, true, "Synthetic cold gallery", "user")
            val source = localGallerySource(context) { session }
            val journal = LocalGalleryJournal.get(context)
            assertTrue(journal.pending(user.uid).isEmpty())
            val prepared = fixture.prepared()
            var committed = false
            val lostReceipt =
                object : GallerySource by source {
                    override suspend fun create(
                        intent: GalleryUploadIntent,
                        imageUrl: String,
                        session: OrganizationSession,
                    ): GalleryReceipt {
                        source.create(intent, imageUrl, session)
                        committed = true
                        throw GalleryException(GalleryFailure.UNCONFIRMED)
                    }
                }
            try {
                GalleryRepository(lostReceipt, journal, { session }, gate)
                    .upload(GalleryUploadIntent(target, "Cold synthetic gallery caption", prepared))
                fail("Lost receipt")
            } catch (error: GalleryException) {
                assertEquals(GalleryFailure.UNCONFIRMED, error.failure)
                assertTrue(committed)
            }
            val pending = journal.pending(user.uid).single()
            assertEquals(target, pending.target)
            assertEquals(GalleryPhase.CREATE_SUBMITTED, pending.phase)
            assertEquals(prepared.hash, source.blob(target, session)?.hash)
            assertNotNull(source.photo(target, session))
            val durable =
                File(context.noBackupFilesDir, "organization-gallery/pending.bin").readBytes()
            assertEquals(
                pending,
                GalleryJournalCodec.decode(durable).single {
                    it.accountHash == GalleryContract.accountHash(user.uid)
                },
            )
            val text = String(durable, Charsets.ISO_8859_1)
            assertFalse(text.contains(user.uid))
            assertFalse(text.contains(user.email))
            assertFalse(text.contains("Cold synthetic gallery caption"))
            println(
                "GALLERY_COLD_PREPARED phase=CREATE_SUBMITTED pending=1 metadata=present blob=verified noPrivateDraftOnDisk=true"
            )
            // Deliberately retained for the next process. No cleanup, sign-out, resubmission or
            // activity launch.
        } catch (error: Throwable) {
            println(
                "GALLERY_COLD_PREPARE_FAILED exactScopeRetained=true accountRetained=true automaticCleanup=false"
            )
            throw error
        }
    }

    @Test
    fun inspectAfterActualProcessDeathWithoutActivityOrMutation() = runBlocking {
        phase("inspect")
        val user =
            LocalFirebase.auth(context).currentUser
                ?: error("No persisted synthetic Gallery identity")
        check(
            user.email?.startsWith("deletion-gallery-cold-") == true &&
                user.email?.endsWith("@example.invalid") == true &&
                user.isEmailVerified
        )
        val session = OrganizationSession(user.uid, 1, true, "Synthetic cold gallery", "user")
        val journal = LocalGalleryJournal.get(context)
        val before = journal.pending(user.uid).single()
        assertEquals(readScope(user.uid), before.target)
        assertEquals(GalleryPhase.CREATE_SUBMITTED, before.phase)
        check(before.target.organizationId.matches(Regex("gallery-cold-[a-f0-9-]{36}")))
        val source = localGallerySource(context) { session }
        val snapshot = source.snapshot(before.target.organizationId, session)
        val photo = source.photo(before.target, session)!!
        val blob = source.blob(before.target, session)!!
        assertEquals(1, snapshot.counter)
        assertEquals(1, snapshot.photos.size)
        assertTrue(GalleryContract.matches(photo, before))
        assertEquals(before.jpegHash, blob.hash)
        assertEquals(before.token, blob.token)
        assertEquals(before, journal.pending(user.uid).single())
        println(
            "GALLERY_COLD_INSPECTED pendingUnchanged=true metadataCount=1 imageMatches=true activityStarted=false serverMutations=0"
        )
    }

    @Test
    fun explicitReconcileAndScopedCleanupAfterInspector() = runBlocking {
        phase("cleanup")
        val captured =
            LocalFirebase.auth(context).currentUser
                ?: error("No persisted synthetic Gallery identity")
        val email = captured.email ?: error("Synthetic email missing")
        check(email.startsWith("deletion-gallery-cold-") && email.endsWith("@example.invalid"))
        val user = AccountDeletionFixtures.User(captured.uid, email, captured)
        val session = OrganizationSession(user.uid, 1, true, "Synthetic cold gallery", "user")
        val journal = LocalGalleryJournal.get(context)
        val pending = journal.pending(user.uid).single()
        assertEquals(readScope(user.uid), pending.target)
        check(pending.target.organizationId.matches(Regex("gallery-cold-[a-f0-9-]{36}")))
        val source = localGallerySource(context) { session }
        val repository = GalleryRepository(source, journal, { session }, gate)
        assertEquals(GalleryRecovery.PUBLISHED, repository.reconcile(pending).status)
        assertTrue(journal.pending(user.uid).isEmpty())
        val photo = source.photo(pending.target, session)!!
        val removed = repository.remove(photo)
        assertEquals(0, removed.snapshot.counter)
        assertTrue(removed.snapshot.photos.isEmpty())
        assertNull(removed.pending)
        assertNull(source.blob(pending.target, session))
        assertNull(source.photo(pending.target, session))
        val fixture =
            GalleryDeviceTest.Fixture(user, pending.target.organizationId).apply {
                remember(pending.target)
            }
        fixture.cleanup()
        AccountDeletionFixtures.clean(user)
        assertTrue(journal.pending(user.uid).isEmpty())
        scopeFile.delete()
        assertFalse(scopeFile.baseFile.exists())
        println(
            "GALLERY_COLD_CLEANUP_CONFIRMED pending=0 metadata=absent blob=absent account=removed"
        )
    }

    private fun saveScope(uid: String, target: GalleryTarget) {
        AccountDeletionFixtures.requireLocalAvd()
        check(!scopeExists()) { "A prior exact Gallery cold-test scope cannot be replaced" }
        require(target.organizationId.matches(Regex("gallery-cold-[a-f0-9-]{36}")))
        val bytes =
            ByteArrayOutputStream()
                .also { buffer ->
                    DataOutputStream(buffer).use {
                        it.writeInt(1)
                        it.writeUTF(GalleryContract.accountHash(uid))
                        it.writeUTF(target.organizationId)
                        it.writeUTF(target.photoId)
                    }
                }
                .toByteArray()
        val output = scopeFile.startWrite()
        try {
            output.write(bytes)
            output.fd.sync()
            scopeFile.finishWrite(output)
        } catch (error: Throwable) {
            scopeFile.failWrite(output)
            throw error
        }
        assertEquals(target, readScope(uid))
    }

    private fun readScope(uid: String): GalleryTarget {
        AccountDeletionFixtures.requireLocalAvd()
        val bytes =
            scopeFile.openRead().use {
                require(it.channel.size() in 1..512)
                it.readBytes()
            }
        return DataInputStream(ByteArrayInputStream(bytes)).use {
            check(it.readInt() == 1 && it.readUTF() == GalleryContract.accountHash(uid))
            GalleryTarget(it.readUTF(), it.readUTF()).also { target ->
                check(
                    target.organizationId.matches(Regex("gallery-cold-[a-f0-9-]{36}")) &&
                        it.read() == -1
                )
            }
        }
    }

    private fun scopeExists() =
        listOf("", ".bak", ".new").any { File(scopeFile.baseFile.path + it).exists() }
}
