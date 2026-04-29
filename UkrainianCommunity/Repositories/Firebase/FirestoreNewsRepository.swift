import Foundation
import FirebaseFirestore

struct FirestoreNewsRepository: NewsRepository {
    private let collection = Firestore.firestore().collection("news")

    func fetchNews() async throws -> [NewsPost] {
        let snapshot = try await collection
            .whereField("moderationStatus", isEqualTo: ModerationStatus.approved.rawValue)
            .order(by: "createdAt", descending: true)
            .getDocuments()

        return try snapshot.documents.map { document in
            try NewsPost(dto: makeNewsPostDTO(from: document))
        }
    }

    func likeNews(id: String) async throws {
        throw AppError.unknown
    }

    func unlikeNews(id: String) async throws {
        throw AppError.unknown
    }

    private func makeNewsPostDTO(from document: QueryDocumentSnapshot) throws -> NewsPostDTO {
        let data = document.data()

        guard
            let title = data["title"] as? String,
            let body = data["body"] as? String,
            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue(),
            let moderationStatus = data["moderationStatus"] as? String
        else {
            throw AppError.notFound
        }

        let subtitle = (data["summary"] as? String) ?? (data["subtitle"] as? String) ?? ""
        let authorName = data["authorName"] as? String ?? ""
        let publishedAt = (data["publishedAt"] as? Timestamp)?.dateValue() ?? createdAt

        let comments = (data["comments"] as? [[String: Any]] ?? []).compactMap { commentData in
            makeCommentDTO(from: commentData)
        }

        return NewsPostDTO(
            id: data["id"] as? String ?? document.documentID,
            title: title,
            subtitle: subtitle,
            body: body,
            authorName: authorName,
            publishedAt: publishedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            comments: comments,
            moderationStatus: moderationStatus,
            likeCount: data["likeCount"] as? Int ?? 0,
            likeState: data["likeState"] as? String ?? LikeState.notLiked.rawValue
        )
    }

    private func makeCommentDTO(from data: [String: Any]) -> CommentDTO? {
        guard
            let id = data["id"] as? String,
            let authorName = data["authorName"] as? String,
            let body = data["body"] as? String,
            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
        else {
            return nil
        }

        return CommentDTO(
            id: id,
            authorName: authorName,
            body: body,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
