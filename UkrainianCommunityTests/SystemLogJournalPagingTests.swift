import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
private final class JournalPageStub: SystemLogRepositoryProtocol {
    var usesServerFiltering: Bool { true }
    var pages: [SystemLogPage] = []
    var continuations: [CheckedContinuation<SystemLogPage, Error>] = []
    var filters: [SystemLogFilter] = []
    var cursors: [String?] = []
    var suspends = false
    func queryPage(filter: SystemLogFilter, sortOption: SystemLogSortOption, limit: Int, cursor: String?) async throws -> SystemLogPage {
        filters.append(filter); cursors.append(cursor)
        if suspends { return try await withCheckedThrowingContinuation { continuations.append($0) } }
        return pages.removeFirst()
    }
    func fetchLogs(filter: SystemLogFilter, sortOption: SystemLogSortOption, limit: Int) async throws -> [SystemLogEntry] { [] }
    func fetchLog(id: String) async throws -> SystemLogEntry? { nil }
    func markReviewed(logID: String, reviewedByUserId: String) async throws {}
}

@MainActor
struct SystemLogJournalPagingTests {
    @Test func emptyServerPagesContinueWithoutHidingOlderMatches() async throws {
        let entry = try #require(MockSystemLogRepository.sampleEntries.first)
        let repository = JournalPageStub()
        repository.pages = [.init(entries: [], cursor: "older"), .init(entries: [entry], cursor: nil)]
        let model = SystemLogsViewModel(repository: repository, accessMode: .appAdmin)
        model.searchText = "older match"; model.selectedSection = .errors
        await model.refresh()
        #expect(model.logs == [entry]); #expect(!model.canLoadMore)
        #expect(repository.cursors.count == 2 && repository.cursors[1] == "older")
        #expect(repository.filters[0].searchText == "older match")
        #expect(repository.filters[0].section == "errors")
        #expect(repository.filters[0].isAppAdminReadable == true)
    }

    @Test func sparseSearchStopsAtBoundAndKeepsContinuationAvailable() async {
        let repository = JournalPageStub()
        repository.pages = (0..<8).map { .init(entries: [], cursor: "page-\($0)") }
        let model = SystemLogsViewModel(repository: repository)
        await model.refresh()
        #expect(model.logs.isEmpty && model.canLoadMore)
        #expect(repository.cursors.count == 8)
    }

    @Test func lateQueryCannotOverwriteNewResultsOrCursor() async throws {
        let entries = MockSystemLogRepository.sampleEntries
        let first = try #require(entries.first), second = try #require(entries.last)
        let repository = JournalPageStub(); repository.suspends = true
        let model = SystemLogsViewModel(repository: repository)
        let oldTask = Task { await model.refresh() }
        for _ in 0..<100 where repository.continuations.isEmpty { await Task.yield() }
        #expect(repository.continuations.count == 1)
        model.searchText = "new query"
        let newTask = Task { await model.refresh() }
        for _ in 0..<100 where repository.continuations.count < 2 { await Task.yield() }
        guard repository.continuations.count == 2 else { Issue.record("Both requests must be pending"); return }
        repository.continuations[1].resume(returning: .init(entries: [second], cursor: nil)); await newTask.value
        repository.continuations[0].resume(returning: .init(entries: [first], cursor: "old-cursor")); await oldTask.value
        #expect(model.logs == [second]); #expect(!model.canLoadMore)
    }

    @Test func periodQueryKeyStaysStableWithinDay() {
        let repository = JournalPageStub(); var time = Date()
        let model = SystemLogsViewModel(repository: repository, nowProvider: { time })
        model.datePreset = .sevenDays
        let key = model.queryKey
        time = time.addingTimeInterval(0.1)
        #expect(model.queryKey == key)
    }
}
