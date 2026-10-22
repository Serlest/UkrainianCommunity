import SwiftUI

/// A direct push/inbox destination; reads only the selected record, with normal owner authorization.
struct SystemLogNotificationDestinationView: View {
    let logID: String
    @State private var log: SystemLogEntry?
    @State private var error: String?
    @State private var loading = false
    @State private var reviewing = false
    private let repository = FirestoreSystemLogRepository()
    @StateObject private var viewModel = SystemLogsViewModel(accessMode: .owner)

    var body: some View {
        Group {
            if let log {
                SystemLogDetailView(log: log, isRefreshing: loading, refreshErrorMessage: error,
                    isMarkingReviewed: reviewing, reviewErrorMessage: viewModel.reviewErrorMessage(for: logID),
                    onRetryRefresh: { await load() }, onMarkReviewed: {
                        reviewing = true
                        await viewModel.markReviewed(logID: logID)
                        await load()
                        reviewing = false
                    })
            } else {
                PushedScreenShell(title: AppStrings.SystemLogs.detailTitle) {
                    if loading { ProgressView() }
                    if let error {
                        ErrorStateCard(title: AppStrings.SystemLogs.detailTitle, message: error, retryTitle: AppStrings.Action.retry) { Task { await load() } }
                    }
                }
            }
        }
        .task(id: logID) { await load() }
    }

    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            log = try await repository.fetchLog(id: logID)
            if log == nil { error = LocalizationStore.localizedString("system_logs.detail.not_found", defaultValue: "Запис журналу більше не доступний.") }
        } catch { self.error = AppStrings.SystemLogs.genericLoadError }
    }
}
