import SwiftUI
import UIKit

struct SplashLoadingView: View {
    @State private var logoOpacity: Double = 0
    @State private var logoScale: CGFloat = 0.65
    @State private var showLoadingIndicator = false
    @State private var splashTask: Task<Void, Never>?

    private enum SplashTiming {
        static let logoSize: CGFloat = 220
        static let logoRevealDuration: Double = 2.0
        static let progressDelayNanoseconds: UInt64 = 4_500_000_000
        static let initialLogoOpacity: Double = 0
        static let initialLogoScale: CGFloat = 0.85
    }

    private var reduceMotionEnabled: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    var body: some View {
        ZStack {
            SplashVideoBackgroundView(shouldAnimate: !reduceMotionEnabled)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                AdaptiveBrandLockupView(layout: .vertical)
                    .frame(width: SplashTiming.logoSize, height: SplashTiming.logoSize)
                    .opacity(logoOpacity)
                    .scaleEffect(logoScale)
                    .accessibilityIdentifier("startup.logo")

                if showLoadingIndicator {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(AppTheme.textSecondary)
                        .scaleEffect(0.78)
                        .opacity(0.86)
                }
            }
            .padding(.horizontal, 24)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("startup.splash")
        .onAppear {
            beginSplashSequence()
        }
        .onDisappear {
            splashTask?.cancel()
            splashTask = nil
        }
    }

    private func beginSplashSequence() {
        logoOpacity = 0
        logoScale = 0.65
        showLoadingIndicator = false
        splashTask?.cancel()

        splashTask = Task {
            if reduceMotionEnabled {
                await MainActor.run {
                    logoOpacity = 1
                    logoScale = 1
                }
            } else {
                await MainActor.run {
                    logoOpacity = SplashTiming.initialLogoOpacity
                    logoScale = SplashTiming.initialLogoScale
                }

                await MainActor.run {
                    withAnimation(.easeOut(duration: SplashTiming.logoRevealDuration)) {
                        logoOpacity = 1
                        logoScale = 1
                    }
                }
            }

            try? await Task.sleep(nanoseconds: SplashTiming.progressDelayNanoseconds)

            if !Task.isCancelled {
                await MainActor.run {
                    showLoadingIndicator = true
                }
            }
        }
    }
}

#Preview {
    SplashLoadingView()
}
