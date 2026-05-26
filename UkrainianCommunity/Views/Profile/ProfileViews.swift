import Combine
import FirebaseFirestore
import PhotosUI
import SwiftUI

private enum ProfileDashboardMode {
    case owner

    init?(user: AppUser) {
        switch user.globalRole.effectiveRole {
        case .owner:
            self = .owner
        case .user, .topAdmin, .appModerator:
            return nil
        }
    }

    var badgeTitle: String {
        switch self {
        case .owner:
            return AppStrings.Profile.platformOwnerBadge
        }
    }

    var statusText: String {
        switch self {
        case .owner:
            return AppStrings.Profile.ownerHeroStatus
        }
    }

    var accessLevel: String {
        switch self {
        case .owner:
            return AppStrings.Profile.ownerFullAccess
        }
    }

    var badgeSymbol: String {
        switch self {
        case .owner:
            return "crown"
        }
    }
}

struct ProfileView: View {
    @ObservedObject var viewModel: ProfileViewModel
    private let feedbackRepository: FeedbackRepository
    private let newsRepository: NewsRepository
    private let eventRepository: EventRepository
    private let organizationRepository: OrganizationRepository
    @EnvironmentObject var authState: AuthState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @StateObject private var registrationsViewModel: MyRegistrationsViewModel
    @StateObject private var myFeedbackViewModel: MyFeedbackViewModel
    @StateObject private var ownerOrganizationsViewModel: OrganizationsViewModel
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
        organizationRepository: OrganizationRepository = FirestoreOrganizationRepository()
    ) {
        self.viewModel = viewModel
        self.feedbackRepository = feedbackRepository
        self.newsRepository = newsRepository
        self.eventRepository = eventRepository
        self.organizationRepository = organizationRepository
        _registrationsViewModel = StateObject(wrappedValue: MyRegistrationsViewModel(repository: eventRepository))
        _myFeedbackViewModel = StateObject(wrappedValue: MyFeedbackViewModel(repository: feedbackRepository))
        _ownerOrganizationsViewModel = StateObject(wrappedValue: OrganizationsViewModel(repository: organizationRepository))
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
        if user.globalRole.effectiveRole == .owner {
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

    private var profileDashboardMode: ProfileDashboardMode? {
        guard let user = permissionUser else { return nil }
        return ProfileDashboardMode(user: user)
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

    private var appManagementSection: some View {
        Section {
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
                }
                await ownerOrganizationsViewModel.loadIfNeeded()
                await ownerOrganizationsViewModel.refreshIfStale()
            } else {
                registrationsViewModel.resetForGuest()
                myFeedbackViewModel.reset()
            }
        }
        .refreshable {
            await viewModel.refresh()
            if authState.isAuthenticated {
                await registrationsViewModel.refresh()
                if let userID = authState.user?.id {
                    await myFeedbackViewModel.refresh(userID: userID)
                }
                await ownerOrganizationsViewModel.refresh()
            }
        }
        .onChange(of: authState.isAuthenticated) { _, isAuthenticated in
            Task {
                if isAuthenticated {
                    await registrationsViewModel.refresh()
                    if let userID = authState.user?.id {
                        await myFeedbackViewModel.refresh(userID: userID)
                    }
                    await ownerOrganizationsViewModel.refresh()
                } else {
                    registrationsViewModel.resetForGuest()
                    myFeedbackViewModel.reset()
                    ownerOrganizationsViewModel.resetForAuthChange()
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
                guard let newUserID else { return }
                await registrationsViewModel.refresh()
                await myFeedbackViewModel.refresh(userID: newUserID)
                await ownerOrganizationsViewModel.refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .registrationsChanged)) { _ in
            guard authState.isAuthenticated else { return }
            Task {
                await registrationsViewModel.refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .organizationsChanged)) { _ in
            guard authState.isAuthenticated else { return }
            Task {
                await ownerOrganizationsViewModel.refresh()
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
                    editProfileContactSection
                    editProfilePreferencesSection

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
                ProfileEditorTextArea(title: AppStrings.Profile.bio, text: $bioDraft, counterText: AppStrings.profileBioCounter(bioDraft.count, 240))
                EditorTextField(AppStrings.Common.city, text: $cityDraft, systemImage: "mappin.and.ellipse", autocapitalization: .words)
                ProfileEditorPickerRow(title: AppStrings.Auth.federalState, systemImage: "globe.europe.africa") {
                    Picker(AppStrings.Auth.federalState, selection: $selectedFederalStateDraft) {
                        ForEach(AustrianFederalState.allCases) { state in
                            Text(AppStrings.FederalStates.title(for: state)).tag(state)
                        }
                    }
                    .labelsHidden()
                }
            }
        }
    }

    private var editProfileContactSection: some View {
        ProfileSectionCard(title: AppStrings.Profile.contactsSection) {
            VStack(spacing: AppTheme.dashboardSpacing) {
                EditorTextField(
                    AppStrings.Profile.telegramUsername,
                    text: $telegramUsernameDraft,
                    systemImage: "paperplane",
                    autocapitalization: .never,
                    autocorrectionDisabled: true
                )

                ProfileReadOnlyField(
                    title: AppStrings.Auth.email,
                    value: displayUser?.email ?? "",
                    systemImage: "envelope",
                    helperText: AppStrings.Profile.emailReadOnlyHint
                )
            }
        }
    }

    private var editProfilePreferencesSection: some View {
        ProfileSectionCard(title: AppStrings.Profile.preferencesSection) {
            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                ProfileModuleRow(
                    title: AppStrings.Profile.appLanguage,
                    subtitle: AppStrings.Profile.languageSettingsSubtitle,
                    systemImage: "globe",
                    status: .soon,
                    accessory: .none
                )
                ProfileModuleRow(
                    title: AppStrings.Profile.regionSettings,
                    subtitle: AppStrings.FederalStates.title(for: selectedFederalStateDraft),
                    systemImage: "mappin.and.ellipse",
                    status: .available,
                    accessory: .none
                )
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
                ProfileModuleRow(title: AppStrings.Profile.notificationSettings, subtitle: AppStrings.Profile.quickActionNotificationsSubtitle, systemImage: "bell", status: .accountRequired, accessory: .none)
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
                ProfileModuleRow(title: AppStrings.Info.title, subtitle: AppStrings.Profile.previewGuideSubtitle, systemImage: "book.closed", status: .available, accessory: .none)
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
            communitySection(for: user)
            notificationsSection
            settingsSection
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
        ownerPlannedSection
        ownerPersonalSettingsSection
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
                ModerationToolsView()
            } label: {
                ProfileQuickActionCard(item: ProfileQuickActionItem(title: AppStrings.Profile.moderatorModerationQueue, subtitle: AppStrings.Profile.ownerPendingReviewSubtitle, systemImage: "clock.badge.exclamationmark", status: canShowModerationTools ? .active : .locked))
            }
            .buttonStyle(.plain)

            ProfileQuickActionCard(item: ProfileQuickActionItem(title: AppStrings.Profile.ownerUserReports, subtitle: AppStrings.Profile.ownerUserReportsSubtitle, systemImage: "exclamationmark.bubble", status: .soon))
            ProfileQuickActionCard(item: ProfileQuickActionItem(title: AppStrings.Profile.ownerComments, subtitle: AppStrings.Profile.ownerCommentsSubtitle, systemImage: "text.bubble", status: .soon))
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

    private func communitySection(for user: AppUser) -> some View {
        ProfileSectionCard(
            title: AppStrings.Profile.communitySection,
            subtitle: AppStrings.Profile.communitySectionSubtitle
        ) {
            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                ProfileModuleRow(title: AppStrings.Profile.volunteeringModule, subtitle: AppStrings.Profile.volunteeringSubtitle, systemImage: "hands.sparkles", status: .soon, accessory: .none)
                ProfileModuleRow(title: AppStrings.Profile.participationRequests, subtitle: AppStrings.Profile.participationRequestsSubtitle, systemImage: "person.badge.plus", status: .soon, accessory: .none)
                ProfileModuleRow(title: AppStrings.Profile.communityBadges, subtitle: AppStrings.Profile.communityBadgesSubtitle, systemImage: "seal", status: .soon, accessory: .none)
            }
        }
    }

    private var notificationsSection: some View {
        ProfileSectionCard(
            title: AppStrings.Profile.notificationSettings,
            subtitle: AppStrings.Profile.notificationsSectionSubtitle
        ) {
            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                ProfileModuleRow(title: AppStrings.Profile.notificationSettings, subtitle: AppStrings.Profile.notificationSettingsRowSubtitle, systemImage: "bell.badge", status: .soon, accessory: .none)
                ProfileModuleRow(title: AppStrings.Profile.organizationNewsNotifications, subtitle: AppStrings.Profile.organizationNewsNotificationsSubtitle, systemImage: "building.2", status: .soon, accessory: .none)
                ProfileModuleRow(title: AppStrings.Profile.eventReminders, subtitle: AppStrings.Profile.eventRemindersSubtitle, systemImage: "calendar.badge.clock", status: .soon, accessory: .none)
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

                NavigationLink { ModerationToolsView() } label: {
                    ProfileModuleRow(title: AppStrings.Profile.ownerPendingReview, subtitle: AppStrings.Profile.ownerPendingReviewSubtitle, systemImage: "clock.badge.exclamationmark", status: canShowModerationTools ? .active : .locked)
                }
                .buttonStyle(.plain)

                NavigationLink {
                    FeedbackInboxView(repository: feedbackRepository)
                } label: {
                    ProfileModuleRow(
                        title: AppStrings.Profile.ownerUserFeedback,
                        subtitle: AppStrings.Feedback.inboxSubtitle,
                        systemImage: "bubble.left.and.bubble.right",
                        status: .active
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var ownerPlannedSection: some View {
        ProfileSectionCard(title: AppStrings.Profile.futureModules, subtitle: AppStrings.Profile.futureModulesSubtitle) {
            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                ProfileModuleRow(title: AppStrings.Profile.ownerGuide, subtitle: AppStrings.Profile.ownerGuideSubtitle, systemImage: "book.closed", status: .soon, accessory: .none)
                ProfileModuleRow(title: AppStrings.Profile.ownerSendPush, subtitle: AppStrings.Profile.futureModuleSubtitle, systemImage: "bell.badge", status: .soon, accessory: .none)
                ProfileModuleRow(title: AppStrings.Profile.ownerProblemReports, subtitle: AppStrings.Profile.futureModuleSubtitle, systemImage: "exclamationmark.bubble", status: .soon, accessory: .none)
                ProfileModuleRow(title: AppStrings.Profile.ownerAuditLogs, subtitle: AppStrings.Profile.ownerAuditLogsSubtitle, systemImage: "list.bullet.clipboard", status: .soon, accessory: .none)
            }
        }
    }

    private var adminContentControlSection: some View {
        ProfileSectionCard(title: AppStrings.Profile.ownerContentControl, subtitle: AppStrings.Profile.adminContentControlSubtitle) {
            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                ProfileModuleRow(title: AppStrings.Profile.ownerHomeBanners, subtitle: AppStrings.Profile.ownerHomeBannersSubtitle, systemImage: "photo.on.rectangle", status: PermissionService.canManageHomeBanner(user: permissionUser) ? .active : .soon)
                ProfileModuleRow(title: AppStrings.Profile.ownerFeaturedNews, subtitle: AppStrings.Profile.futureModuleSubtitle, systemImage: "newspaper", status: .soon, accessory: .none)
                ProfileModuleRow(title: AppStrings.Profile.ownerFeaturedEvents, subtitle: AppStrings.Profile.futureModuleSubtitle, systemImage: "calendar", status: .soon, accessory: .none)
                ProfileModuleRow(title: AppStrings.Profile.ownerFeaturedOrganizations, subtitle: AppStrings.Profile.futureModuleSubtitle, systemImage: "building.2", status: .soon, accessory: .none)
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
                Button(action: beginEditingProfile) {
                    ProfileTextModuleRow(
                        title: AppStrings.Profile.myProfile,
                        subtitle: AppStrings.Profile.editProfileSubtitle
                    )
                }
                .buttonStyle(.plain)

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

                ProfileModuleRow(title: AppStrings.Profile.notificationSettings, subtitle: AppStrings.Profile.notificationSettingsSubtitle, systemImage: "bell.badge", status: .soon, accessory: .none)
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

                ProfileModuleRow(title: AppStrings.Profile.accountSecurity, subtitle: AppStrings.Profile.accountSecuritySubtitle, systemImage: "lock.shield", status: .soon, accessory: .none)
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

                ProfileModuleRow(
                    title: AppStrings.Profile.reportProblem,
                    subtitle: AppStrings.Profile.reportProblemSubtitle,
                    systemImage: "exclamationmark.bubble",
                    status: .soon,
                    accessory: .none
                )

                ProfileModuleRow(
                    title: AppStrings.Profile.helpFAQ,
                    subtitle: AppStrings.Profile.helpCenterSubtitle,
                    systemImage: "questionmark.circle",
                    status: .soon,
                    accessory: .none
                )

                ProfileModuleRow(
                    title: AppStrings.Profile.aboutApp,
                    subtitle: AppStrings.Profile.aboutAppSubtitle,
                    systemImage: "info.circle",
                    status: .soon,
                    accessory: .none
                )

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

    private var publicSupportSection: some View {
        ProfileSectionCard(
            title: AppStrings.Profile.feedbackSupport,
            subtitle: AppStrings.Profile.supportSectionSubtitle
        ) {
            legalRows
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

                ProfileModuleRow(title: AppStrings.Profile.helpCenter, subtitle: AppStrings.Profile.helpCenterSubtitle, systemImage: "questionmark.circle", status: .soon, accessory: .none)
            }
        }
    }

    private var legalRows: some View {
        VStack(spacing: AppTheme.eventsMetadataSpacing) {
            NavigationLink {
                LegalDocumentView(document: .privacy)
            } label: {
                ProfileModuleRow(title: AppStrings.Settings.privacyPolicy, subtitle: AppStrings.authCurrentPrivacyVersion(AuthService.currentPrivacyVersion), systemImage: "lock.doc", status: .available)
            }
            .buttonStyle(.plain)

            NavigationLink {
                LegalDocumentView(document: .terms)
            } label: {
                ProfileModuleRow(title: AppStrings.Settings.terms, subtitle: AppStrings.authCurrentTermsVersion(AuthService.currentTermsVersion), systemImage: "doc.text", status: .available)
            }
            .buttonStyle(.plain)

            ProfileModuleRow(title: AppStrings.Profile.helpCenter, subtitle: AppStrings.Profile.helpCenterSubtitle, systemImage: "questionmark.circle", status: .soon)
            ProfileModuleRow(title: AppStrings.Profile.aboutApp, subtitle: AppStrings.Profile.aboutAppSubtitle, systemImage: "info.circle", status: .soon)
        }
    }

    private var futureModulesSection: some View {
        ProfileSectionCard(
            title: AppStrings.Profile.futureModules,
            subtitle: AppStrings.Profile.userFutureModulesSubtitle
        ) {
            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                ProfileModuleRow(title: AppStrings.Profile.volunteeringModule, subtitle: AppStrings.Profile.futureModuleSubtitle, systemImage: "heart", status: .soon, accessory: .none)
                ProfileModuleRow(title: AppStrings.Profile.communityAchievementsModule, subtitle: AppStrings.Profile.futureModuleSubtitle, systemImage: "seal", status: .soon, accessory: .none)
                ProfileModuleRow(title: AppStrings.Profile.activityHistoryModule, subtitle: AppStrings.Profile.futureModuleSubtitle, systemImage: "clock.arrow.circlepath", status: .soon, accessory: .none)
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
                                    if user.globalRole.effectiveRole != .user {
                                        ProfileBadge(title: user.globalRole.title, systemImage: "person.badge.key")
                                    }

                                    if let readableFederalState {
                                        ProfileBadge(title: readableFederalState, systemImage: "globe.europe.africa")
                                    }
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    if user.globalRole.effectiveRole != .user {
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

private struct GuestPlatformHeroCard: View {
    let onSignIn: () -> Void
    let onCreateAccount: () -> Void

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppStrings.Profile.guestWelcomeTitle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(AppStrings.Profile.guestWelcomeSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: AppTheme.eventsMetadataSpacing) {
                    Button(AppStrings.Auth.signIn, action: onSignIn)
                        .frame(maxWidth: .infinity)
                        .appActionButtonStyle(.primary)
                        .accessibilityIdentifier("profile.guest.signIn")

                    Button(action: onCreateAccount) {
                        Text(AppStrings.Auth.createAccount)
                            .frame(maxWidth: .infinity)
                    }
                    .appActionButtonStyle(.secondary)
                    .accessibilityIdentifier("profile.guest.createAccount")
                }
            }
        }
        .accessibilityIdentifier("profile.guest.card")
    }
}

private struct OwnerHeroCard: View {
    let user: AppUser
    let readableFederalState: String?
    let mode: ProfileDashboardMode

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                HStack(alignment: .top, spacing: 14) {
                    ProfileAvatarView(user: user)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(user.preferredDisplayName)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(mode.statusText)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                ProfileBadge(title: mode.badgeTitle, systemImage: mode.badgeSymbol)
                                ProfileBadge(title: user.accountStatus.title, systemImage: "checkmark.seal")
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                ProfileBadge(title: mode.badgeTitle, systemImage: mode.badgeSymbol)
                                ProfileBadge(title: user.accountStatus.title, systemImage: "checkmark.seal")
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                    if let city = user.city.nilIfEmpty {
                        ProfileMetadataRow(title: AppStrings.Common.city, value: city, systemImage: "mappin.and.ellipse")
                    }

                    if let readableFederalState {
                        ProfileMetadataRow(title: AppStrings.Profile.region, value: readableFederalState, systemImage: "globe.europe.africa")
                    }

                    ProfileMetadataRow(title: AppStrings.Profile.systemAccessLevel, value: mode.accessLevel, systemImage: "lock.shield")
                }
            }
        }
    }
}

private struct ProfileHeroCard: View {
    let user: AppUser
    let readableFederalState: String?
    let onEditProfile: () -> Void

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                HStack(alignment: .top, spacing: 14) {
                    ProfileAvatarView(user: user)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(user.preferredDisplayName)
                            .font(.title3.weight(.semibold))
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
                                ProfileBadge(title: GlobalRole.user.title, systemImage: "person")

                                if user.globalRole.effectiveRole != .user {
                                    ProfileBadge(title: user.globalRole.title, systemImage: "person.badge.key")
                                }

                                if user.accountStatus != .active {
                                    ProfileBadge(title: user.accountStatus.title, systemImage: "checkmark.seal")
                                }
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                ProfileBadge(title: GlobalRole.user.title, systemImage: "person")

                                if user.globalRole.effectiveRole != .user {
                                    ProfileBadge(title: user.globalRole.title, systemImage: "person.badge.key")
                                }

                                if user.accountStatus != .active {
                                    ProfileBadge(title: user.accountStatus.title, systemImage: "checkmark.seal")
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
                } else {
                    Text(AppStrings.Profile.emptyBioStatus)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                    if let city = user.city.nilIfEmpty {
                        ProfileMetadataRow(title: AppStrings.Common.city, value: city, systemImage: "mappin.and.ellipse")
                    }

                    if let readableFederalState {
                        ProfileMetadataRow(title: AppStrings.Profile.region, value: readableFederalState, systemImage: "globe.europe.africa")
                    }

                    ProfileMetadataRow(
                        title: AppStrings.Profile.memberSince,
                        value: LocalizationStore.dateString(from: user.joinedAt, dateStyle: .medium, timeStyle: .none),
                        systemImage: "calendar"
                    )
                }
            }
        }
    }
}

private struct ManagedNewsContentView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel: NewsViewModel
    @State private var editingPost: NewsPost?
    private let repository: NewsRepository
    private let organizationRepository: OrganizationRepository
    private let manageableOrganizations: [Organization]

    init(
        repository: NewsRepository,
        organizationRepository: OrganizationRepository,
        manageableOrganizations: [Organization]
    ) {
        self.repository = repository
        self.organizationRepository = organizationRepository
        self.manageableOrganizations = manageableOrganizations
        _viewModel = StateObject(wrappedValue: NewsViewModel(repository: repository))
    }

    private var organizationsByID: [String: Organization] {
        Dictionary(uniqueKeysWithValues: manageableOrganizations.map { ($0.id, $0) })
    }

    private var managedPosts: [NewsPost] {
        viewModel.posts
            .filter { post in
                guard let organizationID = post.source.organizationId,
                      let organization = organizationsByID[organizationID] else {
                    return false
                }
                return PermissionService.canEditOrganizationNews(organization, user: authState.user)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        ZStack {
            AppBackgroundView()
                .allowsHitTesting(false)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    SectionHeaderBlock(
                        title: AppStrings.Profile.managedNewsTitle,
                        subtitle: AppStrings.Profile.managedNewsSubtitle
                    )

                    if viewModel.isLoading && managedPosts.isEmpty {
                        LoadingStateCard(title: nil)
                    } else if managedPosts.isEmpty {
                        EmptyStateCard(
                            systemImage: "newspaper",
                            title: AppStrings.Profile.managedNewsEmptyTitle,
                            message: AppStrings.Profile.managedNewsEmptyMessage
                        )
                    } else {
                        VStack(spacing: AppTheme.eventsMetadataSpacing) {
                            ForEach(managedPosts) { post in
                                ManagedContentCard(
                                    title: post.title,
                                    subtitle: organizationTitle(for: post.source.organizationId),
                                    metadata: managedNewsMetadata(for: post),
                                    status: post.moderationStatus.title,
                                    systemImage: "newspaper"
                                ) {
                                    NavigationLink {
                                        NewsDetailView(
                                            viewModel: viewModel,
                                            postID: post.id,
                                            onNewsDeleted: {
                                                viewModel.reload()
                                            },
                                            organizationRepository: organizationRepository
                                        )
                                        .environment(\.newsPresentationMode, .management)
                                    } label: {
                                        Label(AppStrings.Action.open, systemImage: "arrow.up.right")
                                    }

                                    Button {
                                        editingPost = post
                                    } label: {
                                        Label(AppStrings.Action.edit, systemImage: "pencil")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, AppTheme.pageHorizontal)
                .padding(.vertical, AppTheme.sectionSpacing)
            }
        }
        .navigationTitle(AppStrings.Profile.managedNewsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .sheet(item: $editingPost) { post in
            NavigationStack {
                NewsEditorView(repository: repository, news: post) {
                    await viewModel.refresh()
                }
            }
            .environmentObject(authState)
        }
    }

    private func organizationTitle(for organizationID: String?) -> String {
        guard let organizationID else { return AppStrings.News.missingOrganization }
        return organizationsByID[organizationID]?.name ?? AppStrings.News.missingOrganization
    }

    private func managedNewsMetadata(for post: NewsPost) -> String {
        LocalizationStore.dateString(from: post.createdAt, dateStyle: .medium, timeStyle: .none)
    }
}

private struct ManagedEventsContentView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel: EventsViewModel
    @State private var editingEvent: Event?
    private let repository: EventRepository
    private let organizationRepository: OrganizationRepository
    private let manageableOrganizations: [Organization]

    init(
        repository: EventRepository,
        organizationRepository: OrganizationRepository,
        manageableOrganizations: [Organization]
    ) {
        self.repository = repository
        self.organizationRepository = organizationRepository
        self.manageableOrganizations = manageableOrganizations
        _viewModel = StateObject(wrappedValue: EventsViewModel(repository: repository))
    }

    private var organizationsByID: [String: Organization] {
        Dictionary(uniqueKeysWithValues: manageableOrganizations.map { ($0.id, $0) })
    }

    private var managedEvents: [Event] {
        viewModel.events
            .filter { event in
                guard let organizationID = event.source.organizationId,
                      let organization = organizationsByID[organizationID] else {
                    return false
                }
                return PermissionService.canEditOrganizationEvent(organization, user: authState.user)
            }
            .sorted { $0.startDate > $1.startDate }
    }

    var body: some View {
        ZStack {
            AppBackgroundView()
                .allowsHitTesting(false)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    SectionHeaderBlock(
                        title: AppStrings.Profile.managedEventsTitle,
                        subtitle: AppStrings.Profile.managedEventsSubtitle
                    )

                    if viewModel.isLoading && managedEvents.isEmpty {
                        LoadingStateCard(title: nil)
                    } else if managedEvents.isEmpty {
                        EmptyStateCard(
                            systemImage: "calendar",
                            title: AppStrings.Profile.managedEventsEmptyTitle,
                            message: AppStrings.Profile.managedEventsEmptyMessage
                        )
                    } else {
                        VStack(spacing: AppTheme.eventsMetadataSpacing) {
                            ForEach(managedEvents) { event in
                                ManagedContentCard(
                                    title: event.title,
                                    subtitle: organizationTitle(for: event.source.organizationId),
                                    metadata: managedEventMetadata(for: event),
                                    status: event.moderationStatus.title,
                                    systemImage: "calendar"
                                ) {
                                    NavigationLink {
                                        EventDetailView(
                                            viewModel: viewModel,
                                            eventID: event.id,
                                            onEventDeleted: {
                                                viewModel.reload()
                                            },
                                            organizationRepository: organizationRepository
                                        )
                                        .environment(\.eventPresentationMode, .management)
                                    } label: {
                                        Label(AppStrings.Action.open, systemImage: "arrow.up.right")
                                    }

                                    Button {
                                        editingEvent = event
                                    } label: {
                                        Label(AppStrings.Action.edit, systemImage: "pencil")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, AppTheme.pageHorizontal)
                .padding(.vertical, AppTheme.sectionSpacing)
            }
        }
        .navigationTitle(AppStrings.Profile.managedEventsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .sheet(item: $editingEvent) { event in
            NavigationStack {
                EventEditorView(repository: repository, event: event) {
                    await viewModel.refresh()
                }
            }
            .environmentObject(authState)
        }
    }

    private func organizationTitle(for organizationID: String?) -> String {
        guard let organizationID else { return AppStrings.News.missingOrganization }
        return organizationsByID[organizationID]?.name ?? AppStrings.News.missingOrganization
    }

    private func managedEventMetadata(for event: Event) -> String {
        LocalizationStore.dateString(from: event.startDate, dateStyle: .medium, timeStyle: .short)
    }
}

private struct ManagedContentCard<Actions: View>: View {
    let title: String
    let subtitle: String
    let metadata: String
    let status: String
    let systemImage: String
    @ViewBuilder let actions: Actions

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                HStack(alignment: .top, spacing: AppTheme.eventsMetadataSpacing) {
                    Image(systemName: systemImage)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimary)
                        .frame(width: 34, height: 34)
                        .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(2)

                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)

                        Text(metadata)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    Spacer(minLength: AppTheme.eventsMetadataSpacing)

                    Text(status)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(AppTheme.accentPrimarySoft, in: Capsule())
                        .lineLimit(1)
                }

                HStack(spacing: AppTheme.eventsMetadataSpacing) {
                    actions
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(AppTheme.accentPrimary)
            }
        }
    }
}

private struct ProfileSectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                SectionHeaderBlock(title: title, subtitle: subtitle)
                content
            }
        }
    }
}

private struct ProfileStatItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let systemImage: String
}

private struct ProfileQuickStatsGrid: View {
    let stats: [ProfileStatItem]

    private let columns = [
        GridItem(.flexible(), spacing: AppTheme.eventsMetadataSpacing),
        GridItem(.flexible(), spacing: AppTheme.eventsMetadataSpacing)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: AppTheme.eventsMetadataSpacing) {
            ForEach(stats) { stat in
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: stat.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimary)

                    Text(stat.value)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .monospacedDigit()

                    Text(stat.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(AppTheme.eventsMetadataSpacing)
                .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
                .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                        .strokeBorder(AppTheme.borderSubtle)
                )
            }
        }
    }
}

private struct ProfileQuickActionItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let systemImage: String
    let status: ProfileModuleStatus
}

private struct ProfileQuickActionGrid: View {
    let items: [ProfileQuickActionItem]

    private let columns = [
        GridItem(.flexible(), spacing: AppTheme.eventsMetadataSpacing),
        GridItem(.flexible(), spacing: AppTheme.eventsMetadataSpacing)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: AppTheme.eventsMetadataSpacing) {
            ForEach(items) { item in
                ProfileQuickActionCard(item: item)
            }
        }
    }
}

private struct ProfileQuickActionCard: View {
    let item: ProfileQuickActionItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: item.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(item.status.tint)
                    .frame(width: 28, height: 28)
                    .background(item.status.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Spacer(minLength: 0)

                if let statusTitle = item.status.title {
                    Text(statusTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(item.status.tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(item.status.tint.opacity(0.10), in: Capsule())
                        .lineLimit(1)
                        .frame(minWidth: 70)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 70, alignment: .trailing)
                }
            }

            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(2)
                .truncationMode(.tail)

            Text(item.subtitle)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AppTheme.eventsMetadataSpacing)
        .frame(maxWidth: .infinity, minHeight: 116, maxHeight: 116, alignment: .topLeading)
        .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle)
        )
        .opacity(item.status.isDisabled ? 0.72 : 1)
        .accessibilityElement(children: .combine)
    }
}

private struct ProfilePreviewGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)

            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProfileEventPreviewCard: View {
    let event: Event

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: event.category.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: 30, height: 30)
                .background(AppTheme.accentPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(registrationEventScheduleText(for: event))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)

                Label(event.city, systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(AppTheme.eventsMetadataSpacing)
        .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct ProfileOrganizationPreviewCard: View {
    let title: String
    let role: String
    let status: ProfileModuleStatus

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "building.2")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(status.tint)
                .frame(width: 30, height: 30)
                .background(status.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                Text(role)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let statusTitle = status.title {
                Text(statusTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(status.tint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(status.tint.opacity(0.10), in: Capsule())
                    .lineLimit(1)
            }
        }
        .padding(AppTheme.eventsMetadataSpacing)
        .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle)
        )
    }
}

private struct OrganizationRoleDashboardCard: View {
    let membership: CommunityMembership
    let roleTitle: String
    let user: AppUser

    private var organizationTitle: String {
        AppStrings.profileOrganizationID(membership.organizationId)
    }

    private var organizationSubtitle: String {
        AppStrings.profileOrganizationScopedSubtitle(membership.organizationId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "building.2")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimary)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.accentPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(organizationTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)

                    Text(organizationSubtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)

                Text(roleTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .frame(minWidth: 92)
                    .background(AppTheme.accentPrimary.opacity(0.10), in: Capsule())
                    .lineLimit(1)
            }

            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                switch membership.role {
                case .communityOwner:
                    ownerActions
                case .communityAdmin:
                    adminActions
                case .communityModerator:
                    moderatorActions
                case .member:
                    EmptyView()
                }
            }
        }
        .padding(AppTheme.eventsMetadataSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle)
        )
        .accessibilityElement(children: .contain)
    }

    private var ownerActions: some View {
        Group {
            NavigationLink {
                OrganizationManagementHubView(focusedOrganizationID: membership.organizationId)
            } label: {
                ProfileModuleRow(title: AppStrings.Profile.organizationEditOrganization, subtitle: organizationSubtitle, systemImage: "pencil", status: .active)
            }
            .buttonStyle(.plain)

            ProfileModuleRow(title: AppStrings.Profile.organizationCreateEvent, subtitle: AppStrings.Profile.organizationScopedFutureSubtitle, systemImage: "calendar.badge.plus", status: .soon, accessory: .none)
            ProfileModuleRow(title: AppStrings.Profile.organizationCreateNews, subtitle: AppStrings.Profile.organizationScopedFutureSubtitle, systemImage: "newspaper", status: .soon, accessory: .none)
            ProfileModuleRow(title: AppStrings.Profile.organizationTeamRoles, subtitle: AppStrings.Profile.organizationTeamRolesSubtitle, systemImage: "person.2.badge.gearshape", status: .soon, accessory: .none)
            organizationModerationLink(title: AppStrings.Profile.organizationModeration)
            ProfileModuleRow(title: AppStrings.Profile.organizationRequestsMessages, subtitle: AppStrings.Profile.organizationRequestsMessagesSubtitle, systemImage: "tray", status: .soon, accessory: .none)
            ProfileModuleRow(title: AppStrings.Profile.organizationAnalytics, subtitle: AppStrings.Profile.futureModuleSubtitle, systemImage: "chart.bar", status: .soon, accessory: .none)
            ProfileModuleRow(title: AppStrings.Profile.organizationSettings, subtitle: AppStrings.Profile.organizationSettingsSubtitle, systemImage: "gearshape", status: .soon, accessory: .none)
        }
    }

    private var adminActions: some View {
        Group {
            ProfileModuleRow(title: AppStrings.Profile.organizationCreateEvent, subtitle: AppStrings.Profile.organizationScopedFutureSubtitle, systemImage: "calendar.badge.plus", status: .soon, accessory: .none)
            ProfileModuleRow(title: AppStrings.Profile.organizationCreateNews, subtitle: AppStrings.Profile.organizationScopedFutureSubtitle, systemImage: "newspaper", status: .soon, accessory: .none)

            NavigationLink {
                OrganizationManagementHubView(focusedOrganizationID: membership.organizationId)
            } label: {
                ProfileModuleRow(title: AppStrings.Profile.organizationEditInfo, subtitle: organizationSubtitle, systemImage: "pencil", status: .active)
            }
            .buttonStyle(.plain)

            organizationModerationLink(title: AppStrings.Profile.organizationModeration)
            ProfileModuleRow(title: AppStrings.Profile.organizationRequestsMessages, subtitle: AppStrings.Profile.organizationRequestsMessagesSubtitle, systemImage: "tray", status: .soon, accessory: .none)
        }
    }

    private var moderatorActions: some View {
        Group {
            organizationModerationLink(title: AppStrings.Profile.moderatorModerationQueue)
        }
    }

    private func organizationModerationLink(title: String) -> some View {
        NavigationLink {
            ModerationToolsView(organizationID: membership.organizationId)
        } label: {
            ProfileModuleRow(
                title: title,
                subtitle: AppStrings.Profile.organizationModerationScopedSubtitle,
                systemImage: "clock.badge.exclamationmark",
                status: .active
            )
        }
        .buttonStyle(.plain)
    }
}

private enum SavedContentSegment: String, CaseIterable, Identifiable {
    case all
    case news
    case events
    case organizations

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return AppStrings.Home.filterAll
        case .news:
            return AppStrings.News.title
        case .events:
            return AppStrings.Events.title
        case .organizations:
            return AppStrings.Tabs.organizations
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "square.grid.2x2"
        case .news:
            return "newspaper"
        case .events:
            return "calendar"
        case .organizations:
            return "building.2"
        }
    }
}

private enum SavedContentItem: Identifiable {
    case news(NewsPost)
    case event(Event)
    case organization(Organization)

    var id: String {
        switch self {
        case let .news(post):
            return "news-\(post.id)"
        case let .event(event):
            return "event-\(event.id)"
        case let .organization(organization):
            return "organization-\(organization.id)"
        }
    }

    var savedSortDate: Date {
        switch self {
        case let .news(post):
            return post.publishedAt
        case let .event(event):
            return event.startDate
        case let .organization(organization):
            return organization.updatedAt
        }
    }
}

private enum RecentViewsSegment: String, CaseIterable, Identifiable {
    case all
    case news
    case events
    case organizations

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return AppStrings.Home.filterAll
        case .news:
            return AppStrings.News.title
        case .events:
            return AppStrings.Events.title
        case .organizations:
            return AppStrings.Tabs.organizations
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "square.grid.2x2"
        case .news:
            return RecentViewItemType.news.systemImage
        case .events:
            return RecentViewItemType.event.systemImage
        case .organizations:
            return RecentViewItemType.organization.systemImage
        }
    }

    func matches(_ item: RecentViewItem) -> Bool {
        switch self {
        case .all:
            return item.itemType != .guide
        case .news:
            return item.itemType == .news
        case .events:
            return item.itemType == .event
        case .organizations:
            return item.itemType == .organization
        }
    }
}

private enum ActivityHistorySegment: String, CaseIterable, Identifiable {
    case all
    case events
    case organizations
    case saved

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return AppStrings.Home.filterAll
        case .events:
            return AppStrings.Events.title
        case .organizations:
            return AppStrings.Tabs.organizations
        case .saved:
            return AppStrings.Profile.activityHistorySavedFilter
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "square.grid.2x2"
        case .events:
            return ActivityLogTargetType.event.systemImage
        case .organizations:
            return ActivityLogTargetType.organization.systemImage
        case .saved:
            return "bookmark"
        }
    }

    func matches(_ item: ActivityLogItem) -> Bool {
        switch self {
        case .all:
            return true
        case .events:
            return item.targetType == .event
        case .organizations:
            return item.targetType == .organization
        case .saved:
            return item.actionType.isSavedAction
        }
    }
}

private struct ProfileDestinationLayout<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let introSubtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            AppBackgroundView()
                .allowsHitTesting(false)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    AppCenteredBrandHeader {
                        AppGlassIconButton(systemImage: "chevron.left", accessibilityLabel: AppStrings.Common.back) {
                            dismiss()
                        }
                    } trailingContent: {
                        AppNotificationBellButton()
                    }

                    AppGroupedContentPlane {
                        VStack(alignment: .leading, spacing: AppTheme.eventsControlGroupSpacing) {
                            ProfileDestinationIntroCard(
                                title: title,
                                subtitle: introSubtitle
                            )

                            content
                        }
                    }
                }
                .padding(.horizontal, AppTheme.pageHorizontal)
                .padding(.top, AppTheme.sectionSpacing)
                .padding(.bottom, AppTheme.homeBottomContentPadding)
            }
        }
        .tint(AppTheme.accentPrimary)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct ProfileDestinationIntroCard: View {
    let title: String
    let subtitle: String

    var body: some View {
        AppEditorSectionCard {
            SectionHeaderBlock(
                title: title,
                subtitle: subtitle
            )
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        }
    }
}

private struct ProfileDestinationEmptyStateCard: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .center, spacing: 8) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimary)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.accentPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(message)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 128)
            .padding(.vertical, 4)
        }
    }
}

private struct ActivityHistoryView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var activityLogViewModel: ActivityLogViewModel
    @StateObject private var newsViewModel: NewsViewModel
    @StateObject private var eventsViewModel: EventsViewModel
    @StateObject private var organizationsViewModel: OrganizationsViewModel
    @State private var selectedSegment: ActivityHistorySegment = .all

    init(
        activityLogRepository: ActivityLogRepository = FirestoreActivityLogRepository(),
        newsRepository: NewsRepository = FirestoreNewsRepository(),
        eventRepository: EventRepository = FirestoreEventRepository(),
        organizationRepository: OrganizationRepository = FirestoreOrganizationRepository()
    ) {
        _activityLogViewModel = StateObject(wrappedValue: ActivityLogViewModel(repository: activityLogRepository))
        _newsViewModel = StateObject(wrappedValue: NewsViewModel(repository: newsRepository))
        _eventsViewModel = StateObject(wrappedValue: EventsViewModel(repository: eventRepository))
        _organizationsViewModel = StateObject(wrappedValue: OrganizationsViewModel(repository: organizationRepository))
    }

    private var filteredItems: [ActivityLogItem] {
        activityLogViewModel.items
            .filter { selectedSegment.matches($0) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var isLoading: Bool {
        activityLogViewModel.isLoading && activityLogViewModel.items.isEmpty
    }

    var body: some View {
        ProfileDestinationLayout(
            title: AppStrings.Profile.activityHistoryModule,
            introSubtitle: AppStrings.Profile.activityHistoryIntro
        ) {
            AppHorizontalFilterRow {
                ForEach(ActivityHistorySegment.allCases) { segment in
                    Button {
                        selectedSegment = segment
                    } label: {
                        AppFilterChip(
                            title: segment.title,
                            systemImage: segment.systemImage,
                            isSelected: selectedSegment == segment
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            activityHistoryContent
        }
        .task(id: authState.user?.id) {
            resetActivityHistoryState()
            guard authState.isAuthenticated else { return }
            await loadActivityHistoryIfNeeded()
        }
        .refreshable {
            await refreshActivityHistory()
        }
    }

    @ViewBuilder
    private var activityHistoryContent: some View {
        if isLoading {
            LoadingStateCard(title: AppStrings.Profile.activityHistoryModule)
        } else if let error = activityLogViewModel.error, activityLogViewModel.items.isEmpty {
            ProfileDestinationEmptyStateCard(
                systemImage: "exclamationmark.triangle",
                title: AppStrings.Profile.activityHistoryModule,
                message: activityHistoryErrorMessage(error)
            )
        } else if filteredItems.isEmpty {
            ProfileDestinationEmptyStateCard(
                systemImage: "list.bullet.rectangle",
                title: AppStrings.Profile.activityHistoryEmptyTitle,
                message: AppStrings.Profile.activityHistoryEmptyMessage
            )
        } else {
            VStack(spacing: AppTheme.feedRowSpacing) {
                ForEach(filteredItems) { item in
                    activityItemLink(item)
                }
            }
        }
    }

    private func loadActivityHistoryIfNeeded() async {
        async let activityLoad: Void = activityLogViewModel.loadIfNeeded()
        async let newsLoad: Void = newsViewModel.loadIfNeeded()
        async let eventsLoad: Void = eventsViewModel.loadIfNeeded()
        async let organizationsLoad: Void = organizationsViewModel.loadIfNeeded()
        _ = await (activityLoad, newsLoad, eventsLoad, organizationsLoad)
    }

    private func refreshActivityHistory() async {
        async let activityRefresh: Void = activityLogViewModel.refresh()
        async let newsRefresh: Void = newsViewModel.refresh()
        async let eventsRefresh: Void = eventsViewModel.refresh()
        async let organizationsRefresh: Void = organizationsViewModel.refresh()
        _ = await (activityRefresh, newsRefresh, eventsRefresh, organizationsRefresh)
    }

    private func resetActivityHistoryState() {
        activityLogViewModel.resetForAuthChange()
        newsViewModel.resetForAuthChange()
        eventsViewModel.resetForAuthChange()
        organizationsViewModel.resetForAuthChange()
    }

    private func activityHistoryErrorMessage(_ error: AppError) -> String {
        switch error {
        case .permissionDenied:
            return AppStrings.Auth.requiredTitle
        case .network:
            return AppStrings.News.loadNetworkError
        case .validationFailed, .notFound:
            return AppStrings.News.loadValidationError
        case .unknown:
            return AppStrings.News.loadUnknownError
        }
    }

    @ViewBuilder
    private func activityItemLink(_ item: ActivityLogItem) -> some View {
        switch item.targetType {
        case .news:
            if newsViewModel.post(for: item.targetId) != nil {
                NavigationLink {
                    NewsDetailView(
                        viewModel: newsViewModel,
                        postID: item.targetId,
                        onNewsDeleted: { newsViewModel.reload() }
                    )
                } label: {
                    ActivityHistoryRow(item: item, canOpenTarget: true)
                }
                .buttonStyle(.plain)
            } else {
                ActivityHistoryRow(item: item, canOpenTarget: false)
            }
        case .event:
            if eventsViewModel.event(for: item.targetId) != nil {
                NavigationLink {
                    EventDetailView(
                        viewModel: eventsViewModel,
                        eventID: item.targetId,
                        onEventDeleted: { @MainActor @Sendable in
                            eventsViewModel.reload()
                        }
                    )
                } label: {
                    ActivityHistoryRow(item: item, canOpenTarget: true)
                }
                .buttonStyle(.plain)
            } else {
                ActivityHistoryRow(item: item, canOpenTarget: false)
            }
        case .organization:
            if organizationsViewModel.organization(for: item.targetId) != nil {
                NavigationLink {
                    OrganizationDetailView(viewModel: organizationsViewModel, organizationID: item.targetId)
                } label: {
                    ActivityHistoryRow(item: item, canOpenTarget: true)
                }
                .buttonStyle(.plain)
            } else {
                ActivityHistoryRow(item: item, canOpenTarget: false)
            }
        }
    }
}

private struct ActivityHistoryRow: View {
    let item: ActivityLogItem
    let canOpenTarget: Bool

    private var subtitle: String {
        let trimmedSubtitle = item.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedSubtitle.isEmpty ? item.targetType.title : trimmedSubtitle
    }

    private var createdAtText: String {
        LocalizationStore.dateString(from: item.createdAt, dateStyle: .medium, timeStyle: .short)
    }

    var body: some View {
        AppEditorSectionCard {
            HStack(alignment: .center, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    AppFeedThumbnail(
                        imageURL: item.imageURL,
                        fallbackSystemImage: item.targetType.systemImage,
                        tint: AppTheme.accentPrimary,
                        fill: AppTheme.accentPrimary.opacity(0.10),
                        size: 58,
                        cornerRadius: 12,
                        source: "ActivityHistoryRow"
                    )

                    Image(systemName: item.actionType.systemImage)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(item.actionType.tint)
                        .frame(width: 22, height: 22)
                        .background(AppTheme.surfacePrimary, in: Circle())
                        .overlay(Circle().strokeBorder(AppTheme.borderSubtle))
                        .offset(x: 4, y: 4)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.actionType.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(item.actionType.tint)
                        .lineLimit(1)

                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)

                    Label(createdAtText, systemImage: "clock")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if canOpenTarget {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
        .opacity(canOpenTarget ? 1 : 0.72)
        .accessibilityElement(children: .combine)
    }
}

private struct RecentViewsView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var recentViewsViewModel: RecentViewsViewModel
    @StateObject private var newsViewModel: NewsViewModel
    @StateObject private var eventsViewModel: EventsViewModel
    @StateObject private var organizationsViewModel: OrganizationsViewModel
    @State private var selectedSegment: RecentViewsSegment = .all

    init(
        recentViewsRepository: RecentViewsRepository = FirestoreRecentViewsRepository(),
        newsRepository: NewsRepository = FirestoreNewsRepository(),
        eventRepository: EventRepository = FirestoreEventRepository(),
        organizationRepository: OrganizationRepository = FirestoreOrganizationRepository()
    ) {
        _recentViewsViewModel = StateObject(wrappedValue: RecentViewsViewModel(repository: recentViewsRepository))
        _newsViewModel = StateObject(wrappedValue: NewsViewModel(repository: newsRepository))
        _eventsViewModel = StateObject(wrappedValue: EventsViewModel(repository: eventRepository))
        _organizationsViewModel = StateObject(wrappedValue: OrganizationsViewModel(repository: organizationRepository))
    }

    private var filteredItems: [RecentViewItem] {
        recentViewsViewModel.items
            .filter { selectedSegment.matches($0) }
            .sorted { $0.viewedAt > $1.viewedAt }
    }

    private var isLoading: Bool {
        recentViewsViewModel.isLoading && recentViewsViewModel.items.isEmpty
    }

    var body: some View {
        ProfileDestinationLayout(
            title: AppStrings.Profile.recentlyViewed,
            introSubtitle: AppStrings.Profile.recentlyViewedIntro
        ) {
            AppHorizontalFilterRow {
                ForEach(RecentViewsSegment.allCases) { segment in
                    Button {
                        selectedSegment = segment
                    } label: {
                        AppFilterChip(
                            title: segment.title,
                            systemImage: segment.systemImage,
                            isSelected: selectedSegment == segment
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            recentViewsContent
        }
        .task(id: authState.user?.id) {
            resetRecentViewsState()
            guard authState.isAuthenticated else { return }
            await loadRecentViewsIfNeeded()
        }
        .refreshable {
            await refreshRecentViews()
        }
    }

    @ViewBuilder
    private var recentViewsContent: some View {
        if isLoading {
            LoadingStateCard(title: AppStrings.Profile.recentlyViewed)
        } else if let error = recentViewsViewModel.error, recentViewsViewModel.items.isEmpty {
            ProfileDestinationEmptyStateCard(
                systemImage: "exclamationmark.triangle",
                title: AppStrings.Profile.recentlyViewed,
                message: recentViewsErrorMessage(error)
            )
        } else if filteredItems.isEmpty {
            ProfileDestinationEmptyStateCard(
                systemImage: "clock.arrow.circlepath",
                title: AppStrings.Profile.recentlyViewedEmptyTitle,
                message: AppStrings.Profile.recentlyViewedEmptyMessage
            )
        } else {
            VStack(spacing: AppTheme.feedRowSpacing) {
                ForEach(filteredItems) { item in
                    recentItemLink(item)
                }
            }
        }
    }

    private func loadRecentViewsIfNeeded() async {
        async let recentViewsLoad: Void = recentViewsViewModel.loadIfNeeded()
        async let newsLoad: Void = newsViewModel.loadIfNeeded()
        async let eventsLoad: Void = eventsViewModel.loadIfNeeded()
        async let organizationsLoad: Void = organizationsViewModel.loadIfNeeded()
        _ = await (recentViewsLoad, newsLoad, eventsLoad, organizationsLoad)
    }

    private func refreshRecentViews() async {
        async let recentViewsRefresh: Void = recentViewsViewModel.refresh()
        async let newsRefresh: Void = newsViewModel.refresh()
        async let eventsRefresh: Void = eventsViewModel.refresh()
        async let organizationsRefresh: Void = organizationsViewModel.refresh()
        _ = await (recentViewsRefresh, newsRefresh, eventsRefresh, organizationsRefresh)
    }

    private func resetRecentViewsState() {
        recentViewsViewModel.resetForAuthChange()
        newsViewModel.resetForAuthChange()
        eventsViewModel.resetForAuthChange()
        organizationsViewModel.resetForAuthChange()
    }

    private func recentViewsErrorMessage(_ error: AppError) -> String {
        switch error {
        case .permissionDenied:
            return AppStrings.Auth.requiredTitle
        case .network:
            return AppStrings.News.loadNetworkError
        case .validationFailed, .notFound:
            return AppStrings.News.loadValidationError
        case .unknown:
            return AppStrings.News.loadUnknownError
        }
    }

    @ViewBuilder
    private func recentItemLink(_ item: RecentViewItem) -> some View {
        switch item.itemType {
        case .news:
            NavigationLink {
                NewsDetailView(
                    viewModel: newsViewModel,
                    postID: item.itemId,
                    onNewsDeleted: { newsViewModel.reload() }
                )
            } label: {
                RecentViewRow(item: item)
            }
            .buttonStyle(.plain)
        case .event:
            NavigationLink {
                EventDetailView(
                    viewModel: eventsViewModel,
                    eventID: item.itemId,
                    onEventDeleted: { @MainActor @Sendable in
                        eventsViewModel.reload()
                    }
                )
            } label: {
                RecentViewRow(item: item)
            }
            .buttonStyle(.plain)
        case .organization:
            NavigationLink {
                OrganizationDetailView(viewModel: organizationsViewModel, organizationID: item.itemId)
            } label: {
                RecentViewRow(item: item)
            }
            .buttonStyle(.plain)
        case .guide:
            RecentViewRow(item: item)
                .opacity(0.72)
        }
    }
}

private struct RecentViewRow: View {
    let item: RecentViewItem

    private var subtitle: String {
        let trimmedSubtitle = item.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedSubtitle.isEmpty ? item.itemType.title : trimmedSubtitle
    }

    private var viewedAtText: String {
        LocalizationStore.dateString(from: item.viewedAt, dateStyle: .medium, timeStyle: .short)
    }

    var body: some View {
        AppEditorSectionCard {
            HStack(alignment: .center, spacing: 12) {
                AppFeedThumbnail(
                    imageURL: item.imageURL,
                    fallbackSystemImage: item.itemType.systemImage,
                    tint: AppTheme.accentPrimary,
                    fill: AppTheme.accentPrimary.opacity(0.10),
                    size: 58,
                    cornerRadius: 12,
                    source: "RecentViewRow"
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)

                    Label(viewedAtText, systemImage: "clock")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SavedContentView: View {
    @StateObject private var newsViewModel: NewsViewModel
    @StateObject private var eventsViewModel: EventsViewModel
    @StateObject private var organizationsViewModel: OrganizationsViewModel
    @State private var selectedSegment: SavedContentSegment = .all

    init(
        newsRepository: NewsRepository = FirestoreNewsRepository(),
        eventRepository: EventRepository = FirestoreEventRepository(),
        organizationRepository: OrganizationRepository = FirestoreOrganizationRepository()
    ) {
        _newsViewModel = StateObject(wrappedValue: NewsViewModel(repository: newsRepository))
        _eventsViewModel = StateObject(wrappedValue: EventsViewModel(repository: eventRepository))
        _organizationsViewModel = StateObject(wrappedValue: OrganizationsViewModel(repository: organizationRepository))
    }

    private var isLoading: Bool {
        (newsViewModel.isLoading || eventsViewModel.isLoading || organizationsViewModel.isLoading)
            && newsViewModel.bookmarkedPosts.isEmpty
            && eventsViewModel.bookmarkedEvents.isEmpty
            && bookmarkedOrganizations.isEmpty
    }

    private var loadError: AppError? {
        newsViewModel.error ?? eventsViewModel.error ?? organizationsViewModel.error
    }

    var body: some View {
        ProfileDestinationLayout(
            title: AppStrings.Profile.savedContent,
            introSubtitle: AppStrings.Profile.savedContentIntro
        ) {
            AppHorizontalFilterRow {
                ForEach(SavedContentSegment.allCases) { segment in
                    Button {
                        selectedSegment = segment
                    } label: {
                        AppFilterChip(
                            title: segment.title,
                            systemImage: segment.systemImage,
                            isSelected: selectedSegment == segment
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            savedContent
        }
        .task {
            await loadSavedContentIfNeeded()
        }
        .refreshable {
            await refreshSavedContent()
        }
        .onReceive(NotificationCenter.default.publisher(for: .newsChanged)) { _ in
            Task { await newsViewModel.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eventsChanged)) { _ in
            Task { await eventsViewModel.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .organizationsChanged)) { _ in
            Task { await organizationsViewModel.refresh() }
        }
    }

    @ViewBuilder
    private var savedContent: some View {
        if isLoading {
            LoadingStateCard(title: AppStrings.Profile.savedContent)
        } else if let loadError, currentItemsAreEmpty {
            ProfileDestinationEmptyStateCard(
                systemImage: "exclamationmark.triangle",
                title: AppStrings.Profile.savedContent,
                message: savedErrorMessage(loadError)
            )
        } else if currentItemsAreEmpty {
            ProfileDestinationEmptyStateCard(
                systemImage: emptyStateSystemImage,
                title: selectedSegment.title,
                message: emptyStateMessage
            )
        } else {
            VStack(spacing: AppTheme.feedRowSpacing) {
                switch selectedSegment {
                case .all:
                    ForEach(savedItems) { item in
                        savedItemLink(item)
                    }
                case .news:
                    ForEach(newsViewModel.bookmarkedPosts) { post in
                        savedNewsLink(post)
                    }
                case .events:
                    ForEach(eventsViewModel.bookmarkedEvents) { event in
                        savedEventLink(event)
                    }
                case .organizations:
                    ForEach(bookmarkedOrganizations) { organization in
                        savedOrganizationLink(organization)
                    }
                }
            }
        }
    }

    private var savedItems: [SavedContentItem] {
        (
            newsViewModel.bookmarkedPosts.map(SavedContentItem.news)
            + eventsViewModel.bookmarkedEvents.map(SavedContentItem.event)
            + bookmarkedOrganizations.map(SavedContentItem.organization)
        )
        .sorted { $0.savedSortDate > $1.savedSortDate }
    }

    private var bookmarkedOrganizations: [Organization] {
        organizationsViewModel.organizations.filter(\.isBookmarked)
    }

    private var currentItemsAreEmpty: Bool {
        switch selectedSegment {
        case .all:
            return savedItems.isEmpty
        case .news:
            return newsViewModel.bookmarkedPosts.isEmpty
        case .events:
            return eventsViewModel.bookmarkedEvents.isEmpty
        case .organizations:
            return bookmarkedOrganizations.isEmpty
        }
    }

    private var emptyStateSystemImage: String {
        switch selectedSegment {
        case .all:
            return "bookmark"
        case .news:
            return "newspaper"
        case .events:
            return "calendar"
        case .organizations:
            return "building.2"
        }
    }

    private var emptyStateMessage: String {
        switch selectedSegment {
        case .all:
            return AppStrings.Profile.savedEmptyAll
        case .news:
            return AppStrings.Profile.savedEmptyNews
        case .events:
            return AppStrings.Profile.savedEmptyEvents
        case .organizations:
            return AppStrings.Profile.savedEmptyOrganizations
        }
    }

    private func loadSavedContentIfNeeded() async {
        async let newsLoad: Void = newsViewModel.loadIfNeeded()
        async let eventsLoad: Void = eventsViewModel.loadIfNeeded()
        async let organizationsLoad: Void = organizationsViewModel.loadIfNeeded()
        _ = await (newsLoad, eventsLoad, organizationsLoad)
    }

    private func refreshSavedContent() async {
        async let newsRefresh: Void = newsViewModel.refresh()
        async let eventsRefresh: Void = eventsViewModel.refresh()
        async let organizationsRefresh: Void = organizationsViewModel.refresh()
        _ = await (newsRefresh, eventsRefresh, organizationsRefresh)
    }

    private func savedErrorMessage(_ error: AppError) -> String {
        switch error {
        case .network:
            return AppStrings.News.loadNetworkError
        case .permissionDenied:
            return AppStrings.News.loadPermissionError
        case .validationFailed, .notFound:
            return AppStrings.News.loadValidationError
        case .unknown:
            return AppStrings.News.loadUnknownError
        }
    }

    @ViewBuilder
    private func savedItemLink(_ item: SavedContentItem) -> some View {
        switch item {
        case let .news(post):
            savedNewsLink(post)
        case let .event(event):
            savedEventLink(event)
        case let .organization(organization):
            savedOrganizationLink(organization)
        }
    }

    private func savedNewsLink(_ post: NewsPost) -> some View {
        NavigationLink {
            NewsDetailView(
                viewModel: newsViewModel,
                postID: post.id,
                onNewsDeleted: { newsViewModel.reload() }
            )
        } label: {
            SavedNewsCard(post: post)
        }
        .buttonStyle(.plain)
    }

    private func savedEventLink(_ event: Event) -> some View {
        NavigationLink {
            EventDetailView(
                viewModel: eventsViewModel,
                eventID: event.id,
                onEventDeleted: { @MainActor @Sendable in
                    eventsViewModel.reload()
                }
            )
        } label: {
            SavedEventCard(event: event)
        }
        .buttonStyle(.plain)
    }

    private func savedOrganizationLink(_ organization: Organization) -> some View {
        NavigationLink {
            OrganizationDetailView(viewModel: organizationsViewModel, organizationID: organization.id)
        } label: {
            ProfileOrganizationListCard(organization: organization)
        }
        .buttonStyle(.plain)
    }
}

private struct FollowedOrganizationsView: View {
    @StateObject private var organizationsViewModel: OrganizationsViewModel

    init(organizationRepository: OrganizationRepository = FirestoreOrganizationRepository()) {
        _organizationsViewModel = StateObject(wrappedValue: OrganizationsViewModel(repository: organizationRepository))
    }

    private var followedOrganizations: [Organization] {
        organizationsViewModel.organizations
            .filter { $0.isSubscribed }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private var isLoading: Bool {
        organizationsViewModel.isLoading && followedOrganizations.isEmpty
    }

    var body: some View {
        ProfileDestinationLayout(
            title: AppStrings.Profile.organizationSubscriptions,
            introSubtitle: AppStrings.Profile.subscriptionsIntro
        ) {
            followedOrganizationsContent
        }
        .task {
            await organizationsViewModel.loadIfNeeded()
        }
        .refreshable {
            await organizationsViewModel.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .organizationsChanged)) { _ in
            Task { await organizationsViewModel.refresh() }
        }
    }

    @ViewBuilder
    private var followedOrganizationsContent: some View {
        if isLoading {
            LoadingStateCard(title: AppStrings.Profile.organizationSubscriptions)
        } else if let error = organizationsViewModel.error, followedOrganizations.isEmpty {
            ProfileDestinationEmptyStateCard(
                systemImage: "exclamationmark.triangle",
                title: AppStrings.Profile.organizationSubscriptions,
                message: followedOrganizationsErrorMessage(error)
            )
        } else if followedOrganizations.isEmpty {
            ProfileDestinationEmptyStateCard(
                systemImage: "person.2",
                title: AppStrings.Profile.organizationSubscriptions,
                message: AppStrings.Profile.subscriptionsEmpty
            )
        } else {
            VStack(spacing: AppTheme.feedRowSpacing) {
                ForEach(followedOrganizations) { organization in
                    NavigationLink {
                        OrganizationDetailView(
                            viewModel: organizationsViewModel,
                            organizationID: organization.id
                        )
                    } label: {
                        ProfileOrganizationListCard(organization: organization)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func followedOrganizationsErrorMessage(_ error: AppError) -> String {
        switch error {
        case .network:
            return AppStrings.Organizations.loadNetworkError
        case .permissionDenied:
            return AppStrings.Organizations.actionPermissionError
        case .validationFailed:
            return AppStrings.Organizations.actionValidationError
        case .notFound:
            return AppStrings.Organizations.actionNotFoundError
        case .unknown:
            return AppStrings.Organizations.actionUnknownError
        }
    }
}

private struct SavedNewsCard: View {
    let post: NewsPost

    var body: some View {
        AppEditorSectionCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "newspaper")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimary)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.accentPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(post.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)

                    Text(post.subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)

                    Label(LocalizationStore.dateString(from: post.publishedAt), systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }
}

private struct SavedEventCard: View {
    let event: Event

    var body: some View {
        AppEditorSectionCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimary)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.accentPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(event.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)

                    Text(event.summary)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)

                    Label(LocalizationStore.dateString(from: event.startDate), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }
}

private struct ProfileOrganizationListCard: View {
    let organization: Organization

    var body: some View {
        AppEditorSectionCard {
            HStack(alignment: .center, spacing: 12) {
                AppFeedThumbnail(
                    imageURL: organization.imageURL,
                    fallbackSystemImage: "building.2",
                    tint: AppTheme.accentPrimary,
                    fill: AppTheme.accentPrimary.opacity(0.10),
                    size: thumbnailSize,
                    source: "ProfileOrganizationListCard"
                )
                .frame(width: thumbnailSize, height: thumbnailSize, alignment: .center)

                VStack(alignment: .leading, spacing: 6) {
                    Text(organization.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)

                    Text(organization.shortDescription)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)

                    Label(metadataText, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    private var thumbnailSize: CGFloat {
        50
    }

    @MainActor private var metadataText: String {
        let region = organization.federalState.map(AppStrings.FederalStates.title(for:)) ?? organization.city
        if organization.city.isEmpty || organization.city == region {
            return region
        }
        return "\(organization.city), \(region)"
    }
}

private struct MyFeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: MyFeedbackViewModel
    let currentUserID: String
    @State private var selectedFeedback: FeedbackItem?

    var body: some View {
        ZStack {
            AppBackgroundView()
                .allowsHitTesting(false)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    AppCenteredBrandHeader {
                        AppGlassIconButton(systemImage: "chevron.left", accessibilityLabel: AppStrings.Common.back) {
                            dismiss()
                        }
                    } trailingContent: {
                        AppNotificationBellButton()
                    }

                    AppGroupedContentPlane {
                        VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                            AppEditorSectionCard {
                                SectionHeaderBlock(
                                    title: AppStrings.Feedback.myFeedbackTitle,
                                    subtitle: AppStrings.Feedback.myFeedbackSubtitle
                                )
                            }

                            feedbackContent
                        }
                    }
                }
                .padding(.horizontal, AppTheme.pageHorizontal)
                .padding(.top, AppTheme.sectionSpacing)
                .padding(.bottom, AppTheme.homeBottomContentPadding)
            }
        }
        .tint(AppTheme.accentPrimary)
        .navigationTitle(AppStrings.Feedback.myFeedbackTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: currentUserID) {
            await viewModel.loadIfNeeded(userID: currentUserID)
        }
        .refreshable {
            await viewModel.refresh(userID: currentUserID)
        }
        .sheet(item: $selectedFeedback) { item in
            let currentItem = currentFeedbackItem(for: item)
            FeedbackConversationSheet(
                item: currentItem,
                messages: viewModel.messages(for: currentItem),
                isLoadingMessages: viewModel.loadingMessageFeedbackIDs.contains(currentItem.id),
                isSending: viewModel.sendingMessageFeedbackIDs.contains(currentItem.id),
                allowsClose: false,
                onLoad: {
                    Task { await viewModel.loadMessages(for: currentItem) }
                },
                onSend: { text in
                    guard let user = authState.user else { return false }
                    let latestItem = currentFeedbackItem(for: currentItem)
                    let sent = await viewModel.sendMessage(text, feedback: latestItem, user: user)
                    if sent, let updatedItem = viewModel.items.first(where: { $0.id == latestItem.id }) {
                        selectedFeedback = updatedItem
                    }
                    return sent
                },
                onStop: {
                    viewModel.stopListeningMessages(for: currentItem.id)
                },
                onClose: nil
            )
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private var feedbackContent: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            LoadingStateCard(title: AppStrings.Feedback.myFeedbackTitle)
        } else if let error = viewModel.error, viewModel.items.isEmpty {
            UnifiedEmptyStateCard(
                systemImage: "exclamationmark.triangle",
                title: AppStrings.Feedback.myFeedbackTitle,
                message: feedbackErrorMessage(error)
            ) {
                PrimaryActionButton(title: AppStrings.Moderation.retry, systemImage: "arrow.clockwise") {
                    Task { await viewModel.refresh(userID: currentUserID) }
                }
            }
        } else if viewModel.items.isEmpty {
            UnifiedEmptyStateCard(
                systemImage: "tray",
                title: AppStrings.Feedback.myFeedbackTitle,
                message: AppStrings.Feedback.myFeedbackEmpty
            )
        } else {
            VStack(spacing: AppTheme.feedRowSpacing) {
                ForEach(viewModel.items) { item in
                    Button {
                        selectedFeedback = item
                    } label: {
                        FeedbackUserRequestCard(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func feedbackErrorMessage(_ error: AppError) -> String {
        switch error {
        case .permissionDenied:
            return AppStrings.Moderation.loadPermissionError
        case .network:
            return AppStrings.Moderation.loadNetworkError
        case .validationFailed, .notFound, .unknown:
            return AppStrings.Feedback.loadFailed
        }
    }

    private func currentFeedbackItem(for item: FeedbackItem) -> FeedbackItem {
        viewModel.items.first { $0.id == item.id } ?? item
    }
}

private struct FeedbackUserRequestCard: View {
    let item: FeedbackItem

    private var previewText: String {
        if let lastMessageText = item.lastMessageText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !lastMessageText.isEmpty {
            return lastMessageText
        }
        return item.message
    }

    private var previewDate: Date {
        item.lastMessageAt ?? item.updatedAt
    }

    private var previewRoleTitle: String? {
        item.lastMessageByRole?.title
    }

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.type.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    FeedbackStatusBadge(status: item.status, userFacing: true)
                }

                Text(previewText)
                    .font(.body)
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let previewRoleTitle {
                    FeedbackMetadataRow(systemImage: "person.crop.circle", title: previewRoleTitle)
                }

                FeedbackMetadataRow(systemImage: "calendar", title: LocalizationStore.dateString(from: previewDate, dateStyle: .medium, timeStyle: .short))
            }
        }
    }
}

private enum FeedbackInboxFilter: String, CaseIterable, Identifiable {
    case open
    case answered
    case closed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open:
            AppStrings.Feedback.filterOpen
        case .answered:
            AppStrings.Feedback.filterAnswered
        case .closed:
            AppStrings.Feedback.filterClosed
        }
    }

    func includes(_ item: FeedbackItem) -> Bool {
        switch self {
        case .open:
            item.status == .open
        case .answered:
            item.status.isAnswered
        case .closed:
            item.status.isClosed
        }
    }
}

private struct FeedbackInboxView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel: FeedbackInboxViewModel
    @State private var selectedFeedback: FeedbackItem?
    @State private var selectedFilter: FeedbackInboxFilter = .open

    private var filteredItems: [FeedbackItem] {
        viewModel.items.filter { selectedFilter.includes($0) }
    }

    init(repository: FeedbackRepository) {
        _viewModel = StateObject(wrappedValue: FeedbackInboxViewModel(repository: repository))
    }

    var body: some View {
        ZStack {
            AppBackgroundView()
                .allowsHitTesting(false)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    AppCenteredBrandHeader {
                        AppGlassIconButton(systemImage: "chevron.left", accessibilityLabel: AppStrings.Common.back) {
                            dismiss()
                        }
                    } trailingContent: {
                        AppNotificationBellButton()
                    }

                    AppGroupedContentPlane {
                        VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                            AppEditorSectionCard {
                                VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                                    SectionHeaderBlock(
                                        title: AppStrings.Feedback.inboxTitle,
                                        subtitle: AppStrings.Feedback.inboxSubtitle
                                    )

                                    Picker(AppStrings.Feedback.inboxFilter, selection: $selectedFilter) {
                                        ForEach(FeedbackInboxFilter.allCases) { filter in
                                            Text(filter.title).tag(filter)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                }
                            }

                            inboxContent
                        }
                    }
                }
                .padding(.horizontal, AppTheme.pageHorizontal)
                .padding(.top, AppTheme.sectionSpacing)
                .padding(.bottom, AppTheme.homeBottomContentPadding)
            }
        }
        .tint(AppTheme.accentPrimary)
        .navigationTitle(AppStrings.Feedback.inboxTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .sheet(item: $selectedFeedback) { item in
            let currentItem = currentFeedbackItem(for: item)
            FeedbackDetailSheet(
                item: currentItem,
                messages: viewModel.messages(for: currentItem),
                isLoadingMessages: viewModel.loadingMessageFeedbackIDs.contains(currentItem.id),
                isUpdating: viewModel.updatingFeedbackIDs.contains(currentItem.id),
                onLoad: {
                    Task { await viewModel.loadMessages(for: currentItem) }
                },
                onSendReply: { reply in
                    guard let owner = authState.user else { return false }
                    let latestItem = currentFeedbackItem(for: currentItem)
                    let sent = await viewModel.sendReply(reply, to: latestItem, owner: owner)
                    if sent, let updatedItem = viewModel.items.first(where: { $0.id == latestItem.id }) {
                        selectedFeedback = updatedItem
                    }
                    return sent
                },
                onStop: {
                    viewModel.stopListeningMessages(for: currentItem.id)
                },
                onClose: {
                    Task {
                        await viewModel.close(currentFeedbackItem(for: currentItem))
                        selectedFeedback = nil
                    }
                }
            )
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private var inboxContent: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            LoadingStateCard(title: AppStrings.Feedback.inboxTitle)
        } else if let error = viewModel.error, viewModel.items.isEmpty {
            UnifiedEmptyStateCard(
                systemImage: "exclamationmark.triangle",
                title: AppStrings.Feedback.inboxTitle,
                message: feedbackErrorMessage(error)
            ) {
                PrimaryActionButton(title: AppStrings.Moderation.retry, systemImage: "arrow.clockwise") {
                    Task { await viewModel.refresh() }
                }
            }
        } else if viewModel.items.isEmpty {
            UnifiedEmptyStateCard(
                systemImage: "bubble.left.and.bubble.right",
                title: AppStrings.Feedback.inboxTitle,
                message: AppStrings.Feedback.inboxEmpty
            )
        } else if filteredItems.isEmpty {
            UnifiedEmptyStateCard(
                systemImage: "line.3.horizontal.decrease.circle",
                title: selectedFilter.title,
                message: AppStrings.Feedback.inboxFilterEmpty
            )
        } else {
            VStack(spacing: AppTheme.feedRowSpacing) {
                if let error = viewModel.error {
                    InlineMessageCard(style: .error, message: feedbackErrorMessage(error))
                }

                ForEach(filteredItems) { item in
                    Button {
                        selectedFeedback = item
                    } label: {
                        FeedbackInboxRow(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func feedbackErrorMessage(_ error: AppError) -> String {
        switch error {
        case .permissionDenied:
            return AppStrings.Moderation.loadPermissionError
        case .network:
            return AppStrings.Moderation.loadNetworkError
        case .validationFailed, .notFound, .unknown:
            return AppStrings.Feedback.loadFailed
        }
    }

    private func currentFeedbackItem(for item: FeedbackItem) -> FeedbackItem {
        viewModel.items.first { $0.id == item.id } ?? item
    }
}

private struct FeedbackInboxRow: View {
    let item: FeedbackItem

    private var authorTitle: String {
        if !item.userDisplayName.isEmpty {
            return item.userDisplayName
        }
        if !item.userId.isEmpty {
            return item.userId
        }
        return AppStrings.Profile.unknownUser
    }

    private var previewText: String {
        if let lastMessageText = item.lastMessageText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !lastMessageText.isEmpty {
            return lastMessageText
        }
        return item.message
    }

    private var previewDate: Date {
        item.lastMessageAt ?? item.updatedAt
    }

    private var previewRoleTitle: String? {
        item.lastMessageByRole?.title
    }

    var body: some View {
        AppEditorSectionCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimary)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.accentPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.type.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        FeedbackStatusBadge(status: item.status)
                    }

                    Text(previewText)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        Label(authorTitle, systemImage: "person")
                            .lineLimit(1)
                        Text("•")
                        Text(LocalizationStore.dateString(from: previewDate, dateStyle: .short, timeStyle: .short))
                            .lineLimit(1)
                        if let previewRoleTitle {
                            Text("•")
                            Text(previewRoleTitle)
                                .lineLimit(1)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.top, 2)
            }
        }
    }
}

private struct FeedbackDetailSheet: View {
    let item: FeedbackItem
    let messages: [FeedbackMessage]
    let isLoadingMessages: Bool
    let isUpdating: Bool
    let onLoad: () -> Void
    let onSendReply: (String) async -> Bool
    let onStop: () -> Void
    let onClose: () -> Void

    var body: some View {
        FeedbackConversationSheet(
            item: item,
            messages: messages,
            isLoadingMessages: isLoadingMessages,
            isSending: isUpdating,
            allowsClose: true,
            onLoad: onLoad,
            onSend: onSendReply,
            onStop: onStop,
            onClose: onClose
        )
    }
}

private struct FeedbackConversationSheet: View {
    let item: FeedbackItem
    let messages: [FeedbackMessage]
    let isLoadingMessages: Bool
    let isSending: Bool
    let allowsClose: Bool
    let onLoad: () -> Void
    let onSend: (String) async -> Bool
    let onStop: () -> Void
    let onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var replyText = ""
    @State private var validationMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                            AppEditorSectionCard {
                                VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(item.type.title)
                                            .font(.headline.weight(.semibold))
                                            .foregroundStyle(AppTheme.textPrimary)
                                        Spacer(minLength: 0)
                                        FeedbackStatusBadge(status: item.status, userFacing: true)
                                    }

                                    FeedbackMetadataRow(systemImage: "person", title: item.userDisplayName.isEmpty ? AppStrings.Profile.unknownUser : item.userDisplayName)
                                    FeedbackMetadataRow(systemImage: "calendar", title: LocalizationStore.dateString(from: item.createdAt, dateStyle: .medium, timeStyle: .short))
                                }
                            }

                            if isLoadingMessages && messages.isEmpty {
                                LoadingStateCard(title: AppStrings.Feedback.messagesTitle)
                            } else if messages.isEmpty {
                                UnifiedEmptyStateCard(
                                    systemImage: "bubble.left",
                                    title: AppStrings.Feedback.messagesTitle,
                                    message: AppStrings.Feedback.noMessages
                                )
                            } else {
                                VStack(spacing: 10) {
                                    ForEach(messages) { message in
                                        FeedbackMessageBubble(message: message)
                                            .id(message.id)
                                    }
                                }
                            }
                        }
                        .padding(AppTheme.pageHorizontal)
                        .padding(.bottom, AppTheme.sectionSpacing)
                    }
                    .onAppear {
                        scrollToLastMessage(with: proxy, animated: false)
                    }
                    .onChange(of: messages.last?.id) {
                        scrollToLastMessage(with: proxy)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    if item.status.isClosed {
                        Label(AppStrings.Feedback.closedMessage, systemImage: "lock")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ZStack(alignment: .topLeading) {
                            if replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(AppStrings.Feedback.addReply)
                                    .font(.body)
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 14)
                            }

                            TextEditor(text: $replyText)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 86, maxHeight: 120)
                                .padding(8)
                        }
                        .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(AppTheme.borderSubtle)
                        )

                        HStack {
                            Text("\(replyText.count)/2000")
                                .foregroundStyle(AppTheme.textSecondary)
                            Spacer(minLength: 0)
                            if let validationMessage {
                                Text(validationMessage)
                                    .foregroundStyle(AppTheme.accentDestructive)
                            }
                        }
                        .font(.caption)

                        HStack(spacing: AppTheme.eventsMetadataSpacing) {
                            PrimaryActionButton(
                                title: isSending ? AppStrings.Feedback.sending : AppStrings.Feedback.send,
                                isEnabled: !isSending,
                                isLoading: isSending,
                                systemImage: "paperplane"
                            ) {
                                submitReply()
                            }

                            if allowsClose, let onClose {
                                Button(action: onClose) {
                                    Label(AppStrings.Feedback.closeFeedback, systemImage: "checkmark.seal")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppTheme.accentDestructive)
                                        .frame(height: AppTheme.iconButtonSize)
                                        .padding(.horizontal, 12)
                                        .background(AppTheme.accentDestructive.opacity(0.10), in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .disabled(isSending)
                            }
                        }
                    }
                }
                .padding(AppTheme.pageHorizontal)
                .padding(.vertical, 12)
                .background(AppTheme.pageBackground)
            }
            .background(AppTheme.pageBackground)
            .navigationTitle(AppStrings.Feedback.inboxTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppStrings.Common.done) {
                        dismiss()
                    }
                }
            }
            .task {
                onLoad()
            }
            .onDisappear {
                onStop()
            }
        }
    }

    private func submitReply() {
        let trimmedReply = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedReply.isEmpty {
            validationMessage = AppStrings.Feedback.replyRequired
            return
        }

        if trimmedReply.count > 2000 {
            validationMessage = AppStrings.Feedback.replyTooLong
            return
        }

        validationMessage = nil
        Task {
            let sent = await onSend(trimmedReply)
            if sent {
                replyText = ""
                validationMessage = nil
            } else {
                validationMessage = "\(AppStrings.Feedback.sendMessageFailed) \(AppStrings.Feedback.tryAgain)"
            }
        }
    }

    private func scrollToLastMessage(with proxy: ScrollViewProxy, animated: Bool = true) {
        guard let lastMessageID = messages.last?.id else { return }
        let action = {
            proxy.scrollTo(lastMessageID, anchor: .bottom)
        }

        if animated {
            withAnimation(.easeOut(duration: 0.2), action)
        } else {
            action()
        }
    }
}

private struct FeedbackMessageBubble: View {
    let message: FeedbackMessage

    private var isOwnerMessage: Bool {
        message.senderRole == .owner
    }

    var body: some View {
        HStack {
            if isOwnerMessage {
                Spacer(minLength: 32)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(message.isSystem ? AppStrings.Feedback.supportLabel : message.senderRole.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isOwnerMessage ? AppTheme.accentPrimary : AppTheme.textSecondary)

                    Text(LocalizationStore.dateString(from: message.createdAt, dateStyle: .short, timeStyle: .short))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(
                (isOwnerMessage ? AppTheme.accentPrimary.opacity(0.10) : AppTheme.surfaceSecondary),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppTheme.borderSubtle)
            )
            .frame(maxWidth: 520, alignment: isOwnerMessage ? .trailing : .leading)

            if !isOwnerMessage {
                Spacer(minLength: 32)
            }
        }
    }
}

private struct FeedbackStatusBadge: View {
    let status: FeedbackStatus
    var userFacing = false

    private var tint: Color {
        switch status {
        case .open:
            return AppTheme.accentPrimary
        case .answered, .reviewed:
            return AppTheme.textSecondary
        case .archived, .closed:
            return AppTheme.accentDestructive
        }
    }

    private var title: String {
        if userFacing && status == .open {
            return AppStrings.Feedback.statusWaitingReply
        }
        return status.title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.10), in: Capsule())
            .lineLimit(1)
    }
}

private struct FeedbackMetadataRow: View {
    let systemImage: String
    let title: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(AppTheme.textSecondary)
            .lineLimit(2)
    }
}

private struct ProfileSettingsPickerRow<PickerContent: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let picker: PickerContent

    init(title: String, subtitle: String, systemImage: String, @ViewBuilder picker: () -> PickerContent) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.picker = picker()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: 30, height: 30)
                .background(AppTheme.accentPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            picker
                .controlSize(.small)
        }
        .padding(.vertical, 3)
    }
}

private enum ProfileModuleStatus {
    case available
    case active
    case accountRequired
    case soon
    case locked

    var title: String? {
        switch self {
        case .available:
            return nil
        case .active:
            return AppStrings.Common.active
        case .accountRequired:
            return AppStrings.Profile.accountRequiredBadge
        case .soon:
            return AppStrings.Profile.comingSoon
        case .locked:
            return AppStrings.Profile.accessLocked
        }
    }

    var tint: Color {
        switch self {
        case .available, .active:
            return AppTheme.accentPrimary
        case .accountRequired, .soon:
            return AppTheme.textSecondary
        case .locked:
            return AppTheme.accentDestructive
        }
    }

    var isDisabled: Bool {
        switch self {
        case .accountRequired, .soon, .locked:
            return true
        case .available, .active:
            return false
        }
    }
}

private struct ProfileTextModuleRow: View {
    let title: String
    let subtitle: String?
    let accessory: AppNavigationRowAccessory

    init(
        title: String,
        subtitle: String? = nil,
        accessory: AppNavigationRowAccessory = .chevron
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            if accessory == .chevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .center)
        .accessibilityElement(children: .combine)
    }
}

private struct ProfileModuleRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let tint: Color?
    let status: ProfileModuleStatus
    let accessory: AppNavigationRowAccessory

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        tint: Color? = nil,
        status: ProfileModuleStatus = .available,
        accessory: AppNavigationRowAccessory = .chevron
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.status = status
        self.accessory = accessory
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            AppNavigationRow(
                title: title,
                subtitle: subtitle,
                systemImage: systemImage,
                tint: tint ?? status.tint,
                accessory: status.title == nil && !status.isDisabled ? accessory : .none
            )

            if let statusTitle = status.title {
                Text(statusTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(status.tint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(status.tint.opacity(0.10), in: Capsule())
                    .lineLimit(1)
                    .frame(minWidth: 82)
            }
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .center)
        .opacity(status.isDisabled ? 0.72 : 1)
        .allowsHitTesting(!status.isDisabled)
        .accessibilityHint(status.isDisabled ? AppStrings.Action.comingSoon : "")
    }
}

private struct PlatformAccessStrip: View {
    let user: AppUser

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.eventsMetadataSpacing) {
            ProfileBadge(title: user.globalRole.title, systemImage: "person.badge.key")
            ProfileBadge(title: AppStrings.Profile.verifiedAccess, systemImage: "checkmark.seal")

            if user.globalRole.effectiveRole == .owner {
                ProfileBadge(title: AppStrings.Profile.systemAccessLevel, systemImage: "lock.shield")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        AppEditorSectionCard {
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
                    Text(AppStrings.Profile.profilePhoto)
                        .font(.headline)
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(AppStrings.Profile.avatarSubtitle)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                        Label(AppStrings.Profile.changeAvatar, systemImage: "camera.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.accentPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AppTheme.accentPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
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
    }
}

private struct ProfileEditorTextArea: View {
    let title: String
    @Binding var text: String
    let counterText: String

    var body: some View {
        AppEditorField(title: title, counterText: counterText) {
            TextEditor(text: $text)
                .font(.subheadline)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 92)
                .padding(8)
                .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
                        .strokeBorder(AppTheme.borderSubtle)
                )
                .accessibilityLabel(title)
        }
    }
}

private struct ProfileReadOnlyField: View {
    let title: String
    let value: String
    let systemImage: String
    let helperText: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: AppTheme.metadataIconSize)

                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppTheme.inputHorizontalPadding)
            .frame(height: AppTheme.newsEditorInputHeight)
            .background(AppTheme.surfaceSecondary.opacity(0.68), in: RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
                    .strokeBorder(AppTheme.borderSubtle)
            )

            Text(helperText)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
    }
}

private struct ProfileEditorPickerRow<PickerContent: View>: View {
    let title: String
    let systemImage: String
    let picker: PickerContent

    init(title: String, systemImage: String, @ViewBuilder picker: () -> PickerContent) {
        self.title = title
        self.systemImage = systemImage
        self.picker = picker()
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: AppTheme.metadataIconSize)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textPrimary)

            Spacer(minLength: 8)

            picker
                .font(.subheadline)
        }
        .padding(.horizontal, AppTheme.inputHorizontalPadding)
        .frame(height: AppTheme.newsEditorInputHeight)
        .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle)
        )
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

private enum MyEventsSegment: String, CaseIterable, Identifiable {
    case all
    case upcoming
    case past

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return AppStrings.Home.filterAll
        case .upcoming:
            return AppStrings.Profile.myEventsUpcoming
        case .past:
            return AppStrings.Profile.myEventsPast
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "calendar"
        case .upcoming:
            return "calendar.badge.clock"
        case .past:
            return "clock.arrow.circlepath"
        }
    }
}

private struct MyRegistrationsView: View {
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: MyRegistrationsViewModel
    let eventRepository: EventRepository
    @State private var selectedSegment: MyEventsSegment = .upcoming

    private var calendar: Calendar { .current }

    private var upcomingEvents: [Event] {
        let startOfToday = calendar.startOfDay(for: Date())
        return viewModel.events
            .filter { $0.endDate >= startOfToday }
            .sorted { $0.startDate < $1.startDate }
    }

    private var pastEvents: [Event] {
        let startOfToday = calendar.startOfDay(for: Date())
        return viewModel.events
            .filter { $0.endDate < startOfToday }
            .sorted { $0.endDate > $1.endDate }
    }

    private var filteredEvents: [Event] {
        switch selectedSegment {
        case .all:
            return upcomingEvents + pastEvents
        case .upcoming:
            return upcomingEvents
        case .past:
            return pastEvents
        }
    }

    private var emptyStateTitle: String {
        switch selectedSegment {
        case .all:
            return AppStrings.Profile.myEventsEmptyAllTitle
        case .upcoming:
            return AppStrings.Profile.myEventsEmptyUpcomingTitle
        case .past:
            return AppStrings.Profile.myEventsEmptyPastTitle
        }
    }

    private var emptyStateMessage: String {
        switch selectedSegment {
        case .all:
            return AppStrings.Profile.myEventsEmptyRegisterMessage
        case .upcoming:
            return viewModel.events.isEmpty
                ? AppStrings.Profile.myEventsEmptyRegisterMessage
                : AppStrings.Profile.myEventsEmptyUpcomingMessage
        case .past:
            return viewModel.events.isEmpty
                ? AppStrings.Profile.myEventsEmptyRegisterMessage
                : AppStrings.Profile.myEventsEmptyPastMessage
        }
    }

    var body: some View {
        ProfileDestinationLayout(
            title: AppStrings.Profile.myRegistrations,
            introSubtitle: AppStrings.Profile.myEventsIntro
        ) {
            filtersRow
            registrationsContent
        }
        .task {
            await viewModel.loadIfNeeded()
            await viewModel.refreshIfStale()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .registrationsChanged)) { _ in
            guard authState.isAuthenticated else { return }
            Task {
                await viewModel.refresh()
            }
        }
    }

    @ViewBuilder
    private var filtersRow: some View {
        AppHorizontalFilterRow {
            ForEach(MyEventsSegment.allCases) { segment in
                Button {
                    selectedSegment = segment
                } label: {
                    AppFilterChip(
                        title: segment.title,
                        systemImage: segment.systemImage,
                        isSelected: selectedSegment == segment
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var registrationsContent: some View {
        if viewModel.isLoading && viewModel.events.isEmpty {
            LoadingStateCard(title: AppStrings.Profile.registrationsLoading)
        } else if let error = viewModel.error, viewModel.events.isEmpty {
            ErrorStateCard(
                title: AppStrings.Profile.myRegistrations,
                message: readableRegistrationsErrorText(error)
            )
        } else if viewModel.events.isEmpty || filteredEvents.isEmpty {
            ProfileDestinationEmptyStateCard(
                systemImage: viewModel.events.isEmpty ? "calendar.badge.clock" : selectedSegment.systemImage,
                title: emptyStateTitle,
                message: emptyStateMessage
            )
        } else {
            VStack(spacing: AppTheme.feedRowSpacing) {
                ForEach(filteredEvents) { event in
                    registrationRow(for: event)
                }
            }
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
        .buttonStyle(.plain)
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
        SoftContentCard(padding: AppTheme.eventsCardPadding) {
            HStack(alignment: .center, spacing: AppTheme.eventsCardHorizontalSpacing) {
                AppEventDateBlock(date: event.startDate)

                VStack(alignment: .leading, spacing: AppTheme.eventsCardContentSpacing) {
                    AppInfoChip(
                        title: AppStrings.Events.title.uppercased(),
                        systemImage: "calendar",
                        tint: AppTheme.accentPrimary,
                        fill: AppTheme.badgeBlueFill,
                        size: .small
                    )

                    Text(event.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)

                    if !event.summary.isEmpty {
                        Text(event.summary)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary.opacity(0.88))
                            .lineLimit(1)
                    }

                    HStack(spacing: AppTheme.eventsMetadataSpacing) {
                        AppMetadataLine(title: LocalizationStore.timeRangeString(startDate: event.startDate, endDate: event.endDate), systemImage: "clock")
                        AppMetadataLine(title: event.city.isEmpty ? event.venue : event.city, systemImage: event.city.isEmpty ? "building.2" : "mappin.and.ellipse")
                    }
                }
                .padding(.trailing, 6)

                Spacer(minLength: 0)

                ZStack(alignment: .topTrailing) {
                    AppFeedThumbnail(
                        imageURL: event.imageURL,
                        fallbackSystemImage: "calendar",
                        tint: AppTheme.accentPrimary,
                        fill: AppTheme.badgeBlueFill,
                        size: AppTheme.eventsThumbnailSize,
                        cornerRadius: 14,
                        source: "RegistrationEventRow"
                    )

                    if isUpdating {
                        ProgressView()
                            .controlSize(.small)
                            .tint(AppTheme.accentPrimary)
                            .padding(6)
                            .background(.regularMaterial, in: Circle())
                    }
                }
                .padding(.trailing, 26)
                .frame(maxHeight: AppTheme.eventsThumbnailSize)
                .layoutPriority(-1)
            }
        }
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

            PrimaryActionButton(
                title: AppStrings.Feedback.submit,
                isEnabled: !isSubmitting,
                isLoading: isSubmitting,
                systemImage: "paperplane"
            ) {
                onSubmit()
            }
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

private extension MyRegistrationsViewModel {
    var registrationsCountText: String {
        if isLoading && events.isEmpty {
            return AppStrings.Profile.loadingStatValue
        }

        return "\(registrationsCount)"
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

private enum ManagedOrganizationRole {
    case owner
    case platformOwner
    case admin
    case moderator

    var title: String {
        switch self {
        case .owner:
            return AppStrings.Profile.organizationRoleOwner
        case .platformOwner:
            return AppStrings.Profile.organizationRolePlatformOwner
        case .admin:
            return AppStrings.Profile.organizationRoleAdmin
        case .moderator:
            return AppStrings.Profile.organizationRoleModerator
        }
    }

    var tint: Color {
        switch self {
        case .owner:
            return AppTheme.accentPrimary
        case .platformOwner:
            return .indigo
        case .admin:
            return .blue
        case .moderator:
            return .orange
        }
    }
}

private struct ManagedOrganizationContentStats {
    let newsCount: Int
    let eventCount: Int
}

private struct OrganizationManagementHubView: View {
    @EnvironmentObject private var authState: AuthState
    let focusedOrganizationID: String?

    private let repository: OrganizationRepository
    private let newsRepository: NewsRepository
    private let eventRepository: EventRepository
    @StateObject private var organizationsViewModel: OrganizationsViewModel
    @State private var isShowingCreateOrganization = false
    @State private var editingOrganizationRequest: Organization?
    @State private var previewingOrganizationRequest: Organization?
    @State private var organizationContentStats: [String: ManagedOrganizationContentStats] = [:]
    @State private var loadingContentStatOrganizationIDs = Set<String>()

    private var authorityUser: AppUser? {
        authState.user
    }

    init(
        focusedOrganizationID: String? = nil,
        repository: OrganizationRepository = FirestoreOrganizationRepository(),
        newsRepository: NewsRepository = FirestoreNewsRepository(),
        eventRepository: EventRepository = FirestoreEventRepository()
    ) {
        self.focusedOrganizationID = focusedOrganizationID
        self.repository = repository
        self.newsRepository = newsRepository
        self.eventRepository = eventRepository
        _organizationsViewModel = StateObject(wrappedValue: OrganizationsViewModel(repository: repository))
    }

    private var manageableOrganizations: [Organization] {
        guard let authorityUser else { return [] }
        let organizations = PermissionService.manageableOrganizations(
            from: organizationsViewModel.organizations,
            user: authorityUser
        )
        guard let focusedOrganizationID else { return organizations }
        return organizations.filter { $0.id == focusedOrganizationID }
    }

    private var organizationRequests: [Organization] {
        focusedOrganizationID == nil ? organizationsViewModel.organizationRequests : []
    }

    private var subscribedOrganizations: [Organization] {
        guard focusedOrganizationID == nil else { return [] }
        let managedIDs = Set(manageableOrganizations.map(\.id))
        let requestIDs = Set(organizationRequests.map(\.id))
        return organizationsViewModel.organizations
            .filter {
                $0.isSubscribed
                    && $0.moderationStatus == .approved
                    && !managedIDs.contains($0.id)
                    && !requestIDs.contains($0.id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var allOrganizationSectionsAreEmpty: Bool {
        manageableOrganizations.isEmpty && organizationRequests.isEmpty && subscribedOrganizations.isEmpty
    }

    private func organizationRole(for organization: Organization) -> ManagedOrganizationRole? {
        guard let authorityUser else { return nil }
        if organization.ownerId == authorityUser.id {
            return .owner
        }
        if authorityUser.globalRole.effectiveRole == .owner {
            return .platformOwner
        }
        if organization.adminIds.contains(authorityUser.id) {
            return .admin
        }
        if organization.moderatorIds.contains(authorityUser.id) {
            return .moderator
        }
        return nil
    }

    private var canCreateOrganization: Bool {
        PermissionService.canCreateOrganization(user: authorityUser)
    }

    var body: some View {
        ProfileDestinationLayout(
            title: AppStrings.Profile.myOrganizations,
            introSubtitle: AppStrings.Profile.organizationManagementIntro
        ) {
            if canCreateOrganization {
                createOrganizationCard
            }

            managedOrganizationsContent
        }
        .task {
            await organizationsViewModel.loadIfNeeded()
            await organizationsViewModel.refreshIfStale()
            await organizationsViewModel.loadOrganizationRequests(for: authorityUser)
            await loadManageableOrganizationContentStats()
        }
        .refreshable {
            await organizationsViewModel.refresh()
            await organizationsViewModel.loadOrganizationRequests(for: authorityUser)
            await loadManageableOrganizationContentStats(force: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .organizationsChanged).debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { _ in
            Task {
                await organizationsViewModel.refresh()
                await organizationsViewModel.loadOrganizationRequests(for: authorityUser)
                await loadManageableOrganizationContentStats(force: true)
            }
        }
        .onChange(of: authState.user?.id) { _, newUserID in
            if newUserID == nil {
                isShowingCreateOrganization = false
                organizationContentStats = [:]
                loadingContentStatOrganizationIDs = []
                organizationsViewModel.resetForAuthChange()
            } else {
                Task {
                    organizationsViewModel.resetForAuthChange()
                    organizationContentStats = [:]
                    loadingContentStatOrganizationIDs = []
                    await organizationsViewModel.refresh()
                    await organizationsViewModel.loadOrganizationRequests(for: authorityUser)
                    await loadManageableOrganizationContentStats(force: true)
                }
            }
        }
        .sheet(isPresented: $isShowingCreateOrganization) {
            NavigationStack {
                OrganizationEditorView(
                    organizationsViewModel: organizationsViewModel,
                    onSaved: {
                        await organizationsViewModel.refresh()
                        await organizationsViewModel.loadOrganizationRequests(for: authorityUser)
                    }
                )
            }
            .environmentObject(authState)
        }
        .sheet(item: $editingOrganizationRequest) { organization in
            NavigationStack {
                OrganizationEditorView(
                    organizationsViewModel: organizationsViewModel,
                    organization: organization,
                    onSaved: {
                        await organizationsViewModel.loadOrganizationRequests(for: authorityUser)
                    }
                )
            }
            .environmentObject(authState)
        }
        .sheet(item: $previewingOrganizationRequest) { organization in
            NavigationStack {
                OrganizationRequestPreviewView(organization: organization)
            }
        }
    }

    private var createOrganizationCard: some View {
        Button {
            isShowingCreateOrganization = true
        } label: {
            AppEditorSectionCard {
                AppNavigationRow(
                    title: AppStrings.Profile.ownerCreateOrganization,
                    subtitle: AppStrings.Profile.organizationManagementSubtitle,
                    systemImage: "plus.circle",
                    accessory: .none
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("organization.management.create")
        .accessibilityLabel(AppStrings.Profile.ownerCreateOrganization)
    }

    @ViewBuilder
    private var managedOrganizationsContent: some View {
        if organizationsViewModel.isLoading && allOrganizationSectionsAreEmpty {
            LoadingStateCard(title: nil)
        } else if allOrganizationSectionsAreEmpty {
            ProfileDestinationEmptyStateCard(
                systemImage: "building.2",
                title: AppStrings.Profile.myOrganizations,
                message: AppStrings.Profile.noOrganizations
            )
        } else {
            if !manageableOrganizations.isEmpty {
                VStack(spacing: AppTheme.feedRowSpacing) {
                    ForEach(manageableOrganizations) { organization in
                        ManagedOrganizationCard(
                            organization: organization,
                            role: organizationRole(for: organization) ?? .moderator,
                            organizationsViewModel: organizationsViewModel,
                            contentStats: organizationContentStats[organization.id],
                            isLoadingContentStats: loadingContentStatOrganizationIDs.contains(organization.id)
                        )
                    }
                }
            }

            if !organizationRequests.isEmpty {
                AppEditorSectionCard {
                    AppEditorSectionTitle(title: AppStrings.Profile.organizationRequests)
                }

                VStack(spacing: AppTheme.feedRowSpacing) {
                    ForEach(organizationRequests) { organization in
                        OrganizationRequestCard(
                            organization: organization,
                            previewAction: {
                                previewingOrganizationRequest = organization
                            },
                            editAction: {
                                editingOrganizationRequest = organization
                            }
                        )
                    }
                }
            }

            if !subscribedOrganizations.isEmpty {
                AppEditorSectionCard {
                    AppEditorSectionTitle(title: AppStrings.Profile.subscribedOrganizations)
                }

                VStack(spacing: AppTheme.feedRowSpacing) {
                    ForEach(subscribedOrganizations) { organization in
                        NavigationLink {
                            OrganizationDetailView(
                                viewModel: organizationsViewModel,
                                organizationID: organization.id
                            )
                        } label: {
                            ProfileOrganizationListCard(organization: organization)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func loadManageableOrganizationContentStats(force: Bool = false) async {
        let organizationIDs = Set(manageableOrganizations.map(\.id))
        organizationContentStats = organizationContentStats.filter { organizationIDs.contains($0.key) }
        loadingContentStatOrganizationIDs = loadingContentStatOrganizationIDs.intersection(organizationIDs)

        for organizationID in organizationIDs.sorted() {
            if !force && organizationContentStats[organizationID] != nil {
                continue
            }
            if loadingContentStatOrganizationIDs.contains(organizationID) {
                continue
            }

            loadingContentStatOrganizationIDs.insert(organizationID)
            do {
                async let newsCount = newsRepository.fetchOrganizationNewsCount(organizationID: organizationID)
                async let eventCount = eventRepository.fetchOrganizationEventCount(organizationID: organizationID)
                organizationContentStats[organizationID] = ManagedOrganizationContentStats(
                    newsCount: try await newsCount,
                    eventCount: try await eventCount
                )
            } catch {
                organizationContentStats[organizationID] = nil
            }
            loadingContentStatOrganizationIDs.remove(organizationID)
        }
    }
}

private struct OrganizationRequestPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let organization: Organization

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                AppEditorSectionCard {
                    HStack(alignment: .top, spacing: 12) {
                        AppFeedThumbnail(
                            imageURL: organization.imageURL,
                            fallbackSystemImage: "building.2",
                            tint: AppTheme.accentPrimary,
                            fill: AppTheme.accentPrimary.opacity(0.10),
                            size: 56,
                            source: "OrganizationRequestPreviewView"
                        )

                        VStack(alignment: .leading, spacing: 7) {
                            AppEditorSectionTitle(title: organization.name)
                            Text(organization.moderationStatus.title)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppTheme.accentPrimary)
                            Text(organization.shortDescription)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }

                previewSection(title: AppStrings.Organizations.aboutSectionTitle) {
                    previewRow(AppStrings.Moderation.shortDescription, organization.shortDescription)
                    previewRow(AppStrings.Moderation.fullDescription, organization.fullDescription)
                    previewRow(AppStrings.Organizations.fieldMissionStatement, organization.missionStatement)
                }

                previewSection(title: AppStrings.Profile.organizationContactsSection) {
                    previewRow(AppStrings.Organizations.fieldContactEmail, organization.contactEmail ?? organization.email)
                    previewRow(AppStrings.Organizations.phonePlaceholder, organization.phone)
                    previewRow(AppStrings.Common.website, organization.website)
                    previewRow(AppStrings.Organizations.fieldTelegramURL, organization.telegramURL)
                    previewRow(AppStrings.Organizations.fieldDonationURL, organization.donationURL)
                    previewRow(AppStrings.Organizations.fieldAddress, organization.address)
                }

                if let reviewMessage = organization.reviewMessage ?? organization.rejectionReason {
                    InlineMessageCard(style: .info, message: reviewMessage)
                }
            }
            .padding(AppTheme.pageHorizontal)
        }
        .background(AppBackgroundView())
        .navigationTitle(AppStrings.Profile.previewOrganizationRequest)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(AppStrings.Common.done) {
                    dismiss()
                }
            }
        }
    }

    private func previewSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: 10) {
                AppEditorSectionTitle(title: title)
                content()
            }
        }
    }

    @ViewBuilder
    private func previewRow(_ title: String, _ value: String?) -> some View {
        if let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct OrganizationRequestCard: View {
    let organization: Organization
    let previewAction: () -> Void
    let editAction: () -> Void

    private var canEdit: Bool {
        organization.moderationStatus == .needsRevision || organization.moderationStatus == .rejected
    }

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                HStack(alignment: .top, spacing: 12) {
                    AppFeedThumbnail(
                        imageURL: organization.imageURL,
                        fallbackSystemImage: "building.2",
                        tint: statusTint,
                        fill: statusTint.opacity(0.10),
                        size: 46,
                        source: "OrganizationRequestCard"
                    )

                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(organization.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                                .lineLimit(2)

                            statusBadge
                        }

                        Text(organization.shortDescription)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let reviewMessage = organization.reviewMessage ?? organization.rejectionReason {
                    InlineMessageCard(style: .info, message: reviewMessage)
                }

                if canEdit {
                    Button(action: editAction) {
                        Label(AppStrings.Action.edit, systemImage: "pencil")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.accentPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: previewAction) {
                        Label(AppStrings.Profile.previewOrganizationRequest, systemImage: "doc.text.magnifyingglass")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var statusBadge: some View {
        Text(statusTitle)
            .font(.caption2.weight(.bold))
            .foregroundStyle(statusTint)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(statusTint.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(statusTint.opacity(0.22)))
    }

    private var statusTitle: String {
        switch organization.moderationStatus {
        case .pendingReview:
            AppStrings.Common.pendingReview
        case .needsRevision:
            AppStrings.Common.needsRevision
        case .rejected:
            AppStrings.Common.rejected
        case .approved:
            AppStrings.Common.approved
        case .draft:
            AppStrings.Common.draft
        case .archived:
            AppStrings.Common.archived
        }
    }

    private var statusTint: Color {
        switch organization.moderationStatus {
        case .pendingReview:
            .orange
        case .needsRevision:
            AppTheme.accentPrimary
        case .rejected:
            AppTheme.accentDestructive
        default:
            AppTheme.textSecondary
        }
    }
}

private struct ManagedOrganizationCard: View {
    let organization: Organization
    let role: ManagedOrganizationRole
    @ObservedObject var organizationsViewModel: OrganizationsViewModel
    let contentStats: ManagedOrganizationContentStats?
    let isLoadingContentStats: Bool

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                HStack(alignment: .top, spacing: 12) {
                    AppFeedThumbnail(
                        imageURL: organization.imageURL,
                        fallbackSystemImage: "building.2",
                        tint: AppTheme.accentPrimary,
                        fill: AppTheme.accentPrimary.opacity(0.10),
                        size: 46,
                        source: "ManagedOrganizationCard"
                    )

                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(organization.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                                .lineLimit(2)

                            roleBadge
                        }

                        Text(organization.shortDescription)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(2)

                        metadataChips
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                statsRow

                HStack(spacing: AppTheme.eventsMetadataSpacing) {
                    NavigationLink {
                        OrganizationDetailView(
                            viewModel: organizationsViewModel,
                            organizationID: organization.id
                        )
                    } label: {
                        managedOrganizationActionLabel(title: AppStrings.Profile.organizationOpen, systemImage: "arrow.up.right")
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        ManagedOrganizationView(
                            organization: organization,
                            organizationsViewModel: organizationsViewModel
                        )
                    } label: {
                        managedOrganizationActionLabel(title: AppStrings.Profile.organizationManage, systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var roleBadge: some View {
        Text(role.title)
            .font(.caption2.weight(.bold))
            .foregroundStyle(role.tint)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(role.tint.opacity(0.12), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(role.tint.opacity(0.22))
            )
    }

    private var metadataChips: some View {
        AppHorizontalChipRow(spacing: 6) {
            AppInfoChip(
                title: regionText,
                systemImage: "mappin.and.ellipse",
                tint: AppTheme.textSecondary,
                fill: AppTheme.surfaceControl.opacity(0.62),
                size: .small
            )

            AppInfoChip(
                title: categoryText,
                systemImage: "building.2",
                tint: AppTheme.textSecondary,
                fill: AppTheme.surfaceControl.opacity(0.62),
                size: .small
            )
        }
    }

    private var statsRow: some View {
        HStack(spacing: 8) {
            managementStat(title: AppStrings.Profile.organizationStatSubscribers, value: "\(organization.subscriberCount)")
            managementStat(title: AppStrings.Profile.organizationStatNews, value: contentStatValue(contentStats?.newsCount))
            managementStat(title: AppStrings.Profile.organizationStatEvents, value: contentStatValue(contentStats?.eventCount))
        }
    }

    private func contentStatValue(_ value: Int?) -> String {
        guard let value else { return isLoadingContentStats ? "..." : "—" }
        return "\(value)"
    }

    private func managementStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)
                .monospacedDigit()

            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surfaceControl.opacity(0.32), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle.opacity(0.7))
        )
    }

    private func managedOrganizationActionLabel(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.accentPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(AppTheme.accentPrimary.opacity(0.18))
            )
    }

    @MainActor private var regionText: String {
        let region = organization.federalState.map(AppStrings.FederalStates.title(for:)) ?? organization.city
        if organization.city.isEmpty || organization.city == region {
            return region
        }
        return "\(organization.city), \(region)"
    }

    private var categoryText: String {
        guard let organizationType = organization.organizationType,
              let category = OrganizationEditorCategory(rawValue: organizationType) else {
            return AppStrings.Organizations.detailBadge
        }
        return category.title
    }
}

private enum OrganizationTeamRole: String, CaseIterable, Identifiable {
    case owner
    case admin
    case moderator
    case member

    var id: String { rawValue }

    var title: String {
        switch self {
        case .owner:
            AppStrings.Profile.organizationRoleOwner
        case .admin:
            AppStrings.Profile.organizationRoleAdmin
        case .moderator:
            AppStrings.Profile.organizationRoleModerator
        case .member:
            AppStrings.Profile.organizationRoleMember
        }
    }

    var tint: Color {
        switch self {
        case .owner:
            AppTheme.accentPrimary
        case .admin:
            Color.blue
        case .moderator:
            Color.orange
        case .member:
            AppTheme.textSecondary
        }
    }

    var communityRole: CommunityRole {
        switch self {
        case .owner:
            .communityOwner
        case .admin:
            .communityAdmin
        case .moderator:
            .communityModerator
        case .member:
            .member
        }
    }

    init?(_ role: CommunityRole) {
        switch role {
        case .communityOwner:
            self = .owner
        case .communityAdmin:
            self = .admin
        case .communityModerator:
            self = .moderator
        case .member:
            self = .member
        }
    }
}

private struct OrganizationTeamMember: Identifiable {
    let profile: PublicUserProfile?
    let userID: String
    let role: OrganizationTeamRole

    var id: String { userID }

    var displayName: String {
        profile?.preferredDisplayName ?? AppStrings.Profile.organizationTeamMissingProfile
    }

    @MainActor var locationText: String? {
        guard let profile else { return nil }
        let city = profile.city.trimmingCharacters(in: .whitespacesAndNewlines)
        let region = profile.federalState.map(AppStrings.FederalStates.title(for:))
        if city.isEmpty {
            return region
        }
        if let region, region != city {
            return "\(city), \(region)"
        }
        return city
    }

    var initials: String {
        guard let profile else { return "?" }
        let parts = profile.preferredDisplayName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let value = String(parts).uppercased()
        return value.isEmpty ? "?" : value
    }
}

private enum OrganizationTeamAction: Identifiable {
    case assign(member: OrganizationTeamMember, role: OrganizationTeamRole)
    case changeOwner(member: OrganizationTeamMember)
    case remove(member: OrganizationTeamMember)

    var id: String {
        switch self {
        case let .assign(member, role):
            "assign-\(member.userID)-\(role.rawValue)"
        case let .changeOwner(member):
            "change-owner-\(member.userID)"
        case let .remove(member):
            "remove-\(member.userID)-\(member.role.rawValue)"
        }
    }

    var title: String {
        switch self {
        case let .assign(member, role):
            AppStrings.profileOrganizationTeamAssignConfirmation(userName: member.displayName, role: role.title.lowercased())
        case let .changeOwner(member):
            AppStrings.profileOrganizationTeamChangeOwnerConfirmation(member.displayName)
        case let .remove(member):
            AppStrings.profileOrganizationTeamRemoveConfirmation(role: member.role.title.lowercased(), userName: member.displayName)
        }
    }

    var confirmTitle: String {
        switch self {
        case .assign:
            AppStrings.Profile.organizationTeamSaveRole
        case .changeOwner:
            AppStrings.Profile.organizationTeamChangeOwner
        case .remove:
            AppStrings.Profile.organizationTeamRemoveRole
        }
    }
}

@MainActor
private final class OrganizationTeamViewModel: ObservableObject {
    @Published private(set) var members: [OrganizationTeamMember] = []
    @Published private(set) var candidateMembers: [OrganizationTeamMember] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingCandidates = false
    @Published private(set) var updatingUserIDs = Set<String>()
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    private let database = Firestore.firestore()
    private let organizationRepository: OrganizationRepository = FirestoreOrganizationRepository()
    private var organizationsCollection: CollectionReference { database.collection("organizations") }
    private var auditCollection: CollectionReference { database.collection("auditLogs") }

    func load(organization: Organization) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let subscriberIDs = try await fetchSubscriberIDs(organizationID: organization.id)
            let teamIDs = Self.teamIDs(for: organization)
            let profiles = try await organizationRepository.fetchPublicUserProfiles(
                userIDs: Array(Set(teamIDs + subscriberIDs))
            )
            members = Self.makeMembers(
                organization: organization,
                profiles: profiles,
                subscriberIDs: subscriberIDs
            )
            statusMessage = nil
        } catch {
            members = []
            errorMessage = AppStrings.Profile.organizationTeamLoadFailed
        }
    }

    private func fetchSubscriberIDs(organizationID: String) async throws -> [String] {
        var cursor: OrganizationSubscriberCursor?
        var userIDs: [String] = []

        repeat {
            let page = try await organizationRepository.fetchOrganizationSubscriberPage(
                organizationID: organizationID,
                limit: 100,
                after: cursor
            )
            userIDs.append(contentsOf: page.items.map(\.userID))
            cursor = page.nextCursor
        } while cursor != nil

        return Array(NSOrderedSet(array: userIDs)) as? [String] ?? userIDs
    }

    func loadCandidateUsers(excluding organization: Organization, allowsExistingTeamMembers: Bool = false) async {
        isLoadingCandidates = true
        defer { isLoadingCandidates = false }

        if members.isEmpty {
            await load(organization: organization)
        }

        let excludedIDs: Set<String>
        if allowsExistingTeamMembers {
            excludedIDs = Set([organization.ownerId].compactMap { $0 }.filter { !$0.isEmpty })
        } else {
            excludedIDs = Set(Self.teamIDs(for: organization))
        }

        candidateMembers = members
            .filter { !excludedIDs.contains($0.userID) }
            .filter { allowsExistingTeamMembers || $0.role == .member }
    }

    func apply(
        _ action: OrganizationTeamAction,
        organization: Organization,
        actor: AppUser
    ) async -> Bool {
        guard PermissionService.canManageOrganizationRoles(organization, user: actor) else {
            errorMessage = AppStrings.Profile.organizationTeamPermissionDenied
            return false
        }

        switch action {
        case let .assign(member, role):
            return await assign(role, to: member, organization: organization, actor: actor)
        case let .changeOwner(member):
            return await changeOwner(to: member, organization: organization, actor: actor)
        case let .remove(member):
            return await remove(member, organization: organization, actor: actor)
        }
    }

    private func assign(
        _ role: OrganizationTeamRole,
        to target: OrganizationTeamMember,
        organization: Organization,
        actor: AppUser
    ) async -> Bool {
        let actorIsPlatformOwner = actor.globalRole.effectiveRole == .owner
        guard actorIsPlatformOwner || role != .owner else {
            errorMessage = AppStrings.Profile.organizationTeamOwnerCanAssignOnlyAdminModerator
            return false
        }

        return await update(targetUserID: target.userID, organization: organization) {
            try await updateRole(
                role: role.communityRole,
                organization: organization,
                targetUserID: target.userID,
                actor: actor,
                isRemoval: false
            )
        }
    }

    private func remove(
        _ member: OrganizationTeamMember,
        organization: Organization,
        actor: AppUser
    ) async -> Bool {
        let actorIsPlatformOwner = actor.globalRole.effectiveRole == .owner
        guard actorIsPlatformOwner || member.role != .owner else {
            errorMessage = AppStrings.Profile.organizationTeamOwnerCannotRemoveOwner
            return false
        }

        guard member.role != .owner else {
            errorMessage = AppStrings.Profile.organizationTeamCannotRemoveLastOwner
            return false
        }

        return await update(targetUserID: member.userID, organization: organization) {
            try await updateRole(
                role: .member,
                organization: organization,
                targetUserID: member.userID,
                actor: actor,
                isRemoval: true
            )
        }
    }

    private func changeOwner(
        to target: OrganizationTeamMember,
        organization: Organization,
        actor: AppUser
    ) async -> Bool {
        guard actor.globalRole.effectiveRole == .owner else {
            errorMessage = AppStrings.Profile.organizationTeamOwnerChangePlatformOnly
            return false
        }

        guard !target.userID.isEmpty else {
            errorMessage = AppStrings.Profile.organizationTeamUserProfileMissing
            return false
        }

        return await update(targetUserID: target.userID, organization: organization) {
            try await updateOwner(
                organization: organization,
                newOwnerID: target.userID,
                actor: actor
            )
        }
    }

    private func update(
        targetUserID: String,
        organization: Organization,
        operation: () async throws -> Void
    ) async -> Bool {
        guard !updatingUserIDs.contains(targetUserID) else { return false }
        updatingUserIDs.insert(targetUserID)
        errorMessage = nil
        statusMessage = nil
        defer { updatingUserIDs.remove(targetUserID) }

        do {
            try await operation()
            statusMessage = AppStrings.Profile.organizationTeamUpdated
            await load(organization: organization)
            return true
        } catch {
            errorMessage = AppStrings.Profile.organizationTeamSaveFailed
            return false
        }
    }

    private func updateRole(
        role: CommunityRole,
        organization: Organization,
        targetUserID: String,
        actor: AppUser,
        isRemoval: Bool
    ) async throws {
        let organizationReference = organizationsCollection.document(organization.id)
        let previousRole = Self.role(for: targetUserID, in: organization)
        let actorIsPlatformOwner = actor.globalRole.effectiveRole == .owner

        _ = try await database.runTransaction { transaction, errorPointer in
            do {
                let organizationSnapshot = try transaction.getDocument(organizationReference)
                guard let organizationData = organizationSnapshot.data() else {
                    errorPointer?.pointee = AppError.notFound.asNSError
                    return nil
                }

                let currentOwnerId = organizationData["ownerId"] as? String
                let currentAdminIds = organizationData["adminIds"] as? [String] ?? []
                let currentModeratorIds = organizationData["moderatorIds"] as? [String] ?? []

                if isRemoval, currentOwnerId == targetUserID {
                    errorPointer?.pointee = AppError.permissionDenied.asNSError
                    return nil
                }

                if !isRemoval, currentOwnerId == targetUserID, role != .communityOwner {
                    errorPointer?.pointee = AppError.permissionDenied.asNSError
                    return nil
                }

                if !actorIsPlatformOwner, role == .communityOwner {
                    errorPointer?.pointee = AppError.permissionDenied.asNSError
                    return nil
                }

                let updatedAdminIds = currentAdminIds.filter { $0 != targetUserID }
                let updatedModeratorIds = currentModeratorIds.filter { $0 != targetUserID }
                var organizationUpdate: [String: Any] = [
                    "adminIds": updatedAdminIds,
                    "moderatorIds": updatedModeratorIds,
                    "updatedAt": FieldValue.serverTimestamp()
                ]

                if !isRemoval {
                    switch role {
                    case .communityOwner:
                        organizationUpdate["ownerId"] = targetUserID
                    case .communityAdmin:
                        organizationUpdate["adminIds"] = Array(Set(updatedAdminIds + [targetUserID])).sorted()
                    case .communityModerator:
                        organizationUpdate["moderatorIds"] = Array(Set(updatedModeratorIds + [targetUserID])).sorted()
                    case .member:
                        break
                    }
                }

                transaction.updateData(organizationUpdate, forDocument: organizationReference)

                transaction.setData([
                    "actionType": isRemoval ? "organizationRoleRemoved" : "organizationRoleAssigned",
                    "targetUserId": targetUserID,
                    "performedBy": actor.id,
                    "createdAt": FieldValue.serverTimestamp(),
                    "reason": "Organization management hub",
                    "note": NSNull(),
                    "previousValue": [
                        "organizationId": organization.id,
                        "role": previousRole?.rawValue ?? "none"
                    ],
                    "newValue": [
                        "organizationId": organization.id,
                        "role": isRemoval ? "none" : role.rawValue
                    ]
                ], forDocument: self.auditCollection.document())
            } catch {
                errorPointer?.pointee = error as NSError
            }

            return nil
        }
    }

    private func updateOwner(
        organization: Organization,
        newOwnerID: String,
        actor: AppUser
    ) async throws {
        let organizationReference = organizationsCollection.document(organization.id)

        _ = try await database.runTransaction { transaction, errorPointer in
            do {
                let organizationSnapshot = try transaction.getDocument(organizationReference)
                guard let organizationData = organizationSnapshot.data() else {
                    errorPointer?.pointee = AppError.notFound.asNSError
                    return nil
                }

                let currentOwnerId = organizationData["ownerId"] as? String
                let currentAdminIds = organizationData["adminIds"] as? [String] ?? []
                let currentModeratorIds = organizationData["moderatorIds"] as? [String] ?? []
                let oldOwnerId = currentOwnerId ?? ""

                guard actor.globalRole.effectiveRole == .owner, !newOwnerID.isEmpty else {
                    errorPointer?.pointee = AppError.permissionDenied.asNSError
                    return nil
                }

                transaction.updateData([
                    "ownerId": newOwnerID,
                    "adminIds": currentAdminIds.filter { $0 != newOwnerID && $0 != oldOwnerId },
                    "moderatorIds": currentModeratorIds.filter { $0 != newOwnerID && $0 != oldOwnerId },
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: organizationReference)

                transaction.setData([
                    "actionType": "organizationOwnerChanged",
                    "targetUserId": newOwnerID,
                    "performedBy": actor.id,
                    "createdAt": FieldValue.serverTimestamp(),
                    "reason": "Organization management hub",
                    "note": NSNull(),
                    "previousValue": [
                        "organizationId": organization.id,
                        "ownerId": currentOwnerId ?? "none"
                    ],
                    "newValue": [
                        "organizationId": organization.id,
                        "ownerId": newOwnerID
                    ]
                ], forDocument: self.auditCollection.document())
            } catch {
                errorPointer?.pointee = error as NSError
            }

            return nil
        }
    }

    private static func teamIDs(for organization: Organization) -> [String] {
        var orderedIDs: [String] = []
        if let ownerId = organization.ownerId, !ownerId.isEmpty {
            orderedIDs.append(ownerId)
        }
        orderedIDs.append(contentsOf: organization.adminIds)
        orderedIDs.append(contentsOf: organization.moderatorIds)
        return Array(NSOrderedSet(array: orderedIDs)) as? [String] ?? orderedIDs
    }

    private static func makeMembers(
        organization: Organization,
        profiles: [PublicUserProfile],
        subscriberIDs: [String]
    ) -> [OrganizationTeamMember] {
        let profilesByID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        var result: [OrganizationTeamMember] = []
        var renderedUserIDs = Set<String>()

        if let ownerId = organization.ownerId, !ownerId.isEmpty {
            result.append(OrganizationTeamMember(profile: profilesByID[ownerId], userID: ownerId, role: .owner))
            renderedUserIDs.insert(ownerId)
        }

        for userID in organization.adminIds where !renderedUserIDs.contains(userID) {
            result.append(OrganizationTeamMember(profile: profilesByID[userID], userID: userID, role: .admin))
            renderedUserIDs.insert(userID)
        }

        for userID in organization.moderatorIds where !renderedUserIDs.contains(userID) {
            result.append(OrganizationTeamMember(profile: profilesByID[userID], userID: userID, role: .moderator))
            renderedUserIDs.insert(userID)
        }

        for userID in subscriberIDs where !renderedUserIDs.contains(userID) {
            result.append(OrganizationTeamMember(profile: profilesByID[userID], userID: userID, role: .member))
            renderedUserIDs.insert(userID)
        }

        return result
    }

    private static func role(for userID: String, in organization: Organization) -> CommunityRole? {
        if organization.ownerId == userID { return .communityOwner }
        if organization.adminIds.contains(userID) { return .communityAdmin }
        if organization.moderatorIds.contains(userID) { return .communityModerator }
        return nil
    }
}

private struct OrganizationTeamMemberRow: View {
    let member: OrganizationTeamMember
    let canManage: Bool
    let canChangeRole: Bool
    let availableRoles: [OrganizationTeamRole]
    let isUpdating: Bool
    let onAssignRole: (OrganizationTeamRole) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            TeamAvatarView(profile: member.profile, fallbackInitials: member.initials)

            VStack(alignment: .leading, spacing: 4) {
                Text(member.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                if let locationText = member.locationText {
                    Text(locationText)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                } else if member.profile == nil {
                    Text(member.userID)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            roleBadge

            if isUpdating {
                ProgressView()
                    .controlSize(.small)
            } else if canManage {
                Menu {
                    if canChangeRole {
                        ForEach(availableRoles) { role in
                            Button(AppStrings.profileOrganizationTeamMakeRole(role.title.lowercased())) {
                                onAssignRole(role)
                            }
                        }

                        if member.role != .member {
                            Button(AppStrings.Profile.organizationTeamRemoveRole, role: .destructive) {
                                onRemove()
                            }
                        }
                    } else {
                        Text(AppStrings.Profile.organizationTeamUnavailable)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(canChangeRole ? AppTheme.accentPrimary : AppTheme.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(AppTheme.surfaceControl.opacity(0.55), in: Circle())
                }
                .disabled(!canChangeRole)
                .accessibilityLabel(AppStrings.Profile.organizationTeamRoleActions)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle.opacity(0.55))
        )
    }

    private var roleBadge: some View {
        Text(member.role.title)
            .font(.caption2.weight(.bold))
            .foregroundStyle(member.role.tint)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(member.role.tint.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(member.role.tint.opacity(0.22)))
    }

}

private struct OrganizationTeamCandidateRow: View {
    let member: OrganizationTeamMember
    let role: OrganizationTeamRole?
    let isOwnerTransfer: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            TeamAvatarView(profile: member.profile, fallbackInitials: member.initials)

            VStack(alignment: .leading, spacing: 4) {
                Text(member.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                VStack(alignment: .leading, spacing: 2) {
                    if let locationText = member.locationText {
                        Text(locationText)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)
                    }

                    if let role {
                        Text(role.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(role.tint)
                    } else if isOwnerTransfer {
                        Text(AppStrings.Profile.organizationTeamNoCurrentRole)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: isOwnerTransfer ? "person.crop.circle.badge.checkmark" : "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(AppTheme.accentPrimary)
        }
        .padding(.vertical, 4)
    }
}

private struct TeamAvatarView: View {
    let profile: PublicUserProfile?
    let fallbackInitials: String

    init(profile: PublicUserProfile?, fallbackInitials: String? = nil) {
        self.profile = profile
        self.fallbackInitials = fallbackInitials ?? "?"
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(AppTheme.accentPrimarySoft)

            if let avatarURL = profile?.avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        initials
                    }
                }
            } else {
                initials
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(Circle())
    }

    private var initials: some View {
        Text(fallbackInitials)
            .font(.caption.weight(.bold))
            .foregroundStyle(AppTheme.accentPrimary)
    }
}

private struct ManagementPill: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(tint.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.22)))
    }
}

private struct OrganizationManagementRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    var isEnabled = true

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.12), in: Circle())
                .overlay(Circle().strokeBorder(tint.opacity(0.18)))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isEnabled ? AppTheme.textPrimary : AppTheme.textSecondary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.textSecondary.opacity(isEnabled ? 0.75 : 0.35))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 66)
        .background(AppTheme.surfaceSecondary.opacity(isEnabled ? 1 : 0.62), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle.opacity(0.55))
        )
    }
}

private struct ManagedOrganizationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authState: AuthState

    let organization: Organization
    @ObservedObject var organizationsViewModel: OrganizationsViewModel

    @StateObject private var teamViewModel = OrganizationTeamViewModel()
    @State private var isShowingNewsEditor = false
    @State private var isShowingEventEditor = false
    @State private var isShowingOrganizationEditor = false
    @State private var isShowingTeamSearch = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isDeletingOrganization = false
    @State private var deleteErrorMessage: String?
    @State private var pendingTeamAction: OrganizationTeamAction?
    @State private var selectedTeamRole: OrganizationTeamRole = .moderator
    @State private var teamSearchText = ""
    @State private var isChangingOwner = false

    private var currentOrganization: Organization {
        organizationsViewModel.organization(for: organization.id) ?? organization
    }

    private var canCreateNews: Bool {
        PermissionService.canCreateOrganizationNews(currentOrganization, user: authState.user)
    }

    private var canCreateEvent: Bool {
        PermissionService.canCreateOrganizationEvent(currentOrganization, user: authState.user)
    }

    private var canEditOrganization: Bool {
        PermissionService.canEditOrganizationInfo(currentOrganization, user: authState.user)
    }

    private var canManageTeam: Bool {
        PermissionService.canManageOrganizationRoles(currentOrganization, user: authState.user)
    }

    private var canManagePhotos: Bool {
        PermissionService.canModerateOrganizationContent(currentOrganization, user: authState.user)
    }

    private var canDeleteOrganization: Bool {
        PermissionService.canDeleteOrganization(currentOrganization, user: authState.user)
    }

    var body: some View {
        ProfileDestinationLayout(
            title: currentOrganization.name,
            introSubtitle: AppStrings.Profile.organizationManagementSubtitle
        ) {
            organizationSummaryCard
            managementHubCard
            contactSectionCard
            teamSectionCard
            photoSectionCard
        }
        .navigationTitle(currentOrganization.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingNewsEditor) {
            NavigationStack {
                NewsEditorView(
                    repository: FirestoreNewsRepository(),
                    organizationId: currentOrganization.id,
                    organizationName: currentOrganization.name,
                    organizationImageURL: currentOrganization.imageURL,
                    organizationFederalState: currentOrganization.federalState
                )
            }
        }
        .sheet(isPresented: $isShowingEventEditor) {
            NavigationStack {
                EventEditorView(
                    repository: FirestoreEventRepository(),
                    organizationId: currentOrganization.id,
                    organizationName: currentOrganization.name,
                    organizationImageURL: currentOrganization.imageURL,
                    organizationFederalState: currentOrganization.federalState
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
        .task(id: currentOrganization.id) {
            await teamViewModel.load(organization: currentOrganization)
        }
        .sheet(isPresented: $isShowingTeamSearch) {
            NavigationStack {
                teamSearchSheet
                    .navigationTitle(isChangingOwner ? AppStrings.Profile.organizationTeamChangeOwner : AppStrings.Profile.organizationTeamAddMember)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(AppStrings.Organizations.cancel) {
                                isShowingTeamSearch = false
                            }
                        }
                    }
            }
            .task(id: isChangingOwner) {
                await teamViewModel.loadCandidateUsers(
                    excluding: currentOrganization,
                    allowsExistingTeamMembers: isChangingOwner
                )
            }
        }
        .confirmationDialog(
            pendingTeamAction?.title ?? "",
            isPresented: Binding(
                get: { pendingTeamAction != nil },
                set: { if !$0 { pendingTeamAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingTeamAction {
                Button(pendingTeamAction.confirmTitle, role: destructiveRole(for: pendingTeamAction)) {
                    Task {
                        await performTeamAction(pendingTeamAction)
                    }
                }
            }

            Button(AppStrings.Organizations.cancel, role: .cancel) {
                pendingTeamAction = nil
            }
        }
    }

    private var organizationSummaryCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                HStack(alignment: .top, spacing: 12) {
                    AppFeedThumbnail(
                        imageURL: currentOrganization.imageURL,
                        fallbackSystemImage: "building.2",
                        tint: AppTheme.accentPrimary,
                        fill: AppTheme.accentPrimary.opacity(0.10),
                        size: 52,
                        source: "ManagedOrganizationView"
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text(currentOrganization.name)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(2)

                        HStack(spacing: 6) {
                            if let role = currentManagementRole {
                                ManagementPill(title: role.title, tint: role.tint)
                            }

                            ManagementPill(
                                title: currentOrganization.moderationStatus.title,
                                tint: currentOrganization.moderationStatus == .approved ? AppTheme.accentPrimary : AppTheme.textSecondary
                            )
                        }

                        Text(currentOrganization.shortDescription)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 8) {
                    MetadataRow(label: AppStrings.Common.city, value: currentOrganization.city, systemImage: "mappin.and.ellipse")

                    if let contactEmail = currentOrganization.contactEmail, !contactEmail.isEmpty {
                        MetadataRow(label: AppStrings.Common.contact, value: contactEmail, systemImage: "envelope")
                    }

                    if let website = currentOrganization.website, !website.isEmpty {
                        MetadataRow(label: AppStrings.Common.website, value: website, systemImage: "link")
                    }
                }
            }
        }
    }

    private var currentManagementRole: ManagedOrganizationRole? {
        guard let user = authState.user else { return nil }
        if currentOrganization.ownerId == user.id {
            return .owner
        }
        if user.globalRole.effectiveRole == .owner {
            return .platformOwner
        }
        if currentOrganization.adminIds.contains(user.id) {
            return .admin
        }
        if currentOrganization.moderatorIds.contains(user.id) {
            return .moderator
        }
        return nil
    }

    private var managementHubCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                AppEditorSectionTitle(title: AppStrings.Profile.organizationManagement)

                if canEditOrganization {
                    managementHubButton(
                        title: AppStrings.Profile.organizationInfoSection,
                        subtitle: AppStrings.Organizations.editorSubtitle,
                        systemImage: "building.2"
                    ) {
                        isShowingOrganizationEditor = true
                    }
                } else {
                    disabledManagementHubRow(
                        title: AppStrings.Profile.organizationInfoSection,
                        subtitle: AppStrings.Profile.organizationInfoLockedSubtitle,
                        systemImage: "building.2"
                    )
                }

                if canCreateNews {
                    managementHubButton(
                        title: AppStrings.News.title,
                        subtitle: AppStrings.Profile.organizationNewsActionSubtitle,
                        systemImage: "newspaper"
                    ) {
                        isShowingNewsEditor = true
                    }
                }

                if canCreateEvent {
                    managementHubButton(
                        title: AppStrings.Events.title,
                        subtitle: AppStrings.Profile.organizationEventActionSubtitle,
                        systemImage: "calendar.badge.plus"
                    ) {
                        isShowingEventEditor = true
                    }
                }

                if canDeleteOrganization {
                    managementHubButton(
                        title: AppStrings.Organizations.delete,
                        subtitle: AppStrings.Organizations.deleteConfirmation,
                        systemImage: "trash.fill",
                        role: .destructive
                    ) {
                        isShowingDeleteConfirmation = true
                    }
                    .disabled(isDeletingOrganization)
                }
            }
        }
    }

    private var contactSectionCard: some View {
        OrganizationContactCard(
            organization: currentOrganization,
            allowsEditing: canEditOrganization,
            showsManagementActions: true,
            onEdit: canEditOrganization ? { isShowingOrganizationEditor = true } : nil
        )
    }

    private var photoSectionCard: some View {
        OrganizationPhotoGallerySection(
            organizationId: currentOrganization.id,
            canManage: canManagePhotos,
            currentUser: authState.user
        )
    }

    private var teamSectionCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                HStack(alignment: .center) {
                    AppEditorSectionTitle(title: AppStrings.Profile.organizationTeamSection)

                    if canManageTeam {
                        HStack(spacing: 8) {
                            if isPlatformOwner {
                                Button {
                                    teamSearchText = ""
                                    selectedTeamRole = .owner
                                    isChangingOwner = true
                                    isShowingTeamSearch = true
                                } label: {
                                    managementCompactActionLabel(
                                        title: AppStrings.Profile.organizationTeamChangeOwner,
                                        systemImage: "person.crop.circle.badge.checkmark"
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            Button {
                                teamSearchText = ""
                                selectedTeamRole = .moderator
                                isChangingOwner = false
                                isShowingTeamSearch = true
                            } label: {
                                managementCompactActionLabel(
                                    title: AppStrings.Profile.organizationTeamAddMember,
                                    systemImage: "plus"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if isPlatformOwner {
                    Text(AppStrings.Profile.organizationTeamOwnerRequiredExplanation)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                if teamViewModel.isLoading && teamViewModel.members.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, AppTheme.dashboardSpacing)
                } else if teamViewModel.members.isEmpty {
                    compactTeamEmptyState
                } else {
                    VStack(spacing: 8) {
                        ForEach(teamViewModel.members) { member in
                            OrganizationTeamMemberRow(
                                member: member,
                                canManage: canManageTeam,
                                canChangeRole: canChangeRole(for: member),
                                availableRoles: availableRoles(for: member),
                                isUpdating: teamViewModel.updatingUserIDs.contains(member.userID),
                                onAssignRole: { role in
                                    pendingTeamAction = .assign(member: member, role: role)
                                },
                                onRemove: {
                                    pendingTeamAction = .remove(member: member)
                                }
                            )
                        }
                    }
                }

                if let statusMessage = teamViewModel.statusMessage {
                    Label(statusMessage, systemImage: "checkmark.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.accentPrimary)
                }

                if let errorMessage = teamViewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.accentDestructive)
                }
            }
        }
    }

    private var compactTeamEmptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(AppStrings.Profile.organizationTeamEmptyTitle, systemImage: "person.2")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)

            Text(AppStrings.Profile.organizationTeamEmptyMessage)
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var teamSearchSheet: some View {
        List {
            Section {
                TextField(AppStrings.Profile.organizationTeamSearchPlaceholder, text: $teamSearchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if isChangingOwner {
                    Text(AppStrings.Profile.organizationTeamOwnerRequiredExplanation)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    Picker(AppStrings.Profile.organizationTeamRolePicker, selection: $selectedTeamRole) {
                        ForEach(addMemberAssignableRoles) { role in
                            Text(role.title).tag(role)
                        }
                    }
                }
            }

            Section {
                Text(AppStrings.Profile.organizationTeamSubscribeToAssign)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)

                if teamViewModel.isLoadingCandidates {
                    ProgressView()
                } else if filteredTeamCandidateMembers.isEmpty {
                    Text(AppStrings.Profile.organizationTeamNoUsers)
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    ForEach(filteredTeamCandidateMembers) { member in
                        Button {
                            pendingTeamAction = isChangingOwner
                                ? .changeOwner(member: member)
                                : .assign(member: member, role: selectedTeamRole)
                            isShowingTeamSearch = false
                        } label: {
                            OrganizationTeamCandidateRow(
                                member: member,
                                role: teamRole(for: member),
                                isOwnerTransfer: isChangingOwner
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var filteredTeamCandidateMembers: [OrganizationTeamMember] {
        let query = teamSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return teamViewModel.candidateMembers }

        return teamViewModel.candidateMembers.filter { member in
            member.displayName.lowercased().contains(query)
                || member.userID.lowercased().contains(query)
                || (member.locationText?.lowercased().contains(query) ?? false)
        }
    }

    private var availableAssignableRoles: [OrganizationTeamRole] {
        guard let user = authState.user else { return [] }
        if user.globalRole.effectiveRole == .owner {
            return [.owner, .admin, .moderator]
        }
        return [.admin, .moderator]
    }

    private var addMemberAssignableRoles: [OrganizationTeamRole] {
        availableAssignableRoles.filter { $0 != .owner }
    }

    private var roleManagementAssignableRoles: [OrganizationTeamRole] {
        availableAssignableRoles.filter { $0 != .owner }
    }

    private var isPlatformOwner: Bool {
        authState.user?.globalRole.effectiveRole == .owner
    }

    private func teamRole(for member: OrganizationTeamMember) -> OrganizationTeamRole? {
        if currentOrganization.ownerId == member.userID {
            return .owner
        }
        if currentOrganization.adminIds.contains(member.userID) {
            return .admin
        }
        if currentOrganization.moderatorIds.contains(member.userID) {
            return .moderator
        }
        return .member
    }

    private func availableRoles(for member: OrganizationTeamMember) -> [OrganizationTeamRole] {
        roleManagementAssignableRoles.filter { $0 != member.role }
    }

    private func canChangeRole(for member: OrganizationTeamMember) -> Bool {
        guard canManageTeam else { return false }
        guard let user = authState.user else { return false }
        if user.globalRole.effectiveRole == .owner {
            return member.role != .owner
        }
        return member.role != .owner && member.userID != user.id
    }

    private func destructiveRole(for action: OrganizationTeamAction) -> ButtonRole? {
        switch action {
        case .assign, .changeOwner:
            nil
        case .remove:
            .destructive
        }
    }

    @MainActor
    private func performTeamAction(_ action: OrganizationTeamAction) async {
        guard let actor = authState.user else {
            pendingTeamAction = nil
            return
        }

        let didUpdate = await teamViewModel.apply(action, organization: currentOrganization, actor: actor)
        pendingTeamAction = nil

        guard didUpdate else { return }
        await organizationsViewModel.refresh()
        let refreshedOrganization = organizationsViewModel.organization(for: currentOrganization.id) ?? currentOrganization
        await teamViewModel.load(organization: refreshedOrganization)

        switch action {
        case let .assign(member, _):
            if member.userID == actor.id {
                await authState.loadUser(uid: actor.id)
            }
        case let .changeOwner(member):
            if member.userID == actor.id || currentOrganization.ownerId == actor.id {
                await authState.loadUser(uid: actor.id)
            }
        case let .remove(member):
            if member.userID == actor.id {
                await authState.loadUser(uid: actor.id)
            }
        }
    }

    private func managementHubButton(
        title: String,
        subtitle: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            OrganizationManagementRow(
                title: title,
                subtitle: subtitle,
                systemImage: systemImage,
                tint: role == .destructive ? AppTheme.accentDestructive : AppTheme.accentPrimary
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func disabledManagementHubRow(title: String, subtitle: String, systemImage: String) -> some View {
        OrganizationManagementRow(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            tint: AppTheme.textSecondary,
            isEnabled: false
        )
        .accessibilityHint(AppStrings.Action.comingSoon)
    }

    private func managementCompactActionLabel(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.accentPrimary)
            .labelStyle(.iconOnly)
            .frame(width: 34, height: 34)
            .background(AppTheme.accentPrimarySoft, in: Circle())
            .overlay(Circle().strokeBorder(AppTheme.accentPrimary.opacity(0.16)))
            .accessibilityLabel(title)
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
            feedbackRepository: MockFeedbackRepository(),
            eventRepository: MockEventRepository()
        )
    }
    .environmentObject(AuthState())
}
