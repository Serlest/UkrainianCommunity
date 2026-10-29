import AppIntents
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
#if DEBUG && targetEnvironment(simulator)
        // Connected UI journeys use real forms/repositories, with every Firebase
        // transport pinned to the disposable demo project before construction.
        if arguments.contains("-sdk-ui-audit"), environment["UACFirebaseEmulators"] == "1" { return false }
#endif
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
        if await AnnouncementPushBridge.shared.receive(notification.request.content.userInfo) {
            let canPresent = AnnouncementPushBridge.shared.canPresentNotification
            return canPresent && notification.request.content.userInfo["announcementChallenge"] == nil
                ? [.banner, .list, .sound] : []
        }
        return [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard !AppTestHost.isUnitTesting else { return }
        if await AnnouncementPushBridge.shared.receive(response.notification.request.content.userInfo, userInitiated: true) { return }
        guard let route = RemoteNotificationRoute(
            userInfo: response.notification.request.content.userInfo
        ) else {
            return
        }

        RemoteNotificationRouteCoordinator.shared.receive(route)
    }

    nonisolated func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        let id = userInfo["announcementId"] as? String
        let challenge = userInfo["announcementChallenge"] as? String
        return await AnnouncementPushBridge.shared.receive(id: id, challenge: challenge) ? .newData : .noData
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
#if DEBUG && targetEnvironment(simulator)
        if processInfo.arguments.contains("-sdk-ui-audit") {
            precondition(environment["UACFirebaseEmulators"] == "1" && !isUITesting,
                         "Connected audit must use local emulators without fixture UI mode")
        }
#endif

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
        if !isUITesting { _ = SystemLogDeliveryQueue.shared }
        _authState = StateObject(wrappedValue: AuthService.shared.authState)

        if isUITesting {
            container = .uiTesting
        } else {
            container = .live(authState: AuthService.shared.authState)
        }

        let shouldForceGuestSession = environment["UITestForceGuestSession"] == "1"
        let shouldForceSignedOutSession = isUITesting && environment["UITestForceSignedOutSession"] == "1"
        let shouldForceAuthenticatedSession = environment["UITestForceAuthenticatedSession"] == "1"
        let shouldForceOwnerSession = environment["UITestForceOwnerSession"] == "1"
        let sharedAuthState = AuthService.shared.authState

        if shouldForceGuestSession || shouldForceSignedOutSession {
            try? Auth.auth().signOut()
        }

        Task { @MainActor in
#if DEBUG && targetEnvironment(simulator)
            await LocalFirebaseEmulatorConfiguration.prepareModerationReviewerFixtureIfRequested()
#endif
            if isUITesting, environment["UITestColdStartConnectionFailure"] == "1" {
                await AuthService.shared.restoreSession()
            } else if let fixture = MockContentBuilder.profileRoleFixture() {
                sharedAuthState.setAuthenticatedSession(user: fixture)
            } else if shouldForceOwnerSession {
#if DEBUG && targetEnvironment(simulator)
                let owner = MockContentBuilder.ownerUser(requiresMultiFactorAuth: isUITesting)
#else
                let owner = MockContentBuilder.ownerUser()
#endif
                sharedAuthState.setAuthenticatedSession(user: owner)
            } else if shouldForceAuthenticatedSession {
                sharedAuthState.setAuthenticatedSession(user: MockContentBuilder.currentUser())
            } else if shouldForceGuestSession || shouldForceSignedOutSession {
                sharedAuthState.setGuestSession()
            } else {
                await AuthService.shared.restoreSession()
            }
#if DEBUG && targetEnvironment(simulator)
            if isUITesting, environment["UITestStartupSecurityDelay"] == "1" {
                await AuthService.shared.refreshPrivilegedMultiFactorRequirement()
            }
            if isUITesting, environment["UITestStartupSecurityBeforeLegal"] == "1",
               AuthSecurityPolicy.requiresProtectedSession(sharedAuthState.user) {
                sharedAuthState.presentAuthFlow(.privilegedMultiFactorRequirement)
            }
#endif
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

    @ViewBuilder private var rootContent: some View {
#if DEBUG
#if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-ui-testing"), ProcessInfo.processInfo.environment["UITestSeasonal"] == "1" {
            SeasonalAuditHarness()
        } else { seasonalOrStandardRoot }
#else
        seasonalOrStandardRoot
#endif
#else
        standardRootContent
#endif
    }

    @ViewBuilder private var seasonalOrStandardRoot: some View {
#if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-ui-testing"),
           ProcessInfo.processInfo.environment["UITestBanner14"] == "1" {
            BannerAuditHarness14()
        } else if ProcessInfo.processInfo.arguments.contains("-ui-testing"),
           ProcessInfo.processInfo.environment["UITestBannerAudit"] == "1" {
            BannerMeasurementAuditHarness()
        } else if ProcessInfo.processInfo.arguments.contains("-ui-testing"),
                  ProcessInfo.processInfo.environment["UITestBannerReportAudit"] == "1" {
            BannerReportAuditHarness()
        } else if ProcessInfo.processInfo.arguments.contains("-ui-testing"),
                  ProcessInfo.processInfo.environment["UITestSystemLogDiagnosis"] == "1" {
            SystemLogDiagnosisAuditHarness()
        } else { standardRootContent }
#else
        standardRootContent
#endif
    }

    @ViewBuilder private var standardRootContent: some View {
        if let container {
            AppStartupGate(container: container)
                .environmentObject(authState)
                .overlay(alignment: .topLeading) {
#if DEBUG && targetEnvironment(simulator)
                    if ProcessInfo.processInfo.arguments.contains("-ui-testing"),
                       ProcessInfo.processInfo.environment["UITestSystemAccessibilityProbe"] == "1" {
                        AccessibilityAuditProbe()
                    }
#endif
                }
                .onChange(of: ProfileAccessIdentity(user: authState.user), initial: true) { _, _ in
                    container.ownerAnalyticsRepository.updateAccess(user: authState.user, state: authState.sessionState)
                }
                .onChange(of: authState.sessionState, initial: true) { _, state in
                    container.ownerAnalyticsRepository.updateAccess(user: authState.user, state: state)
                }
                .onChange(of: presenceUserID, initial: true) { _, userID in
                    presence.update(userID: userID, isActive: scenePhase == .active)
                }
        } else {
            Color.clear
        }
    }

    var body: some Scene {
        WindowGroup {
            rootContent
        }
        .onChange(of: scenePhase) { _, phase in
            // System overlays (including screenshots) can briefly make the
            // scene inactive. Presence stays online until actual backgrounding.
            guard phase != .inactive else { return }
            presence.update(userID: presenceUserID, isActive: phase == .active)
        }
    }
}
