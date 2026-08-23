import Foundation

struct MockRecentViewsRepository: RecentViewsRepository {
    func fetchRecentViews(limit: Int) async throws -> [RecentViewItem] {
        []
    }

    func recordRecentView(_ item: RecentViewItem) async throws {}
}

struct MockActivityLogRepository: ActivityLogRepository {
    func fetchActivityLog(limit: Int) async throws -> [ActivityLogItem] {
        []
    }

    func recordActivity(_ item: ActivityLogItem) async throws {}
}
