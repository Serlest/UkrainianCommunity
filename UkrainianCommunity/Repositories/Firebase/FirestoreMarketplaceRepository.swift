import Foundation
import FirebaseAuth
import FirebaseFirestore

struct FirestoreMarketplaceRepository: MarketplaceRepository {
    private let collection = Firestore.firestore().collection("marketplace")
    private let likesCollection = Firestore.firestore().collection("likes")

    func fetchMarketplaceItems() async throws -> [MarketplaceItem] {
        let snapshot = try await collection
            .whereField("moderationStatus", isEqualTo: ModerationStatus.approved.rawValue)
            .order(by: "createdAt", descending: true)
            .getDocuments()

        let likedMarketplaceIDs = try await fetchLikedMarketplaceIDs()

        return try snapshot.documents.map { document in
            try MarketplaceItem(dto: makeMarketplaceItemDTO(from: document, likedMarketplaceIDs: likedMarketplaceIDs))
        }
    }

    func likeMarketplaceItem(id: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppError.permissionDenied
        }

        let itemReference = collection.document(id)
        let likeReference = likesCollection.document(likeDocumentID(itemID: id, userID: uid))

        _ = try await Firestore.firestore().runTransaction { transaction, errorPointer in
            do {
                let itemSnapshot = try transaction.getDocument(itemReference)
                guard itemSnapshot.exists else {
                    errorPointer?.pointee = AppError.notFound.asNSError
                    return nil
                }

                let likeSnapshot = try transaction.getDocument(likeReference)
                if likeSnapshot.exists {
                    return nil
                }

                transaction.setData([
                    "id": likeReference.documentID,
                    "marketplaceItemId": id,
                    "userId": uid,
                    "createdAt": FieldValue.serverTimestamp()
                ], forDocument: likeReference)
                transaction.updateData([
                    "likeCount": FieldValue.increment(Int64(1))
                ], forDocument: itemReference)
            } catch {
                errorPointer?.pointee = error as NSError
            }

            return nil
        }
    }

    func unlikeMarketplaceItem(id: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppError.permissionDenied
        }

        let itemReference = collection.document(id)
        let likeReference = likesCollection.document(likeDocumentID(itemID: id, userID: uid))

        _ = try await Firestore.firestore().runTransaction { transaction, errorPointer in
            do {
                let itemSnapshot = try transaction.getDocument(itemReference)
                guard itemSnapshot.exists else {
                    errorPointer?.pointee = AppError.notFound.asNSError
                    return nil
                }

                let likeSnapshot = try transaction.getDocument(likeReference)
                guard likeSnapshot.exists else {
                    return nil
                }

                let currentLikeCount = itemSnapshot.data()?["likeCount"] as? Int ?? 0
                transaction.deleteDocument(likeReference)
                transaction.updateData([
                    "likeCount": max(0, currentLikeCount - 1)
                ], forDocument: itemReference)
            } catch {
                errorPointer?.pointee = error as NSError
            }

            return nil
        }
    }

    private func fetchLikedMarketplaceIDs() async throws -> Set<String> {
        guard let uid = Auth.auth().currentUser?.uid else {
            return []
        }

        let snapshot = try await likesCollection
            .whereField("userId", isEqualTo: uid)
            .getDocuments()

        return Set(snapshot.documents.compactMap { $0.data()["marketplaceItemId"] as? String })
    }

    private func makeMarketplaceItemDTO(
        from document: QueryDocumentSnapshot,
        likedMarketplaceIDs: Set<String>
    ) throws -> MarketplaceItemDTO {
        let data = document.data()

        guard
            let title = data["title"] as? String,
            let description = data["description"] as? String,
            let currency = data["currency"] as? String,
            let city = data["city"] as? String,
            let category = data["category"] as? String,
            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue(),
            let moderationStatus = data["moderationStatus"] as? String
        else {
            throw AppError.notFound
        }

        let price = decimalValue(from: data["price"])
        let expiresAt = (data["expiresAt"] as? Timestamp)?.dateValue()

        return MarketplaceItemDTO(
            id: data["id"] as? String ?? document.documentID,
            title: title,
            description: description,
            price: price,
            currency: currency,
            city: city,
            category: category,
            imageURL: data["imageURL"] as? String,
            contactEmail: data["contactEmail"] as? String,
            expiresAt: expiresAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            moderationStatus: moderationStatus,
            likeCount: data["likeCount"] as? Int ?? 0,
            likeState: likedMarketplaceIDs.contains(document.documentID) ? LikeState.liked.rawValue : LikeState.notLiked.rawValue
        )
    }

    private func decimalValue(from rawValue: Any?) -> Decimal? {
        switch rawValue {
        case let decimal as Decimal:
            decimal
        case let number as NSNumber:
            number.decimalValue
        case let string as String:
            Decimal(string: string)
        default:
            nil
        }
    }

    private func likeDocumentID(itemID: String, userID: String) -> String {
        "marketplace_\(itemID)_\(userID)"
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
