import Combine
import SwiftUI

struct OwnerAnalyticsContentSection: Identifiable {
    let contentType: AnalyticsContentType
    let title: String
    let items: [AnalyticsTopContentItem]
    let totalItemCount: Int
    let isExpanded: Bool

    var id: AnalyticsContentType { contentType }
    var hasHiddenItems: Bool { totalItemCount > items.count }
    var canCollapse: Bool { isExpanded }
}

struct OwnerAnalyticsUserMetricItem: Identifiable {
    let title: String
    let value: Int
    let systemImage: String

    var id: String { title }
}

struct OwnerAnalyticsFederalStateUserRowModel: Identifiable {
    let federalState: AustrianFederalState
    let userCount: Int

    var id: AustrianFederalState { federalState }
}

struct OwnerAnalyticsOverviewMetricItem: Identifiable {
    let title: String
    let value: Int
    let systemImage: String

    var id: String { title }
}

struct OwnerAnalyticsRegionRowModel: Identifiable {
    let id: String
    let title: String
    let viewCount: Int
    let breakdownLines: [String]
}

@MainActor
final class OwnerAnalyticsViewModel: ObservableObject {
    @Published var selectedPeriod: AnalyticsPeriod = .today
    @Published var searchText = ""
    @Published private(set) var snapshot: OwnerAnalyticsSnapshot = .empty(period: .today)
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let repository: OwnerAnalyticsRepository
    private let topContentDisplayLimit = 3
    private let expandedTopContentDisplayLimit = 10
    private let federalStateDisplayLimit = 3
    private let expandedFederalStateDisplayLimit = 9
    private let regionDisplayLimit = 5
    private let expandedRegionDisplayLimit = 9
    private var loadedPeriods: Set<AnalyticsPeriod> = []
    @Published private var expandedContentTypes: Set<AnalyticsContentType> = []
    @Published private var isUsersByFederalStateExpanded = false
    @Published private var isRegionsExpanded = false

    init(repository: OwnerAnalyticsRepository) {
        self.repository = repository
    }

    var hasContent: Bool {
        !snapshot.summaryStats.isEmpty
            || !snapshot.topContent.isEmpty
            || !snapshot.regionStats.isEmpty
            || snapshot.userStats.hasData
            || snapshot.actionStats.hasData
    }

    var overviewMetricItems: [OwnerAnalyticsOverviewMetricItem] {
        [
            OwnerAnalyticsOverviewMetricItem(title: AppStrings.OwnerAnalytics.totalViews, value: summaryValue(for: .totalViews), systemImage: AnalyticsMetricType.totalViews.systemImage),
            OwnerAnalyticsOverviewMetricItem(title: AppStrings.OwnerAnalytics.totalUsers, value: snapshot.userStats.totalUsers, systemImage: "person.3"),
            OwnerAnalyticsOverviewMetricItem(title: AppStrings.OwnerAnalytics.newRegistrations, value: snapshot.userStats.newRegistrations, systemImage: "person.badge.plus"),
            OwnerAnalyticsOverviewMetricItem(title: selectedPeriod.activeUsersTitle, value: activeUsersForSelectedPeriod, systemImage: "bolt")
        ]
    }

    var topContentSections: [OwnerAnalyticsContentSection] {
        AnalyticsContentType.allCases.compactMap { contentType in
            let matchingItems = snapshot.topContent
                .filter { $0.contentType == contentType }
                .filter(matchesSearch)
                .sorted { lhs, rhs in
                    if lhs.viewCount == rhs.viewCount {
                        return lhs.rank < rhs.rank
                    }

                    return lhs.viewCount > rhs.viewCount
                }
            let limit = expandedContentTypes.contains(contentType) ? expandedTopContentDisplayLimit : topContentDisplayLimit
            let items = Array(matchingItems.prefix(limit))

            guard !items.isEmpty else { return nil }

            return OwnerAnalyticsContentSection(
                contentType: contentType,
                title: contentType.popularAnalyticsTitle,
                items: items,
                totalItemCount: matchingItems.count,
                isExpanded: expandedContentTypes.contains(contentType)
            )
        }
    }

    var activityMetricItems: [OwnerAnalyticsOverviewMetricItem] {
        snapshot.summaryStats
            .filter { $0.metricType != .totalViews }
            .map { metric in
                OwnerAnalyticsOverviewMetricItem(
                    title: metric.metricType.analyticsTitle,
                    value: metric.value,
                    systemImage: metric.metricType.systemImage
                )
            }
    }

    var actionMetricItems: [OwnerAnalyticsOverviewMetricItem] {
        let stats = snapshot.actionStats
        return [
            OwnerAnalyticsOverviewMetricItem(title: AppStrings.OwnerAnalytics.totalLikes, value: stats.totalLikes, systemImage: AnalyticsMetricType.totalLikes.systemImage),
            OwnerAnalyticsOverviewMetricItem(title: AppStrings.OwnerAnalytics.totalBookmarks, value: stats.totalBookmarks, systemImage: AnalyticsMetricType.totalBookmarks.systemImage),
            OwnerAnalyticsOverviewMetricItem(title: AppStrings.OwnerAnalytics.eventRegistrations, value: stats.eventRegistrations, systemImage: AnalyticsMetricType.eventRegistrations.systemImage),
            OwnerAnalyticsOverviewMetricItem(title: AppStrings.OwnerAnalytics.cancelledEventRegistrations, value: stats.cancelledEventRegistrations, systemImage: AnalyticsMetricType.cancelledEventRegistrations.systemImage),
            OwnerAnalyticsOverviewMetricItem(title: AppStrings.OwnerAnalytics.organizationFollows, value: stats.organizationFollows, systemImage: AnalyticsMetricType.organizationFollows.systemImage),
            OwnerAnalyticsOverviewMetricItem(title: AppStrings.OwnerAnalytics.organizationUnfollows, value: stats.organizationUnfollows, systemImage: AnalyticsMetricType.organizationUnfollows.systemImage)
        ]
    }

    var userMetricItems: [OwnerAnalyticsUserMetricItem] {
        let stats = snapshot.userStats
        return [
            OwnerAnalyticsUserMetricItem(title: AppStrings.OwnerAnalytics.totalUsers, value: stats.totalUsers, systemImage: "person.3"),
            OwnerAnalyticsUserMetricItem(title: AppStrings.OwnerAnalytics.activeUsersToday, value: stats.activeUsersToday, systemImage: "bolt"),
            OwnerAnalyticsUserMetricItem(title: AppStrings.OwnerAnalytics.activeUsersSevenDays, value: stats.activeUsersSevenDays, systemImage: "calendar.badge.clock"),
            OwnerAnalyticsUserMetricItem(title: AppStrings.OwnerAnalytics.activeUsersThirtyDays, value: stats.activeUsersThirtyDays, systemImage: "calendar"),
            OwnerAnalyticsUserMetricItem(title: AppStrings.OwnerAnalytics.newRegistrations, value: stats.newRegistrations, systemImage: "person.badge.plus"),
            OwnerAnalyticsUserMetricItem(title: AppStrings.OwnerAnalytics.deletedAccounts, value: stats.deletedAccounts, systemImage: "person.crop.circle.badge.xmark"),
            OwnerAnalyticsUserMetricItem(title: AppStrings.OwnerAnalytics.blockedUsers, value: stats.blockedUsers, systemImage: "hand.raised"),
            OwnerAnalyticsUserMetricItem(title: AppStrings.OwnerAnalytics.deactivatedUsers, value: stats.deactivatedUsers, systemImage: "person.slash")
        ]
    }

    var userFederalStateRows: [OwnerAnalyticsFederalStateUserRowModel] {
        let rows = snapshot.userStats.usersByFederalState
            .map { federalState, userCount in
                OwnerAnalyticsFederalStateUserRowModel(
                    federalState: federalState,
                    userCount: userCount
                )
            }
            .sorted { lhs, rhs in
                if lhs.userCount == rhs.userCount {
                    return AppStrings.FederalStates.title(for: lhs.federalState) < AppStrings.FederalStates.title(for: rhs.federalState)
                }

                return lhs.userCount > rhs.userCount
            }
            .filter(matchesSearch)
        let limit = isUsersByFederalStateExpanded ? expandedFederalStateDisplayLimit : federalStateDisplayLimit
        return Array(rows.prefix(limit))
    }

    var hasMoreUserFederalStateRows: Bool {
        filteredUserFederalStateRowCount > userFederalStateRows.count
    }

    var canCollapseUserFederalStateRows: Bool {
        isUsersByFederalStateExpanded && filteredUserFederalStateRowCount > federalStateDisplayLimit
    }

    var regionRows: [OwnerAnalyticsRegionRowModel] {
        let rows = snapshot.regionStats
            .sorted { lhs, rhs in
                if lhs.viewCount == rhs.viewCount {
                    return lhs.id < rhs.id
                }

                return lhs.viewCount > rhs.viewCount
            }
            .map { region in
                OwnerAnalyticsRegionRowModel(
                    id: region.id,
                    title: region.analyticsTitle,
                    viewCount: region.viewCount,
                    breakdownLines: region.analyticsBreakdownLines
                )
            }
            .filter(matchesSearch)
        let limit = isRegionsExpanded ? expandedRegionDisplayLimit : regionDisplayLimit
        return Array(rows.prefix(limit))
    }

    var hasMoreRegionRows: Bool {
        filteredRegionRowCount > regionRows.count
    }

    var canCollapseRegionRows: Bool {
        isRegionsExpanded && filteredRegionRowCount > regionDisplayLimit
    }

    var hasActiveSearch: Bool {
        !normalizedSearchText.isEmpty
    }

    var hasSearchResults: Bool {
        topContentSections.isEmpty == false
            || userFederalStateRows.isEmpty == false
            || regionRows.isEmpty == false
    }

    func toggleContentSectionExpansion(_ contentType: AnalyticsContentType) {
        if expandedContentTypes.contains(contentType) {
            expandedContentTypes.remove(contentType)
        } else {
            expandedContentTypes.insert(contentType)
        }
    }

    func toggleUserFederalStateExpansion() {
        isUsersByFederalStateExpanded.toggle()
    }

    func toggleRegionExpansion() {
        isRegionsExpanded.toggle()
    }

    private var filteredUserFederalStateRowCount: Int {
        snapshot.userStats.usersByFederalState
            .map { federalState, userCount in
                OwnerAnalyticsFederalStateUserRowModel(federalState: federalState, userCount: userCount)
            }
            .filter(matchesSearch)
            .count
    }

    private var filteredRegionRowCount: Int {
        snapshot.regionStats
            .map { region in
                OwnerAnalyticsRegionRowModel(
                    id: region.id,
                    title: region.analyticsTitle,
                    viewCount: region.viewCount,
                    breakdownLines: region.analyticsBreakdownLines
                )
            }
            .filter(matchesSearch)
            .count
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
    }

    private func matchesSearch(_ item: AnalyticsTopContentItem) -> Bool {
        guard hasActiveSearch else { return true }
        return [
            item.analyticsDisplayTitle,
            item.contentType.analyticsTitle,
            item.category,
            item.organizationName,
            item.analyticsRegionTitle
        ]
        .compactMap { $0?.localizedLowercase }
        .contains { $0.contains(normalizedSearchText) }
    }

    private func matchesSearch(_ row: OwnerAnalyticsFederalStateUserRowModel) -> Bool {
        guard hasActiveSearch else { return true }
        return AppStrings.FederalStates.title(for: row.federalState)
            .localizedLowercase
            .contains(normalizedSearchText)
    }

    private func matchesSearch(_ row: OwnerAnalyticsRegionRowModel) -> Bool {
        guard hasActiveSearch else { return true }
        return ([row.title] + row.breakdownLines)
            .map { $0.localizedLowercase }
            .contains { $0.contains(normalizedSearchText) }
    }

    func loadIfNeeded() async {
        guard !loadedPeriods.contains(selectedPeriod) else { return }
        await load()
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            snapshot = try await repository.fetchSnapshot(period: selectedPeriod)
            loadedPeriods.insert(selectedPeriod)
        } catch {
            snapshot = .empty(period: selectedPeriod)
            errorMessage = Self.readableErrorMessage(for: error)
        }
    }

    func selectPeriod(_ period: AnalyticsPeriod) async {
        guard selectedPeriod != period else { return }
        selectedPeriod = period
        snapshot = .empty(period: period)
        await loadIfNeeded()
    }

    private var activeUsersForSelectedPeriod: Int {
        switch selectedPeriod {
        case .today:
            snapshot.userStats.activeUsersToday
        case .sevenDays:
            snapshot.userStats.activeUsersSevenDays
        case .thirtyDays:
            snapshot.userStats.activeUsersThirtyDays
        }
    }

    private func summaryValue(for metricType: AnalyticsMetricType) -> Int {
        snapshot.summaryStats.first { $0.metricType == metricType }?.value ?? 0
    }

    private static func readableErrorMessage(for error: Error) -> String {
        if let appError = error as? AppError {
            switch appError {
            case .permissionDenied:
                return AppStrings.OwnerAnalytics.loadFailedPermission
            case .network:
                return AppStrings.OwnerAnalytics.loadFailedNetwork
            case .notFound:
                return AppStrings.OwnerAnalytics.loadFailedNotFound
            case .validationFailed:
                return AppStrings.OwnerAnalytics.loadFailedValidation
            case .unknown:
                return AppStrings.OwnerAnalytics.loadFailedGeneric
            }
        }

        return AppStrings.OwnerAnalytics.loadFailedGeneric
    }
}

private extension AnalyticsPeriod {
    var activeUsersTitle: String {
        switch self {
        case .today:
            AppStrings.OwnerAnalytics.activeUsersToday
        case .sevenDays:
            AppStrings.OwnerAnalytics.activeUsersSevenDays
        case .thirtyDays:
            AppStrings.OwnerAnalytics.activeUsersThirtyDays
        }
    }
}

private extension AnalyticsRegionStats {
    var analyticsTitle: String {
        if let federalState {
            return AppStrings.FederalStates.title(for: federalState)
        }

        switch regionScope {
        case .austria:
            return AppStrings.OwnerAnalytics.regionAustria
        case .federalState:
            return AppStrings.OwnerAnalytics.regionFederalState
        case .city:
            return AppStrings.OwnerAnalytics.regionCity
        }
    }

    var analyticsBreakdownLines: [String] {
        [
            (.newsViews, AppStrings.OwnerAnalytics.newsViews),
            (.eventViews, AppStrings.OwnerAnalytics.eventViews),
            (.organizationViews, AppStrings.OwnerAnalytics.organizationViews),
            (.guideArticleViews, AppStrings.OwnerAnalytics.guideViews)
        ].compactMap { metricType, title in
            guard let value = metrics[metricType], value > 0 else { return nil }
            return "\(title): \(value.formatted())"
        }
    }
}

private extension AnalyticsContentType {
    var popularAnalyticsTitle: String {
        switch self {
        case .news:
            AppStrings.OwnerAnalytics.popularNewsTitle
        case .event:
            AppStrings.OwnerAnalytics.popularEventsTitle
        case .organization:
            AppStrings.OwnerAnalytics.popularOrganizationsTitle
        case .guideArticle:
            AppStrings.OwnerAnalytics.popularGuideMaterialsTitle
        }
    }
}
