package at.uac.android.feature.userstatusmanagement

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
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * Hash-only intent/receipt data plus the contract's opaque routing targetId; never private text.
 */
object UserStatusJournalCodec {
    const val MAX_ENTRIES = UserStatusContract.MAX_PENDING
    const val MAX_BYTES = 32_768
    private const val MAGIC = 0x5541534a
    private const val SCHEMA = 1

    private fun backendBinding(): String =
        UserStatusContract.hash(
            listOf(
                    "uac-user-status-journal-v1",
                    CompiledBackend.ANDROID_PACKAGE,
                    CompiledBackend.FIREBASE_APP_NAME,
                    CompiledBackend.PROJECT_ID,
                    CompiledBackend.FIREBASE_APPLICATION_ID,
                )
                .joinToString("\u0000")
        )

    private fun validate(entries: List<UserStatusPending>) {
        require(entries.size <= MAX_ENTRIES)
        entries.forEach(UserStatusContract::validate)
        require(
            entries.map { it.accountHash to it.version.targetId }.distinct().size == entries.size
        )
        require(entries.map { it.operationId }.distinct().size == entries.size)
    }

    private fun <T> checked(action: () -> T): T =
        try {
            action()
        } catch (error: Exception) {
            throw UserStatusException(UserStatusFailure.JOURNAL, error)
        }

    fun encode(entries: List<UserStatusPending>): ByteArray = checked {
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
            text(backendBinding())
            out.writeByte(entries.size)
            entries.forEach { entry ->
                text(entry.backend, 256)
                text(entry.accountHash)
                text(entry.version.targetId, 512)
                text(entry.version.fingerprint)
                text(entry.version.previousStateHash)
                text(entry.version.preservedHash)
                text(entry.action.name, 32)
                text(entry.reasonHash)
                text(entry.messageHash)
                text(entry.desiredStateHash)
                text(entry.untilHash)
                text(entry.operationId, 36)
                text(entry.issuedRole, 8)
                text(entry.phase.name, 32)
                out.writeByte(if (entry.receipt == null) 0 else 1)
                entry.receipt?.let {
                    text(it.requestHash)
                    text(it.responseHash)
                    text(it.previousStateHash)
                    text(it.newStateHash)
                    out.writeLong(it.wireTime.epochSecond)
                    out.writeInt(it.wireTime.nano)
                }
            }
        }
        bytes.toByteArray()
    }

    fun decode(bytes: ByteArray): List<UserStatusPending> = checked {
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
            require(text() == backendBinding())
            val count = input.readUnsignedByte().also { require(it <= MAX_ENTRIES) }
            val entries =
                List(count) {
                    val backend = text(256)
                    val account = text()
                    val version = UserStatusVersion(text(512), text(), text(), text())
                    val action = UserStatusAction.valueOf(text(32))
                    val reason = text()
                    val message = text()
                    val desired = text()
                    val until = text()
                    val operation = text(36)
                    val role = text(8)
                    val phase = UserStatusPhase.valueOf(text(32))
                    val hasReceipt = input.readUnsignedByte().also { require(it in 0..1) }
                    val receipt =
                        if (hasReceipt == 1) {
                            val request = text()
                            val response = text()
                            val previous = text()
                            val next = text()
                            val seconds = input.readLong()
                            val nanos = input.readInt().also { require(it in 0..999_999_999) }
                            UserStatusReceipt(
                                request,
                                response,
                                previous,
                                next,
                                Instant.ofEpochSecond(seconds, nanos.toLong()),
                            )
                        } else null
                    UserStatusPending(
                        account,
                        version,
                        action,
                        reason,
                        message,
                        desired,
                        until,
                        operation,
                        role,
                        phase,
                        receipt,
                        backend,
                    )
                }
            require(input.read() == -1)
            validate(entries)
            entries
        }
    }
}

/**
 * One app process; all instances for the same directory share the actual read/compare/write lock.
 */
private object UserStatusJournalLocks {
    private val values = ConcurrentHashMap<String, Mutex>()

    fun forDirectory(path: String): Mutex = values.computeIfAbsent(path) { Mutex() }
}

class FileUserStatusJournal(
    directory: File,
    private val sync: (FileOutputStream) -> Unit = { it.fd.sync() },
) : UserStatusJournal {
    private val directory = directory.absoluteFile
    private val mutex = UserStatusJournalLocks.forDirectory(this.directory.canonicalPath)
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

    private fun read(): List<UserStatusPending> {
        requirePaths()
        if (!exists(base)) return emptyList()
        require(base.length() in 1..UserStatusJournalCodec.MAX_BYTES.toLong())
        val bytes =
            atomic.openRead().use { input ->
                val output = ByteArrayOutputStream()
                val buffer = ByteArray(4096)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    require(count <= UserStatusJournalCodec.MAX_BYTES - output.size())
                    output.write(buffer, 0, count)
                }
                output.toByteArray()
            }
        return UserStatusJournalCodec.decode(bytes)
    }

    private fun write(entries: List<UserStatusPending>) {
        val bytes = UserStatusJournalCodec.encode(entries)
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
                    throw UserStatusException(UserStatusFailure.JOURNAL, error)
                }
            }
        }

    override suspend fun pending(uid: String): List<UserStatusPending> = locked {
        val owner = UserStatusContract.accountHash(uid)
        read().filter { it.accountHash == owner }
    }

    override suspend fun put(
        uid: String,
        entry: UserStatusPending,
        expected: UserStatusPending?,
    ): UserStatusPending = locked {
        require(entry.accountHash == UserStatusContract.accountHash(uid))
        UserStatusContract.validate(entry)
        expected?.let {
            UserStatusContract.validate(it)
            require(
                it.accountHash == entry.accountHash && it.version.targetId == entry.version.targetId
            )
        }
        val all = read()
        val old = all.firstOrNull {
            it.accountHash == entry.accountHash && it.version.targetId == entry.version.targetId
        }
        require(old == expected)
        if (old == null) require(entry.phase == UserStatusPhase.PREPARED)
        else
            require(
                entry.copy(phase = old.phase, receipt = old.receipt) == old &&
                    (old.phase == UserStatusPhase.PREPARED &&
                        entry.phase == UserStatusPhase.DISPATCHED ||
                        old.phase == UserStatusPhase.DISPATCHED &&
                            entry.phase == UserStatusPhase.ACKNOWLEDGED)
            )
        write(all.filterNot { it == old } + entry)
        entry
    }

    override suspend fun clear(uid: String, expected: UserStatusPending) = locked {
        require(expected.accountHash == UserStatusContract.accountHash(uid))
        UserStatusContract.validate(expected)
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

object LocalUserStatusJournal {
    @Volatile private var instance: UserStatusJournal? = null
    @Volatile private var boundDirectory: File? = null

    fun get(context: Context): UserStatusJournal =
        synchronized(this) {
            val app = context.applicationContext
            CompiledBackend.configuration.requireAndroidPackage(app.packageName)
            val directory = File(app.noBackupFilesDir, "user-status-recovery").canonicalFile
            require(boundDirectory == null || boundDirectory == directory)
            instance
                ?: FileUserStatusJournal(directory).also {
                    boundDirectory = directory
                    instance = it
                }
        }
}
