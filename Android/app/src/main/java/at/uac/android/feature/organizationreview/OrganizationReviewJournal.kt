package at.uac.android.feature.organizationreview

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

/** Only identifiers and hashes, never message/reason/body/contacts or auth secrets. */
object OrganizationReviewJournalCodec {
    const val MAX_ENTRIES = 16
    const val MAX_BYTES = 32_768
    private const val MAGIC = 0x55414352

    fun validate(entries: List<OrganizationReviewPending>) {
        require(entries.size <= MAX_ENTRIES)
        entries.forEach(OrganizationReviewContract::validate)
        require(
            entries.map { it.accountHash to it.version.organizationId }.distinct().size ==
                entries.size
        )
        require(entries.map { it.operationId }.distinct().size == entries.size)
    }

    fun encode(entries: List<OrganizationReviewPending>): ByteArray {
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
                        out.writeUTF(entry.version.organizationId)
                        out.writeUTF(entry.version.fingerprint)
                        out.writeUTF(entry.version.preservedApprovalHash)
                        out.writeUTF(entry.version.preservedOtherHash)
                        out.writeUTF(entry.version.submitterHash)
                        out.writeUTF(entry.action.name)
                        out.writeUTF(entry.textHash)
                        out.writeUTF(entry.operationId)
                        out.writeUTF(entry.issuedRole)
                        out.writeUTF(entry.phase.name)
                        out.writeBoolean(entry.receipt != null)
                        entry.receipt?.let {
                            out.writeUTF(it.notificationDigest)
                            out.writeLong(it.wireTime.epochSecond)
                            out.writeInt(it.wireTime.nano)
                        }
                    }
                }
            }
            .toByteArray()
            .also { require(it.size <= MAX_BYTES) }
    }

    fun decode(bytes: ByteArray): List<OrganizationReviewPending> {
        require(bytes.size in 1..MAX_BYTES)
        return DataInputStream(ByteArrayInputStream(bytes)).use { input ->
            require(input.readInt() == MAGIC && input.readUnsignedByte() == 1)
            val count = input.readUnsignedByte().also { require(it <= MAX_ENTRIES) }
            List(count) {
                    val backend = input.readUTF()
                    val account = input.readUTF()
                    val version =
                        OrganizationReviewVersion(
                            input.readUTF(),
                            input.readUTF(),
                            input.readUTF(),
                            input.readUTF(),
                            input.readUTF(),
                        )
                    val action = OrganizationReviewAction.valueOf(input.readUTF())
                    val text = input.readUTF()
                    val operation = input.readUTF()
                    val role = input.readUTF()
                    val phase = OrganizationReviewPhase.valueOf(input.readUTF())
                    val receipt =
                        if (input.readBoolean()) {
                            val id = input.readUTF()
                            val seconds = input.readLong()
                            val nanos = input.readInt().also { require(it in 0..999_999_999) }
                            OrganizationReviewReceipt(
                                id,
                                Instant.ofEpochSecond(seconds, nanos.toLong()),
                            )
                        } else null
                    OrganizationReviewPending(
                        account,
                        version,
                        action,
                        text,
                        operation,
                        role,
                        phase,
                        receipt,
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

class FileOrganizationReviewJournal(
    private val directory: File,
    private val sync: (FileOutputStream) -> Unit = { it.fd.sync() },
) : OrganizationReviewJournal {
    private val mutex = Mutex()
    private val file
        get() = AtomicFile(File(directory, "pending.bin"))

    private fun read(): List<OrganizationReviewPending> {
        val bytes =
            try {
                file.openRead().use { input ->
                    val output = ByteArrayOutputStream()
                    val buffer = ByteArray(4096)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        require(count <= OrganizationReviewJournalCodec.MAX_BYTES - output.size())
                        output.write(buffer, 0, count)
                    }
                    output.toByteArray()
                }
            } catch (error: FileNotFoundException) {
                if (listOf("", ".new", ".bak").any { File(file.baseFile.path + it).exists() })
                    throw error
                return emptyList()
            }
        return OrganizationReviewJournalCodec.decode(bytes)
    }

    private fun write(entries: List<OrganizationReviewPending>) {
        val bytes = OrganizationReviewJournalCodec.encode(entries)
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
                    throw OrganizationReviewException(OrganizationReviewFailure.JOURNAL, error)
                }
            }
        }

    override suspend fun pending(uid: String) = locked {
        read().filter { it.accountHash == OrganizationReviewContract.accountHash(uid) }
    }

    override suspend fun put(
        uid: String,
        entry: OrganizationReviewPending,
        expected: OrganizationReviewPending?,
    ): OrganizationReviewPending = locked {
        require(entry.accountHash == OrganizationReviewContract.accountHash(uid))
        OrganizationReviewContract.validate(entry)
        val all = read()
        val old = all.firstOrNull {
            it.accountHash == entry.accountHash &&
                it.version.organizationId == entry.version.organizationId
        }
        require(old == expected)
        if (old == null) require(entry.phase == OrganizationReviewPhase.PREPARED)
        else
            require(
                entry.copy(phase = old.phase, receipt = old.receipt) == old &&
                    (old.phase == OrganizationReviewPhase.PREPARED &&
                        entry.phase == OrganizationReviewPhase.DISPATCHED ||
                        old.phase == OrganizationReviewPhase.DISPATCHED &&
                            entry.phase == OrganizationReviewPhase.ACKNOWLEDGED)
            )
        write(all.filterNot { it == old } + entry)
        entry
    }

    override suspend fun clear(uid: String, expected: OrganizationReviewPending) = locked {
        require(expected.accountHash == OrganizationReviewContract.accountHash(uid))
        val all = read()
        require(
            all.firstOrNull {
                it.accountHash == expected.accountHash &&
                    it.version.organizationId == expected.version.organizationId
            } == expected
        )
        write(all.filterNot { it == expected })
    }
}

object LocalOrganizationReviewJournal {
    @Volatile private var instance: OrganizationReviewJournal? = null

    fun get(context: Context): OrganizationReviewJournal =
        instance
            ?: synchronized(this) {
                instance
                    ?: FileOrganizationReviewJournal(
                            File(
                                context.applicationContext.noBackupFilesDir,
                                "organization-review-recovery",
                            )
                        )
                        .also { instance = it }
            }
}
