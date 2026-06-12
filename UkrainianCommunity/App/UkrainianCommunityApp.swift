import FirebaseAuth
import FirebaseCore
import SwiftUI
import UIKit
import UserNotifications

private enum FirebaseBootstrap {
    private static var isConfigured = false

    static func ensureConfigured() {
        if !isConfigured {
            FirebaseConfiguration.shared.setLoggerLevel(.min)
            FirebaseApp.configure()
            isConfigured = true
        }
    }
}

private final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        if let userInfo = launchOptions?[.remoteNotification] as? [AnyHashable: Any],
           let route = RemoteNotificationRoute(userInfo: userInfo) {
            Task { @MainActor in
                RemoteNotificationRouteCoordinator.shared.receive(route)
            }
        }
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let route = RemoteNotificationRoute(
            userInfo: response.notification.request.content.userInfo
        ) else {
            return
        }

        RemoteNotificationRouteCoordinator.shared.receive(route)
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            RemoteNotificationRegistrationService.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            RemoteNotificationRegistrationService.shared.didFailToRegisterForRemoteNotifications(error)
        }
    }
}

@main
struct UkrainianCommunityApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var authState = AuthService.shared.authState
    private let container: AppContainer

    init() {
        let processInfo = ProcessInfo.processInfo
        let isUITesting = processInfo.arguments.contains("-ui-testing")
        let environment = ProcessInfo.processInfo.environment

        FirebaseBootstrap.ensureConfigured()

        if isUITesting {
            container = .uiTesting
        } else {
            container = .development
        }

        let shouldForceGuestSession = environment["UITestForceGuestSession"] == "1"
        let shouldForceAuthenticatedSession = environment["UITestForceAuthenticatedSession"] == "1"
        let sharedAuthState = AuthService.shared.authState

        if shouldForceGuestSession {
            try? Auth.auth().signOut()
        }

        Task { @MainActor in
            if shouldForceAuthenticatedSession {
                sharedAuthState.user = MockContentBuilder.currentUser()
                sharedAuthState.setAuthenticatedSession()
            } else if shouldForceGuestSession {
                sharedAuthState.setGuestSession()
            } else {
                await AuthService.shared.restoreSession()
            }
        }

        if environment["UITestResetUserSettings"] == "1" {
            AppLanguage.stored = .german
            AppAppearance.stored = .system
        }

        if let languageCode = environment["UITestAppLanguage"],
           let language = AppLanguage(rawValue: languageCode) {
            AppLanguage.stored = language
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(container: container)
                .environmentObject(authState)
        }
    }
}
