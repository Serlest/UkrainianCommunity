import Foundation

nonisolated enum NotificationAuditCopy {
    private static func text(_ key: String, _ fallback: String) -> String {
        LocalizationStore.localizedString("notification_audit." + key, defaultValue: fallback, table: "NotificationAudit")
    }
    static var reviewedContentChanged: String { text("review_changed", "The announcement changed. Review it again before sending.") }
    static var reload: String { text("reload", "Load saved version") }
    static var reloadTitle: String { text("reload_title", "Load the saved announcement?") }
    static var reloadMessage: String { text("reload_message", "The saved version will replace the edits currently shown in this form.") }
    static var loadingRecipient: String { text("loading_recipient", "Loading recipient…") }
    static var unnamedRecipient: String { text("unnamed_recipient", "User without a name") }
    static var unavailableTitle: String { text("unavailable_title", "Notification unavailable") }
    static var unavailableMessage: String { text("unavailable_message", "It may have been deleted, or you may no longer have access to this notification.") }
}
