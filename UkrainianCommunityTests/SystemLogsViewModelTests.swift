import Foundation
import Testing
@testable import UkrainianCommunity

private final class SystemLogRepositoryStub: SystemLogRepositoryProtocol {
    enum StubError: Error { case network }

    var fetchResults: [Result<[SystemLogEntry], Error>]
    var nextPage: [SystemLogEntry]
    private(set) var receivedFilters: [SystemLogFilter] = []
    private(set) var nextPageCallCount = 0
    private(set) var reviewed: [(logID: String, reviewerID: String)] = []
    private(set) var clearAllCallCount = 0
    var clearAllResult: Result<Int, Error> = .success(0)

    init(
        fetchResults: [Result<[SystemLogEntry], Error>],
        nextPage: [SystemLogEntry] = []
    ) {
        self.fetchResults = fetchResults
        self.nextPage = nextPage
    }

    func fetchLogs(
        filter: SystemLogFilter,
        sortOption: SystemLogSortOption,
        limit: Int
    ) async throws -> [SystemLogEntry] {
        receivedFilters.append(filter)
        guard !fetchResults.isEmpty else { return [] }
        return try fetchResults.removeFirst().get()
    }

    func fetchNextPage() async throws -> [SystemLogEntry] {
        nextPageCallCount += 1
        return nextPage
    }
    func fetchLog(id: String) async throws -> SystemLogEntry? { nil }
    func markReviewed(logID: String, reviewedByUserId: String) async throws {
        reviewed.append((logID, reviewedByUserId))
    }
    func clearAllLogs() async throws -> Int {
        clearAllCallCount += 1
        return try clearAllResult.get()
    }
}

@MainActor
struct SystemLogsViewModelTests {
    @Test func refreshFailureKeepsPreviouslyLoadedLogsVisible() async throws {
        let entry = try #require(MockSystemLogRepository.sampleEntries.first)
        let repository = SystemLogRepositoryStub(fetchResults: [
            .success([entry]),
            .failure(NSError(domain: "network", code: -1))
        ])
        let viewModel = SystemLogsViewModel(repository: repository)

        await viewModel.refresh()
        await viewModel.refresh()

        #expect(viewModel.logs == [entry])
        #expect(viewModel.errorMessage == AppStrings.SystemLogs.networkLoadError)
    }

    @Test func clearingFiltersRestoresCompleteVisibleList() async throws {
        let entries = Array(MockSystemLogRepository.sampleEntries.prefix(2))
        let repository = SystemLogRepositoryStub(fetchResults: [.success(entries)])
        let viewModel = SystemLogsViewModel(repository: repository)

        await viewModel.refresh()
        viewModel.searchText = "definitely-not-present"
        viewModel.selectedSection = .errors
        viewModel.toggleFilter(.critical)
        #expect(viewModel.visibleLogs.isEmpty)

        viewModel.clearSearchAndFilters()

        #expect(viewModel.searchText.isEmpty)
        #expect(viewModel.selectedSection == .all)
        #expect(viewModel.selectedFilters.isEmpty)
        #expect(viewModel.visibleLogs == entries)
    }

    @Test func appAdminUsesVisibilityContractAndCanLoadNextPage() async throws {
        let sample = try #require(MockSystemLogRepository.sampleEntries.first)
        let firstPage = (0..<100).map { copied(sample, id: "page-\($0)") }
        let next = copied(sample, id: "next-page")
        let repository = SystemLogRepositoryStub(
            fetchResults: [.success(firstPage)],
            nextPage: [next]
        )
        let viewModel = SystemLogsViewModel(repository: repository, accessMode: .appAdmin)

        await viewModel.refresh()

        #expect(repository.receivedFilters.count == 1)
        #expect(repository.receivedFilters.first?.isAppAdminReadable == true)
        #expect(viewModel.canLoadMore)

        await viewModel.loadNextPage()

        #expect(repository.nextPageCallCount == 1)
        #expect(viewModel.logs.last?.id == next.id)
        #expect(!viewModel.canLoadMore)
    }

    @Test func markingReviewedPersistsThenUpdatesLocalState() async throws {
        let entry = try #require(MockSystemLogRepository.sampleEntries.first)
        let repository = SystemLogRepositoryStub(fetchResults: [.success([entry])])
        let reviewedAt = Date(timeIntervalSince1970: 42)
        let viewModel = SystemLogsViewModel(
            repository: repository,
            nowProvider: { reviewedAt },
            reviewerUserIdProvider: { "reviewer" }
        )

        await viewModel.refresh()
        await viewModel.markReviewed(logID: entry.id)

        #expect(repository.reviewed.first?.logID == entry.id)
        #expect(repository.reviewed.first?.reviewerID == "reviewer")
        #expect(viewModel.log(id: entry.id)?.isReviewed == true)
        #expect(viewModel.log(id: entry.id)?.reviewedAt == reviewedAt)
    }

    @Test func onlyOwnerCanClearAllLogs() async throws {
        let entry = try #require(MockSystemLogRepository.sampleEntries.first)
        let ownerRepository = SystemLogRepositoryStub(fetchResults: [.success([entry])])
        ownerRepository.clearAllResult = .success(1)
        let ownerViewModel = SystemLogsViewModel(repository: ownerRepository, accessMode: .owner)
        await ownerViewModel.refresh()

        await ownerViewModel.clearAllLogs()

        #expect(ownerRepository.clearAllCallCount == 1)
        #expect(ownerViewModel.logs.isEmpty)
        #expect(!ownerViewModel.canLoadMore)

        let adminRepository = SystemLogRepositoryStub(fetchResults: [.success([entry])])
        let adminViewModel = SystemLogsViewModel(repository: adminRepository, accessMode: .appAdmin)
        await adminViewModel.refresh()

        await adminViewModel.clearAllLogs()

        #expect(adminRepository.clearAllCallCount == 0)
        #expect(adminViewModel.logs == [entry])
    }

    private func copied(_ entry: SystemLogEntry, id: String) -> SystemLogEntry {
        SystemLogEntry(
            id: id,
            createdAt: entry.createdAt,
            category: entry.category,
            severity: entry.severity,
            eventType: entry.eventType,
            actorUserId: entry.actorUserId,
            actorDisplayName: entry.actorDisplayName,
            actorRole: entry.actorRole,
            targetType: entry.targetType,
            targetId: entry.targetId,
            targetTitle: entry.targetTitle,
            organizationId: entry.organizationId,
            organizationName: entry.organizationName,
            outcome: entry.outcome,
            summary: entry.summary,
            technicalMessage: entry.technicalMessage,
            errorCode: entry.errorCode,
            moduleName: entry.moduleName,
            screenName: entry.screenName,
            operationName: entry.operationName,
            appVersion: entry.appVersion,
            osVersion: entry.osVersion,
            deviceModel: entry.deviceModel,
            isReviewed: entry.isReviewed,
            reviewedAt: entry.reviewedAt,
            reviewedByUserId: entry.reviewedByUserId,
            metadata: entry.metadata,
            retentionPolicy: entry.retentionPolicy,
            correlationId: entry.correlationId
        )
    }
}
