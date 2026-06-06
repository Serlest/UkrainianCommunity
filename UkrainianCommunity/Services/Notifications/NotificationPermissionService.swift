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
