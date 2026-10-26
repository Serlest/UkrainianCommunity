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

    func fetchNotification(userID: String, notificationID: String) async throws -> AppNotification {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            try await NotificationAuditFailureFixture.shared.check(receipt: false)
        }
        #endif
        guard let item = await store.notifications(userID: userID, limit: Int.max).first(where: { $0.id == notificationID && $0.isVisibleInInbox }) else { throw AppError.notFound }
        return item
    }

    func fetchNotifications(userID: String, limit: Int) async throws -> [AppNotification] {
        await store.notifications(userID: userID, limit: limit)
    }

    func listenNotifications(
        userID: String,
        limit: Int,
        onChange: @escaping @MainActor ([AppNotification]) -> Void,
        onError: @escaping @MainActor (AppError) -> Void
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
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            try await NotificationAuditFailureFixture.shared.check(receipt: true)
        }
        #endif
        await store.markNotificationRead(userID: userID, notificationID: notificationID)
    }

    func markNotificationUnread(userID: String, notificationID: String) async throws {
        await store.markNotificationUnread(userID: userID, notificationID: notificationID)
    }

    func markAllNotificationsRead(userID: String) async throws {
        await store.markAllNotificationsRead(userID: userID)
    }

    func markNotificationPopupPresented(userID: String, notificationID: String) async throws {
        await store.markNotificationPopupPresented(userID: userID, notificationID: notificationID)
    }

    func restoreNotification(userID: String, notificationID: String) async throws {
        await store.restoreNotification(userID: userID, notificationID: notificationID)
    }

    func archiveNotification(userID: String, notificationID: String) async throws {
        await store.archiveNotification(userID: userID, notificationID: notificationID)
    }

    func deleteNotification(userID: String, notificationID: String) async throws {
        await store.deleteNotification(userID: userID, notificationID: notificationID)
    }

    func clearNotifications(userID: String) async throws {
        await store.clearNotifications(userID: userID)
    }

    func createNotification(userID: String, notification: AppNotification) async throws {
        await store.createNotification(notification, userID: userID)
    }
}

#if DEBUG && targetEnvironment(simulator)
private actor NotificationAuditFailureFixture {
    static let shared = NotificationAuditFailureFixture()
    private var detailAttempts = 0
    private var receiptAttempts = 0
    func check(receipt: Bool) async throws {
        let mode = ProcessInfo.processInfo.environment["UITestNotificationFailure"]
        guard mode != nil else { return }
        if receipt {
            receiptAttempts += 1
            if mode == "receiptOnce" && receiptAttempts == 1 { throw AppError.network }
        } else {
            detailAttempts += 1
            try await Task.sleep(for: .milliseconds(500))
            if mode == "missing" { throw AppError.notFound }
            if mode == "networkOnce" && detailAttempts == 1 { throw AppError.network }
        }
    }
}
#endif

struct MockNotificationPushTokenRepository: NotificationPushTokenRepository {
    func saveCurrentDeviceRegistration(
        userID: String,
        registration: NotificationPushRegistration
    ) async throws {}

    func deleteCurrentDeviceRegistration(
        userID: String,
        registration: NotificationPushRegistration
    ) async throws {}
}
