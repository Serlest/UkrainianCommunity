import Foundation

struct AnalyticsDailyStats: Codable, Equatable, Identifiable {
    let date: Date
    let metrics: [AnalyticsMetricType: Int]

    var id: Date { date }

    func value(for metricType: AnalyticsMetricType) -> Int {
        metrics[metricType, default: 0]
    }
}
