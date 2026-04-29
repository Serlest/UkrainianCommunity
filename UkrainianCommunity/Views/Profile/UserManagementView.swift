import SwiftUI

struct UserManagementView: View {
    var body: some View {
        List {
            Section {
                Text("User management tools will be available here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                Label("View users", systemImage: "person.3")
                Label("Block user", systemImage: "hand.raised")
                Label("Assign moderator", systemImage: "person.badge.plus")
                Label("Assign admin", systemImage: "person.crop.circle.badge.plus")
            }
        }
        .navigationTitle("User Management")
    }
}

#Preview {
    NavigationStack {
        UserManagementView()
    }
}
