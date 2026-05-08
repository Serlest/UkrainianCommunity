import FirebaseAuth
import FirebaseCore
import SwiftUI

private enum FirebaseBootstrap {
    private static var isConfigured = false

    static func ensureConfigured() {
        if !isConfigured {
            FirebaseApp.configure()
            isConfigured = true
        }
    }
}

@main
struct UkrainianCommunityApp: App {
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
