import Foundation

struct MockNewsRepository: NewsRepository {
    private let store = MockRepositoryStore.shared

    func fetchNews() async throws -> [NewsPost] {
        await store.news
            .filter { $0.moderationStatus == .approved }
            .sorted { $0.createdAt > $1.createdAt }
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

    func likeNews(id: String) async throws {
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

    func bookmarkNews(id: String) async throws {
        try await store.setNewsBookmark(id: id, isBookmarked: true)
    }

    func unbookmarkNews(id: String) async throws {
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
