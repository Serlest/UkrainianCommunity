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
        let bookmarkedOrganizationIDs = try await fetchBookmarkedOrganizationIDs()

        return try snapshot.documents.map { document in
            try Organization(dto: makeOrganizationDTO(
                from: document,
                likedOrganizationIDs: likedOrganizationIDs,
                bookmarkedOrganizationIDs: bookmarkedOrganizationIDs
            ))
        }
    }

    func fetchOrganization(id: String) async throws -> Organization {
        let document = try await collection.document(id).getDocument()
        guard document.exists else { throw AppError.notFound }

        let likedOrganizationIDs = try await fetchLikedOrganizationIDs()
        let bookmarkedOrganizationIDs = try await fetchBookmarkedOrganizationIDs()
        return try Organization(dto: makeOrganizationDTO(
            from: document,
            likedOrganizationIDs: likedOrganizationIDs,
            bookmarkedOrganizationIDs: bookmarkedOrganizationIDs
        ))
    }

    func fetchPendingOrganizations() async throws -> [Organization] {
        let snapshot = try await collection
            .whereField("moderationStatus", isEqualTo: ModerationStatus.pendingReview.rawValue)
            .order(by: "createdAt", descending: true)
            .getDocuments()

        let likedOrganizationIDs = try await fetchLikedOrganizationIDs()
        let bookmarkedOrganizationIDs = try await fetchBookmarkedOrganizationIDs()

        return try snapshot.documents.map { document in
            try Organization(dto: makeOrganizationDTO(
                from: document,
                likedOrganizationIDs: likedOrganizationIDs,
                bookmarkedOrganizationIDs: bookmarkedOrganizationIDs
            ))
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

        try await collection.document(normalizedOrganization.id).updateData(
            makeSafeOrganizationInfoUpdateData(from: normalizedOrganization)
        )
    }

    private func makeSafeOrganizationInfoUpdateData(from organization: Organization) -> [String: Any] {
        var data: [String: Any] = [
            "name": organization.name,
            "description": organization.description,
            "shortDescription": organization.shortDescription,
            "fullDescription": organization.fullDescription,
            "city": organization.city,
            "languages": organization.languages,
            "socialLinks": organization.socialLinks,
            "updatedAt": Timestamp(date: organization.updatedAt)
        ]

        setUpdateValue(organization.federalState?.rawValue, forKey: "federalState", in: &data)
        setUpdateValue(organization.imageURL, forKey: "imageURL", in: &data)
        setUpdateValue(organization.logoURL, forKey: "logoURL", in: &data)
        setUpdateValue(organization.coverURL, forKey: "coverURL", in: &data)
        setUpdateValue(organization.contactEmail, forKey: "contactEmail", in: &data)
        setUpdateValue(organization.email, forKey: "email", in: &data)
        setUpdateValue(organization.phone, forKey: "phone", in: &data)
        setUpdateValue(organization.website, forKey: "website", in: &data)
        setUpdateValue(organization.address, forKey: "address", in: &data)
        setUpdateValue(organization.latitude, forKey: "latitude", in: &data)
        setUpdateValue(organization.longitude, forKey: "longitude", in: &data)
        setUpdateValue(organization.organizationType, forKey: "organizationType", in: &data)
        setUpdateValue(organization.foundedYear, forKey: "foundedYear", in: &data)
        setUpdateValue(organization.foundedMonth, forKey: "foundedMonth", in: &data)
        setUpdateValue(organization.telegramURL, forKey: "telegramURL", in: &data)
        setUpdateValue(organization.donationURL, forKey: "donationURL", in: &data)
        setUpdateValue(organization.missionStatement, forKey: "missionStatement", in: &data)
        setUpdateValue(organization.contactPerson, forKey: "contactPerson", in: &data)

        return data
    }

    func deleteOrganization(id: String) async throws {
        guard id != Organization.systemOrganizationID else {
            throw AppError.permissionDenied
        }
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

        do {
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
                        "subscriberCount": FieldValue.increment(Int64(1))
                    ], forDocument: organizationReference)
                } catch {
                    errorPointer?.pointee = error as NSError
                }

                return nil
            }
        } catch {
            throw error
        }
    }

    func unlikeOrganization(id: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppError.permissionDenied
        }

        let organizationReference = collection.document(id)
        let likeReference = likesCollection.document(likeDocumentID(organizationID: id, userID: uid))

        do {
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

                    let currentSubscriberCount = organizationSnapshot.data()?["subscriberCount"] as? Int ?? 0
                    transaction.deleteDocument(likeReference)
                    transaction.updateData([
                        "subscriberCount": max(0, currentSubscriberCount - 1)
                    ], forDocument: organizationReference)
                } catch {
                    errorPointer?.pointee = error as NSError
                }

                return nil
            }
        } catch {
            throw error
        }
    }

    func bookmarkOrganization(id: String) async throws {
        let uid = try ensureAuthenticatedUserID()

        try await organizationBookmarkReference(organizationID: id, userID: uid).setData([
            "id": id,
            "organizationId": id,
            "userId": uid,
            "createdAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    func unbookmarkOrganization(id: String) async throws {
        let uid = try ensureAuthenticatedUserID()

        try await organizationBookmarkReference(organizationID: id, userID: uid).delete()
    }

    func isOrganizationBookmarked(id: String) async throws -> Bool {
        let uid = try ensureAuthenticatedUserID()
        let document = try await organizationBookmarkReference(organizationID: id, userID: uid).getDocument()
        return document.exists
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

    func fetchBookmarkedOrganizationIDs() async throws -> Set<String> {
        guard let uid = Auth.auth().currentUser?.uid else {
            return []
        }

        let snapshot = try await Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("organizationBookmarks")
            .getDocuments()

        return Set(snapshot.documents.compactMap { $0.data()["organizationId"] as? String })
    }

    private func makeOrganizationDTO(
        from document: DocumentSnapshot,
        likedOrganizationIDs: Set<String>,
        bookmarkedOrganizationIDs: Set<String>
    ) throws -> OrganizationDTO {
        guard let data = document.data() else {
            throw AppError.notFound
        }

        guard
            let name = data["name"] as? String,
            let description = data["description"] as? String ?? data["shortDescription"] as? String ?? data["fullDescription"] as? String,
            let city = data["city"] as? String,
            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue(),
            let moderationStatus = data["moderationStatus"] as? String
        else {
            throw AppError.notFound
        }

        let documentID = document.documentID
        let imageURL = (data["imageURL"] as? String)?.nilIfEmpty
        let logoURL = (data["logoURL"] as? String)?.nilIfEmpty
        let coverURL = (data["coverURL"] as? String)?.nilIfEmpty
        let subscriberCount = data["subscriberCount"] as? Int ?? 0
        let eventsHeldCount = data["eventsHeldCount"] as? Int ?? 0
        let volunteersCount = data["volunteersCount"] as? Int ?? 0
        let helpedPeopleCount = data["helpedPeopleCount"] as? Int ?? 0
        let likeCount = data["likeCount"] as? Int ?? 0
        let likeState = likedOrganizationIDs.contains(documentID) ? LikeState.liked.rawValue : LikeState.notLiked.rawValue
        let isBookmarked = bookmarkedOrganizationIDs.contains(documentID)

        return OrganizationDTO(
            id: data["id"] as? String ?? documentID,
            name: name,
            description: description,
            shortDescription: data["shortDescription"] as? String,
            fullDescription: data["fullDescription"] as? String,
            regionScope: data["regionScope"] as? String,
            federalState: data["federalState"] as? String,
            city: city,
            imageURL: imageURL,
            logoURL: logoURL,
            coverURL: coverURL,
            contactEmail: data["contactEmail"] as? String,
            email: data["email"] as? String,
            phone: data["phone"] as? String,
            website: data["website"] as? String,
            address: data["address"] as? String,
            latitude: data["latitude"] as? Double,
            longitude: data["longitude"] as? Double,
            organizationType: data["organizationType"] as? String,
            foundedYear: data["foundedYear"] as? Int,
            foundedMonth: data["foundedMonth"] as? Int,
            languages: data["languages"] as? [String],
            socialLinks: data["socialLinks"] as? [String: String],
            telegramURL: data["telegramURL"] as? String,
            donationURL: data["donationURL"] as? String,
            missionStatement: data["missionStatement"] as? String,
            contactPerson: data["contactPerson"] as? String,
            subscriberCount: subscriberCount,
            eventsHeldCount: eventsHeldCount,
            volunteersCount: volunteersCount,
            helpedPeopleCount: helpedPeopleCount,
            ownerId: data["ownerId"] as? String,
            adminIds: data["adminIds"] as? [String] ?? [],
            moderatorIds: data["moderatorIds"] as? [String] ?? [],
            isSystemManaged: data["isSystemManaged"] as? Bool,
            sourceType: data["sourceType"] as? String,
            pinnedNewsId: data["pinnedNewsId"] as? String,
            pinnedEventId: data["pinnedEventId"] as? String,
            createdAt: createdAt,
            updatedAt: updatedAt,
            moderationStatus: moderationStatus,
            likeCount: likeCount,
            likeState: likeState,
            isBookmarked: isBookmarked
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
            shortDescription: organization.shortDescription,
            fullDescription: organization.fullDescription,
            regionScope: organization.regionScope,
            federalState: organization.federalState,
            city: organization.city,
            imageURL: organization.imageURL,
            logoURL: organization.logoURL,
            coverURL: organization.coverURL,
            contactEmail: organization.contactEmail,
            email: organization.email,
            phone: organization.phone,
            website: organization.website,
            address: organization.address,
            latitude: organization.latitude,
            longitude: organization.longitude,
            organizationType: organization.organizationType,
            foundedYear: organization.foundedYear,
            foundedMonth: organization.foundedMonth,
            languages: organization.languages,
            socialLinks: organization.socialLinks,
            telegramURL: organization.telegramURL,
            donationURL: organization.donationURL,
            missionStatement: organization.missionStatement,
            contactPerson: organization.contactPerson,
            subscriberCount: organization.subscriberCount,
            eventsHeldCount: organization.eventsHeldCount,
            volunteersCount: organization.volunteersCount,
            helpedPeopleCount: organization.helpedPeopleCount,
            ownerId: organization.ownerId,
            adminIds: organization.adminIds,
            moderatorIds: organization.moderatorIds,
            isSystemManaged: organization.isSystemManaged,
            sourceType: organization.sourceType,
            pinnedNewsId: organization.pinnedNewsId,
            pinnedEventId: organization.pinnedEventId,
            createdAt: createdAt,
            updatedAt: now,
            moderationStatus: moderationStatus,
            likeCount: organization.likeCount,
            likeState: organization.likeState,
            isBookmarked: organization.isBookmarked
        )
    }

    private func makeOrganizationData(from organization: Organization) -> [String: Any] {
        var data: [String: Any] = [
            "id": organization.id,
            "name": organization.name,
            "description": organization.description,
            "shortDescription": organization.shortDescription,
            "fullDescription": organization.fullDescription,
            "city": organization.city,
            "languages": organization.languages,
            "socialLinks": organization.socialLinks,
            "subscriberCount": organization.subscriberCount,
            "eventsHeldCount": organization.eventsHeldCount,
            "volunteersCount": organization.volunteersCount,
            "helpedPeopleCount": organization.helpedPeopleCount,
            "adminIds": organization.adminIds,
            "moderatorIds": organization.moderatorIds,
            "createdAt": Timestamp(date: organization.createdAt),
            "updatedAt": Timestamp(date: organization.updatedAt),
            "moderationStatus": organization.moderationStatus.rawValue,
            "likeCount": organization.likeCount,
            "likeState": organization.likeState.rawValue
        ]

        setCreateValue(organization.regionScope?.rawValue, forKey: "regionScope", in: &data)
        setCreateValue(organization.federalState?.rawValue, forKey: "federalState", in: &data)
        setCreateValue(organization.imageURL, forKey: "imageURL", in: &data)
        setCreateValue(organization.logoURL, forKey: "logoURL", in: &data)
        setCreateValue(organization.coverURL, forKey: "coverURL", in: &data)
        setCreateValue(organization.contactEmail, forKey: "contactEmail", in: &data)
        setCreateValue(organization.email, forKey: "email", in: &data)
        setCreateValue(organization.phone, forKey: "phone", in: &data)
        setCreateValue(organization.website, forKey: "website", in: &data)
        setCreateValue(organization.address, forKey: "address", in: &data)
        setCreateValue(organization.latitude, forKey: "latitude", in: &data)
        setCreateValue(organization.longitude, forKey: "longitude", in: &data)
        setCreateValue(organization.organizationType, forKey: "organizationType", in: &data)
        setCreateValue(organization.foundedYear, forKey: "foundedYear", in: &data)
        setCreateValue(organization.foundedMonth, forKey: "foundedMonth", in: &data)
        setCreateValue(organization.telegramURL, forKey: "telegramURL", in: &data)
        setCreateValue(organization.donationURL, forKey: "donationURL", in: &data)
        setCreateValue(organization.missionStatement, forKey: "missionStatement", in: &data)
        setCreateValue(organization.contactPerson, forKey: "contactPerson", in: &data)
        setCreateValue(organization.ownerId, forKey: "ownerId", in: &data)
        setCreateValue(organization.isSystemManaged, forKey: "isSystemManaged", in: &data)
        setCreateValue(organization.sourceType?.rawValue, forKey: "sourceType", in: &data)
        setCreateValue(organization.pinnedNewsId, forKey: "pinnedNewsId", in: &data)
        setCreateValue(organization.pinnedEventId, forKey: "pinnedEventId", in: &data)

        return data
    }

    private func setCreateValue(_ value: Any?, forKey key: String, in data: inout [String: Any]) {
        guard let value else { return }
        data[key] = value
    }

    private func setUpdateValue(_ value: Any?, forKey key: String, in data: inout [String: Any]) {
        data[key] = value ?? FieldValue.delete()
    }

    private func organizationBookmarkReference(organizationID: String, userID: String) -> DocumentReference {
        Firestore.firestore()
            .collection("users")
            .document(userID)
            .collection("organizationBookmarks")
            .document(organizationID)
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

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
