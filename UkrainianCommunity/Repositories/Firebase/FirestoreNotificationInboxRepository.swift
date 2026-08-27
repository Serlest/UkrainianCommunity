import Foundation
import FirebaseFirestore

struct FirestoreNotificationInboxRepository: NotificationInboxRepository {
    private let database = Firestore.firestore()

    func fetchNotifications(userID: String, limit: Int) async throws -> [AppNotification] {
        let snapshot = try await inboxCollection(userID: userID)
            .order(by: "createdAt", descending: true)
            .limit(to: max(1, limit))
            .getDocuments()

        return snapshot.documents
            .map(makeNotification)
            .filter(\.isVisibleInInbox)
    }

    func listenNotifications(
        userID: String,
        limit: Int,
        onChange: @escaping @MainActor ([AppNotification]) -> Void,
        onError: @escaping @MainActor (AppError) -> Void
    ) -> AppRealtimeListener {
        let registration = inboxCollection(userID: userID)
            .order(by: "createdAt", descending: true)
            .limit(to: max(1, limit))
            .addSnapshotListener { snapshot, error in
                if let error {
                    Self.logListenerFailure(
                        error,
                        listenerName: "notificationInbox",
                        userID: userID
                    )
                    Task { @MainActor in onError(Self.appError(from: error)) }
                    return
                }

                let notifications = snapshot?.documents
                    .map(makeNotification)
                    .filter(\.isVisibleInInbox) ?? []
                Task { @MainActor in onChange(notifications) }
            }

        return FirebaseRealtimeListener(registration)
    }

    // Independent of the 50-row inbox page: the badge represents the whole inbox.
    func listenUnreadCount(
        userID: String,
        onChange: @escaping @MainActor (Int) -> Void,
        onError: @escaping @MainActor (AppError) -> Void
    ) -> AppRealtimeListener {
        let registration = inboxCollection(userID: userID)
            .whereField("isRead", isEqualTo: false)
            .addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
                if let error {
                    Self.logListenerFailure(error, listenerName: "notificationUnreadCount", userID: userID)
                    Task { @MainActor in onError(Self.appError(from: error)) }
                    return
                }
                // A partial offline cache must not replace the authoritative APNs total.
                guard let snapshot, !snapshot.metadata.isFromCache else { return }
                let count = snapshot.documents.map(makeNotification).filter(\.countsAsUnread).count
                Task { @MainActor in onChange(count) }
            }
        return FirebaseRealtimeListener(registration)
    }

    func fetchUnreadCount(userID: String) async throws -> Int {
        let snapshot = try await inboxCollection(userID: userID)
            .whereField("isRead", isEqualTo: false)
            .getDocuments(source: .server)

        return snapshot.documents
            .map(makeNotification)
            .filter(\.countsAsUnread)
            .count
    }

    func markNotificationRead(userID: String, notificationID: String) async throws {
        try await inboxCollection(userID: userID).document(notificationID).updateData([
            "isRead": true,
            "readAt": FieldValue.serverTimestamp()
        ])
    }

    func markNotificationUnread(userID: String, notificationID: String) async throws {
        try await inboxCollection(userID: userID).document(notificationID).updateData([
            "isRead": false,
            "readAt": FieldValue.delete()
        ])
    }

    func markAllNotificationsRead(userID: String) async throws {
        let snapshot = try await inboxCollection(userID: userID)
            .whereField("isRead", isEqualTo: false)
            .getDocuments()

        let unreadDocuments = snapshot.documents.filter { document in
            makeNotification(from: document).countsAsUnread
        }
        guard !unreadDocuments.isEmpty else { return }

        for start in stride(from: 0, to: unreadDocuments.count, by: 450) {
            let batch = database.batch()
            for document in unreadDocuments[start..<min(start + 450, unreadDocuments.count)] {
                batch.updateData([
                    "isRead": true,
                    "readAt": FieldValue.serverTimestamp()
                ], forDocument: document.reference)
            }
            try await batch.commit()
        }
    }

    func markNotificationPopupPresented(userID: String, notificationID: String) async throws {
        try await inboxCollection(userID: userID).document(notificationID).updateData([
            "popupPresentedAt": FieldValue.serverTimestamp()
        ])
    }

    func archiveNotification(userID: String, notificationID: String) async throws {
        try await inboxCollection(userID: userID).document(notificationID).updateData([
            "archivedAt": FieldValue.serverTimestamp()
        ])
    }

    func deleteNotification(userID: String, notificationID: String) async throws {
        try await inboxCollection(userID: userID).document(notificationID).updateData([
            "deletedAt": FieldValue.serverTimestamp()
        ])
    }

    func clearNotifications(userID: String) async throws {
        let snapshot = try await inboxCollection(userID: userID).getDocuments()
        let visibleDocuments = snapshot.documents.filter {
            makeNotification(from: $0).isVisibleInInbox
        }

        for chunkStart in stride(from: 0, to: visibleDocuments.count, by: 450) {
            let chunkEnd = min(chunkStart + 450, visibleDocuments.count)
            let batch = database.batch()
            for document in visibleDocuments[chunkStart..<chunkEnd] {
                batch.updateData(
                    ["deletedAt": FieldValue.serverTimestamp()],
                    forDocument: document.reference
                )
            }
            try await batch.commit()
        }
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

    private static func logListenerFailure(_ error: Error, listenerName: String, userID: String) {
        Task {
            await SystemTechnicalErrorLoggingService.shared.logFailure(
                error,
                context: SystemTechnicalErrorContext(
                    moduleName: "Notifications",
                    operationName: "listenNotifications",
                    targetType: .notification,
                    targetId: userID,
                    metadata: [
                        "listenerName": listenerName,
                        "pathGroup": "users/{userID}/notificationInbox"
                    ]
                )
            )
        }
    }

    private func makeNotification(from document: QueryDocumentSnapshot) -> AppNotification {
        let data = document.data()
        let type = (data["type"] as? String).flatMap(AppNotificationType.init(rawValue:)) ?? .unknown
        let sourceType = (data["sourceType"] as? String).flatMap(AppNotificationSourceType.init(rawValue:)) ?? .system
        let severity = (data["severity"] as? String).flatMap(AppNotificationSeverity.init(rawValue:)) ?? defaultSeverity(for: type)
        let actionType = (data["actionType"] as? String).flatMap(AppNotificationActionType.init(rawValue:)) ?? defaultActionType(for: type)
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let readAt = (data["readAt"] as? Timestamp)?.dateValue()

        return AppNotification(
            id: data["id"] as? String ?? document.documentID,
            // The authenticated inbox path is authoritative, including legacy records without this field.
            recipientUserId: document.reference.parent.parent?.documentID ?? data["recipientUserId"] as? String ?? "",
            type: type,
            sourceType: sourceType,
            sourceId: data["sourceId"] as? String ?? "",
            severity: severity,
            actionType: actionType,
            actionTargetId: data["actionTargetId"] as? String,
            requiresPopup: data["requiresPopup"] as? Bool ?? false,
            popupPresentedAt: (data["popupPresentedAt"] as? Timestamp)?.dateValue(),
            expiresAt: (data["expiresAt"] as? Timestamp)?.dateValue(),
            archivedAt: (data["archivedAt"] as? Timestamp)?.dateValue(),
            deletedAt: (data["deletedAt"] as? Timestamp)?.dateValue(),
            title: nonEmptyString(from: data["title"]),
            message: nonEmptyString(from: data["message"]),
            metadata: stringDictionary(from: data["metadata"]),
            actorUserId: data["actorUserId"] as? String,
            actorDisplayName: data["actorDisplayName"] as? String,
            dedupeKey: data["dedupeKey"] as? String,
            payload: stringDictionary(from: data["payload"]),
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

        if let title = notification.title {
            data["title"] = title
        }
        if let message = notification.message {
            data["message"] = message
        }
        if notification.severity != defaultSeverity(for: notification.type) {
            data["severity"] = notification.severity.rawValue
        }
        if notification.actionType != .none {
            data["actionType"] = notification.actionType.rawValue
        }
        if let actionTargetId = notification.actionTargetId {
            data["actionTargetId"] = actionTargetId
        }
        if notification.requiresPopup {
            data["requiresPopup"] = notification.requiresPopup
        }
        if let popupPresentedAt = notification.popupPresentedAt {
            data["popupPresentedAt"] = Timestamp(date: popupPresentedAt)
        }
        if let expiresAt = notification.expiresAt {
            data["expiresAt"] = Timestamp(date: expiresAt)
        }
        if let archivedAt = notification.archivedAt {
            data["archivedAt"] = Timestamp(date: archivedAt)
        }
        if let deletedAt = notification.deletedAt {
            data["deletedAt"] = Timestamp(date: deletedAt)
        }
        if let actorUserId = notification.actorUserId {
            data["actorUserId"] = actorUserId
        }
        if let actorDisplayName = notification.actorDisplayName {
            data["actorDisplayName"] = actorDisplayName
        }
        if let dedupeKey = notification.dedupeKey {
            data["dedupeKey"] = dedupeKey
        }
        if !notification.metadata.isEmpty {
            data["metadata"] = notification.metadata
        }
        if let readAt = notification.readAt {
            data["readAt"] = Timestamp(date: readAt)
        }

        return data
    }

    private func stringDictionary(from value: Any?) -> [String: String] {
        guard let dictionary = value as? [String: Any] else { return [:] }

        return dictionary.reduce(into: [String: String]()) { result, item in
            guard let stringValue = stringValue(from: item.value) else { return }
            result[item.key] = stringValue
        }
    }

    private func nonEmptyString(from value: Any?) -> String? {
        guard let string = stringValue(from: value)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty else {
            return nil
        }

        return string
    }

    private func stringValue(from value: Any?) -> String? {
        switch value {
        case let string as String:
            string
        case let bool as Bool:
            String(bool)
        case let number as NSNumber:
            number.stringValue
        case let timestamp as Timestamp:
            ISO8601DateFormatter().string(from: timestamp.dateValue())
        case nil, is NSNull:
            nil
        default:
            value.map { String(describing: $0) }
        }
    }

    private func defaultSeverity(for type: AppNotificationType) -> AppNotificationSeverity {
        switch type {
        case .organizationRequestApproved:
            .success
        case .organizationRequestNeedsRevision, .organizationRequestRejected, .accountStatusChanged, .eventCancelled:
            .warning
        case .legalDocumentsUpdated, .systemAnnouncement:
            .critical
        case .contentDraftReady:
            .info
        case .organizationRequestSubmitted, .commentAdded, .contentModerationChanged, .eventParticipationChanged, .feedbackSubmitted, .feedbackReply, .roleChanged, .organizationRoleAssigned, .organizationRoleRemoved, .reportReviewed, .eventUpdated, .eventRegistrationConfirmed, .organizationNewsPublished, .organizationEventPublished, .unknown:
            .info
        }
    }

    private func defaultActionType(for type: AppNotificationType) -> AppNotificationActionType {
        switch type {
        case .feedbackSubmitted, .feedbackReply:
            .openFeedback
        case .organizationRequestSubmitted, .organizationRequestApproved, .organizationRequestNeedsRevision, .organizationRequestRejected:
            .openOrganizationRequest
        case .organizationRoleAssigned, .organizationRoleRemoved:
            .openOrganization
        case .eventUpdated, .eventCancelled, .eventRegistrationConfirmed, .organizationEventPublished:
            .openEvent
        case .organizationNewsPublished:
            .openNews
        case .reportReviewed:
            .none
        case .legalDocumentsUpdated:
            .openLegalDocuments
        case .accountStatusChanged, .roleChanged:
            .openProfile
        case .contentDraftReady:
            .openContentPlanning
        case .commentAdded, .contentModerationChanged, .eventParticipationChanged, .systemAnnouncement, .unknown:
            .none
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
}
