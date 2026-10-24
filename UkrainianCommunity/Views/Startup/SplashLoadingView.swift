import SwiftUI

struct SplashLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotionEnabled
    @State private var hasPresentedLogo = false
#if DEBUG
    @State private var instanceID = UUID().uuidString
#endif

    private enum SplashTiming {
        static let logoSize: CGFloat = 220
        static let logoRevealDuration: Double = 0.35
        static let initialLogoScale: CGFloat = 0.92
    }

    private var shouldShowLogo: Bool {
        reduceMotionEnabled || hasPresentedLogo
    }

    var body: some View {
        ZStack {
            SplashVideoBackgroundView(shouldAnimate: !reduceMotionEnabled)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                AdaptiveBrandLockupView(layout: .vertical)
                    .frame(width: SplashTiming.logoSize, height: SplashTiming.logoSize)
                    .opacity(shouldShowLogo ? 1 : 0)
                    .scaleEffect(shouldShowLogo ? 1 : SplashTiming.initialLogoScale)
                    .accessibilityIdentifier("startup.logo")

                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(AppTheme.textSecondary)
                    .scaleEffect(0.78)
                    .opacity(0.86)
                    .accessibilityLabel(AppStrings.Startup.loading)
                    .accessibilityIdentifier("startup.progress")
            }
            .padding(.horizontal, 24)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("startup.splash")
#if DEBUG
        .accessibilityValue(ProcessInfo.processInfo.arguments.contains("-ui-testing") ? instanceID : "")
#endif
        .onAppear {
            presentLogo()
        }
    }

    private func presentLogo() {
        guard !hasPresentedLogo else {
            return
        }

        if reduceMotionEnabled {
            hasPresentedLogo = true
        } else {
            withAnimation(.easeOut(duration: SplashTiming.logoRevealDuration)) {
                hasPresentedLogo = true
            }
        }
    }
}

#Preview {
    SplashLoadingView()
}
