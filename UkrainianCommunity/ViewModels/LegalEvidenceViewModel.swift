import Combine
import Foundation

@MainActor
final class LegalEvidenceViewModel: ObservableObject {
    @Published private(set) var accounts: [LegalEvidenceAccount] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var totalMatches: Int?
    @Published private(set) var accessDenied = false
    @Published var searchText = "" {
        didSet {
            if oldValue.trimmingCharacters(in: .whitespacesAndNewlines) != normalizedSearch { clearQuery() }
        }
    }
    var accessScope: () -> LegalAccessScope? = { nil }
    private let repository: LegalEvidenceRepository
    private var nextCursor: LegalEvidenceAccountCursor?
    private var requestRevision: UInt = 0
    private var failedReset = true

    init(repository: LegalEvidenceRepository) { self.repository = repository }
    var canLoadMore: Bool { nextCursor != nil && !accessDenied }
    var normalizedSearch: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    var hasSearchMinimumLength: Bool { normalizedSearch.isEmpty || normalizedSearch.count >= 2 }

    func clear() {
        clearQuery()
        accessDenied = false
        searchText = ""
    }
    private func clearQuery() {
        requestRevision &+= 1
        accounts = []; nextCursor = nil; totalMatches = nil; errorMessage = nil
        hasLoaded = false; isLoading = false; isLoadingMore = false
    }
    private func deny(_ error: Error) {
        clearQuery(); accessDenied = true; hasLoaded = true
        errorMessage = legalEvidenceErrorMessage(for: error, userDetail: false)
    }
    func retry() async { await load(reset: failedReset) }

    func load(reset: Bool = true) async {
        let scope = accessScope()
        guard scope?.allowsOwner != false else { deny(AppError.permissionDenied); return }
        if !reset && (!canLoadMore || isLoadingMore || isLoading) { return }
        guard hasSearchMinimumLength else { clearQuery(); hasLoaded = true; return }
        requestRevision &+= 1
        let revision = requestRevision
        let capturedQuery = normalizedSearch
        accessDenied = false; errorMessage = nil
        if reset { isLoading = true; isLoadingMore = false }
        else { isLoadingMore = true }
        defer {
            if revision == requestRevision { isLoading = false; isLoadingMore = false }
        }
        let query = capturedQuery.isEmpty ? nil : capturedQuery
        let cursor = reset ? nil : nextCursor
        do {
            let page = try await RefreshRequest.run { [repository] in
                try await repository.fetchAccounts(query: query, limit: 50, cursor: cursor)
            }
            guard revision == requestRevision, capturedQuery == normalizedSearch, !Task.isCancelled else { return }
            guard scope == accessScope() else { clear(); return }
            if reset { accounts = page.accounts }
            else {
                let ids = Set(accounts.map(\.id))
                accounts += page.accounts.filter { !ids.contains($0.id) }
            }
            nextCursor = page.nextCursor; totalMatches = page.totalMatches; hasLoaded = true
        } catch is CancellationError { return }
        catch {
            guard revision == requestRevision, capturedQuery == normalizedSearch else { return }
            guard scope == accessScope() else { clear(); return }
            if LegalReadFailure(error).withdrawsPrivateData { deny(error); return }
            failedReset = reset; errorMessage = legalEvidenceErrorMessage(for: error, userDetail: false); hasLoaded = true
        }
    }
}

@MainActor
final class LegalEvidenceUserViewModel: ObservableObject {
    @Published private(set) var account: LegalEvidenceAccount
    @Published private(set) var events: [LegalEvidenceEvent] = []
    @Published private(set) var summary: [LegalEvidenceStatus] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var isExporting = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var accessDenied = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var exportText: String?
    @Published var filter: LegalEvidenceFilter = .all { didSet { if oldValue != filter { invalidateQuery() } } }
    @Published var searchText = "" {
        didSet { if oldValue.trimmingCharacters(in: .whitespacesAndNewlines) != searchText.trimmingCharacters(in: .whitespacesAndNewlines) { invalidateQuery() } }
    }
    var accessScope: () -> LegalAccessScope? = { nil }
    private let subjectID: String
    private var requestRevision: UInt = 0
    private var exportRevision: UInt = 0
    private var nextCursor: String?
    private var seenCursors = Set<String>()
    private var loadedKey: String?
    private var failedReset = true
    private let repository: LegalEvidenceRepository

    init(account: LegalEvidenceAccount, repository: LegalEvidenceRepository) {
        self.account = account; subjectID = account.userID; self.repository = repository
    }
    var canLoadMore: Bool { nextCursor != nil && !accessDenied }
    var filteredEvents: [LegalEvidenceEvent] { loadedKey == requestKey ? events.filter { filter.includes($0.eventType) } : [] }
    var requestKey: String { filter.rawValue + "|" + searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private func invalidateQuery() {
        requestRevision &+= 1
        events = []; nextCursor = nil; seenCursors = []; loadedKey = nil
        hasLoaded = false; errorMessage = nil; isLoading = false; isLoadingMore = false
    }
    func clear() {
        invalidateQuery(); exportRevision &+= 1
        summary = []; exportText = nil; isExporting = false; accessDenied = false
        account = LegalEvidenceAccount(userID: subjectID, displayName: nil, email: nil, createdAt: nil)
    }
    private func deny(_ error: Error) {
        clear(); accessDenied = true; hasLoaded = true
        errorMessage = legalEvidenceErrorMessage(for: error, userDetail: true)
    }
    func retry() async { await load(reset: failedReset) }

    func load(reset: Bool = true) async {
        let scope = accessScope()
        guard scope?.allowsOwner != false else { deny(AppError.permissionDenied); return }
        guard reset || (canLoadMore && !isLoadingMore && !isLoading) else { return }
        requestRevision &+= 1
        let revision = requestRevision, key = requestKey
        accessDenied = false
        if reset { loadedKey = key; isLoading = true; isLoadingMore = false; seenCursors = [] }
        else { isLoadingMore = true }
        let cursor = reset ? nil : nextCursor
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines), selectedFilter = filter
        errorMessage = nil
        defer { if revision == requestRevision { isLoading = false; isLoadingMore = false } }
        do {
            let page = try await RefreshRequest.run { [repository, subjectID] in
                try await repository.fetchEvidencePage(userID: subjectID, cursor: cursor, filter: selectedFilter, query: query)
            }
            guard revision == requestRevision, key == requestKey, !Task.isCancelled else { return }
            guard scope == accessScope() else { clear(); return }
            guard page.history.account.userID == subjectID, page.history.events.allSatisfy({ $0.userID == subjectID }) else { throw AppError.validationFailed }
            if let next = page.nextCursor, !seenCursors.insert(next).inserted { throw AppError.unknown }
            account = page.history.account
            if reset { events = page.history.events; summary = page.history.summary }
            else { let known = Set(events.map(\.id)); events += page.history.events.filter { !known.contains($0.id) } }
            nextCursor = page.nextCursor; hasLoaded = true
        } catch is CancellationError { return }
        catch {
            guard revision == requestRevision, key == requestKey else { return }
            guard scope == accessScope() else { clear(); return }
            if LegalReadFailure(error).withdrawsPrivateData { deny(error); return }
            failedReset = reset; hasLoaded = true; errorMessage = legalEvidenceErrorMessage(for: error, userDetail: true)
        }
    }

    func prepareExport() async {
        let scope = accessScope()
        guard scope?.allowsOwner != false, !accessDenied else { deny(AppError.permissionDenied); return }
        guard !isExporting else { return }
        exportRevision &+= 1
        let revision = exportRevision
        isExporting = true; exportText = nil
        defer { if revision == exportRevision { isExporting = false } }
        do {
            let history = try await RefreshRequest.run(timeout: .seconds(120)) { [repository, subjectID] in
                try await repository.fetchEvidence(userID: subjectID)
            }
            guard revision == exportRevision, !Task.isCancelled else { return }
            guard scope == accessScope() else { clear(); return }
            guard history.account.userID == subjectID, history.events.allSatisfy({ $0.userID == subjectID }) else { throw AppError.validationFailed }
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            exportText = String(data: try encoder.encode(LegalEvidenceExportEnvelope(history: history)), encoding: .utf8)
        } catch {
            guard revision == exportRevision else { return }
            guard scope == accessScope() else { clear(); return }
            if LegalReadFailure(error).withdrawsPrivateData { deny(error) }
            else { errorMessage = legalEvidenceErrorMessage(for: error, userDetail: true) }
        }
    }
}

func legalEvidenceErrorMessage(for error: Error, userDetail: Bool) -> String {
    switch LegalReadFailure(error) {
    case .network: AppStrings.LegalEvidence.loadFailedNetwork
    case .session: AppStrings.LegalEvidence.loadFailedSession
    case .denied: AppStrings.LegalEvidence.loadFailedPermission
    case .missing where userDetail: AppStrings.LegalEvidence.loadFailedNotFound
    default: AppStrings.LegalEvidence.loadFailed
    }
}
