import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

struct FirestoreOrganizationRepository: OrganizationRepository {
    private let collection = Firestore.firestore().collection("organizations")
    private let likesCollection = Firestore.firestore().collection("likes")
    private let publicProfilesCollection = Firestore.firestore().collection("publicProfiles")
    private let imageUploadService = ImageUploadService.shared

    func fetchOrganizations() async throws -> [Organization] {
        let snapshot = try await collection
            .whereField("moderationStatus", isEqualTo: ModerationStatus.approved.rawValue)
            .order(by: "createdAt", descending: true)
            .getDocuments()

        let likedOrganizationIDs = try await fetchLikedOrganizationIDs()
        let subscribedOrganizationIDs = try await fetchSubscribedOrganizationIDs()
        let bookmarkedOrganizationIDs = try await fetchBookmarkedOrganizationIDs()

        return try snapshot.documents.map { document in
            try Organization(dto: makeOrganizationDTO(
                from: document,
                likedOrganizationIDs: likedOrganizationIDs,
                subscribedOrganizationIDs: subscribedOrganizationIDs,
                bookmarkedOrganizationIDs: bookmarkedOrganizationIDs
            ))
        }
    }

    func fetchOrganization(id: String) async throws -> Organization {
        let document = try await collection.document(id).getDocument()
        guard document.exists else { throw AppError.notFound }

        let likedOrganizationIDs = try await fetchLikedOrganizationIDs()
        let subscribedOrganizationIDs = try await fetchSubscribedOrganizationIDs()
        let bookmarkedOrganizationIDs = try await fetchBookmarkedOrganizationIDs()
        return try Organization(dto: makeOrganizationDTO(
            from: document,
            likedOrganizationIDs: likedOrganizationIDs,
            subscribedOrganizationIDs: subscribedOrganizationIDs,
            bookmarkedOrganizationIDs: bookmarkedOrganizationIDs
        ))
    }

    func fetchPendingOrganizations() async throws -> [Organization] {
        let snapshot = try await collection
            .whereField("moderationStatus", isEqualTo: ModerationStatus.pendingReview.rawValue)
            .order(by: "createdAt", descending: true)
            .getDocuments()

        let likedOrganizationIDs = try await fetchLikedOrganizationIDs()
        let subscribedOrganizationIDs = try await fetchSubscribedOrganizationIDs()
        let bookmarkedOrganizationIDs = try await fetchBookmarkedOrganizationIDs()

        return try snapshot.documents.map { document in
            try Organization(dto: makeOrganizationDTO(
                from: document,
                likedOrganizationIDs: likedOrganizationIDs,
                subscribedOrganizationIDs: subscribedOrganizationIDs,
                bookmarkedOrganizationIDs: bookmarkedOrganizationIDs
            ))
        }
    }

    func fetchOrganizationRequests(submittedByUserID: String) async throws -> [Organization] {
        let requestStatuses = [
            ModerationStatus.pendingReview.rawValue,
            ModerationStatus.needsRevision.rawValue,
            ModerationStatus.rejected.rawValue
        ]
        let snapshot = try await collection
            .whereField("submittedByUserId", isEqualTo: submittedByUserID)
            .whereField("moderationStatus", in: requestStatuses)
            .order(by: "submittedAt", descending: true)
            .getDocuments()

        let likedOrganizationIDs = try await fetchLikedOrganizationIDs()
        let subscribedOrganizationIDs = try await fetchSubscribedOrganizationIDs()
        let bookmarkedOrganizationIDs = try await fetchBookmarkedOrganizationIDs()

        return try snapshot.documents.map { document in
            try Organization(dto: makeOrganizationDTO(
                from: document,
                likedOrganizationIDs: likedOrganizationIDs,
                subscribedOrganizationIDs: subscribedOrganizationIDs,
                bookmarkedOrganizationIDs: bookmarkedOrganizationIDs
            ))
        }
    }

    func createOrganization(_ organization: Organization) async throws {
        let uid = try ensureAuthenticatedUserID()
        let normalizedOrganization = normalizedOrganizationForWrite(organization, preserveCreatedAt: false)
        let data = makeOrganizationData(from: normalizedOrganization)
        debugLogOrganizationCreatePayload(uid: uid, organization: normalizedOrganization, data: data)
        try await collection.document(normalizedOrganization.id).setData(data)
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
            "moderationStatus": organization.moderationStatus.rawValue,
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
        setUpdateValue(organization.submittedAt.map(Timestamp.init(date:)), forKey: "submittedAt", in: &data)
        setUpdateValue(organization.reviewMessage, forKey: "reviewMessage", in: &data)
        setUpdateValue(organization.rejectionReason, forKey: "rejectionReason", in: &data)

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

        do {
            try await deleteStorageItems(prefix: "organizations/\(id)")
        } catch {}

        try await deleteRelatedLikes(organizationID: id)
        try await deleteRelatedSubscriptions(organizationID: id)
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
                        "likeCount": FieldValue.increment(Int64(1))
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
        } catch {
            throw error
        }
    }

    func subscribeOrganization(id: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppError.permissionDenied
        }

        let organizationReference = collection.document(id)
        let subscriptionReference = likesCollection.document(subscriptionDocumentID(organizationID: id, userID: uid))

        do {
            _ = try await Firestore.firestore().runTransaction { transaction, errorPointer in
                do {
                    let organizationSnapshot = try transaction.getDocument(organizationReference)
                    guard organizationSnapshot.exists else {
                        errorPointer?.pointee = AppError.notFound.asNSError
                        return nil
                    }

                    let subscriptionSnapshot = try transaction.getDocument(subscriptionReference)
                    if subscriptionSnapshot.exists {
                        return nil
                    }

                    transaction.setData([
                        "id": subscriptionReference.documentID,
                        "subscribedOrganizationId": id,
                        "userId": uid,
                        "createdAt": FieldValue.serverTimestamp()
                    ], forDocument: subscriptionReference)
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

    func unsubscribeOrganization(id: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppError.permissionDenied
        }

        let organizationReference = collection.document(id)
        let subscriptionReference = likesCollection.document(subscriptionDocumentID(organizationID: id, userID: uid))

        do {
            _ = try await Firestore.firestore().runTransaction { transaction, errorPointer in
                do {
                    let organizationSnapshot = try transaction.getDocument(organizationReference)
                    guard organizationSnapshot.exists else {
                        errorPointer?.pointee = AppError.notFound.asNSError
                        return nil
                    }

                    let subscriptionSnapshot = try transaction.getDocument(subscriptionReference)
                    guard subscriptionSnapshot.exists else {
                        return nil
                    }

                    let currentSubscriberCount = organizationSnapshot.data()?["subscriberCount"] as? Int ?? 0
                    transaction.deleteDocument(subscriptionReference)
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

    func fetchOrganizationSubscriberPage(
        organizationID: String,
        limit: Int = 50,
        after cursor: OrganizationSubscriberCursor? = nil
    ) async throws -> OrganizationSubscriberPage {
        var query: Query = likesCollection
            .whereField("subscribedOrganizationId", isEqualTo: organizationID)
            .order(by: "createdAt", descending: true)
            .order(by: FieldPath.documentID(), descending: true)
            .limit(to: limit + 1)

        if let cursor {
            query = query.start(after: [Timestamp(date: cursor.followedAt), cursor.documentID])
        }

        let snapshot: QuerySnapshot
        do {
            snapshot = try await query.getDocuments()
        } catch {
            #if DEBUG
            print(
                """
                OrganizationSubscriberQuery failed \
                purpose=organizationTeamAndCommunitySubscribers \
                path=likes \
                filters=subscribedOrganizationId==\(organizationID) \
                orderBy=createdAt(desc),__name__(desc) \
                limit=\(limit + 1) \
                uid=\(Auth.auth().currentUser?.uid ?? "nil")
                """
            )
            #endif
            throw error
        }
        let documents: [QueryDocumentSnapshot] = Array(snapshot.documents.prefix(limit))
        let items: [OrganizationSubscriberReference] = documents.compactMap { document -> OrganizationSubscriberReference? in
            let data = document.data()
            guard let userID = data["userId"] as? String,
                  let followedAt = (data["createdAt"] as? Timestamp)?.dateValue() else {
                return nil
            }
            return OrganizationSubscriberReference(userID: userID, followedAt: followedAt, documentID: document.documentID)
        }
        let nextCursor = documents.last.flatMap { document -> OrganizationSubscriberCursor? in
            guard let followedAt = (document.data()["createdAt"] as? Timestamp)?.dateValue() else { return nil }
            return OrganizationSubscriberCursor(followedAt: followedAt, documentID: document.documentID)
        }

        return OrganizationSubscriberPage(
            items: items,
            nextCursor: snapshot.documents.count > limit ? nextCursor : nil,
            hasMore: snapshot.documents.count > limit
        )
    }

    func fetchPublicUserProfiles(userIDs: [String]) async throws -> [PublicUserProfile] {
        let uniqueIDs = Array(Set(userIDs)).filter { !$0.isEmpty }
        guard !uniqueIDs.isEmpty else { return [] }

        var profiles: [PublicUserProfile] = []
        for chunk in uniqueIDs.chunked(into: 10) {
            let snapshot = try await publicProfilesCollection
                .whereField(FieldPath.documentID(), in: Array(chunk))
                .getDocuments()

            profiles += snapshot.documents.compactMap { document in
                makePublicUserProfile(from: document)
            }
        }

        return profiles
    }

    func fetchOrganizationComments(organizationID: String) async throws -> [Comment] {
        let snapshot = try await collection.document(organizationID)
            .collection("comments")
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "createdAt", descending: false)
            .getDocuments()

        return snapshot.documents.compactMap { makeCommentDTO(from: $0.data()).map(Comment.init(dto:)) }
    }

    func addOrganizationComment(organizationID: String, text: String, author: AppUser) async throws -> Comment {
        guard Auth.auth().currentUser?.uid == author.id else {
            throw AppError.permissionDenied
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw AppError.validationFailed
        }

        let now = Date()
        let commentReference = collection.document(organizationID).collection("comments").document()
        let comment = Comment(
            id: commentReference.documentID,
            parentType: .organization,
            parentId: organizationID,
            authorId: author.id,
            authorName: commentDisplayName(for: author),
            authorPhotoURL: author.avatarURL?.absoluteString,
            text: String(trimmedText.prefix(1000)),
            createdAt: now,
            updatedAt: nil,
            moderationStatus: .approved,
            isDeleted: false
        )

        try await commentReference.setData(makeCommentData(from: comment.dto))
        return comment
    }

    func updateOrganizationComment(organizationID: String, commentID: String, text: String) async throws -> Comment {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppError.permissionDenied
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw AppError.validationFailed
        }

        let commentReference = collection.document(organizationID).collection("comments").document(commentID)
        let snapshot = try await commentReference.getDocument()
        guard let existing = makeCommentDTO(from: snapshot.data() ?? [:]) else {
            throw AppError.notFound
        }
        guard existing.authorId == uid else {
            throw AppError.permissionDenied
        }

        let now = Date()
        let trimmed = String(trimmedText.prefix(1000))
        try await commentReference.updateData([
            "text": trimmed,
            "body": trimmed,
            "updatedAt": Timestamp(date: now)
        ])

        return Comment(
            id: commentID,
            parentType: .organization,
            parentId: organizationID,
            authorId: existing.authorId,
            authorName: existing.authorName,
            authorPhotoURL: existing.authorPhotoURL,
            text: trimmed,
            createdAt: existing.createdAt,
            updatedAt: now,
            moderationStatus: existing.moderationStatus.flatMap(ModerationStatus.init(rawValue:)) ?? .approved,
            isDeleted: existing.isDeleted ?? false
        )
    }

    func deleteOrganizationComment(organizationID: String, commentID: String) async throws {
        guard Auth.auth().currentUser != nil else {
            throw AppError.permissionDenied
        }

        try await collection.document(organizationID)
            .collection("comments")
            .document(commentID)
            .delete()
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

    func approveOrganizationRequest(id: String, reviewerID: String) async throws {
        let reference = collection.document(id)
        let snapshot = try await reference.getDocument()
        let dto = try makeOrganizationDTO(
            from: snapshot,
            likedOrganizationIDs: [],
            subscribedOrganizationIDs: [],
            bookmarkedOrganizationIDs: []
        )
        guard let submittedByUserId = dto.submittedByUserId?.nilIfEmpty else {
            throw AppError.validationFailed
        }

        let now = Date()
        try await reference.updateData([
            "moderationStatus": ModerationStatus.approved.rawValue,
            "ownerId": submittedByUserId,
            "reviewedByUserId": reviewerID,
            "reviewedAt": Timestamp(date: now),
            "reviewMessage": FieldValue.delete(),
            "rejectionReason": FieldValue.delete(),
            "updatedAt": Timestamp(date: now)
        ])
    }

    func requestOrganizationRevision(id: String, message: String, reviewerID: String) async throws {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { throw AppError.validationFailed }

        let now = Date()
        try await collection.document(id).updateData([
            "moderationStatus": ModerationStatus.needsRevision.rawValue,
            "reviewMessage": trimmedMessage,
            "reviewedByUserId": reviewerID,
            "reviewedAt": Timestamp(date: now),
            "updatedAt": Timestamp(date: now)
        ])
    }

    func rejectOrganizationRequest(id: String, reason: String, reviewerID: String) async throws {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else { throw AppError.validationFailed }

        do {
            try await writeOrganizationReviewAudit(
                organizationID: id,
                actionType: "organizationRequestRejected",
                reason: trimmedReason,
                reviewerID: reviewerID
            )
        } catch {}

        try await deleteOrganization(id: id)
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

    private func fetchSubscribedOrganizationIDs() async throws -> Set<String> {
        guard let uid = Auth.auth().currentUser?.uid else {
            return []
        }

        let snapshot = try await likesCollection
            .whereField("userId", isEqualTo: uid)
            .getDocuments()

        return Set(snapshot.documents.compactMap { $0.data()["subscribedOrganizationId"] as? String })
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
        subscribedOrganizationIDs: Set<String>,
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
            submittedByUserId: data["submittedByUserId"] as? String,
            submittedByDisplayName: data["submittedByDisplayName"] as? String,
            submittedAt: (data["submittedAt"] as? Timestamp)?.dateValue(),
            reviewMessage: data["reviewMessage"] as? String,
            reviewedByUserId: data["reviewedByUserId"] as? String,
            reviewedAt: (data["reviewedAt"] as? Timestamp)?.dateValue(),
            rejectionReason: data["rejectionReason"] as? String,
            createdAt: createdAt,
            updatedAt: updatedAt,
            moderationStatus: moderationStatus,
            likeCount: likeCount,
            likeState: likeState,
            isSubscribed: subscribedOrganizationIDs.contains(documentID),
            isBookmarked: isBookmarked
        )
    }

    private func likeDocumentID(organizationID: String, userID: String) -> String {
        "organization_\(organizationID)_\(userID)"
    }

    private func subscriptionDocumentID(organizationID: String, userID: String) -> String {
        "organization_follow_\(organizationID)_\(userID)"
    }

    private func makePublicUserProfile(from document: QueryDocumentSnapshot) -> PublicUserProfile? {
        let data = document.data()
        let displayName = (data["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !displayName.isEmpty else { return nil }

        return PublicUserProfile(
            id: data["id"] as? String ?? document.documentID,
            displayName: displayName,
            avatarURL: (data["avatarURL"] as? String).flatMap(URL.init(string:)),
            city: data["city"] as? String ?? "",
            federalState: (data["federalState"] as? String).flatMap(AustrianFederalState.init(rawValue:)),
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue()
        )
    }

    private func normalizedOrganizationForWrite(_ organization: Organization, preserveCreatedAt: Bool) -> Organization {
        let now = Date()
        let createdAt = preserveCreatedAt ? organization.createdAt : now
        let moderationStatus = organization.moderationStatus

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
            submittedByUserId: organization.submittedByUserId,
            submittedByDisplayName: organization.submittedByDisplayName,
            submittedAt: organization.submittedAt,
            reviewMessage: organization.reviewMessage,
            reviewedByUserId: organization.reviewedByUserId,
            reviewedAt: organization.reviewedAt,
            rejectionReason: organization.rejectionReason,
            createdAt: createdAt,
            updatedAt: now,
            moderationStatus: moderationStatus,
            likeCount: organization.likeCount,
            likeState: organization.likeState,
            isSubscribed: organization.isSubscribed,
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
        setCreateValue(organization.submittedByUserId, forKey: "submittedByUserId", in: &data)
        setCreateValue(organization.submittedByDisplayName, forKey: "submittedByDisplayName", in: &data)
        setCreateValue(organization.submittedAt.map(Timestamp.init(date:)), forKey: "submittedAt", in: &data)
        setCreateValue(organization.reviewMessage, forKey: "reviewMessage", in: &data)
        setCreateValue(organization.reviewedByUserId, forKey: "reviewedByUserId", in: &data)
        setCreateValue(organization.reviewedAt.map(Timestamp.init(date:)), forKey: "reviewedAt", in: &data)
        setCreateValue(organization.rejectionReason, forKey: "rejectionReason", in: &data)

        return data
    }

    private func debugLogOrganizationCreatePayload(uid: String, organization: Organization, data: [String: Any]) {
        #if DEBUG
        let redactedUID = uid.isEmpty ? "none" : "\(uid.prefix(6))..."
        let isPlatformOwnerCreate = organization.moderationStatus == .approved && organization.submittedByUserId == nil
        print(
            """
            [OrganizationCreatePayload] uid=\(redactedUID) platformOwnerCreate=\(isPlatformOwnerCreate) status=\(organization.moderationStatus.rawValue) submittedByMatchesAuth=\(organization.submittedByUserId == uid) ownerIdPresent=\(organization.ownerId != nil) adminCount=\(organization.adminIds.count) moderatorCount=\(organization.moderatorIds.count) counters=subscribers:\(organization.subscriberCount),likes:\(organization.likeCount),events:\(organization.eventsHeldCount),volunteers:\(organization.volunteersCount),helped:\(organization.helpedPeopleCount) keys=\(data.keys.sorted())
            """
        )
        #endif
    }

    private func writeOrganizationReviewAudit(
        organizationID: String,
        actionType: String,
        reason: String,
        reviewerID: String
    ) async throws {
        let auditReference = Firestore.firestore().collection("auditLogs").document()
        try await auditReference.setData([
            "actionType": actionType,
            "targetUserId": reviewerID,
            "performedBy": reviewerID,
            "createdAt": FieldValue.serverTimestamp(),
            "reason": reason,
            "previousValue": [
                "organizationId": organizationID
            ],
            "newValue": [
                "organizationId": organizationID,
                "moderationStatus": ModerationStatus.rejected.rawValue
            ]
        ])
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

    private func deleteRelatedSubscriptions(organizationID: String) async throws {
        let snapshot = try await likesCollection
            .whereField("subscribedOrganizationId", isEqualTo: organizationID)
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

    private func deleteStorageItems(prefix: String) async throws {
        let reference = Storage.storage().reference().child(prefix)
        let result = try await reference.listAll()
        for item in result.items {
            try? await item.delete()
        }
        for folder in result.prefixes {
            try? await deleteStorageItems(prefix: folder.fullPath)
        }
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

    private func ensureAuthenticatedUserID() throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppError.permissionDenied
        }
        return uid
    }

    private func commentDisplayName(for author: AppUser) -> String {
        let display = author.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !display.isEmpty { return display }
        let full = author.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        return full.isEmpty ? "User" : full
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
