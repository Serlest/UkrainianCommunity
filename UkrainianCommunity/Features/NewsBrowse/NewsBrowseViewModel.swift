import Combine
import Foundation

@MainActor
final class NewsBrowseViewModel: ObservableObject {
    @Published private(set) var posts: [NewsPost] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var hasMore = false
    private let loadPage: (NewsBrowseQuery, Int, NewsPageCursor?) async throws -> NewsPage
    private var cursor: NewsPageCursor?
    private var query: NewsBrowseQuery?
    private var generation = 0
    private var replacePending = false

    init(repository: NewsRepository) {
        loadPage = { try await repository.fetchNewsBrowsePage(query: $0, limit: $1, after: $2) }
    }
    init(loadPage: @escaping (NewsBrowseQuery, Int, NewsPageCursor?) async throws -> NewsPage) {
        self.loadPage = loadPage
    }
    func clear() {
        generation += 1
        posts = []; cursor = nil; query = nil; hasMore = false; loading = false; error = nil
    }
    func reload(_ query: NewsBrowseQuery, visibility: ContentVisibilityPolicy) async {
        let preserve = self.query.map {
            $0.filter == query.filter && $0.region == query.region
                && $0.search == query.search && $0.accountKey == query.accountKey
        } ?? false
        if preserve {
            generation += 1; cursor = nil; hasMore = false; loading = false; error = nil
        } else { clear() }
        self.query = query
        replacePending = true
        await loadMore(visibility: visibility)
    }
    func loadMore(visibility: ContentVisibilityPolicy) async {
        guard !loading, let query else { return }
        let ticket = generation
        loading = true; error = nil
        defer { if generation == ticket { loading = false } }
        do {
            // Bound each request group. If search/private filters match no rows yet,
            // show an explicit continue action instead of claiming there are no results.
            for _ in 0..<4 {
                try Task.checkCancellation()
                let page = try await loadPage(query, 15, cursor)
                guard generation == ticket, !Task.isCancelled else { return }
                if replacePending { posts = []; replacePending = false }
                let visible = visibility.visibleNews(page.items)
                var ids = Set(posts.map { $0.id })
                posts += visible.filter { ids.insert($0.id).inserted }
                cursor = page.nextCursor
                hasMore = page.hasMore && page.nextCursor != nil
                if !visible.isEmpty || !hasMore { break }
            }
        } catch is CancellationError {
        } catch {
            guard generation == ticket, !Task.isCancelled else { return }
            self.error = NewsBrowseStrings.text("error")
        }
    }
}
