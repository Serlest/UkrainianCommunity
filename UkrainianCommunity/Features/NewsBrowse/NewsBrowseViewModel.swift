import Combine
import Foundation

@MainActor
final class NewsBrowseViewModel: ObservableObject {
    @Published private(set) var posts: [NewsPost] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var hasMore = false
    var isAwaitingFirstResult: Bool { lastLoadedAt == nil && error == nil }
    private let loadPage: (NewsBrowseQuery, Int, NewsPageCursor?) async throws -> NewsPage
    private var cursor: NewsPageCursor?
    private var query: NewsBrowseQuery?
    private var generation = 0
    private var replacePending = false
    private var pageTask: Task<Void, Never>?
    private var lastLoadedAt: Date?
    private let staleInterval: TimeInterval = 5 * 60

    init(repository: NewsRepository) {
        loadPage = { try await repository.fetchNewsBrowsePage(query: $0, limit: $1, after: $2) }
    }
    init(loadPage: @escaping (NewsBrowseQuery, Int, NewsPageCursor?) async throws -> NewsPage) {
        self.loadPage = loadPage
    }
    func clear() {
        generation += 1
        pageTask?.cancel(); pageTask = nil
        posts = []; cursor = nil; query = nil; hasMore = false; loading = false; error = nil; lastLoadedAt = nil
    }
    func loadIfNeeded(_ query: NewsBrowseQuery, visibility: ContentVisibilityPolicy) async {
        // SwiftUI can restart the task while the same page is still in flight.
        // Keep that request; changing the query still invalidates its generation.
        if self.query == query, let pageTask { await pageTask.value; return }
        if self.query == query, !replacePending, error == nil, let lastLoadedAt,
           Date().timeIntervalSince(lastLoadedAt) < staleInterval { return }
        await reload(query, visibility: visibility)
    }
    func reload(_ query: NewsBrowseQuery, visibility: ContentVisibilityPolicy) async {
        let preserve = self.query.map {
            $0.filter == query.filter && $0.region == query.region
                && $0.search == query.search && $0.accountKey == query.accountKey
        } ?? false
        if preserve {
            generation += 1; pageTask?.cancel(); pageTask = nil
            cursor = nil; hasMore = false; loading = false; error = nil
        } else { clear() }
        self.query = query
        replacePending = true
        await loadMore(visibility: visibility)
    }
    func visiblePosts(updates: [NewsPost], removedIDs: Set<String>, visibility: ContentVisibilityPolicy) -> [NewsPost] {
        let updatesByID = Dictionary(updates.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        return visibility.visibleNews(posts.compactMap { post in
            guard !removedIDs.contains(post.id) else { return nil }
            let updated = updatesByID[post.id].flatMap { $0.updatedAt >= post.updatedAt ? $0 : nil } ?? post
            guard query?.matches(updated) != false else { return nil }
            if query?.filter.scope == .saved && !updated.isBookmarked { return nil }
            return updated
        })
    }

    func loadMore(visibility: ContentVisibilityPolicy) async {
        if let pageTask { await pageTask.value; return }
        let ticket = generation
        // Keep an identical request alive across a transient tab-task cancellation.
        // clear/reload still cancel it and invalidate its generation on account/filter changes.
        let request = Task<Void, Never> { [weak self] in
            guard let self, self.generation == ticket, !Task.isCancelled else { return }
            await self.performLoadMore(visibility: visibility)
        }
        pageTask = request
        await request.value
        if generation == ticket { pageTask = nil }
    }

    private func performLoadMore(visibility: ContentVisibilityPolicy) async {
        guard !Task.isCancelled, !loading, let query else { return }
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
                lastLoadedAt = Date()
                if !visible.isEmpty || !hasMore { break }
            }
        } catch is CancellationError {
        } catch {
            guard generation == ticket, !Task.isCancelled else { return }
            self.error = NewsBrowseStrings.text("error")
        }
    }
}
