import Foundation

enum OwnerAnalyticsDataSource: String, Codable, CaseIterable, Hashable {
    case topContent
    case contentRegions
    case users
}

struct OwnerAnalyticsSnapshot: Codable, Equatable, Identifiable {
    let period: AnalyticsPeriod
    let generatedAt: Date?
    let summaryStats: [AnalyticsSummaryStats]
    let dailyStats: [AnalyticsDailyStats]
    let topContent: [AnalyticsTopContentItem]
    let regionStats: [AnalyticsRegionStats]
    let userStats: AnalyticsUserStats
    let actionStats: AnalyticsActionStats
    let unavailableSources: Set<OwnerAnalyticsDataSource>

    var id: AnalyticsPeriod { period }

    init(
        period: AnalyticsPeriod,
        generatedAt: Date?,
        summaryStats: [AnalyticsSummaryStats],
        dailyStats: [AnalyticsDailyStats],
        topContent: [AnalyticsTopContentItem],
        regionStats: [AnalyticsRegionStats],
        userStats: AnalyticsUserStats,
        actionStats: AnalyticsActionStats,
        unavailableSources: Set<OwnerAnalyticsDataSource> = []
    ) {
        self.period = period
        self.generatedAt = generatedAt
        self.summaryStats = summaryStats
        self.dailyStats = dailyStats
        self.topContent = topContent
        self.regionStats = regionStats
        self.userStats = userStats
        self.actionStats = actionStats
        self.unavailableSources = unavailableSources
    }

    static func empty(
        period: AnalyticsPeriod,
        generatedAt: Date? = nil,
        unavailableSources: Set<OwnerAnalyticsDataSource> = []
    ) -> OwnerAnalyticsSnapshot {
        OwnerAnalyticsSnapshot(
            period: period,
            generatedAt: generatedAt,
            summaryStats: [],
            dailyStats: [],
            topContent: [],
            regionStats: [],
            userStats: .empty,
            actionStats: .empty,
            unavailableSources: unavailableSources
        )
    }
}
