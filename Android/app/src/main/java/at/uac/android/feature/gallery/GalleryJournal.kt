package at.uac.android.feature.gallery

import android.content.Context
import android.util.AtomicFile
import at.uac.android.core.LocalEnvironment
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileNotFoundException
import java.io.FileOutputStream
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

enum class GalleryPhase {
    UPLOADING,
    UPLOADED,
    CREATE_SUBMITTED,
    CREATE_REJECTED,
    DELETE_SUBMITTED,
    DELETE_REJECTED,
    METADATA_REMOVED,
    UPLOAD_REJECTED,
}

data class GalleryJournalEntry(
    val accountHash: String,
    val target: GalleryTarget,
    val phase: GalleryPhase,
    val jpegHash: String,
    val captionHash: String,
    val uploaderHash: String,
    val token: String? = null,
) {
    override fun toString() = "GalleryJournalEntry(phase=$phase, redacted)"
}

interface GalleryJournal {
    suspend fun pending(uid: String): List<GalleryJournalEntry>

    suspend fun put(
        uid: String,
        entry: GalleryJournalEntry,
        expected: GalleryJournalEntry? = null,
    ): GalleryJournalEntry

    suspend fun clear(uid: String, expected: GalleryJournalEntry)
}

/**
 * A single bounded, backup-excluded file. No caption, original URI, pixel bytes, raw UID or
 * permission state.
 */
object GalleryJournalCodec {
    const val MAX_ENTRIES = 16
    const val MAX_BYTES = 16_384
    private const val MAGIC = 0x55414347
    private val hash = Regex("[a-f0-9]{64}")

    fun validate(entry: GalleryJournalEntry) {
        require(
            listOf(entry.accountHash, entry.jpegHash, entry.captionHash, entry.uploaderHash)
                .all(hash::matches)
        )
        require(
            entry.token == null ||
                GalleryContract.token(
                    GalleryContract.alias(entry.target, entry.token),
                    entry.target,
                ) == entry.token
        )
        require(
            entry.phase in setOf(GalleryPhase.UPLOADING, GalleryPhase.UPLOAD_REJECTED) ||
                entry.token != null
        )
    }

    fun encode(entries: List<GalleryJournalEntry>): ByteArray {
        require(
            entries.size <= MAX_ENTRIES &&
                entries.map { it.accountHash to it.target }.distinct().size == entries.size
        )
        return ByteArrayOutputStream()
            .also { bytes ->
                DataOutputStream(bytes).use { out ->
                    out.writeInt(MAGIC)
                    out.writeByte(1)
                    out.writeByte(entries.size)
                    entries.forEach { entry ->
                        validate(entry)
                        out.writeUTF(entry.accountHash)
                        out.writeUTF(entry.target.organizationId)
                        out.writeUTF(entry.target.photoId)
                        out.writeByte(entry.phase.ordinal)
                        out.writeUTF(entry.jpegHash)
                        out.writeUTF(entry.captionHash)
                        out.writeUTF(entry.uploaderHash)
                        out.writeBoolean(entry.token != null)
                        entry.token?.let(out::writeUTF)
                    }
                }
            }
            .toByteArray()
            .also { require(it.size <= MAX_BYTES) }
    }

    fun decode(bytes: ByteArray): List<GalleryJournalEntry> {
        require(bytes.size in 1..MAX_BYTES)
        return DataInputStream(ByteArrayInputStream(bytes)).use { input ->
            require(input.readInt() == MAGIC && input.readUnsignedByte() == 1)
            val count = input.readUnsignedByte().also { require(it <= MAX_ENTRIES) }
            List(count) {
                    val account = input.readUTF()
                    val target = GalleryTarget(input.readUTF(), input.readUTF())
                    val phase =
                        GalleryPhase.entries.getOrNull(input.readUnsignedByte())
                            ?: error("Invalid gallery phase")
                    GalleryJournalEntry(
                            account,
                            target,
                            phase,
                            input.readUTF(),
                            input.readUTF(),
                            input.readUTF(),
                            if (input.readBoolean()) input.readUTF() else null,
                        )
                        .also(::validate)
                }
                .also { entries ->
                    require(
                        input.read() == -1 &&
                            entries.map { it.accountHash to it.target }.distinct().size ==
                                entries.size
                    )
                }
        }
    }
}

class FileGalleryJournal(
    private val directory: File,
    private val sync: (FileOutputStream) -> Unit = { it.fd.sync() },
) : GalleryJournal {
    private val mutex = Mutex()
    private val file
        get() = AtomicFile(File(directory, "pending.bin"))

    private fun read(): List<GalleryJournalEntry> {
        val atomic = file
        val bytes =
            try {
                atomic.openRead().use { input ->
                    val output = ByteArrayOutputStream()
                    val buffer = ByteArray(4096)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        require(output.size() + count <= GalleryJournalCodec.MAX_BYTES)
                        output.write(buffer, 0, count)
                    }
                    output.toByteArray()
                }
            } catch (error: FileNotFoundException) {
                if (listOf("", ".bak", ".new").any { File(atomic.baseFile.path + it).exists() })
                    throw error
                return emptyList()
            }
        return GalleryJournalCodec.decode(bytes)
    }

    private fun write(entries: List<GalleryJournalEntry>) {
        check(directory.isDirectory || directory.mkdirs())
        val atomic = file
        val stream = atomic.startWrite()
        try {
            stream.write(GalleryJournalCodec.encode(entries))
            // AtomicFile logs its own fsync failure. A failed explicit sync must never acknowledge
            // a pending intent.
            sync(stream)
            atomic.finishWrite(stream)
        } catch (error: Exception) {
            atomic.failWrite(stream)
            throw error
        }
        check(read() == entries)
    }

    private suspend fun <T> locked(action: () -> T): T =
        withContext(Dispatchers.IO) {
            mutex.withLock {
                try {
                    action()
                } catch (error: GalleryException) {
                    throw error
                } catch (error: Exception) {
                    throw GalleryException(GalleryFailure.JOURNAL, error)
                }
            }
        }

    override suspend fun pending(uid: String): List<GalleryJournalEntry> = locked {
        read().filter { it.accountHash == GalleryContract.accountHash(uid) }
    }

    override suspend fun put(
        uid: String,
        entry: GalleryJournalEntry,
        expected: GalleryJournalEntry?,
    ): GalleryJournalEntry = locked {
        if (entry.accountHash != GalleryContract.accountHash(uid))
            GalleryContract.fail(GalleryFailure.JOURNAL)
        val all = read()
        val old = all.firstOrNull {
            it.accountHash == entry.accountHash && it.target == entry.target
        }
        if (old != expected) GalleryContract.fail(GalleryFailure.JOURNAL)
        write(all.filterNot { it == old } + entry)
        entry
    }

    override suspend fun clear(uid: String, expected: GalleryJournalEntry) = locked {
        if (expected.accountHash != GalleryContract.accountHash(uid))
            GalleryContract.fail(GalleryFailure.JOURNAL)
        val all = read()
        if (
            all.firstOrNull {
                it.accountHash == expected.accountHash && it.target == expected.target
            } != expected
        )
            GalleryContract.fail(GalleryFailure.JOURNAL)
        write(all.filterNot { it == expected })
    }
}

object LocalGalleryJournal {
    @Volatile private var instance: GalleryJournal? = null

    fun get(context: Context): GalleryJournal {
        LocalEnvironment.requireSafe()
        require(context.applicationContext.packageName == "at.uac.android.local")
        return instance
            ?: synchronized(this) {
                instance
                    ?: FileGalleryJournal(
                            File(
                                context.applicationContext.noBackupFilesDir,
                                "organization-gallery",
                            )
                        )
                        .also { instance = it }
            }
    }
}
