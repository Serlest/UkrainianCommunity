import Foundation

struct OwnerAnalyticsSnapshot: Codable, Equatable, Identifiable {
    let period: AnalyticsPeriod
    let generatedAt: Date
    let summaryStats: [AnalyticsSummaryStats]
    let dailyStats: [AnalyticsDailyStats]
    let topContent: [AnalyticsTopContentItem]
    let regionStats: [AnalyticsRegionStats]
    let userStats: AnalyticsUserStats
    let actionStats: AnalyticsActionStats

    var id: AnalyticsPeriod { period }

    static func empty(period: AnalyticsPeriod, generatedAt: Date = Date()) -> OwnerAnalyticsSnapshot {
        OwnerAnalyticsSnapshot(
            period: period,
            generatedAt: generatedAt,
            summaryStats: [],
            dailyStats: [],
            topContent: [],
            regionStats: [],
            userStats: .empty,
            actionStats: .empty
        )
    }
}
