import Foundation

protocol SystemLogRepositoryProtocol {
    func fetchLogs(
        filter: SystemLogFilter,
        sortOption: SystemLogSortOption,
        limit: Int
    ) async throws -> [SystemLogEntry]

    func fetchNextPage() async throws -> [SystemLogEntry]

    func fetchLog(id: String) async throws -> SystemLogEntry?

    func markReviewed(logID: String, reviewedByUserId: String) async throws
    func markReviewed(logIDs: [String], reviewedByUserId: String) async throws

    func clearAllLogs() async throws -> Int
    func deleteLog(id: String) async throws
}

extension SystemLogRepositoryProtocol {
    func fetchNextPage() async throws -> [SystemLogEntry] { [] }

    func clearAllLogs() async throws -> Int { 0 }
    func deleteLog(id: String) async throws {}

    func markReviewed(logIDs: [String], reviewedByUserId: String) async throws {
        for logID in logIDs {
            try await markReviewed(logID: logID, reviewedByUserId: reviewedByUserId)
        }
    }

    func fetchLogs(
        filter: SystemLogFilter = .empty,
        sortOption: SystemLogSortOption = .newestFirst,
        limit: Int = 50
    ) async throws -> [SystemLogEntry] {
        try await fetchLogs(filter: filter, sortOption: sortOption, limit: limit)
    }
}
