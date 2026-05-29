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
        guard existingArticle.moderationStatus == .draft,
              existingArticle.status == nil || existingArticle.status == .draft,
              existingArticle.archivedAt == nil else {
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

        let document = collection.document(trimmedId)
        let snapshot = try await document.getDocument()
        guard snapshot.exists else {
            throw AppError.notFound
        }
        guard let existingArticle = makeGuideArticle(from: snapshot) else {
            throw AppError.validationFailed
        }
        guard existingArticle.moderationStatus == .draft,
              existingArticle.status == nil || existingArticle.status == .draft,
              existingArticle.archivedAt == nil else {
            throw AppError.validationFailed
        }

        try await document.updateData(makeSubmitForReviewData(
            updatedAt: Date(),
            submitterId: trimmedSubmitterId
        ))
    }

    func approveGuideArticle(id: String, reviewerId: String) async throws {
        let trimmedId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReviewerId = reviewerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty, !trimmedReviewerId.isEmpty else {
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
        guard existingArticle.moderationStatus == .pendingReview,
              existingArticle.status == .review,
              existingArticle.archivedAt == nil else {
            throw AppError.validationFailed
        }

        try await document.updateData(makeApproveData(
            reviewedAt: Date(),
            reviewerId: trimmedReviewerId
        ))
    }

    func publishGuideArticle(id: String, publisherId: String) async throws {
        let trimmedId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPublisherId = publisherId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty, !trimmedPublisherId.isEmpty else {
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
        guard existingArticle.moderationStatus == .approved,
              existingArticle.status == .approved,
              existingArticle.archivedAt == nil else {
            throw AppError.validationFailed
        }

        let publishedAt = Date()
        let nextReviewAt = makeNextReviewDate(
            from: publishedAt,
            interval: existingArticle.reviewInterval ?? .normal
        )

        try await document.updateData(makePublishData(
            publishedAt: publishedAt,
            nextReviewAt: nextReviewAt,
            publisherId: trimmedPublisherId
        ))
    }

    func archiveGuideArticle(id: String, editorId: String) async throws {
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
        guard existingArticle.moderationStatus == .draft,
              existingArticle.status == nil || existingArticle.status == .draft,
              existingArticle.archivedAt == nil else {
            throw AppError.validationFailed
        }

        let archivedAt = Date()
        let archivedArticle = existingArticle.archivedBy(
            editorId: trimmedEditorId,
            archivedAt: archivedAt
        )

        try await document.updateData(makeArchiveData(from: archivedArticle))
    }

    private func makeNextReviewDate(from date: Date, interval: ReviewInterval) -> Date {
        Calendar.current.date(byAdding: .month, value: interval.months, to: date) ?? date
    }
}
