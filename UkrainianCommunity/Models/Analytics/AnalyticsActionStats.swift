import Foundation

struct AnalyticsActionStats: Codable, Equatable {
    let totalLikes: Int
    let totalBookmarks: Int
    let eventRegistrations: Int
    let cancelledEventRegistrations: Int
    let organizationFollows: Int
    let organizationUnfollows: Int

    var hasData: Bool {
        totalLikes > 0
            || totalBookmarks > 0
            || eventRegistrations > 0
            || cancelledEventRegistrations > 0
            || organizationFollows > 0
            || organizationUnfollows > 0
    }

    static let empty = AnalyticsActionStats(
        totalLikes: 0,
        totalBookmarks: 0,
        eventRegistrations: 0,
        cancelledEventRegistrations: 0,
        organizationFollows: 0,
        organizationUnfollows: 0
    )
}
