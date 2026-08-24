import Foundation

enum AnalyticsMetricType: String, CaseIterable, Codable, Identifiable {
    case totalViews
    case newsViews
    case eventViews
    case organizationViews
    case activeRegions
    case newsLikes
    case totalBookmarks
    case eventRegistrations
    case cancelledEventRegistrations
    case organizationFollows
    case organizationUnfollows

    var id: String { rawValue }
}
