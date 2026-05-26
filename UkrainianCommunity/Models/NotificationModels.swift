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
}

enum AppNotificationSourceType: String, Codable {
    case feedback
    case organization
}

struct AppNotification: Identifiable, Codable, Equatable {
    let id: String
    let recipientUserId: String
    let type: AppNotificationType
    let sourceType: AppNotificationSourceType
    let sourceId: String
    let actorUserId: String?
    let actorDisplayName: String?
    let payload: [String: String]
    let isRead: Bool
    let readAt: Date?
    let createdAt: Date
}
