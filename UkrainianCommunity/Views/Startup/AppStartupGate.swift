import SwiftUI
import UIKit

struct AppStartupGate: View {
    let container: AppContainer

    @EnvironmentObject private var authState: AuthState
    @State private var isShowingSplash = true
    @State private var minimumSplashDurationElapsed = false
    @State private var minimumSplashTask: Task<Void, Never>?
    @State private var uiTestReleasedSplash = false

    private let minimumSplashDuration: UInt64 = 4_000_000_000
    private let transitionDuration = 0.45

    private var reduceMotionEnabled: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    private var shouldHoldSplashForUITesting: Bool {
        let processInfo = ProcessInfo.processInfo
        return processInfo.arguments.contains("-ui-testing")
            && processInfo.environment["UITestHoldSplash"] == "1"
    }

    var body: some View {
        ZStack {
            ContentView(container: container)
                .environmentObject(authState)
                .opacity(isShowingSplash ? 0 : 1)
                .accessibilityHidden(isShowingSplash)

            if isShowingSplash {
                splashView
                    .opacity(1)
                    .transition(.opacity)
            }
        }
        .onAppear {
            startMinimumSplashTimer()
            evaluateStartupState()
        }
        .onDisappear {
            minimumSplashTask?.cancel()
            minimumSplashTask = nil
        }
        .onChange(of: authState.isRestoring) { _, _ in
            evaluateStartupState()
        }
    }

    @ViewBuilder
    private var splashView: some View {
        if shouldHoldSplashForUITesting {
            SplashLoadingView()
                .onTapGesture {
                    releaseSplashForUITesting()
                }
        } else {
            SplashLoadingView()
        }
    }

    private func startMinimumSplashTimer() {
        minimumSplashTask?.cancel()

        minimumSplashTask = Task {
            do {
                try await Task.sleep(nanoseconds: minimumSplashDuration)
                await MainActor.run {
                    minimumSplashDurationElapsed = true
                    evaluateStartupState()
                }
            } catch {
                await MainActor.run {
                    minimumSplashDurationElapsed = true
                    evaluateStartupState()
                }
            }
        }
    }

    private func evaluateStartupState() {
        guard isShowingSplash else {
            return
        }

        guard !shouldHoldSplashForUITesting || uiTestReleasedSplash else {
            return
        }

        guard minimumSplashDurationElapsed else {
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

    private func releaseSplashForUITesting() {
        guard shouldHoldSplashForUITesting else {
            return
        }

        minimumSplashTask?.cancel()
        minimumSplashTask = nil
        minimumSplashDurationElapsed = true
        uiTestReleasedSplash = true
        evaluateStartupState()
    }
}
