import Foundation
import FirebaseFirestore
import FirebaseAuth

struct FirestoreNotificationInboxRepository: NotificationInboxRepository {
    private let database = Firestore.firestore()

    func fetchNotification(userID: String, notificationID: String) async throws -> AppNotification {
        do {
            let snapshot = try await inboxCollection(userID: userID).document(notificationID).getDocument(source: .server)
            guard snapshot.exists else { throw AppError.notFound }
            let item = makeNotification(from: snapshot)
            guard item.isVisibleInInbox else { throw AppError.notFound }
            return item
        } catch let error as AppError { throw error }
        catch { throw FirebaseReadErrorMapper.map(error) }
    }

    private func pageQuery(userID: String, unreadOnly: Bool, limit: Int, after: NotificationInboxCursor?) -> Query {
        var query: Query = inboxCollection(userID: userID)
        if unreadOnly { query = query.whereField("isRead", isEqualTo: false) }
        query = query.order(by: "createdAt", descending: true)
            .order(by: FieldPath.documentID(), descending: true)
            .limit(to: max(1, limit) + 1)
        if let after {
            query = query.start(after: [after.exactTimestamp?.firestoreTimestamp ?? Timestamp(date: after.createdAt), after.documentID])
        }
        return query
    }

    private func page(_ documents: [QueryDocumentSnapshot], limit: Int) -> NotificationInboxPage {
        let selected = Array(documents.prefix(max(1, limit)))
        let cursor = selected.last.flatMap { document -> NotificationInboxCursor? in
            guard let timestamp = document.data()["createdAt"] as? Timestamp else { return nil }
            return NotificationInboxCursor(createdAt: timestamp.dateValue(), documentID: document.documentID,
                                           exactTimestamp: PageCursorTimestamp(timestamp))
        }
        return NotificationInboxPage(items: selected.map(makeNotification), nextCursor: cursor,
                                     hasMore: documents.count > limit && cursor != nil)
    }

    func fetchNotificationPage(userID: String, unreadOnly: Bool, limit: Int, after: NotificationInboxCursor?) async throws -> NotificationInboxPage {
        do {
            let snapshot = try await pageQuery(userID: userID, unreadOnly: unreadOnly, limit: limit, after: after).getDocuments()
            return page(snapshot.documents, limit: limit)
        } catch { throw FirebaseReadErrorMapper.map(error) }
    }

    func listenNotificationHead(userID: String, limit: Int,
        onChange: @escaping @MainActor (NotificationInboxPage) -> Void,
        onError: @escaping @MainActor (AppError) -> Void) -> AppRealtimeListener {
        let registration = pageQuery(userID: userID, unreadOnly: false, limit: limit, after: nil)
            .addSnapshotListener { snapshot, error in
                if let error {
                    Self.logListenerFailure(error, listenerName: "notificationInbox", userID: userID)
                    Task { @MainActor in onError(Self.appError(from: error)) }
                    return
                }
                let result = page(snapshot?.documents ?? [], limit: limit)
                Task { @MainActor in onChange(result) }
            }
        return FirebaseRealtimeListener(registration)
    }

    func restoreNotification(userID: String, notificationID: String) async throws {
        try await inboxCollection(userID: userID).document(notificationID).updateData([
            "archivedAt": NSNull(), "isRead": true, "readAt": FieldValue.serverTimestamp()
        ])
    }

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

    func fetchUnreadCount(userID: String) async throws -> Int {
        do {
            let query = inboxCollection(userID: userID)
                .whereField("isRead", isEqualTo: false)
                .whereField("archivedAt", isEqualTo: NSNull())
                .whereField("deletedAt", isEqualTo: NSNull())
            let snapshot = try await query.count.getAggregation(source: .server)
            return snapshot.count.intValue
        } catch {
            if Task.isCancelled || error is CancellationError {
                throw CancellationError()
            }
            Self.logUnreadCountFailure(error, userID: userID)
            throw FirebaseReadErrorMapper.map(error)
        }
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
            "archivedAt": NSNull(),
            "readAt": FieldValue.delete()
        ])
    }

    func markAllNotificationsRead(userID: String) async throws {
        try await updateExistingPages(userID: userID, unreadOnly: true, deleting: false)
    }

    func markNotificationPopupPresented(userID: String, notificationID: String) async throws {
        try await inboxCollection(userID: userID).document(notificationID).updateData([
            "popupPresentedAt": FieldValue.serverTimestamp()
        ])
    }

    func archiveNotification(userID: String, notificationID: String) async throws {
        try await inboxCollection(userID: userID).document(notificationID).updateData([
            "archivedAt": FieldValue.serverTimestamp(),
            "isRead": true,
            "readAt": FieldValue.serverTimestamp()
        ])
    }

    func deleteNotification(userID: String, notificationID: String) async throws {
        try await inboxCollection(userID: userID).document(notificationID).updateData([
            "deletedAt": FieldValue.serverTimestamp(),
            "isRead": true,
            "readAt": FieldValue.serverTimestamp()
        ])
    }

    func clearNotifications(userID: String) async throws {
        try await updateExistingPages(userID: userID, unreadOnly: false, deleting: true)
    }

    /// Bounded reads/writes; the cutoff protects notifications arriving during the operation.
    private func updateExistingPages(userID: String, unreadOnly: Bool, deleting: Bool) async throws {
        let cutoff = Date()
        var cursor: DocumentSnapshot?
        while true {
            try Task.checkCancellation()
            var query: Query = inboxCollection(userID: userID)
            if unreadOnly { query = query.whereField("isRead", isEqualTo: false) }
            query = query.order(by: FieldPath.documentID()).limit(to: 450)
            if let cursor { query = query.start(afterDocument: cursor) }
            let documents = try await query.getDocuments().documents
            guard !documents.isEmpty else { return }
            let batch = database.batch()
            var writes = 0
            for document in documents {
                let item = makeNotification(from: document)
                guard item.createdAt <= cutoff,
                      (deleting ? item.isVisibleInInbox : item.countsAsUnread) else { continue }
                var fields: [String: Any] = ["isRead": true, "readAt": FieldValue.serverTimestamp()]
                if deleting { fields["deletedAt"] = FieldValue.serverTimestamp() }
                batch.updateData(fields, forDocument: document.reference)
                writes += 1
            }
            if writes > 0 { try await batch.commit() }
            cursor = documents.last
            if documents.count < 450 { return }
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
            // A callback from an old inbox must not be attributed to the newly signed-in account.
            guard Auth.auth().currentUser?.uid == userID else { return }
            await SystemTechnicalErrorLoggingService.shared.logFailure(
                error,
                context: SystemTechnicalErrorContext(
                    moduleName: "Notifications",
                    operationName: "listenNotifications",
                    targetType: .notification,
                    targetId: userID,
                    metadata: [
                        "failureStage": "listenServerUpdates",
                        "listenerName": listenerName,
                        "pathGroup": "users/{userID}/notificationInbox"
                    ],
                    principalID: userID
                )
            )
        }
    }

    private static func logUnreadCountFailure(_ error: Error, userID: String) {
        Task {
            guard Auth.auth().currentUser?.uid == userID else { return }
            await SystemTechnicalErrorLoggingService.shared.logFailure(
                error,
                context: SystemTechnicalErrorContext(
                    moduleName: "Notifications",
                    operationName: "fetchUnreadCount",
                    targetType: .notification,
                    targetId: userID,
                    metadata: [
                        "pathGroup": "users/{userID}/notificationInbox",
                        "queryKind": "serverAggregation",
                        "failureStage": "readServerAggregation"
                    ],
                    principalID: userID
                )
            )
        }
    }

    private func makeNotification(from document: DocumentSnapshot) -> AppNotification {
        let data = document.data() ?? [:]
        let type = (data["type"] as? String).flatMap(AppNotificationType.init(rawValue:)) ?? .unknown
        let sourceType = (data["sourceType"] as? String).flatMap(AppNotificationSourceType.init(rawValue:)) ?? .system
        let severity = (data["severity"] as? String).flatMap(AppNotificationSeverity.init(rawValue:)) ?? defaultSeverity(for: type)
        let actionType = (data["actionType"] as? String).flatMap(AppNotificationActionType.init(rawValue:)) ?? defaultActionType(for: type)
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let readAt = (data["readAt"] as? Timestamp)?.dateValue()

        return AppNotification(
            id: document.documentID,
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
        case .organizationRequestNeedsRevision, .organizationRequestRejected, .organizationRequestCleanupWarning, .organizationRequestExpired, .accountStatusChanged, .eventCancelled:
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
        case .organizationRequestSubmitted, .organizationRequestApproved, .organizationRequestNeedsRevision, .organizationRequestRejected, .organizationRequestCleanupWarning:
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
        case .accountStatusChanged, .roleChanged, .organizationRequestExpired:
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
