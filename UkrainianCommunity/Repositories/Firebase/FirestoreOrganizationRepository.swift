import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

struct FirestoreOrganizationRepository: OrganizationRepository {
    private let collection = Firestore.firestore().collection("organizations")
    private let likesCollection = Firestore.firestore().collection("likes")
    private let imageUploadService = ImageUploadService.shared

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

    func fetchPendingOrganizations() async throws -> [Organization] {
        let snapshot = try await collection
            .whereField("moderationStatus", isEqualTo: ModerationStatus.pendingReview.rawValue)
            .order(by: "createdAt", descending: true)
            .getDocuments()

        let likedOrganizationIDs = try await fetchLikedOrganizationIDs()

        return try snapshot.documents.map { document in
            try Organization(dto: makeOrganizationDTO(from: document, likedOrganizationIDs: likedOrganizationIDs))
        }
    }

    func createOrganization(_ organization: Organization) async throws {
        _ = try ensureAuthenticatedUserID()
        let normalizedOrganization = normalizedOrganizationForWrite(organization, preserveCreatedAt: false)
        try await collection.document(normalizedOrganization.id).setData(makeOrganizationData(from: normalizedOrganization))
    }

    func updateOrganization(_ organization: Organization) async throws {
        _ = try ensureAuthenticatedUserID()
        let normalizedOrganization = normalizedOrganizationForWrite(organization, preserveCreatedAt: true)

        try await collection.document(normalizedOrganization.id).updateData([
            "name": normalizedOrganization.name,
            "description": normalizedOrganization.description,
            "regionScope": normalizedOrganization.regionScope?.rawValue as Any,
            "federalState": normalizedOrganization.federalState?.rawValue as Any,
            "city": normalizedOrganization.city,
            "imageURL": normalizedOrganization.imageURL as Any,
            "contactEmail": normalizedOrganization.contactEmail as Any,
            "website": normalizedOrganization.website as Any,
            "updatedAt": Timestamp(date: normalizedOrganization.updatedAt),
            "moderationStatus": normalizedOrganization.moderationStatus.rawValue
        ])
    }

    func deleteOrganization(id: String) async throws {
        _ = try ensureAuthenticatedUserID()
        let imageReference = Storage.storage().reference().child("organizations/\(id)/cover.jpg")

        do {
            try await imageReference.delete()
        } catch {}

        try await deleteRelatedLikes(organizationID: id)
        try await collection.document(id).delete()
    }

    func uploadOrganizationImage(data: Data, organizationID: String) async throws -> URL {
        _ = try ensureAuthenticatedUserID()
        return try await imageUploadService.uploadOrganizationCoverImage(data: data, organizationID: organizationID)
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

    func updateModerationStatus(id: String, newStatus: ModerationStatus) async throws {
        try await collection.document(id).updateData([
            "moderationStatus": newStatus.rawValue,
            "updatedAt": Timestamp(date: Date())
        ])
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
            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue(),
            let moderationStatus = data["moderationStatus"] as? String
        else {
            throw AppError.notFound
        }

        return OrganizationDTO(
            id: data["id"] as? String ?? document.documentID,
            name: name,
            description: description,
            regionScope: data["regionScope"] as? String,
            federalState: data["federalState"] as? String,
            city: city,
            imageURL: data["imageURL"] as? String,
            contactEmail: data["contactEmail"] as? String,
            website: data["website"] as? String,
            createdAt: createdAt,
            updatedAt: updatedAt,
            moderationStatus: moderationStatus,
            likeCount: data["likeCount"] as? Int ?? 0,
            likeState: likedOrganizationIDs.contains(document.documentID) ? LikeState.liked.rawValue : LikeState.notLiked.rawValue
        )
    }

    private func likeDocumentID(organizationID: String, userID: String) -> String {
        "organization_\(organizationID)_\(userID)"
    }

    private func normalizedOrganizationForWrite(_ organization: Organization, preserveCreatedAt: Bool) -> Organization {
        let now = Date()
        let createdAt = preserveCreatedAt ? organization.createdAt : now
        let moderationStatus = preserveCreatedAt ? organization.moderationStatus : .approved

        return Organization(
            id: organization.id,
            name: organization.name,
            description: organization.description,
            regionScope: organization.regionScope,
            federalState: organization.federalState,
            city: organization.city,
            imageURL: organization.imageURL,
            contactEmail: organization.contactEmail,
            website: organization.website,
            createdAt: createdAt,
            updatedAt: now,
            moderationStatus: moderationStatus,
            likeCount: organization.likeCount,
            likeState: organization.likeState
        )
    }

    private func makeOrganizationData(from organization: Organization) -> [String: Any] {
        [
            "id": organization.id,
            "name": organization.name,
            "description": organization.description,
            "regionScope": organization.regionScope?.rawValue as Any,
            "federalState": organization.federalState?.rawValue as Any,
            "city": organization.city,
            "imageURL": organization.imageURL as Any,
            "contactEmail": organization.contactEmail as Any,
            "website": organization.website as Any,
            "createdAt": Timestamp(date: organization.createdAt),
            "updatedAt": Timestamp(date: organization.updatedAt),
            "moderationStatus": organization.moderationStatus.rawValue,
            "likeCount": organization.likeCount,
            "likeState": organization.likeState.rawValue
        ]
    }

    private func deleteRelatedLikes(organizationID: String) async throws {
        let snapshot = try await likesCollection
            .whereField("organizationId", isEqualTo: organizationID)
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

    private func ensureAuthenticatedUserID() throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppError.permissionDenied
        }
        return uid
    }
}
