import Foundation

protocol OwnerAnalyticsRepository {
    var currentAccountCountLoadedAt: Date? { get }
    func updateAccess(user: AppUser?, state: AuthSessionState)
    func invalidateCachedReads()
    func fetchCurrentAccountCount() async throws -> Int
    func fetchBannerOverview(period: AnalyticsPeriod) async throws -> BannerMeasurementReport
    func fetchSnapshot(period: AnalyticsPeriod) async throws -> OwnerAnalyticsSnapshot
    func fetchContentDetail(
        period: AnalyticsPeriod,
        contentID: String,
        contentType: AnalyticsContentType
    ) async throws -> AnalyticsContentDetailSnapshot
    func fetchOrganizationDetail(
        period: AnalyticsPeriod,
        organizationID: String
    ) async throws -> AnalyticsOrganizationDetailSnapshot
}

extension OwnerAnalyticsRepository {
    var currentAccountCountLoadedAt: Date? { nil }
    func updateAccess(user: AppUser?, state: AuthSessionState) {}
    func invalidateCachedReads() {}
    func fetchCurrentAccountCount() async throws -> Int {
        try await RegisteredUserCountReader.fetch()
    }
    func fetchBannerOverview(period: AnalyticsPeriod) async throws -> BannerMeasurementReport {
        try await FirestoreBannerMeasurementReportRepository().fetch(period: period)
    }
}

struct OwnerAnalyticsBannerOverviewRepository: BannerMeasurementReportRepository {
    let ownerRepository: OwnerAnalyticsRepository
    func fetch(period: AnalyticsPeriod) async throws -> BannerMeasurementReport {
        try await ownerRepository.fetchBannerOverview(period: period)
    }
}
