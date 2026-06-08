import Foundation

enum AnalyticsMetricType: String, CaseIterable, Codable, Identifiable {
    case totalViews
    case newsViews
    case eventViews
    case organizationViews
    case guideArticleViews
    case activeRegions
    case totalLikes
    case totalBookmarks
    case eventRegistrations
    case cancelledEventRegistrations
    case organizationFollows
    case organizationUnfollows

    var id: String { rawValue }
}
