import SwiftUI

nonisolated enum FeedbackRecordState {
    case loading
    case ready
    case unavailable
    case failed(AppError)

    var isReady: Bool { if case .ready = self { return true }; return false }
}

/// A pushed destination owns no second navigation stack and never offers writes
/// from an unconfirmed, missing or inaccessible record.
struct FeedbackRecordStateView: View {
    let state: FeedbackRecordState?
    let errorMessage: String
    let onRetry: () -> Void

    var body: some View {
        ScrollView {
            Group {
                switch state {
                case .unavailable?:
                    UnifiedEmptyStateCard(systemImage: "bubble.left.and.exclamationmark.bubble.right",
                        title: FeedbackSupportCopy.conversationTitle, message: AppStrings.DetailState.unavailableMessage)
                        .accessibilityIdentifier("feedback.detail.unavailable")
                case .failed?:
                    ErrorStateCard(systemImage: "exclamationmark.triangle", title: FeedbackSupportCopy.conversationTitle,
                        message: errorMessage, retryTitle: AppStrings.Action.retry, retryAction: onRetry)
                        .accessibilityIdentifier("feedback.detail.error")
                default:
                    LoadingStateCard(title: FeedbackSupportCopy.conversationTitle)
                        .accessibilityIdentifier("feedback.detail.loading")
                }
            }
            .padding(AppTheme.pageHorizontal)
            .appCenteredContent()
        }
        .background(AppTheme.pageBackground)
        .navigationTitle(FeedbackSupportCopy.conversationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}
