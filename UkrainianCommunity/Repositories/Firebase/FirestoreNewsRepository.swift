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
        let bookmarkedNewsIDs = try await fetchBookmarkedNewsIDs()

        return try snapshot.documents
            .map { document in
                try NewsPost(dto: makeNewsPostDTO(from: document, likedNewsIDs: likedNewsIDs, bookmarkedNewsIDs: bookmarkedNewsIDs))
            }
            .filter(\.isOrganizationNews)
    }

    func fetchPendingNews() async throws -> [NewsPost] {
        let snapshot = try await collection
            .whereField("moderationStatus", isEqualTo: ModerationStatus.pendingReview.rawValue)
            .order(by: "createdAt", descending: true)
            .getDocuments()

        let likedNewsIDs = try await fetchLikedNewsIDs()
        let bookmarkedNewsIDs = try await fetchBookmarkedNewsIDs()

        return try snapshot.documents
            .map { document in
                try NewsPost(dto: makeNewsPostDTO(from: document, likedNewsIDs: likedNewsIDs, bookmarkedNewsIDs: bookmarkedNewsIDs))
            }
            .filter(\.isOrganizationNews)
    }

    func fetchOrganizationModerationNews(organizationID: String) async throws -> [NewsPost] {
        let snapshot = try await collection
            .whereField("sourceType", isEqualTo: ContentSourceType.organization.rawValue)
            .whereField("organizationId", isEqualTo: organizationID)
            .whereField("moderationStatus", in: organizationModerationStatusValues)
            .order(by: "createdAt", descending: true)
            .getDocuments()

        let likedNewsIDs = try await fetchLikedNewsIDs()
        let bookmarkedNewsIDs = try await fetchBookmarkedNewsIDs()

        return try snapshot.documents.map { document in
            try NewsPost(dto: makeNewsPostDTO(from: document, likedNewsIDs: likedNewsIDs, bookmarkedNewsIDs: bookmarkedNewsIDs))
        }
    }

    func fetchOrganizationNewsCount(organizationID: String) async throws -> Int {
        let snapshot = try await collection
            .whereField("sourceType", isEqualTo: ContentSourceType.organization.rawValue)
            .whereField("organizationId", isEqualTo: organizationID)
            .whereField("moderationStatus", in: organizationContentStatusValues)
            .getDocuments()

        return snapshot.documents.count
    }

    func createNews(_ news: NewsPost) async throws {
        guard news.isOrganizationNews else {
            throw AppError.validationFailed
        }

        let dto = news.dto

        var data: [String: Any] = [
            "id": dto.id,
            "title": dto.title,
            "subtitle": dto.subtitle,
            "summary": dto.subtitle,
            "regionScope": dto.regionScope as Any,
            "federalState": dto.federalState as Any,
            "city": dto.city as Any,
            "category": dto.category as Any,
            "tags": dto.tags as Any,
            "sourceType": dto.sourceType as Any,
            "organizationId": dto.organizationId as Any,
            "organizationName": dto.organizationName as Any,
            "organizationImageURL": dto.organizationImageURL as Any,
            "imageURL": dto.imageURL as Any,
            "body": dto.body,
            "authorName": dto.authorName,
            "publishedAt": Timestamp(date: dto.publishedAt),
            "createdAt": Timestamp(date: dto.createdAt),
            "updatedAt": Timestamp(date: dto.updatedAt),
            "moderationStatus": dto.moderationStatus,
            "likeCount": dto.likeCount,
            "likeState": dto.likeState,
            "viewCount": dto.viewCount,
            "commentCount": dto.commentCount ?? dto.comments.count
        ]
        if let sourceName = dto.sourceName {
            data["sourceName"] = sourceName
        }
        if let sourceURL = dto.sourceURL {
            data["sourceURL"] = sourceURL
        }
        try await collection.document(news.id).setData(data)
    }

    func updateNews(_ news: NewsPost) async throws {
        guard news.isOrganizationNews else {
            throw AppError.validationFailed
        }

        var data: [String: Any] = [
            "title": news.title,
            "subtitle": news.subtitle,
            "summary": news.subtitle,
            "regionScope": news.regionScope?.rawValue as Any,
            "federalState": news.federalState?.rawValue as Any,
            "city": news.city as Any,
            "category": news.category.rawValue,
            "tags": news.tags,
            "sourceType": news.source.sourceType.rawValue,
            "organizationId": news.source.organizationId as Any,
            "organizationName": news.source.organizationName as Any,
            "organizationImageURL": news.source.organizationImageURL as Any,
            "body": news.body,
            "imageURL": news.imageURL as Any,
            "authorName": news.authorName,
            "updatedAt": Timestamp(date: news.updatedAt)
        ]
        data["sourceName"] = news.sourceName ?? FieldValue.delete()
        data["sourceURL"] = news.sourceURL ?? FieldValue.delete()
        try await collection.document(news.id).updateData(data)
    }

    func updateNewsImageURL(id: String, imageURL: String?) async throws {
        try await collection.document(id).updateData([
            "imageURL": imageURL as Any,
            "updatedAt": Timestamp(date: Date())
        ])
    }

    func deleteNews(id: String) async throws {
        await deleteNewsCoverImageIfPossible(id: id)
        try await collection.document(id).delete()
        await deleteRelatedLikesIfPossible(newsID: id)
    }

    private func deleteNewsCoverImageIfPossible(id: String) async {
        let imageReference = Storage.storage().reference().child("news/\(id)/cover.jpg")
        do {
            try await imageReference.delete()
        } catch {}
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
            throw error
        }
    }

    func updateModerationStatus(id: String, newStatus: ModerationStatus) async throws {
        try await collection.document(id).updateData([
            "moderationStatus": newStatus.rawValue,
            "updatedAt": Timestamp(date: Date())
        ])
    }

    func recordNewsView(id: String) async throws -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }

        let newsReference = collection.document(id)
        let viewReference = viewReference(newsID: id, userID: uid)
        let viewData: [String: Any] = [
            "id": id,
            "newsId": id,
            "userId": uid,
            "createdAt": FieldValue.serverTimestamp()
        ]

        let result = try await Firestore.firestore().runTransaction { transaction, errorPointer in
            do {
                let newsSnapshot = try transaction.getDocument(newsReference)
                guard newsSnapshot.exists else {
                    errorPointer?.pointee = AppError.notFound.asNSError
                    return false
                }

                let viewSnapshot = try transaction.getDocument(viewReference)
                guard !viewSnapshot.exists else {
                    return false
                }

                transaction.setData(viewData, forDocument: viewReference)
                transaction.updateData([
                    "viewCount": FieldValue.increment(Int64(1))
                ], forDocument: newsReference)
                return true
            } catch {
                errorPointer?.pointee = error as NSError
                return false
            }
        }

        return result as? Bool ?? false
    }

    func fetchNewsComments(newsID: String) async throws -> [Comment] {
        try await fetchComments(newsID: newsID)
    }

    func addNewsComment(newsID: String, text: String, author: AppUser) async throws -> Comment {
        guard Auth.auth().currentUser?.uid == author.id else {
            throw AppError.permissionDenied
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw AppError.validationFailed
        }

        let now = Date()
        let newsReference = collection.document(newsID)
        let commentReference = newsReference.collection("comments").document()
        let comment = Comment(
            id: commentReference.documentID,
            parentType: .news,
            parentId: newsID,
            authorId: author.id,
            authorName: author.commentDisplayName,
            authorPhotoURL: author.avatarURL?.absoluteString,
            text: String(trimmedText.prefix(1000)),
            createdAt: now,
            updatedAt: nil,
            moderationStatus: .approved,
            isDeleted: false
        )

        let firestore = Firestore.firestore()
        let batch = firestore.batch()
        batch.setData(makeCommentData(from: comment.dto), forDocument: commentReference)
        batch.updateData([
            "commentCount": FieldValue.increment(Int64(1))
        ], forDocument: newsReference)
        try await batch.commit()
        return comment
    }

    func updateNewsComment(newsID: String, commentID: String, text: String) async throws -> Comment {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppError.permissionDenied
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw AppError.validationFailed
        }

        let commentReference = collection.document(newsID).collection("comments").document(commentID)
        let snapshot = try await commentReference.getDocument()
        guard let existing = makeCommentDTO(from: snapshot.data() ?? [:]) else {
            throw AppError.notFound
        }
        guard existing.authorId == uid else {
            throw AppError.permissionDenied
        }

        let now = Date()
        try await commentReference.updateData([
            "text": String(trimmedText.prefix(1000)),
            "body": String(trimmedText.prefix(1000)),
            "updatedAt": Timestamp(date: now)
        ])

        return Comment(
            id: commentID,
            parentType: .news,
            parentId: newsID,
            authorId: existing.authorId,
            authorName: existing.authorName,
            authorPhotoURL: existing.authorPhotoURL,
            text: String(trimmedText.prefix(1000)),
            createdAt: existing.createdAt,
            updatedAt: now,
            moderationStatus: existing.moderationStatus.flatMap(ModerationStatus.init(rawValue:)) ?? .approved,
            isDeleted: existing.isDeleted ?? false
        )
    }

    func deleteNewsComment(newsID: String, commentID: String) async throws {
        guard Auth.auth().currentUser != nil else {
            throw AppError.permissionDenied
        }

        let newsReference = collection.document(newsID)
        let commentReference = newsReference.collection("comments").document(commentID)
        _ = try await Firestore.firestore().runTransaction { transaction, errorPointer in
            do {
                let newsSnapshot = try transaction.getDocument(newsReference)
                let commentSnapshot = try transaction.getDocument(commentReference)
                guard makeCommentDTO(from: commentSnapshot.data() ?? [:]) != nil else {
                    errorPointer?.pointee = AppError.notFound.asNSError
                    return nil
                }

                transaction.deleteDocument(commentReference)
                let currentCommentCount = newsSnapshot.data()?["commentCount"] as? Int ?? 0
                if currentCommentCount > 0 {
                    transaction.updateData([
                        "commentCount": currentCommentCount - 1
                    ], forDocument: newsReference)
                }
            } catch {
                errorPointer?.pointee = error as NSError
            }

            return nil
        }
    }

    func bookmarkNews(id: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppError.permissionDenied
        }

        let bookmarkReference = bookmarkReference(newsID: id, userID: uid)
        try await bookmarkReference.setData([
            "id": id,
            "newsId": id,
            "userId": uid,
            "createdAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    func unbookmarkNews(id: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppError.permissionDenied
        }

        try await bookmarkReference(newsID: id, userID: uid).delete()
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

    private func fetchBookmarkedNewsIDs() async throws -> Set<String> {
        guard let uid = Auth.auth().currentUser?.uid else {
            return []
        }

        let snapshot = try await Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("newsBookmarks")
            .getDocuments()

        return Set(snapshot.documents.compactMap { $0.data()["newsId"] as? String })
    }

    private func makeNewsPostDTO(from document: QueryDocumentSnapshot, likedNewsIDs: Set<String>, bookmarkedNewsIDs: Set<String>) throws -> NewsPostDTO {
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
            regionScope: data["regionScope"] as? String,
            federalState: data["federalState"] as? String,
            city: data["city"] as? String,
            category: data["category"] as? String,
            tags: data["tags"] as? [String],
            sourceType: data["sourceType"] as? String,
            organizationId: data["organizationId"] as? String,
            organizationName: data["organizationName"] as? String,
            organizationImageURL: data["organizationImageURL"] as? String,
            sourceName: (data["sourceName"] as? String)?.nilIfEmpty,
            sourceURL: (data["sourceURL"] as? String)?.nilIfEmpty,
            imageURL: (data["imageURL"] as? String)?.nilIfEmpty,
            body: body,
            authorName: authorName,
            publishedAt: publishedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            comments: comments,
            commentCount: (data["commentCount"] as? Int) ?? (data["commentCount"] as? NSNumber)?.intValue ?? 0,
            moderationStatus: moderationStatus,
            likeCount: data["likeCount"] as? Int ?? 0,
            likeState: likedNewsIDs.contains(document.documentID) ? LikeState.liked.rawValue : LikeState.notLiked.rawValue,
            viewCount: data["viewCount"] as? Int ?? 0,
            isBookmarked: bookmarkedNewsIDs.contains(document.documentID)
        )
    }

    private func likeDocumentID(newsID: String, userID: String) -> String {
        "\(newsID)_\(userID)"
    }

    private var organizationModerationStatusValues: [String] {
        [
            ModerationStatus.pendingReview.rawValue,
            ModerationStatus.rejected.rawValue,
            ModerationStatus.archived.rawValue
        ]
    }

    private var organizationContentStatusValues: [String] {
        [
            ModerationStatus.pendingReview.rawValue,
            ModerationStatus.approved.rawValue
        ]
    }

    private func bookmarkReference(newsID: String, userID: String) -> DocumentReference {
        Firestore.firestore()
            .collection("users")
            .document(userID)
            .collection("newsBookmarks")
            .document(newsID)
    }

    private func viewReference(newsID: String, userID: String) -> DocumentReference {
        Firestore.firestore()
            .collection("users")
            .document(userID)
            .collection("newsViews")
            .document(newsID)
    }

    private func fetchComments(newsID: String) async throws -> [Comment] {
        let snapshot = try await collection.document(newsID)
            .collection("comments")
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "createdAt", descending: false)
            .getDocuments()

        return snapshot.documents.compactMap { makeCommentDTO(from: $0.data()).map(Comment.init(dto:)) }
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

    private func deleteRelatedLikesIfPossible(newsID: String) async {
        do {
            try await deleteRelatedLikes(newsID: newsID)
        } catch {}
    }

    private func makeCommentData(from dto: CommentDTO) -> [String: Any] {
        var data: [String: Any] = [
            "id": dto.id,
            "authorName": dto.authorName,
            "text": dto.text,
            "body": dto.text,
            "createdAt": Timestamp(date: dto.createdAt),
            "isDeleted": dto.isDeleted ?? false
        ]

        if let parentType = dto.parentType {
            data["parentType"] = parentType
        }
        if let parentId = dto.parentId {
            data["parentId"] = parentId
        }
        if let authorId = dto.authorId {
            data["authorId"] = authorId
        }
        if let authorPhotoURL = dto.authorPhotoURL {
            data["authorPhotoURL"] = authorPhotoURL
        }
        if let updatedAt = dto.updatedAt {
            data["updatedAt"] = Timestamp(date: updatedAt)
        }
        if let moderationStatus = dto.moderationStatus {
            data["moderationStatus"] = moderationStatus
        }
        return data
    }

    private func makeCommentDTO(from data: [String: Any]) -> CommentDTO? {
        guard
            let id = data["id"] as? String,
            let authorName = data["authorName"] as? String,
            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        else {
            return nil
        }
        let text = (data["text"] as? String) ?? (data["body"] as? String) ?? ""
        guard !text.isEmpty else { return nil }

        return CommentDTO(
            id: id,
            parentType: data["parentType"] as? String,
            parentId: data["parentId"] as? String,
            authorId: data["authorId"] as? String,
            authorName: authorName,
            authorPhotoURL: data["authorPhotoURL"] as? String,
            text: text,
            createdAt: createdAt,
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue(),
            moderationStatus: data["moderationStatus"] as? String,
            isDeleted: data["isDeleted"] as? Bool
        )
    }
}

extension FirestoreNewsRepository: NewsRealtimeRepository {
    func listenNewsComments(
        newsID: String,
        onChange: @escaping @MainActor ([Comment]) -> Void,
        onError: @escaping @MainActor (AppError) -> Void
    ) -> AppRealtimeListener {
        let registration = collection.document(newsID)
            .collection("comments")
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { snapshot, error in
                if let error {
                    Task { @MainActor in onError(Self.appError(from: error)) }
                    return
                }

                let comments = snapshot?.documents.compactMap { makeCommentDTO(from: $0.data()).map(Comment.init(dto:)) } ?? []
                Task { @MainActor in onChange(comments) }
            }
        return FirebaseRealtimeListener(registration)
    }

    private static func appError(from error: Error) -> AppError {
        let nsError = error as NSError
        if nsError.domain == FirestoreErrorDomain,
           nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
            return .permissionDenied
        }
        return .network
    }
}

private extension NewsPost {
    var isOrganizationNews: Bool {
        source.sourceType == .organization
            && source.organizationId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension AppUser {
    nonisolated var commentDisplayName: String {
        let display = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !display.isEmpty { return display }
        let full = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        return full.isEmpty ? "User" : full
    }
}
