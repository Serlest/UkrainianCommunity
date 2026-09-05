package at.uac.android.feature.feedbackdeletion

import android.content.Context
import android.util.AtomicFile
import at.uac.android.core.backend.CompiledBackend
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStream
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.NoSuchFileException
import java.nio.file.attribute.BasicFileAttributes
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/** Separate, hash-only journal except explicit canonical feedback routing ID. No private text. */
object FeedbackDeletionJournalCodec {
    const val MAX_ENTRIES = FeedbackDeletionRecovery.MAX_PENDING
    const val MAX_BYTES = 32_768
    private const val MAGIC = 0x55414644
    private const val SCHEMA = 1

    private fun validate(entries: List<FeedbackDeletionPending>) {
        require(entries.size <= MAX_ENTRIES)
        entries.forEach(FeedbackDeletionRecovery::validate)
        require(
            entries.map { it.accountHash to it.version.targetId }.distinct().size == entries.size
        )
        require(entries.map { it.operationId }.distinct().size == entries.size)
    }

    private fun <T> checked(action: () -> T): T =
        try {
            action()
        } catch (error: Exception) {
            throw FeedbackDeletionException(FeedbackDeletionFailure.JOURNAL, error)
        }

    fun encode(entries: List<FeedbackDeletionPending>): ByteArray = checked {
        validate(entries)
        val bytes = ByteArrayOutputStream()
        val limited =
            object : OutputStream() {
                override fun write(value: Int) {
                    require(bytes.size() < MAX_BYTES)
                    bytes.write(value)
                }

                override fun write(value: ByteArray, offset: Int, length: Int) {
                    require(length >= 0 && length <= MAX_BYTES - bytes.size())
                    bytes.write(value, offset, length)
                }
            }
        DataOutputStream(limited).use { out ->
            fun text(value: String, limit: Int = 64) {
                val encoded = value.toByteArray(Charsets.UTF_8)
                require(encoded.size <= limit)
                out.writeInt(encoded.size)
                out.write(encoded)
            }
            out.writeInt(MAGIC)
            out.writeByte(SCHEMA)
            text(FeedbackDeletionRecovery.backendBinding())
            out.writeByte(entries.size)
            entries.forEach { entry ->
                text(entry.backend, 256)
                text(entry.accountHash)
                text(entry.version.targetId, 800)
                text(entry.version.fingerprint)
                text(entry.operationId, 36)
                text(entry.phase.name, 32)
                out.writeByte(if (entry.receipt == null) 0 else 1)
                entry.receipt?.let {
                    text(it.requestHash)
                    text(it.responseHash)
                }
            }
        }
        bytes.toByteArray()
    }

    fun decode(bytes: ByteArray): List<FeedbackDeletionPending> = checked {
        require(bytes.size in 1..MAX_BYTES)
        DataInputStream(ByteArrayInputStream(bytes)).use { input ->
            fun text(limit: Int = 64): String {
                val size = input.readInt()
                require(size in 0..limit && size <= input.available())
                val value = ByteArray(size)
                input.readFully(value)
                return Charsets.UTF_8.newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(value))
                    .toString()
            }
            require(input.readInt() == MAGIC && input.readUnsignedByte() == SCHEMA)
            require(text() == FeedbackDeletionRecovery.backendBinding())
            val count = input.readUnsignedByte().also { require(it <= MAX_ENTRIES) }
            val entries =
                List(count) {
                    val backend = text(256)
                    val account = text()
                    val version = FeedbackDeletionVersion(text(800), text())
                    val operation = text(36)
                    val phase = FeedbackDeletionPhase.valueOf(text(32))
                    val hasReceipt = input.readUnsignedByte().also { require(it in 0..1) }
                    val receipt =
                        if (hasReceipt == 1) FeedbackDeletionReceipt(text(), text()) else null
                    FeedbackDeletionPending(account, version, operation, phase, receipt, backend)
                }
            require(input.read() == -1)
            validate(entries)
            entries
        }
    }
}

/** One process: all instances for one directory share the read/compare/write lock. */
private object FeedbackDeletionJournalLocks {
    private val values = ConcurrentHashMap<String, Mutex>()

    fun forDirectory(path: String): Mutex = values.computeIfAbsent(path) { Mutex() }
}

class FileFeedbackDeletionJournal(
    directory: File,
    private val sync: (FileOutputStream) -> Unit = { it.fd.sync() },
) : FeedbackDeletionJournal {
    private val directory = directory.absoluteFile
    private val mutex = FeedbackDeletionJournalLocks.forDirectory(this.directory.canonicalPath)
    private val base
        get() = File(directory, "pending.bin")

    private val atomic
        get() = AtomicFile(base)

    private fun exists(file: File): Boolean =
        try {
            Files.readAttributes(
                file.toPath(),
                BasicFileAttributes::class.java,
                LinkOption.NOFOLLOW_LINKS,
            )
            true
        } catch (_: NoSuchFileException) {
            false
        }

    private fun requirePaths() {
        require(directory.canonicalFile == directory && !Files.isSymbolicLink(directory.toPath()))
        require(!exists(directory) || directory.isDirectory)
        // AtomicFile.openRead can otherwise recover .bak or silently discard .new. That is not
        // evidence of durable receipt settlement, even when a valid base also exists.
        require(listOf(".new", ".bak").none { exists(File(base.path + it)) })
        require(!Files.isSymbolicLink(base.toPath()) && base.canonicalFile == base.absoluteFile)
        require(!exists(base) || base.isFile)
    }

    private fun read(): List<FeedbackDeletionPending> {
        requirePaths()
        if (!exists(base)) return emptyList()
        require(base.length() in 1..FeedbackDeletionJournalCodec.MAX_BYTES.toLong())
        val bytes =
            atomic.openRead().use { input ->
                val output = ByteArrayOutputStream()
                val buffer = ByteArray(4096)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    require(count <= FeedbackDeletionJournalCodec.MAX_BYTES - output.size())
                    output.write(buffer, 0, count)
                }
                output.toByteArray()
            }
        return FeedbackDeletionJournalCodec.decode(bytes)
    }

    private fun write(entries: List<FeedbackDeletionPending>) {
        val bytes = FeedbackDeletionJournalCodec.encode(entries)
        requirePaths()
        check(directory.isDirectory || directory.mkdirs())
        requirePaths()
        val file = atomic
        val stream = file.startWrite()
        try {
            stream.write(bytes)
            sync(stream) // Explicit fsync while open; AtomicFile may only log its own sync error.
            file.finishWrite(stream)
        } catch (error: Exception) {
            try {
                file.failWrite(stream)
            } catch (restore: Exception) {
                error.addSuppressed(restore)
            }
            throw error
        }
        check(read() == entries) // No acknowledged return without final-file read-back.
    }

    private suspend fun <T> locked(action: () -> T): T =
        withContext(Dispatchers.IO) {
            mutex.withLock {
                try {
                    action()
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Exception) {
                    throw FeedbackDeletionException(FeedbackDeletionFailure.JOURNAL, error)
                }
            }
        }

    override suspend fun pending(uid: String): List<FeedbackDeletionPending> = locked {
        val owner = FeedbackDeletionRecovery.accountHash(uid)
        read().filter { it.accountHash == owner }
    }

    override suspend fun put(
        uid: String,
        entry: FeedbackDeletionPending,
        expected: FeedbackDeletionPending?,
    ): FeedbackDeletionPending = locked {
        require(entry.accountHash == FeedbackDeletionRecovery.accountHash(uid))
        FeedbackDeletionRecovery.validate(entry)
        expected?.let {
            FeedbackDeletionRecovery.validate(it)
            require(
                it.accountHash == entry.accountHash && it.version.targetId == entry.version.targetId
            )
        }
        val all = read()
        val old = all.firstOrNull {
            it.accountHash == entry.accountHash && it.version.targetId == entry.version.targetId
        }
        require(old == expected)
        if (old == null) require(entry.phase == FeedbackDeletionPhase.PREPARED)
        else
            require(
                entry.copy(phase = old.phase, receipt = old.receipt) == old &&
                    (old.phase == FeedbackDeletionPhase.PREPARED &&
                        entry.phase == FeedbackDeletionPhase.DISPATCHED ||
                        old.phase == FeedbackDeletionPhase.DISPATCHED &&
                            entry.phase == FeedbackDeletionPhase.ACKNOWLEDGED)
            )
        write(all.filterNot { it == old } + entry)
        entry
    }

    override suspend fun clear(uid: String, expected: FeedbackDeletionPending) = locked {
        require(expected.accountHash == FeedbackDeletionRecovery.accountHash(uid))
        FeedbackDeletionRecovery.validate(expected)
        val all = read()
        require(
            all.firstOrNull {
                it.accountHash == expected.accountHash &&
                    it.version.targetId == expected.version.targetId
            } == expected
        )
        // Observation/receipt policy belongs to the repository. This never infers confirmation,
        // clears on missing readback, expires entries or discards another account's pending state.
        write(all.filterNot { it == expected })
    }
}

object LocalFeedbackDeletionJournal {
    @Volatile private var instance: FeedbackDeletionJournal? = null
    @Volatile private var boundDirectory: File? = null

    fun get(context: Context): FeedbackDeletionJournal =
        synchronized(this) {
            val app = context.applicationContext
            CompiledBackend.configuration.requireAndroidPackage(app.packageName)
            // Keep the child path unresolved so the file guard can reject a symlink.
            val directory = File(app.noBackupFilesDir.canonicalFile, "feedback-deletion-recovery")
            require(boundDirectory == null || boundDirectory == directory)
            instance
                ?: FileFeedbackDeletionJournal(directory).also {
                    boundDirectory = directory
                    instance = it
                }
        }
}
