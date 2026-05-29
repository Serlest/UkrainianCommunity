import PhotosUI
import SwiftUI


struct ProfileView: View {
    @ObservedObject var viewModel: ProfileViewModel
    private let feedbackRepository: FeedbackRepository
    private let newsRepository: NewsRepository
    private let eventRepository: EventRepository
    private let organizationRepository: OrganizationRepository
    private let guideRepository: GuideRepository
    private let notificationInboxRepository: NotificationInboxRepository
    @EnvironmentObject var authState: AuthState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @StateObject private var registrationsViewModel: MyRegistrationsViewModel
    @StateObject private var myFeedbackViewModel: MyFeedbackViewModel
    @StateObject private var ownerOrganizationsViewModel: OrganizationsViewModel
    @StateObject private var ownerVisibilityViewModel: OwnerProfileVisibilityViewModel
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
    @State private var isShowingDeleteAccountConfirmation = false
    @State private var isShowingDeleteAccountSheet = false
    @State private var deleteAccountConfirmationText = ""
    @State private var deleteAccountErrorMessage: String?

    init(
        viewModel: ProfileViewModel,
        feedbackRepository: FeedbackRepository = FirestoreFeedbackRepository(),
        newsRepository: NewsRepository = FirestoreNewsRepository(),
        eventRepository: EventRepository,
        organizationRepository: OrganizationRepository = FirestoreOrganizationRepository(),
        guideRepository: GuideRepository = FirestoreGuideRepository(),
        notificationInboxRepository: NotificationInboxRepository = FirestoreNotificationInboxRepository(),
        localEventReminderService: LocalEventReminderServiceProtocol = LocalEventReminderService()
    ) {
        self.viewModel = viewModel
        self.feedbackRepository = feedbackRepository
        self.newsRepository = newsRepository
        self.eventRepository = eventRepository
        self.organizationRepository = organizationRepository
        self.guideRepository = guideRepository
        self.notificationInboxRepository = notificationInboxRepository
        _registrationsViewModel = StateObject(wrappedValue: MyRegistrationsViewModel(
            repository: eventRepository,
            localEventReminderService: localEventReminderService
        ))
        _myFeedbackViewModel = StateObject(wrappedValue: MyFeedbackViewModel(repository: feedbackRepository))
        _ownerOrganizationsViewModel = StateObject(wrappedValue: OrganizationsViewModel(
            repository: organizationRepository,
            notificationInboxRepository: notificationInboxRepository
        ))
        _ownerVisibilityViewModel = StateObject(wrappedValue: OwnerProfileVisibilityViewModel(
            feedbackRepository: feedbackRepository,
            organizationRepository: organizationRepository
        ))
    }

    private var permissionUser: AppUser? {
        authState.user
    }

    private var canShowAdminTools: Bool {
        PermissionService.canAccessAdminTools(user: permissionUser)
    }

    private var canShowModerationTools: Bool {
        PermissionService.canAccessModerationTools(user: permissionUser)
    }

    private var canShowOrganizationManagement: Bool {
        guard let user = permissionUser else { return false }
        if user.globalRole.authorizationRole == .owner {
            return true
        }
        if PermissionService.canCreateOrganization(user: user) {
            return true
        }
        if !PermissionService.manageableOrganizations(
            from: ownerOrganizationsViewModel.organizations,
            user: user
        ).isEmpty {
            return true
        }
        return false
    }

    private var canShowGuideManagement: Bool {
        PermissionService.canManageGuide(user: permissionUser)
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
        canShowModerationTools || canShowAdminTools || canShowGuideManagement
    }

    private var profileDashboardMode: ProfileDashboardMode? {
        guard let user = permissionUser else { return nil }
        return ProfileDashboardMode(user: user)
    }

    private var shouldLoadOwnerVisibility: Bool {
        permissionUser?.globalRole.authorizationRole == .owner
    }

    private var organizationRoleMemberships: [CommunityMembership] {
        guard let user = permissionUser else { return [] }

        let organizationMemberships = PermissionService.manageableOrganizations(
            from: ownerOrganizationsViewModel.organizations,
            user: user
        )
        .compactMap { organization -> CommunityMembership? in
            guard let role = PermissionService.organizationRole(for: organization, user: user) else {
                return nil
            }
            return CommunityMembership(organizationId: organization.id, role: role)
        }

        return organizationMemberships
            .filter { $0.role != .member }
            .sorted { lhs, rhs in
                organizationRoleSortValue(lhs.role) < organizationRoleSortValue(rhs.role)
            }
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

    private var registrationsSectionSubtitle: String {
        if registrationsViewModel.isLoading && registrationsViewModel.events.isEmpty {
            return AppStrings.Profile.registrationsLoading
        }

        if registrationsViewModel.registrationsCount == 0 {
            return AppStrings.Profile.registrationsEmptySummary
        }

        return AppStrings.profileRegistrationsCount(registrationsViewModel.registrationsCount)
    }

    private var upcomingRegistrationPreviews: [Event] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return Array(registrationsViewModel.events
            .filter { $0.endDate >= startOfToday }
            .sorted { $0.startDate < $1.startDate }
            .prefix(2))
    }

    private var recentRegistrationPreviews: [Event] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return Array(registrationsViewModel.events
            .filter { $0.endDate < startOfToday }
            .sorted { $0.endDate > $1.endDate }
            .prefix(2))
    }

    var body: some View {
        ZStack {
            AppBackgroundView()
                .allowsHitTesting(false)

            GeometryReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                        profileHeader

                        profileTitleBlock

                        AppGroupedContentPlane {
                            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                                if let user = displayUser {
                                    userProfileContent(for: user)
                                } else {
                                    guestProfileContent
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, AppTheme.pageHorizontal)
                    .padding(.top, AppTheme.sectionSpacing)
                    .padding(.bottom, AppTheme.homeBottomContentPadding + 32)
                    .frame(width: proxy.size.width, alignment: .topLeading)
                }
                .frame(width: proxy.size.width)
            }
        }
        .tint(AppTheme.accentPrimary)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.loadIfNeeded()
            await viewModel.refreshIfStale()
            if authState.isAuthenticated {
                await registrationsViewModel.loadIfNeeded()
                await registrationsViewModel.refreshIfStale()
                if let userID = authState.user?.id {
                    await myFeedbackViewModel.loadIfNeeded(userID: userID)
                    await viewModel.loadNotificationPreferencesIfNeeded(userID: userID)
                }
                await ownerOrganizationsViewModel.loadIfNeeded()
                await ownerOrganizationsViewModel.refreshIfStale()
                if shouldLoadOwnerVisibility {
                    await ownerVisibilityViewModel.loadIfNeeded()
                } else {
                    ownerVisibilityViewModel.reset()
                }
            } else {
                registrationsViewModel.resetForGuest()
                myFeedbackViewModel.reset()
                ownerVisibilityViewModel.reset()
            }
        }
        .refreshable {
            await viewModel.refresh()
            if authState.isAuthenticated {
                await registrationsViewModel.refresh()
                if let userID = authState.user?.id {
                    await myFeedbackViewModel.refresh(userID: userID)
                    await viewModel.refreshNotificationPreferences(userID: userID)
                }
                await ownerOrganizationsViewModel.refresh()
                if shouldLoadOwnerVisibility {
                    await ownerVisibilityViewModel.refresh()
                } else {
                    ownerVisibilityViewModel.reset()
                }
            }
        }
        .onChange(of: authState.isAuthenticated) { _, isAuthenticated in
            Task {
                if isAuthenticated {
                    await registrationsViewModel.refresh()
                    if let userID = authState.user?.id {
                        await myFeedbackViewModel.refresh(userID: userID)
                        await viewModel.refreshNotificationPreferences(userID: userID)
                    }
                    await ownerOrganizationsViewModel.refresh()
                    if shouldLoadOwnerVisibility {
                        await ownerVisibilityViewModel.refresh()
                    } else {
                        ownerVisibilityViewModel.reset()
                    }
                } else {
                    registrationsViewModel.resetForGuest()
                    myFeedbackViewModel.reset()
                    ownerOrganizationsViewModel.resetForAuthChange()
                    ownerVisibilityViewModel.reset()
                    feedbackMessage = ""
                    selectedFeedbackType = .question
                }
            }
        }
        .onChange(of: authState.user?.id) { _, newUserID in
            Task {
                registrationsViewModel.resetForAuthChange()
                myFeedbackViewModel.reset()
                ownerOrganizationsViewModel.resetForAuthChange()
                ownerVisibilityViewModel.reset()
                guard let newUserID else { return }
                await registrationsViewModel.refresh()
                await myFeedbackViewModel.refresh(userID: newUserID)
                await viewModel.refreshNotificationPreferences(userID: newUserID)
                await ownerOrganizationsViewModel.refresh()
                if shouldLoadOwnerVisibility {
                    await ownerVisibilityViewModel.refresh()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .organizationsChanged)) { _ in
            guard authState.isAuthenticated else { return }
            Task {
                await ownerOrganizationsViewModel.refresh()
                if shouldLoadOwnerVisibility {
                    await ownerVisibilityViewModel.refresh()
                }
            }
        }
        .sheet(isPresented: $isShowingEditProfileSheet) {
            NavigationStack {
                editProfileContent
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
        .confirmationDialog(
            AppStrings.Profile.deleteAccountConfirmTitle,
            isPresented: $isShowingDeleteAccountConfirmation,
            titleVisibility: .visible
        ) {
            Button(AppStrings.Profile.deleteAccount, role: .destructive) {
                deleteAccountConfirmationText = ""
                isShowingDeleteAccountSheet = true
            }

            Button(AppStrings.Common.cancel, role: .cancel) {}
        } message: {
            Text(AppStrings.Profile.deleteAccountConfirmMessage)
        }
        .sheet(isPresented: $isShowingDeleteAccountSheet) {
            deleteAccountConfirmationSheet
                .presentationDragIndicator(.visible)
        }
        .alert(AppStrings.Profile.deleteAccount, isPresented: Binding(
            get: { deleteAccountErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    deleteAccountErrorMessage = nil
                }
            }
        )) {
            Button(AppStrings.Common.ok, role: .cancel) {
                deleteAccountErrorMessage = nil
            }
        } message: {
            Text(deleteAccountErrorMessage ?? "")
        }
        .guestAccessAlert($guestAccessAction)
    }

    private var profileTitleBlock: some View {
        SectionHeaderBlock(title: AppStrings.Profile.title)
    }

    private var profileHeader: some View {
        AppBrandHeader {
            HStack(spacing: AppTheme.eventsControlGroupSpacing) {
                AppNotificationBellButton()

                if displayUser != nil {
                    AppGlassIconButton(systemImage: "slider.horizontal.3", accessibilityLabel: AppStrings.Profile.editProfile) {
                        beginEditingProfile()
                    }
                }
            }
        }
    }

    private var deleteAccountConfirmationSheet: some View {
        NavigationStack {
            ZStack {
                AppBackgroundView()
                    .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    SectionHeaderBlock(
                        title: AppStrings.Profile.deleteAccountConfirmTitle,
                        subtitle: AppStrings.Profile.deleteAccountConfirmMessage
                    )

                    AppEditorSectionCard {
                        VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                            Text(AppStrings.Profile.deleteAccountTypePrompt)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)

                            TextField(AppStrings.Profile.deleteAccountConfirmationKeyword, text: $deleteAccountConfirmationText)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))

                            Button(role: .destructive) {
                                Task {
                                    await performAccountDeletion()
                                }
                            } label: {
                                if viewModel.isDeletingAccount {
                                    Label(AppStrings.Profile.deleteAccountInProgress, systemImage: "hourglass")
                                } else {
                                    Label(AppStrings.Profile.deleteAccountFinalAction, systemImage: "trash")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.accentDestructive)
                            .disabled(!canConfirmAccountDeletion || viewModel.isDeletingAccount)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(AppTheme.pageHorizontal)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.Common.cancel) {
                        isShowingDeleteAccountSheet = false
                    }
                }
            }
        }
    }

    private var canConfirmAccountDeletion: Bool {
        deleteAccountConfirmationText.trimmingCharacters(in: .whitespacesAndNewlines) == AppStrings.Profile.deleteAccountConfirmationKeyword
    }

    private var editProfileContent: some View {
        ZStack(alignment: .bottom) {
            AppBackgroundView()
                .allowsHitTesting(false)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    SectionHeaderBlock(
                        title: AppStrings.Profile.editProfile,
                        subtitle: AppStrings.Profile.editProfileSubtitle
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ProfileAvatarEditorCard(
                        avatarURL: displayUser?.avatarURL,
                        initials: displayUser?.initials ?? "UC",
                        previewImage: avatarPreviewImage,
                        selectedPhoto: $selectedAvatarPhoto,
                        isLoadingAvatar: isLoadingAvatarSelection,
                        isSavingAvatar: viewModel.isSavingProfile && selectedAvatarImageData != nil
                    )

                    editProfileMainInfoSection
                    editProfileAppSettingsSection
                    notificationsSection

                    if let profileStatusMessage {
                        InlineMessageCard(style: profileStatusStyle, message: profileStatusMessage)
                            .accessibilityLabel(profileStatusMessage)
                    }

                    if let profileValidationHint {
                        InlineMessageCard(style: .info, message: profileValidationHint)
                    }
                }
                .padding(.horizontal, AppTheme.pageHorizontal)
                .padding(.top, AppTheme.sectionSpacing)
                .padding(.bottom, AppTheme.homeBottomContentPadding + 84)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                PrimaryActionButton(
                    title: AppStrings.Profile.saveChanges,
                    loadingTitle: AppStrings.Profile.savingProfile,
                    isEnabled: canSaveProfile,
                    isLoading: viewModel.isSavingProfile || isLoadingAvatarSelection,
                    systemImage: "checkmark"
                ) {
                    saveProfileChanges()
                }
                .padding(.horizontal, AppTheme.pageHorizontal)
                .padding(.top, AppTheme.eventsMetadataSpacing)
                .padding(.bottom, AppTheme.eventsMetadataSpacing)
                .background {
                    if reduceTransparency {
                        AppTheme.glassFallbackSurface(for: colorScheme)
                    } else {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                    }
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

    private var editProfileMainInfoSection: some View {
        ProfileSectionCard(title: AppStrings.Profile.mainInformation) {
            VStack(spacing: AppTheme.dashboardSpacing) {
                EditorTextField(AppStrings.Profile.displayName, text: $displayNameDraft, systemImage: "person", autocapitalization: .words)
                EditorTextField(AppStrings.Profile.fullName, text: $fullNameDraft, systemImage: "person.text.rectangle", autocapitalization: .words)
                EditorTextField(AppStrings.Common.city, text: $cityDraft, systemImage: "mappin.and.ellipse", autocapitalization: .words)
                ProfileEditorPickerRow(title: AppStrings.Auth.federalState, systemImage: "globe.europe.africa") {
                    Picker(AppStrings.Auth.federalState, selection: $selectedFederalStateDraft) {
                        ForEach(AustrianFederalState.allCases) { state in
                            Text(AppStrings.FederalStates.title(for: state)).tag(state)
                        }
                    }
                    .labelsHidden()
                }
                EditorTextField(
                    AppStrings.Profile.telegramUsername,
                    text: $telegramUsernameDraft,
                    systemImage: "paperplane",
                    autocapitalization: .never,
                    autocorrectionDisabled: true
                )
                ProfileEditorTextArea(title: AppStrings.Profile.bio, text: $bioDraft, counterText: AppStrings.profileBioCounter(bioDraft.count, 240))

                ProfileReadOnlyField(
                    title: AppStrings.Auth.email,
                    value: displayUser?.email ?? "",
                    systemImage: "envelope",
                    helperText: AppStrings.Profile.emailReadOnlyHint
                )
            }
        }
    }

    private var editProfileAppSettingsSection: some View {
        ProfileSectionCard(
            title: AppStrings.Profile.appSettings,
            subtitle: AppStrings.Profile.appSettingsSubtitle
        ) {
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
            }
        }
    }

    @ViewBuilder
    private var guestProfileContent: some View {
        GuestPlatformHeroCard(
            onSignIn: { authState.presentAuthFlow(.login) },
            onCreateAccount: { authState.presentAuthFlow(.register) }
        )

        ProfileSectionCard(
            title: AppStrings.Profile.afterRegistrationTitle,
            subtitle: AppStrings.Profile.afterRegistrationSubtitle
        ) {
            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                ProfileModuleRow(title: AppStrings.Profile.myEvents, subtitle: AppStrings.Profile.afterRegistrationEventsSubtitle, systemImage: "calendar", status: .accountRequired, accessory: .none)
                ProfileModuleRow(title: AppStrings.Profile.savedContent, subtitle: AppStrings.Profile.afterRegistrationSavedSubtitle, systemImage: "bookmark", status: .accountRequired, accessory: .none)
                ProfileModuleRow(title: AppStrings.Profile.organizationSubscriptions, subtitle: AppStrings.Profile.organizationSubscriptionsSubtitle, systemImage: "person.2", status: .accountRequired, accessory: .none)
                ProfileModuleRow(title: AppStrings.Profile.personalRegion, subtitle: AppStrings.Profile.personalRegionSubtitle, systemImage: "mappin.and.ellipse", status: .accountRequired, accessory: .none)
            }
        }

        ProfileSectionCard(
            title: AppStrings.Profile.guestAvailableTitle,
            subtitle: AppStrings.Profile.guestAvailableSubtitle
        ) {
            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                ProfileModuleRow(title: AppStrings.Profile.guestBrowseNews, subtitle: AppStrings.Profile.previewNewsSubtitle, systemImage: "newspaper", status: .available, accessory: .none)
                ProfileModuleRow(title: AppStrings.Profile.guestBrowseEvents, subtitle: AppStrings.Profile.previewEventsSubtitle, systemImage: "calendar", status: .available, accessory: .none)
                ProfileModuleRow(title: AppStrings.Profile.guestBrowseOrganizations, subtitle: AppStrings.Profile.previewOrganizationsSubtitle, systemImage: "building.2", status: .available, accessory: .none)
                ProfileModuleRow(title: AppStrings.Guide.title, subtitle: AppStrings.Profile.previewGuideSubtitle, systemImage: "book.closed", status: .available, accessory: .none)
            }
        }

        guestSettingsSupportSection
    }

    @ViewBuilder
    private func userProfileContent(for user: AppUser) -> some View {
        if let profileDashboardMode {
            switch profileDashboardMode {
            case .owner:
                ownerControlCenterContent(for: user)
            }
        } else {
            ProfileHeroCard(
                user: user,
                readableFederalState: readableFederalState,
                onEditProfile: beginEditingProfile
            )

            quickActionsSection(for: user)
            guideManagementSection
            supportSection(for: user)
            accountDeletionSection
            logoutSection
        }
    }

    @ViewBuilder
    private func ownerControlCenterContent(for user: AppUser) -> some View {
        OwnerHeroCard(user: user, readableFederalState: readableFederalState, mode: .owner)
        quickActionsSection(for: user)
        ownerPlatformManagementSection
        logoutSection
    }

    private func quickActionsSection(for user: AppUser) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: AppTheme.eventsMetadataSpacing),
                GridItem(.flexible(), spacing: AppTheme.eventsMetadataSpacing)
            ],
            spacing: AppTheme.eventsMetadataSpacing
        ) {
            NavigationLink {
                OrganizationManagementHubView()
            } label: {
                ProfileQuickActionCard(item: ProfileQuickActionItem(
                    title: AppStrings.Profile.myOrganizations,
                    subtitle: AppStrings.Profile.organizationManagementIntro,
                    systemImage: "building.2",
                    status: .available
                ))
            }
            .buttonStyle(.plain)

            NavigationLink {
                MyRegistrationsView(viewModel: registrationsViewModel, eventRepository: eventRepository)
            } label: {
                ProfileQuickActionCard(item: ProfileQuickActionItem(
                    title: AppStrings.Profile.myEvents,
                    subtitle: AppStrings.Profile.quickActionRegisteredEventsSubtitle,
                    systemImage: "calendar",
                    status: .available
                ))
            }
            .buttonStyle(.plain)

            NavigationLink {
                SavedContentView(
                    newsRepository: newsRepository,
                    eventRepository: eventRepository,
                    organizationRepository: organizationRepository
                )
            } label: {
                ProfileQuickActionCard(item: ProfileQuickActionItem(
                    title: AppStrings.Profile.savedContent,
                    subtitle: AppStrings.Profile.quickActionSavedContentSubtitle,
                    systemImage: "bookmark",
                    status: .available
                ))
            }
            .buttonStyle(.plain)

            NavigationLink {
                FollowedOrganizationsView(organizationRepository: organizationRepository)
            } label: {
                ProfileQuickActionCard(item: ProfileQuickActionItem(
                    title: AppStrings.Profile.organizationSubscriptions,
                    subtitle: AppStrings.Profile.quickActionSubscriptionsSubtitle,
                    systemImage: "person.2",
                    status: .available
                ))
            }
            .buttonStyle(.plain)

            NavigationLink {
                RecentViewsView(
                    newsRepository: newsRepository,
                    eventRepository: eventRepository,
                    organizationRepository: organizationRepository
                )
            } label: {
                ProfileQuickActionCard(item: ProfileQuickActionItem(
                    title: AppStrings.Profile.recentlyViewed,
                    subtitle: AppStrings.Profile.recentlyViewedSubtitle,
                    systemImage: "clock.arrow.circlepath",
                    status: .available
                ))
            }
            .buttonStyle(.plain)

            NavigationLink {
                ActivityHistoryView(
                    newsRepository: newsRepository,
                    eventRepository: eventRepository,
                    organizationRepository: organizationRepository
                )
            } label: {
                ProfileQuickActionCard(item: ProfileQuickActionItem(
                    title: AppStrings.Profile.activityHistoryModule,
                    subtitle: AppStrings.Profile.quickActionActivitySubtitle,
                    systemImage: "list.bullet.rectangle",
                    status: .available
                ))
            }
            .buttonStyle(.plain)
        }
    }

    private var moderatorQuickActionsSection: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: AppTheme.eventsMetadataSpacing),
                GridItem(.flexible(), spacing: AppTheme.eventsMetadataSpacing)
            ],
            spacing: AppTheme.eventsMetadataSpacing
        ) {
            NavigationLink {
                ModerationToolsView(
                    organizationRepository: organizationRepository,
                    notificationInboxRepository: notificationInboxRepository
                )
            } label: {
                ProfileQuickActionCard(item: ProfileQuickActionItem(title: AppStrings.Profile.moderatorModerationQueue, subtitle: AppStrings.Profile.ownerPendingReviewSubtitle, systemImage: "clock.badge.exclamationmark", status: canShowModerationTools ? .active : .locked))
            }
            .buttonStyle(.plain)

        }
    }

    private func profileStats(for user: AppUser) -> [ProfileStatItem] {
        [
            ProfileStatItem(title: AppStrings.Profile.statRegistrations, value: registrationsViewModel.registrationsCountText, systemImage: "calendar.badge.clock"),
            ProfileStatItem(title: AppStrings.Profile.statLiked, value: AppStrings.Profile.notAvailableValue, systemImage: "heart"),
            ProfileStatItem(title: AppStrings.Profile.statOrganizations, value: "\(profileOrganizationCount(for: user))", systemImage: "building.2"),
            ProfileStatItem(title: AppStrings.Profile.statSaved, value: AppStrings.Profile.notAvailableValue, systemImage: "bookmark")
        ]
    }

    private func profileOrganizationCount(for user: AppUser) -> Int {
        let organizationCount = PermissionService.manageableOrganizations(
            from: ownerOrganizationsViewModel.organizations,
            user: user
        ).count
        return organizationCount
    }


    @ViewBuilder
    private var guideManagementSection: some View {
        if canShowGuideManagement {
            ProfileSectionCard(title: AppStrings.GuideManagement.title, subtitle: AppStrings.GuideManagement.entrySubtitle) {
                NavigationLink { GuideManagementView(guideRepository: guideRepository) } label: {
                    ProfileModuleRow(
                        title: AppStrings.GuideManagement.title,
                        subtitle: AppStrings.GuideManagement.entrySubtitle,
                        systemImage: "book.closed",
                        status: .available
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var ownerPlatformManagementSection: some View {
        ProfileSectionCard(title: AppStrings.Profile.ownerPlatformManagement, subtitle: AppStrings.Profile.ownerPlatformManagementSubtitle) {
            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                NavigationLink { UserManagementView() } label: {
                    ProfileModuleRow(title: AppStrings.Profile.ownerUsers, subtitle: AppStrings.Profile.ownerUsersSubtitle, systemImage: "person.3", status: canShowAdminTools ? .active : .locked)
                }
                .buttonStyle(.plain)

                if canShowGuideManagement {
                    NavigationLink { GuideManagementView(guideRepository: guideRepository) } label: {
                        ProfileModuleRow(
                            title: AppStrings.GuideManagement.title,
                            subtitle: AppStrings.GuideManagement.entrySubtitle,
                            systemImage: "book.closed",
                            status: .available
                        )
                    }
                    .buttonStyle(.plain)
                }

                NavigationLink {
                    ModerationToolsView(
                        organizationRepository: organizationRepository,
                        notificationInboxRepository: notificationInboxRepository
                    )
                } label: {
                    ProfileModuleRow(
                        title: AppStrings.Profile.ownerOrganizationRequests,
                        subtitle: AppStrings.Profile.moderatorOrganizationsReviewSubtitle,
                        systemImage: "clock.badge.exclamationmark",
                        status: canShowModerationTools ? .available : .locked,
                        countBadge: canShowModerationTools ? ownerVisibilityViewModel.pendingOrganizationRequestCount : nil
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    FeedbackInboxView(
                        repository: feedbackRepository,
                        notificationInboxRepository: notificationInboxRepository
                    )
                } label: {
                    ProfileModuleRow(
                        title: AppStrings.Profile.ownerUserFeedback,
                        subtitle: AppStrings.Feedback.inboxSubtitle,
                        systemImage: "bubble.left.and.bubble.right",
                        status: .available,
                        countBadge: ownerVisibilityViewModel.unreadFeedbackCount
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func moderatorReviewQueuesSection(for user: AppUser) -> some View {
        ProfileSectionCard(title: AppStrings.Profile.moderatorReviewQueues, subtitle: AppStrings.Profile.moderatorReviewQueuesSubtitle) {
            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                ProfileModuleRow(
                    title: AppStrings.Profile.ownerNews,
                    subtitle: AppStrings.Profile.moderatorNewsReviewSubtitle,
                    systemImage: "newspaper",
                    status: PermissionService.canModerate(section: .news, user: user) ? .active : .locked,
                    accessory: .none
                )
                ProfileModuleRow(
                    title: AppStrings.Profile.ownerEvents,
                    subtitle: AppStrings.Profile.moderatorEventsReviewSubtitle,
                    systemImage: "calendar",
                    status: PermissionService.canModerate(section: .events, user: user) ? .active : .locked,
                    accessory: .none
                )
                ProfileModuleRow(
                    title: AppStrings.Profile.ownerOrganizations,
                    subtitle: AppStrings.Profile.moderatorOrganizationsReviewSubtitle,
                    systemImage: "building.2",
                    status: PermissionService.canModerate(section: .organizations, user: user) ? .active : .locked,
                    accessory: .none
                )
            }
        }
    }

    private var ownerPersonalSettingsSection: some View {
        ProfileSectionCard(title: AppStrings.Profile.ownerPersonalSettings, subtitle: AppStrings.Profile.ownerPersonalSettingsSubtitle) {
            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                ProfileSettingsPickerRow(title: AppStrings.Profile.appLanguage, subtitle: AppStrings.Profile.languageSettingsSubtitle, systemImage: "globe") {
                    Picker(AppStrings.Settings.language, selection: $viewModel.settings.language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    }
                    .labelsHidden()
                }

                ProfileSettingsPickerRow(title: AppStrings.Profile.appAppearance, subtitle: AppStrings.Profile.appearanceSettingsSubtitle, systemImage: "circle.lefthalf.filled") {
                    Picker(AppStrings.Settings.appearance, selection: $viewModel.settings.appearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    }
                    .labelsHidden()
                }

            }
        }
    }

    private var settingsSection: some View {
        ProfileSectionCard(
            title: AppStrings.Profile.settingsSection,
            subtitle: AppStrings.Settings.preferencesSubtitle
        ) {
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

                ProfileModuleRow(
                    title: AppStrings.Profile.regionSettings,
                    subtitle: readableFederalState ?? AppStrings.Profile.regionSettingsSubtitle,
                    systemImage: "mappin.and.ellipse",
                    status: .available,
                    accessory: .none
                )

                NavigationLink {
                    LegalDocumentView(document: .privacy)
                } label: {
                    ProfileModuleRow(title: AppStrings.Settings.privacyPolicy, subtitle: AppStrings.Profile.privacySettingsSubtitle, systemImage: "lock.doc", status: .available)
                }
                .buttonStyle(.plain)

            }
        }
    }

    private func supportSection(for user: AppUser) -> some View {
        ProfileSectionCard(
            title: AppStrings.Profile.feedbackSupport,
            subtitle: AppStrings.Profile.supportSectionSubtitle
        ) {
            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                NavigationLink {
                    MyFeedbackView(viewModel: myFeedbackViewModel, currentUserID: user.id)
                } label: {
                    ProfileModuleRow(
                        title: AppStrings.Feedback.myFeedbackTitle,
                        subtitle: AppStrings.Feedback.myFeedbackSubtitle,
                        systemImage: "tray.full",
                        status: .available
                    )
                }
                .buttonStyle(.plain)

                ProfileModuleRow(
                    title: AppStrings.Profile.sendFeedback,
                    subtitle: AppStrings.Profile.sendFeedbackSubtitle,
                    systemImage: "paperplane",
                    status: .available,
                    accessory: .none
                )

                FeedbackComposerCard(
                    selectedFeedbackType: $selectedFeedbackType,
                    feedbackMessage: $feedbackMessage,
                    statusMessage: viewModel.feedbackMessage,
                    isSubmitting: viewModel.isSubmittingFeedback
                ) {
                    submitFeedback(for: user)
                }


                NavigationLink {
                    LegalDocumentView(document: .terms)
                } label: {
                    ProfileModuleRow(title: AppStrings.Settings.terms, subtitle: AppStrings.authCurrentTermsVersion(AuthService.currentTermsVersion), systemImage: "doc.text", status: .available)
                }
                .buttonStyle(.plain)

                NavigationLink {
                    LegalDocumentView(document: .privacy)
                } label: {
                    ProfileModuleRow(title: AppStrings.Settings.privacyPolicy, subtitle: AppStrings.authCurrentPrivacyVersion(AuthService.currentPrivacyVersion), systemImage: "lock.doc", status: .available)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var guestSettingsSupportSection: some View {
        ProfileSectionCard(
            title: AppStrings.Profile.guestSettingsSupportTitle,
            subtitle: AppStrings.Profile.guestSettingsSupportSubtitle
        ) {
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

                NavigationLink {
                    LegalDocumentView(document: .terms)
                } label: {
                    ProfileModuleRow(title: AppStrings.Profile.termsOfUse, subtitle: AppStrings.authCurrentTermsVersion(AuthService.currentTermsVersion), systemImage: "doc.text", status: .available)
                }
                .buttonStyle(.plain)

                NavigationLink {
                    LegalDocumentView(document: .privacy)
                } label: {
                    ProfileModuleRow(title: AppStrings.Profile.privacyPolicy, subtitle: AppStrings.authCurrentPrivacyVersion(AuthService.currentPrivacyVersion), systemImage: "lock.doc", status: .available)
                }
                .buttonStyle(.plain)

            }
        }
    }

    private var logoutSection: some View {
        ProfileSectionCard(title: AppStrings.Settings.sessionSection) {
            Button(role: .destructive) {
                isShowingLogoutConfirmation = true
            } label: {
                ProfileModuleRow(
                    title: AppStrings.Profile.signOut,
                    subtitle: AppStrings.Settings.sessionSubtitle,
                    systemImage: "rectangle.portrait.and.arrow.right",
                    tint: AppTheme.accentDestructive,
                    status: .available,
                    accessory: .none
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.logout.button")
        }
    }

    private var accountDeletionSection: some View {
        ProfileSectionCard(title: AppStrings.Profile.deleteAccount) {
            Button(role: .destructive) {
                isShowingDeleteAccountConfirmation = true
            } label: {
                ProfileModuleRow(
                    title: AppStrings.Profile.deleteAccount,
                    subtitle: AppStrings.Profile.deleteAccountSubtitle,
                    systemImage: "trash",
                    tint: AppTheme.accentDestructive,
                    status: .available,
                    accessory: .none
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.delete_account.button")
        }
    }

    private func performAccountDeletion() async {
        guard let user = displayUser else { return }
        let message = await viewModel.deleteAccount(currentUser: user)

        if let message {
            deleteAccountErrorMessage = message
        } else {
            deleteAccountConfirmationText = ""
            isShowingDeleteAccountSheet = false
        }
    }

    private func communityRoleTitle(_ role: CommunityRole) -> String {
        switch role {
        case .communityOwner:
            return AppStrings.Profile.communityOwner
        case .communityAdmin:
            return AppStrings.Profile.communityAdmin
        case .communityModerator:
            return AppStrings.Profile.communityModerator
        case .member:
            return AppStrings.Profile.communityMember
        }
    }

    private func organizationRoleSortValue(_ role: CommunityRole) -> Int {
        switch role {
        case .communityOwner:
            return 0
        case .communityAdmin:
            return 1
        case .communityModerator:
            return 2
        case .member:
            return 3
        }
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

    private func saveProfileChanges() {
        guard canSaveProfile else { return }

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
                await myFeedbackViewModel.refresh(userID: user.id)
            }
        }
    }
}


private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}


#Preview {
    NavigationStack {
        ProfileView(
            viewModel: ProfileViewModel(
                repository: MockUserRepository(),
                feedbackRepository: MockFeedbackRepository(),
                notificationPreferencesRepository: MockNotificationPreferencesRepository(),
                notificationPermissionService: MockNotificationPermissionService(),
                localEventReminderService: MockLocalEventReminderService()
            ),
            feedbackRepository: MockFeedbackRepository(),
            eventRepository: MockEventRepository(),
            guideRepository: MockGuideRepository(),
            notificationInboxRepository: MockNotificationInboxRepository()
        )
    }
    .environmentObject(AuthState())
}
