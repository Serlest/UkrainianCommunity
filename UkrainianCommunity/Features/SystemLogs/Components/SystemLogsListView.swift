import SwiftUI

struct SystemLogsListView<Destination: View>: View {
    let logs: [SystemLogEntry]
    let destination: (SystemLogEntry) -> Destination
    let deleteAction: ((SystemLogEntry) -> Void)?
    let deletingIDs: Set<String>

    init(
        logs: [SystemLogEntry],
        deletingIDs: Set<String> = [],
        deleteAction: ((SystemLogEntry) -> Void)? = nil,
        @ViewBuilder destination: @escaping (SystemLogEntry) -> Destination
    ) {
        self.logs = logs
        self.deletingIDs = deletingIDs
        self.deleteAction = deleteAction
        self.destination = destination
    }

    var body: some View {
        LazyVStack(spacing: AppTheme.eventsListRowSpacing) {
            ForEach(logs) { log in
                HStack(spacing: AppTheme.eventsMetadataSpacing) {
                    NavigationLink {
                        destination(log)
                    } label: {
                        SystemLogRowView(log: log)
                    }
                    .buttonStyle(.plain)

                    if let deleteAction {
                        if deletingIDs.contains(log.id) {
                            ProgressView().controlSize(.small)
                                .frame(width: AppTheme.minimumInteractiveTarget, height: AppTheme.minimumInteractiveTarget)
                        } else {
                            AppGlassIconButton(
                                systemImage: "trash",
                                accessibilityLabel: AppStrings.Action.delete,
                                role: .destructive
                            ) { deleteAction(log) }
                            .accessibilityIdentifier("systemLogs.delete.\(log.id)")
                        }
                    }
                }
            }
        }
    }
}
