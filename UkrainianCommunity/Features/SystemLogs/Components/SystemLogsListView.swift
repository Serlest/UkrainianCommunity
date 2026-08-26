import SwiftUI

struct SystemLogsListView<Destination: View>: View {
    let logs: [SystemLogEntry]
    let destination: (SystemLogEntry) -> Destination
    let deleteAction: ((SystemLogEntry) -> Void)?
    let reviewAction: ((SystemLogEntry) -> Void)?
    let deletingIDs: Set<String>

    init(
        logs: [SystemLogEntry],
        deletingIDs: Set<String> = [],
        deleteAction: ((SystemLogEntry) -> Void)? = nil,
        reviewAction: ((SystemLogEntry) -> Void)? = nil,
        @ViewBuilder destination: @escaping (SystemLogEntry) -> Destination
    ) {
        self.logs = logs
        self.deletingIDs = deletingIDs
        self.deleteAction = deleteAction
        self.reviewAction = reviewAction
        self.destination = destination
    }

    var body: some View {
        LazyVStack(spacing: AppTheme.eventsListRowSpacing) {
            ForEach(logs) { log in
                NavigationLink {
                    destination(log)
                } label: {
                    SystemLogRowView(log: log, isDeleting: deletingIDs.contains(log.id))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if !log.isReviewed, let reviewAction {
                        Button {
                            reviewAction(log)
                        } label: {
                            Label(AppStrings.SystemLogs.markReviewed, systemImage: "checkmark.seal")
                        }
                    }

                    if let deleteAction {
                        Button(role: .destructive) {
                            deleteAction(log)
                        } label: {
                            Label(AppStrings.Action.delete, systemImage: "trash")
                        }
                        .disabled(deletingIDs.contains(log.id))
                    }
                }
                .accessibilityAction(named: AppStrings.SystemLogs.markReviewed) {
                    guard !log.isReviewed else { return }
                    reviewAction?(log)
                }
                .accessibilityIdentifier("systemLogs.log.\(log.id)")
            }
        }
    }
}
