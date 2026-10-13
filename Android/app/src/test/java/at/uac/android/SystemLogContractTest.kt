package at.uac.android

import at.uac.android.feature.moderation.ModerationSession
import at.uac.android.feature.systemlogs.*
import java.time.Instant
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

class SystemLogContractTest {
    private val owner = ModerationSession("owner", 1, "owner", true)

    @Test fun accessIsOwnerOrScopedAdminOnly() {
        assertEquals(SystemLogAccess.OWNER, SystemLogContract.access(owner))
        assertEquals(SystemLogAccess.APP_ADMIN, SystemLogContract.access(owner.copy(role = "admin")))
        assertFailure(SystemLogFailure.ACCESS) { SystemLogContract.access(owner.copy(role = "user")) }
    }

    @Test fun privacyPolicyRedactsSecretsAndBoundsText() {
        assertEquals("[redacted]", SystemLogContract.sanitize("refresh_token", "secret-value"))
        assertEquals("[redacted]", SystemLogContract.sanitize("note", "Bearer abc"))
        assertTrue(SystemLogContract.sanitize("safe", "safe value ".repeat(31)).endsWith(" [truncated]"))
        assertEquals("Vienna", SystemLogContract.sanitize("city", "Vienna"))
    }

    @Test fun pushAndDeleteReceiptsAreExact() {
        assertEquals(TestPushReceipt(2, 1, 1), SystemLogContract.pushReceipt(mapOf("targetCount" to 2, "successCount" to 1, "failureCount" to 1)))
        assertEquals(1, SystemLogContract.deleted(mapOf("deletedCount" to 1), 1))
        assertFailure(SystemLogFailure.UNCONFIRMED) { SystemLogContract.pushReceipt(mapOf("targetCount" to 1, "successCount" to 0, "failureCount" to 1)) }
    }

    @Test fun metricsMatchIosDefinitions() {
        val logs = listOf(entry("a", "critical", 5, "authorization", false, "security"), entry("b", "error", 4, "diagnostics", true, "technicalError"), entry("c", "info", 1, "moderation", false, "moderationDispute"))
        assertEquals(SystemLogMetrics(2, 1, 2, 1, 1), SystemLogContract.metrics(logs))
    }

    @Test fun unconfirmedDeleteIsNotReplayed() = runTest {
        val value = entry("a", "info", 1, "audit", false, "normalAudit")
        val source = FakeSource(value)
        val repo = SystemLogRepository(source, authority = { owner })
        assertSuspendFailure(SystemLogFailure.UNCONFIRMED) { repo.delete(owner, value) }
        assertEquals(1, source.deleteCalls)
        assertSuspendFailure(SystemLogFailure.UNCONFIRMED) { repo.delete(owner, value) }
        assertEquals(1, source.deleteCalls)
    }

    @Test fun processRestartReconcilesAnExactlyIdentifiedCompletedDelete() = runTest {
        val journal = MemorySystemLogMutationJournal()
        journal.write(owner.uid, SystemLogPending("delete", "a"))
        val repo =
            SystemLogRepository(
                FakeSource(null),
                authority = { owner },
                journal = journal,
            )

        assertNull(repo.reconcilePending(owner))
        assertNull(repo.pendingUnconfirmed(owner))
    }

    private class FakeSource(var value: SystemLogEntry?) : SystemLogSource {
        var deleteCalls = 0
        override suspend fun list(session: ModerationSession, access: SystemLogAccess, sort: SystemLogSort) = listOfNotNull(value)
        override suspend fun find(session: ModerationSession, access: SystemLogAccess, id: String) = value
        override suspend fun review(session: ModerationSession, expected: SystemLogEntry) = expected.copy(reviewed = true)
        override suspend fun delete(session: ModerationSession, expected: SystemLogEntry): Int { deleteCalls++; throw SystemLogException(SystemLogFailure.UNCONFIRMED) }
        override suspend fun clear(session: ModerationSession) = 0
        override suspend fun testPush(session: ModerationSession) = TestPushReceipt(1, 1, 0)
    }

    companion object {
        fun entry(
            id: String,
            severity: String,
            rank: Int,
            category: String,
            reviewed: Boolean,
            retention: String?,
        ) =
            SystemLogEntry(
                id = id,
                createdAt = Instant.parse("2026-09-07T00:00:00Z"),
                category = category,
                severity = severity,
                severityRank = rank,
                eventType = "technicalError",
                actorUserId = null,
                actorDisplayName = "Actor",
                actorRole = "system",
                targetType = "none",
                targetId = null,
                targetTitle = null,
                organizationId = null,
                organizationName = null,
                outcome = "success",
                summary = "Summary",
                technicalMessage = null,
                errorCode = null,
                moduleName = "Module",
                screenName = null,
                operationName = "operation",
                appVersion = "1.0.2",
                osVersion = "Android",
                deviceModel = "Test",
                reviewed = reviewed,
                reviewedAt = null,
                reviewedBy = null,
                metadata = mapOf("safe" to "value"),
                retentionPolicy = retention,
                correlationId = null,
                appAdminReadable = true,
            )
    }

    private fun assertFailure(reason: SystemLogFailure, block: () -> Unit) { assertEquals(reason, assertThrows(SystemLogException::class.java, block).failure) }
    private suspend fun assertSuspendFailure(reason: SystemLogFailure, block: suspend () -> Unit) { try { block(); fail("Expected $reason") } catch (error: SystemLogException) { assertEquals(reason, error.failure) } }
}
