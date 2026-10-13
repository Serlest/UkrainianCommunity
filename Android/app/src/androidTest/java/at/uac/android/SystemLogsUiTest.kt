package at.uac.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import at.uac.android.feature.moderation.ModerationSession
import at.uac.android.feature.systemlogs.*
import java.time.Instant
import org.junit.Rule
import org.junit.Test

class SystemLogsUiTest {
    @get:Rule val compose = createComposeRule()

    @Test fun ownerGetsMetricsDetailAndDestructiveDiagnostics() {
        val owner = ModerationSession("owner", 1, "owner", true)
        val model = model(owner)
        compose.setContent { SystemLogsScreen(model, owner, "de", {}) }
        compose.waitUntil(5_000) { !model.state.value.loading && model.state.value.logs.isNotEmpty() }
        compose.onNodeWithTag("system-log-metric-critical").assertIsDisplayed()
        compose.onNodeWithTag("system-log-list").performScrollToNode(hasTestTag("system-log-test-push"))
        compose.onNodeWithTag("system-log-test-push").assertIsDisplayed()
        compose.onNodeWithTag("system-log-list").performScrollToNode(hasTestTag("system-log-row-log-1"))
        compose.onNodeWithTag("system-log-row-log-1").performClick()
        compose.onNodeWithTag("system-log-detail").assertIsDisplayed()
        compose.onNodeWithTag("system-log-detail").performScrollToNode(hasTestTag("system-log-review"))
        compose.onNodeWithTag("system-log-review").assertIsDisplayed()
        compose.onNodeWithTag("system-log-detail").performScrollToNode(hasTestTag("system-log-delete"))
        compose.onNodeWithTag("system-log-delete").assertIsDisplayed()
    }

    @Test fun scopedAdminCannotSeeOwnerOperations() {
        val admin = ModerationSession("admin", 2, "admin", true)
        val model = model(admin)
        compose.setContent { SystemLogsScreen(model, admin, "uk", {}) }
        compose.waitUntil(5_000) { !model.state.value.loading }
        compose.onAllNodesWithTag("system-log-test-push").assertCountEquals(0)
        compose.onAllNodesWithTag("system-log-clear").assertCountEquals(0)
    }

    private fun model(session: ModerationSession): SystemLogsViewModel {
        val log =
            SystemLogEntry(
                id = "log-1",
                createdAt = Instant.parse("2026-09-07T00:00:00Z"),
                category = "diagnostics",
                severity = "critical",
                severityRank = 5,
                eventType = "technicalError",
                actorUserId = null,
                actorDisplayName = "System",
                actorRole = "system",
                targetType = "diagnosticSnapshot",
                targetId = null,
                targetTitle = "Snapshot",
                organizationId = null,
                organizationName = null,
                outcome = "failed",
                summary = "Diagnostic",
                technicalMessage = "safe",
                errorCode = null,
                moduleName = "Module",
                screenName = null,
                operationName = "operation",
                appVersion = "1.0.2",
                osVersion = "Android",
                deviceModel = "Emulator",
                reviewed = false,
                reviewedAt = null,
                reviewedBy = null,
                metadata = mapOf("token" to "[redacted]"),
                retentionPolicy = "technicalError",
                correlationId = null,
                appAdminReadable = true,
            )
        val source = object : SystemLogSource {
            override suspend fun list(session: ModerationSession, access: SystemLogAccess, sort: SystemLogSort) = listOf(log)
            override suspend fun find(session: ModerationSession, access: SystemLogAccess, id: String) = log
            override suspend fun review(session: ModerationSession, expected: SystemLogEntry) = expected.copy(reviewed = true, reviewedBy = session.uid)
            override suspend fun delete(session: ModerationSession, expected: SystemLogEntry) = 1
            override suspend fun clear(session: ModerationSession) = 1
            override suspend fun testPush(session: ModerationSession) = TestPushReceipt(1, 1, 0)
        }
        return SystemLogsViewModel(SystemLogRepository(source, authority = { session }))
    }
}
