import FirebaseFirestore
import Foundation

private struct AnalyticsTimestampedValue<Value> {
    let value: Value
    let updatedAt: Date?
    let isAvailable: Bool
}

private struct AnalyticsDailyStatsLoad {
    let stats: [AnalyticsDailyStats]
    let updatedAtByDocumentID: [String: Date]
}

private struct AnalyticsDetailLoad {
    let data: [String: Any]?
    let coverage: AnalyticsDetailCoverage
}

enum OwnerAnalyticsRepositoryReadError: Error, Equatable {
    case rollupRefreshing
}

enum AnalyticsFirestorePayloadResolver {
    private static let requiredUserMetricFields = [
        AnalyticsFirestoreSchema.UserStatsField.totalUsers,
        AnalyticsFirestoreSchema.UserStatsField.newRegistrations,
        AnalyticsFirestoreSchema.UserStatsField.deletedAccounts,
        AnalyticsFirestoreSchema.UserStatsField.blockedUsers,
        AnalyticsFirestoreSchema.UserStatsField.deactivatedUsers,
        AnalyticsFirestoreSchema.UserStatsField.activeUsersToday,
        AnalyticsFirestoreSchema.UserStatsField.activeUsersSevenDays,
        AnalyticsFirestoreSchema.UserStatsField.activeUsersThirtyDays,
    ]

    /// The keyed map is updated transactionally for each incoming event, while
    /// the ranked array is refreshed by the rollup. Prefer the map whenever it
    /// contains usable values so an empty or stale array cannot hide fresh data.
    static func preferredPayloads(array: Any?, keyedMap: Any?) -> [[String: Any]] {
        let mappedPayloads = (keyedMap as? [String: Any])?
            .values
            .compactMap { $0 as? [String: Any] } ?? []
        if !mappedPayloads.isEmpty {
            return mappedPayloads
        }

        return array as? [[String: Any]] ?? []
    }

    nonisolated static func preferredTopContentPayloads(
        array: Any?,
        keyedMap: Any?
    ) -> [[String: Any]] {
        preferredUsablePayloads(
            array: array,
            keyedMap: keyedMap,
            isUsable: isUsableTopContentPayload
        )
    }

    nonisolated static func preferredRegionPayloads(
        array: Any?,
        keyedMap: Any?
    ) -> [[String: Any]] {
        preferredUsablePayloads(
            array: array,
            keyedMap: keyedMap,
            isUsable: isUsableRegionPayload
        )
    }

    nonisolated private static func preferredUsablePayloads(
        array: Any?,
        keyedMap: Any?,
        isUsable: ([String: Any]) -> Bool
    ) -> [[String: Any]] {
        let mappedPayloads = (keyedMap as? [String: Any])?
            .values
            .compactMap { $0 as? [String: Any] }
            .filter(isUsable) ?? []
        if !mappedPayloads.isEmpty {
            return mappedPayloads
        }

        return (array as? [[String: Any]] ?? []).filter(isUsable)
    }

    nonisolated private static func isUsableTopContentPayload(_ data: [String: Any]) -> Bool {
        nonEmptyString(data[AnalyticsFirestoreSchema.TopContentField.contentID]) != nil
            && nonEmptyString(data[AnalyticsFirestoreSchema.TopContentField.contentType])
                .flatMap(AnalyticsContentType.init(rawValue:)) != nil
            && isPositiveInteger(data[AnalyticsFirestoreSchema.TopContentField.viewCount])
    }

    nonisolated private static func isUsableRegionPayload(_ data: [String: Any]) -> Bool {
        guard let regionScope = nonEmptyString(
            data[AnalyticsFirestoreSchema.RegionStatsField.regionScope]
        ).flatMap(RegionScope.init(rawValue:)),
        let metrics = data[AnalyticsFirestoreSchema.RegionStatsField.metrics] as? [String: Any]
        else {
            return false
        }

        if regionScope != .austria {
            guard nonEmptyString(
                data[AnalyticsFirestoreSchema.RegionStatsField.federalState]
            ).flatMap(AustrianFederalState.init(rawValue:)) != nil else {
                return false
            }
        }

        return [
            AnalyticsMetricType.newsViews.rawValue,
            AnalyticsMetricType.eventViews.rawValue,
            AnalyticsMetricType.organizationViews.rawValue,
        ].contains { isPositiveInteger(metrics[$0]) }
    }

    nonisolated private static func isPositiveInteger(_ value: Any?) -> Bool {
        isNonNegativeInteger(value) && numericValue(value) > 0
    }

    nonisolated private static func numericValue(_ value: Any?) -> Double {
        if value is Bool { return 0 }
        switch value {
        case let value as Int:
            return Double(value)
        case let value as Int64:
            return Double(value)
        case let value as Double:
            return value
        case let value as NSNumber:
            return value.doubleValue
        default:
            return 0
        }
    }

    static func isTimestampedRollupAvailable(
        updatedAt: Date?,
        arrayPayload: Any?,
        keyedMapPayload: Any?
    ) -> Bool {
        guard updatedAt != nil else { return false }
        return arrayPayload is [[String: Any]] || keyedMapPayload is [String: Any]
    }

    static func isUserStatsAvailable(
        data: [String: Any],
        expectedPeriodDocumentID: String,
        generatedAt: Date?,
        expectedSourceCount: Int
    ) -> Bool {
        guard generatedAt != nil,
              data[AnalyticsFirestoreSchema.UserStatsField.period] as? String == expectedPeriodDocumentID,
              let metrics = data[AnalyticsFirestoreSchema.UserStatsField.metrics] as? [String: Any],
              let usersByFederalState = data[
                AnalyticsFirestoreSchema.UserStatsField.usersByFederalState
              ] as? [String: Any],
              requiredUserMetricFields.allSatisfy({ isNonNegativeInteger(metrics[$0]) }),
              completedUserLifecycleCoverage(
                rootData: data,
                expectedSourceCount: expectedSourceCount
              ) != nil else {
            return false
        }

        return usersByFederalState.allSatisfy { key, value in
            AustrianFederalState(rawValue: key) != nil && isNonNegativeInteger(value)
        }
    }

    nonisolated static func completedUserLifecycleCoverage(
        rootData: [String: Any],
        expectedSourceCount: Int
    ) -> AnalyticsDetailCoverage? {
        let coverageRoot: [String: Any] = [
            AnalyticsFirestoreSchema.DetailStatsField.sourceDocumentIDs:
                rootData[AnalyticsFirestoreSchema.UserStatsField.sourceDocumentIDs] as Any,
            AnalyticsFirestoreSchema.DetailStatsField.coverageStartDay:
                rootData[AnalyticsFirestoreSchema.UserStatsField.lifecycleCoverageStartDay] as Any,
            AnalyticsFirestoreSchema.DetailStatsField.coveredSourceDocumentIDs:
                rootData[
                    AnalyticsFirestoreSchema.UserStatsField.coveredLifecycleSourceDocumentIDs
                ] as Any,
            AnalyticsFirestoreSchema.DetailStatsField.isPartialCoverage:
                rootData[
                    AnalyticsFirestoreSchema.UserStatsField.isLifecyclePartialCoverage
                ] as Any,
        ]
        return completedDetailCoverage(
            rootData: coverageRoot,
            expectedSourceCount: expectedSourceCount
        )
    }

    static func completedDetailRollupGeneration(
        rootData: [String: Any],
        expectedPeriodDocumentID: String
    ) -> String? {
        guard rootData[AnalyticsFirestoreSchema.DetailStatsField.periodID] as? String
                == expectedPeriodDocumentID,
              rootData[AnalyticsFirestoreSchema.DetailStatsField.updatedAt] != nil,
              nonEmptyString(
                rootData[AnalyticsFirestoreSchema.DetailStatsField.rollupInProgressGeneration]
              ) == nil,
              let generation = nonEmptyString(
                rootData[AnalyticsFirestoreSchema.DetailStatsField.rollupGeneration]
              ) else {
            return nil
        }

        return generation
    }

    nonisolated static func completedDetailCoverage(
        rootData: [String: Any],
        expectedSourceCount: Int
    ) -> AnalyticsDetailCoverage? {
        guard let coverageStartDay = nonEmptyString(
            rootData[AnalyticsFirestoreSchema.DetailStatsField.coverageStartDay]
        ),
        let startsAt = AnalyticsFirestoreSchema.date(
            forDailyDocumentID: coverageStartDay
        ),
        let sourceDocumentIDs = rootData[
            AnalyticsFirestoreSchema.DetailStatsField.sourceDocumentIDs
        ] as? [String],
        let coveredSourceDocumentIDs = rootData[
            AnalyticsFirestoreSchema.DetailStatsField.coveredSourceDocumentIDs
        ] as? [String],
        let isPartialCoverage = rootData[
            AnalyticsFirestoreSchema.DetailStatsField.isPartialCoverage
        ] as? Bool,
        sourceDocumentIDs.count == expectedSourceCount,
        Set(sourceDocumentIDs).count == sourceDocumentIDs.count,
        let anchorDocumentID = sourceDocumentIDs.first,
        let anchorDate = AnalyticsFirestoreSchema.date(
            forDailyDocumentID: anchorDocumentID
        ),
        sourceDocumentIDs == AnalyticsFirestoreSchema.trailingDailyDocumentIDs(
            endingAt: anchorDate,
            dayCount: expectedSourceCount
        ) else {
            return nil
        }

        let expectedCoveredDocumentIDs = sourceDocumentIDs.filter {
            $0 >= coverageStartDay
        }
        guard coveredSourceDocumentIDs == expectedCoveredDocumentIDs,
              isPartialCoverage == (coveredSourceDocumentIDs.count < sourceDocumentIDs.count)
        else {
            return nil
        }

        return AnalyticsDetailCoverage(
            startsAt: startsAt,
            isPartial: isPartialCoverage
        )
    }

    static func isDetailPayloadFromCompletedRollup(
        _ data: [String: Any],
        expectedPeriodDocumentID: String,
        completedGeneration: String
    ) -> Bool {
        data[AnalyticsFirestoreSchema.DetailStatsField.periodID] as? String
            == expectedPeriodDocumentID
            && data[AnalyticsFirestoreSchema.DetailStatsField.updatedAt] != nil
            && nonEmptyString(data[AnalyticsFirestoreSchema.DetailStatsField.rollupGeneration])
                == completedGeneration
    }

    static func didDetailRollupRemainCompleted(
        rootData: [String: Any],
        expectedPeriodDocumentID: String,
        completedGeneration: String
    ) -> Bool {
        completedDetailRollupGeneration(
            rootData: rootData,
            expectedPeriodDocumentID: expectedPeriodDocumentID
        ) == completedGeneration
    }

    static func oldestAvailableUpdate(
        dailyUpdatedAt: Date?,
        sources: [(updatedAt: Date?, isAvailable: Bool)]
    ) -> Date? {
        var availableUpdates = sources.compactMap { source in
            source.isAvailable ? source.updatedAt : nil
        }
        if let dailyUpdatedAt {
            availableUpdates.append(dailyUpdatedAt)
        }
        return availableUpdates.min()
    }

    static func activeRegionKeys(from payload: Any?) -> Set<String> {
        Set(
            (payload as? [String: Any] ?? [:]).compactMap { key, value in
                guard (value as? Bool) == true else { return nil }
                if key.hasPrefix("city_") && key != "city_all" {
                    return "federalState_" + key.dropFirst("city_".count)
                }
                return key
            }
        )
    }

    static func activeRegionCount(from payload: Any?, legacyValue: Int) -> Int {
        guard payload is [String: Any] else { return legacyValue }
        return activeRegionKeys(from: payload).count
    }

    static func activeRegionSummary(from dailyStats: [AnalyticsDailyStats]) -> Int {
        let knownRegionKeys = Set(dailyStats.flatMap(\.activeRegionKeys))
        if !knownRegionKeys.isEmpty {
            return knownRegionKeys.count
        }

        // Legacy documents only stored a scalar count. It cannot be unioned
        // across days, so the maximum is the honest lower-bound fallback.
        return dailyStats.map { $0.value(for: .activeRegions) }.max() ?? 0
    }

    static func unavailableSources(
        totalViews: Int,
        activeRegionCount: Int,
        isTopContentAvailable: Bool,
        areContentRegionsAvailable: Bool,
        areUsersAvailable: Bool
    ) -> Set<OwnerAnalyticsDataSource> {
        var sources = Set<OwnerAnalyticsDataSource>()

        if totalViews > 0, !isTopContentAvailable {
            sources.insert(.topContent)
        }
        if activeRegionCount > 0, !areContentRegionsAvailable {
            sources.insert(.contentRegions)
        }
        if !areUsersAvailable {
            sources.insert(.users)
        }

        return sources
    }

    static func mergedRegionStats(_ regions: [AnalyticsRegionStats]) -> [AnalyticsRegionStats] {
        let grouped = Dictionary(grouping: regions, by: \.id)
        return grouped.values.compactMap { matchingRegions in
            guard let first = matchingRegions.first else { return nil }
            let metrics = matchingRegions.reduce(into: [AnalyticsMetricType: Int]()) { result, region in
                for (metric, value) in region.metrics {
                    result[metric, default: 0] += value
                }
            }
            return AnalyticsRegionStats(
                regionScope: first.regionScope,
                federalState: first.federalState,
                viewCount: matchingRegions.map(\.viewCount).reduce(0, +),
                // Legacy scope buckets can overlap in content identity. The
                // maximum is an honest lower bound; summing would overstate it.
                contentCount: matchingRegions.map(\.contentCount).max() ?? 0,
                metrics: metrics
            )
        }
    }

    nonisolated private static func isNonNegativeInteger(_ value: Any?) -> Bool {
        if value is Bool {
            return false
        }

        switch value {
        case let value as Int:
            return value >= 0
        case let value as Int64:
            return value >= 0
        case let value as Double:
            return value.isFinite && value >= 0 && value.rounded(.towardZero) == value
        case let value as NSNumber:
            let doubleValue = value.doubleValue
            return doubleValue.isFinite
                && doubleValue >= 0
                && doubleValue.rounded(.towardZero) == doubleValue
        default:
            return false
        }
    }

    nonisolated private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}

struct FirestoreOwnerAnalyticsRepository: OwnerAnalyticsRepository {
    private let database: Firestore
    private let calendar: Calendar
    private let now: () -> Date

    init(
        database: Firestore = Firestore.firestore(),
        calendar: Calendar = AnalyticsFirestoreSchema.analyticsCalendar,
        now: @escaping () -> Date = Date.init
    ) {
        self.database = database
        self.calendar = calendar
        self.now = now
    }

    func fetchSnapshot(period: AnalyticsPeriod) async throws -> OwnerAnalyticsSnapshot {
        do {
            // One immutable anchor keeps every document read in the same Vienna
            // analytics day, even if this async fetch crosses midnight.
            let anchor = now()
            let currentDates = dates(for: period, anchoredAt: anchor)
            let previousDates = previousDates(for: period, anchoredAt: anchor)
            async let dailyStatsLoad = fetchDailyStats(for: currentDates + previousDates)
            async let topContentLoad = fetchTopContentRecovering(period: period, anchoredAt: anchor)
            async let regionStatsLoad = fetchRegionStatsRecovering(period: period, anchoredAt: anchor)
            async let userStatsLoad = fetchUserStatsRecovering(period: period, anchoredAt: anchor)

            let dailyLoad = try await dailyStatsLoad
            let dailyStats = normalizedDailyStats(for: currentDates, from: dailyLoad.stats)
            let previousDailyStats = normalizedDailyStats(for: previousDates, from: dailyLoad.stats)
            let topContent = try await topContentLoad
            let regionStats = try await regionStatsLoad
            let userStats = try await userStatsLoad
            let summaryStats = makeSummaryStats(from: dailyStats, previousDailyStats: previousDailyStats)
            let totalViews = summaryValue(for: .totalViews, in: dailyStats)
            let activeRegionCount = summaryValue(for: .activeRegions, in: dailyStats)
            let currentDailyDocumentIDs = Set(currentDates.map(documentID))
            let isTopContentAvailable = topContent.isAvailable
                && (totalViews == 0 || !topContent.value.isEmpty)
            let areContentRegionsAvailable = regionStats.isAvailable
                && (activeRegionCount == 0 || !regionStats.value.isEmpty)
            let dailyUpdatedAt = dailyLoad.updatedAtByDocumentID
                .filter { currentDailyDocumentIDs.contains($0.key) }
                .values
                .max()
            let generatedAt = AnalyticsFirestorePayloadResolver.oldestAvailableUpdate(
                dailyUpdatedAt: dailyUpdatedAt,
                sources: [
                    (topContent.updatedAt, isTopContentAvailable),
                    (regionStats.updatedAt, areContentRegionsAvailable),
                    (userStats.updatedAt, userStats.isAvailable),
                ]
            )

            return OwnerAnalyticsSnapshot(
                period: period,
                generatedAt: generatedAt,
                summaryStats: summaryStats,
                dailyStats: dailyStats,
                topContent: topContent.value,
                regionStats: regionStats.value,
                userStats: userStats.value,
                actionStats: makeActionStats(from: dailyStats),
                unavailableSources: AnalyticsFirestorePayloadResolver.unavailableSources(
                    totalViews: totalViews,
                    activeRegionCount: activeRegionCount,
                    isTopContentAvailable: isTopContentAvailable,
                    areContentRegionsAvailable: areContentRegionsAvailable,
                    areUsersAvailable: userStats.isAvailable
                )
            )
        } catch is CancellationError {
            throw CancellationError()
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
            let anchor = now()
            let load = try await fetchDetailData(
                period: period,
                anchoredAt: anchor,
                rootCollection: AnalyticsFirestoreSchema.Collection.contentStats,
                childCollection: AnalyticsFirestoreSchema.DetailStatsField.items,
                childDocumentID: detailContentKey(contentID: contentID, contentType: contentType)
            )
            guard let data = load.data else {
                return .empty(
                    period: period,
                    contentID: contentID,
                    contentType: contentType,
                    coverage: load.coverage
                )
            }

            return makeContentDetailSnapshot(
                period: period,
                fallbackContentID: contentID,
                fallbackContentType: contentType,
                data: data,
                coverage: load.coverage
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as OwnerAnalyticsRepositoryReadError {
            throw error
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
            let anchor = now()
            let load = try await fetchDetailData(
                period: period,
                anchoredAt: anchor,
                rootCollection: AnalyticsFirestoreSchema.Collection.organizationStats,
                childCollection: AnalyticsFirestoreSchema.DetailStatsField.organizations,
                childDocumentID: organizationID
            )
            guard let data = load.data else {
                return .empty(
                    period: period,
                    organizationID: organizationID,
                    coverage: load.coverage
                )
            }

            return makeOrganizationDetailSnapshot(
                period: period,
                fallbackOrganizationID: organizationID,
                data: data,
                coverage: load.coverage
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as OwnerAnalyticsRepositoryReadError {
            throw error
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

    private func fetchDetailData(
        period: AnalyticsPeriod,
        anchoredAt anchor: Date,
        rootCollection: String,
        childCollection: String,
        childDocumentID: String
    ) async throws -> AnalyticsDetailLoad {
        let periodDocumentID = periodDocumentID(for: period, anchoredAt: anchor)
        let rootReference = database
            .collection(rootCollection)
            .document(periodDocumentID)
        let childReference = rootReference
            .collection(childCollection)
            .document(childDocumentID)

        guard period != .today else {
            let childSnapshot = try await childReference.getDocument()
            return AnalyticsDetailLoad(
                data: childSnapshot.exists ? childSnapshot.data() : nil,
                coverage: .complete
            )
        }

        // Read the completion marker first. A later child read can then either
        // match this immutable generation or fail closed while the next rollup
        // is replacing documents. This prevents mixed-period detail metrics.
        let rootSnapshot = try await rootReference.getDocument()
        guard rootSnapshot.exists,
              let rootData = rootSnapshot.data(),
              let completedGeneration = AnalyticsFirestorePayloadResolver
                .completedDetailRollupGeneration(
                    rootData: rootData,
                    expectedPeriodDocumentID: periodDocumentID
                ),
              let coverage = AnalyticsFirestorePayloadResolver.completedDetailCoverage(
                rootData: rootData,
                expectedSourceCount: period.dayCount
              ) else {
            throw OwnerAnalyticsRepositoryReadError.rollupRefreshing
        }

        let childSnapshot = try await childReference.getDocument()
        guard childSnapshot.exists, let childData = childSnapshot.data() else {
            // A newer rollup may have removed the old child between the two
            // reads. Re-check the parent before treating the item as genuinely
            // absent, otherwise a transient generation swap is cached as an
            // empty result.
            let verificationSnapshot = try await rootReference.getDocument()
            guard verificationSnapshot.exists,
                  let verificationData = verificationSnapshot.data(),
                  AnalyticsFirestorePayloadResolver.didDetailRollupRemainCompleted(
                    rootData: verificationData,
                    expectedPeriodDocumentID: periodDocumentID,
                    completedGeneration: completedGeneration
                  ),
                  AnalyticsFirestorePayloadResolver.completedDetailCoverage(
                    rootData: verificationData,
                    expectedSourceCount: period.dayCount
                  ) == coverage else {
                throw OwnerAnalyticsRepositoryReadError.rollupRefreshing
            }
            return AnalyticsDetailLoad(data: nil, coverage: coverage)
        }
        guard AnalyticsFirestorePayloadResolver.isDetailPayloadFromCompletedRollup(
            childData,
            expectedPeriodDocumentID: periodDocumentID,
            completedGeneration: completedGeneration
        ) else {
            throw OwnerAnalyticsRepositoryReadError.rollupRefreshing
        }

        return AnalyticsDetailLoad(data: childData, coverage: coverage)
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

    private func previousDates(for period: AnalyticsPeriod, anchoredAt anchor: Date) -> [Date] {
        let today = calendar.startOfDay(for: anchor)
        guard let previousWindowEnd = calendar.date(byAdding: .day, value: -period.dayCount, to: today) else {
            return []
        }

        return dates(endingAt: previousWindowEnd, dayCount: period.dayCount)
    }

    private func fetchDailyStats(for dates: [Date]) async throws -> AnalyticsDailyStatsLoad {
        let dateByDocumentID = Dictionary(uniqueKeysWithValues: dates.map { date in
            (documentID(for: date), date)
        })
        let documentIDs = dateByDocumentID.keys.sorted()
        guard let firstDocumentID = documentIDs.first,
              let lastDocumentID = documentIDs.last else {
            return AnalyticsDailyStatsLoad(stats: [], updatedAtByDocumentID: [:])
        }

        let snapshot = try await database
            .collection(AnalyticsFirestoreSchema.Collection.dailyStats)
            .whereField(FieldPath.documentID(), isGreaterThanOrEqualTo: firstDocumentID)
            .whereField(FieldPath.documentID(), isLessThanOrEqualTo: lastDocumentID)
            .getDocuments()
        var updateDatesByDocumentID: [String: Date] = [:]
        let stats = snapshot.documents.compactMap { document -> AnalyticsDailyStats? in
            guard let defaultDate = dateByDocumentID[document.documentID] else { return nil }
            if let updatedAt = timestampDate(document.data()[AnalyticsFirestoreSchema.DetailStatsField.updatedAt]) {
                updateDatesByDocumentID[document.documentID] = updatedAt
            }
            return makeDailyStats(defaultDate: defaultDate, data: document.data())
        }

        return AnalyticsDailyStatsLoad(
            stats: stats.sorted { $0.date < $1.date },
            updatedAtByDocumentID: updateDatesByDocumentID
        )
    }

    private func fetchTopContent(
        period: AnalyticsPeriod,
        anchoredAt anchor: Date
    ) async throws -> AnalyticsTimestampedValue<[AnalyticsTopContentItem]> {
        let snapshot = try await database
            .collection(AnalyticsFirestoreSchema.Collection.topContent)
            .document(periodDocumentID(for: period, anchoredAt: anchor))
            .getDocument()

        guard snapshot.exists,
              let data = snapshot.data() else {
            return AnalyticsTimestampedValue(value: [], updatedAt: nil, isAvailable: false)
        }

        let sortedItems = topContentPayloads(from: data)
            .compactMap(makeTopContentItem)
            .sorted { lhs, rhs in
                if lhs.viewCount == rhs.viewCount {
                    return lhs.contentID < rhs.contentID
                }

                return lhs.viewCount > rhs.viewCount
            }
        var nextRankByContentType: [AnalyticsContentType: Int] = [:]
        let items = sortedItems.map { item in
            let rank = nextRankByContentType[item.contentType, default: 0] + 1
            nextRankByContentType[item.contentType] = rank
            return AnalyticsTopContentItem(
                contentID: item.contentID,
                contentType: item.contentType,
                title: item.title,
                category: item.category,
                organizationID: item.organizationID,
                organizationName: item.organizationName,
                regionScope: item.regionScope,
                federalState: item.federalState,
                viewCount: item.viewCount,
                rank: rank
            )
        }
        let updatedAt = timestampDate(data[AnalyticsFirestoreSchema.DetailStatsField.updatedAt])
        return AnalyticsTimestampedValue(
            value: items,
            updatedAt: updatedAt,
            isAvailable: AnalyticsFirestorePayloadResolver.isTimestampedRollupAvailable(
                updatedAt: updatedAt,
                arrayPayload: data[AnalyticsFirestoreSchema.TopContentField.items],
                keyedMapPayload: data[AnalyticsFirestoreSchema.TopContentField.itemsByKey]
            )
        )
    }

    private func fetchTopContentRecovering(
        period: AnalyticsPeriod,
        anchoredAt anchor: Date
    ) async throws -> AnalyticsTimestampedValue<[AnalyticsTopContentItem]> {
        do {
            return try await fetchTopContent(period: period, anchoredAt: anchor)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            await logAnalyticsReadFailure(
                error,
                operationName: "fetchTopContent",
                collectionName: AnalyticsFirestoreSchema.Collection.topContent,
                period: period
            )
            return AnalyticsTimestampedValue(value: [], updatedAt: nil, isAvailable: false)
        }
    }

    private func fetchRegionStats(
        period: AnalyticsPeriod,
        anchoredAt anchor: Date
    ) async throws -> AnalyticsTimestampedValue<[AnalyticsRegionStats]> {
        let snapshot = try await database
            .collection(AnalyticsFirestoreSchema.Collection.regionStats)
            .document(periodDocumentID(for: period, anchoredAt: anchor))
            .getDocument()

        guard snapshot.exists,
              let data = snapshot.data() else {
            return AnalyticsTimestampedValue(value: [], updatedAt: nil, isAvailable: false)
        }

        let regions = AnalyticsFirestorePayloadResolver.mergedRegionStats(
            regionStatsPayloads(from: data).compactMap(makeRegionStats)
        )
            .sorted { $0.viewCount > $1.viewCount }
        let updatedAt = timestampDate(data[AnalyticsFirestoreSchema.DetailStatsField.updatedAt])
        return AnalyticsTimestampedValue(
            value: regions,
            updatedAt: updatedAt,
            isAvailable: AnalyticsFirestorePayloadResolver.isTimestampedRollupAvailable(
                updatedAt: updatedAt,
                arrayPayload: data[AnalyticsFirestoreSchema.RegionStatsField.regions],
                keyedMapPayload: data[AnalyticsFirestoreSchema.RegionStatsField.regionsByKey]
            )
        )
    }

    private func fetchRegionStatsRecovering(
        period: AnalyticsPeriod,
        anchoredAt anchor: Date
    ) async throws -> AnalyticsTimestampedValue<[AnalyticsRegionStats]> {
        do {
            return try await fetchRegionStats(period: period, anchoredAt: anchor)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            await logAnalyticsReadFailure(
                error,
                operationName: "fetchRegionStats",
                collectionName: AnalyticsFirestoreSchema.Collection.regionStats,
                period: period
            )
            return AnalyticsTimestampedValue(value: [], updatedAt: nil, isAvailable: false)
        }
    }

    private func fetchUserStats(
        period: AnalyticsPeriod,
        anchoredAt anchor: Date
    ) async throws -> AnalyticsTimestampedValue<AnalyticsUserStats> {
        let documentID = periodDocumentID(for: period, anchoredAt: anchor)
        let snapshot = try await database
            .collection(AnalyticsFirestoreSchema.Collection.userStats)
            .document(documentID)
            .getDocument()

        guard snapshot.exists,
              let data = snapshot.data() else {
            return AnalyticsTimestampedValue(value: .empty, updatedAt: nil, isAvailable: false)
        }

        let generatedAt = timestampDate(data[AnalyticsFirestoreSchema.UserStatsField.generatedAt])
        let lifecycleCoverage = AnalyticsFirestorePayloadResolver
            .completedUserLifecycleCoverage(
                rootData: data,
                expectedSourceCount: period.dayCount
            )
        let isAvailable = AnalyticsFirestorePayloadResolver.isUserStatsAvailable(
            data: data,
            expectedPeriodDocumentID: documentID,
            generatedAt: generatedAt,
            expectedSourceCount: period.dayCount
        )
        guard isAvailable, let lifecycleCoverage else {
            return AnalyticsTimestampedValue(value: .empty, updatedAt: nil, isAvailable: false)
        }
        return AnalyticsTimestampedValue(
            value: makeUserStats(from: data, lifecycleCoverage: lifecycleCoverage),
            updatedAt: timestampDate(
                data[AnalyticsFirestoreSchema.UserStatsField.generatedAt]
                    ?? data[AnalyticsFirestoreSchema.DetailStatsField.updatedAt]
            ),
            isAvailable: true
        )
    }

    private func fetchUserStatsRecovering(
        period: AnalyticsPeriod,
        anchoredAt anchor: Date
    ) async throws -> AnalyticsTimestampedValue<AnalyticsUserStats> {
        do {
            return try await fetchUserStats(period: period, anchoredAt: anchor)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            await logAnalyticsReadFailure(
                error,
                operationName: "fetchUserStats",
                collectionName: AnalyticsFirestoreSchema.Collection.userStats,
                period: period
            )
            return AnalyticsTimestampedValue(value: .empty, updatedAt: nil, isAvailable: false)
        }
    }

    private func makeDailyStats(defaultDate: Date, data: [String: Any]) -> AnalyticsDailyStats? {
        var metrics = metricValues(from: data[AnalyticsFirestoreSchema.DailyStatsField.metrics] as? [String: Any] ?? data)
        let activeRegionKeysPayload = data[AnalyticsFirestoreSchema.DailyStatsField.activeRegionKeys]
        let activeRegionKeys = AnalyticsFirestorePayloadResolver.activeRegionKeys(
            from: activeRegionKeysPayload
        )
        metrics[.activeRegions] = AnalyticsFirestorePayloadResolver.activeRegionCount(
            from: activeRegionKeysPayload,
            legacyValue: metrics[.activeRegions, default: 0]
        )

        guard !metrics.isEmpty else { return nil }

        let totalViews = AnalyticsFirestoreSchema.activeViewCount(in: metrics)
        metrics[.totalViews] = totalViews

        return AnalyticsDailyStats(
            // The document ID is the analytics-day contract. Using the mutable
            // server timestamp here could move a late write into another day
            // when the viewer is travelling or a legacy document is malformed.
            date: calendar.startOfDay(for: defaultDate),
            metrics: metrics,
            activeRegionKeys: activeRegionKeys
        )
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
        let normalizedRegionScope: RegionScope = regionScope == .city && federalState != nil
            ? .federalState
            : regionScope
        var metrics = metricValues(
            from: data[AnalyticsFirestoreSchema.RegionStatsField.metrics] as? [String: Any] ?? [:]
        )
        let viewCount = AnalyticsFirestoreSchema.activeViewCount(in: metrics)
        metrics[.totalViews] = viewCount

        let contentKeys = data[AnalyticsFirestoreSchema.RegionStatsField.contentKeys] as? [String: Any]
        let resolvedContentCount: Int
        if let contentKeys {
            resolvedContentCount = AnalyticsFirestoreSchema.activeContentCount(in: contentKeys)
        } else {
            resolvedContentCount = 0
        }
        guard AnalyticsFirestoreSchema.hasActiveRegionAnalytics(
            viewCount: viewCount,
            contentCount: resolvedContentCount
        ) else {
            return nil
        }

        return AnalyticsRegionStats(
            regionScope: normalizedRegionScope,
            federalState: federalState,
            viewCount: viewCount,
            contentCount: resolvedContentCount,
            metrics: metrics
        )
    }

    private func makeUserStats(
        from data: [String: Any],
        lifecycleCoverage: AnalyticsDetailCoverage
    ) -> AnalyticsUserStats {
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
            usersByFederalState: usersByFederalState,
            lifecycleCoverage: lifecycleCoverage
        )
    }

    private func makeActionStats(from dailyStats: [AnalyticsDailyStats]) -> AnalyticsActionStats {
        AnalyticsActionStats(
            newsLikes: dailyStats.map { $0.value(for: .newsLikes) }.reduce(0, +),
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
        data: [String: Any],
        coverage: AnalyticsDetailCoverage
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
                .sorted(by: AnalyticsDetailRegionStats.isOrderedByTrackedActivity),
            updatedAt: (data[AnalyticsFirestoreSchema.DetailStatsField.updatedAt] as? Timestamp)?.dateValue(),
            coverage: coverage
        )
    }

    private func makeOrganizationDetailSnapshot(
        period: AnalyticsPeriod,
        fallbackOrganizationID: String,
        data: [String: Any],
        coverage: AnalyticsDetailCoverage
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
                .sorted(by: AnalyticsDetailRegionStats.isOrderedByTrackedActivity),
            updatedAt: (data[AnalyticsFirestoreSchema.DetailStatsField.updatedAt] as? Timestamp)?.dateValue(),
            coverage: coverage
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
        AnalyticsFirestorePayloadResolver.preferredTopContentPayloads(
            array: data[AnalyticsFirestoreSchema.TopContentField.items],
            keyedMap: data[AnalyticsFirestoreSchema.TopContentField.itemsByKey]
        )
    }

    private func regionStatsPayloads(from data: [String: Any]) -> [[String: Any]] {
        AnalyticsFirestorePayloadResolver.preferredRegionPayloads(
            array: data[AnalyticsFirestoreSchema.RegionStatsField.regions],
            keyedMap: data[AnalyticsFirestoreSchema.RegionStatsField.regionsByKey]
        )
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
            return AnalyticsFirestorePayloadResolver.activeRegionSummary(from: dailyStats)
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
        metrics[.activeRegions] = metrics[.activeRegions] ?? intValue(data[AnalyticsFirestoreSchema.DailyStatsField.activeRegions])
        metrics[.newsLikes] = metrics[.newsLikes] ?? intValue(data[AnalyticsFirestoreSchema.DailyStatsField.totalLikes])
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

    private func dates(for period: AnalyticsPeriod, anchoredAt anchor: Date) -> [Date] {
        let today = calendar.startOfDay(for: anchor)
        return dates(endingAt: today, dayCount: period.dayCount)
    }

    private func periodDocumentID(for period: AnalyticsPeriod, anchoredAt anchor: Date) -> String {
        AnalyticsFirestoreSchema.PeriodDocumentID.value(
            for: period,
            now: anchor,
            calendar: calendar
        )
    }

    private func documentID(for date: Date) -> String {
        AnalyticsFirestoreSchema.dailyDocumentID(for: date, calendar: calendar)
    }

    private func dates(endingAt endDate: Date, dayCount: Int) -> [Date] {
        let normalizedEndDate = calendar.startOfDay(for: endDate)
        return (0..<dayCount).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: normalizedEndDate)
        }
    }

    private func normalizedDailyStats(
        for dates: [Date],
        from availableStats: [AnalyticsDailyStats]
    ) -> [AnalyticsDailyStats] {
        let statsByDocumentID = Dictionary(uniqueKeysWithValues: availableStats.map { stats in
            (documentID(for: stats.date), stats)
        })

        return dates.map { date in
            statsByDocumentID[documentID(for: date)]
                ?? AnalyticsDailyStats(date: calendar.startOfDay(for: date), metrics: [:])
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

    private func timestampDate(_ value: Any?) -> Date? {
        switch value {
        case let value as Timestamp:
            value.dateValue()
        case let value as Date:
            value
        default:
            nil
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
        if lhs.viewCount == rhs.viewCount {
            return lhs.contentID < rhs.contentID
        }

        return lhs.viewCount > rhs.viewCount
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
