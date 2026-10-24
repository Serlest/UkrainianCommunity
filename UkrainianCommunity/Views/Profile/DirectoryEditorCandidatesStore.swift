import Combine
import Foundation

/// Uses the paginated server search without unrelated organization hydration.
@MainActor
final class DirectoryEditorCandidatesStore: ObservableObject {
    @Published private(set) var users: [AppUser] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var canLoadMore = false
    @Published private(set) var loadFailed = false
    @Published private(set) var total = 0
    @Published private(set) var hasLoaded = false
    private var failedPage = false
    private var actorID: String?
    private var query = ""
    private var cursor: String?
    private var generation = UUID()
    private let page: (String, String, String?) async throws -> UserDirectoryPage

    init(page: @escaping (String, String, String?) async throws -> UserDirectoryPage = UserDirectoryAPI.candidates) { self.page = page }

    func reset() {
        generation = UUID(); actorID = nil; query = ""; cursor = nil
        users = []; total = 0; hasLoaded = false; failedPage = false; isLoading = false; isLoadingMore = false; canLoadMore = false; loadFailed = false
    }
    func invalidate(actorID: String, query: String) {
        reset(); self.actorID = actorID; self.query = query; isLoading = true
    }
    func load(actorID: String, query: String) async {
        if self.actorID != actorID || self.query != query { invalidate(actorID: actorID, query: query) }
        else { generation = UUID() }
        await fetch(more: false)
    }
    func loadMore() async {
        guard canLoadMore, !isLoading, !isLoadingMore else { return }
        await fetch(more: true)
    }
    func retry() async { await fetch(more: failedPage) }
    private func fetch(more: Bool) async {
        guard let actorID else { return }
        let requestGeneration = generation
        if more { isLoadingMore = true } else { isLoading = true }
        loadFailed = false
        defer { if generation == requestGeneration { isLoading = false; isLoadingMore = false } }
        do {
            let result = try await page(actorID, query, more ? cursor : nil)
            guard requestGeneration == generation, !Task.isCancelled else { return }
            let known = Set(more ? users.map(\.id) : [])
            users = (more ? users : []) + result.users.filter { !known.contains($0.id) }
            hasLoaded = true; failedPage = false
            total = result.total; cursor = result.cursor; canLoadMore = result.cursor != nil
        } catch {
            guard requestGeneration == generation, !Task.isCancelled else { return }
            loadFailed = true; failedPage = more
        }
    }
}
