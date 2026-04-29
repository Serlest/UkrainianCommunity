import SwiftUI

struct ModerationToolsView: View {
    var body: some View {
        List {
            Section {
                Text("Moderation tools will be available here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                Label("Review pending content", systemImage: "clock.badge.exclamationmark")
                NavigationLink {
                    NewsEditorPlaceholderView()
                } label: {
                    Label("Manage news", systemImage: "newspaper")
                }
                Label("Manage events", systemImage: "calendar")
                Label("Manage organizations", systemImage: "building.2")
                Label("Manage marketplace", systemImage: "storefront")
            }
        }
        .navigationTitle("Moderation Tools")
    }
}

#Preview {
    NavigationStack {
        ModerationToolsView()
    }
}
