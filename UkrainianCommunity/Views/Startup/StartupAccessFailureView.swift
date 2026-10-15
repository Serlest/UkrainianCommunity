import SwiftUI

struct StartupAccessFailureView: View {
    let failure: StartupVerificationFailure
    let retry: () async -> Void

    @State private var isRetrying = false

    var body: some View {
        ZStack {
            AppBackgroundView()
                .ignoresSafeArea()

            GeometryReader { geometry in
                ScrollView {
                    UnifiedEmptyStateCard(
                        systemImage: failure == .connection ? "wifi.slash" : "exclamationmark.icloud",
                        title: failure == .connection
                            ? AppStrings.Startup.connectionTitle : AppStrings.Startup.serviceTitle,
                        message: failure == .connection
                            ? AppStrings.Startup.connectionMessage : AppStrings.Startup.serviceMessage
                    ) {
                        PrimaryActionButton(
                            title: AppStrings.Action.retry,
                            isEnabled: !isRetrying,
                            isLoading: isRetrying,
                            systemImage: "arrow.clockwise"
                        ) {
                            guard !isRetrying else { return }
                            isRetrying = true
                            Task {
                                await retry()
                                isRetrying = false
                            }
                        }
                        .accessibilityIdentifier("startup.retry")
                    }
                    .padding(.horizontal, AppTheme.pageHorizontal)
                    .appCenteredContent()
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height)
                }
            }
        }
        .accessibilityIdentifier(failure == .connection ? "startup.connection" : "startup.service")
    }
}
