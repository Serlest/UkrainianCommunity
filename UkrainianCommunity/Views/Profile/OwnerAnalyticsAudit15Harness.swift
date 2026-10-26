#if DEBUG
import SwiftUI

/// Read-only isolated states for the analytics audit, never a production data source.
struct OwnerAnalyticsAudit15Harness: View {
    @State private var repository = OwnerAnalyticsAudit15Repository()
    var body: some View {
        Group {
            let route = ProcessInfo.processInfo.environment["UITestAnalytics15Route"] ?? "overview"
            if route == "organization" {
                AnalyticsOrganizationDetailView(repository: repository, organizationID: "org-ukrainian-center-vienna", initialTitle: "Test organization", initialPeriod: .sevenDays)
            } else if route == "news" || route == "event" {
                let item = MockOwnerAnalyticsRepository.sampleSnapshots[.sevenDays]!.topContent.first { $0.contentType.rawValue == route }!
                AnalyticsContentDetailView(repository: repository, contentID: item.contentID, contentType: item.contentType, initialTitle: item.analyticsDisplayTitle, initialPeriod: .sevenDays)
            } else {
                OwnerAnalyticsView(repository: repository)
            }
        }
    }
}
private final class OwnerAnalyticsAudit15Repository: OwnerAnalyticsRepository {
    private let source = MockOwnerAnalyticsRepository()
    private var snapshotAttempts = 0
    private var mode: String { ProcessInfo.processInfo.environment["UITestAnalytics15State"] ?? "full" }
    private func delayOrFail() async throws {
        if mode == "loading" { try await Task.sleep(for: .seconds(8)) }
        if mode == "error" { throw AppError.network }
    }
    func fetchCurrentAccountCount() async throws -> Int { mode == "empty" ? 0 : 1840 }
    func fetchBannerOverview(period: AnalyticsPeriod) async throws -> BannerMeasurementReport {
        if mode == "empty" { return .init(period: period, counts: [], generatedAt: .now) }
        return try await source.fetchBannerOverview(period: period)
    }
    func fetchSnapshot(period: AnalyticsPeriod) async throws -> OwnerAnalyticsSnapshot {
        try await delayOrFail()
        snapshotAttempts += 1
        if (mode == "retry" && snapshotAttempts == 1) || (mode == "stale" && snapshotAttempts == 2) { throw AppError.network }
        if mode == "empty" { return .empty(period: period) }
        let s = try await source.fetchSnapshot(period: period)
        if mode == "partial" {
            return .init(period: period, generatedAt: s.generatedAt, summaryStats: s.summaryStats, dailyStats: s.dailyStats,
                         topContent: [], regionStats: s.regionStats, userStats: .empty, actionStats: s.actionStats,
                         unavailableSources: [.users, .topContent])
        }
        return s
    }
    func fetchContentDetail(period: AnalyticsPeriod, contentID: String, contentType: AnalyticsContentType) async throws -> AnalyticsContentDetailSnapshot {
        try await delayOrFail()
        if mode == "empty" { return .empty(period: period, contentID: contentID, contentType: contentType) }
        return try await source.fetchContentDetail(period: period, contentID: contentID, contentType: contentType)
    }
    func fetchOrganizationDetail(period: AnalyticsPeriod, organizationID: String) async throws -> AnalyticsOrganizationDetailSnapshot {
        try await delayOrFail()
        if mode == "empty" { return .empty(period: period, organizationID: organizationID) }
        return try await source.fetchOrganizationDetail(period: period, organizationID: organizationID)
    }
}
#endif
