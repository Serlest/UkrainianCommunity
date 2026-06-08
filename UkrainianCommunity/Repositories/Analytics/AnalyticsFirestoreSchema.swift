import Foundation

enum AnalyticsFirestoreSchema {
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
    }

    enum DailyStatsField {
        static let date = "date"
        static let metrics = "metrics"
        static let activeRegionKeys = "activeRegionKeys"
        static let totalViews = "totalViews"
        static let newsViews = "newsViews"
        static let eventViews = "eventViews"
        static let organizationViews = "organizationViews"
        static let guideArticleViews = "guideArticleViews"
        static let activeRegions = "activeRegions"
        static let totalLikes = "totalLikes"
        static let totalBookmarks = "totalBookmarks"
        static let eventRegistrations = "eventRegistrations"
        static let cancelledEventRegistrations = "cancelledEventRegistrations"
        static let organizationFollows = "organizationFollows"
        static let organizationUnfollows = "organizationUnfollows"
    }

    enum TopContentField {
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

    enum RegionStatsField {
        static let regions = "regions"
        static let regionsByKey = "regionsByKey"
        static let regionScope = "regionScope"
        static let federalState = "federalState"
        static let viewCount = "viewCount"
        static let contentCount = "contentCount"
        static let contentKeys = "contentKeys"
        static let metrics = "metrics"
    }

    enum UserStatsField {
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
    }

    enum DetailStatsField {
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

    static func dailyDocumentID(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
