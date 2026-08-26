import Combine
import Foundation

struct OwnerAnalyticsDetailMetricItem: Identifiable {
    let title: String
    let value: Int
    let systemImage: String

    var id: String { title }
}

struct OwnerAnalyticsDetailRegionRowModel: Identifiable {
    let id: String
    let title: String
    let signalCount: Int
    let breakdownLines: [String]

    init(region: AnalyticsDetailRegionStats) {
        id = region.id
        title = region.analyticsTitle
        signalCount = region.trackedSignalCount
        breakdownLines = region.analyticsBreakdownLines
    }
}

@MainActor
final class AnalyticsContentDetailViewModel: ObservableObject {
    @Published var selectedPeriod: AnalyticsPeriod = .today
    @Published private(set) var snapshot: AnalyticsContentDetailSnapshot
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let repository: OwnerAnalyticsRepository
    private let contentID: String
    private let contentType: AnalyticsContentType
    private let initialTitle: String
    private let cacheTTL: TimeInterval
    private let now: () -> Date
    private var snapshotByPeriod: [AnalyticsPeriod: OwnerAnalyticsCacheEntry<AnalyticsContentDetailSnapshot>] = [:]
    private var errorByPeriod: [AnalyticsPeriod: String] = [:]
    private var loadGeneration = 0

    init(
        repository: OwnerAnalyticsRepository,
        contentID: String,
        contentType: AnalyticsContentType,
        initialTitle: String,
        initialPeriod: AnalyticsPeriod = .today,
        cacheTTL: TimeInterval = 60,
        now: @escaping () -> Date = Date.init
    ) {
        self.repository = repository
        self.contentID = contentID
        self.contentType = contentType
        self.initialTitle = initialTitle
        self.cacheTTL = cacheTTL
        self.now = now
        self.selectedPeriod = initialPeriod
        self.snapshot = .empty(period: initialPeriod, contentID: contentID, contentType: contentType)
    }

    var title: String {
        let resolvedTitle = snapshot.title.isAnalyticsUnavailableTitle(comparedTo: contentID) ? initialTitle : snapshot.title
        return resolvedTitle.isAnalyticsUnavailableTitle(comparedTo: contentID) ? AppStrings.OwnerAnalytics.titleUnavailable : resolvedTitle
    }

    var subtitle: String {
        switch contentType {
        case .news:
            AppStrings.OwnerAnalytics.newsDetailSubtitle
        case .event:
            AppStrings.OwnerAnalytics.eventDetailSubtitle
        case .organization:
            AppStrings.OwnerAnalytics.organizationDetailSubtitle
        }
    }

    var hasContent: Bool { snapshot.hasData }

    var metricItems: [OwnerAnalyticsDetailMetricItem] {
        let metrics = snapshot.metrics
        switch contentType {
        case .news:
            return [
                OwnerAnalyticsDetailMetricItem(title: AppStrings.OwnerAnalytics.views, value: metrics.views, systemImage: "eye"),
                OwnerAnalyticsDetailMetricItem(title: AppStrings.OwnerAnalytics.likes, value: metrics.likes, systemImage: "heart"),
                OwnerAnalyticsDetailMetricItem(title: AppStrings.OwnerAnalytics.saves, value: metrics.bookmarks, systemImage: "bookmark")
            ]
        case .event:
            var items = [
                OwnerAnalyticsDetailMetricItem(title: AppStrings.OwnerAnalytics.views, value: metrics.views, systemImage: "eye"),
                OwnerAnalyticsDetailMetricItem(title: AppStrings.OwnerAnalytics.registrations, value: metrics.registrations, systemImage: "checkmark.circle"),
                OwnerAnalyticsDetailMetricItem(title: AppStrings.OwnerAnalytics.saves, value: metrics.bookmarks, systemImage: "bookmark")
            ]
            if metrics.cancelledRegistrations > 0 {
                items.append(OwnerAnalyticsDetailMetricItem(
                    title: AppStrings.OwnerAnalytics.cancelledRegistrations,
                    value: metrics.cancelledRegistrations,
                    systemImage: "xmark.circle"
                ))
            }
            return items
        case .organization:
            var items = [
                OwnerAnalyticsDetailMetricItem(title: AppStrings.OwnerAnalytics.views, value: metrics.views, systemImage: "eye"),
                OwnerAnalyticsDetailMetricItem(title: AppStrings.OwnerAnalytics.organizationFollows, value: metrics.follows, systemImage: "person.crop.circle.badge.plus"),
                OwnerAnalyticsDetailMetricItem(title: AppStrings.OwnerAnalytics.saves, value: metrics.bookmarks, systemImage: "bookmark")
            ]
            if metrics.unfollows > 0 {
                items.append(OwnerAnalyticsDetailMetricItem(
                    title: AppStrings.OwnerAnalytics.organizationUnfollows,
                    value: metrics.unfollows,
                    systemImage: "person.crop.circle.badge.minus"
                ))
            }
            return items
        }
    }

    var relatedChips: [OwnerAnalyticsDetailChipModel] {
        var chips: [OwnerAnalyticsDetailChipModel] = []
        if let category = snapshot.category, !category.isEmpty {
            chips.append(OwnerAnalyticsDetailChipModel(
                title: OwnerAnalyticsFormatting.categoryTitle(
                    rawValue: category,
                    contentType: contentType
                ),
                systemImage: "tag"
            ))
        }
        if let organizationName = snapshot.organizationName,
           !organizationName.isAnalyticsUnavailableTitle(comparedTo: snapshot.organizationID ?? "") {
            chips.append(OwnerAnalyticsDetailChipModel(title: organizationName, systemImage: "building.2"))
        }
        if let regionTitle = snapshot.analyticsRegionTitle {
            chips.append(OwnerAnalyticsDetailChipModel(title: regionTitle, systemImage: "mappin.and.ellipse"))
        }
        return chips
    }

    var registrationsPerTrackedViewText: String? {
        guard contentType == .event, snapshot.metrics.views > 0 else { return nil }
        let rate = Double(snapshot.metrics.registrations) / Double(snapshot.metrics.views)
        return OwnerAnalyticsFormatting.percent(rate)
    }

    var regionRows: [OwnerAnalyticsDetailRegionRowModel] {
        snapshot.regions.map(OwnerAnalyticsDetailRegionRowModel.init(region:))
    }

    var isShowingStaleData: Bool { errorMessage != nil && hasContent }

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
            let loadedSnapshot = try await RefreshRequest.run { [self] in try await repository.fetchContentDetail(
                period: period,
                contentID: contentID,
                contentType: contentType
            ) }
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
            snapshot = .empty(period: period, contentID: contentID, contentType: contentType)
        }
    }

    func selectPeriod(_ period: AnalyticsPeriod) async {
        guard selectedPeriod != period else { return }
        preparePeriodSelection(period)
        await loadIfNeeded()
    }

    private func isCacheExpired(_ entry: OwnerAnalyticsCacheEntry<AnalyticsContentDetailSnapshot>) -> Bool {
        now().timeIntervalSince(entry.loadedAt) >= cacheTTL
    }

}

@MainActor
final class AnalyticsOrganizationDetailViewModel: ObservableObject {
    @Published var selectedPeriod: AnalyticsPeriod = .today
    @Published var searchText = ""
    @Published private(set) var snapshot: AnalyticsOrganizationDetailSnapshot
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let repository: OwnerAnalyticsRepository
    private let organizationID: String
    private let initialTitle: String
    private let collapsedTopContentLimit = 3
    private let cacheTTL: TimeInterval
    private let now: () -> Date
    private var snapshotByPeriod: [AnalyticsPeriod: OwnerAnalyticsCacheEntry<AnalyticsOrganizationDetailSnapshot>] = [:]
    private var errorByPeriod: [AnalyticsPeriod: String] = [:]
    private var loadGeneration = 0
    @Published private var isTopNewsExpanded = false
    @Published private var isTopEventsExpanded = false

    init(
        repository: OwnerAnalyticsRepository,
        organizationID: String,
        initialTitle: String,
        initialPeriod: AnalyticsPeriod = .today,
        cacheTTL: TimeInterval = 60,
        now: @escaping () -> Date = Date.init
    ) {
        self.repository = repository
        self.organizationID = organizationID
        self.initialTitle = initialTitle
        self.cacheTTL = cacheTTL
        self.now = now
        self.selectedPeriod = initialPeriod
        self.snapshot = .empty(period: initialPeriod, organizationID: organizationID)
    }

    var title: String {
        let resolvedTitle = snapshot.organizationName?.isAnalyticsUnavailableTitle(comparedTo: organizationID) == false ? snapshot.organizationName ?? "" : initialTitle
        return resolvedTitle.isAnalyticsUnavailableTitle(comparedTo: organizationID) ? AppStrings.OwnerAnalytics.titleUnavailable : resolvedTitle
    }

    var hasContent: Bool { snapshot.hasData }

    var metricItems: [OwnerAnalyticsDetailMetricItem] {
        guard snapshot.metrics.hasData else { return [] }
        let metrics = snapshot.metrics
        var items = [
            OwnerAnalyticsDetailMetricItem(title: AppStrings.OwnerAnalytics.profileViews, value: metrics.profileViews, systemImage: "person.crop.rectangle"),
            OwnerAnalyticsDetailMetricItem(title: AppStrings.OwnerAnalytics.organizationFollows, value: metrics.follows, systemImage: "person.crop.circle.badge.plus"),
            OwnerAnalyticsDetailMetricItem(title: AppStrings.OwnerAnalytics.saves, value: metrics.bookmarks, systemImage: "bookmark"),
            OwnerAnalyticsDetailMetricItem(title: AppStrings.OwnerAnalytics.newsViews, value: metrics.newsViews, systemImage: "newspaper"),
            OwnerAnalyticsDetailMetricItem(title: AppStrings.OwnerAnalytics.eventViews, value: metrics.eventViews, systemImage: "calendar"),
            OwnerAnalyticsDetailMetricItem(title: AppStrings.OwnerAnalytics.eventRegistrations, value: metrics.eventRegistrations, systemImage: "checkmark.circle")
        ]
        if metrics.unfollows > 0 {
            items.append(OwnerAnalyticsDetailMetricItem(
                title: AppStrings.OwnerAnalytics.organizationUnfollows,
                value: metrics.unfollows,
                systemImage: "person.crop.circle.badge.minus"
            ))
        }
        return items.filter(matchesSearch)
    }

    var relatedChips: [OwnerAnalyticsDetailChipModel] {
        guard let regionTitle = snapshot.analyticsRegionTitle else { return [] }
        return [OwnerAnalyticsDetailChipModel(title: regionTitle, systemImage: "mappin.and.ellipse")]
    }

    var regionRows: [OwnerAnalyticsDetailRegionRowModel] {
        snapshot.regions
            .map(OwnerAnalyticsDetailRegionRowModel.init(region:))
            .filter(matchesSearch)
    }

    var topNewsItems: [AnalyticsOrganizationTopContentItem] {
        let limit = isTopNewsExpanded ? filteredTopNews.count : collapsedTopContentLimit
        return Array(filteredTopNews.prefix(limit))
    }

    var topEventsItems: [AnalyticsOrganizationTopContentItem] {
        let limit = isTopEventsExpanded ? filteredTopEvents.count : collapsedTopContentLimit
        return Array(filteredTopEvents.prefix(limit))
    }

    var hasMoreTopNews: Bool {
        filteredTopNews.count > topNewsItems.count
    }

    var hasMoreTopEvents: Bool {
        filteredTopEvents.count > topEventsItems.count
    }

    var canCollapseTopNews: Bool {
        isTopNewsExpanded && filteredTopNews.count > collapsedTopContentLimit
    }

    var canCollapseTopEvents: Bool {
        isTopEventsExpanded && filteredTopEvents.count > collapsedTopContentLimit
    }

    var hasActiveSearch: Bool {
        !normalizedSearchText.isEmpty
    }

    var hasSearchResults: Bool {
        metricItems.isEmpty == false
            || topNewsItems.isEmpty == false
            || topEventsItems.isEmpty == false
            || regionRows.isEmpty == false
    }

    var isShowingStaleData: Bool { errorMessage != nil && hasContent }

    func toggleTopNewsExpansion() {
        isTopNewsExpanded.toggle()
    }

    func toggleTopEventsExpansion() {
        isTopEventsExpanded.toggle()
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
            let loadedSnapshot = try await RefreshRequest.run { [self] in try await repository.fetchOrganizationDetail(period: period, organizationID: organizationID) }
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
            snapshot = .empty(period: period, organizationID: organizationID)
        }
    }

    func selectPeriod(_ period: AnalyticsPeriod) async {
        guard selectedPeriod != period else { return }
        preparePeriodSelection(period)
        await loadIfNeeded()
    }

    private func isCacheExpired(_ entry: OwnerAnalyticsCacheEntry<AnalyticsOrganizationDetailSnapshot>) -> Bool {
        now().timeIntervalSince(entry.loadedAt) >= cacheTTL
    }

    private var filteredTopNews: [AnalyticsOrganizationTopContentItem] {
        snapshot.topNews.filter(matchesSearch)
    }

    private var filteredTopEvents: [AnalyticsOrganizationTopContentItem] {
        snapshot.topEvents.filter(matchesSearch)
    }

    private var normalizedSearchText: String {
        LocalSearchMatcher.normalized(searchText)
    }

    private func matchesSearch(_ item: AnalyticsOrganizationTopContentItem) -> Bool {
        guard hasActiveSearch else { return true }
        return LocalSearchMatcher.matches(
            query: searchText,
            values: [
                item.title,
                item.contentType.analyticsTitle,
                item.category,
                item.category.map {
                OwnerAnalyticsFormatting.categoryTitle(
                    rawValue: $0,
                    contentType: item.contentType
                )
                },
                item.federalState.map(AppStrings.FederalStates.title(for:)),
                item.regionScope.map { regionScope in
                    switch regionScope {
                    case .austria:
                        return AppStrings.OwnerAnalytics.regionAustria
                    case .federalState:
                        return AppStrings.OwnerAnalytics.regionFederalState
                    case .city:
                        return AppStrings.OwnerAnalytics.regionCity
                    }
                }
            ]
        )
    }

    private func matchesSearch(_ item: OwnerAnalyticsDetailMetricItem) -> Bool {
        guard hasActiveSearch else { return true }
        return LocalSearchMatcher.matches(query: searchText, values: [item.title])
    }

    private func matchesSearch(_ row: OwnerAnalyticsDetailRegionRowModel) -> Bool {
        guard hasActiveSearch else { return true }
        return LocalSearchMatcher.matches(
            query: searchText,
            values: [row.title] + row.breakdownLines
        )
    }
}

struct OwnerAnalyticsDetailChipModel: Identifiable {
    let title: String
    let systemImage: String

    var id: String { "\(systemImage):\(title)" }
}

private extension AnalyticsContentDetailSnapshot {
    var analyticsRegionTitle: String? {
        ownerAnalyticsDetailRegionTitle(regionScope: regionScope, federalState: federalState)
    }
}

private extension AnalyticsOrganizationDetailSnapshot {
    var analyticsRegionTitle: String? {
        ownerAnalyticsDetailRegionTitle(regionScope: regionScope, federalState: federalState)
    }
}

private extension AnalyticsDetailRegionStats {
    var analyticsTitle: String {
        ownerAnalyticsDetailRegionTitle(regionScope: regionScope, federalState: federalState) ?? AppStrings.OwnerAnalytics.region
    }

    var analyticsBreakdownLines: [String] {
        metrics
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .map { key, value in
                "\(OwnerAnalyticsDetailMetricFormatting.title(for: key)): \(OwnerAnalyticsFormatting.integer(value))"
            }
    }
}

private func ownerAnalyticsDetailRegionTitle(regionScope: RegionScope?, federalState: AustrianFederalState?) -> String? {
    if let federalState {
        return AppStrings.FederalStates.title(for: federalState)
    }

    guard let regionScope else { return nil }
    switch regionScope {
    case .austria:
        return AppStrings.OwnerAnalytics.regionAustria
    case .federalState:
        return AppStrings.OwnerAnalytics.regionFederalState
    case .city:
        return AppStrings.OwnerAnalytics.regionCity
    }
}

enum OwnerAnalyticsDetailMetricFormatting {
    static func title(for key: String) -> String {
        switch key {
        case "views":
            return AppStrings.OwnerAnalytics.views
        case "profileViews":
            return AppStrings.OwnerAnalytics.profileViews
        case "likes":
            return AppStrings.OwnerAnalytics.likes
        case "bookmarks":
            return AppStrings.OwnerAnalytics.saves
        case "registrations":
            return AppStrings.OwnerAnalytics.registrations
        case "eventRegistrations":
            return AppStrings.OwnerAnalytics.eventRegistrations
        case "cancelledRegistrations":
            return AppStrings.OwnerAnalytics.cancelledRegistrations
        case "follows":
            return AppStrings.OwnerAnalytics.organizationFollows
        case "unfollows":
            return AppStrings.OwnerAnalytics.organizationUnfollows
        case "newsViews":
            return AppStrings.OwnerAnalytics.newsViews
        case "eventViews":
            return AppStrings.OwnerAnalytics.eventViews
        default:
            return key
        }
    }
}
