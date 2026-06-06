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
    case feedbackSubmitted
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
    case unknown
}

enum AppNotificationSourceType: String, Codable {
    case feedback
    case organization
    case account
    case legal
    case role
    case profile
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
    let title: String?
    let message: String?
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
        title: String? = nil,
        message: String? = nil,
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
        self.title = title
        self.message = message
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
            title: title,
            message: message,
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
            title: title,
            message: message,
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
            title: title,
            message: message,
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

    nonisolated func updatingPopupPresentedState(popupPresentedAt: Date?) -> AppNotification {
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
            title: title,
            message: message,
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

struct AppNotificationDisplayContent: Equatable {
    let title: String
    let body: String
}

extension AppNotification {
    var localizedDisplayContent: AppNotificationDisplayContent {
        AppNotificationDisplayResolver.content(for: self)
    }
}

private enum AppNotificationDisplayResolver {
    static func content(for notification: AppNotification) -> AppNotificationDisplayContent {
        switch notification.type {
        case .systemAnnouncement, .unknown:
            return AppNotificationDisplayContent(
                title: firstNonEmpty(notification.title) ?? AppStrings.NotificationInbox.systemAnnouncementTitle,
                body: firstNonEmpty(notification.message, notification.metadata["message"], notification.payload["message"])
                    ?? AppStrings.NotificationInbox.genericBody
            )
        case .feedbackSubmitted:
            return AppNotificationDisplayContent(
                title: AppStrings.NotificationInbox.feedbackSubmittedTitle,
                body: firstNonEmpty(localizedFeedbackSubject(for: notification), notification.payload["messagePreview"])
                    ?? AppStrings.NotificationInbox.feedbackSubmittedBody
            )
        case .feedbackReply:
            return AppNotificationDisplayContent(
                title: AppStrings.NotificationInbox.feedbackReplyTitle,
                body: firstNonEmpty(localizedFeedbackSubject(for: notification), notification.payload["messagePreview"])
                    ?? AppStrings.NotificationInbox.feedbackReplyBody
            )
        case .organizationRequestApproved:
            return AppNotificationDisplayContent(
                title: AppStrings.NotificationInbox.organizationApprovedTitle,
                body: AppStrings.NotificationInbox.organizationApprovedBody(organizationName(for: notification))
            )
        case .organizationRequestNeedsRevision:
            return AppNotificationDisplayContent(
                title: AppStrings.NotificationInbox.organizationNeedsRevisionTitle,
                body: firstNonEmpty(notification.payload["reviewMessage"], notification.metadata["reviewMessage"])
                    ?? AppStrings.NotificationInbox.organizationNeedsRevisionBody(organizationName(for: notification))
            )
        case .organizationRequestRejected:
            return AppNotificationDisplayContent(
                title: AppStrings.NotificationInbox.organizationRejectedTitle,
                body: firstNonEmpty(notification.payload["rejectionReason"], notification.metadata["rejectionReason"])
                    ?? AppStrings.NotificationInbox.organizationRejectedBody(organizationName(for: notification))
            )
        case .accountStatusChanged:
            return AppNotificationDisplayContent(
                title: AppStrings.NotificationInbox.accountStatusChangedTitle,
                body: AppStrings.NotificationInbox.genericBody
            )
        case .legalDocumentsUpdated:
            return genericContent(title: AppStrings.NotificationInbox.legalDocumentsUpdatedTitle)
        case .roleChanged:
            return genericContent(title: AppStrings.NotificationInbox.roleChangedTitle)
        case .organizationRoleAssigned:
            return genericContent(title: AppStrings.NotificationInbox.organizationRoleAssignedTitle)
        case .organizationRoleRemoved:
            return genericContent(title: AppStrings.NotificationInbox.organizationRoleRemovedTitle)
        case .reportReviewed:
            return genericContent(title: AppStrings.NotificationInbox.reportReviewedTitle)
        case .eventUpdated:
            return genericContent(title: AppStrings.NotificationInbox.eventUpdatedTitle)
        case .eventCancelled:
            return genericContent(title: AppStrings.NotificationInbox.eventCancelledTitle)
        case .guideMaterialUpdated:
            return genericContent(title: AppStrings.NotificationInbox.guideMaterialUpdatedTitle)
        }
    }

    private static func genericContent(title: String) -> AppNotificationDisplayContent {
        AppNotificationDisplayContent(title: title, body: AppStrings.NotificationInbox.genericBody)
    }

    private static func organizationName(for notification: AppNotification) -> String {
        firstNonEmpty(notification.payload["organizationName"], notification.metadata["organizationName"])
            ?? AppStrings.Common.notAvailable
    }

    private static func localizedFeedbackSubject(for notification: AppNotification) -> String? {
        guard let subject = firstNonEmpty(notification.payload["subject"], notification.metadata["subject"]) else {
            return nil
        }

        return FeedbackType(rawValue: subject)?.title ?? subject
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values.lazy
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}
