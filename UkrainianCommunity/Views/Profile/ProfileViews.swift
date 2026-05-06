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

    private var displayUser: AppUser? {
        if let authenticatedUser = authState.user {
            return authenticatedUser
        }

        guard viewModel.user.id != AppUser.placeholder.id else {
            return nil
        }

        return viewModel.user
    }

    private var capabilityItems: [String] {
        guard let user = displayUser else {
            return [AppStrings.Common.likes, AppStrings.Profile.eventRegistration]
        }

        var items = [AppStrings.Common.likes, AppStrings.Profile.eventRegistration]

        if PermissionService.canModerate(section: .news, user: user)
            || PermissionService.canModerate(section: .events, user: user)
            || PermissionService.canModerate(section: .organizations, user: user)
            || PermissionService.canModerate(section: .marketplace, user: user) {
            items.append(AppStrings.Profile.moderationTools)
        }

        if user.globalRole == .owner || user.globalRole == .topAdmin {
            items.append(AppStrings.Profile.adminTools)
            items.append(AppStrings.Profile.userManagement)
        }

        return items
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text((displayUser?.fullName).flatMap { $0.isEmpty ? nil : $0 } ?? AppStrings.Profile.loadingUserProfile)
                        .font(.title3.weight(.bold))

                    if let bio = displayUser?.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if let user = displayUser {
                    MetadataRow(label: AppStrings.Profile.role, value: user.globalRole.title, systemImage: "person.badge.key")
                    MetadataRow(label: AppStrings.Profile.accountStatus, value: user.accountStatus.title, systemImage: "checkmark.shield")
                    MetadataRow(label: AppStrings.Profile.memberSince, value: LocalizationStore.dateString(from: user.joinedAt), systemImage: "calendar")
                } else {
                    Text(AppStrings.Profile.loadingUserProfile)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .listRowBackground(AppTheme.surfacePrimary)

            Section(AppStrings.Profile.capabilities) {
                ForEach(capabilityItems, id: \.self) { capability in
                    Label(capability, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.accentPrimary)
                }
            }
            .listRowBackground(AppTheme.surfacePrimary)

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
                .listRowBackground(AppTheme.surfacePrimary)
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
                .listRowBackground(AppTheme.surfacePrimary)
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

                LabeledContent {
                    Text(AppStrings.Settings.placeholder)
                        .foregroundStyle(AppTheme.textSecondary)
                } label: {
                    Label(AppStrings.Settings.privacyPolicy, systemImage: "lock.doc")
                }

                LabeledContent {
                    Text(AppStrings.Settings.placeholder)
                        .foregroundStyle(AppTheme.textSecondary)
                } label: {
                    Label(AppStrings.Settings.terms, systemImage: "doc.text")
                }
            }
            .listRowBackground(AppTheme.surfacePrimary)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.pageBackground)
        .tint(AppTheme.accentPrimary)
        .navigationTitle(AppStrings.Profile.title)
    }
}

#Preview {
    NavigationStack {
        ProfileView(viewModel: ProfileViewModel(repository: MockUserRepository()))
    }
    .environmentObject(AuthState())
}
