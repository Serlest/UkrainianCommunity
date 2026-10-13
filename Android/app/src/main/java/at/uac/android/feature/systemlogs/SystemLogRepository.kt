package at.uac.android.feature.systemlogs

import at.uac.android.feature.moderation.ModerationSession
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.withContext

class SystemLogRepository(
    private val source: SystemLogSource,
    private val authority: () -> ModerationSession?,
    private val journal: SystemLogMutationJournal = MemorySystemLogMutationJournal(),
) {
    private val operations = Mutex()

    private fun ensure(session: ModerationSession): SystemLogAccess {
        val access = SystemLogContract.access(session)
        if (authority() != session) throw CancellationException("System log scope changed")
        return access
    }

    suspend fun list(session: ModerationSession, sort: SystemLogSort): List<SystemLogEntry> {
        val access = ensure(session)
        return source.list(session, access, sort).also { ensure(session) }
    }

    suspend fun review(session: ModerationSession, entry: SystemLogEntry): SystemLogEntry {
        ensure(session)
        if (entry.reviewed) return entry
        return source.review(session, entry).also { ensure(session) }
    }

    suspend fun delete(session: ModerationSession, entry: SystemLogEntry) {
        if (!operations.tryLock()) SystemLogContract.fail(SystemLogFailure.BUSY)
        try {
            if (journal.read(session.uid) != null) SystemLogContract.fail(SystemLogFailure.UNCONFIRMED)
            if (ensure(session) != SystemLogAccess.OWNER) SystemLogContract.fail(SystemLogFailure.ACCESS)
            val fresh = source.find(session, SystemLogAccess.OWNER, entry.id) ?: SystemLogContract.fail(SystemLogFailure.MISSING)
            if (fresh != entry) SystemLogContract.fail(SystemLogFailure.CONFLICT)
            journal.write(session.uid, SystemLogPending("delete", entry.id))
            try {
                withContext(NonCancellable) {
                    source.delete(session, entry)
                    if (source.find(session, SystemLogAccess.OWNER, entry.id) != null) SystemLogContract.fail(SystemLogFailure.UNCONFIRMED)
                }
                journal.clear(session.uid)
            } catch (error: SystemLogException) {
                if (error.failure != SystemLogFailure.UNCONFIRMED) { journal.clear(session.uid); throw error }
                val missing = runCatching { source.find(session, SystemLogAccess.OWNER, entry.id) == null }.getOrDefault(false)
                if (missing) journal.clear(session.uid) else throw error
            }
            ensure(session)
        } finally { operations.unlock() }
    }

    suspend fun clear(session: ModerationSession): Int {
        if (!operations.tryLock()) SystemLogContract.fail(SystemLogFailure.BUSY)
        try {
            if (journal.read(session.uid) != null) SystemLogContract.fail(SystemLogFailure.UNCONFIRMED)
            if (ensure(session) != SystemLogAccess.OWNER) SystemLogContract.fail(SystemLogFailure.ACCESS)
            journal.write(session.uid, SystemLogPending("clear"))
            return try {
                val count = withContext(NonCancellable) { source.clear(session) }
                journal.clear(session.uid)
                ensure(session)
                count
            } catch (error: SystemLogException) {
                if (error.failure != SystemLogFailure.UNCONFIRMED) journal.clear(session.uid)
                throw error
            }
        } finally { operations.unlock() }
    }

    suspend fun testPush(session: ModerationSession): TestPushReceipt {
        if (!operations.tryLock()) SystemLogContract.fail(SystemLogFailure.BUSY)
        try {
            if (journal.read(session.uid) != null) SystemLogContract.fail(SystemLogFailure.UNCONFIRMED)
            if (ensure(session) != SystemLogAccess.OWNER) SystemLogContract.fail(SystemLogFailure.ACCESS)
            journal.write(session.uid, SystemLogPending("testPush"))
            return try {
                val receipt = withContext(NonCancellable) { source.testPush(session) }
                journal.clear(session.uid)
                ensure(session)
                receipt
            } catch (error: SystemLogException) {
                if (error.failure != SystemLogFailure.UNCONFIRMED) journal.clear(session.uid)
                throw error
            }
        } finally { operations.unlock() }
    }

    suspend fun reconcilePending(session: ModerationSession): String? {
        ensure(session)
        val pending = journal.read(session.uid) ?: return null
        if (pending.action == "delete" && pending.targetId != null) {
            val current = source.find(session, SystemLogAccess.OWNER, pending.targetId)
            ensure(session)
            if (current == null) {
                journal.clear(session.uid)
                return null
            }
        }
        return pending.action
    }

    fun pendingUnconfirmed(session: ModerationSession): String? = journal.read(session.uid)?.action
    /** Explicit operator acknowledgement only. It never dispatches or retries an operation. */
    fun acknowledgeUnconfirmed(session: ModerationSession) { ensure(session); journal.clear(session.uid) }
}
