package at.uac.android.feature.moderation

import android.content.Context
import android.util.AtomicFile
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileNotFoundException
import java.io.FileOutputStream
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

object ModerationDecisionJournalCodec {
    const val MAX_ENTRIES = 16
    const val MAX_BYTES = 16_384
    private const val MAGIC = 0x5541434d

    fun validate(entries: List<ModerationPending>) {
        require(entries.size <= MAX_ENTRIES)
        entries.forEach(ModerationDecisionContract::validate)
        require(entries.map { it.accountHash to it.version.target }.distinct().size == entries.size)
        require(entries.map { it.operationId }.distinct().size == entries.size)
    }

    fun encode(entries: List<ModerationPending>): ByteArray {
        validate(entries)
        return ByteArrayOutputStream()
            .also { bytes ->
                DataOutputStream(bytes).use { out ->
                    out.writeInt(MAGIC)
                    out.writeByte(1)
                    out.writeByte(entries.size)
                    entries.forEach { entry ->
                        out.writeUTF(entry.backend)
                        out.writeUTF(entry.accountHash)
                        out.writeUTF(entry.version.target.kind.name)
                        out.writeUTF(entry.version.target.id)
                        out.writeUTF(entry.version.organizationId)
                        out.writeUTF(entry.version.reviewHash)
                        out.writeUTF(entry.version.preservedHash)
                        out.writeLong(entry.version.updatedAt.epochSecond)
                        out.writeInt(entry.version.updatedAt.nano)
                        out.writeUTF(entry.operationId)
                        out.writeUTF(entry.issuedRole)
                        out.writeUTF(entry.decision.name)
                        out.writeLong(entry.issuedAt.epochSecond)
                        out.writeInt(entry.issuedAt.nano)
                        out.writeUTF(entry.phase.name)
                    }
                }
            }
            .toByteArray()
            .also { require(it.size <= MAX_BYTES) }
    }

    fun decode(bytes: ByteArray): List<ModerationPending> {
        require(bytes.size in 1..MAX_BYTES)
        return DataInputStream(ByteArrayInputStream(bytes)).use { input ->
            require(input.readInt() == MAGIC && input.readUnsignedByte() == 1)
            val count = input.readUnsignedByte().also { require(it <= MAX_ENTRIES) }
            fun time(): Instant {
                val seconds = input.readLong()
                val nanos = input.readInt()
                require(nanos in 0..999_999_999)
                return Instant.ofEpochSecond(seconds, nanos.toLong())
            }
            List(count) {
                    val backend = input.readUTF()
                    val account = input.readUTF()
                    val kind = ModerationKind.valueOf(input.readUTF())
                    val id = input.readUTF()
                    val org = input.readUTF()
                    val review = input.readUTF()
                    val preserved = input.readUTF()
                    val updated = time()
                    val operation = input.readUTF()
                    val role = input.readUTF()
                    val decision = ModerationDecision.valueOf(input.readUTF())
                    val issued = time()
                    ModerationPending(
                        account,
                        ModerationReviewVersion(
                            ModerationTarget(kind, id),
                            review,
                            preserved,
                            updated,
                            org,
                        ),
                        operation,
                        role,
                        decision,
                        issued,
                        ModerationDecisionPhase.valueOf(input.readUTF()),
                        backend,
                    )
                }
                .also {
                    require(input.read() == -1)
                    validate(it)
                }
        }
    }
}

class FileModerationDecisionJournal(
    private val directory: File,
    private val sync: (FileOutputStream) -> Unit = { it.fd.sync() },
) : ModerationDecisionJournal {
    private val mutex = Mutex()
    private val file
        get() = AtomicFile(File(directory, "pending.bin"))

    private fun read(): List<ModerationPending> {
        val bytes =
            try {
                file.openRead().use { input ->
                    val output = ByteArrayOutputStream()
                    val buffer = ByteArray(4096)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        require(count <= ModerationDecisionJournalCodec.MAX_BYTES - output.size())
                        output.write(buffer, 0, count)
                    }
                    output.toByteArray()
                }
            } catch (error: FileNotFoundException) {
                if (listOf("", ".new", ".bak").any { File(file.baseFile.path + it).exists() })
                    throw error
                return emptyList()
            }
        return ModerationDecisionJournalCodec.decode(bytes)
    }

    private fun write(entries: List<ModerationPending>) {
        val bytes = ModerationDecisionJournalCodec.encode(entries)
        check(directory.isDirectory || directory.mkdirs())
        val atomic = file
        val stream = atomic.startWrite()
        try {
            stream.write(bytes)
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
                } catch (error: Exception) {
                    throw ModerationDecisionException(ModerationDecisionFailure.JOURNAL, error)
                }
            }
        }

    override suspend fun pending(uid: String) = locked {
        read().filter { it.accountHash == ModerationDecisionContract.accountHash(uid) }
    }

    override suspend fun put(
        uid: String,
        entry: ModerationPending,
        expected: ModerationPending?,
    ): ModerationPending = locked {
        require(entry.accountHash == ModerationDecisionContract.accountHash(uid))
        ModerationDecisionContract.validate(entry)
        val all = read()
        val old = all.firstOrNull {
            it.accountHash == entry.accountHash && it.version.target == entry.version.target
        }
        require(old == expected)
        if (old != null)
            require(
                entry.copy(phase = old.phase) == old &&
                    (old.phase == ModerationDecisionPhase.PREPARED &&
                        entry.phase == ModerationDecisionPhase.DISPATCHED ||
                        old.phase == ModerationDecisionPhase.DISPATCHED &&
                            entry.phase == ModerationDecisionPhase.ACKNOWLEDGED)
            )
        else require(entry.phase == ModerationDecisionPhase.PREPARED)
        write(all.filterNot { it == old } + entry)
        entry
    }

    override suspend fun clear(uid: String, expected: ModerationPending) = locked {
        require(expected.accountHash == ModerationDecisionContract.accountHash(uid))
        val all = read()
        require(
            all.firstOrNull {
                it.accountHash == expected.accountHash &&
                    it.version.target == expected.version.target
            } == expected
        )
        write(all.filterNot { it == expected })
    }
}

object LocalModerationDecisionJournal {
    @Volatile private var instance: ModerationDecisionJournal? = null

    fun get(context: Context): ModerationDecisionJournal =
        instance
            ?: synchronized(this) {
                instance
                    ?: FileModerationDecisionJournal(
                            File(
                                context.applicationContext.noBackupFilesDir,
                                "content-moderation-recovery",
                            )
                        )
                        .also { instance = it }
            }
}
