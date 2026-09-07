package at.uac.android.feature.systemlogs

import at.uac.android.core.LocalCallableProtocol
import at.uac.android.feature.moderation.ModerationSession
import java.util.Locale

object SystemLogContract {
    val categories = setOf("authentication", "authorization", "audit", "moderation", "content", "organization", "userAccount", "configuration", "notification", "dataIntegrity", "diagnostics", "unknown")
    val severities = listOf("debug", "info", "notice", "warning", "error", "critical")
    val retention = setOf("normalAudit", "technicalError", "security", "moderationDispute")

    fun access(session: ModerationSession?): SystemLogAccess {
        if (session == null || !session.ready || !id(session.uid)) fail(SystemLogFailure.ACCESS)
        return when (session.role) { "owner" -> SystemLogAccess.OWNER; "admin" -> SystemLogAccess.APP_ADMIN; else -> fail(SystemLogFailure.ACCESS) }
    }

    fun id(value: String): Boolean = value.length in 1..200 && value.trim() == value && !value.contains('/') && value.none(Char::isISOControl)

    fun deletePayload(id: String): Map<String, String> {
        if (!id(id)) fail(SystemLogFailure.INVALID)
        return mapOf("logId" to id).also(LocalCallableProtocol::request)
    }

    fun clearPayload(): Map<String, Any?> = emptyMap<String, Any?>().also(LocalCallableProtocol::request)

    fun deleted(data: Any?, expected: Int? = null): Int {
        val map = data as? Map<*, *> ?: fail(SystemLogFailure.UNCONFIRMED)
        if (map.keys != setOf("deletedCount")) fail(SystemLogFailure.UNCONFIRMED)
        val count = (map["deletedCount"] as? Number)?.toInt() ?: fail(SystemLogFailure.UNCONFIRMED)
        if (count < 0 || expected != null && count != expected) fail(SystemLogFailure.UNCONFIRMED)
        return count
    }

    fun pushReceipt(data: Any?): TestPushReceipt {
        val map = data as? Map<*, *> ?: fail(SystemLogFailure.UNCONFIRMED)
        if (map.keys != setOf("targetCount", "successCount", "failureCount")) fail(SystemLogFailure.UNCONFIRMED)
        val target = (map["targetCount"] as? Number)?.toInt() ?: fail(SystemLogFailure.UNCONFIRMED)
        val success = (map["successCount"] as? Number)?.toInt() ?: fail(SystemLogFailure.UNCONFIRMED)
        val failure = (map["failureCount"] as? Number)?.toInt() ?: fail(SystemLogFailure.UNCONFIRMED)
        if (target < 1 || success < 1 || failure < 0 || success + failure != target) fail(SystemLogFailure.UNCONFIRMED)
        return TestPushReceipt(target, success, failure)
    }

    fun metrics(logs: List<SystemLogEntry>) = SystemLogMetrics(
        logs.count { !it.reviewed }, logs.count { it.severity == "critical" },
        logs.count { it.category == "diagnostics" || it.severityRank >= 4 },
        logs.count { it.retentionPolicy == "security" || it.category == "authorization" },
        logs.count { it.category == "moderation" || it.retentionPolicy == "moderationDispute" },
    )

    fun sanitize(key: String, value: String, maximum: Int = 300): String {
        val normalized = key.replace("_", "").replace("-", "").replace(" ", "").lowercase(Locale.ROOT)
        val blocked = setOf("password", "passcode", "token", "authorization", "authheader", "secret", "apikey", "privatemessage", "messagebody", "rawcontent", "fulladdress", "streetaddress")
        val text = value.trim()
        val tokenLike = text.lowercase(Locale.ROOT).let { it.startsWith("bearer ") || it.startsWith("basic ") || it.startsWith("eyj") || it.startsWith("sk_") } || text.split('.').let { it.size == 3 && it.all { part -> part.length >= 10 } } || text.length >= 48 && text.none(Char::isWhitespace)
        if (blocked.any(normalized::contains) || tokenLike) return "[redacted]"
        return if (text.length <= maximum) text else text.take(maximum) + " [truncated]"
    }

    fun fail(failure: SystemLogFailure): Nothing = throw SystemLogException(failure)
}
