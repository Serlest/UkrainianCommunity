import PhotosUI
import SwiftUI

private let profileRootScrollTopID = "profileRootScrollTop"

enum ProfileNavigationRoute: Hashable {
    case organizationManagement
    case registrations
    case savedContent
    case followedOrganizations
    case recentViews
    case activityHistory
    case profileSettings
    case feedbackComposer
    case supportProject
    case blockedUsers
    case organizationRequests
    case moderationTools
    case userManagement
    case featuredBannerManagement
    case legalDocumentManagement
    case legalEvidence
    case ownerAnalytics
    case donationSettings
    case feedbackInbox
    case systemLogs(SystemLogsAccessMode)
    case notifications
    case myFeedback(userID: String)
    case dsaStatement(statementID: String)
    case legal(LegalDocumentKind)
}

enum ProfileBrowseDestination {
    case home
    case events
    case organizations
}

struct ProfileView: View {
    @ObservedObject var viewModel: ProfileViewModel
    private let feedbackRepository: FeedbackRepository
    private let newsRepository: NewsRepository
    private let eventRepository: EventRepository
    private let organizationRepository: OrganizationRepository
    private let featuredBannerRepository: FeaturedBannerRepository
    private let featuredBannerCache: FeaturedBannerCache
    private let legalDocumentRepository: LegalDocumentRepository
    private let ownerAnalyticsRepository: OwnerAnalyticsRepository
    private let analyticsService: AnalyticsTracking
    private let donationConfigRepository: DonationConfigRepository
    private let notificationInboxRepository: NotificationInboxRepository
    @ObservedObject private var userBlockingCoordinator: UserBlockingCoordinator
    private let onNotificationTap: (AppNotification) -> Void
    private let onBrowseDestinationSelected: (ProfileBrowseDestination) -> Void
    @EnvironmentObject var authState: AuthState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @StateObject private var registrationsViewModel: MyRegistrationsViewModel
    @StateObject private var myFeedbackViewModel: MyFeedbackViewModel
    @StateObject private var recentViewsViewModel: RecentViewsViewModel
    @StateObject private var activityLogViewModel: ActivityLogViewModel
    @StateObject private var ownerVisibilityViewModel: OwnerProfileVisibilityViewModel
    @StateObject private var donationConfigViewModel: DonationConfigViewModel
    @ObservedObject private var notificationInboxViewModel: NotificationInboxViewModel
    @ObservedObject private var newsViewModel: NewsViewModel
    @ObservedObject private var eventsViewModel: EventsViewModel
    @ObservedObject private var organizationsViewModel: OrganizationsViewModel
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
    @State private var cropSourceAvatarImage: UIImage?
    @State private var isShowingAvatarCrop = false
    @State private var ignoresNextAvatarPhotoClear = false
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
    @State private var isAnalyticsCollectionEnabled: Bool
    @Binding var navigationPath: [ProfileNavigationRoute]
    let scrollResetToken: Int

    init(
        viewModel: ProfileViewModel,
        feedbackRepository: FeedbackRepository = FirestoreFeedbackRepository(),
        newsRepository: NewsRepository = FirestoreNewsRepository(),
        eventRepository: EventRepository,
        organizationRepository: OrganizationRepository = FirestoreOrganizationRepository(),
        newsViewModel: NewsViewModel? = nil,
        eventsViewModel: EventsViewModel? = nil,
        organizationsViewModel: OrganizationsViewModel? = nil,
        featuredBannerRepository: FeaturedBannerRepository = FirestoreFeaturedBannerRepository(),
        featuredBannerCache: FeaturedBannerCache = FeaturedBannerCache(),
        legalDocumentRepository: LegalDocumentRepository = FirestoreLegalDocumentRepository(),
        ownerAnalyticsRepository: OwnerAnalyticsRepository = FirestoreOwnerAnalyticsRepository(),
        analyticsService: AnalyticsTracking = NoopAnalyticsService(),
        donationConfigRepository: DonationConfigRepository = FirestoreDonationConfigRepository(),
        notificationInboxRepository: NotificationInboxRepository = FirestoreNotificationInboxRepository(),
        notificationInboxViewModel: NotificationInboxViewModel? = nil,
        userBlockingCoordinator: UserBlockingCoordinator,
        localEventReminderService: LocalEventReminderServiceProtocol = LocalEventReminderService(),
        onNotificationTap: @escaping (AppNotification) -> Void = { _ in },
        onBrowseDestinationSelected: @escaping (ProfileBrowseDestination) -> Void = { _ in },
        navigationPath: Binding<[ProfileNavigationRoute]> = .constant([]),
        scrollResetToken: Int = 0
    ) {
        self.viewModel = viewModel
        self.feedbackRepository = feedbackRepository
        self.newsRepository = newsRepository
        self.eventRepository = eventRepository
        self.organizationRepository = organizationRepository
        self.newsViewModel = newsViewModel ?? NewsViewModel(repository: newsRepository)
        self.eventsViewModel = eventsViewModel ?? EventsViewModel(
            repository: eventRepository,
            localEventReminderService: localEventReminderService
        )
        self.organizationsViewModel = organizationsViewModel ?? OrganizationsViewModel(repository: organizationRepository)
        self.featuredBannerRepository = featuredBannerRepository
        self.featuredBannerCache = featuredBannerCache
        self.legalDocumentRepository = legalDocumentRepository
        self.ownerAnalyticsRepository = ownerAnalyticsRepository
        self.analyticsService = analyticsService
        self.donationConfigRepository = donationConfigRepository
        self.notificationInboxRepository = notificationInboxRepository
        self.notificationInboxViewModel = notificationInboxViewModel ?? NotificationInboxViewModel(
            repository: notificationInboxRepository
        )
        self.userBlockingCoordinator = userBlockingCoordinator
        self.onNotificationTap = onNotificationTap
        self.onBrowseDestinationSelected = onBrowseDestinationSelected
        self.scrollResetToken = scrollResetToken
        _isAnalyticsCollectionEnabled = State(initialValue: analyticsService.isCollectionEnabled)
        _navigationPath = navigationPath
        _registrationsViewModel = StateObject(wrappedValue: MyRegistrationsViewModel(
            repository: eventRepository,
            localEventReminderService: localEventReminderService
        ))
        _myFeedbackViewModel = StateObject(wrappedValue: MyFeedbackViewModel(repository: feedbackRepository))
        _recentViewsViewModel = StateObject(wrappedValue: RecentViewsViewModel(repository: FirestoreRecentViewsRepository()))
        _activityLogViewModel = StateObject(wrappedValue: ActivityLogViewModel(repository: FirestoreActivityLogRepository()))
        _ownerVisibilityViewModel = StateObject(wrappedValue: OwnerProfileVisibilityViewModel(
            feedbackRepository: feedbackRepository,
            organizationRepository: organizationRepository
        ))
        _donationConfigViewModel = StateObject(wrappedValue: DonationConfigViewModel(
            repository: donationConfigRepository
        ))
    }

    private var permissionUser: AppUser? {
        authState.user
    }

    private var appLanguage: AppLanguage {
        DonationLocalization.language(from: locale)
    }

    private var canShowAdminTools: Bool {
        PermissionService.canAccessAdminTools(user: permissionUser)
    }

    private var canShowModerationTools: Bool {
        PermissionService.canAccessModerationTools(user: permissionUser)
    }

    private var canShowOrganizationRequests: Bool {
        PermissionService.canManageOrganizationRequests(user: permissionUser)
    }

    private var canShowFeedbackReports: Bool {
        PermissionService.canManageFeedback(user: permissionUser)
            || PermissionService.canManageReports(user: permissionUser)
    }

    private var canShowFeaturedBanners: Bool {
        PermissionService.canManageFeaturedBanners(user: permissionUser)
    }

    private var canShowOrganizationManagement: Bool {
        guard let user = permissionUser else { return false }
        if PermissionService.canManageOrganizations(user: user) {
            return true
        }
        if PermissionService.canCreateOrganization(user: user) {
            return true
        }
        if !PermissionService.manageableOrganizations(
            from: organizationsViewModel.organizations,
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

    private var shouldLoadOwnerVisibility: Bool {
        canShowOrganizationRequests || canShowFeedbackReports
    }

    private func loadOwnerVisibilityIfAllowed() async {
        guard shouldLoadOwnerVisibility else {
            ownerVisibilityViewModel.reset()
            return
        }

        await ownerVisibilityViewModel.loadIfNeeded(
            includeOrganizationRequests: canShowOrganizationRequests,
            includeFeedback: canShowFeedbackReports
        )
    }

    private func refreshOwnerVisibilityIfAllowed() async {
        guard shouldLoadOwnerVisibility else {
            ownerVisibilityViewModel.reset()
            return
        }

        await ownerVisibilityViewModel.refresh(
            includeOrganizationRequests: canShowOrganizationRequests,
            includeFeedback: canShowFeedbackReports
        )
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

    var body: some View {
        ZStack {
            AppBackgroundView()
                .allowsHitTesting(false)

            GeometryReader { proxy in
                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        Color.clear
                            .frame(height: 0)
                            .id(profileRootScrollTopID)

                        VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                            profileHeader

                            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                                if let user = displayUser {
                                    userProfileContent(for: user)
                                } else {
                                    guestProfileContent
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, AppTheme.pageHorizontal)
                        .padding(.bottom, AppTheme.homeBottomContentPadding + 32)
                        .appCenteredContent(maxWidth: AppTheme.feedContentMaxWidth)
                    }
                    .frame(width: proxy.size.width)
                    .onChange(of: scrollResetToken) {
                        scrollToTop(with: scrollProxy)
                    }
                }
            }
        }
        .tint(AppTheme.accentPrimary)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: ProfileNavigationRoute.self) { route in
            profileDestination(for: route)
                .id(locale.identifier)
        }
        .task {
            isAnalyticsCollectionEnabled = analyticsService.isCollectionEnabled
            await viewModel.loadIfNeeded()
            await donationConfigViewModel.loadIfNeeded()
            if authState.isAuthenticated {
                await registrationsViewModel.loadIfNeeded()
                await registrationsViewModel.refreshIfStale()
                if let userID = authState.user?.id {
                    await myFeedbackViewModel.loadIfNeeded(userID: userID)
                    await viewModel.loadNotificationPreferencesIfNeeded(userID: userID)
                }
                await organizationsViewModel.loadIfNeeded()
                await organizationsViewModel.refreshIfStale()
                await loadOwnerVisibilityIfAllowed()
            } else {
                registrationsViewModel.resetForGuest()
                myFeedbackViewModel.reset()
                ownerVisibilityViewModel.reset()
            }
        }
        .onChange(of: authState.user?.id) {
            // Consent is scoped to the active principal. Never leave the
            // previous account's switch value visible after an account change.
            isAnalyticsCollectionEnabled = analyticsService.isCollectionEnabled
        }
        .refreshable {
            await viewModel.refresh()
            await donationConfigViewModel.load()
            if authState.isAuthenticated {
                await registrationsViewModel.refresh()
                if let userID = authState.user?.id {
                    await myFeedbackViewModel.refresh(userID: userID)
                    await notificationInboxViewModel.refresh()
                    await viewModel.refreshNotificationPreferences(userID: userID)
                }
                await organizationsViewModel.refresh()
                await refreshOwnerVisibilityIfAllowed()
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
                    await organizationsViewModel.refresh()
                    await refreshOwnerVisibilityIfAllowed()
                } else {
                    registrationsViewModel.resetForGuest()
                    myFeedbackViewModel.reset()
                    ownerVisibilityViewModel.reset()
                    feedbackMessage = ""
                    selectedFeedbackType = .question
                }
            }
        }
        .onChange(of: authState.user?.id) { _, newUserID in
            viewModel.clearFeedbackSuccessMessage()
            Task {
                registrationsViewModel.resetForAuthChange()
                myFeedbackViewModel.reset()
                ownerVisibilityViewModel.reset()
                guard let newUserID else { return }
                await registrationsViewModel.refresh()
                await myFeedbackViewModel.refresh(userID: newUserID)
                await viewModel.refreshNotificationPreferences(userID: newUserID)
                await organizationsViewModel.refresh()
                await refreshOwnerVisibilityIfAllowed()
            }
        }
        .onChange(of: eventsViewModel.contentVersion) { _, _ in
            guard authState.isAuthenticated else { return }
            registrationsViewModel.synchronize(with: eventsViewModel.events)
        }
        .onReceive(NotificationCenter.default.publisher(for: .organizationsChanged)) { _ in
            guard authState.isAuthenticated else { return }
            Task {
                await organizationsViewModel.refresh()
                await refreshOwnerVisibilityIfAllowed()
            }
        }
        .onDisappear {
            viewModel.clearFeedbackSuccessMessage()
        }
        .sheet(isPresented: $isShowingEditProfileSheet) {
            NavigationStack {
                editProfileContent
            }
            .presentationDragIndicator(.visible)
        }
        .alert(
            AppStrings.Profile.signOutConfirmTitle,
            isPresented: $isShowingLogoutConfirmation
        ) {
            Button(AppStrings.Profile.signOut, role: .destructive) {
                Task {
                    let didSignOut = await AuthService.shared.signOut()
                    if !didSignOut {
                        logoutErrorMessage = AppStrings.Profile.signOutFailed
                    }
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
        .observesKeyboardDismissTaps()
    }

    private var profileHeader: some View {
        AppBrandHeader {
            HStack(spacing: AppTheme.eventsControlGroupSpacing) {
                AppNotificationBellButton()

                if displayUser != nil {
                    AppGlassIconButton(systemImage: "pencil", accessibilityLabel: AppStrings.Profile.editProfile) {
                        beginEditingProfile()
                    }
                }
            }
        }
    }

    private func scrollToTop(with scrollProxy: ScrollViewProxy) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            scrollProxy.scrollTo(profileRootScrollTopID, anchor: .top)
        }
    }

    @ViewBuilder
    private func profileDestination(for route: ProfileNavigationRoute) -> some View {
        switch route {
        case .organizationManagement:
            OrganizationManagementHubView(
                organizationsViewModel: organizationsViewModel,
                repository: organizationRepository,
                newsRepository: newsRepository,
                eventRepository: eventRepository
            )
        case .registrations:
            MyRegistrationsView(
                viewModel: registrationsViewModel,
                eventRepository: eventRepository,
                eventsViewModel: eventsViewModel
            )
        case .savedContent:
            SavedContentView(
                newsViewModel: newsViewModel,
                eventsViewModel: eventsViewModel,
                organizationsViewModel: organizationsViewModel
            )
        case .followedOrganizations:
            FollowedOrganizationsView(
                organizationsViewModel: organizationsViewModel,
                organizationRepository: organizationRepository
            )
        case .recentViews:
            RecentViewsView(
                recentViewsViewModel: recentViewsViewModel,
                newsViewModel: newsViewModel,
                eventsViewModel: eventsViewModel,
                organizationsViewModel: organizationsViewModel
            )
        case .activityHistory:
            ActivityHistoryView(
                activityLogViewModel: activityLogViewModel,
                newsViewModel: newsViewModel,
                eventsViewModel: eventsViewModel,
                organizationsViewModel: organizationsViewModel
            )
        case .profileSettings:
            ProfilePreferencesView(
                viewModel: viewModel,
                userBlockingCoordinator: userBlockingCoordinator,
                analyticsService: analyticsService,
                isAnalyticsCollectionEnabled: $isAnalyticsCollectionEnabled,
                currentUser: displayUser,
                onDeleteAccount: { isShowingDeleteAccountConfirmation = true }
            )
        case .feedbackComposer:
            if let user = displayUser {
                ProfileFeedbackComposerView(
                    selectedFeedbackType: $selectedFeedbackType,
                    feedbackMessage: $feedbackMessage,
                    statusMessage: viewModel.feedbackMessage,
                    isSubmitting: viewModel.isSubmittingFeedback,
                    onSubmit: { submitFeedback(for: user) }
                )
            }
        case .supportProject:
            ProfileProjectSupportView(
                config: donationConfigViewModel.config,
                language: appLanguage
            )
        case .blockedUsers:
            BlockedUsersView(coordinator: userBlockingCoordinator)
        case .organizationRequests:
            ModerationToolsView(
                scope: .organizationRequests,
                organizationRepository: organizationRepository
            )
        case .moderationTools:
            ModerationToolsView(
                organizationRepository: organizationRepository
            )
        case .userManagement:
            UserManagementView()
        case .featuredBannerManagement:
            FeaturedBannerManagementView(
                repository: featuredBannerRepository,
                publicCache: featuredBannerCache,
                newsRepository: newsRepository,
                eventRepository: eventRepository,
                organizationRepository: organizationRepository
            )
        case .legalDocumentManagement:
            LegalDocumentManagementView(repository: legalDocumentRepository)
        case .legalEvidence:
            if PermissionService.isAppOwner(user: permissionUser) {
                LegalEvidenceView()
            }
        case .ownerAnalytics:
            if PermissionService.isAppOwner(user: permissionUser) {
                OwnerAnalyticsView(repository: ownerAnalyticsRepository)
            }
        case .donationSettings:
            DonationSettingsView(viewModel: donationConfigViewModel)
        case .feedbackInbox:
            FeedbackInboxView(
                repository: feedbackRepository,
                notificationInboxRepository: notificationInboxRepository
            )
        case let .systemLogs(accessMode):
            switch accessMode {
            case .owner:
                if PermissionService.isAppOwner(user: permissionUser) {
                    SystemLogsDashboardView(accessMode: .owner, embedsInNavigationStack: false)
                }
            case .appAdmin:
                if PermissionService.isAppAdmin(user: permissionUser) {
                    SystemLogsDashboardView(accessMode: .appAdmin, embedsInNavigationStack: false)
                }
            }
        case .notifications:
            NotificationInboxView(
                viewModel: notificationInboxViewModel,
                onNotificationTap: onNotificationTap
            )
        case let .myFeedback(userID):
            MyFeedbackView(viewModel: myFeedbackViewModel, currentUserID: userID)
        case let .dsaStatement(statementID):
            DsaStatementView(statementID: statementID)
        case let .legal(document):
            LegalDocumentView(document: document, repository: legalDocumentRepository)
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
                                .font(AppTheme.buttonLabelFont)
                                .foregroundStyle(AppTheme.textPrimary)

                            TextField(AppStrings.Profile.deleteAccountConfirmationKeyword, text: $deleteAccountConfirmationText)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .appEditorInputStyle()

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
                            .appActionButtonStyle(.primary)
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
            .observesKeyboardDismissTaps()
        }
    }

    private var canConfirmAccountDeletion: Bool {
        deleteAccountConfirmationText.trimmingCharacters(in: .whitespacesAndNewlines) == AppStrings.Profile.deleteAccountConfirmationKeyword
    }

    private var editProfileContent: some View {
        EditorScreenShell(
            title: AppStrings.Profile.editProfile,
            subtitle: AppStrings.Profile.editProfileSubtitle,
            closeStyle: .cancel,
            closeAction: {
                guard !viewModel.isSavingProfile else { return }
                isShowingEditProfileSheet = false
            }
        ) {
            ProfileAvatarEditorCard(
                avatarURL: displayUser?.avatarURL,
                initials: displayUser?.initials ?? "UC",
                previewImage: avatarPreviewImage,
                selectedPhoto: $selectedAvatarPhoto,
                isLoadingAvatar: isLoadingAvatarSelection,
                isSavingAvatar: viewModel.isSavingProfile && selectedAvatarImageData != nil
            )

            editProfileIdentitySection
            editProfileLocationSection
            editProfileContactSection

            if let profileStatusMessage {
                InlineMessageCard(style: profileStatusStyle, message: profileStatusMessage)
                    .accessibilityLabel(profileStatusMessage)
            }

            if let profileValidationHint {
                InlineMessageCard(style: .info, message: profileValidationHint)
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
        .interactiveDismissDisabled(viewModel.isSavingProfile)
        .sheet(isPresented: $isShowingAvatarCrop, onDismiss: resetAvatarCropSelection) {
            if let cropSourceAvatarImage {
                ImageCropView(
                    sourceImage: cropSourceAvatarImage,
                    profile: .squareAvatar,
                    title: AppStrings.Images.Crop.title,
                    instructions: AppStrings.Profile.avatarSubtitle,
                    onCancel: {},
                    onApply: applyCroppedAvatarImage(_:)
                )
            }
        }
        .onChange(of: selectedAvatarPhoto) { _, newValue in
            if newValue == nil, ignoresNextAvatarPhotoClear {
                ignoresNextAvatarPhotoClear = false
                return
            }
            Task {
                await loadSelectedAvatarPhoto(item: newValue)
            }
        }
    }

    private var editProfileIdentitySection: some View {
        ProfileSectionCard(title: AppStrings.Profile.mainInformation) {
            VStack(spacing: AppTheme.dashboardSpacing) {
                EditorTextField(AppStrings.Profile.displayName, text: $displayNameDraft, systemImage: "person", autocapitalization: .words)
                EditorTextField(AppStrings.Profile.fullName, text: $fullNameDraft, systemImage: "person.text.rectangle", autocapitalization: .words)
                ProfileEditorTextArea(
                    title: AppStrings.Profile.bio,
                    text: $bioDraft,
                    counterText: AppStrings.profileBioCounter(bioDraft.count, 240),
                    maxLength: 240
                )
            }
        }
    }

    private var editProfileLocationSection: some View {
        ProfileSectionCard(
            title: AppStrings.Profile.personalRegion,
            subtitle: AppStrings.Profile.personalRegionSubtitle
        ) {
            VStack(spacing: AppTheme.dashboardSpacing) {
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
            title: AppStrings.Profile.guestAvailableTitle,
            subtitle: AppStrings.Profile.guestAvailableSubtitle
        ) {
            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                guestBrowseButton(title: AppStrings.Profile.guestBrowseNews, subtitle: AppStrings.Profile.previewNewsSubtitle, systemImage: "newspaper", destination: .home)
                guestBrowseButton(title: AppStrings.Profile.guestBrowseEvents, subtitle: AppStrings.Profile.previewEventsSubtitle, systemImage: "calendar", destination: .events)
                guestBrowseButton(title: AppStrings.Profile.guestBrowseOrganizations, subtitle: AppStrings.Profile.previewOrganizationsSubtitle, systemImage: "building.2", destination: .organizations)
            }
        }

        guestSupportAndSettingsSection
    }

    @ViewBuilder
    private func userProfileContent(for user: AppUser) -> some View {
        if let profileDashboardMode {
            platformProfileContent(for: user, mode: profileDashboardMode)
        } else {
            ProfileHeroCard(
                user: user,
                readableFederalState: readableFederalState
            )

            quickActionsSection(for: user)
            activityNavigationSection
            supportNavigationSection(for: user)
            preferencesNavigationSection
            sessionActionSection
        }
    }

    @ViewBuilder
    private func platformProfileContent(for user: AppUser, mode: ProfileDashboardMode) -> some View {
        OwnerHeroCard(user: user, readableFederalState: readableFederalState, mode: mode)
        platformOperationsSection
        platformAdministrationSection
        quickActionsSection(for: user)
        activityNavigationSection
        supportNavigationSection(for: user)
        preferencesNavigationSection
        sessionActionSection
    }

    private func quickActionsSection(for user: AppUser, includeMyOrganizations: Bool = true) -> some View {
        ProfileSectionCard(
            title: AppStrings.Profile.personalContentTitle,
            subtitle: AppStrings.Profile.personalContentSubtitle
        ) {
            AppAdaptiveGrid(
                minimumWidth: 145,
                maximumWidth: 260,
                spacing: AppTheme.eventsMetadataSpacing
            ) {
                if includeMyOrganizations {
                    myOrganizationsQuickAction
                }

                NavigationLink(value: ProfileNavigationRoute.registrations) {
                    ProfileQuickActionCard(item: ProfileQuickActionItem(
                        title: AppStrings.Profile.myEvents,
                        subtitle: AppStrings.Profile.quickActionRegisteredEventsSubtitle,
                        systemImage: "calendar",
                        status: .available
                    ))
                }
                .buttonStyle(.plain)

                NavigationLink(value: ProfileNavigationRoute.savedContent) {
                    ProfileQuickActionCard(item: ProfileQuickActionItem(
                        title: AppStrings.Profile.savedContent,
                        subtitle: AppStrings.Profile.quickActionSavedContentSubtitle,
                        systemImage: "bookmark",
                        status: .available
                    ))
                }
                .buttonStyle(.plain)

                NavigationLink(value: ProfileNavigationRoute.followedOrganizations) {
                    ProfileQuickActionCard(item: ProfileQuickActionItem(
                        title: AppStrings.Profile.organizationSubscriptions,
                        subtitle: AppStrings.Profile.quickActionSubscriptionsSubtitle,
                        systemImage: "person.2",
                        status: .available
                    ))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var activityNavigationSection: some View {
        ProfileSectionCard(
            title: AppStrings.Profile.myActivity,
            subtitle: AppStrings.Profile.activitySectionSummary
        ) {
            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                NavigationLink(value: ProfileNavigationRoute.recentViews) {
                    ProfileModuleRow(
                        title: AppStrings.Profile.recentlyViewed,
                        subtitle: AppStrings.Profile.recentlyViewedSubtitle,
                        systemImage: "clock.arrow.circlepath"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink(value: ProfileNavigationRoute.activityHistory) {
                    ProfileModuleRow(
                        title: AppStrings.Profile.activityHistoryModule,
                        subtitle: AppStrings.Profile.quickActionActivitySubtitle,
                        systemImage: "list.bullet.rectangle"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func supportNavigationSection(for user: AppUser) -> some View {
        ProfileSectionCard(
            title: AppStrings.Profile.feedbackSupport,
            subtitle: AppStrings.Profile.supportSectionSubtitle
        ) {
            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                NavigationLink(value: ProfileNavigationRoute.myFeedback(userID: user.id)) {
                    ProfileModuleRow(
                        title: AppStrings.Feedback.myFeedbackTitle,
                        subtitle: AppStrings.Feedback.myFeedbackSubtitle,
                        systemImage: "tray.full"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink(value: ProfileNavigationRoute.feedbackComposer) {
                    ProfileModuleRow(
                        title: AppStrings.Profile.contactSupportTitle,
                        subtitle: AppStrings.Profile.contactSupportSubtitle,
                        systemImage: "square.and.pencil"
                    )
                }
                .buttonStyle(.plain)

                if isProjectSupportAvailable {
                    NavigationLink(value: ProfileNavigationRoute.supportProject) {
                        ProfileModuleRow(
                            title: DonationLocalization.publicSectionTitle(for: appLanguage),
                            subtitle: DonationLocalization.publicSectionSubtitle(for: appLanguage),
                            systemImage: "heart.circle"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var preferencesNavigationSection: some View {
        ProfileSectionCard(
            title: AppStrings.Profile.settingsSection,
            subtitle: AppStrings.Settings.preferencesSubtitle
        ) {
            NavigationLink(value: ProfileNavigationRoute.profileSettings) {
                ProfileModuleRow(
                    title: AppStrings.Profile.settingsAndPrivacyTitle,
                    subtitle: AppStrings.Profile.settingsAndPrivacySubtitle,
                    systemImage: "gearshape",
                    countBadge: notificationInboxViewModel.unreadCount
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var sessionActionSection: some View {
        ProfileSectionCard(
            title: AppStrings.Settings.sessionSection,
            subtitle: AppStrings.Settings.sessionSubtitle
        ) {
            Button(role: .destructive) {
                isShowingLogoutConfirmation = true
            } label: {
                ProfileModuleRow(
                    title: AppStrings.Profile.signOut,
                    subtitle: AppStrings.Settings.sessionSubtitle,
                    systemImage: "rectangle.portrait.and.arrow.right",
                    tint: AppTheme.accentDestructiveForeground,
                    status: .available,
                    accessory: .none
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.logout.button")
        }
    }

    private var guestSupportAndSettingsSection: some View {
        ProfileSectionCard(
            title: AppStrings.Profile.guestSettingsSupportTitle,
            subtitle: AppStrings.Profile.guestSettingsSupportSubtitle
        ) {
            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                if isProjectSupportAvailable {
                    NavigationLink(value: ProfileNavigationRoute.supportProject) {
                        ProfileModuleRow(
                            title: DonationLocalization.publicSectionTitle(for: appLanguage),
                            subtitle: DonationLocalization.publicSectionSubtitle(for: appLanguage),
                            systemImage: "heart.circle"
                        )
                    }
                    .buttonStyle(.plain)
                }

                NavigationLink(value: ProfileNavigationRoute.profileSettings) {
                    ProfileModuleRow(
                        title: AppStrings.Profile.settingsAndPrivacyTitle,
                        subtitle: AppStrings.Profile.settingsAndPrivacySubtitle,
                        systemImage: "gearshape"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var isProjectSupportAvailable: Bool {
        donationConfigViewModel.hasLoadedData
            && donationConfigViewModel.config.isEnabled
            && donationConfigViewModel.config.validDonationURL != nil
    }

    private var myOrganizationsQuickAction: some View {
        NavigationLink(value: ProfileNavigationRoute.organizationManagement) {
            ProfileQuickActionCard(item: ProfileQuickActionItem(
                title: AppStrings.Profile.myOrganizations,
                subtitle: AppStrings.Profile.organizationManagementIntro,
                systemImage: "building.2",
                status: .available
            ))
        }
        .buttonStyle(.plain)
    }

    private func guestBrowseButton(
        title: String,
        subtitle: String,
        systemImage: String,
        destination: ProfileBrowseDestination
    ) -> some View {
        Button {
            onBrowseDestinationSelected(destination)
        } label: {
            ProfileModuleRow(
                title: title,
                subtitle: subtitle,
                systemImage: systemImage,
                status: .available
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var platformOperationsSection: some View {
        if canShowOrganizationRequests || canShowModerationTools || canShowFeedbackReports {
            ProfileSectionCard(
                title: AppStrings.Profile.platformOperationsTitle,
                subtitle: AppStrings.Profile.platformOperationsSubtitle
            ) {
                VStack(spacing: AppTheme.eventsMetadataSpacing) {
                    if canShowOrganizationRequests {
                        NavigationLink(value: ProfileNavigationRoute.organizationRequests) {
                            ProfileModuleRow(
                                title: AppStrings.Profile.ownerOrganizationRequests,
                                subtitle: AppStrings.Profile.organizationRequestsReviewSubtitle,
                                systemImage: "clock.badge.exclamationmark",
                                status: .available,
                                countBadge: ownerVisibilityViewModel.pendingOrganizationRequestCount
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if canShowModerationTools {
                        NavigationLink(value: ProfileNavigationRoute.moderationTools) {
                            ProfileModuleRow(
                                title: AppStrings.Profile.ownerModeration,
                                subtitle: AppStrings.Profile.ownerModerationSubtitle,
                                systemImage: "shield.lefthalf.filled",
                                status: .available
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if canShowFeedbackReports {
                        NavigationLink(value: ProfileNavigationRoute.feedbackInbox) {
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
        }
    }

    @ViewBuilder
    private var platformAdministrationSection: some View {
        if hasPlatformAdministrationItems {
            ProfileSectionCard(
                title: AppStrings.Profile.platformAdministrationTitle,
                subtitle: AppStrings.Profile.platformAdministrationSubtitle
            ) {
                VStack(spacing: AppTheme.eventsMetadataSpacing) {
                    if canShowAdminTools {
                        NavigationLink(value: ProfileNavigationRoute.userManagement) {
                            ProfileModuleRow(
                                title: AppStrings.Profile.ownerUsers,
                                subtitle: AppStrings.Profile.ownerUsersSubtitle,
                                systemImage: "person.3"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if canShowFeaturedBanners {
                        NavigationLink(value: ProfileNavigationRoute.featuredBannerManagement) {
                            ProfileModuleRow(
                                title: AppStrings.FeaturedManagement.profileEntryTitle,
                                subtitle: AppStrings.FeaturedManagement.profileEntrySubtitle,
                                systemImage: "sparkles.rectangle.stack"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if PermissionService.isAppOwner(user: permissionUser) {
                        NavigationLink(value: ProfileNavigationRoute.ownerAnalytics) {
                            ProfileModuleRow(
                                title: AppStrings.OwnerAnalytics.title,
                                subtitle: AppStrings.OwnerAnalytics.subtitle,
                                systemImage: "chart.bar.xaxis"
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("profile.owner.analytics")

                        platformOwnerAdministrationRows
                    } else if PermissionService.isAppAdmin(user: permissionUser) {
                        NavigationLink(value: ProfileNavigationRoute.systemLogs(.appAdmin)) {
                            ProfileModuleRow(
                                title: AppStrings.SystemLogs.appAdminTitle,
                                subtitle: AppStrings.SystemLogs.appAdminSubtitle,
                                systemImage: "doc.text.magnifyingglass"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var hasPlatformAdministrationItems: Bool {
        canShowAdminTools
            || canShowFeaturedBanners
            || PermissionService.isAppOwner(user: permissionUser)
            || PermissionService.isAppAdmin(user: permissionUser)
    }

    @ViewBuilder
    private var platformOwnerAdministrationRows: some View {
        NavigationLink(value: ProfileNavigationRoute.donationSettings) {
            ProfileModuleRow(
                title: DonationLocalization.publicSectionTitle(for: appLanguage),
                subtitle: DonationLocalization.platformEntrySubtitle(for: appLanguage),
                systemImage: "heart.circle"
            )
        }
        .buttonStyle(.plain)

        NavigationLink(value: ProfileNavigationRoute.legalDocumentManagement) {
            ProfileModuleRow(
                title: AppStrings.Profile.ownerLegalDocuments,
                subtitle: AppStrings.Profile.ownerLegalDocumentsSubtitle,
                systemImage: "doc.text.magnifyingglass"
            )
        }
        .buttonStyle(.plain)

        NavigationLink(value: ProfileNavigationRoute.legalEvidence) {
            ProfileModuleRow(
                title: AppStrings.LegalEvidence.title,
                subtitle: AppStrings.LegalEvidence.profileSubtitle,
                systemImage: "signature"
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("profile.owner.legalEvidence")

        NavigationLink(value: ProfileNavigationRoute.systemLogs(.owner)) {
            ProfileModuleRow(
                title: AppStrings.SystemLogs.ownerTitle,
                subtitle: AppStrings.SystemLogs.ownerProfileSubtitle,
                systemImage: "waveform.path.ecg.rectangle"
            )
        }
        .buttonStyle(.plain)
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
        cropSourceAvatarImage = nil
        isShowingAvatarCrop = false
        ignoresNextAvatarPhotoClear = false
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
            guard authState.updateAuthenticatedUser(updatedUser) else { return }
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
                isLoadingAvatarSelection = false
                return
            }

            cropSourceAvatarImage = image
            isShowingAvatarCrop = true
            viewModel.profileMessage = nil
            isLoadingAvatarSelection = false
        } catch {
            viewModel.profileMessage = AppStrings.Profile.avatarSelectionFailed
            isLoadingAvatarSelection = false
        }
    }

    private func applyCroppedAvatarImage(_ processedImage: ProcessedImageSelection) {
        guard let previewImage = UIImage(data: processedImage.data) else {
            viewModel.profileMessage = AppStrings.Profile.avatarSelectionFailed
            return
        }

        avatarPreviewImage = previewImage
        selectedAvatarImageData = processedImage.data
        viewModel.profileMessage = nil
    }

    private func resetAvatarCropSelection() {
        cropSourceAvatarImage = nil
        guard selectedAvatarPhoto != nil else { return }
        ignoresNextAvatarPhotoClear = true
        selectedAvatarPhoto = nil
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


struct ProfileDonationSupportCard: View {
    let config: DonationConfig
    let language: AppLanguage
    @Environment(\.openURL) private var openURL

    private var title: String {
        config.title(for: language)
    }

    private var message: String {
        config.message(for: language)
    }

    private var buttonTitle: String {
        config.buttonTitle(for: language)
    }

    private var donationURL: URL? {
        guard config.isEnabled else { return nil }
        return config.validDonationURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "heart.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.accentSupportForeground)
                    .frame(width: 40, height: 40)
                    .background(AppTheme.accentSupport.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let donationURL {
                PrimaryActionButton(
                    title: buttonTitle,
                    systemImage: "arrow.up.right.square"
                ) {
                    openURL(donationURL)
                }

                Label {
                    Text(DonationLocalization.externalSiteNotice(
                        host: donationURL.host ?? donationURL.absoluteString,
                        language: language
                    ))
                } icon: {
                    Image(systemName: "lock.shield")
                }
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppTheme.dashboardCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.accentSupport.opacity(0.07), in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .strokeBorder(AppTheme.accentSupport.opacity(0.16), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
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
            newsRepository: MockNewsRepository(),
            eventRepository: MockEventRepository(),
            organizationRepository: MockOrganizationRepository(),
            featuredBannerRepository: MockFeaturedBannerRepository(),
            ownerAnalyticsRepository: MockOwnerAnalyticsRepository(),
            notificationInboxRepository: MockNotificationInboxRepository(),
            notificationInboxViewModel: NotificationInboxViewModel(repository: MockNotificationInboxRepository()),
            userBlockingCoordinator: UserBlockingCoordinator(repository: MockUserBlockingRepository())
        )
    }
    .environmentObject(AuthState())
}
