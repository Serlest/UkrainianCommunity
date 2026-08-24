import Foundation

struct AnalyticsDailyStats: Codable, Equatable, Identifiable {
    let date: Date
    let metrics: [AnalyticsMetricType: Int]
    let activeRegionKeys: Set<String>

    var id: Date { date }

    func value(for metricType: AnalyticsMetricType) -> Int {
        metrics[metricType, default: 0]
    }

    init(
        date: Date,
        metrics: [AnalyticsMetricType: Int],
        activeRegionKeys: Set<String> = []
    ) {
        self.date = date
        self.metrics = metrics
        self.activeRegionKeys = activeRegionKeys
    }
}
