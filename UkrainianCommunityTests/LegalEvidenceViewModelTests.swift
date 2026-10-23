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

    func fetchEvidence(userID: String) async throws -> LegalEvidenceHistory {
        requestedUserIDs.append(userID)
        if let evidenceError { throw evidenceError }
        return LegalEvidenceHistory(
            account: LegalEvidenceAccount(userID: userID, displayName: "Philipp", email: "philipp@example.com", createdAt: nil),
            events: events,
            generatedAt: Date(timeIntervalSince1970: 30)
        )
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
            organizationName: nil,
            sourceRecordID: "receipt-1",
            acceptedFromPlatform: "ios",
            consentID: nil,
            purposeVersion: nil,
            disclosureVersion: nil,
            disclosureText: nil
        )
    }
}

extension LegalEvidenceViewModelTests {
    @Test func searchPagesRemainReachableAndDoNotRepeatAccounts() async {
        let first = sampleAccount(id: "search-1"), second = sampleAccount(id: "search-2")
        let cursor = LegalEvidenceAccountCursor(userID: first.id, createdAt: Date(), searchQuery: "philipp")
        let repository = LegalEvidenceRepositoryStub(pages: [
            LegalEvidenceAccountPage(accounts: [first], nextCursor: cursor, totalMatches: nil),
            LegalEvidenceAccountPage(accounts: [first, second], nextCursor: nil, totalMatches: nil),
        ])
        let model = LegalEvidenceViewModel(repository: repository)
        model.searchText = "philipp"
        await model.load()
        #expect(model.canLoadMore)
        await model.load(reset: false)
        #expect(model.accounts.map(\.id) == [first.id, second.id])
        #expect(repository.accountRequests.last?.query == "philipp")
        #expect(repository.accountRequests.last?.cursor == cursor)
    }

    @Test func historyLoadsFirstPageAndExportsWholeHistoryOnlyOnRequest() async throws {
        let account = sampleAccount(id: "selected-user")
        let events = (0..<121).map { index in
            LegalEvidenceEvent(id: "event-\(index)", userID: account.id, displayName: nil, email: nil,
                eventType: .termsAccepted, occurredAt: Date(timeIntervalSince1970: Double(index)), version: "2026.13",
                locale: "de", appVersion: "fixture", source: "legalDocument", contentHash: nil,
                organizationID: nil, organizationName: nil, sourceRecordID: nil, acceptedFromPlatform: "ios",
                consentID: nil, purposeVersion: nil, disclosureVersion: nil, disclosureText: nil)
        }
        let repository = LegalEvidenceRepositoryStub(events: events)
        let model = LegalEvidenceUserViewModel(account: account, repository: repository)
        await model.load()
        #expect(model.events.count == 50)
        #expect(model.canLoadMore)
        #expect(model.exportText == nil)
        await model.load(reset: false)
        #expect(model.events.count == 100)
        await model.prepareExport()
        let text = try #require(model.exportText)
        let object = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect((object["events"] as? [[String: Any]])?.count == 121)
        #expect(model.events.count == 100)
        model.clear()
        #expect(model.events.isEmpty)
        #expect(model.exportText == nil)
    }

    @Test func recordedVersionReaderRejectsAnotherVersionOrHash() async throws {
        let repository = MockLegalDocumentRepository()
        let document = try await repository.fetchAuthoritativeActiveDocument(type: .terms)
        let verified = try await repository.fetchPublishedVersion(type: .terms, version: document.version, expectedHash: document.contentHash)
        #expect(verified.version == document.version)
        await #expect(throws: (any Error).self) {
            _ = try await repository.fetchPublishedVersion(type: .terms, version: "1900.1", expectedHash: document.contentHash)
        }
        await #expect(throws: (any Error).self) {
            _ = try await repository.fetchPublishedVersion(type: .terms, version: document.version, expectedHash: "wrong-hash")
        }
    }
}
