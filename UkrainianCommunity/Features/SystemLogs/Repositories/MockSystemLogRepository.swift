import Foundation

struct MockSystemLogRepository: SystemLogRepositoryProtocol {
    private let entries: [SystemLogEntry]

    nonisolated init(entries: [SystemLogEntry] = MockSystemLogRepository.sampleEntries) {
        self.entries = entries
    }

    func fetchLogs(
        filter: SystemLogFilter,
        sortOption: SystemLogSortOption,
        limit: Int
    ) async throws -> [SystemLogEntry] {
        guard limit > 0 else { return [] }

        return entries
            .filter { entry in matches(entry, filter: filter) }
            .sorted { lhs, rhs in isOrderedBefore(lhs, rhs, sortOption: sortOption) }
            .prefix(limit)
            .map { $0 }
    }

    func fetchLog(id: String) async throws -> SystemLogEntry? {
        entries.first { $0.id == id }
    }

    func markReviewed(logID: String, reviewedByUserId: String) async throws {
        // Mock repository does not persist changes; the view model updates local state.
    }

    private func matches(_ entry: SystemLogEntry, filter: SystemLogFilter) -> Bool {
        if !filter.categories.isEmpty, !filter.categories.contains(entry.category) {
            return false
        }

        if !filter.severities.isEmpty, !filter.severities.contains(entry.severity) {
            return false
        }

        if !filter.eventTypes.isEmpty, !filter.eventTypes.contains(entry.eventType) {
            return false
        }

        if !filter.actorRoles.isEmpty, !filter.actorRoles.contains(entry.actorRole) {
            return false
        }

        if !filter.targetTypes.isEmpty, !filter.targetTypes.contains(entry.targetType) {
            return false
        }

        if !filter.outcomes.isEmpty, entry.outcome.map(filter.outcomes.contains) != true {
            return false
        }

        if let actorUserId = filter.actorUserId, entry.actorUserId != actorUserId {
            return false
        }

        if let targetId = filter.targetId, entry.targetId != targetId {
            return false
        }

        if let organizationId = filter.organizationId, entry.organizationId != organizationId {
            return false
        }

        if let isReviewed = filter.isReviewed, entry.isReviewed != isReviewed {
            return false
        }

        if let startDate = filter.startDate, entry.createdAt < startDate {
            return false
        }

        if let endDate = filter.endDate, entry.createdAt > endDate {
            return false
        }

        if let searchText = filter.searchText?.trimmingCharacters(in: .whitespacesAndNewlines), !searchText.isEmpty {
            return entry.summary.localizedCaseInsensitiveContains(searchText)
                || entry.technicalMessage?.localizedCaseInsensitiveContains(searchText) == true
                || entry.errorCode?.localizedCaseInsensitiveContains(searchText) == true
                || entry.actorDisplayName?.localizedCaseInsensitiveContains(searchText) == true
                || entry.targetTitle?.localizedCaseInsensitiveContains(searchText) == true
                || entry.organizationName?.localizedCaseInsensitiveContains(searchText) == true
                || entry.metadata.values.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }

        return true
    }

    private func isOrderedBefore(
        _ lhs: SystemLogEntry,
        _ rhs: SystemLogEntry,
        sortOption: SystemLogSortOption
    ) -> Bool {
        switch sortOption {
        case .newestFirst:
            lhs.createdAt > rhs.createdAt
        case .oldestFirst:
            lhs.createdAt < rhs.createdAt
        case .severityHighToLow:
            lhs.severity > rhs.severity
        case .severityLowToHigh:
            lhs.severity < rhs.severity
        case .category:
            lhs.category.rawValue < rhs.category.rawValue
        }
    }
}
