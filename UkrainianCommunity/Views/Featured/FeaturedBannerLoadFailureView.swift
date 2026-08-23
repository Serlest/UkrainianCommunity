import SwiftUI

struct FeaturedBannerLoadFailureView: View {
    let error: AppError
    let retry: @MainActor () async -> Void

    var body: some View {
        ErrorStateCard(
            systemImage: "sparkles.rectangle.stack",
            title: AppStrings.Featured.loadErrorTitle,
            message: message,
            retryTitle: AppStrings.Action.retry
        ) {
            Task { await retry() }
        }
    }

    private var message: String {
        switch error {
        case .network:
            return AppStrings.Featured.loadNetworkError
        case .permissionDenied:
            return AppStrings.Featured.loadPermissionError
        case .validationFailed:
            return AppStrings.Featured.loadDataError
        case .notFound, .unknown:
            return AppStrings.Featured.loadUnknownError
        }
    }
}
