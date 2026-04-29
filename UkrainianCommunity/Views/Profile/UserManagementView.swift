import SwiftUI

struct UserManagementView: View {
    var body: some View {
        List {
            Section {
                Text(AppStrings.UserManagement.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                Label(AppStrings.UserManagement.viewUsers, systemImage: "person.3")
                Label(AppStrings.UserManagement.blockUser, systemImage: "hand.raised")
                Label(AppStrings.UserManagement.assignModerator, systemImage: "person.badge.plus")
                Label(AppStrings.UserManagement.assignAdmin, systemImage: "person.crop.circle.badge.plus")
            }
        }
        .navigationTitle(AppStrings.UserManagement.title)
    }
}

#Preview {
    NavigationStack {
        UserManagementView()
    }
}
