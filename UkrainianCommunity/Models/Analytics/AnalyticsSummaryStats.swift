import Foundation

struct AnalyticsSummaryStats: Codable, Equatable, Identifiable {
    let metricType: AnalyticsMetricType
    let value: Int
    let previousValue: Int?

    var id: AnalyticsMetricType { metricType }

    var delta: Int? {
        guard let previousValue else { return nil }
        return value - previousValue
    }
}
