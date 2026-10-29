import Testing
@testable import UkrainianCommunity

@MainActor struct EventLocationLoadingTests {
    @Test func stalledAddressLookupEndsBeforeDebounceAndCanRetry() async throws {
        let model = EventLocationSearchViewModel(deadline: { _ in try await Task.sleep(for: .milliseconds(30)) })
        model.updateQuery("Innsbruck")
        #expect(model.isSearching)
        try await Task.sleep(for: .milliseconds(100))
        #expect(!model.isSearching && model.searchFailed && model.completions.isEmpty)
        model.updateQuery("Wien")
        #expect(model.isSearching && !model.searchFailed)
        model.clear()
    }
    @Test func clearingSearchRejectsAnExpiredDeadline() async throws {
        let model = EventLocationSearchViewModel(deadline: { _ in try await Task.sleep(for: .milliseconds(30)) })
        model.updateQuery("Innsbruck"); model.clear()
        try await Task.sleep(for: .milliseconds(100))
        #expect(!model.isSearching && !model.searchFailed && model.completions.isEmpty)
    }
}
