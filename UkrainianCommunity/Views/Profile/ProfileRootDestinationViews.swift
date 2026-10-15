import SwiftUI

struct ProfilePreferencesView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: ProfileViewModel
    @ObservedObject var userBlockingCoordinator: UserBlockingCoordinator
    let analyticsService: AnalyticsTracking
    @ObservedObject var bannerMeasurementService: BannerMeasurementService
    @Binding var isAnalyticsCollectionEnabled: Bool
    let currentUser: AppUser?
    @State private var accountDeletionCandidate: AppUser?
    @State private var analyticsConsentWasRejected = false
    @State private var isShowingBannerConsent = false

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
                            ? AppStrings.Profile.analyticsCollectionSummary
                            : AppStrings.Profile.analyticsCollectionUnavailableSubtitle,
                        systemImage: "chart.bar.xaxis",
                        isOn: Binding(
                            get: { isAnalyticsCollectionEnabled },
                            set: { isEnabled in
                                analyticsConsentWasRejected = false
                                isAnalyticsCollectionEnabled = isEnabled
                                analyticsService.setCollectionEnabled(isEnabled)
                            }
                        )
                    )
                    .disabled(!analyticsService.isCollectionAvailable)
                    .accessibilityIdentifier("profile.settings.analyticsConsent")

                    DisclosureGroup(AppStrings.Profile.analyticsCollectionDetails) {
                        Text(AppStrings.Profile.analyticsCollectionSubtitle)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.footnote.weight(.semibold))
                    .tint(AppTheme.primaryBlue)

                    if analyticsConsentWasRejected || analyticsService.hasConsentSyncFailure {
                        InlineMessageCard(
                            style: .error,
                            message: AppStrings.Profile.analyticsConsentRejected
                        )
                        .accessibilityIdentifier("profile.settings.analyticsConsent.error")

                        Button {
                            analyticsConsentWasRejected = false
                            isAnalyticsCollectionEnabled = true
                            // A server-side withdrawal can tombstone the old
                            // consent ID. This explicit retry records a fresh
                            // choice while leaving collection paused until ack.
                            analyticsService.setCollectionEnabled(false)
                            analyticsService.setCollectionEnabled(true)
                        } label: {
                            Label(AppStrings.Action.retry, systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("profile.settings.analyticsConsent.retry")
                    }

                    if bannerMeasurementService.isAvailable {
                        ProfileSettingsToggleRow(
                            title: AppStrings.Profile.bannerMeasurementTitle,
                            subtitle: AppStrings.Profile.bannerMeasurementSubtitle,
                            systemImage: "rectangle.on.rectangle",
                            isOn: Binding(
                                get: { bannerMeasurementService.isEnabled },
                                set: { enabled in
                                    if enabled {
                                        isShowingBannerConsent = true
                                    } else {
                                        Task { await bannerMeasurementService.setEnabled(false) }
                                    }
                                }
                            )
                        )
                        .disabled(bannerMeasurementService.isBusy)
                        .accessibilityIdentifier("profile.settings.bannerMeasurementConsent")

                        if bannerMeasurementService.hasError {
                            InlineMessageCard(style: .error, message: AppStrings.Profile.bannerMeasurementError)
                            Button(AppStrings.Action.retry) {
                                Task { await bannerMeasurementService.refresh() }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
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
                                status: .available
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
                            status: .available
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("profile.delete_account.button")
                }
            }
        }
        .accessibilityIdentifier("screen.profile.preferences")
        .sheet(isPresented: $isShowingBannerConsent) {
            BannerMeasurementConsentSheet {
                Task { await bannerMeasurementService.setEnabled(true) }
            }
        }
        .task(id: currentUser?.id) {
            guard let userID = currentUser?.id else { return }
            await viewModel.loadNotificationPreferencesIfNeeded(userID: userID)
        }
        .task(id: currentUser?.id) {
            await bannerMeasurementService.refresh()
        }
        .task(id: currentUser?.id) {
            for await _ in analyticsService.collectionChanges() {
                guard !Task.isCancelled else { return }
                isAnalyticsCollectionEnabled = analyticsService.isCollectionEnabled
            }
        }
        .task(id: currentUser?.id) {
            analyticsConsentWasRejected = false
            for await failure in analyticsService.consentFailures() {
                guard !Task.isCancelled else { return }
                if failure.kind == .permanentRejection,
                   analyticsService.isCurrentConsentFailure(failure) {
                    analyticsConsentWasRejected = true
                    isAnalyticsCollectionEnabled = analyticsService.isCollectionEnabled
                }
            }
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
            subtitle: DonationLocalization.publicSectionSubtitle(for: language)
        ) {
            ProfileDonationSupportCard(config: config, language: language)
        }
    }
}
