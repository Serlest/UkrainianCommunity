import SwiftUI
import UIKit

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
            ContentView(container: container, isStartupReady: !isShowingSplash)
                .environmentObject(authState)
                .opacity(isShowingSplash ? 0 : 1)
                .accessibilityHidden(isShowingSplash)

            if isShowingSplash {
                SplashLoadingView()
                    .opacity(1)
                    .transition(.opacity)
            }
        }
        .background(AppLockShield(authState: authState).frame(width: 0, height: 0))
        .onAppear {
            evaluateStartupState()
        }
        .onChange(of: authState.isRestoring) { _, _ in
            evaluateStartupState()
        }
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
