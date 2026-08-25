import SwiftUI

struct ProfilePreferencesView: View {
    @Environment(\.locale) private var locale
    @ObservedObject var viewModel: ProfileViewModel
    @ObservedObject var userBlockingCoordinator: UserBlockingCoordinator
    let analyticsService: AnalyticsTracking
    @Binding var isAnalyticsCollectionEnabled: Bool
    let currentUser: AppUser?
    let onDeleteAccount: () -> Void

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
                                Text(language.title).tag(language)
                            }
                        }
                        .labelsHidden()
                        .id(locale.identifier)
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

                        if PermissionService.canAccessBlockedUsersSettings(user: currentUser) {
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
                    Button(role: .destructive, action: onDeleteAccount) {
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
