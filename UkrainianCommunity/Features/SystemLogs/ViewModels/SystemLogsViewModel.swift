import Combine
import FirebaseAuth
import Foundation

@MainActor
final class SystemLogsViewModel: ObservableObject {
    @Published private(set) var logs: [SystemLogEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var searchText = ""
    @Published var selectedSection: SystemLogDashboardSection = .all
    @Published private(set) var selectedFilters: Set<SystemLogQuickFilter> = []
    @Published private(set) var reviewingLogIDs: Set<String> = []
    @Published private(set) var reviewErrorMessages: [String: String] = [:]

    private let repository: SystemLogRepositoryProtocol
    let accessMode: SystemLogsAccessMode
    let calendar: Calendar
    let nowProvider: () -> Date
    private let reviewerUserIdProvider: () -> String?
    private let fetchLimit = 100
    private var hasLoadedInitialPage = false

    init(
        repository: SystemLogRepositoryProtocol? = nil,
        accessMode: SystemLogsAccessMode = .owner,
        calendar: Calendar = .current,
        nowProvider: @escaping () -> Date = Date.init,
        reviewerUserIdProvider: @escaping () -> String? = { Auth.auth().currentUser?.uid }
    ) {
        self.repository = repository ?? FirestoreSystemLogRepository()
        self.accessMode = accessMode
        self.calendar = calendar
        self.nowProvider = nowProvider
        self.reviewerUserIdProvider = reviewerUserIdProvider
    }

    var visibleLogs: [SystemLogEntry] {
        filteredLogs.sorted(by: defaultSort)
    }

    func loadIfNeeded() async {
        guard !hasLoadedInitialPage else { return }
        await refresh()
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            logs = try await fetchLogsForAccessMode()
            hasLoadedInitialPage = true
            errorMessage = nil
        } catch {
            errorMessage = readableErrorMessage(for: error)
        }
    }

    func ensureSelectedSectionIsVisible() {
        guard !accessMode.visibleSections.contains(selectedSection) else { return }
        selectedSection = .all
    }

    private func fetchLogsForAccessMode() async throws -> [SystemLogEntry] {
        switch accessMode {
        case .owner:
            try await repository.fetchLogs(filter: .empty, sortOption: .newestFirst, limit: fetchLimit)
        case .appAdmin:
            try await fetchAppAdminLogs()
        }
    }

    private func fetchAppAdminLogs() async throws -> [SystemLogEntry] {
        let safeActorRoles = Set(SystemLogActorRole.allCases.filter { $0 != .owner })
        let diagnostics = try await repository.fetchLogs(
            filter: SystemLogFilter(categories: [.diagnostics], actorRoles: safeActorRoles),
            sortOption: .newestFirst,
            limit: fetchLimit
        )

        let scopedCategories: [SystemLogCategory] = [.moderation, .organization, .userAccount]
        var scopedLogs: [SystemLogEntry] = diagnostics

        for category in scopedCategories {
            let categoryLogs = try await repository.fetchLogs(
                filter: SystemLogFilter(categories: [category], actorRoles: safeActorRoles),
                sortOption: .newestFirst,
                limit: fetchLimit
            )
            scopedLogs.append(contentsOf: categoryLogs)
        }

        return Array(Dictionary(grouping: scopedLogs, by: \.id).compactMap { $0.value.first })
            .sorted(by: defaultSort)
            .prefix(fetchLimit)
            .map { $0 }
    }

    private func readableErrorMessage(for error: Error) -> String {
        let nsError = error as NSError
        let details = [nsError.domain, nsError.localizedDescription].joined(separator: " ").lowercased()

        if details.contains("permission") || details.contains("denied") {
            switch accessMode {
            case .owner:
                return AppStrings.SystemLogs.ownerLoadPermissionError
            case .appAdmin:
                return AppStrings.SystemLogs.adminLoadPermissionError
            }
        }

        if details.contains("index") || details.contains("failed-precondition") {
            return AppStrings.SystemLogs.indexRequiredError
        }

        if details.contains("unavailable") || details.contains("network") {
            return AppStrings.SystemLogs.networkLoadError
        }

        return AppStrings.SystemLogs.genericLoadError
    }

    func markReviewed(logID: String) async {
        guard !reviewingLogIDs.contains(logID) else { return }
        guard let reviewerUserId = reviewerUserIdProvider()?.trimmingCharacters(in: .whitespacesAndNewlines), !reviewerUserId.isEmpty else {
            reviewErrorMessages[logID] = AppStrings.SystemLogs.missingReviewerError
            return
        }

        reviewingLogIDs.insert(logID)
        reviewErrorMessages[logID] = nil
        defer { reviewingLogIDs.remove(logID) }

        do {
            try await repository.markReviewed(logID: logID, reviewedByUserId: reviewerUserId)
            applyReviewedState(logID: logID, reviewedByUserId: reviewerUserId, reviewedAt: nowProvider())
        } catch {
            reviewErrorMessages[logID] = readableReviewErrorMessage(for: error)
        }
    }

    func reviewErrorMessage(for logID: String) -> String? {
        reviewErrorMessages[logID]
    }

    func log(id: String) -> SystemLogEntry? {
        logs.first { $0.id == id }
    }

    private func applyReviewedState(logID: String, reviewedByUserId: String, reviewedAt: Date) {
        guard let index = logs.firstIndex(where: { $0.id == logID }) else { return }
        logs[index] = logs[index].markedReviewed(at: reviewedAt, reviewedByUserId: reviewedByUserId)
    }

    private func readableReviewErrorMessage(for error: Error) -> String {
        let nsError = error as NSError
        let details = [nsError.domain, nsError.localizedDescription].joined(separator: " ").lowercased()

        if details.contains("permission") || details.contains("denied") {
            switch accessMode {
            case .owner:
                return AppStrings.SystemLogs.ownerReviewPermissionError
            case .appAdmin:
                return AppStrings.SystemLogs.adminReviewPermissionError
            }
        }

        if details.contains("unavailable") || details.contains("network") {
            return AppStrings.SystemLogs.networkReviewError
        }

        return AppStrings.SystemLogs.genericReviewError
    }

    func toggleFilter(_ filter: SystemLogQuickFilter) {
        if selectedFilters.contains(filter) {
            selectedFilters.remove(filter)
        } else {
            selectedFilters.insert(filter)
        }
    }

    func isSelected(_ filter: SystemLogQuickFilter) -> Bool {
        selectedFilters.contains(filter)
    }
}
