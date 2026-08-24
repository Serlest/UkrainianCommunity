import Foundation
import Testing
@testable import UkrainianCommunity

struct AnalyticsFirestoreRepositoryContractTests {
    @Test func freshKeyedTopContentWinsOverAnEmptyLegacyArray() throws {
        let payloads = AnalyticsFirestorePayloadResolver.preferredPayloads(
            array: [[String: Any]](),
            keyedMap: [
                "news_news__1": [
                    "contentID": "news-1",
                    "contentType": "news",
                    "viewCount": 7,
                ]
            ]
        )

        let payload = try #require(payloads.first)
        #expect(payloads.count == 1)
        #expect(payload["contentID"] as? String == "news-1")
        #expect(payload["viewCount"] as? Int == 7)
    }

    @Test func keyedPayloadWinsWhileTheMaterializedArrayIsStale() throws {
        let payloads = AnalyticsFirestorePayloadResolver.preferredPayloads(
            array: [["contentID": "stale", "viewCount": 1]],
            keyedMap: ["fresh": ["contentID": "fresh", "viewCount": 9]]
        )

        let payload = try #require(payloads.first)
        #expect(payloads.count == 1)
        #expect(payload["contentID"] as? String == "fresh")
        #expect(payload["viewCount"] as? Int == 9)
    }

    @Test func malformedKeyedTopContentFallsBackAfterSemanticValidation() throws {
        let payloads = AnalyticsFirestorePayloadResolver.preferredTopContentPayloads(
            array: [[
                "contentID": "legacy",
                "contentType": "news",
                "viewCount": 3,
            ]],
            keyedMap: [
                "broken": [
                    "contentID": "broken",
                    "contentType": "news",
                    "viewCount": 0,
                ]
            ]
        )

        let payload = try #require(payloads.first)
        #expect(payloads.count == 1)
        #expect(payload["contentID"] as? String == "legacy")
    }

    @Test func malformedKeyedRegionFallsBackAfterSemanticValidation() throws {
        let payloads = AnalyticsFirestorePayloadResolver.preferredRegionPayloads(
            array: [[
                "regionScope": "federalState",
                "federalState": "wien",
                "metrics": ["newsViews": 3],
            ]],
            keyedMap: [
                "broken": [
                    "regionScope": "federalState",
                    "federalState": "unknown",
                    "metrics": ["newsViews": 9],
                ]
            ]
        )

        let payload = try #require(payloads.first)
        #expect(payloads.count == 1)
        #expect(payload["federalState"] as? String == "wien")
    }

    @Test func rollupAvailabilityRequiresBothFreshnessAndAStructuralPayload() {
        let updatedAt = Date(timeIntervalSince1970: 1_777_593_600)

        #expect(AnalyticsFirestorePayloadResolver.isTimestampedRollupAvailable(
            updatedAt: updatedAt,
            arrayPayload: [[String: Any]](),
            keyedMapPayload: nil
        ))
        #expect(AnalyticsFirestorePayloadResolver.isTimestampedRollupAvailable(
            updatedAt: updatedAt,
            arrayPayload: nil,
            keyedMapPayload: [String: Any]()
        ))
        #expect(!AnalyticsFirestorePayloadResolver.isTimestampedRollupAvailable(
            updatedAt: nil,
            arrayPayload: [[String: Any]](),
            keyedMapPayload: nil
        ))
        #expect(!AnalyticsFirestorePayloadResolver.isTimestampedRollupAvailable(
            updatedAt: updatedAt,
            arrayPayload: "malformed",
            keyedMapPayload: nil
        ))
    }

    @Test func userStatsAvailabilityRequiresTheCompleteMaterializedContract() {
        let generatedAt = Date(timeIntervalSince1970: 1_777_593_600)
        let data = completeUserStatsPayload()

        #expect(AnalyticsFirestorePayloadResolver.isUserStatsAvailable(
            data: data,
            expectedPeriodDocumentID: "seven_days",
            generatedAt: generatedAt,
            expectedSourceCount: 7
        ))

        let requiredFields = [
            AnalyticsFirestoreSchema.UserStatsField.totalUsers,
            AnalyticsFirestoreSchema.UserStatsField.newRegistrations,
            AnalyticsFirestoreSchema.UserStatsField.deletedAccounts,
            AnalyticsFirestoreSchema.UserStatsField.blockedUsers,
            AnalyticsFirestoreSchema.UserStatsField.deactivatedUsers,
            AnalyticsFirestoreSchema.UserStatsField.activeUsersToday,
            AnalyticsFirestoreSchema.UserStatsField.activeUsersSevenDays,
            AnalyticsFirestoreSchema.UserStatsField.activeUsersThirtyDays,
        ]
        for field in requiredFields {
            var incomplete = data
            var metrics = incomplete[AnalyticsFirestoreSchema.UserStatsField.metrics] as? [String: Any] ?? [:]
            metrics.removeValue(forKey: field)
            incomplete[AnalyticsFirestoreSchema.UserStatsField.metrics] = metrics

            #expect(!AnalyticsFirestorePayloadResolver.isUserStatsAvailable(
                data: incomplete,
                expectedPeriodDocumentID: "seven_days",
                generatedAt: generatedAt,
                expectedSourceCount: 7
            ))
        }
    }

    @Test func userStatsAvailabilityRejectsMissingFreshnessAndMalformedValues() {
        let generatedAt = Date(timeIntervalSince1970: 1_777_593_600)
        let data = completeUserStatsPayload()

        #expect(!AnalyticsFirestorePayloadResolver.isUserStatsAvailable(
            data: data,
            expectedPeriodDocumentID: "seven_days",
            generatedAt: nil,
            expectedSourceCount: 7
        ))
        #expect(!AnalyticsFirestorePayloadResolver.isUserStatsAvailable(
            data: data,
            expectedPeriodDocumentID: "thirty_days",
            generatedAt: generatedAt,
            expectedSourceCount: 7
        ))

        var malformedMetricData = data
        var metrics = malformedMetricData[AnalyticsFirestoreSchema.UserStatsField.metrics] as? [String: Any] ?? [:]
        metrics[AnalyticsFirestoreSchema.UserStatsField.deletedAccounts] = -1
        malformedMetricData[AnalyticsFirestoreSchema.UserStatsField.metrics] = metrics
        #expect(!AnalyticsFirestorePayloadResolver.isUserStatsAvailable(
            data: malformedMetricData,
            expectedPeriodDocumentID: "seven_days",
            generatedAt: generatedAt,
            expectedSourceCount: 7
        ))

        var malformedRegionData = data
        malformedRegionData[AnalyticsFirestoreSchema.UserStatsField.usersByFederalState] = [
            "unknown": 1
        ]
        #expect(!AnalyticsFirestorePayloadResolver.isUserStatsAvailable(
            data: malformedRegionData,
            expectedPeriodDocumentID: "seven_days",
            generatedAt: generatedAt,
            expectedSourceCount: 7
        ))

        var missingCoverageData = data
        missingCoverageData.removeValue(
            forKey: AnalyticsFirestoreSchema.UserStatsField.lifecycleCoverageStartDay
        )
        #expect(!AnalyticsFirestorePayloadResolver.isUserStatsAvailable(
            data: missingCoverageData,
            expectedPeriodDocumentID: "seven_days",
            generatedAt: generatedAt,
            expectedSourceCount: 7
        ))

        var nonContiguousCoverageData = data
        nonContiguousCoverageData[AnalyticsFirestoreSchema.UserStatsField.sourceDocumentIDs] = [
            "2026-08-24", "2026-08-22", "2026-08-23", "2026-08-21",
            "2026-08-20", "2026-08-19", "2026-08-18"
        ]
        #expect(!AnalyticsFirestorePayloadResolver.isUserStatsAvailable(
            data: nonContiguousCoverageData,
            expectedPeriodDocumentID: "seven_days",
            generatedAt: generatedAt,
            expectedSourceCount: 7
        ))
    }

    @Test func detailRollupRequiresACompletedGeneration() throws {
        let completedAt = Date(timeIntervalSince1970: 1_777_593_600)
        let rootData: [String: Any] = [
            AnalyticsFirestoreSchema.DetailStatsField.periodID: "seven_days",
            AnalyticsFirestoreSchema.DetailStatsField.rollupGeneration: "generation-2",
            AnalyticsFirestoreSchema.DetailStatsField.updatedAt: completedAt,
        ]

        let generation = try #require(
            AnalyticsFirestorePayloadResolver.completedDetailRollupGeneration(
                rootData: rootData,
                expectedPeriodDocumentID: "seven_days"
            )
        )
        #expect(generation == "generation-2")
        #expect(AnalyticsFirestorePayloadResolver.isDetailPayloadFromCompletedRollup(
            [
                AnalyticsFirestoreSchema.DetailStatsField.periodID: "seven_days",
                AnalyticsFirestoreSchema.DetailStatsField.rollupGeneration: generation,
                AnalyticsFirestoreSchema.DetailStatsField.updatedAt: completedAt,
            ],
            expectedPeriodDocumentID: "seven_days",
            completedGeneration: generation
        ))
    }

    @Test func detailRollupRejectsInProgressAndMixedGenerations() {
        let completedAt = Date(timeIntervalSince1970: 1_777_593_600)
        let refreshingRoot: [String: Any] = [
            AnalyticsFirestoreSchema.DetailStatsField.periodID: "seven_days",
            AnalyticsFirestoreSchema.DetailStatsField.rollupGeneration: "generation-1",
            AnalyticsFirestoreSchema.DetailStatsField.rollupInProgressGeneration: "generation-2",
            AnalyticsFirestoreSchema.DetailStatsField.updatedAt: completedAt,
        ]

        #expect(AnalyticsFirestorePayloadResolver.completedDetailRollupGeneration(
            rootData: refreshingRoot,
            expectedPeriodDocumentID: "seven_days"
        ) == nil)
        #expect(!AnalyticsFirestorePayloadResolver.isDetailPayloadFromCompletedRollup(
            [
                AnalyticsFirestoreSchema.DetailStatsField.periodID: "seven_days",
                AnalyticsFirestoreSchema.DetailStatsField.rollupGeneration: "generation-2",
                AnalyticsFirestoreSchema.DetailStatsField.updatedAt: completedAt,
            ],
            expectedPeriodDocumentID: "seven_days",
            completedGeneration: "generation-1"
        ))
        #expect(!AnalyticsFirestorePayloadResolver.didDetailRollupRemainCompleted(
            rootData: refreshingRoot,
            expectedPeriodDocumentID: "seven_days",
            completedGeneration: "generation-1"
        ))

        let unchangedRoot: [String: Any] = [
            AnalyticsFirestoreSchema.DetailStatsField.periodID: "seven_days",
            AnalyticsFirestoreSchema.DetailStatsField.rollupGeneration: "generation-1",
            AnalyticsFirestoreSchema.DetailStatsField.updatedAt: completedAt,
        ]
        #expect(AnalyticsFirestorePayloadResolver.didDetailRollupRemainCompleted(
            rootData: unchangedRoot,
            expectedPeriodDocumentID: "seven_days",
            completedGeneration: "generation-1"
        ))
    }

    @Test func detailCoverageRequiresTheExactContiguousTrailingWindow() throws {
        let valid: [String: Any] = [
            AnalyticsFirestoreSchema.DetailStatsField.sourceDocumentIDs: [
                "2026-08-24", "2026-08-23", "2026-08-22", "2026-08-21",
                "2026-08-20", "2026-08-19", "2026-08-18"
            ],
            AnalyticsFirestoreSchema.DetailStatsField.coverageStartDay: "2026-08-22",
            AnalyticsFirestoreSchema.DetailStatsField.coveredSourceDocumentIDs: [
                "2026-08-24", "2026-08-23", "2026-08-22"
            ],
            AnalyticsFirestoreSchema.DetailStatsField.isPartialCoverage: true,
        ]
        let coverage = try #require(
            AnalyticsFirestorePayloadResolver.completedDetailCoverage(
                rootData: valid,
                expectedSourceCount: 7
            )
        )
        #expect(coverage.isPartial)
        #expect(coverage.startsAt != nil)

        var reordered = valid
        reordered[AnalyticsFirestoreSchema.DetailStatsField.sourceDocumentIDs] = [
            "2026-08-24", "2026-08-22", "2026-08-23", "2026-08-21",
            "2026-08-20", "2026-08-19", "2026-08-18"
        ]
        #expect(AnalyticsFirestorePayloadResolver.completedDetailCoverage(
            rootData: reordered,
            expectedSourceCount: 7
        ) == nil)

        var falseComplete = valid
        falseComplete[AnalyticsFirestoreSchema.DetailStatsField.isPartialCoverage] = false
        #expect(AnalyticsFirestorePayloadResolver.completedDetailCoverage(
            rootData: falseComplete,
            expectedSourceCount: 7
        ) == nil)
    }

    @Test func freshnessExcludesUnavailableOptionalSources() throws {
        let daily = Date(timeIntervalSince1970: 30)
        let unavailableOldValue = Date(timeIntervalSince1970: 10)
        let availableOldestValue = Date(timeIntervalSince1970: 20)
        let newestValue = Date(timeIntervalSince1970: 25)

        let result = AnalyticsFirestorePayloadResolver.oldestAvailableUpdate(
            dailyUpdatedAt: daily,
            sources: [
                (unavailableOldValue, false),
                (availableOldestValue, true),
                (newestValue, true),
            ]
        )

        #expect(try #require(result) == availableOldestValue)
    }

    @Test func legacyArrayRemainsAValidFallback() throws {
        let payloads = AnalyticsFirestorePayloadResolver.preferredPayloads(
            array: [["contentID": "legacy", "viewCount": 3]],
            keyedMap: [String: Any]()
        )

        let payload = try #require(payloads.first)
        #expect(payload["contentID"] as? String == "legacy")
    }

    @Test func legacyActiveRegionScalarIsNotOverwrittenWhenKeyMapIsAbsent() {
        #expect(
            AnalyticsFirestorePayloadResolver.activeRegionCount(
                from: nil,
                legacyValue: 4
            ) == 4
        )
    }

    @Test func modernActiveRegionKeysReplaceTheLegacyScalar() {
        #expect(
            AnalyticsFirestorePayloadResolver.activeRegionCount(
                from: ["wien": true, "tirol": true, "stale": false],
                legacyValue: 99
            ) == 2
        )
    }

    @Test func legacyActiveRegionSummaryUsesAnHonestLowerBound() {
        let calendar = AnalyticsFirestoreSchema.analyticsCalendar
        let firstDay = Date(timeIntervalSince1970: 1_777_593_600)
        let secondDay = calendar.date(byAdding: .day, value: 1, to: firstDay) ?? firstDay
        let stats = [
            AnalyticsDailyStats(date: firstDay, metrics: [.activeRegions: 3]),
            AnalyticsDailyStats(date: secondDay, metrics: [.activeRegions: 5]),
        ]

        #expect(AnalyticsFirestorePayloadResolver.activeRegionSummary(from: stats) == 5)
    }

    @Test func modernActiveRegionSummaryUnionsStableKeysAcrossDays() {
        let calendar = AnalyticsFirestoreSchema.analyticsCalendar
        let firstDay = Date(timeIntervalSince1970: 1_777_593_600)
        let secondDay = calendar.date(byAdding: .day, value: 1, to: firstDay) ?? firstDay
        let stats = [
            AnalyticsDailyStats(
                date: firstDay,
                metrics: [.activeRegions: 2],
                activeRegionKeys: ["federal_state:wien", "federal_state:tirol"]
            ),
            AnalyticsDailyStats(
                date: secondDay,
                metrics: [.activeRegions: 2],
                activeRegionKeys: ["federal_state:tirol", "federal_state:salzburg"]
            ),
        ]

        #expect(AnalyticsFirestorePayloadResolver.activeRegionSummary(from: stats) == 3)
    }

    @Test func missingRollupsAreReportedOnlyWhenTheirDataIsExpected() {
        let unavailable = AnalyticsFirestorePayloadResolver.unavailableSources(
            totalViews: 12,
            activeRegionCount: 2,
            isTopContentAvailable: false,
            areContentRegionsAvailable: false,
            areUsersAvailable: false
        )

        #expect(unavailable == [.topContent, .contentRegions, .users])
    }

    @Test func emptyViewPeriodDoesNotRequireTopContentOrContentRegions() {
        let unavailable = AnalyticsFirestorePayloadResolver.unavailableSources(
            totalViews: 0,
            activeRegionCount: 0,
            isTopContentAvailable: false,
            areContentRegionsAvailable: false,
            areUsersAvailable: true
        )

        #expect(unavailable.isEmpty)
    }

    @Test func legacyCityAndFederalStateBucketsMergeWithoutDoubleLabelRows() throws {
        let regions = AnalyticsFirestorePayloadResolver.mergedRegionStats([
            AnalyticsRegionStats(
                regionScope: .federalState,
                federalState: .wien,
                viewCount: 4,
                contentCount: 2,
                metrics: [.newsViews: 4]
            ),
            AnalyticsRegionStats(
                regionScope: .federalState,
                federalState: .wien,
                viewCount: 3,
                contentCount: 2,
                metrics: [.eventViews: 3]
            ),
        ])

        let region = try #require(regions.first)
        #expect(regions.count == 1)
        #expect(region.viewCount == 7)
        #expect(region.contentCount == 2)
        #expect(region.metrics == [.newsViews: 4, .eventViews: 3])
    }

    @Test func legacyCityActivityKeyNormalizesToItsFederalState() {
        #expect(
            AnalyticsFirestorePayloadResolver.activeRegionKeys(
                from: ["city_wien": true, "federalState_wien": true]
            ) == ["federalState_wien"]
        )
    }

    private func completeUserStatsPayload() -> [String: Any] {
        [
            AnalyticsFirestoreSchema.UserStatsField.period: "seven_days",
            AnalyticsFirestoreSchema.UserStatsField.metrics: [
                AnalyticsFirestoreSchema.UserStatsField.totalUsers: 10,
                AnalyticsFirestoreSchema.UserStatsField.newRegistrations: 2,
                AnalyticsFirestoreSchema.UserStatsField.deletedAccounts: 1,
                AnalyticsFirestoreSchema.UserStatsField.blockedUsers: 0,
                AnalyticsFirestoreSchema.UserStatsField.deactivatedUsers: 0,
                AnalyticsFirestoreSchema.UserStatsField.activeUsersToday: 3,
                AnalyticsFirestoreSchema.UserStatsField.activeUsersSevenDays: 7,
                AnalyticsFirestoreSchema.UserStatsField.activeUsersThirtyDays: 9,
            ],
            AnalyticsFirestoreSchema.UserStatsField.usersByFederalState: [
                AustrianFederalState.wien.rawValue: 5,
                AustrianFederalState.tirol.rawValue: 2,
            ],
            AnalyticsFirestoreSchema.UserStatsField.sourceDocumentIDs: [
                "2026-08-24", "2026-08-23", "2026-08-22", "2026-08-21",
                "2026-08-20", "2026-08-19", "2026-08-18"
            ],
            AnalyticsFirestoreSchema.UserStatsField.lifecycleCoverageStartDay:
                "2026-08-22",
            AnalyticsFirestoreSchema.UserStatsField.coveredLifecycleSourceDocumentIDs: [
                "2026-08-24", "2026-08-23", "2026-08-22"
            ],
            AnalyticsFirestoreSchema.UserStatsField.isLifecyclePartialCoverage: true,
        ]
    }
}
