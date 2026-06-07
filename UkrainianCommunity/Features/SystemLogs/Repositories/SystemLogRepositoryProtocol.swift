import Foundation

protocol SystemLogRepositoryProtocol {
    func fetchLogs(
        filter: SystemLogFilter,
        sortOption: SystemLogSortOption,
        limit: Int
    ) async throws -> [SystemLogEntry]

    func fetchLog(id: String) async throws -> SystemLogEntry?

    func markReviewed(logID: String, reviewedByUserId: String) async throws
}

extension SystemLogRepositoryProtocol {
    func fetchLogs(
        filter: SystemLogFilter = .empty,
        sortOption: SystemLogSortOption = .newestFirst,
        limit: Int = 50
    ) async throws -> [SystemLogEntry] {
        try await fetchLogs(filter: filter, sortOption: sortOption, limit: limit)
    }
}
