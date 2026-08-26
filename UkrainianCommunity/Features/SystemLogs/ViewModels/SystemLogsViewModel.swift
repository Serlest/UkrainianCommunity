import Combine
import FirebaseAuth
import Foundation

@MainActor
final class SystemLogsViewModel: ObservableObject {
    @Published private(set) var logs: [SystemLogEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingNextPage = false
    @Published private(set) var canLoadMore = false
    @Published private(set) var errorMessage: String?
    @Published var searchText = ""
    @Published var selectedSection: SystemLogDashboardSection = .all
    @Published var sortOption: SystemLogSortOption = .newestFirst
    @Published private(set) var selectedFilters: Set<SystemLogQuickFilter> = []
    @Published var selectedCategories: Set<SystemLogCategory> = []
    @Published var selectedSeverities: Set<SystemLogSeverity> = []
    @Published var selectedOutcomes: Set<SystemLogOutcome> = []
    @Published var reviewFilter: SystemLogReviewFilter = .all
    @Published var datePreset: SystemLogDatePreset = .all
    @Published private(set) var reviewingLogIDs: Set<String> = []
    @Published private(set) var isMarkingVisibleReviewed = false
    @Published private(set) var bulkReviewErrorMessage: String?
    @Published private(set) var reviewErrorMessages: [String: String] = [:]
    @Published private(set) var isClearingLogs = false
    @Published private(set) var deletingLogIDs = Set<String>()
    @Published private(set) var clearLogsErrorMessage: String?

    private let repository: SystemLogRepositoryProtocol
    let accessMode: SystemLogsAccessMode
    let calendar: Calendar
    let nowProvider: () -> Date
    private let reviewerUserIdProvider: () -> String?
    private let fetchLimit = 100
    private var hasLoadedInitialPage = false
    private var dataRequestRevision: UInt = 0

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
        filteredLogs
    }

    var hasActiveFilters: Bool {
        selectedSection != .all
            || !selectedFilters.isEmpty
            || !selectedCategories.isEmpty
            || !selectedSeverities.isEmpty
            || !selectedOutcomes.isEmpty
            || reviewFilter != .all
            || datePreset != .all
            || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var advancedFilterCount: Int {
        selectedCategories.count
            + selectedSeverities.count
            + selectedOutcomes.count
            + (reviewFilter == .all ? 0 : 1)
            + (datePreset == .all ? 0 : 1)
    }

    var unreviewedVisibleLogs: [SystemLogEntry] {
        visibleLogs.filter { !$0.isReviewed }
    }

    func loadIfNeeded() async {
        guard !hasLoadedInitialPage else { return }
        await refresh()
    }

    func refresh() async {
        dataRequestRevision &+= 1
        let requestRevision = dataRequestRevision
        isLoading = true
        defer {
            if requestRevision == dataRequestRevision {
                isLoading = false
            }
        }

        do {
            let refreshedLogs = try await fetchLogsForAccessMode()
            guard requestRevision == dataRequestRevision else { return }
            logs = refreshedLogs
            canLoadMore = logs.count >= fetchLimit
            hasLoadedInitialPage = true
            errorMessage = nil
        } catch {
            guard requestRevision == dataRequestRevision else { return }
            errorMessage = readableErrorMessage(for: error)
        }
    }

    func loadNextPage() async {
        guard canLoadMore, !isLoading, !isLoadingNextPage else { return }
        let requestRevision = dataRequestRevision
        let requestedSortOption = sortOption
        isLoadingNextPage = true
        defer { isLoadingNextPage = false }

        do {
            let nextPage = try await repository.fetchNextPage()
            guard requestRevision == dataRequestRevision, requestedSortOption == sortOption else { return }
            let existingIDs = Set(logs.map(\.id))
            logs.append(contentsOf: nextPage.filter { !existingIDs.contains($0.id) })
            canLoadMore = nextPage.count >= fetchLimit
            errorMessage = nil
        } catch {
            guard requestRevision == dataRequestRevision, requestedSortOption == sortOption else { return }
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
            try await repository.fetchLogs(filter: .empty, sortOption: sortOption, limit: fetchLimit)
        case .appAdmin:
            try await repository.fetchLogs(
                filter: SystemLogFilter(isAppAdminReadable: true),
                sortOption: sortOption,
                limit: fetchLimit
            )
        }
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

    func clearSearchAndFilters() {
        searchText = ""
        selectedFilters = []
        selectedSection = .all
        clearAdvancedFilters()
    }

    func clearQuickFilters() {
        selectedFilters = []
    }

    func clearAdvancedFilters() {
        selectedCategories = []
        selectedSeverities = []
        selectedOutcomes = []
        reviewFilter = .all
        datePreset = .all
    }

    func applyMetric(id: String) {
        clearSearchAndFilters()
        switch id {
        case "unreviewed":
            reviewFilter = .unreviewed
        case "critical":
            selectedSeverities = [.critical]
        case "errors":
            selectedSection = .errors
        case "security":
            selectedSection = .security
        case "moderation":
            selectedSection = .moderation
        default:
            break
        }
    }

    func markVisibleReviewed() async {
        let candidates = unreviewedVisibleLogs
        guard !candidates.isEmpty, !isMarkingVisibleReviewed else { return }
        guard let reviewerUserId = reviewerUserIdProvider()?.trimmingCharacters(in: .whitespacesAndNewlines), !reviewerUserId.isEmpty else {
            bulkReviewErrorMessage = AppStrings.SystemLogs.missingReviewerError
            return
        }

        isMarkingVisibleReviewed = true
        bulkReviewErrorMessage = nil
        defer { isMarkingVisibleReviewed = false }

        do {
            try await repository.markReviewed(
                logIDs: candidates.map(\.id),
                reviewedByUserId: reviewerUserId
            )
            let reviewedAt = nowProvider()
            for log in candidates {
                applyReviewedState(logID: log.id, reviewedByUserId: reviewerUserId, reviewedAt: reviewedAt)
            }
        } catch {
            bulkReviewErrorMessage = readableReviewErrorMessage(for: error)
        }
    }

    func clearAllLogs() async {
        guard accessMode == .owner, !isClearingLogs else { return }
        isClearingLogs = true
        clearLogsErrorMessage = nil
        defer { isClearingLogs = false }

        do {
            _ = try await repository.clearAllLogs()
            logs = []
            canLoadMore = false
            errorMessage = nil
            clearSearchAndFilters()
        } catch {
            clearLogsErrorMessage = readableClearLogsErrorMessage(for: error)
        }
    }

    func deleteLog(id: String) async {
        guard accessMode == .owner, !deletingLogIDs.contains(id) else { return }
        deletingLogIDs.insert(id)
        clearLogsErrorMessage = nil
        defer { deletingLogIDs.remove(id) }

        do {
            try await repository.deleteLog(id: id)
            logs.removeAll { $0.id == id }
            reviewErrorMessages[id] = nil
            errorMessage = nil
        } catch {
            clearLogsErrorMessage = readableClearLogsErrorMessage(for: error)
        }
    }

    private func readableClearLogsErrorMessage(for error: Error) -> String {
        let nsError = error as NSError
        let details = [nsError.domain, nsError.localizedDescription].joined(separator: " ").lowercased()
        if details.contains("permission") || details.contains("denied") {
            return AppStrings.SystemLogs.clearPermissionError
        }
        if details.contains("unavailable") || details.contains("network") {
            return AppStrings.SystemLogs.clearNetworkError
        }
        return AppStrings.SystemLogs.clearGenericError
    }
}
