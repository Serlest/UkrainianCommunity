import SwiftUI

struct GuideLoadingView: View {
    var body: some View {
        LoadingStateCard(title: AppStrings.Guide.loading)
            .frame(maxWidth: .infinity, minHeight: 180)
    }
}

struct GuideErrorStateView: View {
    let error: AppError
    let retryAction: () -> Void

    var body: some View {
        ErrorStateCard(
            systemImage: "book.closed",
            title: AppStrings.Guide.title,
            message: message,
            retryTitle: AppStrings.Action.retry,
            retryAction: retryAction
        )
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    private var message: String {
        switch error {
        case .network:
            AppStrings.Guide.loadNetworkError
        case .permissionDenied:
            AppStrings.Guide.loadPermissionError
        case .validationFailed:
            AppStrings.Guide.loadValidationError
        case .notFound, .unknown:
            AppStrings.Guide.loadUnknownError
        }
    }
}

struct GuideEmptyStateView: View {
    enum Kind {
        case noArticles
        case noMatches
    }

    let kind: Kind

    var body: some View {
        EmptyStateCard(
            systemImage: systemImage,
            title: title,
            message: message
        )
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    private var systemImage: String {
        switch kind {
        case .noArticles:
            "book.closed"
        case .noMatches:
            "magnifyingglass"
        }
    }

    private var title: String {
        switch kind {
        case .noArticles:
            AppStrings.Guide.emptyTitle
        case .noMatches:
            AppStrings.Guide.noMatchesTitle
        }
    }

    private var message: String {
        switch kind {
        case .noArticles:
            AppStrings.Guide.emptyMessage
        case .noMatches:
            AppStrings.Guide.noResults
        }
    }
}
