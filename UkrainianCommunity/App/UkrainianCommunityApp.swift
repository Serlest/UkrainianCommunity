import FirebaseAppCheck
import FirebaseCore
import SwiftUI
import UIKit
import UserNotifications

private enum FirebaseBootstrap {
    private static var isConfigured = false

    static func ensureConfigured() {
        if !isConfigured {
            FirebaseConfiguration.shared.setLoggerLevel(.min)
            configureAppCheck()
            FirebaseApp.configure()
            isConfigured = true
        }
    }

    private static func configureAppCheck() {
#if DEBUG
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
#else
        AppCheck.setAppCheckProviderFactory(ProductionAppCheckProviderFactory())
#endif
    }
}

private final class ProductionAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        AppAttestProvider(app: app)
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
    @StateObject private var authState: AuthState
    private let container: AppContainer

    init() {
        let processInfo = ProcessInfo.processInfo
        let isUITesting = processInfo.arguments.contains("-ui-testing")
        let environment = processInfo.environment
        let shouldForceAuthenticatedSession = environment["UITestForceAuthenticatedSession"] == "1"

        if environment["UITestResetUserSettings"] == "1" {
            AppLanguage.stored = .german
            AppAppearance.stored = .system
        }

        if let languageCode = environment["UITestAppLanguage"],
           let language = AppLanguage(rawValue: languageCode) {
            AppLanguage.stored = language
        }

        let resolvedContainer: AppContainer
        if isUITesting {
            let testAuthState: AuthState
            if shouldForceAuthenticatedSession {
                testAuthState = AuthState(
                    user: MockContentBuilder.currentUser(),
                    sessionState: .authenticated
                )
            } else {
                testAuthState = AuthState(sessionState: .guest)
            }
            resolvedContainer = .uiTesting(authState: testAuthState)
        } else {
            FirebaseBootstrap.ensureConfigured()
            resolvedContainer = .development
        }

        container = resolvedContainer
        _authState = StateObject(wrappedValue: resolvedContainer.authState)

        if !isUITesting {
            Task { @MainActor in
                await AuthService.shared.restoreSession()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            AppStartupGate(container: container)
                .environmentObject(authState)
        }
    }
}
