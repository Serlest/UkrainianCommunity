import Foundation
import FirebaseAuth
import FirebaseFirestore

struct FirestoreNewsRepository: NewsRepository {
    private let collection = Firestore.firestore().collection("news")
    private let likesCollection = Firestore.firestore().collection("likes")
    private let sessionDataCache: SessionDataCache

    init(sessionDataCache: SessionDataCache = .shared) {
        self.sessionDataCache = sessionDataCache
    }

    func fetchNews() async throws -> [NewsPost] {
        try await fetchNewsPage(limit: 30, after: nil).items
    }

    func fetchNews(id: String) async throws -> NewsPost {
        let document = try await collection.document(id).getDocument()
        guard document.exists else { throw AppError.notFound }
        let likedIDs = try await fetchLikedNewsIDs()
        let bookmarkedIDs = try await fetchBookmarkedNewsIDs()
        let post = try NewsPost(dto: makeNewsPostDTO(
            from: document,
            likedNewsIDs: likedIDs,
            bookmarkedNewsIDs: bookmarkedIDs
        ))
        guard post.moderationStatus == .approved, post.isOrganizationNews else {
            throw AppError.notFound
        }
        return post
    }

    func fetchBookmarkedNews() async throws -> [NewsPost] {
        let bookmarkedIDs = try await fetchBookmarkedNewsIDs()
        guard !bookmarkedIDs.isEmpty else { return [] }
        let likedIDs = try await fetchLikedNewsIDs()
        var posts: [NewsPost] = []

        for chunk in Array(bookmarkedIDs).chunked(into: 10) {
            let snapshot = try await collection
                .whereField(FieldPath.documentID(), in: Array(chunk))
                .whereField("moderationStatus", isEqualTo: ModerationStatus.approved.rawValue)
                .getDocuments()
            let resolved = try snapshot.documents.compactMap { document -> NewsPost? in
                let post = try NewsPost(dto: makeNewsPostDTO(
                    from: document,
                    likedNewsIDs: likedIDs,
                    bookmarkedNewsIDs: bookmarkedIDs
                ))
                return post.moderationStatus == .approved && post.isOrganizationNews ? post : nil
            }
            posts.append(contentsOf: resolved)
        }

        return posts.sorted { $0.publishedAt > $1.publishedAt }
    }

    func fetchNewsPage(limit: Int, after cursor: NewsPageCursor?) async throws -> NewsPage {
        var query: Query = collection
            .whereField("sourceType", isEqualTo: ContentSourceType.organization.rawValue)
            .whereField("moderationStatus", isEqualTo: ModerationStatus.approved.rawValue)
            .order(by: "createdAt", descending: true)
            .order(by: FieldPath.documentID(), descending: true)
            .limit(to: max(1, limit) + 1)

        if let cursor {
            query = query.start(after: [Timestamp(date: cursor.createdAt), cursor.documentID])
        }

        let snapshot = try await query.getDocuments()
        let documents = Array(snapshot.documents.prefix(max(1, limit)))
        let likedNewsIDs = try await fetchLikedNewsIDs()
        let bookmarkedNewsIDs = try await fetchBookmarkedNewsIDs()
        let items = try documents
            .map { document in
                try NewsPost(dto: makeNewsPostDTO(from: document, likedNewsIDs: likedNewsIDs, bookmarkedNewsIDs: bookmarkedNewsIDs))
            }

        return NewsPage(
            items: items,
            nextCursor: documents.last.flatMap(makeNewsPageCursor),
            hasMore: snapshot.documents.count > max(1, limit)
        )
    }

    func fetchOrganizationNews(organizationID: String, limit: Int) async throws -> [NewsPost] {
        let snapshot = try await collection
            .whereField("sourceType", isEqualTo: ContentSourceType.organization.rawValue)
            .whereField("organizationId", isEqualTo: organizationID)
            .whereField("moderationStatus", isEqualTo: ModerationStatus.approved.rawValue)
            .order(by: "createdAt", descending: true)
            .limit(to: max(1, limit))
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
            .count
            .getAggregation(source: .server)

        return snapshot.count.intValue
    }

    func createNews(_ news: NewsPost) async throws {
        guard news.isOrganizationNews else {
            throw AppError.validationFailed
        }
        guard let authorID = Auth.auth().currentUser?.uid else {
            throw AppError.permissionDenied
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
            "authorId": authorID,
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
        do {
            try await collection.document(news.id).setData(data)
        } catch {
            await SystemTechnicalErrorLoggingService.shared.logFailure(
                error,
                context: SystemTechnicalErrorContext(
                    moduleName: "News",
                    operationName: "createNews",
                    targetType: .newsPost,
                    targetId: news.id,
                    targetTitle: news.title,
                    organizationId: news.source.organizationId,
                    organizationName: news.source.organizationName
                )
            )
            throw error
        }

        await SystemAuditLoggingService.shared.logSuccess(
            SystemAuditLogContext(
                moduleName: "News",
                operationName: "createNews",
                eventType: .contentCreated,
                targetType: .newsPost,
                targetId: news.id,
                targetTitle: news.title,
                organizationId: news.source.organizationId,
                organizationName: news.source.organizationName,
                summary: "News post created"
            )
        )
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
            "authorName": news.authorName,
            "updatedAt": Timestamp(date: news.updatedAt)
        ]
        if let imageURL = news.imageURL {
            data["imageURL"] = imageURL
        } else {
            data["imageURL"] = FieldValue.delete()
        }
        data["sourceName"] = news.sourceName ?? FieldValue.delete()
        data["sourceURL"] = news.sourceURL ?? FieldValue.delete()
        do {
            try await collection.document(news.id).updateData(data)
        } catch {
            await SystemTechnicalErrorLoggingService.shared.logFailure(
                error,
                context: SystemTechnicalErrorContext(
                    moduleName: "News",
                    operationName: "updateNews",
                    targetType: .newsPost,
                    targetId: news.id,
                    targetTitle: news.title,
                    organizationId: news.source.organizationId,
                    organizationName: news.source.organizationName
                )
            )
            throw error
        }

        await SystemAuditLoggingService.shared.logSuccess(
            SystemAuditLogContext(
                moduleName: "News",
                operationName: "updateNews",
                eventType: .contentUpdated,
                targetType: .newsPost,
                targetId: news.id,
                targetTitle: news.title,
                organizationId: news.source.organizationId,
                organizationName: news.source.organizationName,
                summary: "News post updated"
            )
        )
    }

    func updateNewsImageURL(id: String, imageURL: String?) async throws {
        do {
            var data: [String: Any] = ["updatedAt": Timestamp(date: Date())]
            if let imageURL {
                data["imageURL"] = imageURL
            } else {
                data["imageURL"] = FieldValue.delete()
            }
            try await collection.document(id).updateData(data)
        } catch {
            await SystemTechnicalErrorLoggingService.shared.logFailure(
                error,
                context: SystemTechnicalErrorContext(
                    moduleName: "News",
                    operationName: "updateNewsImageURL",
                    targetType: .newsPost,
                    targetId: id
                )
            )
            throw error
        }
    }

    func deleteNews(id: String) async throws {
        do {
            _ = try await CloudFunctionsClient.shared.deleteNews(id: id)
        } catch {
            await SystemTechnicalErrorLoggingService.shared.logFailure(
                error,
                context: SystemTechnicalErrorContext(
                    moduleName: "News",
                    operationName: "deleteNews",
                    targetType: .newsPost,
                    targetId: id
                )
            )
            throw error
        }

        await SystemAuditLoggingService.shared.logSuccess(
            SystemAuditLogContext(
                moduleName: "News",
                operationName: "deleteNews",
                eventType: .contentDeleted,
                targetType: .newsPost,
                targetId: id,
                summary: "News post deleted"
            )
        )
    }

    func likeNews(id: String, actionCapture: AnalyticsActionCapture?) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppError.permissionDenied
        }

        let newsReference = collection.document(id)
        let likeReference = likesCollection.document(likeDocumentID(newsID: id, userID: uid))
        let proofReference = actionCapture.map {
            Firestore.firestore().collection("analyticsActionProofs").document($0.proofID)
        }
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
                if let actionCapture,
                   actionCapture.eventName == "news_like",
                   actionCapture.contentID == id,
                   let proofReference {
                    transaction.setData(actionCapture.firestoreData, forDocument: proofReference)
                }
            } catch {
                errorPointer?.pointee = (error as NSError)
            }

            return nil
            }
        } catch {
            throw error
        }
        await sessionDataCache.updateLikedNewsID(id, isLiked: true, for: uid)
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

                transaction.deleteDocument(likeReference)
            } catch {
                errorPointer?.pointee = (error as NSError)
            }

            return nil
            }
        } catch {
            throw error
        }
        await sessionDataCache.updateLikedNewsID(id, isLiked: false, for: uid)
    }

    func updateModerationStatus(id: String, newStatus: ModerationStatus) async throws {
        try await collection.document(id).updateData([
            "moderationStatus": newStatus.rawValue,
            "updatedAt": Timestamp(date: Date())
        ])

        await logModerationStatusChange(id: id, newStatus: newStatus)
    }

    private func logModerationStatusChange(id: String, newStatus: ModerationStatus) async {
        guard let moderationLogContext = moderationLogContext(id: id, newStatus: newStatus) else { return }
        await SystemModerationLoggingService.shared.logSuccess(moderationLogContext)
    }

    private func moderationLogContext(id: String, newStatus: ModerationStatus) -> SystemModerationLogContext? {
        switch newStatus {
        case .approved:
            return SystemModerationLogContext(
                operationName: "approveNewsPost",
                eventType: .contentApproved,
                targetType: .newsPost,
                targetId: id,
                outcome: .approved,
                summary: "Новину схвалено",
                metadata: ["newStatus": newStatus.rawValue]
            )
        case .rejected:
            return SystemModerationLogContext(
                operationName: "rejectNewsPost",
                eventType: .contentRejected,
                targetType: .newsPost,
                targetId: id,
                outcome: .rejected,
                summary: "Новину відхилено",
                metadata: ["newStatus": newStatus.rawValue]
            )
        case .draft, .pendingReview, .needsRevision, .archived:
            return nil
        }
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
        return try await CloudCommentMutationService.shared.save(
            parentType: .news,
            parentId: newsID,
            text: text
        )
    }

    func updateNewsComment(newsID: String, commentID: String, text: String) async throws -> Comment {
        throw AppError.permissionDenied
    }

    func deleteNewsComment(newsID: String, commentID: String) async throws {
        guard Auth.auth().currentUser != nil else {
            throw AppError.permissionDenied
        }

        let newsReference = collection.document(newsID)
        let commentReference = newsReference.collection("comments").document(commentID)
        _ = try await Firestore.firestore().runTransaction { transaction, errorPointer in
            do {
                _ = try transaction.getDocument(newsReference)
                let commentSnapshot = try transaction.getDocument(commentReference)
                guard makeCommentDTO(from: commentSnapshot.data() ?? [:]) != nil else {
                    errorPointer?.pointee = AppError.notFound.asNSError
                    return nil
                }

                transaction.deleteDocument(commentReference)
            } catch {
                errorPointer?.pointee = error as NSError
            }

            return nil
        }
    }

    func bookmarkNews(id: String, actionCapture: AnalyticsActionCapture?) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppError.permissionDenied
        }

        let database = Firestore.firestore()
        let bookmarkReference = bookmarkReference(newsID: id, userID: uid)
        let batch = database.batch()
        batch.setData([
            "id": id,
            "newsId": id,
            "userId": uid,
            "createdAt": FieldValue.serverTimestamp()
        ], forDocument: bookmarkReference)
        if let actionCapture,
           actionCapture.eventName == "news_bookmark",
           actionCapture.contentID == id {
            batch.setData(
                actionCapture.firestoreData,
                forDocument: database.collection("analyticsActionProofs").document(actionCapture.proofID)
            )
        }
        try await batch.commit()
        await sessionDataCache.updateBookmarkedNewsID(id, isBookmarked: true, for: uid)
    }

    func unbookmarkNews(id: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppError.permissionDenied
        }

        try await bookmarkReference(newsID: id, userID: uid).delete()
        await sessionDataCache.updateBookmarkedNewsID(id, isBookmarked: false, for: uid)
    }

    private func fetchLikedNewsIDs() async throws -> Set<String> {
        guard let uid = Auth.auth().currentUser?.uid else {
            return []
        }
        if let cached = await sessionDataCache.cachedLikedNewsIDs(for: uid) {
            return cached
        }

        let snapshot = try await likesCollection
            .whereField("userId", isEqualTo: uid)
            .getDocuments()

        let ids = Set(snapshot.documents.compactMap { $0.data()["newsId"] as? String })
        await sessionDataCache.storeLikedNewsIDs(ids, for: uid)
        return ids
    }

    private func fetchBookmarkedNewsIDs() async throws -> Set<String> {
        guard let uid = Auth.auth().currentUser?.uid else {
            return []
        }
        if let cached = await sessionDataCache.cachedBookmarkedNewsIDs(for: uid) {
            return cached
        }

        let snapshot = try await Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("newsBookmarks")
            .getDocuments()

        let ids = Set(snapshot.documents.compactMap { $0.data()["newsId"] as? String })
        await sessionDataCache.storeBookmarkedNewsIDs(ids, for: uid)
        return ids
    }

    private func makeNewsPostDTO(from document: DocumentSnapshot, likedNewsIDs: Set<String>, bookmarkedNewsIDs: Set<String>) throws -> NewsPostDTO {
        guard
            let data = document.data(),
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
            authorId: (data["authorId"] as? String)?.nilIfEmpty,
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

    private func makeNewsPageCursor(from document: QueryDocumentSnapshot) -> NewsPageCursor? {
        guard let createdAt = (document.data()["createdAt"] as? Timestamp)?.dateValue() else {
            return nil
        }
        return NewsPageCursor(createdAt: createdAt, documentID: document.documentID)
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
                    Self.logListenerFailure(error, newsID: newsID)
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

    private static func logListenerFailure(_ error: Error, newsID: String) {
        Task {
            await SystemTechnicalErrorLoggingService.shared.logFailure(
                error,
                context: SystemTechnicalErrorContext(
                    moduleName: "News",
                    operationName: "listenNewsComments",
                    targetType: .newsPost,
                    targetId: newsID,
                    metadata: [
                        "listenerName": "newsComments",
                        "pathGroup": "news/{newsID}/comments"
                    ]
                )
            )
        }
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
