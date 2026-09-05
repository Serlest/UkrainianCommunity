import DeviceCheck
import FirebaseAuth
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
#if DEBUG && targetEnvironment(simulator)
            if LocalFirebaseEmulatorConfiguration.configureIfRequested() {
                isConfigured = true
                return
            }
#endif
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
        if DCAppAttestService.shared.isSupported {
            return AppAttestProvider(app: app)
        }

        return DeviceCheckProvider(app: app)
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
    @Environment(\.scenePhase) private var scenePhase
    @State private var presence = UserPresenceService()
    private let container: AppContainer

    private var presenceUserID: String? {
        guard !ProcessInfo.processInfo.arguments.contains("-ui-testing"),
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              NSClassFromString("XCTestCase") == nil,
              authState.isAuthenticated, PermissionService.isUsableAccount(user: authState.user) else { return nil }
        return authState.user?.id
    }

    init() {
        let processInfo = ProcessInfo.processInfo
        let isUITesting = processInfo.arguments.contains("-ui-testing")
        let environment = ProcessInfo.processInfo.environment

        FirebaseBootstrap.ensureConfigured()

        if isUITesting {
            container = .uiTesting
        } else {
            container = .live
        }

        let shouldForceGuestSession = environment["UITestForceGuestSession"] == "1"
        let shouldForceAuthenticatedSession = environment["UITestForceAuthenticatedSession"] == "1"
        let shouldForceOwnerSession = environment["UITestForceOwnerSession"] == "1"
        let sharedAuthState = AuthService.shared.authState

        if shouldForceGuestSession {
            try? Auth.auth().signOut()
        }

        Task { @MainActor in
            if shouldForceOwnerSession {
#if DEBUG && targetEnvironment(simulator)
                let owner = MockContentBuilder.ownerUser(requiresMultiFactorAuth: isUITesting)
#else
                let owner = MockContentBuilder.ownerUser()
#endif
                sharedAuthState.setAuthenticatedSession(user: owner)
            } else if shouldForceAuthenticatedSession {
                sharedAuthState.setAuthenticatedSession(user: MockContentBuilder.currentUser())
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

        if isUITesting, environment["UITestResetContentDrafts"] == "1" {
            try? LocalDraftRecoveryService.shared.resetAllDraftsForUITesting()
        }

        if let languageCode = environment["UITestAppLanguage"],
           let language = AppLanguage(rawValue: languageCode) {
            AppLanguage.stored = language
        }

        if let appearanceCode = environment["UITestAppAppearance"],
           let appearance = AppAppearance(rawValue: appearanceCode) {
            AppAppearance.stored = appearance
        }
    }

    var body: some Scene {
        WindowGroup {
            AppStartupGate(container: container)
                .environmentObject(authState)
                .onChange(of: presenceUserID, initial: true) { _, userID in
                    presence.update(userID: userID, isActive: scenePhase == .active)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            presence.update(userID: presenceUserID, isActive: phase == .active)
        }
    }
}
