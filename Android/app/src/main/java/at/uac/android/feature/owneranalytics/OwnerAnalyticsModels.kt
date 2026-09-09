package at.uac.android.feature.owneranalytics

import at.uac.android.feature.auth.AuthSession
import java.time.Instant

enum class AnalyticsPeriod(val documentId: String, val days: Int) {
    TODAY("today", 1),
    SEVEN_DAYS("seven_days", 7),
    THIRTY_DAYS("thirty_days", 30),
}

data class OwnerAnalyticsSession(val uid: String, val revision: Long, val ready: Boolean)

fun AuthSession.ownerAnalyticsScope(): OwnerAnalyticsSession? {
    val actor = identity?.takeUnless { it.anonymous } ?: return null
    val owner = profile?.takeIf { it.uid == actor.uid && it.globalRole == "owner" } ?: return null
    return OwnerAnalyticsSession(
        actor.uid,
        revision,
        readyForActions && owner.active && owner.requiresMultiFactorAuth && totpAuthenticated,
    )
}

enum class OwnerAnalyticsFailure {
    ACCESS,
    OFFLINE,
    INVALID,
    REFRESHING,
}

class OwnerAnalyticsException(val failure: OwnerAnalyticsFailure, cause: Throwable? = null) :
    Exception(failure.name, cause)

data class AnalyticsTopItem(
    val id: String,
    val type: String,
    val title: String,
    val views: Int,
    val rank: Int,
    val organizationId: String? = null,
)

data class AnalyticsRegion(
    val id: String,
    val scope: String,
    val federalState: String?,
    val views: Int,
    val contentCount: Int,
    val metrics: Map<String, Int>,
)

data class AnalyticsUsers(
    val total: Int = 0,
    val newRegistrations: Int = 0,
    val deleted: Int = 0,
    val blocked: Int = 0,
    val deactivated: Int = 0,
    val activeToday: Int = 0,
    val activeSevenDays: Int = 0,
    val activeThirtyDays: Int = 0,
    val byFederalState: Map<String, Int> = emptyMap(),
)

data class OwnerAnalyticsSnapshot(
    val period: AnalyticsPeriod,
    val generatedAt: Instant?,
    val metrics: Map<String, Int>,
    val previousMetrics: Map<String, Int>,
    val daily: List<Pair<String, Map<String, Int>>>,
    val top: List<AnalyticsTopItem>,
    val regions: List<AnalyticsRegion>,
    val users: AnalyticsUsers,
    val unavailable: Set<String> = emptySet(),
) {
    val hasData: Boolean
        get() =
            metrics.values.any { it > 0 } ||
                top.isNotEmpty() ||
                regions.isNotEmpty() ||
                users != AnalyticsUsers()
}

data class AnalyticsDetail(
    val type: String,
    val id: String,
    val title: String,
    val period: AnalyticsPeriod,
    val metrics: Map<String, Int>,
    val regions: List<AnalyticsRegion>,
    val topNews: List<AnalyticsTopItem> = emptyList(),
    val topEvents: List<AnalyticsTopItem> = emptyList(),
    val updatedAt: Instant? = null,
    val partialSince: String? = null,
) {
    val hasData: Boolean
        get() =
            metrics.values.any { it > 0 } ||
                regions.isNotEmpty() ||
                topNews.isNotEmpty() ||
                topEvents.isNotEmpty()
}
