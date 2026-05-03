import SwiftUI

struct ProfileView: View {
    @ObservedObject var viewModel: ProfileViewModel
    @EnvironmentObject var authState: AuthState

    private var canShowAdminTools: Bool {
        guard let user = authState.user else {
            return false
        }
        return user.globalRole == .owner || user.globalRole == .topAdmin
    }

    private var canShowModerationTools: Bool {
        guard let user = authState.user else {
            return false
        }

        return PermissionService.canModerate(section: .news, user: user)
            || PermissionService.canModerate(section: .events, user: user)
            || PermissionService.canModerate(section: .organizations, user: user)
            || PermissionService.canModerate(section: .marketplace, user: user)
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
                    Text(AppStrings.Profile.loadingUserProfile)
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
                Section(AppStrings.Profile.moderationTools) {
                    NavigationLink {
                        ModerationToolsView()
                    } label: {
                        Label(AppStrings.Profile.reviewPendingContent, systemImage: "clock.badge.exclamationmark")
                    }
                    Label(AppStrings.Profile.manageNews, systemImage: "newspaper")
                    Label(AppStrings.Profile.manageEvents, systemImage: "calendar")
                    Label(AppStrings.Profile.manageOrganizations, systemImage: "building.2")
                    Label(AppStrings.Profile.manageMarketplace, systemImage: "storefront")
                }
            }

            if canShowAdminTools {
                Section(AppStrings.Profile.adminTools) {
                    NavigationLink {
                        UserManagementView()
                    } label: {
                        Label(AppStrings.Profile.userManagement, systemImage: "person.3")
                    }
                    Label(AppStrings.Profile.moderationTools, systemImage: "checkmark.shield")
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
