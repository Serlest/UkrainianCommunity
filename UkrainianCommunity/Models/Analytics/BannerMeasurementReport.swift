import Foundation

struct BannerMeasurementDailyCount: Equatable {
    let day: String
    let bannerID: String
    let section: FeaturedBannerVisibleSection
    let impressions: Int
    let clicks: Int
}

nonisolated struct BannerMeasurementTotals: Equatable, Sendable {
    var impressions = 0
    var clicks = 0

    var clickRate: Double? {
        impressions > 0 ? Double(clicks) / Double(impressions) : nil
    }

    @MainActor
    mutating func add(_ count: BannerMeasurementDailyCount) {
        impressions += count.impressions
        clicks += count.clicks
    }
}

struct BannerMeasurementReport {
    struct DayRow: Identifiable {
        let id: String
        let totals: BannerMeasurementTotals
    }

    struct BannerRow: Identifiable {
        let id: String
        let totals: BannerMeasurementTotals
        let sections: [FeaturedBannerVisibleSection: BannerMeasurementTotals]
    }

    let period: AnalyticsPeriod
    let generatedAt: Date
    let totals: BannerMeasurementTotals
    let sections: [FeaturedBannerVisibleSection: BannerMeasurementTotals]
    let banners: [BannerRow]
    let days: [DayRow]

    init(period: AnalyticsPeriod, counts: [BannerMeasurementDailyCount], generatedAt: Date = Date()) {
        self.period = period
        self.generatedAt = generatedAt

        var total = BannerMeasurementTotals()
        var bySection: [FeaturedBannerVisibleSection: BannerMeasurementTotals] = [:]
        var byBanner: [String: BannerMeasurementTotals] = [:]
        var byDay: [String: BannerMeasurementTotals] = [:]
        var byBannerSection: [String: [FeaturedBannerVisibleSection: BannerMeasurementTotals]] = [:]

        for count in counts {
            total.add(count)
            bySection[count.section, default: BannerMeasurementTotals()].add(count)
            byBanner[count.bannerID, default: BannerMeasurementTotals()].add(count)
            byDay[count.day, default: BannerMeasurementTotals()].add(count)
            byBannerSection[count.bannerID, default: [:]][count.section, default: BannerMeasurementTotals()].add(count)
        }

        totals = total
        sections = bySection
        days = byDay.map { DayRow(id: $0.key, totals: $0.value) }
            .sorted { $0.id > $1.id }
        banners = byBanner.map { id, totals in
            BannerRow(id: id, totals: totals, sections: byBannerSection[id] ?? [:])
        }.sorted { left, right in
            if left.totals.impressions != right.totals.impressions {
                return left.totals.impressions > right.totals.impressions
            }
            return left.id < right.id
        }
    }
}
