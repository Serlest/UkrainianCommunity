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
    let total: Int
    let breakdownLines: [String]
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
    private var snapshotByPeriod: [AnalyticsPeriod: AnalyticsContentDetailSnapshot] = [:]

    init(
        repository: OwnerAnalyticsRepository,
        contentID: String,
        contentType: AnalyticsContentType,
        initialTitle: String
    ) {
        self.repository = repository
        self.contentID = contentID
        self.contentType = contentType
        self.initialTitle = initialTitle
        self.snapshot = .empty(period: .today, contentID: contentID, contentType: contentType)
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
        case .guideArticle:
            AppStrings.OwnerAnalytics.guideDetailSubtitle
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
            return [
                OwnerAnalyticsDetailMetricItem(title: AppStrings.OwnerAnalytics.views, value: metrics.views, systemImage: "eye"),
                OwnerAnalyticsDetailMetricItem(title: AppStrings.OwnerAnalytics.registrations, value: metrics.registrations, systemImage: "checkmark.circle"),
                OwnerAnalyticsDetailMetricItem(title: AppStrings.OwnerAnalytics.cancelledRegistrations, value: metrics.cancelledRegistrations, systemImage: "xmark.circle"),
                OwnerAnalyticsDetailMetricItem(title: AppStrings.OwnerAnalytics.saves, value: metrics.bookmarks, systemImage: "bookmark")
            ]
        case .organization:
            return [
                OwnerAnalyticsDetailMetricItem(title: AppStrings.OwnerAnalytics.views, value: metrics.views, systemImage: "eye"),
                OwnerAnalyticsDetailMetricItem(title: AppStrings.OwnerAnalytics.organizationFollows, value: metrics.follows, systemImage: "person.crop.circle.badge.plus"),
                OwnerAnalyticsDetailMetricItem(title: AppStrings.OwnerAnalytics.organizationUnfollows, value: metrics.unfollows, systemImage: "person.crop.circle.badge.minus"),
                OwnerAnalyticsDetailMetricItem(title: AppStrings.OwnerAnalytics.saves, value: metrics.bookmarks, systemImage: "bookmark")
            ]
        case .guideArticle:
            return [
                OwnerAnalyticsDetailMetricItem(title: AppStrings.OwnerAnalytics.views, value: metrics.views, systemImage: "eye")
            ]
        }
    }

    var relatedChips: [OwnerAnalyticsDetailChipModel] {
        var chips: [OwnerAnalyticsDetailChipModel] = []
        if let category = snapshot.category, !category.isEmpty {
            chips.append(OwnerAnalyticsDetailChipModel(title: category, systemImage: "tag"))
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

    var conversionRateText: String? {
        guard contentType == .event, snapshot.metrics.views > 0 else { return nil }
        let rate = Double(snapshot.metrics.registrations) / Double(snapshot.metrics.views)
        return NumberFormatter.localizedString(from: NSNumber(value: rate), number: .percent)
    }

    var regionRows: [OwnerAnalyticsDetailRegionRowModel] {
        snapshot.regions.map(OwnerAnalyticsDetailRegionRowModel.init(region:))
    }

    func loadIfNeeded() async {
        if let cachedSnapshot = snapshotByPeriod[selectedPeriod] {
            snapshot = cachedSnapshot
            errorMessage = nil
            return
        }

        await load()
    }

    func load() async {
        let period = selectedPeriod
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let loadedSnapshot = try await repository.fetchContentDetail(
                period: period,
                contentID: contentID,
                contentType: contentType
            )
            snapshotByPeriod[period] = loadedSnapshot
            guard selectedPeriod == period else { return }
            snapshot = loadedSnapshot
        } catch {
            guard selectedPeriod == period else { return }
            snapshot = .empty(period: period, contentID: contentID, contentType: contentType)
            errorMessage = Self.readableErrorMessage(for: error)
        }
    }

    func selectPeriod(_ period: AnalyticsPeriod) async {
        guard selectedPeriod != period else { return }
        selectedPeriod = period
        errorMessage = nil
        if let cachedSnapshot = snapshotByPeriod[period] {
            snapshot = cachedSnapshot
            return
        }

        snapshot = .empty(period: period, contentID: contentID, contentType: contentType)
        await loadIfNeeded()
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
    private let expandedTopContentLimit = 10
    private var snapshotByPeriod: [AnalyticsPeriod: AnalyticsOrganizationDetailSnapshot] = [:]
    @Published private var isTopNewsExpanded = false
    @Published private var isTopEventsExpanded = false

    init(repository: OwnerAnalyticsRepository, organizationID: String, initialTitle: String) {
        self.repository = repository
        self.organizationID = organizationID
        self.initialTitle = initialTitle
        self.snapshot = .empty(period: .today, organizationID: organizationID)
    }

    var title: String {
        let resolvedTitle = snapshot.organizationName?.isAnalyticsUnavailableTitle(comparedTo: organizationID) == false ? snapshot.organizationName ?? "" : initialTitle
        return resolvedTitle.isAnalyticsUnavailableTitle(comparedTo: organizationID) ? AppStrings.OwnerAnalytics.titleUnavailable : resolvedTitle
    }

    var hasContent: Bool { snapshot.hasData }

    var metricItems: [OwnerAnalyticsDetailMetricItem] {
        let metrics = snapshot.metrics
        return [
            OwnerAnalyticsDetailMetricItem(title: AppStrings.OwnerAnalytics.profileViews, value: metrics.profileViews, systemImage: "person.crop.rectangle"),
            OwnerAnalyticsDetailMetricItem(title: AppStrings.OwnerAnalytics.organizationFollows, value: metrics.follows, systemImage: "person.crop.circle.badge.plus"),
            OwnerAnalyticsDetailMetricItem(title: AppStrings.OwnerAnalytics.organizationUnfollows, value: metrics.unfollows, systemImage: "person.crop.circle.badge.minus"),
            OwnerAnalyticsDetailMetricItem(title: AppStrings.OwnerAnalytics.saves, value: metrics.bookmarks, systemImage: "bookmark"),
            OwnerAnalyticsDetailMetricItem(title: AppStrings.OwnerAnalytics.newsViews, value: metrics.newsViews, systemImage: "newspaper"),
            OwnerAnalyticsDetailMetricItem(title: AppStrings.OwnerAnalytics.eventViews, value: metrics.eventViews, systemImage: "calendar"),
            OwnerAnalyticsDetailMetricItem(title: AppStrings.OwnerAnalytics.eventRegistrations, value: metrics.eventRegistrations, systemImage: "checkmark.circle")
        ]
    }

    var relatedChips: [OwnerAnalyticsDetailChipModel] {
        guard let regionTitle = snapshot.analyticsRegionTitle else { return [] }
        return [OwnerAnalyticsDetailChipModel(title: regionTitle, systemImage: "mappin.and.ellipse")]
    }

    var regionRows: [OwnerAnalyticsDetailRegionRowModel] {
        snapshot.regions.map(OwnerAnalyticsDetailRegionRowModel.init(region:))
    }

    var topNewsItems: [AnalyticsOrganizationTopContentItem] {
        let limit = isTopNewsExpanded ? expandedTopContentLimit : collapsedTopContentLimit
        return Array(filteredTopNews.prefix(limit))
    }

    var topEventsItems: [AnalyticsOrganizationTopContentItem] {
        let limit = isTopEventsExpanded ? expandedTopContentLimit : collapsedTopContentLimit
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
        topNewsItems.isEmpty == false || topEventsItems.isEmpty == false || regionRows.isEmpty == false
    }

    func toggleTopNewsExpansion() {
        isTopNewsExpanded.toggle()
    }

    func toggleTopEventsExpansion() {
        isTopEventsExpanded.toggle()
    }

    func loadIfNeeded() async {
        if let cachedSnapshot = snapshotByPeriod[selectedPeriod] {
            snapshot = cachedSnapshot
            errorMessage = nil
            return
        }

        await load()
    }

    func load() async {
        let period = selectedPeriod
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let loadedSnapshot = try await repository.fetchOrganizationDetail(period: period, organizationID: organizationID)
            snapshotByPeriod[period] = loadedSnapshot
            guard selectedPeriod == period else { return }
            snapshot = loadedSnapshot
        } catch {
            guard selectedPeriod == period else { return }
            snapshot = .empty(period: period, organizationID: organizationID)
            errorMessage = Self.readableErrorMessage(for: error)
        }
    }

    func selectPeriod(_ period: AnalyticsPeriod) async {
        guard selectedPeriod != period else { return }
        selectedPeriod = period
        errorMessage = nil
        if let cachedSnapshot = snapshotByPeriod[period] {
            snapshot = cachedSnapshot
            return
        }

        snapshot = .empty(period: period, organizationID: organizationID)
        await loadIfNeeded()
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

    private var filteredTopNews: [AnalyticsOrganizationTopContentItem] {
        snapshot.topNews.filter(matchesSearch)
    }

    private var filteredTopEvents: [AnalyticsOrganizationTopContentItem] {
        snapshot.topEvents.filter(matchesSearch)
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
    }

    private func matchesSearch(_ item: AnalyticsOrganizationTopContentItem) -> Bool {
        guard hasActiveSearch else { return true }
        return [
            item.title,
            item.contentType.analyticsTitle,
            item.category,
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
        .compactMap { $0?.localizedLowercase }
        .contains { $0.contains(normalizedSearchText) }
    }
}

struct OwnerAnalyticsDetailChipModel: Identifiable {
    let title: String
    let systemImage: String

    var id: String { "\(systemImage):\(title)" }
}

private extension OwnerAnalyticsDetailRegionRowModel {
    init(region: AnalyticsDetailRegionStats) {
        self.init(
            id: region.id,
            title: region.analyticsTitle,
            total: region.total,
            breakdownLines: region.analyticsBreakdownLines
        )
    }
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
                "\(analyticsMetricTitle(for: key)): \(value.formatted())"
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

private func analyticsMetricTitle(for key: String) -> String {
    switch key {
    case "views", "profileViews":
        return AppStrings.OwnerAnalytics.views
    case "likes":
        return AppStrings.OwnerAnalytics.likes
    case "bookmarks":
        return AppStrings.OwnerAnalytics.saves
    case "registrations", "eventRegistrations":
        return AppStrings.OwnerAnalytics.registrations
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
