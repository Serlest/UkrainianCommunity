package at.uac.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.feature.gallery.*
import java.io.File
import java.io.SyncFailedException
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Native AtomicFile/fd.sync fault checks in exact fresh test directories, never the shared user
 * recovery journal.
 */
@RunWith(AndroidJUnit4::class)
class GalleryJournalDeviceTest {
    private val uid = "synthetic-native-gallery-owner"

    private fun entry() =
        GalleryJournalEntry(
            GalleryContract.accountHash(uid),
            GalleryTarget("synthetic-native-gallery", "synthetic-photo"),
            GalleryPhase.CREATE_SUBMITTED,
            GalleryContract.hashText("synthetic-jpeg"),
            GalleryContract.hashText("PRIVATE-CAPTION-NOT-ON-DISK"),
            GalleryContract.accountHash(uid),
            "synthetic-token",
        )

    private class Fixture {
        private val context = AccountDeletionFixtures.context
        private val token = UUID.randomUUID().toString()
        val directory = File(context.noBackupFilesDir, "gallery-journal-test-$token").canonicalFile
        val base
            get() = File(directory, "pending.bin")

        init {
            AccountDeletionFixtures.requireLocalAvd()
            check(!directory.exists() && directory.mkdirs())
        }

        fun store(failSync: Boolean = false) =
            FileGalleryJournal(
                directory,
                sync = {
                    if (failSync) throw SyncFailedException("Synthetic Gallery fd.sync failure")
                    else it.fd.sync()
                },
            )

        fun cleanup() {
            AccountDeletionFixtures.requireLocalAvd()
            check(
                directory.name == "gallery-journal-test-$token" &&
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
        var original: Throwable? = null
        try {
            action(fixture)
        } catch (error: Throwable) {
            original = error
            throw error
        } finally {
            try {
                fixture.cleanup()
            } catch (error: Throwable) {
                if (original == null) throw error else original.addSuppressed(error)
            }
        }
    }

    private suspend fun fails(action: suspend () -> Unit) {
        try {
            action()
            fail("A corrupt or non-durable journal must fail closed")
        } catch (error: GalleryException) {
            assertEquals(GalleryFailure.JOURNAL, error.failure)
        }
    }

    @Test
    fun nativeRoundTripNewInstanceAccountIsolationAndCompareAndSet() = runBlocking {
        fixture { f ->
            val value = entry()
            assertEquals(value, f.store().put(uid, value))
            assertEquals(listOf(value), f.store().pending(uid))
            assertTrue(f.store().pending("foreign-gallery-user").isEmpty())
            val raw = f.base.readBytes()
            val readable = raw.toString(Charsets.ISO_8859_1)
            assertFalse(readable.contains(uid))
            assertFalse(readable.contains("PRIVATE-CAPTION-NOT-ON-DISK"))
            fails { f.store().clear(uid, value.copy(phase = GalleryPhase.DELETE_SUBMITTED)) }
            assertArrayEquals(raw, f.base.readBytes())
            assertEquals(listOf(value), f.store().pending(uid))
            f.store().clear(uid, value)
            assertTrue(f.store().pending(uid).isEmpty())
        }
    }

    @Test
    fun corruptAndOversizedJournalNeverBecomeEmptyOrGetOverwritten() = runBlocking {
        for (bytes in
            listOf(byteArrayOf(1, 2, 3), ByteArray(GalleryJournalCodec.MAX_BYTES + 1))) fixture { f
            ->
            f.base.writeBytes(bytes)
            fails { f.store().pending(uid) }
            fails { f.store().put(uid, entry()) }
            assertArrayEquals(bytes, f.base.readBytes())
        }
    }

    @Test
    fun interruptedInitialNewFileIsPreservedAndCannotAllowAnotherIntent() = runBlocking {
        fixture { f ->
            val interrupted = File(f.base.path + ".new")
            val bytes = byteArrayOf(1, 2, 3)
            interrupted.writeBytes(bytes)
            assertFalse(f.base.exists())
            fails { f.store().pending(uid) }
            fails { f.store().put(uid, entry()) }
            assertFalse(f.base.exists())
            assertArrayEquals(bytes, interrupted.readBytes())
        }
    }

    @Test
    fun explicitSyncFailureDoesNotAcknowledgeFirstWriteOrReplaceCommittedEntry() = runBlocking {
        fixture { f ->
            fails { f.store(failSync = true).put(uid, entry()) }
            assertTrue(f.store().pending(uid).isEmpty())
        }
        fixture { f ->
            val value = entry()
            f.store().put(uid, value)
            val committed = f.base.readBytes()
            fails {
                f.store(failSync = true)
                    .put(uid, value.copy(phase = GalleryPhase.DELETE_SUBMITTED), value)
            }
            assertArrayEquals(committed, f.base.readBytes())
            assertEquals(listOf(value), f.store().pending(uid))
        }
    }
}
