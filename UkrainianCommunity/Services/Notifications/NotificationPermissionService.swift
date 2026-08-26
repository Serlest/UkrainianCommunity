import Foundation
import UserNotifications

protocol NotificationPermissionServiceProtocol {
    func requestNotificationAuthorization() async throws -> Bool
}

struct NotificationPermissionService: NotificationPermissionServiceProtocol {
    func requestNotificationAuthorization() async throws -> Bool {
        try await RemoteNotificationRegistrationService.shared.requestAuthorizationAndRegister()
    }
}

struct MockNotificationPermissionService: NotificationPermissionServiceProtocol {
    var isGranted = true

    func requestNotificationAuthorization() async throws -> Bool {
        isGranted
    }
}

@MainActor
protocol NotificationBadgeUpdating {
    func setCount(_ count: Int)
}

struct SystemNotificationBadgeUpdater: NotificationBadgeUpdating {
    func setCount(_ count: Int) {
        // Submit synchronously: UNUserNotificationCenter processes requests in order.
        // Creating independent Tasks here could let an older count overwrite logout's zero.
        UNUserNotificationCenter.current().setBadgeCount(max(0, count)) { error in
            if let error {
                NSLog("Notification badge update failed: %@", error.localizedDescription)
            }
        }
    }
}
