import Foundation

struct MockNotificationPreferencesRepository: NotificationPreferencesRepository {
    private let store = MockRepositoryStore.shared

    func fetchNotificationPreferences(userID: String) async throws -> NotificationPreferences {
        await store.notificationPreferences(userID: userID)
    }

    func saveNotificationPreferences(_ preferences: NotificationPreferences, userID: String) async throws {
        await store.saveNotificationPreferences(preferences, userID: userID)
    }
}

private struct MockRealtimeListener: AppRealtimeListener {
    func cancel() {}
}

struct MockNotificationInboxRepository: NotificationInboxRepository {
    private let store = MockRepositoryStore.shared

    func fetchNotifications(userID: String, limit: Int) async throws -> [AppNotification] {
        await store.notifications(userID: userID, limit: limit)
    }

    func listenNotifications(
        userID: String,
        limit: Int,
        onChange: @escaping @MainActor ([AppNotification]) -> Void
    ) -> AppRealtimeListener {
        Task {
            let notifications = await store.notifications(userID: userID, limit: limit)
            await MainActor.run {
                onChange(notifications)
            }
        }
        return MockRealtimeListener()
    }

    func fetchUnreadCount(userID: String) async throws -> Int {
        await store.unreadNotificationCount(userID: userID)
    }

    func markNotificationRead(userID: String, notificationID: String) async throws {
        await store.markNotificationRead(userID: userID, notificationID: notificationID)
    }

    func markNotificationUnread(userID: String, notificationID: String) async throws {
        await store.markNotificationUnread(userID: userID, notificationID: notificationID)
    }

    func markAllNotificationsRead(userID: String) async throws {
        await store.markAllNotificationsRead(userID: userID)
    }

    func archiveNotification(userID: String, notificationID: String) async throws {
        await store.archiveNotification(userID: userID, notificationID: notificationID)
    }

    func deleteNotification(userID: String, notificationID: String) async throws {
        await store.deleteNotification(userID: userID, notificationID: notificationID)
    }

    func createNotification(userID: String, notification: AppNotification) async throws {
        await store.createNotification(notification, userID: userID)
    }
}
