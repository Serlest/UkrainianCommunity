import Combine
import PhotosUI
import SwiftUI

struct ProfileView: View {
    @ObservedObject var viewModel: ProfileViewModel
    private let eventRepository: EventRepository
    @EnvironmentObject var authState: AuthState
    @StateObject private var registrationsViewModel: MyRegistrationsViewModel
    @State private var isShowingEditProfileSheet = false
    @State private var fullNameDraft = ""
    @State private var displayNameDraft = ""
    @State private var telegramUsernameDraft = ""
    @State private var cityDraft = ""
    @State private var bioDraft = ""
    @State private var selectedFederalStateDraft: AustrianFederalState = .tirol
    @State private var selectedAvatarPhoto: PhotosPickerItem?
    @State private var selectedAvatarImageData: Data?
    @State private var avatarPreviewImage: UIImage?
    @State private var isLoadingAvatarSelection = false
    @State private var selectedFeedbackType: FeedbackType = .question
    @State private var feedbackMessage = ""
    @State private var guestAccessAction: GuestAccessAction?
    @State private var isShowingLogoutConfirmation = false
    @State private var logoutErrorMessage: String?

    init(viewModel: ProfileViewModel, eventRepository: EventRepository) {
        self.viewModel = viewModel
        self.eventRepository = eventRepository
        _registrationsViewModel = StateObject(wrappedValue: MyRegistrationsViewModel(repository: eventRepository))
    }

    private var permissionUser: AppUser? {
        authState.user ?? displayUser
    }

    private var canShowAdminTools: Bool {
        PermissionService.canAccessAdminTools(user: permissionUser)
    }

    private var canShowModerationTools: Bool {
        PermissionService.canAccessModerationTools(user: permissionUser)
    }

    private var canShowContentManagement: Bool {
        PermissionService.canAccessContentManagement(user: permissionUser)
    }

    private var canShowOrganizationManagement: Bool {
        PermissionService.canAccessOrganizationManagement(user: permissionUser)
    }

    private var displayUser: AppUser? {
        guard authState.isAuthenticated else {
            return nil
        }

        if let authenticatedUser = authState.user {
            return authenticatedUser
        }

        guard viewModel.user.id != AppUser.placeholder.id else {
            return nil
        }

        return viewModel.user
    }

    private var readableFederalState: String? {
        guard let federalState = displayUser?.selectedFederalState else { return nil }
        return AppStrings.FederalStates.title(for: federalState)
    }

    private var hasAdministrationSection: Bool {
        canShowModerationTools || canShowAdminTools
    }

    private var saveButtonTitle: String {
        viewModel.isSavingProfile ? AppStrings.Profile.savingProfile : AppStrings.Profile.saveProfile
    }

    private var profileStatusStyle: InlineMessageStyle {
        if viewModel.profileMessage == AppStrings.Profile.profileSaved {
            return .success
        }

        if viewModel.isSavingProfile || isLoadingAvatarSelection {
            return .info
        }

        return .error
    }

    private var profileStatusMessage: String? {
        if isLoadingAvatarSelection {
            return AppStrings.Profile.avatarLoading
        }

        if viewModel.isSavingProfile {
            return AppStrings.Profile.savingProfileMessage
        }

        if selectedAvatarImageData != nil, viewModel.profileMessage == nil {
            return AppStrings.Profile.avatarReadyToSave
        }

        return viewModel.profileMessage
    }

    private var profileValidationHint: String? {
        if displayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AppStrings.Profile.displayNameRequired
        }

        if isLoadingAvatarSelection {
            return AppStrings.Profile.avatarLoading
        }

        if !hasProfileChanges {
            return AppStrings.Profile.noProfileChanges
        }

        return nil
    }

    private var hasProfileChanges: Bool {
        guard let user = displayUser else { return false }

        let hasTextualChanges =
            user.fullName.trimmingCharacters(in: .whitespacesAndNewlines) != fullNameDraft.trimmingCharacters(in: .whitespacesAndNewlines) ||
            user.displayName.trimmingCharacters(in: .whitespacesAndNewlines) != displayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines) ||
            (user.telegramUsername ?? "").trimmingCharacters(in: .whitespacesAndNewlines) != telegramUsernameDraft.trimmingCharacters(in: .whitespacesAndNewlines) ||
            user.city.trimmingCharacters(in: .whitespacesAndNewlines) != cityDraft.trimmingCharacters(in: .whitespacesAndNewlines) ||
            user.bio.trimmingCharacters(in: .whitespacesAndNewlines) != bioDraft.trimmingCharacters(in: .whitespacesAndNewlines) ||
            user.selectedFederalState != selectedFederalStateDraft

        return hasTextualChanges || selectedAvatarImageData != nil
    }

    private var canSaveProfile: Bool {
        !viewModel.isSavingProfile &&
        !isLoadingAvatarSelection &&
        hasProfileChanges &&
        !displayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var feedbackSupportSection: some View {
        Section(AppStrings.Profile.feedbackSupport) {
            if let user = displayUser {
                FeedbackComposerCard(
                    selectedFeedbackType: $selectedFeedbackType,
                    feedbackMessage: $feedbackMessage,
                    statusMessage: viewModel.feedbackMessage,
                    isSubmitting: viewModel.isSubmittingFeedback
                ) {
                    submitFeedback(for: user)
                }
            }
        }
        .listRowBackground(AppTheme.surfacePrimary)
    }

    private var activitySection: some View {
        Section {
            NavigationLink {
                MyRegistrationsView(
                    viewModel: registrationsViewModel,
                    eventRepository: eventRepository
                )
            } label: {
                AppNavigationRow(
                    title: AppStrings.Profile.myRegistrations,
                    subtitle: registrationsSectionSubtitle,
                    systemImage: "calendar.badge.clock"
                )
            }
            .accessibilityLabel(AppStrings.Profile.myRegistrations)
        } header: {
            SectionHeaderBlock(
                title: AppStrings.Profile.myActivity,
                subtitle: AppStrings.Profile.activitySectionSummary
            )
            .textCase(nil)
        }
        .listRowBackground(AppTheme.surfacePrimary)
    }

    private var registrationsSectionSubtitle: String {
        if registrationsViewModel.isLoading && registrationsViewModel.events.isEmpty {
            return AppStrings.Profile.registrationsLoading
        }

        if registrationsViewModel.registrationsCount == 0 {
            return AppStrings.Profile.registrationsEmptySummary
        }

        return AppStrings.profileRegistrationsCount(registrationsViewModel.registrationsCount)
    }

    private var organizationsSection: some View {
        Section {
            if canShowOrganizationManagement, let user = permissionUser {
                NavigationLink {
                    OrganizationManagementHubView(currentUser: user)
                } label: {
                    AppNavigationRow(
                        title: AppStrings.Profile.organizationManagement,
                        subtitle: AppStrings.Profile.organizationManagementSubtitle,
                        systemImage: "building.2.crop.circle"
                    )
                }
                .accessibilityLabel(AppStrings.Profile.organizationManagement)
            } else {
                EmptyStateCard(
                    systemImage: "building.2",
                    title: AppStrings.Profile.myOrganizations,
                    message: AppStrings.Profile.organizationsSectionSubtitle
                )
            }
        } header: {
            SectionHeaderBlock(
                title: AppStrings.Profile.myOrganizations,
                subtitle: AppStrings.Profile.organizationsSectionSummary
            )
            .textCase(nil)
        }
        .listRowBackground(AppTheme.surfacePrimary)
    }

    private var appManagementSection: some View {
        Section {
            if canShowContentManagement {
                if PermissionService.canManageAppNews(user: permissionUser) {
                    NavigationLink {
                        AppNewsManagementView()
                    } label: {
                        AppNavigationRow(
                            title: AppStrings.Profile.manageAppNews,
                            subtitle: AppStrings.Profile.contentManagementSubtitle,
                            systemImage: "newspaper"
                        )
                    }
                    .accessibilityLabel(AppStrings.Profile.manageAppNews)
                }

                if PermissionService.canManageAppEvents(user: permissionUser) {
                    NavigationLink {
                        AppEventsManagementView()
                    } label: {
                        AppNavigationRow(
                            title: AppStrings.Profile.manageAppEvents,
                            subtitle: AppStrings.Profile.contentManagementSubtitle,
                            systemImage: "calendar"
                        )
                    }
                    .accessibilityLabel(AppStrings.Profile.manageAppEvents)
                }
            }

            if canShowModerationTools {
                NavigationLink {
                    ModerationToolsView()
                } label: {
                    AppNavigationRow(
                        title: AppStrings.Profile.reviewPendingContent,
                        subtitle: AppStrings.Profile.appManagementSubtitle,
                        systemImage: "clock.badge.exclamationmark"
                    )
                }
                .accessibilityLabel(AppStrings.Profile.reviewPendingContent)
            }

            if canShowAdminTools {
                NavigationLink {
                    UserManagementView()
                } label: {
                    AppNavigationRow(
                        title: AppStrings.Profile.userManagement,
                        subtitle: AppStrings.Profile.appManagementSubtitle,
                        systemImage: "person.3"
                    )
                }
                .accessibilityLabel(AppStrings.Profile.userManagement)
            }
        } header: {
            SectionHeaderBlock(
                title: AppStrings.Profile.appManagement,
                subtitle: AppStrings.Profile.appManagementSubtitle
            )
            .textCase(nil)
        }
        .listRowBackground(AppTheme.surfacePrimary)
    }

    private var settingsPreferencesSection: some View {
        Section {
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
        } header: {
            SectionHeaderBlock(
                title: AppStrings.Settings.title,
                subtitle: AppStrings.Settings.preferencesSubtitle
            )
            .textCase(nil)
        }
        .listRowBackground(AppTheme.surfacePrimary)
    }

    private var settingsLegalSection: some View {
        Section {
            NavigationLink {
                LegalDocumentView(document: .privacy)
            } label: {
                AppNavigationRow(
                    title: AppStrings.Settings.privacyPolicy,
                    subtitle: AppStrings.authCurrentPrivacyVersion(AuthService.currentPrivacyVersion),
                    systemImage: "lock.doc"
                )
            }
            .accessibilityIdentifier("settings.privacy.button")
            .accessibilityLabel(AppStrings.Settings.privacyPolicy)

            NavigationLink {
                LegalDocumentView(document: .terms)
            } label: {
                AppNavigationRow(
                    title: AppStrings.Settings.terms,
                    subtitle: AppStrings.authCurrentTermsVersion(AuthService.currentTermsVersion),
                    systemImage: "doc.text"
                )
            }
            .accessibilityIdentifier("settings.terms.button")
            .accessibilityLabel(AppStrings.Settings.terms)
        } header: {
            SectionHeaderBlock(
                title: AppStrings.Settings.legalSection,
                subtitle: AppStrings.Settings.legalSectionSubtitle
            )
            .textCase(nil)
        }
        .listRowBackground(AppTheme.surfacePrimary)
    }

    private var settingsSessionSection: some View {
        Section {
            Button(role: .destructive) {
                isShowingLogoutConfirmation = true
            } label: {
                AppNavigationRow(
                    title: AppStrings.Profile.signOut,
                    subtitle: AppStrings.Settings.sessionSubtitle,
                    systemImage: "rectangle.portrait.and.arrow.right",
                    tint: AppTheme.accentDestructive,
                    accessory: .none
                )
            }
            .accessibilityIdentifier("profile.logout.button")
            .accessibilityLabel(AppStrings.Profile.signOut)
        } header: {
            SectionHeaderBlock(title: AppStrings.Settings.sessionSection)
                .textCase(nil)
        }
        .listRowBackground(AppTheme.surfacePrimary)
    }

    var body: some View {
        List {
            Section {
                ProfileHeaderCard(
                    sessionState: authState.sessionState,
                    user: displayUser,
                    readableFederalState: readableFederalState,
                    onEditProfile: beginEditingProfile,
                    onSignIn: { authState.presentAuthFlow(.login) },
                    onCreateAccount: { authState.presentAuthFlow(.register) }
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            } header: {
                if authState.isAuthenticated {
                    SectionHeaderBlock(
                        title: AppStrings.Profile.accountSection,
                        subtitle: AppStrings.Profile.accountSectionSummary
                    )
                    .textCase(nil)
                } else {
                    Text(AppStrings.Profile.guestSectionSummary)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .textCase(nil)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if authState.isAuthenticated {
                activitySection
                organizationsSection
            }

            if displayUser != nil, (hasAdministrationSection || canShowContentManagement) {
                appManagementSection
            }

            if displayUser != nil {
                feedbackSupportSection
            }

            settingsPreferencesSection
            settingsLegalSection

            if authState.isAuthenticated {
                settingsSessionSection
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.pageBackground)
        .tint(AppTheme.accentPrimary)
        .navigationTitle(AppStrings.Profile.title)
        .safeAreaInset(edge: .bottom) {
            Color.clear
                .frame(height: 72)
        }
        .task {
            await viewModel.loadIfNeeded()
            await viewModel.refreshIfStale()
            if authState.isAuthenticated {
                await registrationsViewModel.loadIfNeeded()
                await registrationsViewModel.refreshIfStale()
            } else {
                registrationsViewModel.resetForGuest()
            }
        }
        .refreshable {
            await viewModel.refresh()
            if authState.isAuthenticated {
                await registrationsViewModel.refresh()
            }
        }
        .onChange(of: authState.isAuthenticated) { _, isAuthenticated in
            Task {
                if isAuthenticated {
                    await registrationsViewModel.refresh()
                } else {
                    registrationsViewModel.resetForGuest()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .registrationsChanged)) { _ in
            guard authState.isAuthenticated else { return }
            Task {
                await registrationsViewModel.refresh()
            }
        }
        .sheet(isPresented: $isShowingEditProfileSheet) {
            NavigationStack {
                Form {
                    Section {
                        ProfileAvatarEditorCard(
                            avatarURL: displayUser?.avatarURL,
                            initials: displayUser?.initials ?? "UC",
                            previewImage: avatarPreviewImage,
                            selectedPhoto: $selectedAvatarPhoto,
                            isLoadingAvatar: isLoadingAvatarSelection,
                            isSavingAvatar: viewModel.isSavingProfile && selectedAvatarImageData != nil
                        )
                    } header: {
                        SectionHeaderBlock(
                            title: AppStrings.Profile.editProfile,
                            subtitle: AppStrings.Profile.editProfileSubtitle
                        )
                        .textCase(nil)
                    }

                    Section {
                        TextField(AppStrings.Profile.fullName, text: $fullNameDraft)
                            .textInputAutocapitalization(.words)
                            .accessibilityLabel(AppStrings.Profile.fullName)

                        TextField(AppStrings.Profile.displayName, text: $displayNameDraft)
                            .textInputAutocapitalization(.words)
                            .accessibilityLabel(AppStrings.Profile.displayName)

                        TextField(AppStrings.Auth.email, text: .constant(displayUser?.email ?? ""))
                            .disabled(true)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(AppStrings.Auth.email)

                        TextField(AppStrings.Common.city, text: $cityDraft)
                            .textInputAutocapitalization(.words)
                            .accessibilityLabel(AppStrings.Common.city)

                        TextField(AppStrings.Profile.telegramUsername, text: $telegramUsernameDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityLabel(AppStrings.Profile.telegramUsername)

                        Picker(AppStrings.Auth.federalState, selection: $selectedFederalStateDraft) {
                            ForEach(AustrianFederalState.allCases) { state in
                                Text(AppStrings.FederalStates.title(for: state)).tag(state)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(AppStrings.Profile.bio)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)

                            TextEditor(text: $bioDraft)
                                .frame(minHeight: 120)
                                .padding(8)
                                .background(
                                    AppTheme.surfaceSecondary,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )
                                .accessibilityLabel(AppStrings.Profile.bio)
                        }
                    } footer: {
                        Text(AppStrings.Profile.emailReadOnlyHint)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(.secondary)
                    }

                    if let profileStatusMessage {
                        Section {
                            InlineMessageCard(style: profileStatusStyle, message: profileStatusMessage)
                                .accessibilityLabel(profileStatusMessage)
                        }
                    }

                    Section {
                        Button {
                            Task {
                                let updatedUser = await viewModel.saveProfile(
                                    EditableUserProfileDraft(
                                        fullName: fullNameDraft,
                                        displayName: displayNameDraft,
                                        telegramUsername: telegramUsernameDraft,
                                        city: cityDraft,
                                        bio: bioDraft,
                                        selectedFederalState: selectedFederalStateDraft,
                                        avatarURL: displayUser?.avatarURL
                                    ),
                                    avatarImageData: selectedAvatarImageData
                                )
                                guard let updatedUser else { return }
                                authState.user = updatedUser
                                isShowingEditProfileSheet = false
                            }
                        } label: {
                            if viewModel.isSavingProfile || isLoadingAvatarSelection {
                                ProgressView(saveButtonTitle)
                            } else {
                                Text(saveButtonTitle)
                            }
                        }
                        .disabled(!canSaveProfile)
                        .accessibilityLabel(AppStrings.Profile.saveProfile)
                    } footer: {
                        if let profileValidationHint {
                            Text(profileValidationHint)
                                .fixedSize(horizontal: false, vertical: true)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationTitle(AppStrings.Profile.editProfile)
                .navigationBarTitleDisplayMode(.inline)
                .interactiveDismissDisabled(viewModel.isSavingProfile)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(AppStrings.Common.cancel) {
                            guard !viewModel.isSavingProfile else { return }
                            isShowingEditProfileSheet = false
                        }
                    }
                }
                .onChange(of: selectedAvatarPhoto) { _, newValue in
                    Task {
                        await loadSelectedAvatarPhoto(item: newValue)
                    }
                }
            }
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            AppStrings.Profile.signOutConfirmTitle,
            isPresented: $isShowingLogoutConfirmation,
            titleVisibility: .visible
        ) {
            Button(AppStrings.Profile.signOut, role: .destructive) {
                let didSignOut = AuthService.shared.signOut()
                if !didSignOut {
                    logoutErrorMessage = AppStrings.Profile.signOutFailed
                }
            }

            Button(AppStrings.Common.cancel, role: .cancel) {}
        } message: {
            Text(AppStrings.Profile.signOutConfirmMessage)
        }
        .alert(AppStrings.Profile.signOutFailed, isPresented: Binding(
            get: { logoutErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    logoutErrorMessage = nil
                }
            }
        )) {
            Button(AppStrings.Common.ok, role: .cancel) {
                logoutErrorMessage = nil
            }
        } message: {
            Text(logoutErrorMessage ?? "")
        }
        .guestAccessAlert($guestAccessAction)
    }

    private func beginEditingProfile() {
        guard authState.isAuthenticated else {
            guestAccessAction = .profileEditing
            return
        }

        fullNameDraft = displayUser?.fullName ?? ""
        displayNameDraft = displayUser?.displayName ?? ""
        telegramUsernameDraft = displayUser?.telegramUsername ?? ""
        cityDraft = displayUser?.city ?? ""
        bioDraft = displayUser?.bio ?? ""
        selectedFederalStateDraft = displayUser?.selectedFederalState ?? .tirol
        selectedAvatarPhoto = nil
        selectedAvatarImageData = nil
        avatarPreviewImage = nil
        viewModel.profileMessage = nil
        isShowingEditProfileSheet = true
    }

    @MainActor
    private func loadSelectedAvatarPhoto(item: PhotosPickerItem?) async {
        guard let item else {
            selectedAvatarImageData = nil
            avatarPreviewImage = nil
            isLoadingAvatarSelection = false
            return
        }

        isLoadingAvatarSelection = true
        do {
            let data = try await item.loadTransferable(type: Data.self)
            guard
                let data,
                let image = UIImage(data: data)
            else {
                viewModel.profileMessage = AppStrings.Profile.avatarSelectionFailed
                selectedAvatarImageData = nil
                avatarPreviewImage = nil
                isLoadingAvatarSelection = false
                return
            }

            selectedAvatarImageData = data
            avatarPreviewImage = image
            viewModel.profileMessage = nil
            isLoadingAvatarSelection = false
        } catch {
            viewModel.profileMessage = AppStrings.Profile.avatarSelectionFailed
            selectedAvatarImageData = nil
            avatarPreviewImage = nil
            isLoadingAvatarSelection = false
        }
    }

    private func submitFeedback(for user: AppUser) {
        guard authState.isAuthenticated else {
            guestAccessAction = .feedback
            return
        }

        Task {
            let didSubmit = await viewModel.submitFeedback(
                type: selectedFeedbackType,
                message: feedbackMessage,
                user: user
            )
            if didSubmit {
                feedbackMessage = ""
                selectedFeedbackType = .question
            }
        }
    }
}

private struct ProfileHeaderCard: View {
    let sessionState: AuthSessionState
    let user: AppUser?
    let readableFederalState: String?
    let onEditProfile: () -> Void
    let onSignIn: () -> Void
    let onCreateAccount: () -> Void

    var body: some View {
        CommunityCard {
            if let user {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 14) {
                        ProfileAvatarView(user: user)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(user.preferredDisplayName)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(AppTheme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)

                            if let fullName = user.preferredFullName {
                                Text(fullName)
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 8) {
                                    if user.globalRole != .user {
                                        ProfileBadge(title: user.globalRole.title, systemImage: "person.badge.key")
                                    }

                                    if let readableFederalState {
                                        ProfileBadge(title: readableFederalState, systemImage: "globe.europe.africa")
                                    }
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    if user.globalRole != .user {
                                        ProfileBadge(title: user.globalRole.title, systemImage: "person.badge.key")
                                    }

                                    if let readableFederalState {
                                        ProfileBadge(title: readableFederalState, systemImage: "globe.europe.africa")
                                    }
                                }
                            }
                        }

                        Spacer(minLength: 0)
                    }

                    if let bio = user.bio.nilIfEmpty {
                        Text(bio)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        if let city = user.city.nilIfEmpty {
                            ProfileMetadataRow(
                                title: AppStrings.Common.city,
                                value: city,
                                systemImage: "mappin.and.ellipse"
                            )
                        }

                        if let telegramUsername = user.telegramUsername?.nilIfEmpty {
                            ProfileMetadataRow(
                                title: AppStrings.Profile.telegramUsername,
                                value: "@\(telegramUsername)",
                                systemImage: "paperplane"
                            )
                        }
                    }

                    Button(action: onEditProfile) {
                        Label(AppStrings.Profile.editProfile, systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity)
                    }
                    .appActionButtonStyle(.secondary)
                    .accessibilityIdentifier("profile.edit.button")
                    .accessibilityLabel(AppStrings.Profile.editProfile)
                }
            } else if sessionState == .restoring {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(AppStrings.Profile.loadingUserProfile)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppStrings.Profile.guestTitle)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(AppStrings.Profile.guestMessage)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 8) {
                        Button(AppStrings.Auth.signIn, action: onSignIn)
                            .frame(maxWidth: .infinity)
                            .appActionButtonStyle(.primary)
                            .accessibilityIdentifier("profile.guest.signIn")

                        Button(action: onCreateAccount) {
                            Text(AppStrings.Auth.createAccount)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(AppTheme.accentPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(AppTheme.surfacePrimary)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(AppTheme.accentPrimary.opacity(0.34), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("profile.guest.createAccount")
                    }
                }
                .accessibilityIdentifier("profile.guest.card")
            }
        }
        .accessibilityIdentifier("profile.account.hero")
    }
}

private struct ProfileAvatarView: View {
    let user: AppUser

    var body: some View {
        AvatarArtworkView(
            avatarURL: user.avatarURL,
            initials: user.initials,
            size: 72,
            accessibilityLabel: user.preferredDisplayName
        )
    }
}

private struct ProfileAvatarEditorCard: View {
    let avatarURL: URL?
    let initials: String
    let previewImage: UIImage?
    @Binding var selectedPhoto: PhotosPickerItem?
    let isLoadingAvatar: Bool
    let isSavingAvatar: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                AvatarArtworkView(
                    avatarURL: avatarURL,
                    previewImage: previewImage,
                    initials: initials,
                    size: 84,
                    isLoading: isLoadingAvatar || isSavingAvatar,
                    isDecorative: true
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text(AppStrings.Profile.changeAvatar)
                        .font(.headline)
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(AppStrings.Profile.avatarSubtitle)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                        Label(AppStrings.Profile.changeAvatar, systemImage: "camera.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSavingAvatar)
                    .accessibilityLabel(AppStrings.Profile.changeAvatar)

                    if isLoadingAvatar {
                        Text(AppStrings.Profile.avatarLoading)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if isSavingAvatar {
                        Text(AppStrings.Profile.avatarUploading)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ProfileMetadataRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        Label {
            HStack(spacing: 8) {
                Text(title)
                    .foregroundStyle(AppTheme.textSecondary)

                Spacer(minLength: 8)

                Text(value)
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.accentPrimary)
        }
        .font(.subheadline)
    }
}

private struct MyRegistrationsView: View {
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: MyRegistrationsViewModel
    let eventRepository: EventRepository

    private var calendar: Calendar { .current }

    private var upcomingEvents: [Event] {
        let startOfToday = calendar.startOfDay(for: Date())
        return viewModel.events.filter { $0.endDate >= startOfToday }
    }

    private var pastEvents: [Event] {
        let startOfToday = calendar.startOfDay(for: Date())
        return viewModel.events.filter { $0.endDate < startOfToday }
    }

    var body: some View {
        List {
            if viewModel.isLoading && viewModel.events.isEmpty {
                LoadingStateCard(title: AppStrings.Profile.registrationsLoading)
                    .listRowBackground(Color.clear)
            } else if let error = viewModel.error, viewModel.events.isEmpty {
                ErrorStateCard(
                    title: AppStrings.Profile.myRegistrations,
                    message: readableRegistrationsErrorText(error)
                )
                .listRowBackground(Color.clear)
            } else if viewModel.events.isEmpty {
                EmptyStateCard(
                    systemImage: "calendar.badge.clock",
                    title: AppStrings.Profile.myRegistrations,
                    message: AppStrings.Profile.registrationsEmptyMessage
                )
                .listRowBackground(Color.clear)
            } else {
                if !upcomingEvents.isEmpty {
                    Section(AppStrings.Events.upcomingTitle) {
                        ForEach(upcomingEvents) { event in
                            registrationRow(for: event)
                        }
                    }
                    .listRowBackground(AppTheme.surfacePrimary)
                }

                if !pastEvents.isEmpty {
                    Section(AppStrings.Events.pastTitle) {
                        ForEach(pastEvents) { event in
                            registrationRow(for: event)
                        }
                    }
                    .listRowBackground(AppTheme.surfacePrimary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.pageBackground)
        .navigationTitle(AppStrings.Profile.myRegistrations)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadIfNeeded()
            await viewModel.refreshIfStale()
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    @ViewBuilder
    private func registrationRow(for event: Event) -> some View {
        NavigationLink {
            RegisteredEventDetailContainer(event: event, repository: eventRepository)
        } label: {
            RegistrationEventRow(
                event: event,
                isUpdating: viewModel.pendingCancellationIDs.contains(event.id)
            )
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task {
                    await viewModel.cancelRegistration(for: event.id)
                }
            } label: {
                Text(AppStrings.Action.cancelRegistration)
            }
            .disabled(viewModel.pendingCancellationIDs.contains(event.id))
        }
        .accessibilityLabel("\(event.title), \(registrationEventScheduleText(for: event))")
    }

    private func readableRegistrationsErrorText(_ error: AppError) -> String {
        switch error {
        case .network:
            AppStrings.Events.loadNetworkError
        case .permissionDenied:
            AppStrings.Events.loadPermissionError
        case .validationFailed:
            AppStrings.Events.loadValidationError
        case .notFound:
            AppStrings.Profile.registrationsEmptyMessage
        case .unknown:
            AppStrings.Events.loadUnknownError
        }
    }
}

private struct RegisteredEventDetailContainer: View {
    let event: Event
    @StateObject private var detailViewModel: EventsViewModel

    init(event: Event, repository: EventRepository) {
        self.event = event
        _detailViewModel = StateObject(wrappedValue: EventsViewModel(repository: repository))
    }

    var body: some View {
        EventDetailView(
            viewModel: detailViewModel,
            eventID: event.id,
            onEventDeleted: {}
        )
        .environment(\.eventPresentationMode, .public)
    }
}

private struct RegistrationEventRow: View {
    let event: Event
    let isUpdating: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(event.title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(event.summary)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)

                Label(registrationEventScheduleText(for: event), systemImage: "calendar")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)

                Label("\(event.city), \(event.venue)", systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if isUpdating {
                ProgressView()
                    .controlSize(.small)
                    .tint(AppTheme.accentPrimary)
            } else {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
        .opacity(isUpdating ? 0.7 : 1)
    }
}

private func registrationEventScheduleText(for event: Event) -> String {
    let startDateText = LocalizationStore.dateString(from: event.startDate, dateStyle: .medium, timeStyle: .short)

    guard event.endDate > event.startDate else {
        return startDateText
    }

    let isSameDay = Calendar.current.isDate(event.startDate, inSameDayAs: event.endDate)
    if isSameDay {
        let endTimeText = LocalizationStore.dateString(from: event.endDate, dateStyle: .none, timeStyle: .short)
        return "\(startDateText) - \(endTimeText)"
    }

    let endDateText = LocalizationStore.dateString(from: event.endDate, dateStyle: .medium, timeStyle: .short)
    return "\(startDateText) - \(endDateText)"
}

private struct FeedbackComposerCard: View {
    @Binding var selectedFeedbackType: FeedbackType
    @Binding var feedbackMessage: String
    let statusMessage: String?
    let isSubmitting: Bool
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppStrings.Feedback.subtitle)
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            LabeledContent(AppStrings.Feedback.fieldType) {
                Picker(AppStrings.Feedback.fieldType, selection: $selectedFeedbackType) {
                    ForEach(FeedbackType.allCases) { feedbackType in
                        Text(feedbackType.title).tag(feedbackType)
                    }
                }
                .pickerStyle(.menu)
            }
            .accessibilityLabel(AppStrings.Feedback.fieldType)

            VStack(alignment: .leading, spacing: 8) {
                Text(AppStrings.Feedback.fieldMessage)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)

                ZStack(alignment: .topLeading) {
                    if feedbackMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(AppStrings.Feedback.fieldMessage)
                            .font(.body)
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 14)
                    }

                    TextEditor(text: $feedbackMessage)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 92)
                        .padding(8)
                        .background(Color.clear)
                }
                .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.borderSubtle)
                )
                .accessibilityLabel(AppStrings.Feedback.fieldMessage)
            }

            if let statusMessage {
                InlineMessageCard(
                    style: statusMessage == AppStrings.Feedback.submitted ? .success : .error,
                    message: statusMessage
                )
            }

            Button(action: onSubmit) {
                if isSubmitting {
                    ProgressView(AppStrings.Feedback.submit)
                        .frame(maxWidth: .infinity)
                } else {
                    Text(AppStrings.Feedback.submit)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(AppTheme.accentPrimary)
            .disabled(isSubmitting)
            .accessibilityLabel(AppStrings.Feedback.submit)
        }
        .padding(.vertical, 2)
    }
}

private struct ProfileBadge: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.accentPrimary)
            .multilineTextAlignment(.leading)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(AppTheme.accentPrimarySoft, in: Capsule())
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct AppNewsManagementView: View {
    private let repository: NewsRepository
    @StateObject private var viewModel: NewsViewModel

    init(repository: NewsRepository = FirestoreNewsRepository()) {
        self.repository = repository
        _viewModel = StateObject(wrappedValue: NewsViewModel(repository: repository))
    }

    var body: some View {
        NewsListView(
            viewModel: viewModel,
            newsRepository: repository,
            onNewsPublished: {},
            onNewsChanged: {},
            presentationMode: .management
        )
    }
}

private struct AppEventsManagementView: View {
    private let repository: EventRepository
    @StateObject private var viewModel: EventsViewModel

    init(repository: EventRepository = FirestoreEventRepository()) {
        self.repository = repository
        _viewModel = StateObject(wrappedValue: EventsViewModel(repository: repository))
    }

    var body: some View {
        EventsListView(
            viewModel: viewModel,
            eventRepository: repository,
            onEventPublished: {},
            onEventDeleted: { @MainActor @Sendable in },
            presentationMode: .management
        )
    }
}

private struct OrganizationManagementHubView: View {
    @EnvironmentObject private var authState: AuthState
    let currentUser: AppUser

    private let repository: OrganizationRepository
    @StateObject private var organizationsViewModel: OrganizationsViewModel
    @State private var isShowingCreateOrganization = false

    init(
        currentUser: AppUser,
        repository: OrganizationRepository = FirestoreOrganizationRepository()
    ) {
        self.currentUser = currentUser
        self.repository = repository
        _organizationsViewModel = StateObject(wrappedValue: OrganizationsViewModel(repository: repository))
    }

    private var manageableOrganizations: [Organization] {
        switch currentUser.globalRole {
        case .owner, .topAdmin:
            return organizationsViewModel.organizations
        case .appModerator, .user:
            let manageableIDs = PermissionService.manageableOrganizationIDs(user: currentUser)
            return organizationsViewModel.organizations.filter { manageableIDs.contains($0.id) }
        }
    }

    private var canCreateOrganization: Bool {
        PermissionService.canCreateOrganization(user: currentUser)
    }

    var body: some View {
        List {
            Section {
                Text(AppStrings.Profile.organizationManagementSubtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(AppTheme.surfacePrimary)

            if canCreateOrganization {
                Section {
                    Button {
                        isShowingCreateOrganization = true
                    } label: {
                        AppNavigationRow(
                            title: AppStrings.Organizations.editorTitle,
                            subtitle: AppStrings.Profile.organizationManagementSubtitle,
                            systemImage: "plus.circle",
                            accessory: .none
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("organization.management.create")
                    .accessibilityLabel(AppStrings.Organizations.editorTitle)
                }
                .listRowBackground(AppTheme.surfacePrimary)
            }

            if organizationsViewModel.isLoading && manageableOrganizations.isEmpty {
                Section {
                    LoadingStateCard(title: nil)
                }
                .listRowBackground(AppTheme.surfacePrimary)
            } else if manageableOrganizations.isEmpty {
                Section {
                    EmptyStateCard(
                        systemImage: "building.2",
                        title: AppStrings.Profile.myOrganizations,
                        message: AppStrings.Profile.noManagedOrganizations
                    )
                }
                .listRowBackground(AppTheme.surfacePrimary)
            } else {
                Section {
                    ForEach(manageableOrganizations) { organization in
                        NavigationLink {
                            ManagedOrganizationView(
                                organization: organization,
                                organizationsViewModel: organizationsViewModel
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(organization.name)
                                    .font(.headline)

                                Text(organization.city)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                        .accessibilityLabel(organization.name)
                    }
                }
                .listRowBackground(AppTheme.surfacePrimary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.pageBackground)
        .navigationTitle(AppStrings.Profile.organizationManagement)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await organizationsViewModel.loadIfNeeded()
            await organizationsViewModel.refreshIfStale()
        }
        .refreshable {
            await organizationsViewModel.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .organizationsChanged).debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { _ in
            Task {
                await organizationsViewModel.refresh()
            }
        }
        .sheet(isPresented: $isShowingCreateOrganization) {
            NavigationStack {
                OrganizationEditorView(
                    organizationsViewModel: organizationsViewModel,
                    onSaved: {
                        await organizationsViewModel.refresh()
                    }
                )
            }
            .environmentObject(authState)
        }
    }
}

private struct ManagedOrganizationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authState: AuthState

    let organization: Organization
    @ObservedObject var organizationsViewModel: OrganizationsViewModel

    @State private var isShowingNewsEditor = false
    @State private var isShowingEventEditor = false
    @State private var isShowingOrganizationEditor = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isDeletingOrganization = false
    @State private var deleteErrorMessage: String?

    private var currentOrganization: Organization {
        organizationsViewModel.organization(for: organization.id) ?? organization
    }

    private var canCreateNews: Bool {
        PermissionService.canCreateNews(for: currentOrganization.id, user: authState.user)
    }

    private var canCreateEvent: Bool {
        PermissionService.canCreateEvent(for: currentOrganization.id, user: authState.user)
    }

    private var canEditOrganization: Bool {
        PermissionService.canEditOrganization(organizationId: currentOrganization.id, user: authState.user)
    }

    private var canDeleteOrganization: Bool {
        PermissionService.canDeleteOrganization(user: authState.user)
    }

    var body: some View {
        List {
            Section(AppStrings.Profile.myOrganizations) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(currentOrganization.name)
                        .font(.title3.weight(.semibold))

                    Text(currentOrganization.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                MetadataRow(label: AppStrings.Common.city, value: currentOrganization.city, systemImage: "mappin.and.ellipse")

                if let contactEmail = currentOrganization.contactEmail, !contactEmail.isEmpty {
                    MetadataRow(label: AppStrings.Common.contact, value: contactEmail, systemImage: "envelope")
                }

                if let website = currentOrganization.website, !website.isEmpty {
                    MetadataRow(label: AppStrings.Common.website, value: website, systemImage: "link")
                }
            }
            .listRowBackground(AppTheme.surfacePrimary)

            Section(AppStrings.Profile.organizationManagement) {
                if canCreateNews {
                    Button {
                        isShowingNewsEditor = true
                    } label: {
                        Label(AppStrings.Profile.createOrganizationNews, systemImage: "square.and.pencil")
                    }
                    .accessibilityLabel(AppStrings.Profile.createOrganizationNews)
                }

                if canCreateEvent {
                    Button {
                        isShowingEventEditor = true
                    } label: {
                        Label(AppStrings.Profile.createOrganizationEvent, systemImage: "calendar.badge.plus")
                    }
                    .accessibilityLabel(AppStrings.Profile.createOrganizationEvent)
                }

                if canEditOrganization {
                    Button {
                        isShowingOrganizationEditor = true
                    } label: {
                        Label(AppStrings.Profile.editOrganizationDetails, systemImage: "building.2.crop.circle")
                    }
                    .accessibilityLabel(AppStrings.Profile.editOrganizationDetails)
                }

                if canDeleteOrganization {
                    Button(role: .destructive) {
                        isShowingDeleteConfirmation = true
                    } label: {
                        Label(AppStrings.Organizations.delete, systemImage: "trash")
                    }
                    .disabled(isDeletingOrganization)
                    .accessibilityLabel(AppStrings.Organizations.delete)
                }
            }
            .listRowBackground(AppTheme.surfacePrimary)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.pageBackground)
        .navigationTitle(currentOrganization.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingNewsEditor) {
            NavigationStack {
                NewsEditorView(
                    repository: FirestoreNewsRepository(),
                    organizationId: currentOrganization.id,
                    organizationName: currentOrganization.name,
                    organizationImageURL: currentOrganization.imageURL
                )
            }
        }
        .sheet(isPresented: $isShowingEventEditor) {
            NavigationStack {
                EventEditorView(
                    repository: FirestoreEventRepository(),
                    organizationId: currentOrganization.id,
                    organizationName: currentOrganization.name,
                    organizationImageURL: currentOrganization.imageURL
                )
            }
        }
        .sheet(isPresented: $isShowingOrganizationEditor) {
            NavigationStack {
                OrganizationEditorView(
                    organizationsViewModel: organizationsViewModel,
                    organization: currentOrganization,
                    onSaved: {}
                )
            }
        }
        .confirmationDialog(
            AppStrings.Organizations.deleteConfirmation,
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(AppStrings.Organizations.delete, role: .destructive) {
                Task {
                    await deleteOrganization()
                }
            }

            Button(AppStrings.Organizations.cancel, role: .cancel) {}
        }
        .alert(
            AppStrings.Organizations.deleteFailed,
            isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { if !$0 { deleteErrorMessage = nil } }
            )
        ) {
            Button(AppStrings.Organizations.dismissError, role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "")
        }
    }

    @MainActor
    private func deleteOrganization() async {
        guard !isDeletingOrganization else { return }
        isDeletingOrganization = true
        defer { isDeletingOrganization = false }

        do {
            try await organizationsViewModel.deleteOrganization(id: currentOrganization.id, user: authState.user)
            organizationsViewModel.removeDeletedOrganization(id: currentOrganization.id)
            dismiss()
        } catch let appError as AppError {
            deleteErrorMessage = readableManagedOrganizationErrorText(appError)
        } catch {
            deleteErrorMessage = readableManagedOrganizationErrorText(.unknown)
        }
    }

    private func readableManagedOrganizationErrorText(_ error: AppError?) -> String {
        switch error {
        case .network:
            AppStrings.Organizations.loadNetworkError
        case .permissionDenied:
            AppStrings.Organizations.actionPermissionError
        case .validationFailed:
            AppStrings.Organizations.actionValidationError
        case .notFound:
            AppStrings.Organizations.actionNotFoundError
        case .unknown:
            AppStrings.Organizations.actionUnknownError
        case nil:
            AppStrings.Organizations.actionUnknownError
        }
    }
}

#Preview {
    NavigationStack {
        ProfileView(
            viewModel: ProfileViewModel(
                repository: MockUserRepository(),
                feedbackRepository: MockFeedbackRepository()
            ),
            eventRepository: MockEventRepository()
        )
    }
    .environmentObject(AuthState())
}
