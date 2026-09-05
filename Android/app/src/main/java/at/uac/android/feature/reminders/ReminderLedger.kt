package at.uac.android.feature.reminders

import android.util.AtomicFile
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileNotFoundException
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

interface ReminderLedger {
    suspend fun read(): ReminderPlan

    suspend fun retire(retainClaimedOwner: String?, current: () -> Boolean)

    suspend fun replace(snapshot: ReminderSnapshot, current: () -> Boolean): ReminderPlan

    suspend fun addLocalTest(owner: String, now: Instant, current: () -> Boolean): ReminderPlan

    suspend fun finish(
        ticket: ReminderTicket,
        shown: Boolean,
        now: Instant,
        current: () -> Boolean,
    ): ReminderTicket?
}

/**
 * Binary, versioned and bounded. No UID, token, title, address, READY flag or language is
 * serialized.
 */
object ReminderLedgerCodec {
    const val MAX_BYTES = 256 * 1_024

    private fun hash(value: String) = Regex("[a-f0-9]{64}").matches(value)

    fun valid(plan: ReminderPlan): Boolean =
        (plan.owner == null) == (plan.epoch == null) &&
            (plan.owner == null || hash(plan.owner) && reminderOpaque(plan.epoch!!)) &&
            (plan.owner != null || plan.tickets.isEmpty()) &&
            plan.tickets.size <= REMINDER_MAX_EVENTS + 1 &&
            plan.receipts.size <= REMINDER_MAX_RECEIPTS &&
            plan.receipts.all { hash(it.key) } &&
            plan.receipts.map { it.key }.distinct().size == plan.receipts.size &&
            plan.tickets.map { it.token }.distinct().size == plan.tickets.size &&
            plan.tickets.map { it.key }.distinct().size == plan.tickets.size &&
            plan.tickets.all {
                reminderOpaque(it.token) &&
                    it.owner == plan.owner &&
                    it.epoch == plan.epoch &&
                    reminderId(it.eventId) &&
                    reminderId(it.occurrence.id) &&
                    it.occurrence.end >= it.occurrence.start &&
                    it.fireAt < it.occurrence.end &&
                    (it.state == ReminderTicketState.PENDING ||
                        plan.receipts.any { receipt -> receipt.key == it.key })
            }

    fun encode(plan: ReminderPlan): ByteArray {
        require(valid(plan))
        val buffer = ByteArrayOutputStream()
        DataOutputStream(buffer).use { out ->
            out.writeInt(0x55414315)
            out.writeInt(1)
            out.writeBoolean(plan.owner != null)
            if (plan.owner != null) {
                out.writeUTF(plan.owner)
                out.writeUTF(plan.epoch!!)
            }
            out.writeInt(plan.tickets.size)
            plan.tickets.forEach { ticket ->
                out.writeUTF(ticket.token)
                out.writeUTF(ticket.eventId)
                out.writeUTF(ticket.occurrence.id)
                out.instant(ticket.occurrence.start)
                out.instant(ticket.occurrence.end)
                out.instant(ticket.fireAt)
                out.writeBoolean(ticket.localTest)
                out.writeByte(ticket.state.ordinal)
            }
            out.writeInt(plan.receipts.size)
            plan.receipts.forEach {
                out.writeUTF(it.key)
                out.instant(it.retainUntil)
            }
        }
        return buffer.toByteArray().also { require(it.size <= MAX_BYTES) }
    }

    fun decode(bytes: ByteArray): ReminderPlan {
        require(bytes.size in 12..MAX_BYTES)
        return DataInputStream(ByteArrayInputStream(bytes)).use { input ->
            require(input.readInt() == 0x55414315 && input.readInt() == 1)
            val active = input.readBoolean()
            val owner = if (active) input.readUTF().also { require(hash(it)) } else null
            val epoch = if (active) input.readUTF().also { require(reminderOpaque(it)) } else null
            val count =
                input.readInt().also {
                    require(it in 0..REMINDER_MAX_EVENTS + 1 && (active || it == 0))
                }
            val tickets =
                List(count) {
                    val token = input.readUTF()
                    val event = input.readUTF()
                    val occurrence = input.readUTF()
                    val start = input.instant()
                    val end = input.instant()
                    val fire = input.instant()
                    val test = input.readBoolean()
                    val state =
                        ReminderTicketState.entries.getOrNull(input.readUnsignedByte())
                            ?: error("Invalid receipt state")
                    ReminderTicket(
                        token,
                        owner!!,
                        epoch!!,
                        event,
                        ReminderOccurrence(occurrence, start, end),
                        fire,
                        test,
                        state,
                    )
                }
            val receiptCount = input.readInt().also { require(it in 0..REMINDER_MAX_RECEIPTS) }
            val receipts = List(receiptCount) { ReminderReceipt(input.readUTF(), input.instant()) }
            require(input.read() == -1)
            ReminderPlan(owner, epoch, tickets, receipts).also { require(valid(it)) }
        }
    }

    private fun DataOutputStream.instant(value: Instant) {
        writeLong(value.epochSecond)
        writeInt(value.nano)
    }

    private fun DataInputStream.instant(): Instant =
        Instant.ofEpochSecond(readLong(), readInt().also { require(it in 0..999_999_999) }.toLong())
}

/**
 * Same reducer is tested without an Android filesystem. Every write is checked by the storage port.
 */
class TransactionalReminderLedger(
    private val load: suspend () -> ReminderPlan,
    private val save: suspend (ReminderPlan) -> Unit,
    private val opaque: () -> String = { UUID.randomUUID().toString() },
) : ReminderLedger {
    private val mutex = Mutex()

    override suspend fun read(): ReminderPlan = mutex.withLock { load() }

    private suspend fun commit(plan: ReminderPlan, current: () -> Boolean): ReminderPlan {
        if (!current()) throw ReminderException(ReminderFailure.STALE)
        if (!ReminderLedgerCodec.valid(plan)) throw ReminderException(ReminderFailure.INVALID)
        save(plan)
        if (load() != plan) throw ReminderException(ReminderFailure.STORAGE)
        if (!current()) throw ReminderException(ReminderFailure.STALE)
        return plan
    }

    override suspend fun retire(retainClaimedOwner: String?, current: () -> Boolean) {
        mutex.withLock {
            val old = load()
            val retained =
                if (old.owner != null && old.owner == retainClaimedOwner)
                    old.copy(
                        tickets = old.tickets.filter { it.state == ReminderTicketState.CLAIMED }
                    )
                else ReminderPlan(receipts = old.receipts)
            commit(retained, current)
        }
    }

    override suspend fun replace(snapshot: ReminderSnapshot, current: () -> Boolean): ReminderPlan =
        mutex.withLock {
            if (!snapshot.session.ready) throw ReminderException(ReminderFailure.NOT_READY)
            if (!snapshot.complete || snapshot.candidates.size > REMINDER_MAX_EVENTS)
                throw ReminderException(ReminderFailure.LIMIT)
            if (
                !snapshot.preferences.valid() ||
                    snapshot.candidates.map { it.eventId }.distinct().size !=
                        snapshot.candidates.size
            )
                throw ReminderException(ReminderFailure.INVALID)
            val previous = load()
            val receipts = previous.receipts.filter { it.retainUntil > snapshot.confirmedAt }
            val owner = reminderOwner(snapshot.session.uid)
            val epoch = previous.epoch?.takeIf { previous.owner == owner } ?: opaque()
            val claimed =
                previous.tickets.filter {
                    it.owner == owner &&
                        it.epoch == epoch &&
                        it.state == ReminderTicketState.CLAIMED &&
                        it.occurrence.end > snapshot.confirmedAt
                }
            val tickets =
                if (
                    !snapshot.preferences.notificationsEnabled ||
                        !snapshot.preferences.eventRemindersEnabled
                )
                    emptyList()
                else
                    snapshot.candidates
                        .map { candidate ->
                            if (candidate.fireAt <= snapshot.confirmedAt)
                                throw ReminderException(ReminderFailure.INVALID)
                            ReminderTicket(
                                opaque(),
                                owner,
                                epoch,
                                candidate.eventId,
                                candidate.occurrence,
                                candidate.fireAt,
                            )
                        }
                        .filter { ticket -> receipts.none { it.key == ticket.key } }
            if (claimed.size + tickets.size > REMINDER_MAX_EVENTS + 1)
                throw ReminderException(ReminderFailure.LIMIT)
            commit(ReminderPlan(owner, epoch, claimed + tickets, receipts), current)
        }

    override suspend fun addLocalTest(
        owner: String,
        now: Instant,
        current: () -> Boolean,
    ): ReminderPlan = mutex.withLock {
        val plan = load()
        if (plan.owner != owner || plan.epoch == null)
            throw ReminderException(ReminderFailure.NOT_READY)
        val token = opaque()
        val ticket =
            ReminderTicket(
                token,
                owner,
                plan.epoch,
                "local-test",
                ReminderOccurrence(
                    token,
                    now.plusSeconds(5),
                    now.plusSeconds(300),
                ),
                now.plusSeconds(5),
                localTest = true,
            )
        commit(plan.copy(tickets = plan.tickets.filterNot { it.localTest } + ticket), current)
    }

    override suspend fun finish(
        ticket: ReminderTicket,
        shown: Boolean,
        now: Instant,
        current: () -> Boolean,
    ): ReminderTicket? = mutex.withLock {
        val plan = load()
        if (plan.owner != ticket.owner || plan.epoch != ticket.epoch || !current())
            return@withLock null
        val existing =
            plan.tickets.singleOrNull { it.token == ticket.token } ?: return@withLock null
        if (
            existing != ticket ||
                existing.state != ReminderTicketState.PENDING ||
                now < ticket.fireAt ||
                plan.receipts.any { it.key == ticket.key }
        )
            return@withLock null
        if (shown && !ticket.due(now)) return@withLock null
        val receipts = plan.receipts.filter { it.retainUntil > now }
        if (receipts.size >= REMINDER_MAX_RECEIPTS) throw ReminderException(ReminderFailure.LIMIT)
        val completed =
            ticket.copy(
                state = if (shown) ReminderTicketState.CLAIMED else ReminderTicketState.SUPPRESSED
            )
        commit(
            plan.copy(
                tickets = plan.tickets.map { if (it.token == ticket.token) completed else it },
                receipts =
                    receipts +
                        ReminderReceipt(
                            ticket.key,
                            maxOf(ticket.occurrence.end, now).plusSeconds(30 * 86_400L),
                        ),
            ),
            current,
        )
        completed
    }
}

fun fileReminderLedger(directory: File): ReminderLedger {
    val atomic = AtomicFile(File(directory, "plan.bin"))
    suspend fun read(): ReminderPlan =
        withContext(Dispatchers.IO) {
            try {
                val bytes =
                    atomic.openRead().use { input ->
                        val result = ByteArrayOutputStream()
                        val buffer = ByteArray(4_096)
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            if (result.size() + count > ReminderLedgerCodec.MAX_BYTES)
                                throw ReminderException(ReminderFailure.STORAGE)
                            result.write(buffer, 0, count)
                        }
                        result.toByteArray()
                    }
                ReminderLedgerCodec.decode(bytes)
            } catch (error: FileNotFoundException) {
                if (atomic.baseFile.exists() || File(atomic.baseFile.path + ".bak").exists())
                    throw ReminderException(ReminderFailure.STORAGE)
                ReminderPlan()
            } catch (_: Exception) {
                throw ReminderException(ReminderFailure.STORAGE)
            }
        }
    suspend fun write(plan: ReminderPlan) =
        withContext(Dispatchers.IO) {
            try {
                check(directory.isDirectory || directory.mkdirs())
                val bytes = ReminderLedgerCodec.encode(plan)
                val stream = atomic.startWrite()
                try {
                    stream.write(bytes)
                    atomic.finishWrite(stream)
                } catch (error: Exception) {
                    atomic.failWrite(stream)
                    throw error
                }
            } catch (_: Exception) {
                throw ReminderException(ReminderFailure.STORAGE)
            }
        }
    return TransactionalReminderLedger(::read, ::write)
}
