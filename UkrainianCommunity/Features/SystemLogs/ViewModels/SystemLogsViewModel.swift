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
    @Published private(set) var refreshingDetailLogIDs = Set<String>()
    @Published private(set) var detailRefreshErrorMessages: [String: String] = [:]

    let repository: SystemLogRepositoryProtocol
    let accessMode: SystemLogsAccessMode
    let calendar: Calendar
    let nowProvider: () -> Date
    private let reviewerUserIdProvider: () -> String?
    private let fetchLimit = 100
    private var hasLoadedInitialPage = false
    private var dataRequestRevision: UInt = 0
    private var nextCursor: String?
    private var loadedQueryKey: String?
    private var lastLoadedAt: Date?
    private var reviewedOverrides: [String: (String, Date)] = [:]

    var queryKey: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? String(data: encoder.encode(queryFilter), encoding: .utf8))! + sortOption.rawValue
    }

    var queryFilter: SystemLogFilter {
        var filter = SystemLogFilter(section: selectedSection.rawValue, categories: selectedCategories,
            severities: selectedSeverities, outcomes: selectedOutcomes,
            isReviewed: reviewFilter == .all ? nil : reviewFilter == .reviewed,
            searchText: searchText.trimmingCharacters(in: .whitespacesAndNewlines),
            isAppAdminReadable: accessMode == .appAdmin ? true : nil)
        if selectedFilters.contains(.unreviewed) { filter.isReviewed = false }
        if selectedFilters.contains(.critical) {
            // Contradictory selections intentionally produce no matches.
            if !selectedSeverities.isEmpty && !selectedSeverities.contains(.critical) { filter.targetId = "__no_matching_journal_entry__" }
            filter.severities = [.critical]
        }
        var dates: [Date] = []
        let now = calendar.startOfDay(for: nowProvider())
        if selectedFilters.contains(.today) || datePreset == .today { dates.append(calendar.startOfDay(for: now)) }
        if selectedFilters.contains(.sevenDays) || datePreset == .sevenDays { dates.append(calendar.date(byAdding: .day, value: -7, to: now) ?? now) }
        if datePreset == .thirtyDays { dates.append(calendar.date(byAdding: .day, value: -30, to: now) ?? now) }
        filter.startDate = dates.max()
        if selectedFilters.contains(.today) { filter.endDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))?.addingTimeInterval(-0.001) }
        if selectedFilters.contains(.unreviewed) && reviewFilter == .reviewed { filter.targetId = "__no_matching_journal_entry__" }
        return filter
    }

    func refreshIfStale() async {
        guard !isLoading else { return }
        if loadedQueryKey != queryKey || lastLoadedAt.map({ nowProvider().timeIntervalSince($0) >= 60 || !calendar.isDate($0, inSameDayAs: nowProvider()) }) != false {
            await refresh()
        }
    }

    func queryChanged() async {
        guard loadedQueryKey != queryKey else { await loadIfNeeded(); return }
        if repository.usesServerFiltering {
            dataRequestRevision &+= 1
            logs = []; nextCursor = nil; canLoadMore = false
        }
        do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
        guard !Task.isCancelled, loadedQueryKey != queryKey else { return }
        await refresh()
    }


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
        guard !hasLoadedInitialPage else { await refreshIfStale(); return }
        await refresh()
    }

    func refresh() async {
        dataRequestRevision &+= 1
        let requestRevision = dataRequestRevision
        let key = queryKey
        let filter = repository.usesServerFiltering ? queryFilter : SystemLogFilter(isAppAdminReadable: accessMode == .appAdmin ? true : nil)
        let sort = sortOption
        isLoading = true
        defer {
            if requestRevision == dataRequestRevision {
                isLoading = false
            }
        }

        do {
            var page = try await repository.queryPage(filter: filter, sortOption: sort, limit: fetchLimit, cursor: nil)
            for _ in 0..<7 {
                guard page.entries.isEmpty, let cursor = page.cursor, !Task.isCancelled, requestRevision == dataRequestRevision else { break }
                page = try await repository.queryPage(filter: filter, sortOption: sort, limit: fetchLimit, cursor: cursor)
            }
            guard requestRevision == dataRequestRevision, key == queryKey, !Task.isCancelled else { return }
            logs = page.entries.map(applyingReviewOverride)
            nextCursor = page.cursor
            canLoadMore = page.cursor != nil
            loadedQueryKey = key
            lastLoadedAt = nowProvider()
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
        let key = queryKey
        let filter = queryFilter
        isLoadingNextPage = true
        defer { isLoadingNextPage = false }

        do {
            var page = try await repository.queryPage(filter: filter, sortOption: requestedSortOption, limit: fetchLimit, cursor: nextCursor)
            for _ in 0..<7 {
                guard page.entries.isEmpty, let cursor = page.cursor, !Task.isCancelled, requestRevision == dataRequestRevision else { break }
                page = try await repository.queryPage(filter: filter, sortOption: requestedSortOption, limit: fetchLimit, cursor: cursor)
            }
            guard key == queryKey else { return }
            let nextPage = page.entries.map(applyingReviewOverride)
            guard requestRevision == dataRequestRevision, requestedSortOption == sortOption else { return }
            let existingIDs = Set(logs.map(\.id))
            logs.append(contentsOf: nextPage.filter { !existingIDs.contains($0.id) })
            nextCursor = page.cursor
            canLoadMore = page.cursor != nil
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

    func refreshLogDetail(id: String) async {
        guard !refreshingDetailLogIDs.contains(id) else { return }
        refreshingDetailLogIDs.insert(id)
        detailRefreshErrorMessages[id] = nil
        defer { refreshingDetailLogIDs.remove(id) }

        do {
            guard let refreshedLog = try await repository.fetchLog(id: id) else {
                detailRefreshErrorMessages[id] = LocalizationStore.localizedString(
                    "system_logs.detail.not_found",
                    defaultValue: "Запис журналу більше не доступний."
                )
                return
            }
            if let index = logs.firstIndex(where: { $0.id == id }) {
                logs[index] = refreshedLog
            }
        } catch {
            detailRefreshErrorMessages[id] = readableErrorMessage(for: error)
        }
    }

    private func applyReviewedState(logID: String, reviewedByUserId: String, reviewedAt: Date) {
        reviewedOverrides[logID] = (reviewedByUserId, reviewedAt)
        guard let index = logs.firstIndex(where: { $0.id == logID }) else { return }
        logs[index] = logs[index].markedReviewed(at: reviewedAt, reviewedByUserId: reviewedByUserId)
    }

    private func applyingReviewOverride(_ entry: SystemLogEntry) -> SystemLogEntry {
        guard let (reviewer, date) = reviewedOverrides[entry.id], !entry.isReviewed else { return entry }
        return entry.markedReviewed(at: date, reviewedByUserId: reviewer)
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
        } catch let partialError as SystemLogBulkReviewPartialError {
            let reviewedAt = nowProvider()
            for logID in partialError.committedLogIDs {
                applyReviewedState(logID: logID, reviewedByUserId: reviewerUserId, reviewedAt: reviewedAt)
            }
            bulkReviewErrorMessage = LocalizationStore.localizedString(
                "system_logs.review.partial_failure",
                defaultValue: "Частину записів позначено як переглянуті. Не вдалося завершити всю операцію. Оновіть журнал і повторіть спробу."
            )
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
            dataRequestRevision &+= 1
            isLoading = false
            nextCursor = nil
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
