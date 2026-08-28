import Foundation
import FirebaseAuth
import FirebaseFirestore

struct FirestoreOrganizationRepository: OrganizationRepository {
    private let collection = Firestore.firestore().collection("organizations")
    private let likesCollection = Firestore.firestore().collection("likes")
    private let publicProfilesCollection = Firestore.firestore().collection("publicProfiles")
    private let imageUploadService = ImageUploadService.shared
    private let sessionDataCache: SessionDataCache

    init(sessionDataCache: SessionDataCache = .shared) {
        self.sessionDataCache = sessionDataCache
    }

    func fetchOrganizations() async throws -> [Organization] {
        try await fetchOrganizationsPage(limit: 30, after: nil).items
    }

    func fetchAuthoringOrganizations(user: AppUser) async throws -> [Organization] {
        guard PermissionService.isUsableAccount(user: user), Auth.auth().currentUser?.uid == user.id else {
            throw AppError.permissionDenied
        }
        let approved = collection.whereField("moderationStatus", isEqualTo: ModerationStatus.approved.rawValue)
        let documents: [QueryDocumentSnapshot]
        if PermissionService.isAppOwner(user: user) {
            documents = try await approved.getDocuments(source: .server).documents
        } else {
            // Query canonical organization roles, not the first catalog page or
            // potentially stale user membership mirrors. Existing Rules apply.
            async let owned = approved.whereField("ownerId", isEqualTo: user.id).getDocuments(source: .server)
            async let administered = approved.whereField("adminIds", arrayContains: user.id).getDocuments(source: .server)
            async let moderated = approved.whereField("moderatorIds", arrayContains: user.id).getDocuments(source: .server)
            let snapshots = try await [owned, administered, moderated]
            var seen = Set<String>()
            documents = snapshots.flatMap(\.documents).filter { seen.insert($0.documentID).inserted }
        }
        let organizations = try documents.map {
            try Organization(dto: makeOrganizationDTO(from: $0, likedOrganizationIDs: [], subscribedOrganizationIDs: [], bookmarkedOrganizationIDs: []))
        }
        return PermissionService.manageableOrganizations(from: organizations, user: user)
    }

    func fetchBookmarkedOrganizations() async throws -> [Organization] {
        let bookmarkedIDs = try await fetchBookmarkedOrganizationIDs()
        guard !bookmarkedIDs.isEmpty else { return [] }
        let bookmarkedIDList = Array(bookmarkedIDs)
        async let liked = fetchLikedOrganizationIDs(for: bookmarkedIDList)
        async let subscribed = fetchSubscribedOrganizationIDs(for: bookmarkedIDList)
        let (likedIDs, subscribedIDs) = try await (liked, subscribed)
        var organizations: [Organization] = []

        for chunk in bookmarkedIDList.chunked(into: 10) {
            let snapshot = try await collection
                .whereField(FieldPath.documentID(), in: Array(chunk))
                .whereField("moderationStatus", isEqualTo: ModerationStatus.approved.rawValue)
                .getDocuments()
            let resolved = try snapshot.documents.compactMap { document -> Organization? in
                let organization = try Organization(dto: makeOrganizationDTO(
                    from: document,
                    likedOrganizationIDs: likedIDs,
                    subscribedOrganizationIDs: subscribedIDs,
                    bookmarkedOrganizationIDs: bookmarkedIDs
                ))
                return organization.moderationStatus == .approved ? organization : nil
            }
            organizations.append(contentsOf: resolved)
        }

        return organizations.sorted {
            let result = LocalizationStore.compareForSorting($0.localizedName, $1.localizedName)
            return result == .orderedSame ? $0.id < $1.id : result == .orderedAscending
        }
    }

    func fetchSubscribedOrganizations() async throws -> [Organization] {
        let subscribedIDs = try await fetchSubscribedOrganizationIDs()
        guard !subscribedIDs.isEmpty else { return [] }
        let subscribedIDList = Array(subscribedIDs)
        async let liked = fetchLikedOrganizationIDs(for: subscribedIDList)
        async let bookmarked = fetchBookmarkedOrganizationIDs(for: subscribedIDList)
        let (likedIDs, bookmarkedIDs) = try await (liked, bookmarked)
        var organizations: [Organization] = []

        for chunk in subscribedIDList.chunked(into: 10) {
            let snapshot = try await collection
                .whereField(FieldPath.documentID(), in: Array(chunk))
                .whereField("moderationStatus", isEqualTo: ModerationStatus.approved.rawValue)
                .getDocuments()
            let resolved = try snapshot.documents.map { document in
                try Organization(dto: makeOrganizationDTO(
                    from: document,
                    likedOrganizationIDs: likedIDs,
                    subscribedOrganizationIDs: subscribedIDs,
                    bookmarkedOrganizationIDs: bookmarkedIDs
                ))
            }
            organizations.append(contentsOf: resolved)
        }

        return organizations.sorted {
            let result = LocalizationStore.compareForSorting($0.localizedName, $1.localizedName)
            return result == .orderedSame ? $0.id < $1.id : result == .orderedAscending
        }
    }

    func fetchOrganizationsPage(limit: Int, after cursor: OrganizationPageCursor?) async throws -> OrganizationPage {
        var query: Query = collection
            .whereField("moderationStatus", isEqualTo: ModerationStatus.approved.rawValue)
            .order(by: "createdAt", descending: true)
            .order(by: FieldPath.documentID(), descending: true)
            .limit(to: max(1, limit) + 1)

        if let cursor {
            query = query.start(after: [Timestamp(date: cursor.createdAt), cursor.documentID])
        }

        let snapshot = try await query.getDocuments()
        let documents = Array(snapshot.documents.prefix(max(1, limit)))
        let documentIDs = documents.map(\.documentID)
        async let liked = fetchLikedOrganizationIDs(for: documentIDs)
        async let subscribed = fetchSubscribedOrganizationIDs(for: documentIDs)
        async let bookmarked = fetchBookmarkedOrganizationIDs(for: documentIDs)
        let (likedOrganizationIDs, subscribedOrganizationIDs, bookmarkedOrganizationIDs) = try await (liked, subscribed, bookmarked)
        let items = try documents.map { document in
            try Organization(dto: makeOrganizationDTO(
                from: document,
                likedOrganizationIDs: likedOrganizationIDs,
                subscribedOrganizationIDs: subscribedOrganizationIDs,
                bookmarkedOrganizationIDs: bookmarkedOrganizationIDs
            ))
        }

        return OrganizationPage(
            items: items,
            nextCursor: documents.last.flatMap(makeOrganizationPageCursor),
            hasMore: snapshot.documents.count > max(1, limit)
        )
    }

    private func makeOrganizationPageCursor(from document: QueryDocumentSnapshot) -> OrganizationPageCursor? {
        guard let createdAt = (document.data()["createdAt"] as? Timestamp)?.dateValue() else {
            return nil
        }
        return OrganizationPageCursor(createdAt: createdAt, documentID: document.documentID)
    }

    func fetchOrganization(id: String) async throws -> Organization {
        let document = try await collection.document(id).getDocument()
        guard document.exists else { throw AppError.notFound }

        var likedOrganizationIDs = Set<String>()
        var subscribedOrganizationIDs = Set<String>()
        var bookmarkedOrganizationIDs = Set<String>()
        if let uid = Auth.auth().currentUser?.uid {
            async let like = likesCollection.document(likeDocumentID(organizationID: id, userID: uid)).getDocument()
            async let subscription = likesCollection.document(subscriptionDocumentID(organizationID: id, userID: uid)).getDocument()
            async let bookmark = organizationBookmarkReference(organizationID: id, userID: uid).getDocument()
            let (likeDocument, subscriptionDocument, bookmarkDocument) = try await (like, subscription, bookmark)
            if likeDocument.exists { likedOrganizationIDs.insert(id) }
            if subscriptionDocument.exists { subscribedOrganizationIDs.insert(id) }
            if bookmarkDocument.exists { bookmarkedOrganizationIDs.insert(id) }
        }
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
            .limit(to: 100)
            .getDocuments()

        let documentIDs = snapshot.documents.map(\.documentID)
        async let liked = fetchLikedOrganizationIDs(for: documentIDs)
        async let subscribed = fetchSubscribedOrganizationIDs(for: documentIDs)
        async let bookmarked = fetchBookmarkedOrganizationIDs(for: documentIDs)
        let (likedOrganizationIDs, subscribedOrganizationIDs, bookmarkedOrganizationIDs) = try await (liked, subscribed, bookmarked)

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
            .limit(to: 100)
            .getDocuments()

        let documentIDs = snapshot.documents.map(\.documentID)
        async let liked = fetchLikedOrganizationIDs(for: documentIDs)
        async let subscribed = fetchSubscribedOrganizationIDs(for: documentIDs)
        async let bookmarked = fetchBookmarkedOrganizationIDs(for: documentIDs)
        let (likedOrganizationIDs, subscribedOrganizationIDs, bookmarkedOrganizationIDs) = try await (liked, subscribed, bookmarked)

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
        do {
            try await collection.document(normalizedOrganization.id).setData(data)
        } catch {
            await SystemTechnicalErrorLoggingService.shared.logFailure(
                error,
                context: SystemTechnicalErrorContext(
                    moduleName: "Organizations",
                    operationName: "createOrganization",
                    targetType: .organization,
                    targetId: normalizedOrganization.id,
                    targetTitle: normalizedOrganization.name,
                    organizationId: normalizedOrganization.id,
                    organizationName: normalizedOrganization.name
                )
            )
            throw error
        }

        await SystemAuditLoggingService.shared.logSuccess(
            SystemAuditLogContext(
                moduleName: "Organizations",
                operationName: "createOrganization",
                eventType: .contentCreated,
                targetType: .organization,
                targetId: normalizedOrganization.id,
                targetTitle: normalizedOrganization.name,
                organizationId: normalizedOrganization.id,
                organizationName: normalizedOrganization.name,
                summary: "Organization created"
            )
        )
    }

    func updateOrganization(_ organization: Organization) async throws {
        _ = try ensureAuthenticatedUserID()
        let normalizedOrganization = normalizedOrganizationForWrite(organization, preserveCreatedAt: true)

        do {
            try await collection.document(normalizedOrganization.id).updateData(
                makeSafeOrganizationInfoUpdateData(from: normalizedOrganization)
            )
        } catch {
            await SystemTechnicalErrorLoggingService.shared.logFailure(
                error,
                context: SystemTechnicalErrorContext(
                    moduleName: "Organizations",
                    operationName: "updateOrganization",
                    targetType: .organization,
                    targetId: normalizedOrganization.id,
                    targetTitle: normalizedOrganization.name,
                    organizationId: normalizedOrganization.id,
                    organizationName: normalizedOrganization.name
                )
            )
            throw error
        }

        await SystemAuditLoggingService.shared.logSuccess(
            SystemAuditLogContext(
                moduleName: "Organizations",
                operationName: "updateOrganization",
                eventType: .contentUpdated,
                targetType: .organization,
                targetId: normalizedOrganization.id,
                targetTitle: normalizedOrganization.name,
                organizationId: normalizedOrganization.id,
                organizationName: normalizedOrganization.name,
                summary: "Organization updated"
            )
        )
    }

    private func makeSafeOrganizationInfoUpdateData(from organization: Organization) -> [String: Any] {
        var data: [String: Any] = [
            "localizations": FirestoreContentPublishingCoding.organizationLocalizationsData(organization.localizations),
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

        setUpdateValue(organization.regionScope?.rawValue, forKey: "regionScope", in: &data)
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
        setUpdateValue(makeDirectoryProfileData(organization.directoryProfile), forKey: "directoryProfile", in: &data)
        setUpdateValue(organization.foundedYear, forKey: "foundedYear", in: &data)
        setUpdateValue(organization.foundedMonth, forKey: "foundedMonth", in: &data)
        setUpdateValue(organization.telegramURL, forKey: "telegramURL", in: &data)
        setUpdateValue(organization.donationURL, forKey: "donationURL", in: &data)
        setUpdateValue(organization.facebookURL, forKey: "facebookURL", in: &data)
        setUpdateValue(organization.instagramURL, forKey: "instagramURL", in: &data)
        setUpdateValue(organization.whatsappURL, forKey: "whatsappURL", in: &data)
        setUpdateValue(organization.youtubeURL, forKey: "youtubeURL", in: &data)
        setUpdateValue(organization.linkedinURL, forKey: "linkedinURL", in: &data)
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
        do {
            _ = try await CloudFunctionsClient.shared.deleteOrganization(id: id)
        } catch {
            await SystemTechnicalErrorLoggingService.shared.logFailure(
                error,
                context: SystemTechnicalErrorContext(
                    moduleName: "Organizations",
                    operationName: "deleteOrganization",
                    targetType: .organization,
                    targetId: id,
                    organizationId: id
                )
            )
            throw error
        }

        await SystemAuditLoggingService.shared.logSuccess(
            SystemAuditLogContext(
                moduleName: "Organizations",
                operationName: "deleteOrganization",
                eventType: .contentDeleted,
                targetType: .organization,
                targetId: id,
                organizationId: id,
                summary: "Organization deleted"
            )
        )
    }

    func uploadOrganizationImage(data: Data, organizationID: String) async throws -> URL {
        _ = try ensureAuthenticatedUserID()
        do {
            return try await imageUploadService.uploadOrganizationLogoImage(data: data, organizationID: organizationID)
        } catch {
            await SystemTechnicalErrorLoggingService.shared.logFailure(
                error,
                context: SystemTechnicalErrorContext(
                    moduleName: "Organizations",
                    operationName: "uploadOrganizationImage",
                    targetType: .organization,
                    targetId: organizationID,
                    organizationId: organizationID
                )
            )
            throw error
        }
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
                } catch {
                    errorPointer?.pointee = error as NSError
                }

                return nil
            }
        } catch {
            throw error
        }
        await sessionDataCache.updateLikedOrganizationID(id, isLiked: true, for: uid)
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

                    transaction.deleteDocument(likeReference)
                } catch {
                    errorPointer?.pointee = error as NSError
                }

                return nil
            }
        } catch {
            throw error
        }
        await sessionDataCache.updateLikedOrganizationID(id, isLiked: false, for: uid)
    }

    func subscribeOrganization(id: String, actionCapture: AnalyticsActionCapture?) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppError.permissionDenied
        }

        let organizationReference = collection.document(id)
        let subscriptionReference = likesCollection.document(subscriptionDocumentID(organizationID: id, userID: uid))
        let proofReference = actionCapture.map {
            Firestore.firestore().collection("analyticsActionProofs").document($0.proofID)
        }

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
                    if let actionCapture,
                       actionCapture.eventName == "organization_follow",
                       actionCapture.contentID == id,
                       let proofReference {
                        transaction.setData(actionCapture.firestoreData, forDocument: proofReference)
                    }
                } catch {
                    errorPointer?.pointee = error as NSError
                }

                return nil
            }
        } catch {
            throw error
        }
        await sessionDataCache.updateSubscribedOrganizationID(id, isSubscribed: true, for: uid)
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

                    transaction.deleteDocument(subscriptionReference)
                } catch {
                    errorPointer?.pointee = error as NSError
                }

                return nil
            }
        } catch {
            throw error
        }
        await sessionDataCache.updateSubscribedOrganizationID(id, isSubscribed: false, for: uid)
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
        var seenIDs = Set<String>()
        let uniqueIDs = userIDs.filter { !$0.isEmpty && seenIDs.insert($0).inserted }
        guard !uniqueIDs.isEmpty else { return [] }

        guard let uid = Auth.auth().currentUser?.uid else {
            let profiles = try await fetchPublicProfilesFromFirestore(userIDs: uniqueIDs)
            return uniqueIDs.compactMap { profiles[$0] }
        }

        let cached = await sessionDataCache.cachedPublicProfiles(for: uniqueIDs, userID: uid)
        let fetchedProfiles = try await fetchPublicProfilesFromFirestore(userIDs: cached.missingIDs)
        await sessionDataCache.storePublicProfiles(Array(fetchedProfiles.values), for: uid)
        let profiles = cached.profiles.merging(fetchedProfiles) { _, fetched in fetched }
        return uniqueIDs.compactMap { profiles[$0] }
    }

    private func fetchPublicProfilesFromFirestore(userIDs: [String]) async throws -> [String: PublicUserProfile] {
        var profiles: [String: PublicUserProfile] = [:]
        for chunk in userIDs.chunked(into: 10) {
            let snapshot = try await publicProfilesCollection
                .whereField(FieldPath.documentID(), in: Array(chunk))
                .getDocuments()

            for document in snapshot.documents {
                guard let profile = makePublicUserProfile(from: document) else { continue }
                profiles[profile.id] = profile
            }
        }

        return profiles
    }

    func fetchOrganizationComments(organizationID: String) async throws -> [Comment] {
        let snapshot = try await collection.document(organizationID)
            .collection("comments")
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
            .getDocuments()

        return snapshot.documents.reversed().compactMap { makeCommentDTO(from: $0.data()).map(Comment.init(dto:)) }
    }

    func addOrganizationComment(organizationID: String, text: String, author: AppUser) async throws -> Comment {
        guard Auth.auth().currentUser?.uid == author.id else {
            throw AppError.permissionDenied
        }

        return try await CloudCommentMutationService.shared.save(
            parentType: .organization,
            parentId: organizationID,
            text: text
        )
    }

    func updateOrganizationComment(organizationID: String, commentID: String, text: String) async throws -> Comment {
        throw AppError.permissionDenied
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

    func bookmarkOrganization(id: String, actionCapture: AnalyticsActionCapture?) async throws {
        let uid = try ensureAuthenticatedUserID()

        let database = Firestore.firestore()
        let batch = database.batch()
        batch.setData([
            "id": id,
            "organizationId": id,
            "userId": uid,
            "createdAt": FieldValue.serverTimestamp()
        ], forDocument: organizationBookmarkReference(organizationID: id, userID: uid))
        if let actionCapture,
           actionCapture.eventName == "organization_bookmark",
           actionCapture.contentID == id {
            batch.setData(
                actionCapture.firestoreData,
                forDocument: database.collection("analyticsActionProofs").document(actionCapture.proofID)
            )
        }
        try await batch.commit()
        await sessionDataCache.updateBookmarkedOrganizationID(id, isBookmarked: true, for: uid)
    }

    func unbookmarkOrganization(id: String) async throws {
        let uid = try ensureAuthenticatedUserID()

        try await organizationBookmarkReference(organizationID: id, userID: uid).delete()
        await sessionDataCache.updateBookmarkedOrganizationID(id, isBookmarked: false, for: uid)
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
        _ = try await CloudFunctionsClient.shared.approveOrganization(
            OrganizationReviewFunctionRequest(organizationId: id)
        )

        await SystemModerationLoggingService.shared.logSuccess(
            SystemModerationLogContext(
                operationName: "approveOrganizationRequest",
                eventType: .organizationRequestApproved,
                targetType: .organizationRequest,
                targetId: id,
                organizationId: id,
                outcome: .approved,
                summary: "Запит організації схвалено",
                metadata: ["newStatus": ModerationStatus.approved.rawValue]
            )
        )
    }

    func requestOrganizationRevision(id: String, message: String, reviewerID: String) async throws {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { throw AppError.validationFailed }

        _ = try await CloudFunctionsClient.shared.requestOrganizationRevision(
            OrganizationReviewFunctionRequest(organizationId: id, message: trimmedMessage)
        )
    }

    func rejectOrganizationRequest(id: String, reason: String, reviewerID: String) async throws {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else { throw AppError.validationFailed }

        _ = try await CloudFunctionsClient.shared.rejectOrganization(
            OrganizationReviewFunctionRequest(organizationId: id, reason: trimmedReason)
        )

        await SystemModerationLoggingService.shared.logSuccess(
            SystemModerationLogContext(
                operationName: "rejectOrganizationRequest",
                eventType: .organizationRequestRejected,
                targetType: .organizationRequest,
                targetId: id,
                organizationId: id,
                outcome: .rejected,
                summary: "Запит організації відхилено",
                metadata: ["newStatus": ModerationStatus.rejected.rawValue]
            )
        )
    }

    private func fetchLikedOrganizationIDs(for organizationIDs: [String]) async throws -> Set<String> {
        guard let uid = Auth.auth().currentUser?.uid, !organizationIDs.isEmpty else { return [] }
        var result = Set<String>()
        for chunk in organizationIDs.chunked(into: 30) {
            let documentIDs = chunk.map { likeDocumentID(organizationID: $0, userID: uid) }
            let snapshot = try await likesCollection
                .whereField(FieldPath.documentID(), in: documentIDs)
                .getDocuments()
            result.formUnion(snapshot.documents.compactMap { $0.data()["organizationId"] as? String })
        }
        return result
    }

    private func fetchSubscribedOrganizationIDs() async throws -> Set<String> {
        guard let uid = Auth.auth().currentUser?.uid else {
            return []
        }
        if let cached = await sessionDataCache.cachedSubscribedOrganizationIDs(for: uid) {
            return cached
        }

        let snapshot = try await likesCollection
            .whereField("userId", isEqualTo: uid)
            .getDocuments()
        let ids = Set(snapshot.documents.compactMap { $0.data()["subscribedOrganizationId"] as? String })
        await sessionDataCache.storeSubscribedOrganizationIDs(ids, for: uid)
        return ids
    }

    private func fetchSubscribedOrganizationIDs(for organizationIDs: [String]) async throws -> Set<String> {
        guard let uid = Auth.auth().currentUser?.uid, !organizationIDs.isEmpty else { return [] }
        var result = Set<String>()
        for chunk in organizationIDs.chunked(into: 30) {
            let documentIDs = chunk.map { subscriptionDocumentID(organizationID: $0, userID: uid) }
            let snapshot = try await likesCollection
                .whereField(FieldPath.documentID(), in: documentIDs)
                .getDocuments()
            result.formUnion(snapshot.documents.compactMap { $0.data()["subscribedOrganizationId"] as? String })
        }
        return result
    }

    func fetchBookmarkedOrganizationIDs() async throws -> Set<String> {
        guard let uid = Auth.auth().currentUser?.uid else {
            return []
        }
        if let cached = await sessionDataCache.cachedBookmarkedOrganizationIDs(for: uid) {
            return cached
        }

        let snapshot = try await Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("organizationBookmarks")
            .getDocuments()

        let ids = Set(snapshot.documents.compactMap { $0.data()["organizationId"] as? String })
        await sessionDataCache.storeBookmarkedOrganizationIDs(ids, for: uid)
        return ids
    }

    private func fetchBookmarkedOrganizationIDs(for organizationIDs: [String]) async throws -> Set<String> {
        guard let uid = Auth.auth().currentUser?.uid, !organizationIDs.isEmpty else { return [] }
        let collection = Firestore.firestore().collection("users").document(uid).collection("organizationBookmarks")
        var result = Set<String>()
        for chunk in organizationIDs.chunked(into: 30) {
            let snapshot = try await collection
                .whereField(FieldPath.documentID(), in: Array(chunk))
                .getDocuments()
            result.formUnion(snapshot.documents.map(\.documentID))
        }
        return result
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
            localizations: FirestoreContentPublishingCoding.organizationLocalizations(from: data["localizations"]),
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
            directoryProfile: makeDirectoryProfile(from: data["directoryProfile"]),
            foundedYear: data["foundedYear"] as? Int,
            foundedMonth: data["foundedMonth"] as? Int,
            languages: data["languages"] as? [String],
            socialLinks: data["socialLinks"] as? [String: String],
            telegramURL: data["telegramURL"] as? String,
            donationURL: data["donationURL"] as? String,
            facebookURL: data["facebookURL"] as? String,
            instagramURL: data["instagramURL"] as? String,
            whatsappURL: data["whatsappURL"] as? String,
            youtubeURL: data["youtubeURL"] as? String,
            linkedinURL: data["linkedinURL"] as? String,
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
            localizations: organization.localizations,
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
            directoryProfile: organization.directoryProfile,
            foundedYear: organization.foundedYear,
            foundedMonth: organization.foundedMonth,
            languages: organization.languages,
            socialLinks: organization.socialLinks,
            telegramURL: organization.telegramURL,
            donationURL: organization.donationURL,
            facebookURL: organization.facebookURL,
            instagramURL: organization.instagramURL,
            whatsappURL: organization.whatsappURL,
            youtubeURL: organization.youtubeURL,
            linkedinURL: organization.linkedinURL,
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
            "localizations": FirestoreContentPublishingCoding.organizationLocalizationsData(organization.localizations),
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
        setCreateValue(makeDirectoryProfileData(organization.directoryProfile), forKey: "directoryProfile", in: &data)
        setCreateValue(organization.foundedYear, forKey: "foundedYear", in: &data)
        setCreateValue(organization.foundedMonth, forKey: "foundedMonth", in: &data)
        setCreateValue(organization.telegramURL, forKey: "telegramURL", in: &data)
        setCreateValue(organization.donationURL, forKey: "donationURL", in: &data)
        setCreateValue(organization.facebookURL, forKey: "facebookURL", in: &data)
        setCreateValue(organization.instagramURL, forKey: "instagramURL", in: &data)
        setCreateValue(organization.whatsappURL, forKey: "whatsappURL", in: &data)
        setCreateValue(organization.youtubeURL, forKey: "youtubeURL", in: &data)
        setCreateValue(organization.linkedinURL, forKey: "linkedinURL", in: &data)
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

    private func setCreateValue(_ value: Any?, forKey key: String, in data: inout [String: Any]) {
        guard let value else { return }
        data[key] = value
    }

    private func setUpdateValue(_ value: Any?, forKey key: String, in data: inout [String: Any]) {
        data[key] = value ?? FieldValue.delete()
    }

    private func makeDirectoryProfile(from value: Any?) -> OrganizationDirectoryProfile? {
        guard let data = value as? [String: Any],
              let rawKind = data["profileKind"] as? String,
              let profileKind = OrganizationProfileKind(rawValue: rawKind) else {
            return nil
        }

        let regularHours = data["regularHours"] as? [String: String] ?? [:]
        let serviceModes = (data["serviceModes"] as? [String] ?? [])
            .compactMap(OrganizationServiceMode.init(rawValue:))
        return OrganizationDirectoryProfile(
            profileKind: profileKind,
            secondaryCategories: data["secondaryCategories"] as? [String] ?? [],
            serviceModes: serviceModes,
            serviceArea: data["serviceArea"] as? String,
            regularHours: regularHours,
            specialHoursNote: data["specialHoursNote"] as? String,
            services: data["services"] as? [String] ?? [],
            orderURL: data["orderURL"] as? String,
            bookingURL: data["bookingURL"] as? String,
            currentOfferTitle: data["currentOfferTitle"] as? String,
            currentOfferDetails: data["currentOfferDetails"] as? String,
            currentOfferURL: data["currentOfferURL"] as? String,
            currentOfferValidUntil: (data["currentOfferValidUntil"] as? Timestamp)?.dateValue()
        )
    }

    private func makeDirectoryProfileData(_ profile: OrganizationDirectoryProfile?) -> [String: Any]? {
        guard let profile else { return nil }
        var data: [String: Any] = [
            "profileKind": profile.profileKind.rawValue,
            "secondaryCategories": profile.secondaryCategories,
            "serviceModes": profile.serviceModes.map(\.rawValue),
            "regularHours": profile.regularHours,
            "services": profile.services
        ]
        setCreateValue(profile.serviceArea, forKey: "serviceArea", in: &data)
        setCreateValue(profile.specialHoursNote, forKey: "specialHoursNote", in: &data)
        setCreateValue(profile.orderURL, forKey: "orderURL", in: &data)
        setCreateValue(profile.bookingURL, forKey: "bookingURL", in: &data)
        setCreateValue(profile.currentOfferTitle, forKey: "currentOfferTitle", in: &data)
        setCreateValue(profile.currentOfferDetails, forKey: "currentOfferDetails", in: &data)
        setCreateValue(profile.currentOfferURL, forKey: "currentOfferURL", in: &data)
        setCreateValue(profile.currentOfferValidUntil.map(Timestamp.init(date:)), forKey: "currentOfferValidUntil", in: &data)
        return data
    }

    private func organizationBookmarkReference(organizationID: String, userID: String) -> DocumentReference {
        Firestore.firestore()
            .collection("users")
            .document(userID)
            .collection("organizationBookmarks")
            .document(organizationID)
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

extension FirestoreOrganizationRepository: OrganizationRealtimeRepository {
    func listenOrganizationComments(
        organizationID: String,
        onChange: @escaping @MainActor ([Comment]) -> Void,
        onError: @escaping @MainActor (AppError) -> Void
    ) -> AppRealtimeListener {
        let registration = collection.document(organizationID)
            .collection("comments")
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
            .addSnapshotListener { snapshot, error in
                if let error {
                    Self.logListenerFailure(
                        error,
                        listenerName: "organizationComments",
                        operationName: "listenOrganizationComments",
                        targetType: .organization,
                        targetId: organizationID,
                        pathGroup: "organizations/{organizationID}/comments"
                    )
                    Task { @MainActor in onError(Self.appError(from: error)) }
                    return
                }

                let comments = snapshot?.documents.reversed().compactMap { makeCommentDTO(from: $0.data()).map(Comment.init(dto:)) } ?? []
                Task { @MainActor in onChange(comments) }
            }
        return FirebaseRealtimeListener(registration)
    }

    func listenSubmittedOrganizationRequests(
        userID: String,
        onChange: @escaping @MainActor ([Organization]) -> Void,
        onError: @escaping @MainActor (AppError) -> Void
    ) -> AppRealtimeListener {
        let requestStatuses = [
            ModerationStatus.pendingReview.rawValue,
            ModerationStatus.needsRevision.rawValue,
            ModerationStatus.rejected.rawValue
        ]
        let registration = collection
            .whereField("submittedByUserId", isEqualTo: userID)
            .whereField("moderationStatus", in: requestStatuses)
            .order(by: "submittedAt", descending: true)
            .limit(to: 100)
            .addSnapshotListener { snapshot, error in
                handleOrganizationRequestSnapshot(
                    snapshot,
                    error: error,
                    listenerName: "submittedOrganizationRequests",
                    targetId: userID,
                    onChange: onChange,
                    onError: onError
                )
            }
        return FirebaseRealtimeListener(registration)
    }

    func listenPendingOrganizationRequestsForOwner(
        onChange: @escaping @MainActor ([Organization]) -> Void,
        onError: @escaping @MainActor (AppError) -> Void
    ) -> AppRealtimeListener {
        let registration = collection
            .whereField("moderationStatus", isEqualTo: ModerationStatus.pendingReview.rawValue)
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
            .addSnapshotListener { snapshot, error in
                handleOrganizationRequestSnapshot(
                    snapshot,
                    error: error,
                    listenerName: "pendingOrganizationRequestsForOwner",
                    targetId: nil,
                    onChange: onChange,
                    onError: onError
                )
            }
        return FirebaseRealtimeListener(registration)
    }

    private func handleOrganizationRequestSnapshot(
        _ snapshot: QuerySnapshot?,
        error: Error?,
        listenerName: String,
        targetId: String?,
        onChange: @escaping @MainActor ([Organization]) -> Void,
        onError: @escaping @MainActor (AppError) -> Void
    ) {
        if let error {
            Self.logListenerFailure(
                error,
                listenerName: listenerName,
                operationName: "listenOrganizationRequests",
                targetType: .organization,
                targetId: targetId,
                pathGroup: "organizations"
            )
            Task { @MainActor in onError(Self.appError(from: error)) }
            return
        }

        Task {
            do {
                let organizations = try snapshot?.documents.map { document in
                    try Organization(dto: makeOrganizationDTO(
                        from: document,
                        likedOrganizationIDs: [],
                        subscribedOrganizationIDs: [],
                        bookmarkedOrganizationIDs: []
                    ))
                } ?? []
                await MainActor.run {
                    onChange(organizations)
                }
            } catch let appError as AppError {
                await MainActor.run {
                    onError(appError)
                }
            } catch {
                await MainActor.run {
                    onError(.unknown)
                }
            }
        }
    }

    private static func appError(from error: Error) -> AppError {
        let nsError = error as NSError
        if nsError.domain == FirestoreErrorDomain,
           nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
            return .permissionDenied
        }
        return .network
    }

    private static func logListenerFailure(
        _ error: Error,
        listenerName: String,
        operationName: String,
        targetType: SystemLogTargetType,
        targetId: String?,
        pathGroup: String
    ) {
        Task {
            await SystemTechnicalErrorLoggingService.shared.logFailure(
                error,
                context: SystemTechnicalErrorContext(
                    moduleName: "Organizations",
                    operationName: operationName,
                    targetType: targetType,
                    targetId: targetId,
                    metadata: [
                        "listenerName": listenerName,
                        "pathGroup": pathGroup
                    ]
                )
            )
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
