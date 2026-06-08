import Foundation

struct AnalyticsRegionStats: Codable, Equatable, Identifiable {
    let regionScope: RegionScope
    let federalState: AustrianFederalState?
    let viewCount: Int
    let contentCount: Int
    let metrics: [AnalyticsMetricType: Int]

    var id: String {
        [
            regionScope.rawValue,
            federalState?.rawValue ?? "all"
        ].joined(separator: ":")
    }

    init(
        regionScope: RegionScope,
        federalState: AustrianFederalState?,
        viewCount: Int,
        contentCount: Int,
        metrics: [AnalyticsMetricType: Int] = [:]
    ) {
        self.regionScope = regionScope
        self.federalState = federalState
        self.viewCount = viewCount
        self.contentCount = contentCount
        self.metrics = metrics
    }
}
