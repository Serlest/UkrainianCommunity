import Foundation
import FirebaseFirestore

struct FirestoreGuideRepository: InfoRepository {
    private let collection = Firestore.firestore().collection("guideArticles")

    func fetchGuideArticles() async throws -> [GuideArticle] {
        let snapshot = try await collection
            .whereField("moderationStatus", isEqualTo: ModerationStatus.approved.rawValue)
            .order(by: "updatedAt", descending: true)
            .getDocuments()

        let articles = try snapshot.documents.map(makeGuideArticle)
        return articles.sorted { lhs, rhs in
            if lhs.isPinned == rhs.isPinned {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.isPinned && !rhs.isPinned
        }
    }

    private func makeGuideArticle(from document: QueryDocumentSnapshot) throws -> GuideArticle {
        let data = document.data()

        guard
            let title = data["title"] as? String,
            let summary = data["summary"] as? String,
            let body = data["body"] as? String,
            let category = data["category"] as? String,
            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue(),
            let moderationStatus = data["moderationStatus"] as? String
        else {
            throw AppError.notFound
        }

        return GuideArticle(dto: GuideArticleDTO(
            id: data["id"] as? String ?? document.documentID,
            title: title,
            summary: summary,
            body: body,
            category: category,
            regionScope: data["regionScope"] as? String,
            federalState: data["federalState"] as? String,
            city: data["city"] as? String,
            officialSourceURL: data["officialSourceURL"] as? String,
            sourceName: data["sourceName"] as? String,
            isPinned: data["isPinned"] as? Bool ?? false,
            moderationStatus: moderationStatus,
            createdAt: createdAt,
            updatedAt: updatedAt
        ))
    }
}
