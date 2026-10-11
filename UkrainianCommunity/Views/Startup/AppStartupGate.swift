import SwiftUI
import UIKit
import GoogleSignIn

struct AppStartupGate: View {
    let container: AppContainer

    @EnvironmentObject private var authState: AuthState
    @State private var isShowingSplash = true

    private let transitionDuration = 0.25

    private var reduceMotionEnabled: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    var body: some View {
        ZStack {
            if authState.isRestoring
                || (authState.isAuthenticating && authState.presentedAuthFlow == nil)
                || isShowingSplash {
                SplashLoadingView()
            } else if authState.isAuthenticated || usesGuestUITestFixture {
                ContentView(container: container)
                    .environmentObject(authState)
            } else {
                AuthFlowContainerView(initialDestination: requiredAuthDestination, allowsDismissal: false)
                    .id(requiredAuthDestination)
                    .environmentObject(authState)
                    .preferredColorScheme(AppAppearance.stored.colorScheme)
                    .environment(\.locale, Locale(identifier: AppLanguage.stored.rawValue))
            }
        }
        .background(AppLockShield(authState: authState).frame(width: 0, height: 0))
        .onAppear {
            evaluateStartupState()
        }
        .onChange(of: authState.isRestoring) { _, _ in
            evaluateStartupState()
        }
        .onOpenURL { url in
            _ = GIDSignIn.sharedInstance.handle(url)
        }
    }

    private var requiredAuthDestination: AuthFlowDestination {
        if let presented = authState.presentedAuthFlow { return presented }
        switch authState.sessionState {
        case .verificationPending: return .emailVerification
        case .registrationPending: return .socialRegistration
        case .sessionUnavailable: return .sessionRecovery
        default: return .landing
        }
    }

    private var usesGuestUITestFixture: Bool {
#if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
            && ProcessInfo.processInfo.environment["UITestForceGuestSession"] == "1"
#else
        false
#endif
    }

    private func evaluateStartupState() {
        guard isShowingSplash else {
            return
        }

        guard !authState.isRestoring else {
            return
        }

        if reduceMotionEnabled {
            isShowingSplash = false
        } else {
            withAnimation(.easeInOut(duration: transitionDuration)) {
                isShowingSplash = false
            }
        }
    }
}
