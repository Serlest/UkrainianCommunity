import Combine
import FirebaseFunctions
import Foundation

@MainActor
final class LegalEvidenceViewModel: ObservableObject {
    @Published private(set) var accounts: [LegalEvidenceAccount] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var totalMatches: Int?
    @Published var searchText = ""

    private let repository: LegalEvidenceRepository
    private var nextCursor: LegalEvidenceAccountCursor?
    private var requestRevision: UInt = 0
    private var loadedQuery: String?

    init(repository: LegalEvidenceRepository) {
        self.repository = repository
    }

    var canLoadMore: Bool {
        nextCursor != nil
    }

    var normalizedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasSearchMinimumLength: Bool {
        normalizedSearch.isEmpty || normalizedSearch.count >= 2
    }

    func load(reset: Bool = true) async {
        if !reset && (!canLoadMore || isLoadingMore || isLoading) { return }
        guard hasSearchMinimumLength else {
            requestRevision &+= 1
            accounts = []
            nextCursor = nil
            totalMatches = nil
            errorMessage = nil
            hasLoaded = true
            isLoading = false; isLoadingMore = false
            return
        }

        if reset && loadedQuery != normalizedSearch { accounts = []; nextCursor = nil; hasLoaded = false }
        loadedQuery = normalizedSearch
        requestRevision &+= 1
        let revision = requestRevision
        if reset {
            isLoading = true; isLoadingMore = false
        } else {
            isLoadingMore = true
        }
        defer {
            if revision == requestRevision {
                isLoading = false
                isLoadingMore = false
            }
        }

        let query = normalizedSearch.isEmpty ? nil : normalizedSearch
        let cursor = reset ? nil : nextCursor
        do {
            let page = try await RefreshRequest.run { [self] in try await repository.fetchAccounts(
                query: query,
                limit: 50,
                cursor: cursor
            ) }
            guard revision == requestRevision, !Task.isCancelled else { return }
            if reset {
                accounts = page.accounts
            } else {
                let existingIDs = Set(accounts.map(\.id))
                accounts.append(contentsOf: page.accounts.filter { !existingIDs.contains($0.id) })
            }
            nextCursor = page.nextCursor
            totalMatches = page.totalMatches
            errorMessage = nil
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            guard revision == requestRevision else { return }
            errorMessage = legalEvidenceErrorMessage(for: error, userDetail: false)
            hasLoaded = true
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
    @Published private(set) var errorMessage: String?
    @Published private(set) var exportText: String?
    @Published var filter: LegalEvidenceFilter = .all
    @Published var searchText = ""
    private var requestRevision: UInt = 0
    private var nextCursor: String?
    private var seenCursors = Set<String>()
    private var loadedKey: String?
    private let repository: LegalEvidenceRepository

    init(account: LegalEvidenceAccount, repository: LegalEvidenceRepository) {
        self.account = account
        self.repository = repository
    }

    var canLoadMore: Bool { nextCursor != nil }
    var filteredEvents: [LegalEvidenceEvent] {
        guard loadedKey == requestKey else { return [] }
        return events.filter { filter.includes($0.eventType) }
    }
    var requestKey: String { filter.rawValue + "|" + searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    func load(reset: Bool = true) async {
        guard reset || (canLoadMore && !isLoadingMore && !isLoading) else { return }
        requestRevision &+= 1
        let revision = requestRevision
        if reset {
            if loadedKey != requestKey { events = []; nextCursor = nil; hasLoaded = false }
            loadedKey = requestKey
            isLoading = true; isLoadingMore = false; seenCursors = []
        } else { isLoadingMore = true }
        let cursor = reset ? nil : nextCursor
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedFilter = filter
        errorMessage = nil
        defer { if revision == requestRevision { isLoading = false; isLoadingMore = false } }
        do {
            let page = try await RefreshRequest.run { [self] in
                try await repository.fetchEvidencePage(userID: account.userID, cursor: cursor, filter: selectedFilter, query: query)
            }
            guard revision == requestRevision, !Task.isCancelled else { return }
            if let next = page.nextCursor, !seenCursors.insert(next).inserted { throw AppError.unknown }
            account = page.history.account
            if reset { events = page.history.events; summary = page.history.summary }
            else {
                let known = Set(events.map(\.id))
                events += page.history.events.filter { !known.contains($0.id) }
            }
            nextCursor = page.nextCursor
            hasLoaded = true
        } catch is CancellationError { return }
        catch {
            guard revision == requestRevision else { return }
            hasLoaded = true
            errorMessage = legalEvidenceErrorMessage(for: error, userDetail: true)
        }
    }

    func prepareExport() async {
        guard !isExporting else { return }
        let revision = requestRevision
        isExporting = true; exportText = nil
        defer { isExporting = false }
        do {
            let history = try await RefreshRequest.run(timeout: .seconds(120)) { [self] in
                try await repository.fetchEvidence(userID: account.userID)
            }
            guard revision == requestRevision, !Task.isCancelled else { return }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            exportText = String(data: try encoder.encode(LegalEvidenceExportEnvelope(history: history)), encoding: .utf8)
        } catch { if revision == requestRevision { errorMessage = legalEvidenceErrorMessage(for: error, userDetail: true) } }
    }

    func clear() {
        requestRevision &+= 1
        events = []; summary = []; exportText = nil; nextCursor = nil
        hasLoaded = false; isLoading = false; isLoadingMore = false
    }
}

private func legalEvidenceErrorMessage(for error: Error, userDetail: Bool) -> String {
    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain {
        return AppStrings.LegalEvidence.loadFailedNetwork
    }

    switch FunctionsErrorCode(rawValue: nsError.code) {
    case .unauthenticated:
        return AppStrings.LegalEvidence.loadFailedSession
    case .permissionDenied:
        return AppStrings.LegalEvidence.loadFailedPermission
    case .notFound where userDetail:
        return AppStrings.LegalEvidence.loadFailedNotFound
    case .unavailable, .deadlineExceeded, .resourceExhausted:
        return AppStrings.LegalEvidence.loadFailedService
    default:
        return AppStrings.LegalEvidence.loadFailed
    }
}
