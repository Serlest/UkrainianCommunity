import Foundation
import UserNotifications

protocol NotificationPermissionServiceProtocol {
    func requestNotificationAuthorization() async throws -> Bool
}

struct NotificationPermissionService: NotificationPermissionServiceProtocol {
    func requestNotificationAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }
}

struct MockNotificationPermissionService: NotificationPermissionServiceProtocol {
    var isGranted = true

    func requestNotificationAuthorization() async throws -> Bool {
        isGranted
    }
}
