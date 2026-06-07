import SwiftUI

struct SystemLogsListView<Destination: View>: View {
    let logs: [SystemLogEntry]
    let destination: (SystemLogEntry) -> Destination

    init(
        logs: [SystemLogEntry],
        @ViewBuilder destination: @escaping (SystemLogEntry) -> Destination
    ) {
        self.logs = logs
        self.destination = destination
    }

    var body: some View {
        LazyVStack(spacing: AppTheme.eventsListRowSpacing) {
            ForEach(logs) { log in
                NavigationLink {
                    destination(log)
                } label: {
                    SystemLogRowView(log: log)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
