import Foundation
import FirebaseFunctions
import Testing
@testable import UkrainianCommunity

private final class LegalEvidenceRepositoryStub: LegalEvidenceRepository {
    var pages: [LegalEvidenceAccountPage]
    var events: [LegalEvidenceEvent]
    var accountError: Error?
    var evidenceError: Error?
    private(set) var accountRequests: [(query: String?, cursor: LegalEvidenceAccountCursor?)] = []
    private(set) var requestedUserIDs: [String] = []

    init(pages: [LegalEvidenceAccountPage] = [], events: [LegalEvidenceEvent] = []) {
        self.pages = pages
        self.events = events
    }

    func fetchAccounts(
        query: String?,
        limit: Int,
        cursor: LegalEvidenceAccountCursor?
    ) async throws -> LegalEvidenceAccountPage {
        accountRequests.append((query, cursor))
        if let accountError { throw accountError }
        return pages.isEmpty ? LegalEvidenceAccountPage(accounts: [], nextCursor: nil, totalMatches: nil) : pages.removeFirst()
    }

    func fetchEvidence(userID: String) async throws -> [LegalEvidenceEvent] {
        requestedUserIDs.append(userID)
        if let evidenceError { throw evidenceError }
        return events
    }
}

@MainActor
struct LegalEvidenceViewModelTests {
    @Test func accountSearchRequiresTwoCharactersAndUsesServerSearch() async {
        let account = sampleAccount(id: "user-1")
        let repository = LegalEvidenceRepositoryStub(pages: [
            LegalEvidenceAccountPage(accounts: [account], nextCursor: nil, totalMatches: 1)
        ])
        let viewModel = LegalEvidenceViewModel(repository: repository)

        viewModel.searchText = "p"
        await viewModel.load()
        #expect(repository.accountRequests.isEmpty)
        #expect(!viewModel.hasSearchMinimumLength)

        viewModel.searchText = " philipp "
        await viewModel.load()
        #expect(repository.accountRequests.first?.query == "philipp")
        #expect(viewModel.accounts == [account])
        #expect(viewModel.totalMatches == 1)
    }

    @Test func accountBrowsingAppendsTheNextStablePage() async throws {
        let cursor = LegalEvidenceAccountCursor(
            userID: "user-1",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let first = sampleAccount(id: "user-1")
        let second = sampleAccount(id: "user-2")
        let repository = LegalEvidenceRepositoryStub(pages: [
            LegalEvidenceAccountPage(accounts: [first], nextCursor: cursor, totalMatches: nil),
            LegalEvidenceAccountPage(accounts: [second], nextCursor: nil, totalMatches: nil),
        ])
        let viewModel = LegalEvidenceViewModel(repository: repository)

        await viewModel.load()
        #expect(viewModel.canLoadMore)
        await viewModel.load(reset: false)

        #expect(viewModel.accounts == [first, second])
        #expect(repository.accountRequests.count == 2)
        #expect(repository.accountRequests.last?.cursor == cursor)
        #expect(!viewModel.canLoadMore)
    }

    @Test func userDetailLoadsOnlyTheSelectedAccountsHistory() async {
        let account = sampleAccount(id: "selected-user")
        let event = sampleEvent(userID: account.userID)
        let repository = LegalEvidenceRepositoryStub(events: [event])
        let viewModel = LegalEvidenceUserViewModel(account: account, repository: repository)

        await viewModel.load()

        #expect(repository.requestedUserIDs == ["selected-user"])
        #expect(viewModel.events == [event])
    }

    @Test func listReportsOwnerPermissionFailuresPrecisely() async {
        let repository = LegalEvidenceRepositoryStub()
        repository.accountError = NSError(
            domain: "FirebaseFunctions",
            code: FunctionsErrorCode.permissionDenied.rawValue
        )
        let viewModel = LegalEvidenceViewModel(repository: repository)

        await viewModel.load()

        #expect(viewModel.errorMessage == AppStrings.LegalEvidence.loadFailedPermission)
    }

    @Test func detailReportsMissingAccountsPrecisely() async {
        let account = sampleAccount(id: "removed-user")
        let repository = LegalEvidenceRepositoryStub()
        repository.evidenceError = NSError(
            domain: "FirebaseFunctions",
            code: FunctionsErrorCode.notFound.rawValue
        )
        let viewModel = LegalEvidenceUserViewModel(account: account, repository: repository)

        await viewModel.load()

        #expect(viewModel.errorMessage == AppStrings.LegalEvidence.loadFailedNotFound)
    }

    private func sampleAccount(id: String) -> LegalEvidenceAccount {
        LegalEvidenceAccount(
            userID: id,
            displayName: "Philipp",
            email: "philipp@example.com",
            createdAt: Date(timeIntervalSince1970: 10)
        )
    }

    private func sampleEvent(userID: String) -> LegalEvidenceEvent {
        LegalEvidenceEvent(
            id: "event-1",
            userID: userID,
            displayName: "Philipp",
            email: "philipp@example.com",
            eventType: .termsAccepted,
            occurredAt: Date(timeIntervalSince1970: 20),
            version: "1.0",
            locale: "de",
            appVersion: "1.0",
            source: "legalDocument",
            contentHash: "hash",
            organizationID: nil,
            organizationName: nil
        )
    }
}
