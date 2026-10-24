import Foundation

struct MockNewsRepository: NewsRepository {
    private let store = MockRepositoryStore.shared
    private let seededNews: [NewsPost]?

    init(seededNews: [NewsPost]? = nil) {
        self.seededNews = seededNews
    }

    func fetchNewsBrowsePage(query: NewsBrowseQuery, limit: Int, after: NewsPageCursor?) async throws -> NewsPage {
        if try await store.newsBrowsePageIsEmpty() { return NewsPage(items: [], nextCursor: nil, hasMore: false) }
        let subscribedIDs = await Set(store.organizations.filter(\.isSubscribed).map(\.id))
        let posts = try await fetchNews().filter { query.matches($0) }
            .filter { query.filter.scope != .saved || $0.isBookmarked }
            .filter { query.filter.scope != .subscribed || subscribedIDs.contains($0.source.organizationId ?? "") }
            .sorted(by: query.precedes)
        let remaining = posts.filter { post in
            guard let after else { return true }
            if post.publishedAt == after.publishedAt { return query.filter.oldestFirst ? post.id > after.documentID : post.id < after.documentID }
            return query.filter.oldestFirst ? post.publishedAt > after.publishedAt : post.publishedAt < after.publishedAt
        }
        let items = Array(remaining.prefix(max(1, min(limit, 50))))
        return NewsPage(items: items, nextCursor: items.last.map { NewsPageCursor(publishedAt: $0.publishedAt, documentID: $0.id) }, hasMore: remaining.count > items.count)
    }

    func fetchNews() async throws -> [NewsPost] {
#if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-ui-testing"),
           ProcessInfo.processInfo.environment["UITestNewsBrowseDelay"] == "1" {
            try await Task.sleep(for: .seconds(8))
        }
#endif
        if let seededNews {
            return seededNews
                .filter { $0.moderationStatus == .approved }
                .sorted { $0.createdAt > $1.createdAt }
        }
        return await store.news
            .filter { $0.moderationStatus == .approved }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func fetchSavedNews() async throws -> [SavedContentRecord<NewsPost>] {
        if try await store.personalPageIsEmpty("saved") { return [] }
        var records = try await fetchNews().filter(\.isBookmarked).map { SavedContentRecord(id: $0.id, savedAt: nil, content: $0) }
#if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-ui-testing"),
           ProcessInfo.processInfo.environment["UITestUnavailablePersonalContent"] == "1",
           !(await store.personalFixtureIsRemoved("unavailable-news")) {
            records.append(SavedContentRecord(id: "unavailable-news", savedAt: .now, content: nil))
        }
#endif
        return records
    }

    func fetchPendingNews() async throws -> [NewsPost] {
        await store.pendingNews()
    }

    func fetchOrganizationModerationNews(organizationID: String) async throws -> [NewsPost] {
        await store.organizationModerationNews(organizationID: organizationID)
    }

    func fetchOrganizationNewsCount(organizationID: String) async throws -> Int {
        await store.organizationNewsCount(organizationID: organizationID)
    }

    func createNews(_ news: NewsPost) async throws {
        await store.createNews(news)
    }

    func updateNews(_ news: NewsPost) async throws {
        try await store.updateNews(news)
    }

    func updateNewsImageURL(id: String, imageURL: String?) async throws {
        try await store.updateNewsImageURL(id: id, imageURL: imageURL)
    }

    func deleteNews(id: String) async throws {
        try await store.deleteNews(id: id)
    }

    func likeNews(id: String, actionCapture: AnalyticsActionCapture?) async throws {
        try await store.toggleNewsLike(id: id, isLiked: true)
    }

    func unlikeNews(id: String) async throws {
        try await store.toggleNewsLike(id: id, isLiked: false)
    }

    func recordNewsView(id: String) async throws -> Bool {
        try await store.recordNewsView(id: id)
    }

    func fetchNewsComments(newsID: String) async throws -> [Comment] {
        try await store.newsComments(newsID: newsID)
    }

    func bookmarkNews(id: String, actionCapture: AnalyticsActionCapture?) async throws {
        try await store.setNewsBookmark(id: id, isBookmarked: true)
    }

    func unbookmarkNews(id: String) async throws {
#if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-ui-testing"),
           ProcessInfo.processInfo.environment["UITestUnavailablePersonalContent"] == "1", id == "unavailable-news" {
            await store.removePersonalFixture(id); return
        }
#endif
        try await store.setNewsBookmark(id: id, isBookmarked: false)
    }

    func updateModerationStatus(id: String, newStatus: ModerationStatus) async throws {
        try await store.updateNewsModerationStatus(id: id, newStatus: newStatus)
    }

    func addNewsComment(newsID: String, text: String, author: AppUser) async throws -> Comment {
        try await store.addNewsComment(newsID: newsID, text: text, author: author)
    }

    func updateNewsComment(newsID: String, commentID: String, text: String) async throws -> Comment {
        try await store.updateNewsComment(newsID: newsID, commentID: commentID, text: text)
    }

    func deleteNewsComment(newsID: String, commentID: String) async throws {
        try await store.deleteNewsComment(newsID: newsID, commentID: commentID)
    }
}

extension MockNewsRepository: OrganizationActivityPageRepository {
    func fetchOrganizationActivityPage(organizationID: String, limit: Int, after: OrganizationActivityCursor?) async throws -> OrganizationActivityPage {
        try await store.publicOrganizationActivityWillLoad("news")
        let items = try await fetchNews().filter { $0.source.organizationId == organizationID }.map(OrganizationActivityItem.init(post:))
        return .mock(items: items, limit: limit, after: after)
    }
}
