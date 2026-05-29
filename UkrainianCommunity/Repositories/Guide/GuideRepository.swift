import Foundation

protocol GuideRepository {
    func fetchGuideArticles() async throws -> [GuideArticle]
    func fetchDraftGuideArticles() async throws -> [GuideArticle]
    func fetchInReviewGuideArticles() async throws -> [GuideArticle]
    func fetchApprovedGuideArticles() async throws -> [GuideArticle]
    func createGuideArticle(from draft: GuideArticleDraft, authorId: String) async throws -> GuideArticle
    func updateGuideArticle(id: String, from draft: GuideArticleDraft, editorId: String) async throws -> GuideArticle
    func submitGuideArticleForReview(id: String, submitterId: String) async throws
    func approveGuideArticle(id: String, reviewerId: String) async throws
    func publishGuideArticle(id: String, publisherId: String) async throws
    func archiveGuideArticle(id: String, editorId: String) async throws
}

typealias InfoRepository = GuideRepository
