import Foundation
import FirebaseFirestore

struct FirestoreGuideRepository: GuideRepository {
    private let collection = Firestore.firestore().collection("guideArticles")

    func fetchGuideArticles() async throws -> [GuideArticle] {
        let snapshot = try await collection
            .whereField("moderationStatus", isEqualTo: ModerationStatus.approved.rawValue)
            .whereField("status", isEqualTo: GuideStatus.published.rawValue)
            .order(by: "updatedAt", descending: true)
            .getDocuments()

        let articles = snapshot.documents.compactMap(makeGuideArticle)
        return articles.sorted { lhs, rhs in
            if lhs.isPinned == rhs.isPinned {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.isPinned && !rhs.isPinned
        }
    }

    func fetchDraftGuideArticles() async throws -> [GuideArticle] {
        let snapshot = try await collection
            .whereField("moderationStatus", isEqualTo: ModerationStatus.draft.rawValue)
            .getDocuments()

        return snapshot.documents
            .compactMap(makeGuideArticle)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func fetchInReviewGuideArticles() async throws -> [GuideArticle] {
        let snapshot = try await collection
            .whereField("moderationStatus", isEqualTo: ModerationStatus.pendingReview.rawValue)
            .whereField("status", isEqualTo: GuideStatus.review.rawValue)
            .getDocuments()

        return snapshot.documents
            .compactMap(makeGuideArticle)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func fetchApprovedGuideArticles() async throws -> [GuideArticle] {
        let snapshot = try await collection
            .whereField("moderationStatus", isEqualTo: ModerationStatus.approved.rawValue)
            .whereField("status", isEqualTo: GuideStatus.approved.rawValue)
            .getDocuments()

        return snapshot.documents
            .compactMap(makeGuideArticle)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func createGuideArticle(from draft: GuideArticleDraft, authorId: String) async throws -> GuideArticle {
        let trimmedAuthorId = authorId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAuthorId.isEmpty else {
            throw AppError.permissionDenied
        }

        let document = collection.document()
        let now = Date()
        let article = try draft.makeGuideArticle(
            id: document.documentID,
            createdAt: now,
            updatedAt: now,
            createdBy: trimmedAuthorId
        )

        try await document.setData(try makeCreateData(from: article))
        return article
    }

    func updateGuideArticle(id: String, from draft: GuideArticleDraft, editorId: String) async throws -> GuideArticle {
        let trimmedId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEditorId = editorId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty, !trimmedEditorId.isEmpty else {
            throw AppError.permissionDenied
        }

        let document = collection.document(trimmedId)
        let snapshot = try await document.getDocument()
        guard snapshot.exists else {
            throw AppError.notFound
        }
        guard let existingArticle = makeGuideArticle(from: snapshot) else {
            throw AppError.validationFailed
        }
        guard isEditableGuideArticle(existingArticle) else {
            throw AppError.validationFailed
        }

        let updatedAt = Date()
        let article = try draft.updatingGuideArticle(
            existingArticle,
            editorId: trimmedEditorId,
            updatedAt: updatedAt
        )

        try await document.updateData(try makeUpdateData(from: article))
        return article
    }

    func submitGuideArticleForReview(id: String, submitterId: String) async throws {
        let trimmedId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSubmitterId = submitterId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty, !trimmedSubmitterId.isEmpty else {
            throw AppError.permissionDenied
        }

        _ = try await CloudFunctionsClient.shared.submitGuideArticleForReview(
            GuideWorkflowFunctionRequest(articleId: trimmedId)
        )
    }

    func approveGuideArticle(id: String, reviewerId: String) async throws {
        let trimmedId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReviewerId = reviewerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty, !trimmedReviewerId.isEmpty else {
            throw AppError.permissionDenied
        }

        _ = try await CloudFunctionsClient.shared.approveGuideArticle(
            GuideWorkflowFunctionRequest(articleId: trimmedId)
        )
    }

    func publishGuideArticle(id: String, publisherId: String) async throws {
        let trimmedId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPublisherId = publisherId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty, !trimmedPublisherId.isEmpty else {
            throw AppError.permissionDenied
        }

        _ = try await CloudFunctionsClient.shared.publishGuideArticle(
            GuideWorkflowFunctionRequest(articleId: trimmedId)
        )
    }

    func archiveGuideArticle(id: String, editorId: String) async throws {
        let trimmedId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEditorId = editorId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty, !trimmedEditorId.isEmpty else {
            throw AppError.permissionDenied
        }

        _ = try await CloudFunctionsClient.shared.archiveGuideArticle(
            GuideWorkflowFunctionRequest(articleId: trimmedId)
        )
    }

    func deleteGuideArticle(id: String, editorId: String) async throws {
        let trimmedId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEditorId = editorId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty, !trimmedEditorId.isEmpty else {
            throw AppError.permissionDenied
        }

        let document = collection.document(trimmedId)
        let snapshot = try await document.getDocument()
        guard snapshot.exists else {
            throw AppError.notFound
        }
        guard let existingArticle = makeGuideArticle(from: snapshot),
              isEditableGuideArticle(existingArticle) else {
            throw AppError.validationFailed
        }

        try await document.delete()
    }

    private func isEditableGuideArticle(_ article: GuideArticle) -> Bool {
        guard article.archivedAt == nil else { return false }

        let isDraft = article.moderationStatus == .draft
            && (article.status == nil || article.status == .draft)
        let isPublished = article.moderationStatus == .approved
            && article.status == .published
        return isDraft || isPublished
    }
}
