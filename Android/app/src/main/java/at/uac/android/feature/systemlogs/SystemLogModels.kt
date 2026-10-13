package at.uac.android.feature.systemlogs

import java.time.Instant

enum class SystemLogAccess { OWNER, APP_ADMIN }
enum class SystemLogSort { NEWEST, OLDEST, SEVERITY_HIGH, SEVERITY_LOW, CATEGORY }
enum class SystemLogQuickFilter { UNREVIEWED, CRITICAL, TODAY, SEVEN_DAYS }

data class SystemLogEntry(
    val id: String,
    val createdAt: Instant,
    val category: String,
    val severity: String,
    val severityRank: Int,
    val eventType: String,
    val actorUserId: String?,
    val actorDisplayName: String?,
    val actorRole: String,
    val targetType: String,
    val targetId: String?,
    val targetTitle: String?,
    val organizationId: String?,
    val organizationName: String?,
    val outcome: String?,
    val summary: String,
    val technicalMessage: String?,
    val errorCode: String?,
    val moduleName: String?,
    val screenName: String?,
    val operationName: String?,
    val appVersion: String?,
    val osVersion: String?,
    val deviceModel: String?,
    val reviewed: Boolean,
    val reviewedAt: Instant?,
    val reviewedBy: String?,
    val metadata: Map<String, String>,
    val retentionPolicy: String?,
    val correlationId: String?,
    val appAdminReadable: Boolean,
) {
    val retentionDays: Long? get() = when (retentionPolicy) {
        "normalAudit" -> 365; "technicalError" -> 90; "security" -> 730; "moderationDispute" -> 1095; else -> null
    }
    val retentionUntil: Instant? get() = retentionDays?.let { createdAt.plusSeconds(it * 86_400) }
}

data class SystemLogMetrics(val unreviewed: Int, val critical: Int, val errors: Int, val security: Int, val moderation: Int)

data class TestPushReceipt(val targetCount: Int, val successCount: Int, val failureCount: Int)

enum class SystemLogFailure { ACCESS, INVALID, OFFLINE, MISSING, CONFLICT, UNCONFIRMED, BUSY }
class SystemLogException(val failure: SystemLogFailure, cause: Throwable? = null) : Exception(failure.name, cause)

data class SystemLogsState(
    val principal: Pair<String, Long>? = null,
    val access: SystemLogAccess? = null,
    val loading: Boolean = false,
    val logs: List<SystemLogEntry> = emptyList(),
    val selectedId: String? = null,
    val search: String = "",
    val category: String? = null,
    val severity: String? = null,
    val review: Boolean? = null,
    val quick: Set<SystemLogQuickFilter> = emptySet(),
    val sort: SystemLogSort = SystemLogSort.NEWEST,
    val mutating: Boolean = false,
    val failure: SystemLogFailure? = null,
    val unconfirmedAction: String? = null,
    val pushReceipt: TestPushReceipt? = null,
)
