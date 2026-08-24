import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
private final class DelayedOwnerAnalyticsRepository: OwnerAnalyticsRepository {
    let delaysByPeriod: [AnalyticsPeriod: UInt64]
    let snapshotsByPeriod: [AnalyticsPeriod: OwnerAnalyticsSnapshot]

    init(
        delaysByPeriod: [AnalyticsPeriod: UInt64],
        snapshotsByPeriod: [AnalyticsPeriod: OwnerAnalyticsSnapshot]
    ) {
        self.delaysByPeriod = delaysByPeriod
        self.snapshotsByPeriod = snapshotsByPeriod
    }

    func fetchSnapshot(period: AnalyticsPeriod) async throws -> OwnerAnalyticsSnapshot {
        if let delay = delaysByPeriod[period] {
            try await Task.sleep(nanoseconds: delay)
        }
        return snapshotsByPeriod[period] ?? .empty(period: period)
    }

    func fetchContentDetail(
        period: AnalyticsPeriod,
        contentID: String,
        contentType: AnalyticsContentType
    ) async throws -> AnalyticsContentDetailSnapshot {
        .empty(period: period, contentID: contentID, contentType: contentType)
    }

    func fetchOrganizationDetail(
        period: AnalyticsPeriod,
        organizationID: String
    ) async throws -> AnalyticsOrganizationDetailSnapshot {
        .empty(period: period, organizationID: organizationID)
    }
}

@MainActor
private final class SequencedOwnerAnalyticsRepository: OwnerAnalyticsRepository {
    private var results: [Result<OwnerAnalyticsSnapshot, AppError>]
    private(set) var fetchCount = 0

    init(results: [Result<OwnerAnalyticsSnapshot, AppError>]) {
        self.results = results
    }

    func fetchSnapshot(period: AnalyticsPeriod) async throws -> OwnerAnalyticsSnapshot {
        fetchCount += 1
        guard !results.isEmpty else { return .empty(period: period) }
        return try results.removeFirst().get()
    }

    func fetchContentDetail(
        period: AnalyticsPeriod,
        contentID: String,
        contentType: AnalyticsContentType
    ) async throws -> AnalyticsContentDetailSnapshot {
        .empty(period: period, contentID: contentID, contentType: contentType)
    }

    func fetchOrganizationDetail(
        period: AnalyticsPeriod,
        organizationID: String
    ) async throws -> AnalyticsOrganizationDetailSnapshot {
        .empty(period: period, organizationID: organizationID)
    }
}

@MainActor
private final class DetailOwnerAnalyticsRepository: OwnerAnalyticsRepository {
    private let contentDelaysByPeriod: [AnalyticsPeriod: UInt64]
    private var contentResultsByPeriod: [AnalyticsPeriod: [Result<AnalyticsContentDetailSnapshot, AppError>]]
    private var organizationResultsByPeriod: [AnalyticsPeriod: [Result<AnalyticsOrganizationDetailSnapshot, AppError>]]
    private(set) var contentFetchCountByPeriod: [AnalyticsPeriod: Int] = [:]
    private(set) var organizationFetchCountByPeriod: [AnalyticsPeriod: Int] = [:]

    init(
        contentDelaysByPeriod: [AnalyticsPeriod: UInt64] = [:],
        contentResultsByPeriod: [AnalyticsPeriod: [Result<AnalyticsContentDetailSnapshot, AppError>]] = [:],
        organizationResultsByPeriod: [AnalyticsPeriod: [Result<AnalyticsOrganizationDetailSnapshot, AppError>]] = [:]
    ) {
        self.contentDelaysByPeriod = contentDelaysByPeriod
        self.contentResultsByPeriod = contentResultsByPeriod
        self.organizationResultsByPeriod = organizationResultsByPeriod
    }

    func fetchSnapshot(period: AnalyticsPeriod) async throws -> OwnerAnalyticsSnapshot {
        .empty(period: period)
    }

    func fetchContentDetail(
        period: AnalyticsPeriod,
        contentID: String,
        contentType: AnalyticsContentType
    ) async throws -> AnalyticsContentDetailSnapshot {
        contentFetchCountByPeriod[period, default: 0] += 1
        if let delay = contentDelaysByPeriod[period] {
            try await Task.sleep(nanoseconds: delay)
        }

        var results = contentResultsByPeriod[period] ?? []
        guard !results.isEmpty else {
            return .empty(period: period, contentID: contentID, contentType: contentType)
        }
        let result = results.removeFirst()
        contentResultsByPeriod[period] = results
        return try result.get()
    }

    func fetchOrganizationDetail(
        period: AnalyticsPeriod,
        organizationID: String
    ) async throws -> AnalyticsOrganizationDetailSnapshot {
        organizationFetchCountByPeriod[period, default: 0] += 1
        var results = organizationResultsByPeriod[period] ?? []
        guard !results.isEmpty else {
            return .empty(period: period, organizationID: organizationID)
        }
        let result = results.removeFirst()
        organizationResultsByPeriod[period] = results
        return try result.get()
    }
}

@MainActor
struct OwnerAnalyticsAuditTests {
    @Test func refreshingDetailRollupHasAnExplicitRetryMessage() {
        #expect(
            OwnerAnalyticsErrorPresentation.message(
                for: OwnerAnalyticsRepositoryReadError.rollupRefreshing
            ) == AppStrings.OwnerAnalytics.rollupRefreshing
        )
    }

    @Test func viennaAnalyticsDayIsStableAcrossTravelAndDaylightSavingChanges() throws {
        let beforeSpringShift = try #require(ISO8601DateFormatter().date(from: "2026-03-29T00:30:00Z"))
        let afterSpringShift = try #require(ISO8601DateFormatter().date(from: "2026-03-29T01:30:00Z"))
        let beforeViennaMidnight = try #require(ISO8601DateFormatter().date(from: "2026-08-23T21:59:00Z"))
        let afterViennaMidnight = try #require(ISO8601DateFormatter().date(from: "2026-08-23T22:01:00Z"))

        #expect(AnalyticsFirestoreSchema.dailyDocumentID(for: beforeSpringShift) == "2026-03-29")
        #expect(AnalyticsFirestoreSchema.dailyDocumentID(for: afterSpringShift) == "2026-03-29")
        #expect(AnalyticsFirestoreSchema.dailyDocumentID(for: beforeViennaMidnight) == "2026-08-23")
        #expect(AnalyticsFirestoreSchema.dailyDocumentID(for: afterViennaMidnight) == "2026-08-24")
        #expect(
            AnalyticsFirestoreSchema.PeriodDocumentID.value(for: .today, now: afterViennaMidnight)
                == "2026-08-24"
        )
    }

    @Test func contentViewDeduplicationResetsOnTheViennaCalendarDay() throws {
        let beforeMidnight = try #require(ISO8601DateFormatter().date(from: "2026-08-23T21:59:00Z"))
        let afterMidnight = try #require(ISO8601DateFormatter().date(from: "2026-08-23T22:01:00Z"))

        #expect(
            AnalyticsTrackingKey.daily(
                contentID: "news-1",
                collectionScopeID: "scope-a",
                date: beforeMidnight
            ) != AnalyticsTrackingKey.daily(
                contentID: "news-1",
                collectionScopeID: "scope-a",
                date: afterMidnight
            )
        )
        #expect(
            AnalyticsTrackingKey.daily(
                contentID: "news-1",
                collectionScopeID: "scope-a",
                date: beforeMidnight
            ) != AnalyticsTrackingKey.daily(
                contentID: "news-1",
                collectionScopeID: "scope-b",
                date: beforeMidnight
            )
        )
    }

    @Test func detailRegionAndOrganizationRowsUseViewMetricsOnly() {
        let region = AnalyticsDetailRegionStats(
            regionScope: .federalState,
            federalState: .wien,
            metrics: [
                "views": 7,
                "profileViews": 3,
                "newsViews": 5,
                "eventViews": 4,
                "likes": 99,
                "registrations": 42
            ]
        )
        let item = AnalyticsOrganizationTopContentItem(
            contentID: "news-1",
            contentType: .news,
            title: "Title",
            category: nil,
            federalState: .wien,
            regionScope: .federalState,
            metrics: ["views": 12, "likes": 50, "bookmarks": 20]
        )

        #expect(region.viewCount == 19)
        #expect(item.viewCount == 12)
    }

    @Test func actionOnlyDetailRegionReportsOneTrackedSignalInsteadOfZeroViews() {
        let region = AnalyticsDetailRegionStats(
            regionScope: .federalState,
            federalState: .wien,
            metrics: ["likes": 1]
        )
        let row = OwnerAnalyticsDetailRegionRowModel(region: region)

        #expect(region.viewCount == 0)
        #expect(region.trackedSignalCount == 1)
        #expect(row.signalCount == 1)
        #expect(row.breakdownLines == [
            "\(AppStrings.OwnerAnalytics.likes): \(OwnerAnalyticsFormatting.integer(1))"
        ])
    }

    @Test func detailRegionsAreRankedByAllTrackedSignalsWithStableTies() {
        let viewOnly = AnalyticsDetailRegionStats(
            regionScope: .federalState,
            federalState: .wien,
            metrics: ["views": 2]
        )
        let actionOnly = AnalyticsDetailRegionStats(
            regionScope: .federalState,
            federalState: .tirol,
            metrics: ["likes": 3]
        )
        let tiedActionOnly = AnalyticsDetailRegionStats(
            regionScope: .federalState,
            federalState: .burgenland,
            metrics: ["bookmarks": 3]
        )

        let sortedRegions = [viewOnly, actionOnly, tiedActionOnly]
            .sorted(by: AnalyticsDetailRegionStats.isOrderedByTrackedActivity)

        #expect(sortedRegions.map(\.id) == [
            tiedActionOnly.id,
            actionOnly.id,
            viewOnly.id
        ])
    }

    @Test func aggregatePayloadKeepsOnlyTheCanonicalContentIdentifier() throws {
        let event = AppAnalyticsEvent(
            name: .newsView,
            parameters: [
                .contentID: .string("news-1"),
                .contentTitle: .string("A title that does not need to leave the device"),
                .organizationName: .string("Organization"),
                .federalState: .string("wien"),
                .isGuest: .bool(false)
            ]
        )

        let request = try #require(AnalyticsAggregationRequest(
            event: event,
            consentID: "123e4567-e89b-42d3-a456-426614174000"
        ))

        #expect(request.name == AnalyticsEventName.newsView.rawValue)
        #expect(request.parameters == [AnalyticsParameterName.contentID.rawValue: "news-1"])
    }

    @Test func latestPeriodSelectionWinsWhenOlderRequestFinishesLast() async {
        let sevenDaySnapshot = Self.snapshot(period: .sevenDays, totalViews: 7)
        let thirtyDaySnapshot = Self.snapshot(period: .thirtyDays, totalViews: 30)
        let repository = DelayedOwnerAnalyticsRepository(
            delaysByPeriod: [
                .sevenDays: 150_000_000,
                .thirtyDays: 10_000_000
            ],
            snapshotsByPeriod: [
                .sevenDays: sevenDaySnapshot,
                .thirtyDays: thirtyDaySnapshot
            ]
        )
        let viewModel = OwnerAnalyticsViewModel(repository: repository)

        let olderLoad = Task { await viewModel.selectPeriod(.sevenDays) }
        try? await Task.sleep(nanoseconds: 20_000_000)
        let latestLoad = Task { await viewModel.selectPeriod(.thirtyDays) }
        await olderLoad.value
        await latestLoad.value

        #expect(viewModel.selectedPeriod == .thirtyDays)
        #expect(viewModel.snapshot == thirtyDaySnapshot)
    }

    @Test func refreshFailureKeepsTheLastKnownGoodAnalytics() async {
        let goodSnapshot = Self.snapshot(period: .today, totalViews: 11)
        let repository = SequencedOwnerAnalyticsRepository(results: [
            .success(goodSnapshot),
            .failure(.network)
        ])
        let viewModel = OwnerAnalyticsViewModel(repository: repository)

        await viewModel.load()
        await viewModel.load()

        #expect(viewModel.snapshot == goodSnapshot)
        #expect(viewModel.hasContent)
        #expect(viewModel.isShowingStaleData)
        #expect(viewModel.errorMessage == AppStrings.OwnerAnalytics.loadFailedNetwork)
    }

    @Test func zeroCurrentPeriodWithPreviousActivityRemainsRenderable() async {
        let snapshot = Self.snapshot(period: .today, totalViews: 0, previousViews: 20)
        let viewModel = OwnerAnalyticsViewModel(repository: MockOwnerAnalyticsRepository(
            snapshotsByPeriod: [.today: snapshot],
            contentDetailsByKey: [:],
            organizationDetailsByKey: [:]
        ))

        await viewModel.load()

        #expect(viewModel.hasContent)
        #expect(viewModel.overviewMetricItems.count == 1)
        #expect(viewModel.overviewMetricItems.first?.value == 0)
        #expect(viewModel.overviewMetricItems.first?.previousValue == 20)
    }

    @Test func searchResultsOnlyIncludeSectionsThatCanRender() async {
        let snapshot = Self.snapshot(period: .today, totalViews: 11)
        let viewModel = OwnerAnalyticsViewModel(repository: MockOwnerAnalyticsRepository(
            snapshotsByPeriod: [.today: snapshot],
            contentDetailsByKey: [:],
            organizationDetailsByKey: [:]
        ))
        await viewModel.load()

        viewModel.searchText = AppStrings.OwnerAnalytics.deletedAccounts

        #expect(viewModel.userMetricItems.isEmpty)
        #expect(viewModel.actionMetricItems.isEmpty)
        #expect(viewModel.hasSearchResults == false)
    }

    @Test func freshCachePreservesRefreshErrorAndExpiredCacheRevalidates() async {
        var currentTime = Date(timeIntervalSince1970: 1_000)
        let initialSnapshot = Self.snapshot(period: .today, totalViews: 11)
        let refreshedSnapshot = Self.snapshot(period: .today, totalViews: 22)
        let repository = SequencedOwnerAnalyticsRepository(results: [
            .success(initialSnapshot),
            .failure(.network),
            .success(refreshedSnapshot)
        ])
        let viewModel = OwnerAnalyticsViewModel(
            repository: repository,
            cacheTTL: 60,
            now: { currentTime }
        )

        await viewModel.load()
        await viewModel.load()
        await viewModel.loadIfNeeded()

        #expect(repository.fetchCount == 2)
        #expect(viewModel.snapshot == initialSnapshot)
        #expect(viewModel.errorMessage == AppStrings.OwnerAnalytics.loadFailedNetwork)

        currentTime.addTimeInterval(61)
        await viewModel.loadIfNeeded()

        #expect(repository.fetchCount == 3)
        #expect(viewModel.snapshot == refreshedSnapshot)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func contentDetailLatestPeriodSelectionWinsWhenOlderRequestFinishesLast() async {
        let sevenDaySnapshot = Self.contentDetailSnapshot(period: .sevenDays, views: 7)
        let thirtyDaySnapshot = Self.contentDetailSnapshot(period: .thirtyDays, views: 30)
        let repository = DetailOwnerAnalyticsRepository(
            contentDelaysByPeriod: [
                .sevenDays: 150_000_000,
                .thirtyDays: 10_000_000
            ],
            contentResultsByPeriod: [
                .sevenDays: [.success(sevenDaySnapshot)],
                .thirtyDays: [.success(thirtyDaySnapshot)]
            ]
        )
        let viewModel = AnalyticsContentDetailViewModel(
            repository: repository,
            contentID: "news-1",
            contentType: .news,
            initialTitle: "News"
        )

        let olderLoad = Task { await viewModel.selectPeriod(.sevenDays) }
        try? await Task.sleep(nanoseconds: 20_000_000)
        let latestLoad = Task { await viewModel.selectPeriod(.thirtyDays) }
        await olderLoad.value
        await latestLoad.value

        #expect(viewModel.selectedPeriod == .thirtyDays)
        #expect(viewModel.snapshot == thirtyDaySnapshot)
        #expect(viewModel.isLoading == false)
    }

    @Test func organizationDetailFreshCachePreservesStaleErrorAndExpiredCacheRevalidates() async {
        var currentTime = Date(timeIntervalSince1970: 2_000)
        let initialSnapshot = Self.organizationDetailSnapshot(period: .today, profileViews: 11)
        let refreshedSnapshot = Self.organizationDetailSnapshot(period: .today, profileViews: 22)
        let repository = DetailOwnerAnalyticsRepository(
            organizationResultsByPeriod: [
                .today: [
                    .success(initialSnapshot),
                    .failure(.permissionDenied),
                    .success(refreshedSnapshot)
                ]
            ]
        )
        let viewModel = AnalyticsOrganizationDetailViewModel(
            repository: repository,
            organizationID: "org-1",
            initialTitle: "Organization",
            cacheTTL: 60,
            now: { currentTime }
        )

        await viewModel.load()
        await viewModel.load()
        await viewModel.loadIfNeeded()

        #expect(repository.organizationFetchCountByPeriod[.today] == 2)
        #expect(viewModel.snapshot == initialSnapshot)
        #expect(viewModel.hasContent)
        #expect(viewModel.isShowingStaleData)
        #expect(viewModel.errorMessage == AppStrings.OwnerAnalytics.loadFailedPermission)

        currentTime.addTimeInterval(61)
        await viewModel.loadIfNeeded()

        #expect(repository.organizationFetchCountByPeriod[.today] == 3)
        #expect(viewModel.snapshot == refreshedSnapshot)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isShowingStaleData == false)
    }

    @Test func trendDateFormattingUsesTheViennaAnalyticsDay() throws {
        let afterViennaMidnight = try #require(ISO8601DateFormatter().date(from: "2026-08-23T22:30:00Z"))
        let laterThatDay = try #require(ISO8601DateFormatter().date(from: "2026-08-24T18:00:00Z"))
        let beforeViennaMidnight = try #require(ISO8601DateFormatter().date(from: "2026-08-23T21:30:00Z"))

        let label = OwnerAnalyticsDateFormatting.analyticsDayText(
            afterViennaMidnight,
            locale: Locale(identifier: "en_US")
        )

        #expect(label.contains("24"))
        #expect(OwnerAnalyticsDateFormatting.isSameAnalyticsDay(afterViennaMidnight, laterThatDay))
        #expect(!OwnerAnalyticsDateFormatting.isSameAnalyticsDay(beforeViennaMidnight, afterViennaMidnight))
    }

    @Test func trendSelectionDoesNotCarryAnOutOfRangeDateIntoANewPeriod() throws {
        let oldSelection = try #require(ISO8601DateFormatter().date(from: "2026-08-01T10:00:00Z"))
        let retainedSelection = try #require(ISO8601DateFormatter().date(from: "2026-08-24T10:00:00Z"))
        let currentPointDate = try #require(ISO8601DateFormatter().date(from: "2026-08-24T00:00:00Z"))
        let points = [OwnerAnalyticsTrendPoint(date: currentPointDate, value: 7)]

        #expect(OwnerAnalyticsTrendSelection.normalizedDate(oldSelection, in: points) == nil)
        #expect(
            OwnerAnalyticsTrendSelection.normalizedDate(retainedSelection, in: points)
                == retainedSelection
        )
        #expect(OwnerAnalyticsTrendSelection.point(for: oldSelection, in: points) == nil)
    }

    @Test func detailRegionMetricsKeepTheirDistinctSemanticLabels() {
        #expect(
            OwnerAnalyticsDetailMetricFormatting.title(for: "profileViews")
                == AppStrings.OwnerAnalytics.profileViews
        )
        #expect(
            OwnerAnalyticsDetailMetricFormatting.title(for: "eventRegistrations")
                == AppStrings.OwnerAnalytics.eventRegistrations
        )
        #expect(
            OwnerAnalyticsDetailMetricFormatting.title(for: "views")
                == AppStrings.OwnerAnalytics.views
        )
    }

    @Test func anEmptySnapshotDoesNotPretendToContainAnalytics() {
        let viewModel = OwnerAnalyticsViewModel(repository: MockOwnerAnalyticsRepository(
            snapshotsByPeriod: [.today: .empty(period: .today)],
            contentDetailsByKey: [:],
            organizationDetailsByKey: [:]
        ))

        #expect(viewModel.hasContent == false)
    }

    @Test func legacyNegativeActionsRemainVisibleInsteadOfRenderingZeroOnlyCards() async {
        let overviewSnapshot = OwnerAnalyticsSnapshot(
            period: .today,
            generatedAt: Date(timeIntervalSince1970: 1),
            summaryStats: [],
            dailyStats: [],
            topContent: [],
            regionStats: [],
            userStats: .empty,
            actionStats: AnalyticsActionStats(
                newsLikes: 0,
                totalBookmarks: 0,
                eventRegistrations: 0,
                cancelledEventRegistrations: 2,
                organizationFollows: 0,
                organizationUnfollows: 3
            )
        )
        let overviewViewModel = OwnerAnalyticsViewModel(
            repository: MockOwnerAnalyticsRepository(
                snapshotsByPeriod: [.today: overviewSnapshot],
                contentDetailsByKey: [:],
                organizationDetailsByKey: [:]
            )
        )
        await overviewViewModel.load()

        #expect(overviewViewModel.hasContent)
        #expect(overviewViewModel.actionMetricItems.contains {
            $0.title == AppStrings.OwnerAnalytics.cancelledRegistrations && $0.value == 2
        })
        #expect(overviewViewModel.actionMetricItems.contains {
            $0.title == AppStrings.OwnerAnalytics.organizationUnfollows && $0.value == 3
        })

        let eventSnapshot = AnalyticsContentDetailSnapshot(
            period: .today,
            contentID: "event-1",
            contentType: .event,
            title: "Event",
            organizationID: "org-1",
            organizationName: "Organization",
            category: nil,
            federalState: nil,
            regionScope: .austria,
            metrics: AnalyticsContentDetailMetrics(
                views: 0,
                likes: 0,
                bookmarks: 0,
                registrations: 0,
                cancelledRegistrations: 4,
                follows: 0,
                unfollows: 0
            ),
            regions: [],
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let detailRepository = DetailOwnerAnalyticsRepository(
            contentResultsByPeriod: [.today: [.success(eventSnapshot)]]
        )
        let detailViewModel = AnalyticsContentDetailViewModel(
            repository: detailRepository,
            contentID: "event-1",
            contentType: .event,
            initialTitle: "Event"
        )
        await detailViewModel.load()

        #expect(detailViewModel.hasContent)
        #expect(detailViewModel.metricItems.contains {
            $0.title == AppStrings.OwnerAnalytics.cancelledRegistrations && $0.value == 4
        })
    }

    @Test func partialSourceFailureIsVisibleEvenWhenTheSnapshotIsEmpty() async {
        let snapshot = OwnerAnalyticsSnapshot.empty(
            period: .today,
            unavailableSources: [.users]
        )
        let viewModel = OwnerAnalyticsViewModel(repository: MockOwnerAnalyticsRepository(
            snapshotsByPeriod: [.today: snapshot],
            contentDetailsByKey: [:],
            organizationDetailsByKey: [:]
        ))
        await viewModel.load()

        #expect(viewModel.hasContent == false)
        #expect(viewModel.partialDataMessage?.contains(AppStrings.OwnerAnalytics.sourceUsers) == true)
    }

    @Test func analyticsFormattingUsesTheRequestedLocaleAndPreservesSmallRatios() {
        let german = Locale(identifier: "de_DE")
        let english = Locale(identifier: "en_US")

        #expect(OwnerAnalyticsFormatting.integer(12_345, locale: german) == "12.345")
        #expect(OwnerAnalyticsFormatting.integer(12_345, locale: english) == "12,345")
        #expect(OwnerAnalyticsFormatting.percent(1.0 / 1_000.0, locale: german) != "0 %")
        #expect(OwnerAnalyticsFormatting.percent(1.0 / 1_000.0, locale: english) == "0.1%")
        #expect(OwnerAnalyticsFormatting.list(["A", "B"], locale: german).contains(" und "))
    }

    @Test func analyticsCategoriesUseDomainLocalizedTitles() {
        #expect(
            OwnerAnalyticsFormatting.categoryTitle(rawValue: "education", contentType: .news)
                == NewsCategory.education.title
        )
        #expect(
            OwnerAnalyticsFormatting.categoryTitle(rawValue: "meetups", contentType: .event)
                == EventCategory.meetups.title
        )
        #expect(
            OwnerAnalyticsFormatting.categoryTitle(rawValue: "future-category", contentType: .event)
                == "future-category"
        )
    }

    private static func snapshot(
        period: AnalyticsPeriod,
        totalViews: Int,
        previousViews: Int = 0
    ) -> OwnerAnalyticsSnapshot {
        OwnerAnalyticsSnapshot(
            period: period,
            generatedAt: Date(timeIntervalSince1970: Double(totalViews)),
            summaryStats: [
                AnalyticsSummaryStats(
                    metricType: .totalViews,
                    value: totalViews,
                    previousValue: previousViews
                )
            ],
            dailyStats: [],
            topContent: [],
            regionStats: [],
            userStats: .empty,
            actionStats: .empty
        )
    }

    private static func contentDetailSnapshot(
        period: AnalyticsPeriod,
        views: Int
    ) -> AnalyticsContentDetailSnapshot {
        AnalyticsContentDetailSnapshot(
            period: period,
            contentID: "news-1",
            contentType: .news,
            title: "News",
            organizationID: "org-1",
            organizationName: "Organization",
            category: NewsCategory.news.rawValue,
            federalState: .wien,
            regionScope: .federalState,
            metrics: AnalyticsContentDetailMetrics(
                views: views,
                likes: 0,
                bookmarks: 0,
                registrations: 0,
                cancelledRegistrations: 0,
                follows: 0,
                unfollows: 0
            ),
            regions: [],
            updatedAt: Date(timeIntervalSince1970: Double(views))
        )
    }

    private static func organizationDetailSnapshot(
        period: AnalyticsPeriod,
        profileViews: Int
    ) -> AnalyticsOrganizationDetailSnapshot {
        AnalyticsOrganizationDetailSnapshot(
            period: period,
            organizationID: "org-1",
            organizationName: "Organization",
            federalState: .wien,
            regionScope: .federalState,
            metrics: AnalyticsOrganizationDetailMetrics(
                profileViews: profileViews,
                follows: 0,
                unfollows: 0,
                bookmarks: 0,
                newsViews: 0,
                eventViews: 0,
                eventRegistrations: 0
            ),
            topNews: [],
            topEvents: [],
            regions: [],
            updatedAt: Date(timeIntervalSince1970: Double(profileViews))
        )
    }
}
