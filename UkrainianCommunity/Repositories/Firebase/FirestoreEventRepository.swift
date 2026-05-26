import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

struct FirestoreEventRepository: EventRepository {
    private let collection = Firestore.firestore().collection("events")
    private let likesCollection = Firestore.firestore().collection("likes")
    private let registrationsCollection = Firestore.firestore().collection("registrations")

    func fetchEvents() async throws -> [Event] {
        let snapshot = try await collection
            .whereField("moderationStatus", isEqualTo: ModerationStatus.approved.rawValue)
            .order(by: "startDate", descending: false)
            .getDocuments()

        let likedEventIDs = try await fetchLikedEventIDs()
        let registeredEventIDs = try await fetchRegisteredEventIDs()
        let bookmarkedEventIDs = try await fetchBookmarkedEventIDs()

        return try snapshot.documents.map { document in
            try Event(dto: makeEventDTO(
                from: document,
                likedEventIDs: likedEventIDs,
                registeredEventIDs: registeredEventIDs,
                bookmarkedEventIDs: bookmarkedEventIDs
            ))
        }
    }

    func fetchRegisteredEvents() async throws -> [Event] {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppError.permissionDenied
        }

        let registrationsSnapshot = try await registrationsCollection
            .whereField("userId", isEqualTo: uid)
            .getDocuments()

        let registeredEventIDs = registrationsSnapshot.documents.compactMap { $0.data()["eventId"] as? String }
        guard !registeredEventIDs.isEmpty else {
            return []
        }

        let likedEventIDs = try await fetchLikedEventIDs()
        let bookmarkedEventIDs = try await fetchBookmarkedEventIDs()
        let registeredEventIDSet = Set(registeredEventIDs)
        var registeredEvents: [Event] = []

        for chunk in registeredEventIDs.chunked(into: 10) {
            let snapshot = try await collection
                .whereField(FieldPath.documentID(), in: Array(chunk))
                .getDocuments()

            var resolvedEvents: [Event] = []
            for document in snapshot.documents {
                let dto = try makeEventDTO(
                    from: document,
                    likedEventIDs: likedEventIDs,
                    registeredEventIDs: registeredEventIDSet,
                    bookmarkedEventIDs: bookmarkedEventIDs
                )

                guard dto.moderationStatus == ModerationStatus.approved.rawValue else {
                    continue
                }

                resolvedEvents.append(Event(dto: dto))
            }

            registeredEvents.append(contentsOf: resolvedEvents)
        }

        return registeredEvents.sorted { $0.startDate < $1.startDate }
    }

    func fetchPendingEvents() async throws -> [Event] {
        let snapshot = try await collection
            .whereField("moderationStatus", isEqualTo: ModerationStatus.pendingReview.rawValue)
            .order(by: "createdAt", descending: true)
            .getDocuments()

        let likedEventIDs = try await fetchLikedEventIDs()
        let registeredEventIDs = try await fetchRegisteredEventIDs()
        let bookmarkedEventIDs = try await fetchBookmarkedEventIDs()

        return try snapshot.documents.map { document in
            try Event(dto: makeEventDTO(
                from: document,
                likedEventIDs: likedEventIDs,
                registeredEventIDs: registeredEventIDs,
                bookmarkedEventIDs: bookmarkedEventIDs
            ))
        }
    }

    func fetchOrganizationModerationEvents(organizationID: String) async throws -> [Event] {
        let snapshot = try await collection
            .whereField("sourceType", isEqualTo: ContentSourceType.organization.rawValue)
            .whereField("organizationId", isEqualTo: organizationID)
            .whereField("moderationStatus", in: organizationModerationStatusValues)
            .order(by: "createdAt", descending: true)
            .getDocuments()

        let likedEventIDs = try await fetchLikedEventIDs()
        let registeredEventIDs = try await fetchRegisteredEventIDs()
        let bookmarkedEventIDs = try await fetchBookmarkedEventIDs()

        return try snapshot.documents.map { document in
            try Event(dto: makeEventDTO(
                from: document,
                likedEventIDs: likedEventIDs,
                registeredEventIDs: registeredEventIDs,
                bookmarkedEventIDs: bookmarkedEventIDs
            ))
        }
    }

    func fetchOrganizationEventCount(organizationID: String) async throws -> Int {
        let snapshot = try await collection
            .whereField("sourceType", isEqualTo: ContentSourceType.organization.rawValue)
            .whereField("organizationId", isEqualTo: organizationID)
            .whereField("moderationStatus", in: organizationContentStatusValues)
            .getDocuments()

        return snapshot.documents.count
    }

    func fetchEventComments(eventID: String) async throws -> [Comment] {
        try await fetchComments(eventID: eventID)
    }

    func createEvent(_ event: Event) async throws {
        let now = Date()
        let currentUserID = Auth.auth().currentUser?.uid
        let resolvedAuthorName = try await resolvedCurrentUserAuthorName()
        let normalizedEvent = Event(
            id: event.id,
            title: event.title,
            summary: event.summary,
            details: event.details,
            regionScope: event.regionScope,
            federalState: event.federalState,
            source: event.source,
            authorId: event.authorId ?? currentUserID,
            authorName: event.authorName ?? resolvedAuthorName,
            city: event.city,
            venue: event.venue,
            address: event.address,
            locationNote: event.locationNote,
            latitude: event.latitude,
            longitude: event.longitude,
            imageURL: event.imageURL,
            startDate: event.startDate,
            endDate: event.endDate,
            createdAt: now,
            updatedAt: now,
            price: event.price,
            capacity: event.capacity,
            registeredCount: event.registeredCount,
            comments: event.comments,
            moderationStatus: .approved,
            registrationState: event.registrationState,
            likeCount: event.likeCount,
            likeState: event.likeState,
            viewCount: event.viewCount,
            category: event.category,
            isAllDay: event.isAllDay
        )
        let dto = normalizedEvent.dto
        var data: [String: Any] = [
            "id": dto.id,
            "title": dto.title,
            "summary": dto.summary,
            "details": dto.details,
            "regionScope": dto.regionScope as Any,
            "federalState": dto.federalState as Any,
            "sourceType": dto.sourceType as Any,
            "organizationId": dto.organizationId as Any,
            "organizationName": dto.organizationName as Any,
            "organizationImageURL": dto.organizationImageURL as Any,
            "city": dto.city,
            "venue": dto.venue,
            "imageURL": dto.imageURL as Any,
            "startDate": dto.startDate,
            "endDate": dto.endDate,
            "createdAt": dto.createdAt,
            "updatedAt": dto.updatedAt,
            "price": dto.price,
            "registeredCount": dto.registeredCount,
            "moderationStatus": dto.moderationStatus,
            "registrationState": dto.registrationState,
            "likeCount": dto.likeCount,
            "likeState": dto.likeState,
            "viewCount": dto.viewCount,
            "commentCount": dto.commentCount ?? dto.comments.count,
            "category": dto.category as Any,
            "visibility": "public",
            "isAllDay": dto.isAllDay as Any
        ]

        if let capacity = dto.capacity {
            data["capacity"] = capacity
        }
        if let authorId = dto.authorId {
            data["authorId"] = authorId
        }
        if let authorName = dto.authorName {
            data["authorName"] = authorName
        }
        if let address = dto.address {
            data["address"] = address
        }
        if let locationNote = dto.locationNote {
            data["locationNote"] = locationNote
        }
        if let latitude = dto.latitude {
            data["latitude"] = latitude
        }
        if let longitude = dto.longitude {
            data["longitude"] = longitude
        }

        try await collection.document(dto.id).setData(data)
    }

    func updateEvent(_ event: Event) async throws {
        var data: [String: Any] = [
            "title": event.title,
            "summary": event.summary,
            "details": event.details,
            "regionScope": event.regionScope?.rawValue as Any,
            "federalState": event.federalState?.rawValue as Any,
            "sourceType": event.source.sourceType.rawValue,
            "organizationId": event.source.organizationId as Any,
            "organizationName": event.source.organizationName as Any,
            "organizationImageURL": event.source.organizationImageURL as Any,
            "city": event.city,
            "venue": event.venue,
            "imageURL": event.imageURL as Any,
            "startDate": Timestamp(date: event.startDate),
            "endDate": Timestamp(date: event.endDate),
            "updatedAt": Timestamp(date: event.updatedAt),
            "price": event.price,
            "category": event.category.rawValue,
            "visibility": "public",
            "isAllDay": event.isAllDay
        ]

        if let capacity = event.capacity {
            data["capacity"] = capacity
        } else {
            data["capacity"] = FieldValue.delete()
        }

        if let authorName = event.authorName {
            data["authorName"] = authorName
        } else {
            data["authorName"] = FieldValue.delete()
        }

        if let authorId = event.authorId {
            data["authorId"] = authorId
        } else {
            data["authorId"] = FieldValue.delete()
        }

        if let address = event.address {
            data["address"] = address
        } else {
            data["address"] = FieldValue.delete()
        }

        if let locationNote = event.locationNote {
            data["locationNote"] = locationNote
        } else {
            data["locationNote"] = FieldValue.delete()
        }

        if let latitude = event.latitude {
            data["latitude"] = latitude
        } else {
            data["latitude"] = FieldValue.delete()
        }

        if let longitude = event.longitude {
            data["longitude"] = longitude
        } else {
            data["longitude"] = FieldValue.delete()
        }

        try await collection.document(event.id).updateData(data)
    }

    func updateEventImageURL(id: String, imageURL: String?) async throws {
        try await collection.document(id).updateData([
            "imageURL": imageURL as Any,
            "updatedAt": Timestamp(date: Date())
        ])
    }

    func deleteEvent(id: String) async throws {
        await deleteEventCoverImageIfPossible(id: id)
        try await collection.document(id).delete()
        await deleteRelatedLikesIfPossible(eventID: id)
        await deleteRelatedRegistrationsIfPossible(eventID: id)
    }

    private func deleteEventCoverImageIfPossible(id: String) async {
        let imageReference = Storage.storage().reference().child("events/\(id)/cover.jpg")

        do {
            try await imageReference.delete()
        } catch {}
    }

    func likeEvent(id: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppError.permissionDenied
        }

        let eventReference = collection.document(id)
        let likeReference = likesCollection.document(likeDocumentID(eventID: id, userID: uid))
        let likeData: [String: Any] = [
            "id": likeReference.documentID,
            "eventId": id,
            "userId": uid,
            "createdAt": FieldValue.serverTimestamp()
        ]

        do {
            _ = try await Firestore.firestore().runTransaction { transaction, errorPointer in
            do {
                let eventSnapshot = try transaction.getDocument(eventReference)
                guard eventSnapshot.exists else {
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
                ], forDocument: eventReference)
            } catch {
                errorPointer?.pointee = error as NSError
            }

            return nil
            }
        } catch {
            throw error
        }
    }

    func unlikeEvent(id: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppError.permissionDenied
        }

        let eventReference = collection.document(id)
        let likeReference = likesCollection.document(likeDocumentID(eventID: id, userID: uid))
        do {
            _ = try await Firestore.firestore().runTransaction { transaction, errorPointer in
            do {
                let eventSnapshot = try transaction.getDocument(eventReference)
                guard eventSnapshot.exists else {
                    errorPointer?.pointee = AppError.notFound.asNSError
                    return nil
                }

                let likeSnapshot = try transaction.getDocument(likeReference)
                guard likeSnapshot.exists else {
                    return nil
                }

                let currentLikeCount = eventSnapshot.data()?["likeCount"] as? Int ?? 0
                transaction.deleteDocument(likeReference)
                transaction.updateData([
                    "likeCount": max(0, currentLikeCount - 1)
                ], forDocument: eventReference)
            } catch {
                errorPointer?.pointee = error as NSError
            }

            return nil
            }
        } catch {
            throw error
        }
    }

    func recordEventView(id: String) async throws -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }

        let eventReference = collection.document(id)
        let viewReference = eventViewReference(eventID: id, userID: uid)
        let viewData: [String: Any] = [
            "id": id,
            "eventId": id,
            "userId": uid,
            "createdAt": FieldValue.serverTimestamp()
        ]

        let result = try await Firestore.firestore().runTransaction { transaction, errorPointer in
            do {
                let eventSnapshot = try transaction.getDocument(eventReference)
                guard eventSnapshot.exists else {
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
                ], forDocument: eventReference)
                return true
            } catch {
                errorPointer?.pointee = error as NSError
                return false
            }
        }

        return result as? Bool ?? false
    }

    func addEventComment(eventID: String, text: String, author: AppUser) async throws -> Comment {
        guard Auth.auth().currentUser?.uid == author.id else {
            throw AppError.permissionDenied
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw AppError.validationFailed
        }

        let now = Date()
        let eventReference = collection.document(eventID)
        let commentReference = eventReference.collection("comments").document()
        let comment = Comment(
            id: commentReference.documentID,
            parentType: .event,
            parentId: eventID,
            authorId: author.id,
            authorName: author.commentDisplayName,
            authorPhotoURL: author.avatarURL?.absoluteString,
            text: String(trimmedText.prefix(1000)),
            createdAt: now,
            updatedAt: nil,
            moderationStatus: .approved,
            isDeleted: false
        )

        let batch = Firestore.firestore().batch()
        batch.setData(makeCommentData(from: comment.dto), forDocument: commentReference)
        batch.updateData([
            "commentCount": FieldValue.increment(Int64(1))
        ], forDocument: eventReference)
        try await batch.commit()
        return comment
    }

    func updateEventComment(eventID: String, commentID: String, text: String) async throws -> Comment {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppError.permissionDenied
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw AppError.validationFailed
        }

        let commentReference = collection.document(eventID).collection("comments").document(commentID)
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
            parentType: .event,
            parentId: eventID,
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

    func deleteEventComment(eventID: String, commentID: String) async throws {
        guard Auth.auth().currentUser != nil else {
            throw AppError.permissionDenied
        }

        let eventReference = collection.document(eventID)
        let commentReference = eventReference.collection("comments").document(commentID)
        _ = try await Firestore.firestore().runTransaction { transaction, errorPointer in
            do {
                let eventSnapshot = try transaction.getDocument(eventReference)
                let commentSnapshot = try transaction.getDocument(commentReference)
                guard makeCommentDTO(from: commentSnapshot.data() ?? [:]) != nil else {
                    errorPointer?.pointee = AppError.notFound.asNSError
                    return nil
                }

                transaction.deleteDocument(commentReference)
                let currentCommentCount = eventSnapshot.data()?["commentCount"] as? Int ?? 0
                if currentCommentCount > 0 {
                    transaction.updateData([
                        "commentCount": currentCommentCount - 1
                    ], forDocument: eventReference)
                }
            } catch {
                errorPointer?.pointee = error as NSError
            }

            return nil
        }
    }

    func registerForEvent(id: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppError.permissionDenied
        }

        let eventReference = collection.document(id)
        let registrationReference = registrationsCollection.document(registrationDocumentID(eventID: id, userID: uid))
        let registrationData: [String: Any] = [
            "id": registrationReference.documentID,
            "eventId": id,
            "userId": uid,
            "registeredAt": FieldValue.serverTimestamp(),
            "createdAt": FieldValue.serverTimestamp()
        ]

        do {
            _ = try await Firestore.firestore().runTransaction { transaction, errorPointer in
            do {
                let eventSnapshot = try transaction.getDocument(eventReference)
                guard eventSnapshot.exists else {
                    errorPointer?.pointee = AppError.notFound.asNSError
                    return nil
                }

                // Do not pre-read the registration document here. Firestore rules allow create
                // and deny update, so the deterministic document id acts as create-only protection.
                transaction.setData(registrationData, forDocument: registrationReference)
                transaction.updateData([
                    "registeredCount": FieldValue.increment(Int64(1))
                ], forDocument: eventReference)
            } catch {
                errorPointer?.pointee = error as NSError
            }

            return nil
            }
        } catch {
            throw error
        }
    }

    func cancelEventRegistration(id: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppError.permissionDenied
        }

        let eventReference = collection.document(id)
        let registrationReference = registrationsCollection.document(registrationDocumentID(eventID: id, userID: uid))
        do {
            _ = try await Firestore.firestore().runTransaction { transaction, errorPointer in
            do {
                let eventSnapshot = try transaction.getDocument(eventReference)
                guard eventSnapshot.exists else {
                    errorPointer?.pointee = AppError.notFound.asNSError
                    return nil
                }

                let registrationSnapshot = try transaction.getDocument(registrationReference)
                guard registrationSnapshot.exists else {
                    return nil
                }

                let currentRegisteredCount = eventSnapshot.data()?["registeredCount"] as? Int ?? 0
                transaction.deleteDocument(registrationReference)
                transaction.updateData([
                    "registeredCount": max(0, currentRegisteredCount - 1)
                ], forDocument: eventReference)
            } catch {
                errorPointer?.pointee = error as NSError
            }

            return nil
            }
        } catch {
            throw error
        }
    }

    func bookmarkEvent(id: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppError.permissionDenied
        }

        try await eventBookmarkReference(eventID: id, userID: uid).setData([
            "id": id,
            "eventId": id,
            "userId": uid,
            "createdAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    func unbookmarkEvent(id: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppError.permissionDenied
        }

        try await eventBookmarkReference(eventID: id, userID: uid).delete()
    }

    func updateModerationStatus(id: String, newStatus: ModerationStatus) async throws {
        try await collection.document(id).updateData([
            "moderationStatus": newStatus.rawValue,
            "updatedAt": Timestamp(date: Date())
        ])
    }

    private func fetchLikedEventIDs() async throws -> Set<String> {
        guard let uid = Auth.auth().currentUser?.uid else {
            return []
        }

        let snapshot = try await likesCollection
            .whereField("userId", isEqualTo: uid)
            .getDocuments()

        return Set(snapshot.documents.compactMap { $0.data()["eventId"] as? String })
    }

    private func fetchRegisteredEventIDs() async throws -> Set<String> {
        guard let uid = Auth.auth().currentUser?.uid else {
            return []
        }

        let snapshot = try await registrationsCollection
            .whereField("userId", isEqualTo: uid)
            .getDocuments()

        return Set(snapshot.documents.compactMap { $0.data()["eventId"] as? String })
    }

    private func fetchBookmarkedEventIDs() async throws -> Set<String> {
        guard let uid = Auth.auth().currentUser?.uid else {
            return []
        }

        let snapshot = try await Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("eventBookmarks")
            .getDocuments()

        return Set(snapshot.documents.compactMap { $0.data()["eventId"] as? String })
    }

    private func makeEventDTO(
        from document: QueryDocumentSnapshot,
        likedEventIDs: Set<String>,
        registeredEventIDs: Set<String>,
        bookmarkedEventIDs: Set<String>
    ) throws -> EventDTO {
        let data = document.data()

        guard
            let title = data["title"] as? String,
            let summary = data["summary"] as? String,
            let details = data["details"] as? String,
            let city = data["city"] as? String,
            let venue = data["venue"] as? String,
            let startDate = (data["startDate"] as? Timestamp)?.dateValue(),
            let endDate = (data["endDate"] as? Timestamp)?.dateValue(),
            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue(),
            let moderationStatus = data["moderationStatus"] as? String
        else {
            throw AppError.notFound
        }

        let comments = (data["comments"] as? [[String: Any]] ?? []).compactMap(makeCommentDTO(from:))

        return EventDTO(
            id: data["id"] as? String ?? document.documentID,
            title: title,
            summary: summary,
            details: details,
            regionScope: data["regionScope"] as? String,
            federalState: data["federalState"] as? String,
            sourceType: data["sourceType"] as? String,
            organizationId: data["organizationId"] as? String,
            organizationName: data["organizationName"] as? String,
            organizationImageURL: data["organizationImageURL"] as? String,
            authorId: data["authorId"] as? String,
            authorName: data["authorName"] as? String,
            city: city,
            venue: venue,
            address: data["address"] as? String,
            locationNote: data["locationNote"] as? String,
            latitude: data["latitude"] as? Double,
            longitude: data["longitude"] as? Double,
            imageURL: (data["imageURL"] as? String)?.nilIfEmpty,
            startDate: startDate,
            endDate: endDate,
            createdAt: createdAt,
            updatedAt: updatedAt,
            price: (data["price"] as? NSNumber)?.doubleValue ?? 0,
            capacity: data["capacity"] as? Int,
            registeredCount: data["registeredCount"] as? Int ?? 0,
            comments: comments,
            commentCount: (data["commentCount"] as? Int) ?? (data["commentCount"] as? NSNumber)?.intValue ?? 0,
            moderationStatus: moderationStatus,
            registrationState: registeredEventIDs.contains(document.documentID) ? EventRegistrationState.registered.rawValue : EventRegistrationState.notRegistered.rawValue,
            likeCount: data["likeCount"] as? Int ?? 0,
            likeState: likedEventIDs.contains(document.documentID) ? LikeState.liked.rawValue : LikeState.notLiked.rawValue,
            viewCount: data["viewCount"] as? Int ?? 0,
            category: data["category"] as? String,
            visibility: data["visibility"] as? String,
            isAllDay: data["isAllDay"] as? Bool,
            isBookmarked: bookmarkedEventIDs.contains(document.documentID)
        )
    }

    private func likeDocumentID(eventID: String, userID: String) -> String {
        "event_\(eventID)_\(userID)"
    }

    private func registrationDocumentID(eventID: String, userID: String) -> String {
        "event_\(eventID)_\(userID)"
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

    private func eventBookmarkReference(eventID: String, userID: String) -> DocumentReference {
        Firestore.firestore()
            .collection("users")
            .document(userID)
            .collection("eventBookmarks")
            .document(eventID)
    }

    private func eventViewReference(eventID: String, userID: String) -> DocumentReference {
        Firestore.firestore()
            .collection("users")
            .document(userID)
            .collection("eventViews")
            .document(eventID)
    }

    private func resolvedCurrentUserAuthorName() async throws -> String? {
        guard let uid = Auth.auth().currentUser?.uid else {
            return currentUserAuthorName
        }

        let snapshot = try? await Firestore.firestore()
            .collection("users")
            .document(uid)
            .getDocument()
        let data = snapshot?.data()
        let profileDisplayName = (data?["displayName"] as? String)?.nilIfEmpty
        let profileFullName = (data?["fullName"] as? String)?.nilIfEmpty
        return profileDisplayName ?? profileFullName ?? currentUserAuthorName
    }

    private var currentUserAuthorName: String? {
        let user = Auth.auth().currentUser
        let displayName = user?.displayName?.nilIfEmpty
        let emailName = user?.email?
            .split(separator: "@")
            .first
            .map(String.init)?
            .nilIfEmpty
        return displayName ?? emailName
    }

    private func deleteRelatedLikes(eventID: String) async throws {
        let snapshot = try await likesCollection
            .whereField("eventId", isEqualTo: eventID)
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

    private func deleteRelatedLikesIfPossible(eventID: String) async {
        do {
            try await deleteRelatedLikes(eventID: eventID)
        } catch {}
    }

    private func deleteRelatedRegistrations(eventID: String) async throws {
        let snapshot = try await registrationsCollection
            .whereField("eventId", isEqualTo: eventID)
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

    private func deleteRelatedRegistrationsIfPossible(eventID: String) async {
        do {
            try await deleteRelatedRegistrations(eventID: eventID)
        } catch {}
    }

    private func fetchComments(eventID: String) async throws -> [Comment] {
        let snapshot = try await collection.document(eventID)
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

extension FirestoreEventRepository: EventRealtimeRepository {
    func listenEventComments(
        eventID: String,
        onChange: @escaping @MainActor ([Comment]) -> Void,
        onError: @escaping @MainActor (AppError) -> Void
    ) -> AppRealtimeListener {
        let registration = collection.document(eventID)
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
