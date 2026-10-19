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
