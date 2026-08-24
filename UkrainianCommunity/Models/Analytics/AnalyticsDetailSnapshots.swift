import Foundation

struct AnalyticsDetailCoverage: Codable, Equatable {
    let startsAt: Date?
    let isPartial: Bool

    static let complete = AnalyticsDetailCoverage(startsAt: nil, isPartial: false)
}

struct AnalyticsContentDetailSnapshot: Codable, Equatable, Identifiable {
    let period: AnalyticsPeriod
    let contentID: String
    let contentType: AnalyticsContentType
    let title: String
    let organizationID: String?
    let organizationName: String?
    let category: String?
    let federalState: AustrianFederalState?
    let regionScope: RegionScope?
    let metrics: AnalyticsContentDetailMetrics
    let regions: [AnalyticsDetailRegionStats]
    let updatedAt: Date?
    var coverage: AnalyticsDetailCoverage? = nil

    var resolvedCoverage: AnalyticsDetailCoverage { coverage ?? .complete }

    var id: String { "\(period.rawValue):\(contentType.rawValue):\(contentID)" }
    var hasData: Bool { metrics.hasData || !regions.isEmpty }

    static func empty(
        period: AnalyticsPeriod,
        contentID: String,
        contentType: AnalyticsContentType,
        coverage: AnalyticsDetailCoverage = .complete
    ) -> AnalyticsContentDetailSnapshot {
        AnalyticsContentDetailSnapshot(
            period: period,
            contentID: contentID,
            contentType: contentType,
            title: "",
            organizationID: nil,
            organizationName: nil,
            category: nil,
            federalState: nil,
            regionScope: nil,
            metrics: .empty,
            regions: [],
            updatedAt: nil,
            coverage: coverage
        )
    }
}

struct AnalyticsContentDetailMetrics: Codable, Equatable {
    let views: Int
    let likes: Int
    let bookmarks: Int
    let registrations: Int
    let cancelledRegistrations: Int
    let follows: Int
    let unfollows: Int

    var hasData: Bool {
        views > 0
            || likes > 0
            || bookmarks > 0
            || registrations > 0
            || cancelledRegistrations > 0
            || follows > 0
            || unfollows > 0
    }

    static let empty = AnalyticsContentDetailMetrics(
        views: 0,
        likes: 0,
        bookmarks: 0,
        registrations: 0,
        cancelledRegistrations: 0,
        follows: 0,
        unfollows: 0
    )
}

struct AnalyticsOrganizationDetailSnapshot: Codable, Equatable, Identifiable {
    let period: AnalyticsPeriod
    let organizationID: String
    let organizationName: String?
    let federalState: AustrianFederalState?
    let regionScope: RegionScope?
    let metrics: AnalyticsOrganizationDetailMetrics
    let topNews: [AnalyticsOrganizationTopContentItem]
    let topEvents: [AnalyticsOrganizationTopContentItem]
    let regions: [AnalyticsDetailRegionStats]
    let updatedAt: Date?
    var coverage: AnalyticsDetailCoverage? = nil

    var resolvedCoverage: AnalyticsDetailCoverage { coverage ?? .complete }

    var id: String { "\(period.rawValue):\(organizationID)" }
    var hasData: Bool { metrics.hasData || !topNews.isEmpty || !topEvents.isEmpty || !regions.isEmpty }

    static func empty(
        period: AnalyticsPeriod,
        organizationID: String,
        coverage: AnalyticsDetailCoverage = .complete
    ) -> AnalyticsOrganizationDetailSnapshot {
        AnalyticsOrganizationDetailSnapshot(
            period: period,
            organizationID: organizationID,
            organizationName: nil,
            federalState: nil,
            regionScope: nil,
            metrics: .empty,
            topNews: [],
            topEvents: [],
            regions: [],
            updatedAt: nil,
            coverage: coverage
        )
    }
}

struct AnalyticsOrganizationDetailMetrics: Codable, Equatable {
    let profileViews: Int
    let follows: Int
    let unfollows: Int
    let bookmarks: Int
    let newsViews: Int
    let eventViews: Int
    let eventRegistrations: Int

    var hasData: Bool {
        profileViews > 0
            || follows > 0
            || unfollows > 0
            || bookmarks > 0
            || newsViews > 0
            || eventViews > 0
            || eventRegistrations > 0
    }

    static let empty = AnalyticsOrganizationDetailMetrics(
        profileViews: 0,
        follows: 0,
        unfollows: 0,
        bookmarks: 0,
        newsViews: 0,
        eventViews: 0,
        eventRegistrations: 0
    )
}

struct AnalyticsDetailRegionStats: Codable, Equatable, Identifiable {
    let regionScope: RegionScope
    let federalState: AustrianFederalState?
    let metrics: [String: Int]

    nonisolated var id: String { "\(regionScope.rawValue):\(federalState?.rawValue ?? "all")" }
    nonisolated var viewCount: Int {
        ["views", "profileViews", "newsViews", "eventViews"]
            .map { metrics[$0, default: 0] }
            .reduce(0, +)
    }

    nonisolated var trackedSignalCount: Int {
        metrics.values
            .filter { $0 > 0 }
            .reduce(0, +)
    }

    nonisolated static func isOrderedByTrackedActivity(
        _ lhs: AnalyticsDetailRegionStats,
        _ rhs: AnalyticsDetailRegionStats
    ) -> Bool {
        if lhs.trackedSignalCount == rhs.trackedSignalCount {
            return lhs.id < rhs.id
        }

        return lhs.trackedSignalCount > rhs.trackedSignalCount
    }
}

struct AnalyticsOrganizationTopContentItem: Codable, Equatable, Identifiable {
    let contentID: String
    let contentType: AnalyticsContentType
    let title: String
    let category: String?
    let federalState: AustrianFederalState?
    let regionScope: RegionScope?
    let metrics: [String: Int]

    var id: String { "\(contentType.rawValue):\(contentID)" }
    var viewCount: Int { metrics["views", default: 0] }
}
