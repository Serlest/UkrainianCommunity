import Foundation

struct AnalyticsActionStats: Codable, Equatable {
    let newsLikes: Int
    let totalBookmarks: Int
    let eventRegistrations: Int
    let cancelledEventRegistrations: Int
    let organizationFollows: Int
    let organizationUnfollows: Int

    var hasData: Bool {
        newsLikes > 0
            || totalBookmarks > 0
            || eventRegistrations > 0
            || cancelledEventRegistrations > 0
            || organizationFollows > 0
            || organizationUnfollows > 0
    }

    static let empty = AnalyticsActionStats(
        newsLikes: 0,
        totalBookmarks: 0,
        eventRegistrations: 0,
        cancelledEventRegistrations: 0,
        organizationFollows: 0,
        organizationUnfollows: 0
    )
}
