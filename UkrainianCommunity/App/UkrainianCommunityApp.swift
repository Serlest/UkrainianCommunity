import DeviceCheck
import FirebaseAuth
import FirebaseAppCheck
import FirebaseCore
import SwiftUI
import UIKit
import UserNotifications

/// UI tests launch the real app explicitly; hosted unit tests need no app services.
enum AppTestHost {
    static var isUnitTesting: Bool {
        isUnitTesting(
            arguments: ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment,
            hasXCTestCase: NSClassFromString("XCTestCase") != nil
        )
    }

    static func isUnitTesting(
        arguments: [String], environment: [String: String], hasXCTestCase: Bool
    ) -> Bool {
        guard !arguments.contains("-ui-testing") else { return false }
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || hasXCTestCase
    }
}

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
        guard !AppTestHost.isUnitTesting else { return true }
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
        guard !AppTestHost.isUnitTesting else { return [] }
        return [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard !AppTestHost.isUnitTesting else { return }
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
        guard !AppTestHost.isUnitTesting else { return }
        Task { @MainActor in
            RemoteNotificationRegistrationService.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        guard !AppTestHost.isUnitTesting else { return }
        Task { @MainActor in
            RemoteNotificationRegistrationService.shared.didFailToRegisterForRemoteNotifications(error)
        }
    }
}

@main
struct UkrainianCommunityApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var authState: AuthState
    @Environment(\.scenePhase) private var scenePhase
    @State private var presence = UserPresenceService()
    private let container: AppContainer?

    private var presenceUserID: String? {
        guard !ProcessInfo.processInfo.arguments.contains("-ui-testing"),
              !AppTestHost.isUnitTesting,
              authState.isAuthenticated, PermissionService.isUsableAccount(user: authState.user) else { return nil }
        return authState.user?.id
    }

    init() {
        let processInfo = ProcessInfo.processInfo
        let isUITesting = processInfo.arguments.contains("-ui-testing")
        let environment = ProcessInfo.processInfo.environment

        if AppTestHost.isUnitTesting {
            // Do not construct live repositories, restore Auth, or mount AppStartupGate.
            // The opt-in SDK journey still configures only its fixed local demo project.
#if DEBUG && targetEnvironment(simulator)
            _ = LocalFirebaseEmulatorConfiguration.configureIfRequested()
#endif
            _authState = StateObject(wrappedValue: AuthState())
            container = nil
            return
        }

        FirebaseBootstrap.ensureConfigured()
        _authState = StateObject(wrappedValue: AuthService.shared.authState)

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
            if let container {
                AppStartupGate(container: container)
                    .environmentObject(authState)
                    .onChange(of: presenceUserID, initial: true) { _, userID in
                        presence.update(userID: userID, isActive: scenePhase == .active)
                    }
            } else {
                Color.clear
            }
        }
        .onChange(of: scenePhase) { _, phase in
            presence.update(userID: presenceUserID, isActive: phase == .active)
        }
    }
}
