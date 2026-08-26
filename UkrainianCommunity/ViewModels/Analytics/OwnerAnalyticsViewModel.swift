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
    let previousValue: Int?
    let systemImage: String

    var id: String { title }

    init(title: String, value: Int, previousValue: Int? = nil, systemImage: String) {
        self.title = title
        self.value = value
        self.previousValue = previousValue
        self.systemImage = systemImage
    }
}

struct OwnerAnalyticsRegionRowModel: Identifiable {
    let id: String
    let title: String
    let viewCount: Int
    let breakdownLines: [String]
}

struct OwnerAnalyticsTrendPoint: Identifiable, Equatable {
    let date: Date
    let value: Int

    var id: Date { date }
}

struct OwnerAnalyticsCacheEntry<Value> {
    let value: Value
    let loadedAt: Date
}

enum OwnerAnalyticsErrorPresentation {
    static func message(for error: Error) -> String {
        if error as? OwnerAnalyticsRepositoryReadError == .rollupRefreshing {
            return AppStrings.OwnerAnalytics.rollupRefreshing
        }

        guard let appError = error as? AppError else {
            return AppStrings.OwnerAnalytics.loadFailedGeneric
        }

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
}

@MainActor
final class OwnerAnalyticsViewModel: ObservableObject {
    @Published var selectedPeriod: AnalyticsPeriod = .today
    @Published var searchText = ""
    @Published var selectedTrendMetric: AnalyticsMetricType = .totalViews
    @Published private(set) var snapshot: OwnerAnalyticsSnapshot = .empty(period: .today)
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let repository: OwnerAnalyticsRepository
    private let topContentDisplayLimit = 3
    private let federalStateDisplayLimit = 3
    private let regionDisplayLimit = 5
    private let cacheTTL: TimeInterval
    private let now: () -> Date
    private var snapshotByPeriod: [AnalyticsPeriod: OwnerAnalyticsCacheEntry<OwnerAnalyticsSnapshot>] = [:]
    private var errorByPeriod: [AnalyticsPeriod: String] = [:]
    private var loadGeneration = 0
    @Published private var expandedContentTypes: Set<AnalyticsContentType> = []
    @Published private var isUsersByFederalStateExpanded = false
    @Published private var isRegionsExpanded = false

    init(
        repository: OwnerAnalyticsRepository,
        cacheTTL: TimeInterval = 60,
        now: @escaping () -> Date = Date.init
    ) {
        self.repository = repository
        self.cacheTTL = cacheTTL
        self.now = now
    }

    var hasContent: Bool {
        snapshot.summaryStats.contains { $0.value > 0 || ($0.previousValue ?? 0) > 0 }
            || !snapshot.topContent.isEmpty
            || !snapshot.regionStats.isEmpty
            || snapshot.userStats.hasData
            || snapshot.actionStats.hasData
    }

    var overviewMetricItems: [OwnerAnalyticsOverviewMetricItem] {
        [.totalViews, .activeRegions]
            .compactMap { overviewMetricItem(for: $0) }
            .filter(matchesSearch)
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
            let limit = expandedContentTypes.contains(contentType) ? matchingItems.count : topContentDisplayLimit
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

    var contentViewMetricItems: [OwnerAnalyticsOverviewMetricItem] {
        snapshot.summaryStats
            .filter { [.newsViews, .eventViews, .organizationViews].contains($0.metricType) }
            .compactMap { overviewMetricItem(for: $0.metricType) }
            .filter(matchesSearch)
    }

    var actionMetricItems: [OwnerAnalyticsOverviewMetricItem] {
        guard snapshot.actionStats.hasData else { return [] }
        let stats = snapshot.actionStats
        var items = [
            OwnerAnalyticsOverviewMetricItem(title: AppStrings.OwnerAnalytics.newsLikes, value: stats.newsLikes, systemImage: AnalyticsMetricType.newsLikes.systemImage),
            OwnerAnalyticsOverviewMetricItem(title: AppStrings.OwnerAnalytics.totalBookmarks, value: stats.totalBookmarks, systemImage: AnalyticsMetricType.totalBookmarks.systemImage),
            OwnerAnalyticsOverviewMetricItem(title: AppStrings.OwnerAnalytics.eventRegistrations, value: stats.eventRegistrations, systemImage: AnalyticsMetricType.eventRegistrations.systemImage),
            OwnerAnalyticsOverviewMetricItem(title: AppStrings.OwnerAnalytics.organizationFollows, value: stats.organizationFollows, systemImage: AnalyticsMetricType.organizationFollows.systemImage)
        ]
        if stats.cancelledEventRegistrations > 0 {
            items.append(OwnerAnalyticsOverviewMetricItem(
                title: AppStrings.OwnerAnalytics.cancelledRegistrations,
                value: stats.cancelledEventRegistrations,
                systemImage: "xmark.circle"
            ))
        }
        if stats.organizationUnfollows > 0 {
            items.append(OwnerAnalyticsOverviewMetricItem(
                title: AppStrings.OwnerAnalytics.organizationUnfollows,
                value: stats.organizationUnfollows,
                systemImage: "person.crop.circle.badge.minus"
            ))
        }
        return items.filter(matchesSearch)
    }

    var userMetricItems: [OwnerAnalyticsUserMetricItem] {
        guard snapshot.userStats.hasData else { return [] }
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
        ].filter(matchesSearch)
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
        let limit = isUsersByFederalStateExpanded ? rows.count : federalStateDisplayLimit
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
        let limit = isRegionsExpanded ? rows.count : regionDisplayLimit
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
        overviewMetricItems.isEmpty == false
            || contentViewMetricItems.isEmpty == false
            || actionMetricItems.isEmpty == false
            || userMetricItems.isEmpty == false
            || topContentSections.isEmpty == false
            || userFederalStateRows.isEmpty == false
            || regionRows.isEmpty == false
    }

    var trendMetricOptions: [AnalyticsMetricType] {
        [.totalViews, .newsViews, .eventViews, .organizationViews]
    }

    var trendPoints: [OwnerAnalyticsTrendPoint] {
        snapshot.dailyStats.map { stats in
            OwnerAnalyticsTrendPoint(
                date: stats.date,
                value: stats.value(for: selectedTrendMetric)
            )
        }
    }

    var isShowingStaleData: Bool {
        errorMessage != nil && hasContent
    }

    var partialDataMessage: String? {
        let sourceNames = OwnerAnalyticsDataSource.allCases
            .filter(snapshot.unavailableSources.contains)
            .map(\.analyticsTitle)
        guard !sourceNames.isEmpty else { return nil }

        return AppStrings.OwnerAnalytics.partialData(
            OwnerAnalyticsFormatting.list(sourceNames)
        )
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
        LocalSearchMatcher.normalized(searchText)
    }

    private func matchesSearch(_ item: AnalyticsTopContentItem) -> Bool {
        guard hasActiveSearch else { return true }
        return LocalSearchMatcher.matches(
            query: searchText,
            values: [
                item.analyticsDisplayTitle,
                item.contentType.analyticsTitle,
                item.category,
                item.category.map {
                OwnerAnalyticsFormatting.categoryTitle(
                    rawValue: $0,
                    contentType: item.contentType
                )
                },
                item.organizationName,
                item.analyticsRegionTitle
            ]
        )
    }

    private func matchesSearch(_ row: OwnerAnalyticsFederalStateUserRowModel) -> Bool {
        guard hasActiveSearch else { return true }
        return LocalSearchMatcher.matches(
            query: searchText,
            values: [AppStrings.FederalStates.title(for: row.federalState)]
        )
    }

    private func matchesSearch(_ row: OwnerAnalyticsRegionRowModel) -> Bool {
        guard hasActiveSearch else { return true }
        return LocalSearchMatcher.matches(
            query: searchText,
            values: [row.title] + row.breakdownLines
        )
    }

    private func matchesSearch(_ item: OwnerAnalyticsOverviewMetricItem) -> Bool {
        matchesSearch(title: item.title)
    }

    private func matchesSearch(_ item: OwnerAnalyticsUserMetricItem) -> Bool {
        matchesSearch(title: item.title)
    }

    private func matchesSearch(title: String) -> Bool {
        guard hasActiveSearch else { return true }
        return LocalSearchMatcher.matches(query: searchText, values: [title])
    }

    func loadIfNeeded() async {
        let period = selectedPeriod
        if let cacheEntry = snapshotByPeriod[period] {
            snapshot = cacheEntry.value
            errorMessage = errorByPeriod[period]
            guard !isCacheExpired(cacheEntry) else {
                await load()
                return
            }
            return
        }

        await load()
    }

    func load() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        let period = selectedPeriod
        isLoading = true
        defer {
            if generation == loadGeneration {
                isLoading = false
            }
        }

        do {
            let loadedSnapshot = try await RefreshRequest.run { [self] in try await repository.fetchSnapshot(period: period) }
            guard generation == loadGeneration, selectedPeriod == period else { return }
            snapshotByPeriod[period] = OwnerAnalyticsCacheEntry(value: loadedSnapshot, loadedAt: now())
            errorByPeriod.removeValue(forKey: period)
            snapshot = loadedSnapshot
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration, selectedPeriod == period else { return }
            let message = OwnerAnalyticsErrorPresentation.message(for: error)
            errorByPeriod[period] = message
            errorMessage = message
        }
    }

    func preparePeriodSelection(_ period: AnalyticsPeriod) {
        guard selectedPeriod != period else { return }
        loadGeneration &+= 1
        isLoading = false
        selectedPeriod = period
        errorMessage = errorByPeriod[period]
        if let cacheEntry = snapshotByPeriod[period] {
            snapshot = cacheEntry.value
        } else {
            snapshot = .empty(period: period)
        }
    }

    func selectPeriod(_ period: AnalyticsPeriod) async {
        guard selectedPeriod != period else { return }
        preparePeriodSelection(period)
        await loadIfNeeded()
    }

    private func overviewMetricItem(for metricType: AnalyticsMetricType) -> OwnerAnalyticsOverviewMetricItem? {
        guard let summary = snapshot.summaryStats.first(where: { $0.metricType == metricType }) else {
            return nil
        }
        return OwnerAnalyticsOverviewMetricItem(
            title: metricType.analyticsTitle,
            value: summary.value,
            previousValue: summary.previousValue,
            systemImage: metricType.systemImage
        )
    }

    private func isCacheExpired(_ entry: OwnerAnalyticsCacheEntry<OwnerAnalyticsSnapshot>) -> Bool {
        now().timeIntervalSince(entry.loadedAt) >= cacheTTL
    }

}

private extension OwnerAnalyticsDataSource {
    var analyticsTitle: String {
        switch self {
        case .topContent:
            AppStrings.OwnerAnalytics.sourceTopContent
        case .contentRegions:
            AppStrings.OwnerAnalytics.sourceContentRegions
        case .users:
            AppStrings.OwnerAnalytics.sourceUsers
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
            (.organizationViews, AppStrings.OwnerAnalytics.organizationViews)
        ].compactMap { metricType, title in
            guard let value = metrics[metricType], value > 0 else { return nil }
            return "\(title): \(OwnerAnalyticsFormatting.integer(value))"
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
        }
    }
}
