import FirebaseCore
import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {}

@main
struct UkrainianCommunityApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var authState = AuthService.shared.authState

    init() {
        FirebaseApp.configure()
        Task { @MainActor in
            await AuthService.shared.signInAnonymously()
        }

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
