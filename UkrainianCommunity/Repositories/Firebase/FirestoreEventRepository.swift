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

        return try snapshot.documents.map { document in
            try Event(dto: makeEventDTO(
                from: document,
                likedEventIDs: likedEventIDs,
                registeredEventIDs: registeredEventIDs
            ))
        }
    }

    func fetchPendingEvents() async throws -> [Event] {
        let snapshot = try await collection
            .whereField("moderationStatus", isEqualTo: ModerationStatus.pendingReview.rawValue)
            .order(by: "createdAt", descending: true)
            .getDocuments()

        let likedEventIDs = try await fetchLikedEventIDs()
        let registeredEventIDs = try await fetchRegisteredEventIDs()

        return try snapshot.documents.map { document in
            try Event(dto: makeEventDTO(
                from: document,
                likedEventIDs: likedEventIDs,
                registeredEventIDs: registeredEventIDs
            ))
        }
    }

    func createEvent(_ event: Event) async throws {
        let now = Date()
        let normalizedEvent = Event(
            id: event.id,
            title: event.title,
            summary: event.summary,
            details: event.details,
            regionScope: event.regionScope,
            federalState: event.federalState,
            source: event.source,
            city: event.city,
            venue: event.venue,
            imageURL: event.imageURL,
            startDate: event.startDate,
            endDate: event.endDate,
            createdAt: now,
            updatedAt: now,
            capacity: event.capacity,
            registeredCount: event.registeredCount,
            comments: event.comments,
            moderationStatus: .approved,
            registrationState: event.registrationState,
            likeCount: event.likeCount,
            likeState: event.likeState
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
            "registeredCount": dto.registeredCount,
            "comments": dto.comments.map { comment in
                [
                    "id": comment.id,
                    "authorName": comment.authorName,
                    "body": comment.body,
                    "createdAt": comment.createdAt,
                    "updatedAt": comment.updatedAt
                ]
            },
            "moderationStatus": dto.moderationStatus,
            "registrationState": dto.registrationState,
            "likeCount": dto.likeCount,
            "likeState": dto.likeState
        ]

        if let capacity = dto.capacity {
            data["capacity"] = capacity
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
            "updatedAt": Timestamp(date: event.updatedAt)
        ]

        if let capacity = event.capacity {
            data["capacity"] = capacity
        } else {
            data["capacity"] = FieldValue.delete()
        }

        try await collection.document(event.id).updateData(data)
    }

    func deleteEvent(id: String) async throws {
        let imageReference = Storage.storage().reference().child("events/\(id)/cover.jpg")

        do {
            try await imageReference.delete()
        } catch {}

        try await deleteRelatedLikes(eventID: id)
        try await deleteRelatedRegistrations(eventID: id)
        try await collection.document(id).delete()
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
            let nsError = error as NSError
            print("Firestore likeEvent failed")
            print("error code=\(nsError.code) domain=\(nsError.domain)")
            print("error message=\(nsError.localizedDescription)")
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
            let nsError = error as NSError
            print("Firestore unlikeEvent failed")
            print("error code=\(nsError.code) domain=\(nsError.domain)")
            print("error message=\(nsError.localizedDescription)")
            throw error
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

                let registrationSnapshot = try transaction.getDocument(registrationReference)
                if registrationSnapshot.exists {
                    return nil
                }

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
            let nsError = error as NSError
            print("Firestore registerForEvent failed")
            print("error code=\(nsError.code) domain=\(nsError.domain)")
            print("error message=\(nsError.localizedDescription)")
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
            let nsError = error as NSError
            print("Firestore cancelEventRegistration failed")
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

    private func makeEventDTO(
        from document: QueryDocumentSnapshot,
        likedEventIDs: Set<String>,
        registeredEventIDs: Set<String>
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
            city: city,
            venue: venue,
            imageURL: data["imageURL"] as? String,
            startDate: startDate,
            endDate: endDate,
            createdAt: createdAt,
            updatedAt: updatedAt,
            capacity: data["capacity"] as? Int,
            registeredCount: data["registeredCount"] as? Int ?? 0,
            comments: comments,
            moderationStatus: moderationStatus,
            registrationState: registeredEventIDs.contains(document.documentID) ? EventRegistrationState.registered.rawValue : EventRegistrationState.notRegistered.rawValue,
            likeCount: data["likeCount"] as? Int ?? 0,
            likeState: likedEventIDs.contains(document.documentID) ? LikeState.liked.rawValue : LikeState.notLiked.rawValue
        )
    }

    private func likeDocumentID(eventID: String, userID: String) -> String {
        "event_\(eventID)_\(userID)"
    }

    private func registrationDocumentID(eventID: String, userID: String) -> String {
        "event_\(eventID)_\(userID)"
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
