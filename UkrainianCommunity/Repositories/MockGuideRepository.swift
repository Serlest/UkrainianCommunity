import Foundation

struct MockGuideRepository: GuideRepository {
    private let store = MockRepositoryStore.shared

    func fetchGuideArticles() async throws -> [GuideArticle] {
        await store.guideArticles
            .filter { $0.moderationStatus == .approved && $0.status == .published }
            .sorted { lhs, rhs in
                if lhs.isPinned == rhs.isPinned {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.isPinned && !rhs.isPinned
            }
    }

    func fetchDraftGuideArticles() async throws -> [GuideArticle] {
        await store.draftGuideArticles()
    }

    func fetchInReviewGuideArticles() async throws -> [GuideArticle] {
        await store.inReviewGuideArticles()
    }

    func fetchApprovedGuideArticles() async throws -> [GuideArticle] {
        await store.approvedGuideArticles()
    }

    func createGuideArticle(from draft: GuideArticleDraft, authorId: String) async throws -> GuideArticle {
        try await store.createGuideArticle(from: draft, authorId: authorId)
    }

    func updateGuideArticle(id: String, from draft: GuideArticleDraft, editorId: String) async throws -> GuideArticle {
        try await store.updateGuideArticle(id: id, from: draft, editorId: editorId)
    }

    func submitGuideArticleForReview(id: String, submitterId: String) async throws {
        try await store.submitGuideArticleForReview(id: id, submitterId: submitterId)
    }

    func approveGuideArticle(id: String, reviewerId: String) async throws {
        try await store.approveGuideArticle(id: id, reviewerId: reviewerId)
    }

    func publishGuideArticle(id: String, publisherId: String) async throws {
        try await store.publishGuideArticle(id: id, publisherId: publisherId)
    }

    func archiveGuideArticle(id: String, editorId: String) async throws {
        try await store.archiveGuideArticle(id: id, editorId: editorId)
    }

    func deleteGuideArticle(id: String, editorId: String) async throws {
        try await store.deleteGuideArticle(id: id, editorId: editorId)
    }
}

typealias MockInfoRepository = MockGuideRepository
