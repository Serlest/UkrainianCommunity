import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

struct FirestoreNewsRepository: NewsRepository {
    private let collection = Firestore.firestore().collection("news")
    private let likesCollection = Firestore.firestore().collection("likes")

    func fetchNews() async throws -> [NewsPost] {
        let snapshot = try await collection
            .whereField("moderationStatus", isEqualTo: ModerationStatus.approved.rawValue)
            .order(by: "createdAt", descending: true)
            .getDocuments()

        let likedNewsIDs = try await fetchLikedNewsIDs()

        return try snapshot.documents.map { document in
            try NewsPost(dto: makeNewsPostDTO(from: document, likedNewsIDs: likedNewsIDs))
        }
    }

    func fetchPendingNews() async throws -> [NewsPost] {
        let snapshot = try await collection
            .whereField("moderationStatus", isEqualTo: ModerationStatus.pendingReview.rawValue)
            .order(by: "createdAt", descending: true)
            .getDocuments()

        let likedNewsIDs = try await fetchLikedNewsIDs()

        return try snapshot.documents.map { document in
            try NewsPost(dto: makeNewsPostDTO(from: document, likedNewsIDs: likedNewsIDs))
        }
    }

    func createNews(_ news: NewsPost) async throws {
        let dto = news.dto

        try await collection.document(news.id).setData([
            "id": dto.id,
            "title": dto.title,
            "subtitle": dto.subtitle,
            "summary": dto.subtitle,
            "imageURL": dto.imageURL as Any,
            "body": dto.body,
            "authorName": dto.authorName,
            "publishedAt": Timestamp(date: dto.publishedAt),
            "createdAt": Timestamp(date: dto.createdAt),
            "updatedAt": Timestamp(date: dto.updatedAt),
            "comments": dto.comments.map(makeCommentData(from:)),
            "moderationStatus": dto.moderationStatus,
            "likeCount": dto.likeCount,
            "likeState": dto.likeState
        ])
    }

    func updateNews(_ news: NewsPost) async throws {
        try await collection.document(news.id).updateData([
            "title": news.title,
            "subtitle": news.subtitle,
            "summary": news.subtitle,
            "body": news.body,
            "imageURL": news.imageURL as Any,
            "authorName": news.authorName,
            "updatedAt": Timestamp(date: news.updatedAt)
        ])
    }

    func deleteNews(id: String) async throws {
        let imageReference = Storage.storage().reference().child("news/\(id)/cover.jpg")

        do {
            try await imageReference.delete()
        } catch {}

        try await deleteRelatedLikes(newsID: id)
        try await collection.document(id).delete()
    }

    func likeNews(id: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppError.permissionDenied
        }

        let newsReference = collection.document(id)
        let likeReference = likesCollection.document(likeDocumentID(newsID: id, userID: uid))
        let likeData: [String: Any] = [
            "id": likeReference.documentID,
            "newsId": id,
            "userId": uid,
            "createdAt": FieldValue.serverTimestamp()
        ]

        do {
            _ = try await Firestore.firestore().runTransaction { transaction, errorPointer in
            do {
                let newsSnapshot = try transaction.getDocument(newsReference)
                guard newsSnapshot.exists else {
                    errorPointer?.pointee = AppError.notFound.asNSError
                    return nil
                }

                let likeSnapshot = try transaction.getDocument(likeReference)
                if likeSnapshot.exists {
                    return nil
                }

                transaction.setData(likeData, forDocument: likeReference)
                transaction.updateData([
                    "likeCount": FieldValue.increment(Int64(1))
                ], forDocument: newsReference)
            } catch {
                errorPointer?.pointee = (error as NSError)
            }

            return nil
            }
        } catch {
            let nsError = error as NSError
            print("Firestore likeNews failed")
            print("error code=\(nsError.code) domain=\(nsError.domain)")
            print("error message=\(nsError.localizedDescription)")
            throw error
        }
    }

    func unlikeNews(id: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppError.permissionDenied
        }

        let newsReference = collection.document(id)
        let likeReference = likesCollection.document(likeDocumentID(newsID: id, userID: uid))
        do {
            _ = try await Firestore.firestore().runTransaction { transaction, errorPointer in
            do {
                let newsSnapshot = try transaction.getDocument(newsReference)
                guard newsSnapshot.exists else {
                    errorPointer?.pointee = AppError.notFound.asNSError
                    return nil
                }

                let likeSnapshot = try transaction.getDocument(likeReference)
                guard likeSnapshot.exists else {
                    return nil
                }

                let currentLikeCount = newsSnapshot.data()?["likeCount"] as? Int ?? 0
                transaction.deleteDocument(likeReference)
                transaction.updateData([
                    "likeCount": max(0, currentLikeCount - 1)
                ], forDocument: newsReference)
            } catch {
                errorPointer?.pointee = (error as NSError)
            }

            return nil
            }
        } catch {
            let nsError = error as NSError
            print("Firestore unlikeNews failed")
            print("error code=\(nsError.code) domain=\(nsError.domain)")
            print("error message=\(nsError.localizedDescription)")
            throw error
        }
    }

    func updateModerationStatus(id: String, newStatus: ModerationStatus) async throws {
        try await collection.document(id).updateData([
            "moderationStatus": newStatus.rawValue,
            "updatedAt": Timestamp(date: Date())
        ])
    }

    private func fetchLikedNewsIDs() async throws -> Set<String> {
        guard let uid = Auth.auth().currentUser?.uid else {
            return []
        }

        let snapshot = try await likesCollection
            .whereField("userId", isEqualTo: uid)
            .getDocuments()

        return Set(snapshot.documents.compactMap { $0.data()["newsId"] as? String })
    }

    private func makeNewsPostDTO(from document: QueryDocumentSnapshot, likedNewsIDs: Set<String>) throws -> NewsPostDTO {
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
            imageURL: data["imageURL"] as? String,
            body: body,
            authorName: authorName,
            publishedAt: publishedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            comments: comments,
            moderationStatus: moderationStatus,
            likeCount: data["likeCount"] as? Int ?? 0,
            likeState: likedNewsIDs.contains(document.documentID) ? LikeState.liked.rawValue : LikeState.notLiked.rawValue
        )
    }

    private func likeDocumentID(newsID: String, userID: String) -> String {
        "\(newsID)_\(userID)"
    }

    private func deleteRelatedLikes(newsID: String) async throws {
        let snapshot = try await likesCollection
            .whereField("newsId", isEqualTo: newsID)
            .getDocuments()

        guard !snapshot.documents.isEmpty else { return }

        let firestore = Firestore.firestore()
        for chunk in snapshot.documents.chunked(into: 500) {
            let batch = firestore.batch()
            for document in chunk {
                batch.deleteDocument(document.reference)
            }
            try await batch.commit()
        }
    }

    private func makeCommentData(from dto: CommentDTO) -> [String: Any] {
        [
            "id": dto.id,
            "authorName": dto.authorName,
            "body": dto.body,
            "createdAt": Timestamp(date: dto.createdAt),
            "updatedAt": Timestamp(date: dto.updatedAt)
        ]
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

private extension Array {
    func chunked(into size: Int) -> [ArraySlice<Element>] {
        guard size > 0 else { return [self[...]] }

        var chunks: [ArraySlice<Element>] = []
        var currentIndex = startIndex

        while currentIndex < endIndex {
            let nextIndex = index(currentIndex, offsetBy: size, limitedBy: endIndex) ?? endIndex
            chunks.append(self[currentIndex..<nextIndex])
            currentIndex = nextIndex
        }

        return chunks
    }
}

private extension AppError {
    var asNSError: NSError {
        NSError(domain: "AppError", code: code)
    }

    var code: Int {
        switch self {
        case .network:
            1
        case .permissionDenied:
            2
        case .validationFailed:
            3
        case .notFound:
            4
        case .unknown:
            5
        }
    }
}
