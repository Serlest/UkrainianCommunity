import Foundation

struct AnalyticsUserStats: Codable, Equatable {
    let totalUsers: Int
    let newRegistrations: Int
    let deletedAccounts: Int
    let blockedUsers: Int
    let deactivatedUsers: Int
    let activeUsersToday: Int
    let activeUsersSevenDays: Int
    let activeUsersThirtyDays: Int
    let usersByFederalState: [AustrianFederalState: Int]

    var hasData: Bool {
        totalUsers > 0
            || newRegistrations > 0
            || deletedAccounts > 0
            || blockedUsers > 0
            || deactivatedUsers > 0
            || activeUsersToday > 0
            || activeUsersSevenDays > 0
            || activeUsersThirtyDays > 0
            || !usersByFederalState.isEmpty
    }

    static let empty = AnalyticsUserStats(
        totalUsers: 0,
        newRegistrations: 0,
        deletedAccounts: 0,
        blockedUsers: 0,
        deactivatedUsers: 0,
        activeUsersToday: 0,
        activeUsersSevenDays: 0,
        activeUsersThirtyDays: 0,
        usersByFederalState: [:]
    )
}
