package at.uac.android.core

import android.content.Context
import android.util.AtomicFile
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileNotFoundException
import java.security.MessageDigest
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

enum class DeletionJournalStatus {
    PENDING,
    PARTIAL,
}

data class DeletionJournalEntry(
    val accountHash: String,
    val submittedAt: Instant,
    val status: DeletionJournalStatus = DeletionJournalStatus.PENDING,
)

/**
 * No passwords, tokens, email, raw UID or content. Pending records do not expire or disappear on
 * sign-out.
 */
interface AccountDeletionJournal {
    suspend fun pending(uid: String): DeletionJournalEntry?

    suspend fun record(uid: String, submittedAt: Instant): DeletionJournalEntry

    suspend fun markPartial(uid: String, expectedSubmittedAt: Instant): DeletionJournalEntry?

    suspend fun clearConfirmed(uid: String, expectedSubmittedAt: Instant): Boolean
}

object DeletionJournalCodec {
    private const val MAGIC = 0x55414344
    const val MAX_BYTES = 256

    fun accountHash(uid: String): String {
        require(
            uid.isNotBlank() &&
                uid.length <= 128 &&
                uid == uid.trim() &&
                uid.none(Char::isISOControl)
        )
        return MessageDigest.getInstance("SHA-256")
            .digest("uac-self-deletion-v1:$uid".toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it.toInt() and 0xff) }
    }

    fun encode(entry: DeletionJournalEntry): ByteArray {
        require(
            entry.accountHash.matches(Regex("[a-f0-9]{64}")) && entry.submittedAt.toEpochMilli() > 0
        )
        return ByteArrayOutputStream()
            .also { bytes ->
                DataOutputStream(bytes).use {
                    it.writeInt(MAGIC)
                    it.writeByte(1)
                    it.writeUTF(entry.accountHash)
                    it.writeLong(entry.submittedAt.toEpochMilli())
                    it.writeByte(entry.status.ordinal)
                }
            }
            .toByteArray()
    }

    fun decode(bytes: ByteArray, expectedHash: String): DeletionJournalEntry {
        require(bytes.size in 1..MAX_BYTES)
        return DataInputStream(ByteArrayInputStream(bytes)).use {
            require(it.readInt() == MAGIC && it.readUnsignedByte() == 1)
            val hash = it.readUTF()
            require(hash == expectedHash && hash.matches(Regex("[a-f0-9]{64}")))
            val time = it.readLong().also { millis -> require(millis > 0) }
            val status =
                DeletionJournalStatus.entries.getOrNull(it.readUnsignedByte())
                    ?: error("Invalid deletion journal status")
            require(it.read() == -1)
            DeletionJournalEntry(hash, Instant.ofEpochMilli(time), status)
        }
    }
}

/** AtomicFile is fsynced and read back before the destructive callable may be submitted. */
class FileAccountDeletionJournal(private val directory: File) : AccountDeletionJournal {
    private val mutex = Mutex()

    private fun file(uid: String) =
        AtomicFile(File(directory, "${DeletionJournalCodec.accountHash(uid)}.bin"))

    private fun read(uid: String): DeletionJournalEntry? {
        val atomic = file(uid)
        val bytes =
            try {
                atomic.openRead().use { stream ->
                    val output = ByteArrayOutputStream()
                    val buffer = ByteArray(DeletionJournalCodec.MAX_BYTES + 1)
                    while (true) {
                        val count = stream.read(buffer)
                        if (count < 0) break
                        require(output.size() + count <= DeletionJournalCodec.MAX_BYTES)
                        output.write(buffer, 0, count)
                    }
                    output.toByteArray()
                }
            } catch (error: FileNotFoundException) {
                // An existing but unreadable record is not silently treated as a new account.
                if (atomic.baseFile.exists() || File(atomic.baseFile.path + ".bak").exists())
                    throw error
                return null
            }
        return DeletionJournalCodec.decode(bytes, DeletionJournalCodec.accountHash(uid))
    }

    private fun write(uid: String, entry: DeletionJournalEntry): DeletionJournalEntry {
        check(directory.isDirectory || directory.mkdirs())
        val atomic = file(uid)
        val stream = atomic.startWrite()
        try {
            stream.write(DeletionJournalCodec.encode(entry))
            atomic.finishWrite(stream)
        } catch (error: Exception) {
            atomic.failWrite(stream)
            throw error
        }
        check(read(uid) == entry) { "Deletion checkpoint was not confirmed on disk" }
        return entry
    }

    override suspend fun pending(uid: String): DeletionJournalEntry? =
        withContext(Dispatchers.IO) { mutex.withLock { read(uid) } }

    override suspend fun record(uid: String, submittedAt: Instant): DeletionJournalEntry =
        withContext(Dispatchers.IO) {
            mutex.withLock {
                // Millisecond precision is deliberately identical before and after durable
                // read-back.
                write(
                    uid,
                    DeletionJournalEntry(
                        DeletionJournalCodec.accountHash(uid),
                        Instant.ofEpochMilli(submittedAt.toEpochMilli()),
                    ),
                )
            }
        }

    override suspend fun markPartial(
        uid: String,
        expectedSubmittedAt: Instant,
    ): DeletionJournalEntry? =
        withContext(Dispatchers.IO) {
            mutex.withLock {
                val existing = read(uid) ?: return@withLock null
                if (existing.submittedAt != expectedSubmittedAt) return@withLock existing
                write(uid, existing.copy(status = DeletionJournalStatus.PARTIAL))
            }
        }

    override suspend fun clearConfirmed(uid: String, expectedSubmittedAt: Instant): Boolean =
        withContext(Dispatchers.IO) {
            mutex.withLock {
                val existing = read(uid) ?: return@withLock true
                if (existing.submittedAt != expectedSubmittedAt) return@withLock false
                file(uid).delete()
                check(read(uid) == null) { "Confirmed deletion checkpoint could not be cleared" }
                true
            }
        }
}

object LocalAccountDeletionJournal {
    @Volatile private var value: AccountDeletionJournal? = null

    fun get(context: Context): AccountDeletionJournal {
        LocalEnvironment.requireSafe()
        check(context.applicationContext.packageName == "at.uac.android.local")
        return value
            ?: synchronized(this) {
                value
                    ?: FileAccountDeletionJournal(
                            File(
                                context.applicationContext.noBackupFilesDir,
                                "self-account-deletion",
                            )
                        )
                        .also { value = it }
            }
    }
}
