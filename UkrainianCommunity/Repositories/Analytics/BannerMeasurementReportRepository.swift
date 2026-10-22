import FirebaseFirestore
import Foundation
import CoreFoundation

protocol BannerMeasurementReportRepository {
    func fetch(period: AnalyticsPeriod) async throws -> BannerMeasurementReport
    func fetch(period: AnalyticsPeriod, bannerID: String?) async throws -> BannerMeasurementReport
}

extension BannerMeasurementReportRepository {
    func fetch(period: AnalyticsPeriod, bannerID: String?) async throws -> BannerMeasurementReport {
        try await fetch(period: period).filtered(bannerID: bannerID, region: nil, section: nil)
    }
}

struct FirestoreBannerMeasurementReportRepository: BannerMeasurementReportRepository {
    private let database = Firestore.firestore()
    private let pageSize = 500

    func fetch(period: AnalyticsPeriod) async throws -> BannerMeasurementReport {
        try await fetch(period: period, bannerID: nil)
    }

    func fetch(period: AnalyticsPeriod, bannerID: String?) async throws -> BannerMeasurementReport {
        let now = Date()
        let (firstDay, lastDay) = Self.utcDayRange(period: period, now: now)
        var collection: Query = database.collection("bannerMeasurementDailyShards")
        if let bannerID { collection = collection.whereField("bannerID", isEqualTo: bannerID) }
        let baseQuery = collection
            .whereField("day", isGreaterThanOrEqualTo: firstDay)
            .whereField("day", isLessThanOrEqualTo: lastDay)
            .order(by: "day")
            .limit(to: pageSize)

        var counts: [BannerMeasurementDailyCount] = []
        var lastDocument: QueryDocumentSnapshot?
        while true {
            let query = lastDocument.map { baseQuery.start(afterDocument: $0) } ?? baseQuery
            let page = try await query.getDocuments(source: .server)
            for document in page.documents {
                guard let count = Self.decode(document.data()) else {
                    throw AppError.validationFailed
                }
                counts.append(count)
            }
            guard page.documents.count == pageSize, let last = page.documents.last else { break }
            lastDocument = last
        }

        return BannerMeasurementReport(period: period, counts: counts, generatedAt: now)
    }

    static func utcDayRange(period: AnalyticsPeriod, now: Date) -> (String, String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(byAdding: .day, value: 1 - period.dayCount, to: now)!
        let format = DateFormatter()
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd"
        return (format.string(from: start), format.string(from: now))
    }

    static func decode(_ data: [String: Any]) -> BannerMeasurementDailyCount? {
        if let region = data["displayRegion"] {
            guard let name = region as? String,
                  name == "unknown" || name == "allAustria" || AustrianFederalState(rawValue: name) != nil else { return nil }
        }
        guard let day = data["day"] as? String,
              isValidUTCDay(day),
              let bannerID = data["bannerID"] as? String, !bannerID.isEmpty,
              let sectionName = data["section"] as? String,
              let section = FeaturedBannerVisibleSection(rawValue: sectionName), section.isSupported,
              let impressions = nonNegativeInteger(data["impressions"]),
              let clicks = nonNegativeInteger(data["clicks"]) else { return nil }
        return BannerMeasurementDailyCount(
            day: day, bannerID: bannerID, section: section,
            impressions: impressions, clicks: clicks, displayRegion: data["displayRegion"] as? String
        )
    }

    private static func isValidUTCDay(_ day: String) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return AnalyticsFirestoreSchema.date(forDailyDocumentID: day, calendar: calendar) != nil
    }

    private static func nonNegativeInteger(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let numeric = number.doubleValue
        guard numeric.isFinite, numeric >= 0, numeric.rounded(.towardZero) == numeric,
              numeric < Double(Int.max) else { return nil }
        return number.intValue
    }
}
