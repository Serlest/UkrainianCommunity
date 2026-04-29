import SwiftUI

struct ProfileView: View {
    @ObservedObject var viewModel: ProfileViewModel
    @EnvironmentObject var authState: AuthState

    private var canShowAdminTools: Bool {
        guard let role = authState.user?.role else {
            return false
        }

        let permissions = role.permissions
        return permissions.canManageUsers || permissions.canAccessOwnerTools
    }

    private var canShowModerationTools: Bool {
        guard let role = authState.user?.role else {
            return false
        }

        let permissions = role.permissions
        return permissions.canCreateNews
            || permissions.canEditNews
            || permissions.canCreateEvent
            || permissions.canEditEvent
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(viewModel.user.fullName)
                        .font(.title3.weight(.bold))
                    Text(viewModel.user.bio)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let user = authState.user {
                    MetadataRow(label: AppStrings.Profile.role, value: user.role.title, systemImage: "person.badge.key")
                    MetadataRow(label: AppStrings.Profile.accountStatus, value: user.blockState.title, systemImage: "checkmark.shield")
                } else {
                    Text("Loading user profile...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                MetadataRow(label: AppStrings.Profile.memberSince, value: LocalizationStore.dateString(from: viewModel.user.joinedAt), systemImage: "calendar")
            }

            Section(AppStrings.Profile.capabilities) {
                ForEach(viewModel.capabilities, id: \.self) { capability in
                    Label(capability, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.primaryBlue)
                }
            }

            if canShowModerationTools {
                Section("Moderation tools") {
                    NavigationLink {
                        ModerationToolsView()
                    } label: {
                        Label("Review pending content", systemImage: "clock.badge.exclamationmark")
                    }
                    Label("Manage news", systemImage: "newspaper")
                    Label("Manage events", systemImage: "calendar")
                    Label("Manage organizations", systemImage: "building.2")
                    Label("Manage marketplace", systemImage: "storefront")
                }
            }

            if canShowAdminTools {
                Section("Admin tools") {
                    NavigationLink {
                        UserManagementView()
                    } label: {
                        Label("User management", systemImage: "person.3")
                    }
                    Label("Moderation tools", systemImage: "checkmark.shield")
                }
            }

            Section(AppStrings.Settings.title) {
                Picker(AppStrings.Settings.language, selection: $viewModel.settings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }

                Picker(AppStrings.Settings.appearance, selection: $viewModel.settings.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }

                MetadataRow(label: AppStrings.Settings.privacyPolicy, value: AppStrings.Settings.placeholder, systemImage: "lock.doc")
                MetadataRow(label: AppStrings.Settings.terms, value: AppStrings.Settings.placeholder, systemImage: "doc.text")
            }
        }
        .navigationTitle(AppStrings.Profile.title)
    }
}

#Preview {
    NavigationStack {
        ProfileView(viewModel: ProfileViewModel(repository: MockUserRepository()))
    }
    .environmentObject(AuthState())
}
