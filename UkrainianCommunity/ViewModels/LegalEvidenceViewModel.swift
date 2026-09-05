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

    init(repository: LegalEvidenceRepository) {
        self.repository = repository
    }

    var canLoadMore: Bool {
        normalizedSearch.isEmpty && nextCursor != nil
    }

    var normalizedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasSearchMinimumLength: Bool {
        normalizedSearch.isEmpty || normalizedSearch.count >= 2
    }

    func load(reset: Bool = true) async {
        guard hasSearchMinimumLength else {
            requestRevision &+= 1
            accounts = []
            nextCursor = nil
            totalMatches = nil
            errorMessage = nil
            hasLoaded = true
            return
        }

        requestRevision &+= 1
        let revision = requestRevision
        if reset {
            isLoading = true
        } else {
            guard canLoadMore, !isLoadingMore else { return }
            isLoadingMore = true
        }
        defer {
            if revision == requestRevision {
                isLoading = false
                isLoadingMore = false
            }
        }

        do {
            let page = try await RefreshRequest.run { [self] in try await repository.fetchAccounts(
                query: normalizedSearch.isEmpty ? nil : normalizedSearch,
                limit: 50,
                cursor: reset ? nil : nextCursor
            ) }
            guard revision == requestRevision else { return }
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
    @Published private(set) var events: [LegalEvidenceEvent] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var errorMessage: String?
    @Published var filter: LegalEvidenceFilter = .all

    private var requestRevision: UInt = 0
    private let repository: LegalEvidenceRepository
    let account: LegalEvidenceAccount

    init(account: LegalEvidenceAccount, repository: LegalEvidenceRepository) {
        self.account = account
        self.repository = repository
    }

    var exportText: String? {
        guard hasLoaded, !isLoading, errorMessage == nil else { return nil }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(events)).flatMap { String(data: $0, encoding: .utf8) }
    }

    var filteredEvents: [LegalEvidenceEvent] {
        events.filter { filter.includes($0.eventType) }
    }

    func load() async {
        requestRevision &+= 1
        let revision = requestRevision
        isLoading = true
        errorMessage = nil
        defer {
            if revision == requestRevision { isLoading = false }
        }
        do {
            let loaded = try await RefreshRequest.run(timeout: .seconds(120)) { [self] in try await repository.fetchEvidence(userID: account.userID) }
            guard revision == requestRevision else { return }
            events = loaded
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            guard revision == requestRevision else { return }
            hasLoaded = true
            errorMessage = legalEvidenceErrorMessage(for: error, userDetail: true)
        }
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
