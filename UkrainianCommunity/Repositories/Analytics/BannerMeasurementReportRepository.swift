import FirebaseFunctions
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
    func fetch(period: AnalyticsPeriod) async throws -> BannerMeasurementReport {
        try await fetch(period: period, bannerID: nil)
    }

    func fetch(period: AnalyticsPeriod, bannerID: String?) async throws -> BannerMeasurementReport {
        try Task.checkCancellation()
        var payload: [String: Any] = ["dayCount": period.dayCount]
        if let bannerID { payload["bannerID"] = bannerID }
        do {
            let result = try await Functions.functions(region: "europe-west3")
                .httpsCallable("getBannerMeasurementReport").call(payload)
            try Task.checkCancellation()
            guard let data = result.data as? [String: Any], data["calendar"] as? String == "UTC",
                  let rows = data["counts"] as? [[String: Any]],
                  let milliseconds = data["generatedAtMilliseconds"] as? NSNumber,
                  let anchor = data["periodAnchorMilliseconds"] as? NSNumber else {
                throw AppError.validationFailed
            }
            let counts = try rows.map { row in
                guard let count = Self.decode(row) else { throw AppError.validationFailed }
                return count
            }
            return BannerMeasurementReport(period: period, counts: counts,
                generatedAt: Date(timeIntervalSince1970: milliseconds.doubleValue / 1000),
                periodAnchor: Date(timeIntervalSince1970: anchor.doubleValue / 1000))
        } catch is CancellationError { throw CancellationError() }
        catch {
            if let appError = error as? AppError { throw appError }
            let failure = error as NSError
            if failure.domain == FunctionsErrorDomain {
                switch FunctionsErrorCode(rawValue: failure.code) {
                case .permissionDenied, .unauthenticated: throw AppError.permissionDenied
                case .unavailable, .deadlineExceeded: throw AppError.network
                default: break
                }
            }
            throw AppError.unknown
        }
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
