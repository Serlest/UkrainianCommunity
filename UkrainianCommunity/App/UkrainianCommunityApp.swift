import FirebaseCore
import SwiftUI
import UIKit

private enum FirebaseBootstrap {
    private static var isConfigured = false

    static func ensureConfigured() {
        #if DEBUG
        print("FirebaseBootstrap ensureConfigured called")
        #endif
        if !isConfigured {
            FirebaseApp.configure()
            isConfigured = true
            #if DEBUG
            print("FirebaseBootstrap configure executed")
            #endif
        } else {
            #if DEBUG
            print("FirebaseBootstrap configure skipped already configured")
            #endif
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Task { @MainActor in
            await AuthService.shared.signInAnonymously()
        }

        return true
    }
}

@main
struct UkrainianCommunityApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var authState = AuthService.shared.authState

    init() {
        FirebaseBootstrap.ensureConfigured()

        let environment = ProcessInfo.processInfo.environment

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
            ContentView(container: .development)
                .environmentObject(authState)
        }
    }
}
