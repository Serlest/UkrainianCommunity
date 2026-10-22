import Foundation
import Testing
@testable import UkrainianCommunity

struct BannerMeasurementReportTests {
    @Test func shardsAreSummedWithoutMixingBannersOrSections() {
        let counts = [
            BannerMeasurementDailyCount(day: "2026-10-11", bannerID: "a", section: .home,
                                        impressions: 10, clicks: 2),
            BannerMeasurementDailyCount(day: "2026-10-11", bannerID: "a", section: .home,
                                        impressions: 4, clicks: 1),
            BannerMeasurementDailyCount(day: "2026-10-12", bannerID: "a", section: .events,
                                        impressions: 6, clicks: 0),
            BannerMeasurementDailyCount(day: "2026-10-12", bannerID: "b", section: .home,
                                        impressions: 2, clicks: 1),
        ]
        let report = BannerMeasurementReport(period: .sevenDays, counts: counts)

        #expect(report.totals == BannerMeasurementTotals(impressions: 22, clicks: 4))
        #expect(report.totals.clickRate == 4.0 / 22.0)
        #expect(report.sections[.home] == BannerMeasurementTotals(impressions: 16, clicks: 4))
        #expect(report.days.map(\.id) == ["2026-10-12", "2026-10-11"])
        #expect(report.days[0].totals == BannerMeasurementTotals(impressions: 8, clicks: 1))
        #expect(report.banners.map(\.id) == ["a", "b"])
        #expect(report.banners[0].sections[.events] == BannerMeasurementTotals(impressions: 6, clicks: 0))
        #expect(BannerMeasurementTotals().clickRate == nil)
    }

    @Test func reportingPeriodUsesUTCAndRejectsMalformedShards() {
        let now = Date(timeIntervalSince1970: 1_760_310_600)
        let days = FirestoreBannerMeasurementReportRepository.utcDayRange(period: .sevenDays, now: now)
        #expect(days.0 <= days.1)
        #expect(days.0 == "2025-10-06")
        #expect(days.1 == "2025-10-12")

        let valid: [String: Any] = [
            "day": "2026-10-12", "bannerID": "a", "section": "home",
            "impressions": 3, "clicks": 1,
        ]
        #expect(FirestoreBannerMeasurementReportRepository.decode(valid)?.clicks == 1)
        #expect(FirestoreBannerMeasurementReportRepository.decode(valid.merging(["clicks": -1]) { _, new in new }) == nil)
        #expect(FirestoreBannerMeasurementReportRepository.decode(valid.merging(["section": "guide"]) { _, new in new }) == nil)
    }
}

extension BannerMeasurementReportTests {
    @Test func filtersKeepUnknownSeparateAndExportCannotExecuteFormulas() {
        let counts = [
            BannerMeasurementDailyCount(day: "2026-10-19", bannerID: "a", section: .home,
                impressions: 8, clicks: 2, displayRegion: "tirol"),
            BannerMeasurementDailyCount(day: "2026-10-19", bannerID: "a", section: .home,
                impressions: 2, clicks: 1, displayRegion: "tirol"),
            BannerMeasurementDailyCount(day: "2026-10-19", bannerID: "a", section: .events,
                impressions: 4, clicks: 0, displayRegion: "wien"),
            BannerMeasurementDailyCount(day: "2026-10-19", bannerID: "b", section: .home,
                impressions: 3, clicks: 1),
        ]
        let report = BannerMeasurementReport(period: .sevenDays, counts: counts)
        #expect(report.regions["unknown"]?.impressions == 3)
        let filtered = report.filtered(bannerID: "a", region: "tirol", section: .home)
        #expect(filtered.totals == BannerMeasurementTotals(impressions: 10, clicks: 3))
        #expect(filtered.totals.clickRate == 0.3)
        #expect(report.filtered(bannerID: nil, region: "salzburg", section: nil).counts.isEmpty)
        let csv = filtered.csv(titles: ["a": "=HYPERLINK(\"x\")"])
        #expect(csv.contains("'" + "=HYPERLINK"))
        #expect(csv.contains("30.0000"))
        #expect(csv.components(separatedBy: "\r\n").count == 3) // header + one merged row + final newline
    }

    @Test @MainActor func queuedRegionSurvivesSerializationAndLegacyMissingRegionDecodes() throws {
        let measurement = FeaturedBannerMeasurement(id: UUID(), bannerID: "a", section: .home,
            kind: .click, occurredAt: Date(), displayRegion: "wien")
        let event = BannerMeasurementQueuedEvent(measurement, consentID: "consent")
        let restored = try JSONDecoder().decode(BannerMeasurementQueuedEvent.self, from: JSONEncoder().encode(event))
        #expect(restored.payload["displayRegion"] as? String == "wien")
        var data = try JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as! [String: Any]
        data.removeValue(forKey: "displayRegion")
        let legacy = try JSONDecoder().decode(BannerMeasurementQueuedEvent.self, from: JSONSerialization.data(withJSONObject: data))
        #expect(legacy.displayRegion == nil)
        #expect(legacy.payload["displayRegion"] == nil)
    }
}


extension BannerMeasurementReportTests {
    @Test @MainActor func freshReportDoesNotClaimToUpdateInTheFuture() {
        let now = Date()
        for language in ["uk", "de"] {
            let locale = Locale(identifier: language)
            #expect(OwnerAnalyticsDateFormatting.relativeFreshnessText(now.addingTimeInterval(0.1), relativeTo: now, locale: locale)
                == OwnerAnalyticsDateFormatting.relativeFreshnessText(now, relativeTo: now, locale: locale))
        }
    }
}

@MainActor
private struct BannerCatalogMetricsFixture: BannerMeasurementReportRepository {
    func fetch(period: AnalyticsPeriod) async throws -> BannerMeasurementReport {
        BannerMeasurementReport(period: period, counts: [
            .init(day: "2026-10-22", bannerID: "a", section: .home, impressions: 20, clicks: 4, displayRegion: "tirol"),
            .init(day: "2026-10-22", bannerID: "b", section: .events, impressions: 10, clicks: 1, displayRegion: "wien"),
            .init(day: "2026-10-22", bannerID: "deleted", section: .home, impressions: 5, clicks: 2)
        ])
    }
}

extension BannerMeasurementReportTests {
    @Test @MainActor func currentCatalogIncludesZeroAndInactiveButHistoricalTotalsSurviveDeletion() async throws {
        let banners = ["a", "b", "zero"].map { id in
            FeaturedBanner(id: id, title: id, actionType: .externalURL, externalURL: "https://example.com",
                visibleSections: [.home], isActive: id != "b", createdAt: .now, updatedAt: .now, createdBy: "fixture")
        }
        let repository = MockFeaturedBannerRepository(banners: banners)
        let model = BannerMeasurementReportViewModel(repository: BannerCatalogMetricsFixture(), bannerRepository: repository, initialPeriod: .thirtyDays)
        await model.load()
        #expect(Set(model.displayedBanners.map(\.id)) == ["a", "b", "zero"])
        #expect(model.visibleReport?.totals.clicks == 7)
        #expect(model.visibleReport?.filtered(bannerID: "zero", region: nil, section: nil).totals.clicks == 0)
        #expect(model.exportReport()?.counts.contains { $0.bannerID == "deleted" } == false)
        #expect(model.exportReport()?.totals == model.visibleReport?.totals)
        model.selectedBannerID = "b"
        #expect(model.visibleReport?.totals.clicks == 1)
        #expect(model.displayedBanners.map(\.id) == ["b"])
    }

    @Test @MainActor func fixedBannerNeverFallsBackToAllBannersAndDeletedDetailIsUnavailable() async {
        let banner = FeaturedBanner(id: "a", title: "A", actionType: .externalURL, externalURL: "https://example.com",
            visibleSections: [.home], createdAt: .now, updatedAt: .now, createdBy: "fixture")
        let repository = MockFeaturedBannerRepository(banners: [banner])
        let model = BannerMeasurementReportViewModel(repository: BannerCatalogMetricsFixture(), bannerRepository: repository,
            initialPeriod: .thirtyDays, bannerID: "a")
        await model.load()
        #expect(model.visibleReport?.totals.clicks == 4)
        model.selectedBannerID = "b"
        #expect(model.visibleReport?.totals.clicks == 4)
        model.selectedRegion = "wien"
        #expect(model.visibleReport?.totals.clicks == 0)
        let deleted = BannerMeasurementReportViewModel(repository: BannerCatalogMetricsFixture(), bannerRepository: repository,
            initialPeriod: .sevenDays, bannerID: "deleted")
        await deleted.load()
        #expect(deleted.bannerUnavailable)
        #expect(deleted.visibleReport == nil)
        #expect(deleted.exportReport() == nil)
    }
}

extension BannerMeasurementReportTests {
    @Test func malformedDatesBooleansAndFractionalCountsNeverBecomeBannerMetrics() {
        let valid: [String: Any] = ["day": "2026-10-22", "bannerID": "a", "section": "home", "impressions": NSNumber(value: 1), "clicks": NSNumber(value: 0)]
        #expect(FirestoreBannerMeasurementReportRepository.decode(valid)?.impressions == 1)
        for day in ["2026-99-99", "2026-02-30", "2026-1-022", "abcdefghij"] {
            #expect(FirestoreBannerMeasurementReportRepository.decode(valid.merging(["day": day]) { _, v in v }) == nil)
        }
        for bad: Any in [true, NSNumber(value: false), NSNumber(value: 0.5), Double.infinity, Double.nan, -1] {
            for field in ["impressions", "clicks"] {
                #expect(FirestoreBannerMeasurementReportRepository.decode(valid.merging([field: bad]) { _, v in v }) == nil)
            }
        }
    }

    @Test func reportTimelineAndQueryShareTheSameAnchorAcrossMidnightUTC() throws {
        let anchor = try #require(ISO8601DateFormatter().date(from: "2026-10-22T23:59:59Z"))
        let (first, last) = FirestoreBannerMeasurementReportRepository.utcDayRange(period: .sevenDays, now: anchor)
        let report = BannerMeasurementReport(period: .sevenDays, counts: [
            .init(day: first, bannerID: "a", section: .home, impressions: 7, clicks: 1),
            .init(day: last, bannerID: "a", section: .home, impressions: 3, clicks: 1)
        ], generatedAt: anchor)
        #expect(report.timeline.first?.id == first)
        #expect(report.timeline.last?.id == last)
        #expect(report.timeline.reduce(0) { $0 + $1.totals.impressions } == report.totals.impressions)
    }
}
