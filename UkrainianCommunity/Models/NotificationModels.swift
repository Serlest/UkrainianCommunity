import Foundation

struct NotificationPreferences: Codable, Equatable {
    var notificationsEnabled: Bool
    var eventRemindersEnabled: Bool
    var reminderLeadMinutes: Int
    var updatedAt: Date?

    nonisolated static let `default` = NotificationPreferences(
        notificationsEnabled: false,
        eventRemindersEnabled: true,
        reminderLeadMinutes: 60,
        updatedAt: nil
    )
}

enum AppNotificationType: String, Codable, CaseIterable {
    case feedbackReply
    case organizationRequestApproved
    case organizationRequestNeedsRevision
    case organizationRequestRejected
    case accountStatusChanged
    case legalDocumentsUpdated
    case roleChanged
    case organizationRoleAssigned
    case organizationRoleRemoved
    case reportReviewed
    case eventUpdated
    case eventCancelled
    case guideMaterialUpdated
    case systemAnnouncement
}

enum AppNotificationSourceType: String, Codable {
    case feedback
    case organization
    case account
    case legal
    case role
    case event
    case guideMaterial
    case guideReport
    case system
}

enum AppNotificationSeverity: String, Codable, CaseIterable {
    case info
    case success
    case warning
    case critical
}

enum AppNotificationActionType: String, Codable, CaseIterable {
    case none
    case openFeedback
    case openOrganization
    case openOrganizationRequest
    case openEvent
    case openGuideMaterial
    case openGuideReport
    case openLegalDocuments
    case openProfile
    case openURL
}

struct AppNotification: Identifiable, Codable, Equatable {
    let id: String
    let recipientUserId: String
    let type: AppNotificationType
    let sourceType: AppNotificationSourceType
    let sourceId: String
    let severity: AppNotificationSeverity
    let actionType: AppNotificationActionType
    let actionTargetId: String?
    let requiresPopup: Bool
    let popupPresentedAt: Date?
    let expiresAt: Date?
    let archivedAt: Date?
    let deletedAt: Date?
    let metadata: [String: String]
    let actorUserId: String?
    let actorDisplayName: String?
    let dedupeKey: String?
    let payload: [String: String]
    let isRead: Bool
    let readAt: Date?
    let createdAt: Date

    nonisolated init(
        id: String,
        recipientUserId: String,
        type: AppNotificationType,
        sourceType: AppNotificationSourceType,
        sourceId: String,
        severity: AppNotificationSeverity = .info,
        actionType: AppNotificationActionType = .none,
        actionTargetId: String? = nil,
        requiresPopup: Bool = false,
        popupPresentedAt: Date? = nil,
        expiresAt: Date? = nil,
        archivedAt: Date? = nil,
        deletedAt: Date? = nil,
        metadata: [String: String] = [:],
        actorUserId: String? = nil,
        actorDisplayName: String? = nil,
        dedupeKey: String? = nil,
        payload: [String: String],
        isRead: Bool,
        readAt: Date?,
        createdAt: Date
    ) {
        self.id = id
        self.recipientUserId = recipientUserId
        self.type = type
        self.sourceType = sourceType
        self.sourceId = sourceId
        self.severity = severity
        self.actionType = actionType
        self.actionTargetId = actionTargetId
        self.requiresPopup = requiresPopup
        self.popupPresentedAt = popupPresentedAt
        self.expiresAt = expiresAt
        self.archivedAt = archivedAt
        self.deletedAt = deletedAt
        self.metadata = metadata
        self.actorUserId = actorUserId
        self.actorDisplayName = actorDisplayName
        self.dedupeKey = dedupeKey
        self.payload = payload
        self.isRead = isRead
        self.readAt = readAt
        self.createdAt = createdAt
    }

    nonisolated var isArchived: Bool {
        archivedAt != nil
    }

    nonisolated var isDeleted: Bool {
        deletedAt != nil
    }

    nonisolated var isVisibleInInbox: Bool {
        deletedAt == nil
    }

    nonisolated var countsAsUnread: Bool {
        !isRead && archivedAt == nil && deletedAt == nil
    }

    nonisolated func updatingReadState(isRead: Bool, readAt: Date?) -> AppNotification {
        AppNotification(
            id: id,
            recipientUserId: recipientUserId,
            type: type,
            sourceType: sourceType,
            sourceId: sourceId,
            severity: severity,
            actionType: actionType,
            actionTargetId: actionTargetId,
            requiresPopup: requiresPopup,
            popupPresentedAt: popupPresentedAt,
            expiresAt: expiresAt,
            archivedAt: archivedAt,
            deletedAt: deletedAt,
            metadata: metadata,
            actorUserId: actorUserId,
            actorDisplayName: actorDisplayName,
            dedupeKey: dedupeKey,
            payload: payload,
            isRead: isRead,
            readAt: readAt,
            createdAt: createdAt
        )
    }

    nonisolated func updatingArchiveState(archivedAt: Date?) -> AppNotification {
        AppNotification(
            id: id,
            recipientUserId: recipientUserId,
            type: type,
            sourceType: sourceType,
            sourceId: sourceId,
            severity: severity,
            actionType: actionType,
            actionTargetId: actionTargetId,
            requiresPopup: requiresPopup,
            popupPresentedAt: popupPresentedAt,
            expiresAt: expiresAt,
            archivedAt: archivedAt,
            deletedAt: deletedAt,
            metadata: metadata,
            actorUserId: actorUserId,
            actorDisplayName: actorDisplayName,
            dedupeKey: dedupeKey,
            payload: payload,
            isRead: isRead,
            readAt: readAt,
            createdAt: createdAt
        )
    }

    nonisolated func updatingDeleteState(deletedAt: Date?) -> AppNotification {
        AppNotification(
            id: id,
            recipientUserId: recipientUserId,
            type: type,
            sourceType: sourceType,
            sourceId: sourceId,
            severity: severity,
            actionType: actionType,
            actionTargetId: actionTargetId,
            requiresPopup: requiresPopup,
            popupPresentedAt: popupPresentedAt,
            expiresAt: expiresAt,
            archivedAt: archivedAt,
            deletedAt: deletedAt,
            metadata: metadata,
            actorUserId: actorUserId,
            actorDisplayName: actorDisplayName,
            dedupeKey: dedupeKey,
            payload: payload,
            isRead: isRead,
            readAt: readAt,
            createdAt: createdAt
        )
    }
}
