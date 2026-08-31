import SwiftUI
import UIKit

struct ContentDetailLoadStateCard: View {
    let state: ContentDetailLoadState
    let accessibilityPrefix: String
    let retryAction: () -> Void

    var body: some View {
        Group {
            switch state {
            case .loading:
                LoadingStateCard(title: AppStrings.DetailState.loading)
                    .accessibilityLabel(AppStrings.DetailState.loading)
                    .accessibilityIdentifier("\(accessibilityPrefix).loading")
            case .failed(let error):
                ErrorStateCard(
                    systemImage: systemImage(for: error),
                    title: title(for: error),
                    message: message(for: error),
                    retryTitle: AppStrings.Action.retry,
                    retryAction: retryAction
                )
                .accessibilityIdentifier("\(accessibilityPrefix).\(identifier(for: error))")
                .onAppear {
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: "\(title(for: error)). \(message(for: error))"
                    )
                }
            case .content:
                EmptyView()
            }
        }
    }

    private func systemImage(for error: AppError) -> String {
        switch error {
        case .network:
            "wifi.exclamationmark"
        case .permissionDenied:
            "lock.fill"
        case .notFound:
            "doc.questionmark"
        case .validationFailed:
            "doc.badge.ellipsis"
        case .unknown:
            "exclamationmark.triangle"
        }
    }

    private func title(for error: AppError) -> String {
        switch error {
        case .network:
            AppStrings.DetailState.networkTitle
        case .permissionDenied:
            AppStrings.DetailState.permissionTitle
        case .notFound:
            AppStrings.DetailState.unavailableTitle
        case .validationFailed:
            AppStrings.DetailState.invalidTitle
        case .unknown:
            AppStrings.DetailState.unknownTitle
        }
    }

    private func message(for error: AppError) -> String {
        switch error {
        case .network:
            AppStrings.DetailState.networkMessage
        case .permissionDenied:
            AppStrings.DetailState.permissionMessage
        case .notFound:
            AppStrings.DetailState.unavailableMessage
        case .validationFailed:
            AppStrings.DetailState.invalidMessage
        case .unknown:
            AppStrings.DetailState.unknownMessage
        }
    }

    private func identifier(for error: AppError) -> String {
        switch error {
        case .network:
            "network"
        case .permissionDenied:
            "permission"
        case .notFound:
            "unavailable"
        case .validationFailed:
            "invalid"
        case .unknown:
            "unknown"
        }
    }
}
