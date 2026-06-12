import FirebaseFirestore
import Foundation

struct FirestoreOwnerAnalyticsRepository: OwnerAnalyticsRepository {
    private let database: Firestore
    private let calendar: Calendar

    init(database: Firestore = Firestore.firestore(), calendar: Calendar = .current) {
        self.database = database
        self.calendar = calendar
    }

    func fetchSnapshot(period: AnalyticsPeriod) async throws -> OwnerAnalyticsSnapshot {
        do {
            let dailyStats = try await fetchDailyStats(for: period)
            let previousDailyStats = try await fetchPreviousDailyStats(for: period)
            async let topContentLoad = fetchTopContent(period: period)
            async let regionStatsLoad = fetchRegionStats(period: period)
            async let userStatsLoad = fetchUserStats(period: period)

            let topContent = try await topContentLoad
            let regionStats = try await regionStatsLoad
            let userStats = try await userStatsLoad

            return OwnerAnalyticsSnapshot(
                period: period,
                generatedAt: Date(),
                summaryStats: makeSummaryStats(from: dailyStats, previousDailyStats: previousDailyStats),
                dailyStats: dailyStats,
                topContent: topContent,
                regionStats: regionStats,
                userStats: userStats,
                actionStats: makeActionStats(from: dailyStats)
            )
        } catch {
            await logAnalyticsReadFailure(
                error,
                operationName: "fetchSnapshot",
                collectionName: "ownerAnalyticsAggregate",
                period: period
            )
            throw appError(from: error)
        }
    }

    func fetchContentDetail(
        period: AnalyticsPeriod,
        contentID: String,
        contentType: AnalyticsContentType
    ) async throws -> AnalyticsContentDetailSnapshot {
        do {
            let snapshot = try await database
                .collection(AnalyticsFirestoreSchema.Collection.contentStats)
                .document(AnalyticsFirestoreSchema.PeriodDocumentID.value(for: period))
                .collection(AnalyticsFirestoreSchema.DetailStatsField.items)
                .document(detailContentKey(contentID: contentID, contentType: contentType))
                .getDocument()

            guard snapshot.exists, let data = snapshot.data() else {
                return .empty(period: period, contentID: contentID, contentType: contentType)
            }

            return makeContentDetailSnapshot(
                period: period,
                fallbackContentID: contentID,
                fallbackContentType: contentType,
                data: data
            )
        } catch {
            await logAnalyticsReadFailure(
                error,
                operationName: "fetchContentDetail",
                collectionName: AnalyticsFirestoreSchema.Collection.contentStats,
                period: period,
                targetType: .diagnosticSnapshot,
                targetId: nil,
                metadata: [
                    "contentType": contentType.rawValue
                ]
            )
            throw appError(from: error)
        }
    }

    func fetchOrganizationDetail(
        period: AnalyticsPeriod,
        organizationID: String
    ) async throws -> AnalyticsOrganizationDetailSnapshot {
        do {
            let snapshot = try await database
                .collection(AnalyticsFirestoreSchema.Collection.organizationStats)
                .document(AnalyticsFirestoreSchema.PeriodDocumentID.value(for: period))
                .collection(AnalyticsFirestoreSchema.DetailStatsField.organizations)
                .document(organizationID)
                .getDocument()

            guard snapshot.exists, let data = snapshot.data() else {
                return .empty(period: period, organizationID: organizationID)
            }

            return makeOrganizationDetailSnapshot(
                period: period,
                fallbackOrganizationID: organizationID,
                data: data
            )
        } catch {
            await logAnalyticsReadFailure(
                error,
                operationName: "fetchOrganizationDetail",
                collectionName: AnalyticsFirestoreSchema.Collection.organizationStats,
                period: period
            )
            throw appError(from: error)
        }
    }

    private func logAnalyticsReadFailure(
        _ error: Error,
        operationName: String,
        collectionName: String,
        period: AnalyticsPeriod,
        targetType: SystemLogTargetType = .diagnosticSnapshot,
        targetId: String? = nil,
        metadata: [String: String] = [:]
    ) async {
        var metadata = metadata
        metadata["collection"] = collectionName
        metadata["period"] = period.rawValue

        await SystemTechnicalErrorLoggingService.shared.logFailure(
            error,
            context: SystemTechnicalErrorContext(
                moduleName: "OwnerAnalytics",
                operationName: operationName,
                screenName: "OwnerAnalytics",
                targetType: targetType,
                targetId: targetId,
                metadata: metadata
            )
        )
    }

    private func fetchDailyStats(for period: AnalyticsPeriod) async throws -> [AnalyticsDailyStats] {
        try await fetchDailyStats(for: dates(for: period))
    }

    private func fetchPreviousDailyStats(for period: AnalyticsPeriod) async throws -> [AnalyticsDailyStats] {
        let today = calendar.startOfDay(for: Date())
        guard let previousWindowEnd = calendar.date(byAdding: .day, value: -period.dayCount, to: today) else {
            return []
        }

        return try await fetchDailyStats(for: dates(endingAt: previousWindowEnd, dayCount: period.dayCount))
    }

    private func fetchDailyStats(for dates: [Date]) async throws -> [AnalyticsDailyStats] {
        var stats: [AnalyticsDailyStats] = []

        for date in dates {
            let snapshot = try await database
                .collection(AnalyticsFirestoreSchema.Collection.dailyStats)
                .document(AnalyticsFirestoreSchema.dailyDocumentID(for: date, calendar: calendar))
                .getDocument()

            guard snapshot.exists, let data = snapshot.data() else {
                continue
            }

            if let dailyStats = makeDailyStats(defaultDate: date, data: data) {
                stats.append(dailyStats)
            }
        }

        return stats.sorted { $0.date < $1.date }
    }

    private func fetchTopContent(period: AnalyticsPeriod) async throws -> [AnalyticsTopContentItem] {
        let snapshot = try await database
            .collection(AnalyticsFirestoreSchema.Collection.topContent)
            .document(AnalyticsFirestoreSchema.PeriodDocumentID.value(for: period))
            .getDocument()

        guard snapshot.exists,
              let data = snapshot.data() else {
            return []
        }

        return topContentPayloads(from: data)
            .compactMap(makeTopContentItem)
            .sorted { lhs, rhs in
                if lhs.viewCount == rhs.viewCount {
                    return lhs.contentID < rhs.contentID
                }

                return lhs.viewCount > rhs.viewCount
            }
            .enumerated()
            .map { index, item in
                AnalyticsTopContentItem(
                    contentID: item.contentID,
                    contentType: item.contentType,
                    title: item.title,
                    category: item.category,
                    organizationID: item.organizationID,
                    organizationName: item.organizationName,
                    regionScope: item.regionScope,
                    federalState: item.federalState,
                    viewCount: item.viewCount,
                    rank: index + 1
                )
            }
    }

    private func fetchRegionStats(period: AnalyticsPeriod) async throws -> [AnalyticsRegionStats] {
        let snapshot = try await database
            .collection(AnalyticsFirestoreSchema.Collection.regionStats)
            .document(AnalyticsFirestoreSchema.PeriodDocumentID.value(for: period))
            .getDocument()

        guard snapshot.exists,
              let data = snapshot.data() else {
            return []
        }

        return regionStatsPayloads(from: data)
            .compactMap(makeRegionStats)
            .sorted { $0.viewCount > $1.viewCount }
    }

    private func fetchUserStats(period: AnalyticsPeriod) async throws -> AnalyticsUserStats {
        let snapshot = try await database
            .collection(AnalyticsFirestoreSchema.Collection.userStats)
            .document(AnalyticsFirestoreSchema.PeriodDocumentID.value(for: period))
            .getDocument()

        guard snapshot.exists,
              let data = snapshot.data() else {
            return .empty
        }

        return makeUserStats(from: data)
    }

    private func makeDailyStats(defaultDate: Date, data: [String: Any]) -> AnalyticsDailyStats? {
        let date = (data[AnalyticsFirestoreSchema.DailyStatsField.date] as? Timestamp)?.dateValue() ?? defaultDate
        var metrics = metricValues(from: data[AnalyticsFirestoreSchema.DailyStatsField.metrics] as? [String: Any] ?? data)
        if metrics[.activeRegions] == nil,
           let activeRegionKeys = data[AnalyticsFirestoreSchema.DailyStatsField.activeRegionKeys] as? [String: Any] {
            metrics[.activeRegions] = activeRegionKeys.count
        }

        guard !metrics.isEmpty else { return nil }

        let totalViews = metrics[.totalViews]
            ?? [.newsViews, .eventViews, .organizationViews, .guideArticleViews]
                .map { metrics[$0, default: 0] }
                .reduce(0, +)
        metrics[.totalViews] = totalViews

        return AnalyticsDailyStats(date: calendar.startOfDay(for: date), metrics: metrics)
    }

    private func makeTopContentItem(from data: [String: Any]) -> AnalyticsTopContentItem? {
        guard let contentID = nonEmptyString(data[AnalyticsFirestoreSchema.TopContentField.contentID]),
              let contentTypeRawValue = nonEmptyString(data[AnalyticsFirestoreSchema.TopContentField.contentType]),
              let contentType = AnalyticsContentType(rawValue: contentTypeRawValue) else {
            return nil
        }

        return AnalyticsTopContentItem(
            contentID: contentID,
            contentType: contentType,
            title: nonEmptyString(data[AnalyticsFirestoreSchema.TopContentField.title]) ?? "",
            category: nonEmptyString(data[AnalyticsFirestoreSchema.TopContentField.category]),
            organizationID: nonEmptyString(data[AnalyticsFirestoreSchema.TopContentField.organizationID]),
            organizationName: nonEmptyString(data[AnalyticsFirestoreSchema.TopContentField.organizationName]),
            regionScope: nonEmptyString(data[AnalyticsFirestoreSchema.TopContentField.regionScope])
                .flatMap(RegionScope.init(rawValue:)),
            federalState: nonEmptyString(data[AnalyticsFirestoreSchema.TopContentField.federalState])
                .flatMap(AustrianFederalState.init(rawValue:)),
            viewCount: intValue(data[AnalyticsFirestoreSchema.TopContentField.viewCount]),
            rank: intValue(data[AnalyticsFirestoreSchema.TopContentField.rank])
        )
    }

    private func makeRegionStats(from data: [String: Any]) -> AnalyticsRegionStats? {
        guard let regionScopeRawValue = nonEmptyString(data[AnalyticsFirestoreSchema.RegionStatsField.regionScope]),
              let regionScope = RegionScope(rawValue: regionScopeRawValue) else {
            return nil
        }

        let federalState = nonEmptyString(data[AnalyticsFirestoreSchema.RegionStatsField.federalState])
            .flatMap(AustrianFederalState.init(rawValue:))
        let contentCount = intValue(data[AnalyticsFirestoreSchema.RegionStatsField.contentCount])
        let contentKeysCount = (data[AnalyticsFirestoreSchema.RegionStatsField.contentKeys] as? [String: Any])?.count ?? 0

        return AnalyticsRegionStats(
            regionScope: regionScope,
            federalState: federalState,
            viewCount: intValue(data[AnalyticsFirestoreSchema.RegionStatsField.viewCount]),
            contentCount: contentCount > 0 ? contentCount : contentKeysCount,
            metrics: metricValues(from: data[AnalyticsFirestoreSchema.RegionStatsField.metrics] as? [String: Any] ?? [:])
        )
    }

    private func makeUserStats(from data: [String: Any]) -> AnalyticsUserStats {
        let metrics = data[AnalyticsFirestoreSchema.UserStatsField.metrics] as? [String: Any] ?? data
        let usersByFederalState = (data[AnalyticsFirestoreSchema.UserStatsField.usersByFederalState] as? [String: Any] ?? [:])
            .reduce(into: [AustrianFederalState: Int]()) { result, item in
                guard let federalState = AustrianFederalState(rawValue: item.key) else { return }
                let value = intValue(item.value)
                guard value > 0 else { return }
                result[federalState] = value
            }

        return AnalyticsUserStats(
            totalUsers: intValue(metrics[AnalyticsFirestoreSchema.UserStatsField.totalUsers]),
            newRegistrations: intValue(metrics[AnalyticsFirestoreSchema.UserStatsField.newRegistrations]),
            deletedAccounts: intValue(metrics[AnalyticsFirestoreSchema.UserStatsField.deletedAccounts]),
            blockedUsers: intValue(metrics[AnalyticsFirestoreSchema.UserStatsField.blockedUsers]),
            deactivatedUsers: intValue(metrics[AnalyticsFirestoreSchema.UserStatsField.deactivatedUsers]),
            activeUsersToday: intValue(metrics[AnalyticsFirestoreSchema.UserStatsField.activeUsersToday]),
            activeUsersSevenDays: intValue(metrics[AnalyticsFirestoreSchema.UserStatsField.activeUsersSevenDays]),
            activeUsersThirtyDays: intValue(metrics[AnalyticsFirestoreSchema.UserStatsField.activeUsersThirtyDays]),
            usersByFederalState: usersByFederalState
        )
    }

    private func makeActionStats(from dailyStats: [AnalyticsDailyStats]) -> AnalyticsActionStats {
        AnalyticsActionStats(
            totalLikes: dailyStats.map { $0.value(for: .totalLikes) }.reduce(0, +),
            totalBookmarks: dailyStats.map { $0.value(for: .totalBookmarks) }.reduce(0, +),
            eventRegistrations: dailyStats.map { $0.value(for: .eventRegistrations) }.reduce(0, +),
            cancelledEventRegistrations: dailyStats.map { $0.value(for: .cancelledEventRegistrations) }.reduce(0, +),
            organizationFollows: dailyStats.map { $0.value(for: .organizationFollows) }.reduce(0, +),
            organizationUnfollows: dailyStats.map { $0.value(for: .organizationUnfollows) }.reduce(0, +)
        )
    }

    private func makeContentDetailSnapshot(
        period: AnalyticsPeriod,
        fallbackContentID: String,
        fallbackContentType: AnalyticsContentType,
        data: [String: Any]
    ) -> AnalyticsContentDetailSnapshot {
        let contentType = nonEmptyString(data[AnalyticsFirestoreSchema.DetailStatsField.contentType])
            .flatMap(AnalyticsContentType.init(rawValue:)) ?? fallbackContentType

        return AnalyticsContentDetailSnapshot(
            period: period,
            contentID: nonEmptyString(data[AnalyticsFirestoreSchema.DetailStatsField.contentID]) ?? fallbackContentID,
            contentType: contentType,
            title: nonEmptyString(data[AnalyticsFirestoreSchema.DetailStatsField.contentTitle]) ?? "",
            organizationID: nonEmptyString(data[AnalyticsFirestoreSchema.DetailStatsField.organizationID]),
            organizationName: nonEmptyString(data[AnalyticsFirestoreSchema.DetailStatsField.organizationName]),
            category: nonEmptyString(data[AnalyticsFirestoreSchema.DetailStatsField.category]),
            federalState: nonEmptyString(data[AnalyticsFirestoreSchema.DetailStatsField.federalState])
                .flatMap(AustrianFederalState.init(rawValue:)),
            regionScope: nonEmptyString(data[AnalyticsFirestoreSchema.DetailStatsField.regionScope])
                .flatMap(RegionScope.init(rawValue:)),
            metrics: makeContentDetailMetrics(from: data[AnalyticsFirestoreSchema.DetailStatsField.metrics] as? [String: Any] ?? [:]),
            regions: detailRegionPayloads(from: data)
                .compactMap(makeDetailRegionStats)
                .sorted { $0.total > $1.total },
            updatedAt: (data[AnalyticsFirestoreSchema.DetailStatsField.updatedAt] as? Timestamp)?.dateValue()
        )
    }

    private func makeOrganizationDetailSnapshot(
        period: AnalyticsPeriod,
        fallbackOrganizationID: String,
        data: [String: Any]
    ) -> AnalyticsOrganizationDetailSnapshot {
        AnalyticsOrganizationDetailSnapshot(
            period: period,
            organizationID: nonEmptyString(data[AnalyticsFirestoreSchema.DetailStatsField.organizationID]) ?? fallbackOrganizationID,
            organizationName: nonEmptyString(data[AnalyticsFirestoreSchema.DetailStatsField.organizationName]),
            federalState: nonEmptyString(data[AnalyticsFirestoreSchema.DetailStatsField.federalState])
                .flatMap(AustrianFederalState.init(rawValue:)),
            regionScope: nonEmptyString(data[AnalyticsFirestoreSchema.DetailStatsField.regionScope])
                .flatMap(RegionScope.init(rawValue:)),
            metrics: makeOrganizationDetailMetrics(from: data[AnalyticsFirestoreSchema.DetailStatsField.metrics] as? [String: Any] ?? [:]),
            topNews: organizationTopContentPayloads(from: data[AnalyticsFirestoreSchema.DetailStatsField.topNews])
                .compactMap(makeOrganizationTopContentItem)
                .sorted(by: sortOrganizationTopContent),
            topEvents: organizationTopContentPayloads(from: data[AnalyticsFirestoreSchema.DetailStatsField.topEvents])
                .compactMap(makeOrganizationTopContentItem)
                .sorted(by: sortOrganizationTopContent),
            regions: detailRegionPayloads(from: data)
                .compactMap(makeDetailRegionStats)
                .sorted { $0.total > $1.total },
            updatedAt: (data[AnalyticsFirestoreSchema.DetailStatsField.updatedAt] as? Timestamp)?.dateValue()
        )
    }

    private func makeContentDetailMetrics(from data: [String: Any]) -> AnalyticsContentDetailMetrics {
        AnalyticsContentDetailMetrics(
            views: intValue(data[AnalyticsFirestoreSchema.DetailStatsField.views]),
            likes: intValue(data[AnalyticsFirestoreSchema.DetailStatsField.likes]),
            bookmarks: intValue(data[AnalyticsFirestoreSchema.DetailStatsField.bookmarks]),
            registrations: intValue(data[AnalyticsFirestoreSchema.DetailStatsField.registrations]),
            cancelledRegistrations: intValue(data[AnalyticsFirestoreSchema.DetailStatsField.cancelledRegistrations]),
            follows: intValue(data[AnalyticsFirestoreSchema.DetailStatsField.follows]),
            unfollows: intValue(data[AnalyticsFirestoreSchema.DetailStatsField.unfollows])
        )
    }

    private func makeOrganizationDetailMetrics(from data: [String: Any]) -> AnalyticsOrganizationDetailMetrics {
        AnalyticsOrganizationDetailMetrics(
            profileViews: intValue(data[AnalyticsFirestoreSchema.DetailStatsField.profileViews]),
            follows: intValue(data[AnalyticsFirestoreSchema.DetailStatsField.follows]),
            unfollows: intValue(data[AnalyticsFirestoreSchema.DetailStatsField.unfollows]),
            bookmarks: intValue(data[AnalyticsFirestoreSchema.DetailStatsField.bookmarks]),
            newsViews: intValue(data[AnalyticsFirestoreSchema.DetailStatsField.newsViews]),
            eventViews: intValue(data[AnalyticsFirestoreSchema.DetailStatsField.eventViews]),
            eventRegistrations: intValue(data[AnalyticsFirestoreSchema.DetailStatsField.eventRegistrations])
        )
    }

    private func makeDetailRegionStats(from data: [String: Any]) -> AnalyticsDetailRegionStats? {
        guard let regionScopeRawValue = nonEmptyString(data[AnalyticsFirestoreSchema.DetailStatsField.regionScope]),
              let regionScope = RegionScope(rawValue: regionScopeRawValue) else {
            return nil
        }

        return AnalyticsDetailRegionStats(
            regionScope: regionScope,
            federalState: nonEmptyString(data[AnalyticsFirestoreSchema.DetailStatsField.federalState])
                .flatMap(AustrianFederalState.init(rawValue:)),
            metrics: detailMetrics(from: data[AnalyticsFirestoreSchema.DetailStatsField.metrics] as? [String: Any] ?? [:])
        )
    }

    private func makeOrganizationTopContentItem(from data: [String: Any]) -> AnalyticsOrganizationTopContentItem? {
        guard let contentID = nonEmptyString(data[AnalyticsFirestoreSchema.DetailStatsField.contentID]),
              let contentTypeRawValue = nonEmptyString(data[AnalyticsFirestoreSchema.DetailStatsField.contentType]),
              let contentType = AnalyticsContentType(rawValue: contentTypeRawValue) else {
            return nil
        }

        return AnalyticsOrganizationTopContentItem(
            contentID: contentID,
            contentType: contentType,
            title: nonEmptyString(data[AnalyticsFirestoreSchema.DetailStatsField.contentTitle]) ?? "",
            category: nonEmptyString(data[AnalyticsFirestoreSchema.DetailStatsField.category]),
            federalState: nonEmptyString(data[AnalyticsFirestoreSchema.DetailStatsField.federalState])
                .flatMap(AustrianFederalState.init(rawValue:)),
            regionScope: nonEmptyString(data[AnalyticsFirestoreSchema.DetailStatsField.regionScope])
                .flatMap(RegionScope.init(rawValue:)),
            metrics: detailMetrics(from: data[AnalyticsFirestoreSchema.DetailStatsField.metrics] as? [String: Any] ?? [:])
        )
    }

    private func topContentPayloads(from data: [String: Any]) -> [[String: Any]] {
        if let items = data[AnalyticsFirestoreSchema.TopContentField.items] as? [[String: Any]] {
            return items
        }

        guard let itemsByKey = data[AnalyticsFirestoreSchema.TopContentField.itemsByKey] as? [String: Any] else {
            return []
        }

        return itemsByKey.values.compactMap { $0 as? [String: Any] }
    }

    private func regionStatsPayloads(from data: [String: Any]) -> [[String: Any]] {
        if let regions = data[AnalyticsFirestoreSchema.RegionStatsField.regions] as? [[String: Any]] {
            return regions
        }

        guard let regionsByKey = data[AnalyticsFirestoreSchema.RegionStatsField.regionsByKey] as? [String: Any] else {
            return []
        }

        return regionsByKey.values.compactMap { $0 as? [String: Any] }
    }

    private func detailRegionPayloads(from data: [String: Any]) -> [[String: Any]] {
        guard let regionsByKey = data[AnalyticsFirestoreSchema.DetailStatsField.regionsByKey] as? [String: Any] else {
            return []
        }

        return regionsByKey.values.compactMap { $0 as? [String: Any] }
    }

    private func organizationTopContentPayloads(from value: Any?) -> [[String: Any]] {
        if let items = value as? [[String: Any]] {
            return items
        }

        guard let itemsByKey = value as? [String: Any] else {
            return []
        }

        return itemsByKey.values.compactMap { $0 as? [String: Any] }
    }

    private func makeSummaryStats(
        from dailyStats: [AnalyticsDailyStats],
        previousDailyStats: [AnalyticsDailyStats]
    ) -> [AnalyticsSummaryStats] {
        let includedMetrics: [AnalyticsMetricType] = [
            .totalViews,
            .newsViews,
            .eventViews,
            .organizationViews,
            .guideArticleViews,
            .activeRegions
        ]

        return includedMetrics.map { metricType in
            return AnalyticsSummaryStats(
                metricType: metricType,
                value: summaryValue(for: metricType, in: dailyStats),
                previousValue: summaryValue(for: metricType, in: previousDailyStats)
            )
        }
    }

    private func summaryValue(for metricType: AnalyticsMetricType, in dailyStats: [AnalyticsDailyStats]) -> Int {
        if metricType == .activeRegions {
            return dailyStats.map { $0.value(for: metricType) }.max() ?? 0
        }

        return dailyStats.map { $0.value(for: metricType) }.reduce(0, +)
    }

    private func metricValues(from data: [String: Any]) -> [AnalyticsMetricType: Int] {
        var metrics: [AnalyticsMetricType: Int] = [:]

        for metricType in AnalyticsMetricType.allCases {
            if let value = data[metricType.rawValue] {
                metrics[metricType] = intValue(value)
            }
        }

        metrics[.totalViews] = metrics[.totalViews] ?? intValue(data[AnalyticsFirestoreSchema.DailyStatsField.totalViews])
        metrics[.newsViews] = metrics[.newsViews] ?? intValue(data[AnalyticsFirestoreSchema.DailyStatsField.newsViews])
        metrics[.eventViews] = metrics[.eventViews] ?? intValue(data[AnalyticsFirestoreSchema.DailyStatsField.eventViews])
        metrics[.organizationViews] = metrics[.organizationViews] ?? intValue(data[AnalyticsFirestoreSchema.DailyStatsField.organizationViews])
        metrics[.guideArticleViews] = metrics[.guideArticleViews] ?? intValue(data[AnalyticsFirestoreSchema.DailyStatsField.guideArticleViews])
        metrics[.activeRegions] = metrics[.activeRegions] ?? intValue(data[AnalyticsFirestoreSchema.DailyStatsField.activeRegions])
        metrics[.totalLikes] = metrics[.totalLikes] ?? intValue(data[AnalyticsFirestoreSchema.DailyStatsField.totalLikes])
        metrics[.totalBookmarks] = metrics[.totalBookmarks] ?? intValue(data[AnalyticsFirestoreSchema.DailyStatsField.totalBookmarks])
        metrics[.eventRegistrations] = metrics[.eventRegistrations] ?? intValue(data[AnalyticsFirestoreSchema.DailyStatsField.eventRegistrations])
        metrics[.cancelledEventRegistrations] = metrics[.cancelledEventRegistrations] ?? intValue(data[AnalyticsFirestoreSchema.DailyStatsField.cancelledEventRegistrations])
        metrics[.organizationFollows] = metrics[.organizationFollows] ?? intValue(data[AnalyticsFirestoreSchema.DailyStatsField.organizationFollows])
        metrics[.organizationUnfollows] = metrics[.organizationUnfollows] ?? intValue(data[AnalyticsFirestoreSchema.DailyStatsField.organizationUnfollows])

        return metrics.filter { $0.value > 0 || $0.key == .activeRegions }
    }

    private func detailMetrics(from data: [String: Any]) -> [String: Int] {
        data.reduce(into: [String: Int]()) { result, item in
            let value = intValue(item.value)
            guard value > 0 else { return }
            result[item.key] = value
        }
    }

    private func dates(for period: AnalyticsPeriod) -> [Date] {
        let today = calendar.startOfDay(for: Date())
        return dates(endingAt: today, dayCount: period.dayCount)
    }

    private func dates(endingAt endDate: Date, dayCount: Int) -> [Date] {
        let normalizedEndDate = calendar.startOfDay(for: endDate)
        return (0..<dayCount).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: normalizedEndDate)
        }
    }

    private func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func intValue(_ value: Any?) -> Int {
        switch value {
        case let value as Int:
            value
        case let value as Int64:
            Int(value)
        case let value as Double:
            Int(value)
        case let value as NSNumber:
            value.intValue
        default:
            0
        }
    }

    private func detailContentKey(contentID: String, contentType: AnalyticsContentType) -> String {
        [
            escapedAnalyticsKeySegment(contentType.rawValue),
            escapedAnalyticsKeySegment(contentID)
        ].joined(separator: "_")
    }

    private func escapedAnalyticsKeySegment(_ value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: "__")
            .replacingOccurrences(of: ".", with: "_d")
            .replacingOccurrences(of: ":", with: "_c")
            .replacingOccurrences(of: "-", with: "_h")
    }

    private func sortOrganizationTopContent(
        lhs: AnalyticsOrganizationTopContentItem,
        rhs: AnalyticsOrganizationTopContentItem
    ) -> Bool {
        if lhs.primaryCount == rhs.primaryCount {
            return lhs.contentID < rhs.contentID
        }

        return lhs.primaryCount > rhs.primaryCount
    }

    private func appError(from error: Error) -> AppError {
        if let appError = error as? AppError {
            return appError
        }

        let nsError = error as NSError
        guard let code = FirestoreErrorCode.Code(rawValue: nsError.code) else {
            return .unknown
        }

        switch code {
        case .permissionDenied:
            return .permissionDenied
        case .unavailable, .deadlineExceeded:
            return .network
        case .notFound:
            return .notFound
        default:
            return .unknown
        }
    }
}
