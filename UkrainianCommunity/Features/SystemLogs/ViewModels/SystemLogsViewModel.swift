import Combine
import FirebaseAuth
import FirebaseFunctions
import FirebaseFirestore
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
    @Published private(set) var hasLoadedInitialPage = false
    @Published private(set) var unavailableLogIDs: Set<String> = []
    @Published private(set) var accessDenied = false
    @Published private(set) var cursorRequiresRefresh = false
    @Published private(set) var details: [String: SystemLogEntry] = [:]
    private let sessionKeyProvider: () -> String
    private var currentSessionKey: String
    private var sessionGeneration = UUID()
    private var detailRequests: [String: UUID] = [:]
    private var pageRequest = UUID()
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
        if selectedFilters.contains(.sevenDays) || datePreset == .sevenDays { dates.append(calendar.date(byAdding: .day, value: -6, to: now) ?? now) }
        if datePreset == .thirtyDays { dates.append(calendar.date(byAdding: .day, value: -29, to: now) ?? now) }
        filter.startDate = dates.max()
        if !dates.isEmpty { filter.endDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))?.addingTimeInterval(-0.001) }
        if selectedFilters.contains(.unreviewed) && reviewFilter == .reviewed { filter.targetId = "__no_matching_journal_entry__" }
        return filter
    }

    func refreshIfStale() async {
        synchronizeSession()
        guard !isLoading else { return }
        if loadedQueryKey != queryKey || lastLoadedAt.map({ nowProvider().timeIntervalSince($0) >= 60 || !calendar.isDate($0, inSameDayAs: nowProvider()) }) != false {
            await refresh()
        }
    }

    func queryChanged() async {
        synchronizeSession()
        guard loadedQueryKey != queryKey else { await loadIfNeeded(); return }
        if repository.usesServerFiltering {
            dataRequestRevision &+= 1
            logs = []; nextCursor = nil; canLoadMore = false
            loadedQueryKey = nil; lastLoadedAt = nil
        }
        let revision = dataRequestRevision
        isLoading = true; errorMessage = nil
        // The first request has no search keystrokes to debounce.
        if hasLoadedInitialPage {
            do { try await Task.sleep(for: .milliseconds(300)) }
            catch { if revision == dataRequestRevision { isLoading = false }; return }
        }
        guard !Task.isCancelled else { if revision == dataRequestRevision { isLoading = false }; return }
        await refresh()
    }

    static var liveSessionKey: String {
        let auth = AuthService.shared.authState
        return [auth.user?.id ?? "guest", String(describing: auth.sessionState),
            String(auth.authorizationRevision), String(describing: auth.user?.globalRole),
            String(describing: auth.user?.accountStatus)].joined(separator: "|")
    }

    var isSessionCurrent: Bool { currentSessionKey == sessionKeyProvider() }

    func synchronizeSession() {
        let key = sessionKeyProvider()
        guard key != currentSessionKey else { return }
        currentSessionKey = key; sessionGeneration = UUID()
        withdrawPrivateData(); hasLoadedInitialPage = false; accessDenied = false
        reviewingLogIDs = []; deletingLogIDs = []; refreshingDetailLogIDs = []
        isMarkingVisibleReviewed = false; isClearingLogs = false
        reviewErrorMessages = [:]; detailRefreshErrorMessages = [:]
        clearLogsErrorMessage = nil; bulkReviewErrorMessage = nil; errorMessage = nil
        unavailableLogIDs = []; detailRequests = [:]
        clearSearchAndFilters()
    }

    private func requestScope() -> UUID { synchronizeSession(); return sessionGeneration }
    private func isCurrent(_ scope: UUID) -> Bool {
        synchronizeSession()
        return scope == sessionGeneration && !Task.isCancelled
    }
    private func withdrawPrivateData() {
        sessionGeneration = UUID()
        detailRequests = [:]; refreshingDetailLogIDs = []
        reviewingLogIDs = []; deletingLogIDs = []
        isMarkingVisibleReviewed = false; isClearingLogs = false
        dataRequestRevision &+= 1; pageRequest = UUID()
        logs = []; details = [:]; reviewedOverrides = [:]; nextCursor = nil
        canLoadMore = false; cursorRequiresRefresh = false
        loadedQueryKey = nil; lastLoadedAt = nil; isLoading = false; isLoadingNextPage = false
    }
    private func withdrawIfDenied(_ error: Error) {
        if SystemLogFailureKind(error).isAccessFailure { withdrawPrivateData(); accessDenied = true }
    }
    private func forgetLog(_ id: String) {
        unavailableLogIDs.insert(id); logs.removeAll { $0.id == id }; details[id] = nil
        reviewedOverrides[id] = nil; detailRequests[id] = nil
    }


    init(
        repository: SystemLogRepositoryProtocol? = nil,
        accessMode: SystemLogsAccessMode = .owner,
        calendar: Calendar = .current,
        nowProvider: @escaping () -> Date = Date.init,
        reviewerUserIdProvider: @escaping () -> String? = { Auth.auth().currentUser?.uid },
        sessionKeyProvider: (() -> String)? = nil
    ) {
        let provider: () -> String = sessionKeyProvider ?? (repository == nil ? { Self.liveSessionKey } : { "fixture" })
        self.sessionKeyProvider = provider; self.currentSessionKey = provider()
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

    private func readPage(filter: SystemLogFilter, sort: SystemLogSortOption, cursor: String?, started: ContinuousClock.Instant) async throws -> SystemLogPage {
        let remaining = Duration.seconds(20) - (ContinuousClock.now - started)
        guard remaining > .zero else { throw AppError.network }
        return try await RefreshRequest.run(timeout: remaining) { [repository, fetchLimit] in
            try await repository.queryPage(filter: filter, sortOption: sort, limit: fetchLimit, cursor: cursor)
        }
    }

    func refresh() async {
        let scope = requestScope()
        dataRequestRevision &+= 1
        let requestRevision = dataRequestRevision
        let key = queryKey
        let filter = repository.usesServerFiltering ? queryFilter : SystemLogFilter(isAppAdminReadable: accessMode == .appAdmin ? true : nil)
        let sort = sortOption
        isLoading = true; cursorRequiresRefresh = false
        pageRequest = UUID(); isLoadingNextPage = false
        defer {
            if requestRevision == dataRequestRevision {
                isLoading = false
            }
        }

        do {
            let started = ContinuousClock.now
            var page = try await readPage(filter: filter, sort: sort, cursor: nil, started: started)
            for _ in 0..<7 {
                guard page.entries.isEmpty, let cursor = page.cursor, !Task.isCancelled, requestRevision == dataRequestRevision, isCurrent(scope) else { break }
                page = try await readPage(filter: filter, sort: sort, cursor: cursor, started: started)
            }
            guard isCurrent(scope), requestRevision == dataRequestRevision, key == queryKey else { return }
            logs = page.entries.filter { !unavailableLogIDs.contains($0.id) }.map(applyingReviewOverride)
            nextCursor = page.cursor
            canLoadMore = page.cursor != nil
            loadedQueryKey = key
            lastLoadedAt = nowProvider()
            hasLoadedInitialPage = true
            accessDenied = false; errorMessage = nil
        } catch {
            guard isCurrent(scope), requestRevision == dataRequestRevision else { return }
            withdrawIfDenied(error)
            errorMessage = readableErrorMessage(for: error)
        }
    }

    func loadNextPage() async {
        let scope = requestScope()
        guard !accessDenied else { return }
        if cursorRequiresRefresh { await refresh(); return }
        guard canLoadMore, !isLoading, !isLoadingNextPage else { return }
        let revision = dataRequestRevision, key = queryKey
        let token = UUID(); pageRequest = token
        let sort = sortOption, filter = queryFilter
        var cursor = nextCursor
        isLoadingNextPage = true
        defer { if pageRequest == token { isLoadingNextPage = false } }
        do {
            let started = ContinuousClock.now
            var page = try await readPage(filter: filter, sort: sort, cursor: cursor, started: started)
            for _ in 0..<7 {
                guard page.entries.isEmpty, let next = page.cursor, isCurrent(scope), revision == dataRequestRevision else { break }
                cursor = next
                page = try await readPage(filter: filter, sort: sort, cursor: cursor, started: started)
            }
            guard isCurrent(scope), revision == dataRequestRevision, key == queryKey else { return }
            let ids = Set(logs.map(\.id))
            logs.append(contentsOf: page.entries.filter { !ids.contains($0.id) && !unavailableLogIDs.contains($0.id) }.map(applyingReviewOverride))
            nextCursor = page.cursor; canLoadMore = page.cursor != nil; errorMessage = nil
        } catch {
            guard isCurrent(scope), revision == dataRequestRevision, key == queryKey else { return }
            withdrawIfDenied(error)
            if SystemLogFailureKind(error) == .expiredCursor { cursorRequiresRefresh = true }
            else if !accessDenied { nextCursor = cursor }
            errorMessage = readableErrorMessage(for: error)
        }
    }

    func ensureSelectedSectionIsVisible() {
        guard !accessMode.visibleSections.contains(selectedSection) else { return }
        selectedSection = .all
    }

    func readableErrorMessage(for error: Error) -> String {
        switch SystemLogFailureKind(error) {
        case .access:
            return accessMode == .owner ? AppStrings.SystemLogs.ownerLoadPermissionError : AppStrings.SystemLogs.adminLoadPermissionError
        case .session: return SystemLogJournalStrings.sessionRequired
        case .requirements: return SystemLogJournalStrings.requirements
        case .expiredCursor: return SystemLogJournalStrings.cursorExpired
        case .index: return AppStrings.SystemLogs.indexRequiredError
        case .network: return AppStrings.SystemLogs.networkLoadError
        case .other: return AppStrings.SystemLogs.genericLoadError
        }
    }

    func markReviewed(logID: String) async {
        let scope = requestScope()
        guard !accessDenied, !unavailableLogIDs.contains(logID) else { return }
        guard !reviewingLogIDs.contains(logID) else { return }
        guard let reviewerUserId = reviewerUserIdProvider()?.trimmingCharacters(in: .whitespacesAndNewlines), !reviewerUserId.isEmpty else {
            reviewErrorMessages[logID] = AppStrings.SystemLogs.missingReviewerError
            return
        }

        reviewingLogIDs.insert(logID)
        reviewErrorMessages[logID] = nil
        defer { if scope == sessionGeneration { reviewingLogIDs.remove(logID) } }

        do {
            try await repository.markReviewed(logID: logID, reviewedByUserId: reviewerUserId)
            guard isCurrent(scope), !unavailableLogIDs.contains(logID) else { return }
            applyReviewedState(logID: logID, reviewedByUserId: reviewerUserId, reviewedAt: nowProvider())
        } catch {
            guard isCurrent(scope) else { return }; withdrawIfDenied(error)
            reviewErrorMessages[logID] = readableReviewErrorMessage(for: error)
        }
    }

    func reviewErrorMessage(for logID: String) -> String? {
        reviewErrorMessages[logID]
    }

    func log(id: String) -> SystemLogEntry? {
        guard isSessionCurrent, !accessDenied, !unavailableLogIDs.contains(id) else { return nil }
        return details[id] ?? logs.first { $0.id == id }
    }

    func refreshLogDetail(id: String) async {
        let scope = requestScope()
        guard !refreshingDetailLogIDs.contains(id), !unavailableLogIDs.contains(id) else { return }
        let token = UUID(); detailRequests[id] = token
        refreshingDetailLogIDs.insert(id); detailRefreshErrorMessages[id] = nil
        defer { if detailRequests[id] == token { refreshingDetailLogIDs.remove(id) } }
        do {
            let refreshed = try await RefreshRequest.run { [repository] in try await repository.fetchLog(id: id) }
            guard isCurrent(scope), detailRequests[id] == token, !unavailableLogIDs.contains(id) else { return }
            guard let refreshed else {
                forgetLog(id); refreshingDetailLogIDs.remove(id)
                detailRefreshErrorMessages[id] = SystemLogJournalStrings.notFound
                return
            }
            accessDenied = false
            details[id] = refreshed
            if let index = logs.firstIndex(where: { $0.id == id }) { logs[index] = refreshed }
        } catch {
            guard isCurrent(scope), detailRequests[id] == token else { return }
            withdrawIfDenied(error)
            detailRefreshErrorMessages[id] = readableErrorMessage(for: error)
        }
    }

    private func applyReviewedState(logID: String, reviewedByUserId: String, reviewedAt: Date) {
        reviewedOverrides[logID] = (reviewedByUserId, reviewedAt)
        if let detail = details[logID] { details[logID] = detail.markedReviewed(at: reviewedAt, reviewedByUserId: reviewedByUserId) }
        guard let index = logs.firstIndex(where: { $0.id == logID }) else { return }
        logs[index] = logs[index].markedReviewed(at: reviewedAt, reviewedByUserId: reviewedByUserId)
    }

    private func applyingReviewOverride(_ entry: SystemLogEntry) -> SystemLogEntry {
        guard let (reviewer, date) = reviewedOverrides[entry.id], !entry.isReviewed else { return entry }
        return entry.markedReviewed(at: date, reviewedByUserId: reviewer)
    }

    private func readableReviewErrorMessage(for error: Error) -> String {
        if SystemLogFailureKind(error) == .session { return SystemLogJournalStrings.sessionRequired }
        if SystemLogFailureKind(error) == .requirements { return SystemLogJournalStrings.requirements }
        if SystemLogFailureKind(error).isAccessFailure {
            switch accessMode {
            case .owner:
                return AppStrings.SystemLogs.ownerReviewPermissionError
            case .appAdmin:
                return AppStrings.SystemLogs.adminReviewPermissionError
            }
        }

        if SystemLogFailureKind(error) == .network {
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
        let scope = requestScope()
        guard !accessDenied else { return }
        let candidates = unreviewedVisibleLogs
        guard !candidates.isEmpty, !isMarkingVisibleReviewed else { return }
        guard let reviewerUserId = reviewerUserIdProvider()?.trimmingCharacters(in: .whitespacesAndNewlines), !reviewerUserId.isEmpty else {
            bulkReviewErrorMessage = AppStrings.SystemLogs.missingReviewerError
            return
        }

        isMarkingVisibleReviewed = true
        bulkReviewErrorMessage = nil
        defer { if scope == sessionGeneration { isMarkingVisibleReviewed = false } }

        do {
            try await repository.markReviewed(
                logIDs: candidates.map(\.id),
                reviewedByUserId: reviewerUserId
            )
            guard isCurrent(scope) else { return }
            let reviewedAt = nowProvider()
            for log in candidates where !unavailableLogIDs.contains(log.id) {
                applyReviewedState(logID: log.id, reviewedByUserId: reviewerUserId, reviewedAt: reviewedAt)
            }
        } catch let partialError as SystemLogBulkReviewPartialError {
            guard isCurrent(scope) else { return }
            let reviewedAt = nowProvider()
            for logID in partialError.committedLogIDs {
                guard !unavailableLogIDs.contains(logID) else { continue }
                applyReviewedState(logID: logID, reviewedByUserId: reviewerUserId, reviewedAt: reviewedAt)
            }
            bulkReviewErrorMessage = LocalizationStore.localizedString(
                "system_logs.review.partial_failure",
                defaultValue: "Частину записів позначено як переглянуті. Не вдалося завершити всю операцію. Оновіть журнал і повторіть спробу."
            )
        } catch {
            guard isCurrent(scope) else { return }; withdrawIfDenied(error)
            bulkReviewErrorMessage = readableReviewErrorMessage(for: error)
        }
    }

    func clearAllLogs() async {
        let scope = requestScope()
        guard !accessDenied else { return }
        guard accessMode == .owner, !isClearingLogs else { return }
        isClearingLogs = true
        clearLogsErrorMessage = nil
        defer { if scope == sessionGeneration { isClearingLogs = false } }

        do {
            _ = try await repository.clearAllLogs()
            guard isCurrent(scope) else { return }
            logs.forEach { unavailableLogIDs.insert($0.id) }; details.keys.forEach { unavailableLogIDs.insert($0) }
            withdrawPrivateData()
            hasLoadedInitialPage = true
            dataRequestRevision &+= 1
            isLoading = false
            nextCursor = nil
            logs = []
            canLoadMore = false
            errorMessage = nil
            clearSearchAndFilters()
        } catch {
            guard isCurrent(scope) else { return }; withdrawIfDenied(error)
            clearLogsErrorMessage = readableClearLogsErrorMessage(for: error)
        }
    }

    func deleteLog(id: String) async {
        let scope = requestScope()
        guard !accessDenied else { return }
        guard accessMode == .owner, !deletingLogIDs.contains(id) else { return }
        deletingLogIDs.insert(id)
        clearLogsErrorMessage = nil
        defer { if scope == sessionGeneration { deletingLogIDs.remove(id) } }

        do {
            try await repository.deleteLog(id: id)
            guard isCurrent(scope) else { return }
            forgetLog(id)
            reviewErrorMessages[id] = nil
            errorMessage = nil
        } catch {
            guard isCurrent(scope) else { return }; withdrawIfDenied(error)
            clearLogsErrorMessage = readableClearLogsErrorMessage(for: error)
        }
    }

    private func readableClearLogsErrorMessage(for error: Error) -> String {
        if SystemLogFailureKind(error) == .session { return SystemLogJournalStrings.sessionRequired }
        if SystemLogFailureKind(error) == .requirements { return SystemLogJournalStrings.requirements }
        if SystemLogFailureKind(error).isAccessFailure {
            return AppStrings.SystemLogs.clearPermissionError
        }
        if SystemLogFailureKind(error) == .network {
            return AppStrings.SystemLogs.clearNetworkError
        }
        return AppStrings.SystemLogs.clearGenericError
    }
}
