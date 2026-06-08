import Foundation

protocol OwnerAnalyticsRepository {
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
