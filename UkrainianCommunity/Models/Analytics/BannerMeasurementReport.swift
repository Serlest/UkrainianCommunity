import Foundation

struct BannerMeasurementDailyCount: Equatable {
    let day: String
    let bannerID: String
    let section: FeaturedBannerVisibleSection
    let impressions: Int
    let clicks: Int
}

struct BannerMeasurementTotals: Equatable {
    var impressions = 0
    var clicks = 0

    var clickRate: Double? {
        impressions > 0 ? Double(clicks) / Double(impressions) : nil
    }

    mutating func add(_ count: BannerMeasurementDailyCount) {
        impressions += count.impressions
        clicks += count.clicks
    }
}

struct BannerMeasurementReport {
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

    init(period: AnalyticsPeriod, counts: [BannerMeasurementDailyCount], generatedAt: Date = Date()) {
        self.period = period
        self.generatedAt = generatedAt

        var total = BannerMeasurementTotals()
        var bySection: [FeaturedBannerVisibleSection: BannerMeasurementTotals] = [:]
        var byBanner: [String: BannerMeasurementTotals] = [:]
        var byBannerSection: [String: [FeaturedBannerVisibleSection: BannerMeasurementTotals]] = [:]

        for count in counts {
            total.add(count)
            bySection[count.section, default: BannerMeasurementTotals()].add(count)
            byBanner[count.bannerID, default: BannerMeasurementTotals()].add(count)
            byBannerSection[count.bannerID, default: [:]][count.section, default: BannerMeasurementTotals()].add(count)
        }

        totals = total
        sections = bySection
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
