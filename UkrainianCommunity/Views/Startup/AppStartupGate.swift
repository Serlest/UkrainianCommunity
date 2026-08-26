import SwiftUI
import UIKit

struct AppStartupGate: View {
    let container: AppContainer

    @EnvironmentObject private var authState: AuthState
    @State private var isShowingSplash = true
    @State private var minimumSplashDurationElapsed = false
    @State private var minimumSplashTask: Task<Void, Never>?

    private let minimumSplashDuration: UInt64 = 4_000_000_000
    private let transitionDuration = 0.45

    private var reduceMotionEnabled: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    var body: some View {
        ZStack {
            ContentView(container: container)
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
}
