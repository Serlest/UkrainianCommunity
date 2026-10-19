import Foundation

struct BannerMeasurementDailyCount: Equatable {
    let day: String
    let bannerID: String
    let section: FeaturedBannerVisibleSection
    let impressions: Int
    let clicks: Int
    var displayRegion: String? = nil
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

    let counts: [BannerMeasurementDailyCount]
    let regions: [String: BannerMeasurementTotals]
    let period: AnalyticsPeriod
    let generatedAt: Date
    let totals: BannerMeasurementTotals
    let sections: [FeaturedBannerVisibleSection: BannerMeasurementTotals]
    let banners: [BannerRow]
    let days: [DayRow]

    init(period: AnalyticsPeriod, counts: [BannerMeasurementDailyCount], generatedAt: Date = Date()) {
        self.counts = counts
        var regions: [String: BannerMeasurementTotals] = [:]
        for count in counts { regions[count.displayRegion ?? "unknown", default: .init()].add(count) }
        self.regions = regions
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


extension BannerMeasurementReport {
    var timeline: [DayRow] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let format = DateFormatter()
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd"
        let byDay = Dictionary(uniqueKeysWithValues: days.map { ($0.id, $0.totals) })
        return (0..<period.dayCount).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: generatedAt) else { return nil }
            let day = format.string(from: date)
            return DayRow(id: day, totals: byDay[day] ?? BannerMeasurementTotals())
        }
    }

    func filtered(bannerID: String?, region: String?, section: FeaturedBannerVisibleSection?) -> BannerMeasurementReport {
        BannerMeasurementReport(period: period, counts: counts.filter {
            (bannerID == nil || $0.bannerID == bannerID)
                && (region == nil || ($0.displayRegion ?? "unknown") == region)
                && (section == nil || $0.section == section)
        }, generatedAt: generatedAt)
    }

    func csv(titles: [String: String]) -> String {
        func escape(_ value: String) -> String {
            // Untrusted advertiser names must not become spreadsheet formulas.
            let first = value.trimmingCharacters(in: .whitespacesAndNewlines).first
            let safe = first.map { "=+-@".contains($0) } == true ? "'" + value : value
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let grouped = Dictionary(grouping: counts) {
            [$0.day, $0.bannerID, $0.section.rawValue, $0.displayRegion ?? "unknown"].joined(separator: "|")
        }
        var rows = ["day_utc,banner_id,banner_name,display_region,section,impressions,clicks,ctr_percent"]
        for key in grouped.keys.sorted() {
            guard let values = grouped[key], let row = values.first else { continue }
            var totals = BannerMeasurementTotals()
            values.forEach { totals.add($0) }
            let rate = totals.clickRate.map { String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), $0 * 100) } ?? ""
            rows.append([row.day, row.bannerID, titles[row.bannerID] ?? row.bannerID,
                         row.displayRegion ?? "unknown", row.section.rawValue,
                         String(totals.impressions), String(totals.clicks), rate].map(escape).joined(separator: ","))
        }
        return "\u{FEFF}" + rows.joined(separator: "\r\n") + "\r\n"
    }
}
