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
