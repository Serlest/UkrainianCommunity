import Foundation

protocol OwnerAnalyticsRepository {
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
