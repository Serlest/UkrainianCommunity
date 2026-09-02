import SwiftUI

struct ProfilePreferencesView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: ProfileViewModel
    @ObservedObject var userBlockingCoordinator: UserBlockingCoordinator
    let analyticsService: AnalyticsTracking
    @Binding var isAnalyticsCollectionEnabled: Bool
    let currentUser: AppUser?
    @State private var accountDeletionCandidate: AppUser?

    var body: some View {
        PushedScreenShell(
            title: AppStrings.Profile.settingsSection,
            subtitle: AppStrings.Settings.preferencesSubtitle
        ) {
            ProfileSectionCard(title: AppStrings.Profile.appSettings) {
                VStack(spacing: AppTheme.eventsMetadataSpacing) {
                    ProfileSettingsPickerRow(
                        title: AppStrings.Profile.appLanguage,
                        subtitle: AppStrings.Profile.languageSettingsSubtitle,
                        systemImage: "globe"
                    ) {
                        Picker(AppStrings.Settings.language, selection: $viewModel.settings.language) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.title)
                                    .tag(language)
                                    .accessibilityIdentifier("profile.settings.language.\(language.rawValue)")
                            }
                        }
                        .labelsHidden()
                        .id(locale.identifier)
                        .accessibilityIdentifier("profile.settings.language")
                    }

                    ProfileSettingsPickerRow(
                        title: AppStrings.Profile.appAppearance,
                        subtitle: AppStrings.Profile.appearanceSettingsSubtitle,
                        systemImage: "circle.lefthalf.filled"
                    ) {
                        Picker(AppStrings.Settings.appearance, selection: $viewModel.settings.appearance) {
                            ForEach(AppAppearance.allCases) { appearance in
                                Text(appearance.title).tag(appearance)
                            }
                        }
                        .labelsHidden()
                    }

                    ProfileSettingsToggleRow(
                        title: AppStrings.Profile.analyticsCollectionTitle,
                        subtitle: analyticsService.isCollectionAvailable
                            ? AppStrings.Profile.analyticsCollectionSubtitle
                            : AppStrings.Profile.analyticsCollectionUnavailableSubtitle,
                        systemImage: "chart.bar.xaxis",
                        isOn: Binding(
                            get: { isAnalyticsCollectionEnabled },
                            set: { isEnabled in
                                isAnalyticsCollectionEnabled = isEnabled
                                analyticsService.setCollectionEnabled(isEnabled)
                            }
                        )
                    )
                    .disabled(!analyticsService.isCollectionAvailable)
                    .accessibilityIdentifier("profile.settings.analyticsConsent")
                }
            }

            if let currentUser {
                BiometricLockSettingsSection(lock: authState.appLock)

                NotificationSettingsSectionView(
                    viewModel: viewModel,
                    userID: currentUser.id,
                    canSendTestNotification: PermissionService.canSendTestNotification(user: currentUser)
                )
            }

            if currentUser != nil {
                ProfileSectionCard(title: AppStrings.Profile.accountSection) {
                    VStack(spacing: AppTheme.eventsMetadataSpacing) {
                        if let currentUser {
                            ProfileModuleRow(
                                title: AppStrings.Auth.email,
                                subtitle: currentUser.email,
                                systemImage: "envelope",
                                status: .available,
                                accessory: .none
                            )
                            .accessibilityElement(children: .combine)
                        }

                        NavigationLink(value: ProfileNavigationRoute.accountSecurity) {
                            ProfileModuleRow(
                                title: AppStrings.Profile.accountSecurity,
                                subtitle: AppStrings.Profile.accountSecuritySubtitle,
                                systemImage: "lock.shield",
                                status: .available
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("profile.settings.accountSecurity")

                        if PermissionService.canAccessBlockedUsersSettings(user: currentUser) {
                            NavigationLink(value: ProfileNavigationRoute.blockedOrganizations) {
                                ProfileModuleRow(
                                    title: AppStrings.Safety.blockedOrganizationsTitle,
                                    subtitle: AppStrings.Safety.blockedOrganizationsExplanation,
                                    systemImage: "building.2", status: .available
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("profile.settings.blockedOrganizations")
                            NavigationLink(value: ProfileNavigationRoute.blockedUsers) {
                                ProfileModuleRow(
                                    title: AppStrings.Safety.blockedUsersTitle,
                                    subtitle: AppStrings.Safety.blockedUsersSubtitle,
                                    systemImage: "person.slash",
                                    status: .available,
                                    countBadge: userBlockingCoordinator.blockedUsers.count
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            ProfileSectionCard(
                title: AppStrings.Settings.legalSection,
                subtitle: AppStrings.Settings.legalSectionSubtitle
            ) {
                VStack(spacing: AppTheme.eventsMetadataSpacing) {
                    NavigationLink(value: ProfileNavigationRoute.legal(.terms)) {
                        ProfileModuleRow(
                            title: AppStrings.Settings.terms,
                            subtitle: AppStrings.authCurrentTermsVersion(AuthService.currentTermsVersion),
                            systemImage: "doc.text",
                            status: .available
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("profile.legal.terms")

                    NavigationLink(value: ProfileNavigationRoute.legal(.privacy)) {
                        ProfileModuleRow(
                            title: AppStrings.Settings.privacyPolicy,
                            subtitle: AppStrings.authCurrentPrivacyVersion(AuthService.currentPrivacyVersion),
                            systemImage: "lock.doc",
                            status: .available
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("profile.legal.privacy")
                }
            }

            if currentUser != nil {
                ProfileSectionCard(
                    title: AppStrings.Profile.criticalActions,
                    subtitle: AppStrings.Profile.deleteAccountSubtitle
                ) {
                    Button(role: .destructive) {
                        accountDeletionCandidate = currentUser
                    } label: {
                        ProfileModuleRow(
                            title: AppStrings.Profile.deleteAccount,
                            subtitle: AppStrings.Profile.deleteAccountSubtitle,
                            systemImage: "trash",
                            tint: AppTheme.accentDestructiveForeground,
                            status: .available,
                            accessory: .none
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("profile.delete_account.button")
                }
            }
        }
        .accessibilityIdentifier("screen.profile.preferences")
        .task(id: currentUser?.id) {
            guard let userID = currentUser?.id else { return }
            await viewModel.loadNotificationPreferencesIfNeeded(userID: userID)
        }
        .sheet(item: $accountDeletionCandidate) { user in
            AccountDeletionConfirmationSheet(
                viewModel: viewModel,
                currentUser: user
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}

private struct AccountDeletionConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ProfileViewModel
    let currentUser: AppUser
    @State private var confirmationText = ""
    @State private var errorMessage: String?

    private var canConfirmDeletion: Bool {
        confirmationText.trimmingCharacters(in: .whitespacesAndNewlines)
            == AppStrings.Profile.deleteAccountConfirmationKeyword
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackgroundView()
                    .allowsHitTesting(false)

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                        SectionHeaderBlock(
                            title: AppStrings.Profile.deleteAccountConfirmTitle,
                            subtitle: AppStrings.Profile.deleteAccountConfirmMessage
                        )

                        AppEditorSectionCard {
                            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                                Text(AppStrings.Profile.deleteAccountTypePrompt)
                                    .font(AppTheme.buttonLabelFont)
                                    .foregroundStyle(AppTheme.textPrimary)

                                TextField(
                                    AppStrings.Profile.deleteAccountConfirmationKeyword,
                                    text: $confirmationText
                                )
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .appEditorInputStyle()
                                .accessibilityIdentifier("profile.delete_account.confirmation")

                                Button(role: .destructive) {
                                    Task {
                                        await performDeletion()
                                    }
                                } label: {
                                    if viewModel.isDeletingAccount {
                                        Label(AppStrings.Profile.deleteAccountInProgress, systemImage: "hourglass")
                                    } else {
                                        Label(AppStrings.Profile.deleteAccountFinalAction, systemImage: "trash")
                                    }
                                }
                                .appActionButtonStyle(.primary)
                                .tint(AppTheme.accentDestructive)
                                .disabled(!canConfirmDeletion || viewModel.isDeletingAccount)
                                .accessibilityIdentifier("profile.delete_account.confirm")
                            }
                        }
                    }
                    .padding(AppTheme.pageHorizontal)
                    .appCenteredContent(maxWidth: AppTheme.feedContentMaxWidth)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(AppStrings.Profile.deleteAccount)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.Common.cancel) {
                        dismiss()
                    }
                    .disabled(viewModel.isDeletingAccount)
                }
            }
            .interactiveDismissDisabled(viewModel.isDeletingAccount)
            .alert(AppStrings.Profile.deleteAccount, isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        errorMessage = nil
                    }
                }
            )) {
                Button(AppStrings.Common.ok, role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
            .observesKeyboardDismissTaps()
        }
    }

    private func performDeletion() async {
        guard canConfirmDeletion, !viewModel.isDeletingAccount else { return }

        if let message = await viewModel.deleteAccount(currentUser: currentUser) {
            errorMessage = message
        } else {
            confirmationText = ""
            dismiss()
        }
    }
}

struct ProfileFeedbackComposerView: View {
    @Binding var selectedFeedbackType: FeedbackType
    @Binding var feedbackMessage: String
    let statusMessage: String?
    let isSubmitting: Bool
    let onSubmit: () -> Void

    var body: some View {
        PushedScreenShell(
            title: AppStrings.Profile.feedbackSupport,
            subtitle: AppStrings.Feedback.subtitle
        ) {
            AppEditorSectionCard {
                FeedbackComposerCard(
                    selectedFeedbackType: $selectedFeedbackType,
                    feedbackMessage: $feedbackMessage,
                    statusMessage: statusMessage,
                    isSubmitting: isSubmitting,
                    onSubmit: onSubmit
                )
            }
        }
    }
}

struct ProfileProjectSupportView: View {
    let config: DonationConfig
    let language: AppLanguage

    var body: some View {
        PushedScreenShell(
            title: DonationLocalization.publicSectionTitle(for: language),
            subtitle: config.message(for: language)
        ) {
            ProfileDonationSupportCard(config: config, language: language)
        }
    }
}
