import Foundation
import FirebaseFirestore

struct FirestoreEventRepository: EventRepository {
    private let collection = Firestore.firestore().collection("events")

    func fetchEvents() async throws -> [Event] {
        let snapshot = try await collection
            .whereField("moderationStatus", isEqualTo: ModerationStatus.approved.rawValue)
            .order(by: "startDate", descending: false)
            .getDocuments()

        return try snapshot.documents.map { document in
            try Event(dto: makeEventDTO(from: document))
        }
    }

    func createEvent(_ event: Event) async throws {
        let now = Date()
        let normalizedEvent = Event(
            id: event.id,
            title: event.title,
            summary: event.summary,
            details: event.details,
            city: event.city,
            venue: event.venue,
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
            "city": dto.city,
            "venue": dto.venue,
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

    func likeEvent(id: String) async throws {
        throw AppError.unknown
    }

    func unlikeEvent(id: String) async throws {
        throw AppError.unknown
    }

    func registerForEvent(id: String) async throws {
        throw AppError.unknown
    }

    func cancelEventRegistration(id: String) async throws {
        throw AppError.unknown
    }

    private func makeEventDTO(from document: QueryDocumentSnapshot) throws -> EventDTO {
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
            city: city,
            venue: venue,
            startDate: startDate,
            endDate: endDate,
            createdAt: createdAt,
            updatedAt: updatedAt,
            capacity: data["capacity"] as? Int,
            registeredCount: data["registeredCount"] as? Int ?? 0,
            comments: comments,
            moderationStatus: moderationStatus,
            registrationState: data["registrationState"] as? String ?? EventRegistrationState.notRegistered.rawValue,
            likeCount: data["likeCount"] as? Int ?? 0,
            likeState: data["likeState"] as? String ?? LikeState.notLiked.rawValue
        )
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
