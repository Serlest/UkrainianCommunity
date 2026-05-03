import Foundation
import FirebaseAuth
import FirebaseFirestore

struct FirestoreOrganizationRepository: OrganizationRepository {
    private let collection = Firestore.firestore().collection("organizations")
    private let likesCollection = Firestore.firestore().collection("likes")

    func fetchOrganizations() async throws -> [Organization] {
        let snapshot = try await collection
            .whereField("moderationStatus", isEqualTo: ModerationStatus.approved.rawValue)
            .order(by: "createdAt", descending: true)
            .getDocuments()

        let likedOrganizationIDs = try await fetchLikedOrganizationIDs()

        return try snapshot.documents.map { document in
            try Organization(dto: makeOrganizationDTO(from: document, likedOrganizationIDs: likedOrganizationIDs))
        }
    }

    func likeOrganization(id: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppError.permissionDenied
        }

        let organizationReference = collection.document(id)
        let likeReference = likesCollection.document(likeDocumentID(organizationID: id, userID: uid))

        _ = try await Firestore.firestore().runTransaction { transaction, errorPointer in
            do {
                let organizationSnapshot = try transaction.getDocument(organizationReference)
                guard organizationSnapshot.exists else {
                    errorPointer?.pointee = AppError.notFound.asNSError
                    return nil
                }

                let likeSnapshot = try transaction.getDocument(likeReference)
                if likeSnapshot.exists {
                    return nil
                }

                transaction.setData([
                    "id": likeReference.documentID,
                    "organizationId": id,
                    "userId": uid,
                    "createdAt": FieldValue.serverTimestamp()
                ], forDocument: likeReference)
                transaction.updateData([
                    "likeCount": FieldValue.increment(Int64(1))
                ], forDocument: organizationReference)
            } catch {
                errorPointer?.pointee = error as NSError
            }

            return nil
        }
    }

    func unlikeOrganization(id: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppError.permissionDenied
        }

        let organizationReference = collection.document(id)
        let likeReference = likesCollection.document(likeDocumentID(organizationID: id, userID: uid))

        _ = try await Firestore.firestore().runTransaction { transaction, errorPointer in
            do {
                let organizationSnapshot = try transaction.getDocument(organizationReference)
                guard organizationSnapshot.exists else {
                    errorPointer?.pointee = AppError.notFound.asNSError
                    return nil
                }

                let likeSnapshot = try transaction.getDocument(likeReference)
                guard likeSnapshot.exists else {
                    return nil
                }

                let currentLikeCount = organizationSnapshot.data()?["likeCount"] as? Int ?? 0
                transaction.deleteDocument(likeReference)
                transaction.updateData([
                    "likeCount": max(0, currentLikeCount - 1)
                ], forDocument: organizationReference)
            } catch {
                errorPointer?.pointee = error as NSError
            }

            return nil
        }
    }

    private func fetchLikedOrganizationIDs() async throws -> Set<String> {
        guard let uid = Auth.auth().currentUser?.uid else {
            return []
        }

        let snapshot = try await likesCollection
            .whereField("userId", isEqualTo: uid)
            .getDocuments()

        return Set(snapshot.documents.compactMap { $0.data()["organizationId"] as? String })
    }

    private func makeOrganizationDTO(
        from document: QueryDocumentSnapshot,
        likedOrganizationIDs: Set<String>
    ) throws -> OrganizationDTO {
        let data = document.data()

        guard
            let name = data["name"] as? String,
            let description = data["description"] as? String,
            let city = data["city"] as? String,
            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
            let moderationStatus = data["moderationStatus"] as? String
        else {
            throw AppError.notFound
        }

        return OrganizationDTO(
            id: data["id"] as? String ?? document.documentID,
            name: name,
            description: description,
            city: city,
            imageURL: data["imageURL"] as? String,
            contactEmail: data["contactEmail"] as? String,
            website: data["website"] as? String,
            createdAt: createdAt,
            moderationStatus: moderationStatus,
            likeCount: data["likeCount"] as? Int ?? 0,
            likeState: likedOrganizationIDs.contains(document.documentID) ? LikeState.liked.rawValue : LikeState.notLiked.rawValue
        )
    }

    private func likeDocumentID(organizationID: String, userID: String) -> String {
        "organization_\(organizationID)_\(userID)"
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
