import Foundation

enum AnalyticsFirestoreSchema {
    nonisolated static let analyticsTimeZone = TimeZone(identifier: "Europe/Vienna")!

    nonisolated static var analyticsCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = analyticsTimeZone
        return calendar
    }
    static let activeViewMetricTypes: [AnalyticsMetricType] = [
        .newsViews,
        .eventViews,
        .organizationViews
    ]

    static func activeViewCount(in metrics: [AnalyticsMetricType: Int]) -> Int {
        activeViewMetricTypes
            .map { metrics[$0, default: 0] }
            .reduce(0, +)
    }

    static func activeContentCount(in contentKeys: [String: Any]) -> Int {
        contentKeys.keys.filter { key in
            AnalyticsContentType.allCases.contains { key.hasPrefix("\($0.rawValue)_") }
        }.count
    }

    static func hasActiveRegionAnalytics(viewCount: Int, contentCount: Int) -> Bool {
        viewCount > 0 || contentCount > 0
    }

    enum Collection {
        static let dailyStats = "analyticsDailyStats"
        static let topContent = "analyticsTopContent"
        static let regionStats = "analyticsRegionStats"
        static let userStats = "analyticsUserStats"
        static let contentStats = "analyticsContentStats"
        static let organizationStats = "analyticsOrganizationStats"
    }

    enum PeriodDocumentID {
        static let today = "today"
        static let sevenDays = "seven_days"
        static let thirtyDays = "thirty_days"

        static func value(for period: AnalyticsPeriod) -> String {
            switch period {
            case .today:
                today
            case .sevenDays:
                sevenDays
            case .thirtyDays:
                thirtyDays
            }
        }

        static func value(
            for period: AnalyticsPeriod,
            now: Date,
            calendar: Calendar = AnalyticsFirestoreSchema.analyticsCalendar
        ) -> String {
            period == .today ? dailyDocumentID(for: now, calendar: calendar) : value(for: period)
        }
    }

    enum DailyStatsField {
        static let date = "date"
        static let metrics = "metrics"
        static let activeRegionKeys = "activeRegionKeys"
        static let totalViews = "totalViews"
        static let newsViews = "newsViews"
        static let eventViews = "eventViews"
        static let organizationViews = "organizationViews"
        static let activeRegions = "activeRegions"
        static let totalLikes = "totalLikes"
        static let newsLikes = "newsLikes"
        static let totalBookmarks = "totalBookmarks"
        static let eventRegistrations = "eventRegistrations"
        static let cancelledEventRegistrations = "cancelledEventRegistrations"
        static let organizationFollows = "organizationFollows"
        static let organizationUnfollows = "organizationUnfollows"
    }

    nonisolated enum TopContentField {
        static let items = "items"
        static let itemsByKey = "itemsByKey"
        static let contentID = "contentID"
        static let contentType = "contentType"
        static let title = "title"
        static let category = "category"
        static let organizationID = "organizationID"
        static let organizationName = "organizationName"
        static let regionScope = "regionScope"
        static let federalState = "federalState"
        static let viewCount = "viewCount"
        static let rank = "rank"
    }

    nonisolated enum RegionStatsField {
        static let regions = "regions"
        static let regionsByKey = "regionsByKey"
        static let regionScope = "regionScope"
        static let federalState = "federalState"
        static let viewCount = "viewCount"
        static let contentCount = "contentCount"
        static let contentKeys = "contentKeys"
        static let metrics = "metrics"
    }

    nonisolated enum UserStatsField {
        static let period = "period"
        static let generatedAt = "generatedAt"
        static let metrics = "metrics"
        static let totalUsers = "totalUsers"
        static let newRegistrations = "newRegistrations"
        static let deletedAccounts = "deletedAccounts"
        static let blockedUsers = "blockedUsers"
        static let deactivatedUsers = "deactivatedUsers"
        static let activeUsersToday = "activeUsersToday"
        static let activeUsersSevenDays = "activeUsersSevenDays"
        static let activeUsersThirtyDays = "activeUsersThirtyDays"
        static let usersByFederalState = "usersByFederalState"
        static let sourceDocumentIDs = "sourceDocumentIDs"
        static let lifecycleCoverageStartDay = "lifecycleCoverageStartDay"
        static let coveredLifecycleSourceDocumentIDs = "coveredLifecycleSourceDocumentIDs"
        static let isLifecyclePartialCoverage = "isLifecyclePartialCoverage"
    }

    nonisolated enum DetailStatsField {
        static let items = "items"
        static let organizations = "organizations"
        static let periodID = "periodId"
        static let contentID = "contentID"
        static let contentType = "contentType"
        static let contentTitle = "contentTitle"
        static let organizationID = "organizationID"
        static let organizationName = "organizationName"
        static let category = "category"
        static let federalState = "federalState"
        static let regionScope = "regionScope"
        static let metrics = "metrics"
        static let regionsByKey = "regionsByKey"
        static let topNews = "topNews"
        static let topEvents = "topEvents"
        static let updatedAt = "updatedAt"
        static let sourceDocumentIDs = "sourceDocumentIDs"
        static let rollupGeneration = "rollupGeneration"
        static let rollupInProgressGeneration = "rollupInProgressGeneration"
        static let coverageStartDay = "coverageStartDay"
        static let coveredSourceDocumentIDs = "coveredSourceDocumentIDs"
        static let isPartialCoverage = "isPartialCoverage"

        static let views = "views"
        static let likes = "likes"
        static let bookmarks = "bookmarks"
        static let registrations = "registrations"
        static let cancelledRegistrations = "cancelledRegistrations"
        static let follows = "follows"
        static let unfollows = "unfollows"
        static let profileViews = "profileViews"
        static let newsViews = "newsViews"
        static let eventViews = "eventViews"
        static let eventRegistrations = "eventRegistrations"
    }

    nonisolated static func dailyDocumentID(
        for date: Date,
        calendar: Calendar = analyticsCalendar
    ) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    nonisolated static func date(
        forDailyDocumentID documentID: String,
        calendar: Calendar = analyticsCalendar
    ) -> Date? {
        let components = documentID.split(separator: "-").compactMap { Int($0) }
        guard components.count == 3,
              documentID.count == 10,
              let date = calendar.date(from: DateComponents(
                timeZone: calendar.timeZone,
                year: components[0],
                month: components[1],
                day: components[2],
                hour: 12
              )),
              dailyDocumentID(for: date, calendar: calendar) == documentID else {
            return nil
        }
        return calendar.startOfDay(for: date)
    }

    nonisolated static func trailingDailyDocumentIDs(
        endingAt date: Date,
        dayCount: Int,
        calendar: Calendar = analyticsCalendar
    ) -> [String] {
        guard dayCount > 0 else { return [] }
        return (0..<dayCount).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: date).map {
                dailyDocumentID(for: $0, calendar: calendar)
            }
        }
    }
}
