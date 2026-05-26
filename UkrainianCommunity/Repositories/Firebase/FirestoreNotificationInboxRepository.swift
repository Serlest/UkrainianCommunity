import Foundation
import FirebaseFirestore

struct FirestoreNotificationInboxRepository: NotificationInboxRepository {
    private let database = Firestore.firestore()

    func fetchNotifications(userID: String, limit: Int) async throws -> [AppNotification] {
        let snapshot = try await inboxCollection(userID: userID)
            .order(by: "createdAt", descending: true)
            .limit(to: max(1, limit))
            .getDocuments()

        return snapshot.documents.map(makeNotification)
    }

    func listenNotifications(
        userID: String,
        limit: Int,
        onChange: @escaping @MainActor ([AppNotification]) -> Void
    ) -> AppRealtimeListener {
        let registration = inboxCollection(userID: userID)
            .order(by: "createdAt", descending: true)
            .limit(to: max(1, limit))
            .addSnapshotListener { snapshot, _ in
                let notifications = snapshot?.documents.map(makeNotification) ?? []
                Task { @MainActor in onChange(notifications) }
            }

        return FirebaseRealtimeListener(registration)
    }

    func fetchUnreadCount(userID: String) async throws -> Int {
        let snapshot = try await inboxCollection(userID: userID)
            .whereField("isRead", isEqualTo: false)
            .getDocuments()

        return snapshot.documents.count
    }

    func markNotificationRead(userID: String, notificationID: String) async throws {
        try await inboxCollection(userID: userID).document(notificationID).updateData([
            "isRead": true,
            "readAt": FieldValue.serverTimestamp()
        ])
    }

    func markAllNotificationsRead(userID: String) async throws {
        let snapshot = try await inboxCollection(userID: userID)
            .whereField("isRead", isEqualTo: false)
            .getDocuments()

        guard !snapshot.documents.isEmpty else { return }

        let batch = database.batch()
        for document in snapshot.documents {
            batch.updateData([
                "isRead": true,
                "readAt": FieldValue.serverTimestamp()
            ], forDocument: document.reference)
        }
        try await batch.commit()
    }

    func createNotification(userID: String, notification: AppNotification) async throws {
        try await inboxCollection(userID: userID)
            .document(notification.id)
            .setData(makeNotificationData(notification))
    }

    private func inboxCollection(userID: String) -> CollectionReference {
        database
            .collection("users")
            .document(userID)
            .collection("notificationInbox")
    }

    private func makeNotification(from document: QueryDocumentSnapshot) -> AppNotification {
        let data = document.data()
        let type = (data["type"] as? String).flatMap(AppNotificationType.init(rawValue:)) ?? .feedbackReply
        let sourceType = (data["sourceType"] as? String).flatMap(AppNotificationSourceType.init(rawValue:)) ?? .feedback
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let readAt = (data["readAt"] as? Timestamp)?.dateValue()

        return AppNotification(
            id: data["id"] as? String ?? document.documentID,
            recipientUserId: data["recipientUserId"] as? String ?? "",
            type: type,
            sourceType: sourceType,
            sourceId: data["sourceId"] as? String ?? "",
            actorUserId: data["actorUserId"] as? String,
            actorDisplayName: data["actorDisplayName"] as? String,
            payload: data["payload"] as? [String: String] ?? [:],
            isRead: data["isRead"] as? Bool ?? false,
            readAt: readAt,
            createdAt: createdAt
        )
    }

    private func makeNotificationData(_ notification: AppNotification) -> [String: Any] {
        var data: [String: Any] = [
            "id": notification.id,
            "recipientUserId": notification.recipientUserId,
            "type": notification.type.rawValue,
            "sourceType": notification.sourceType.rawValue,
            "sourceId": notification.sourceId,
            "payload": notification.payload,
            "isRead": notification.isRead,
            "createdAt": Timestamp(date: notification.createdAt)
        ]

        if let actorUserId = notification.actorUserId {
            data["actorUserId"] = actorUserId
        }
        if let actorDisplayName = notification.actorDisplayName {
            data["actorDisplayName"] = actorDisplayName
        }
        if let readAt = notification.readAt {
            data["readAt"] = Timestamp(date: readAt)
        }

        return data
    }
}
