import SwiftUI

struct SystemLogNotificationDestinationView: View {
    let logID: String
    @StateObject private var model = SystemLogsViewModel(accessMode: .owner)
    var body: some View { SystemLogRecordView(viewModel: model, logID: logID) }
}

/// Both entry paths share exact reads, error states and session fencing.
struct SystemLogRecordView: View {
    @ObservedObject var viewModel: SystemLogsViewModel
    let logID: String
    @EnvironmentObject private var authState: AuthState
    private func retry() async { await viewModel.refreshLogDetail(id: logID) }
    private func review() async {
        await viewModel.markReviewed(logID: logID)
        await viewModel.refreshLogDetail(id: logID)
    }
    private var requestID: String { [logID, SystemLogsViewModel.liveSessionKey, authState.user?.id ?? ""].joined(separator: "|") }
    var body: some View {
        Group {
            if let log = viewModel.log(id: logID) {
                SystemLogDetailView(log: log,
                    isRefreshing: viewModel.refreshingDetailLogIDs.contains(logID),
                    refreshErrorMessage: viewModel.detailRefreshErrorMessages[logID],
                    isMarkingReviewed: viewModel.reviewingLogIDs.contains(logID),
                    reviewErrorMessage: viewModel.reviewErrorMessage(for: logID),
                    onRetryRefresh: retry,
                    onMarkReviewed: review)
            } else {
                missingContent
            }
        }
        .task(id: requestID) {
            viewModel.synchronizeSession()
            await viewModel.refreshLogDetail(id: logID)
        }
    }
    private var missingContent: some View {
        PushedScreenShell(title: AppStrings.SystemLogs.detailTitle) {
            if !viewModel.isSessionCurrent || viewModel.refreshingDetailLogIDs.contains(logID) {
                ProgressView().frame(maxWidth: .infinity)
            } else if viewModel.unavailableLogIDs.contains(logID) {
                InlineMessageCard(style: .info, message: SystemLogJournalStrings.notFound)
            } else if let message = viewModel.detailRefreshErrorMessages[logID] ?? viewModel.errorMessage {
                ErrorStateCard(title: AppStrings.SystemLogs.detailTitle, message: message,
                    retryTitle: AppStrings.Action.retry) { Task { await retry() } }
            } else { ProgressView().frame(maxWidth: .infinity) }
        }
    }

}
