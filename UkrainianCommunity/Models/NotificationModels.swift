import Combine
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

enum AppNotificationType: String, Codable, CaseIterable, Sendable {
    case feedbackSubmitted
    case feedbackReply
    case organizationRequestApproved
    case organizationRequestNeedsRevision
    case organizationRequestRejected
    case accountStatusChanged
    case legalDocumentsUpdated
    case organizationNewsPublished
    case organizationEventPublished
    case roleChanged
    case organizationRoleAssigned
    case organizationRoleRemoved
    case reportReviewed
    case eventUpdated
    case eventCancelled
    case eventRegistrationConfirmed
    case guideMaterialUpdated
    case systemAnnouncement
    case unknown
}

enum AppNotificationSourceType: String, Codable, Sendable {
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

enum AppNotificationActionType: String, Codable, CaseIterable, Sendable {
    case none
    case openNews
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

enum RemoteNotificationRouteDestination: Equatable, Sendable {
    case openNews(newsId: String)
    case openEvent(eventId: String)
    case openOrganization(organizationId: String)
    case openFeedback(feedbackId: String?)
    case openProfile
    case openURL(urlString: String)
    case systemAnnouncement
}

struct RemoteNotificationRoute: Equatable, Sendable {
    let notificationId: String?
    let type: AppNotificationType
    let sourceType: AppNotificationSourceType?
    let sourceId: String?
    let actionType: AppNotificationActionType
    let actionTargetId: String?
    let destination: RemoteNotificationRouteDestination

    init?(
        notificationId: String?,
        type: AppNotificationType,
        sourceType: AppNotificationSourceType?,
        sourceId: String?,
        actionType: AppNotificationActionType,
        actionTargetId: String?,
        route: String?,
        routeTargetId: String?
    ) {
        let resolvedRoute = Self.normalizedRoute(
            route: route,
            actionType: actionType,
            sourceType: sourceType
        )
        let resolvedTargetId = Self.firstNonEmpty(
            routeTargetId,
            actionTargetId,
            sourceId
        )

        guard let destination = Self.destination(
            route: resolvedRoute,
            targetId: resolvedTargetId
        ) else {
            return nil
        }

        self.notificationId = notificationId
        self.type = type
        self.sourceType = sourceType
        self.sourceId = sourceId
        self.actionType = actionType
        self.actionTargetId = actionTargetId
        self.destination = destination
    }

    init?(userInfo: [AnyHashable: Any]) {
        let notificationId = Self.stringValue(userInfo, keys: ["notificationId", "id"])
        let type = Self.stringValue(userInfo, keys: ["type"])
            .flatMap(AppNotificationType.init(rawValue:)) ?? .unknown
        let sourceType = Self.stringValue(userInfo, keys: ["sourceType"])
            .flatMap(AppNotificationSourceType.init(rawValue:))
        let sourceId = Self.stringValue(userInfo, keys: ["sourceId"])
        let actionType = Self.stringValue(userInfo, keys: ["actionType"])
            .flatMap(AppNotificationActionType.init(rawValue:)) ?? .none
        let actionTargetId = Self.stringValue(userInfo, keys: ["actionTargetId"])
        let route = Self.stringValue(userInfo, keys: ["route"])
        let routeTargetId = Self.stringValue(userInfo, keys: ["routeTargetId", "targetId", "targetID"])

        self.init(
            notificationId: notificationId,
            type: type,
            sourceType: sourceType,
            sourceId: sourceId,
            actionType: actionType,
            actionTargetId: actionTargetId,
            route: route,
            routeTargetId: routeTargetId
        )
    }

    private static func destination(
        route: String,
        targetId: String?
    ) -> RemoteNotificationRouteDestination? {
        switch route {
        case "openNews", "news":
            return targetId.map { .openNews(newsId: $0) }
        case "openEvent", "event":
            return targetId.map { .openEvent(eventId: $0) }
        case "openOrganization", "organization":
            return targetId.map { .openOrganization(organizationId: $0) }
        case "openFeedback", "feedback":
            return .openFeedback(feedbackId: targetId)
        case "openProfile", "profile":
            return .openProfile
        case "openURL", "url":
            return targetId.map { .openURL(urlString: $0) }
        case "systemAnnouncement", "announcement", "none":
            return .systemAnnouncement
        default:
            return nil
        }
    }

    private static func normalizedRoute(
        route: String?,
        actionType: AppNotificationActionType,
        sourceType: AppNotificationSourceType?
    ) -> String {
        if let route = firstNonEmpty(route) {
            return route
        }

        switch actionType {
        case .openNews:
            return "openNews"
        case .openEvent:
            return "openEvent"
        case .openOrganization, .openOrganizationRequest:
            return "openOrganization"
        case .openFeedback:
            return "openFeedback"
        case .openProfile:
            return "openProfile"
        case .openURL:
            return "openURL"
        case .openGuideMaterial, .openGuideReport, .openLegalDocuments:
            return actionType.rawValue
        case .none:
            switch sourceType {
            case .some(.event):
                return "openEvent"
            case .some(.organization):
                return "openOrganization"
            case .some(.feedback):
                return "openFeedback"
            case .some(.system):
                return "systemAnnouncement"
            case .some(.account), .some(.profile):
                return "openProfile"
            case .some(.guideMaterial), .some(.guideReport), .some(.legal), .some(.role), .none:
                return "none"
            }
        }
    }

    private static func stringValue(_ userInfo: [AnyHashable: Any], keys: [String]) -> String? {
        for key in keys {
            guard let value = userInfo[AnyHashable(key)] else { continue }
            if let string = value as? String,
               let nonEmpty = firstNonEmpty(string) {
                return nonEmpty
            }
            if let number = value as? NSNumber {
                return number.stringValue
            }
        }

        return nil
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values.lazy
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

@MainActor
final class RemoteNotificationRouteCoordinator: ObservableObject {
    static let shared = RemoteNotificationRouteCoordinator()

    @Published private(set) var pendingRoute: RemoteNotificationRoute?

    private init() {}

    func receive(_ route: RemoteNotificationRoute) {
        pendingRoute = route
    }

    func consume(_ route: RemoteNotificationRoute) {
        if pendingRoute == route {
            pendingRoute = nil
        }
    }
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
        case .eventRegistrationConfirmed:
            return AppNotificationDisplayContent(
                title: firstNonEmpty(notification.title) ?? AppStrings.NotificationInbox.title,
                body: firstNonEmpty(notification.message, notification.payload["eventTitle"], notification.metadata["eventTitle"])
                    ?? AppStrings.NotificationInbox.genericBody
            )
        case .organizationNewsPublished, .organizationEventPublished:
            return AppNotificationDisplayContent(
                title: firstNonEmpty(notification.title) ?? AppStrings.NotificationInbox.title,
                body: firstNonEmpty(notification.message, notification.payload["contentTitle"], notification.metadata["contentTitle"])
                    ?? AppStrings.NotificationInbox.genericBody
            )
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
