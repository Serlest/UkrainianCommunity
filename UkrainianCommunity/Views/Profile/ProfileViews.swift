import PhotosUI
import SwiftUI

private let profileRootScrollTopID = "profileRootScrollTop"

enum ProfileNavigationRoute: Hashable {
    case announcementManagement
    case announcementHistory
    case announcementFeedback(UserAnnouncement)
    case organizationManagement
    case registrations
    case savedContent
    case followedOrganizations
    case recentViews
    case activityHistory
    case profileSettings
    case accountSecurity
    case feedbackComposer
    case supportProject
    case blockedUsers
    case blockedOrganizations
    case organizationRequests
    case organizationRequestReview(organizationID: String)
    case moderationTools
    case moderationMaterial(contentType: String, id: String)
    case userManagement
    case directoryEditors
    case featuredBannerManagement
    case contentPlanning(draftID: String?)
    case contentPlanningNews(id: String)
    case contentPlanningEvent(id: String)
    case legalDocumentManagement
    case legalEvidence
    case ownerAnalytics
    case bannerAnalytics(period: AnalyticsPeriod)
    case donationSettings
    case feedbackInbox
    case feedbackDetail(feedbackID: String)
    case myFeedbackDetail(userID: String, feedbackID: String)
    case systemLogs(SystemLogsAccessMode)
    case systemLogDetail(String)
    case notifications
    case myFeedback(userID: String)
    case dsaStatement(statementID: String)
    case legal(LegalDocumentKind)
}

struct ProfileView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var isProfileVisible = false
    @EnvironmentObject private var announcementCoordinator: AnnouncementCoordinator
    @ObservedObject var viewModel: ProfileViewModel
    private let feedbackRepository: FeedbackRepository
    private let newsRepository: NewsRepository
    private let eventRepository: EventRepository
    private let organizationRepository: OrganizationRepository
    private let featuredBannerRepository: FeaturedBannerRepository
    private let featuredBannerCache: FeaturedBannerCache
    private let legalDocumentRepository: LegalDocumentRepository
    private let ownerAnalyticsRepository: OwnerAnalyticsRepository
    private let ownerContentDraftRepository: OwnerContentDraftRepository
    private let analyticsService: AnalyticsTracking
    private let bannerMeasurementService: BannerMeasurementService
    private let donationConfigRepository: DonationConfigRepository
    private let notificationInboxRepository: NotificationInboxRepository
    @ObservedObject private var userBlockingCoordinator: UserBlockingCoordinator
    private let onNotificationTap: (AppNotification) -> Void
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
    @State private var isShowingProfileDiscardConfirmation = false
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
    @State private var avatarSelectionTask: Task<Void, Never>?
    @State private var selectedFeedbackType: FeedbackType = .question
    @State private var feedbackMessage = ""
    @State private var guestAccessAction: GuestAccessAction?
    @State private var isShowingLogoutConfirmation = false
    @State private var logoutErrorMessage: String?
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
        ownerContentDraftRepository: OwnerContentDraftRepository = FirestoreOwnerContentDraftRepository(),
        analyticsService: AnalyticsTracking = NoopAnalyticsService(),
        bannerMeasurementService: BannerMeasurementService,
        donationConfigRepository: DonationConfigRepository = DonationConfigRepositories.makeDefault(),
        notificationInboxRepository: NotificationInboxRepository = FirestoreNotificationInboxRepository(),
        notificationInboxViewModel: NotificationInboxViewModel? = nil,
        userBlockingCoordinator: UserBlockingCoordinator,
        localEventReminderService: LocalEventReminderServiceProtocol = LocalEventReminderService(),
        onNotificationTap: @escaping (AppNotification) -> Void = { _ in },
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
        self.ownerContentDraftRepository = ownerContentDraftRepository
        self.analyticsService = analyticsService
        self.bannerMeasurementService = bannerMeasurementService
        self.donationConfigRepository = donationConfigRepository
        self.notificationInboxRepository = notificationInboxRepository
        self.notificationInboxViewModel = notificationInboxViewModel ?? NotificationInboxViewModel(
            repository: notificationInboxRepository
        )
        self.userBlockingCoordinator = userBlockingCoordinator
        self.onNotificationTap = onNotificationTap
        self.scrollResetToken = scrollResetToken
        _isAnalyticsCollectionEnabled = State(initialValue: analyticsService.isCollectionEnabled)
        _navigationPath = navigationPath
        _registrationsViewModel = StateObject(wrappedValue: MyRegistrationsViewModel(
            repository: eventRepository,
            localEventReminderService: localEventReminderService,
            analyticsService: analyticsService
        ))
        _myFeedbackViewModel = StateObject(wrappedValue: MyFeedbackViewModel(repository: feedbackRepository))
        var historyRepository: any RecentViewsRepository = FirestoreRecentViewsRepository()
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing"),
           ProcessInfo.processInfo.environment["UITestRecentViews"] == "1" {
            historyRepository = UITestRecentViewsRepository()
        }
#endif
        _recentViewsViewModel = StateObject(wrappedValue: RecentViewsViewModel(repository: historyRepository))
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing"),
           ProcessInfo.processInfo.environment["UITestActivityHistory"] == "1" {
            _activityLogViewModel = StateObject(wrappedValue: ActivityLogViewModel(repository: UITestActivityLogRepository(), synchronizePending: { _ in nil }))
        } else {
            _activityLogViewModel = StateObject(wrappedValue: ActivityLogViewModel(repository: FirestoreActivityLogRepository()))
        }
#else
        _activityLogViewModel = StateObject(wrappedValue: ActivityLogViewModel(repository: FirestoreActivityLogRepository()))
#endif
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

    private var accessPolicy: ProfileAccessPolicy { ProfileAccessPolicy(user: permissionUser) }
    private var accessIdentity: ProfileAccessIdentity { ProfileAccessIdentity(user: permissionUser) }

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

    private var displayUser: AppUser? {
        authState.isAuthenticated ? authState.user : nil
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
        if viewModel.hasPendingProfileSave { return .info }
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
        if let validationMessage = profileDraft.validationMessage { return validationMessage }

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
        !viewModel.isSavingProfile && !isLoadingAvatarSelection &&
        (viewModel.hasPendingProfileSave || (hasProfileChanges && profileDraft.validationMessage == nil))
    }

    private var profileDraft: EditableUserProfileDraft {
        EditableUserProfileDraft(
            fullName: fullNameDraft, displayName: displayNameDraft,
            telegramUsername: telegramUsernameDraft, city: cityDraft, bio: bioDraft,
            selectedFederalState: selectedFederalStateDraft, avatarURL: displayUser?.avatarURL
        )
    }

    var body: some View {
        ZStack {
            AppBackgroundView()
                .allowsHitTesting(false)

            GeometryReader { proxy in
                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 0) {
                            Color.clear
                                .frame(height: 0)
                                .id(profileRootScrollTopID)

                            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                                profileHeader

                                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                                    if let user = displayUser {
                                        userProfileContent(for: user)
                                    } else if authState.isGuest {
                                        ProfileGuestContent {
                                            authState.presentAuthFlow(.login)
                                        } createAccount: {
                                            authState.presentAuthFlow(.register)
                                        }
                                    } else {
                                        ProgressView()
                                            .frame(maxWidth: .infinity)
                                            .accessibilityIdentifier("profile.loading")
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
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
            Group {
                if accessPolicy.allows(route) {
                    profileDestination(for: route)
                } else {
                    PushedScreenShell(title: AppStrings.Profile.title) {
                        InlineMessageCard(style: .error, message: AppStrings.Errors.permissionDenied)
                    }
                    .accessibilityIdentifier("profile.accessDenied")
                }
            }
            .id(locale.identifier)
        }
        .task(id: authState.user?.id) {
            isAnalyticsCollectionEnabled = analyticsService.isCollectionEnabled
            async let profile: Void = viewModel.loadIfNeeded()
            async let donation: Void = donationConfigViewModel.loadIfNeeded()
            if !authState.isAuthenticated {
                registrationsViewModel.resetForGuest()
                myFeedbackViewModel.reset()
                ownerVisibilityViewModel.reset()
            }
            _ = await (profile, donation)
        }
        .task(id: accessIdentity) {
            ownerVisibilityViewModel.reset()
            await loadOwnerVisibilityIfAllowed()
        }
        .onChange(of: accessIdentity) { _, _ in
            navigationPath.removeAll()
            isShowingEditProfileSheet = false
            isShowingAvatarCrop = false
            avatarSelectionTask?.cancel()
        }
        .appRefreshable {
            async let profile: Void = viewModel.refresh()
            async let donation: Void = donationConfigViewModel.load()
            if authState.isAuthenticated {
                async let notifications: Void = notificationInboxViewModel.refresh()
                async let owner: Void = refreshOwnerVisibilityIfAllowed()
                _ = await (notifications, owner)
            }
            _ = await (profile, donation)
        }
        .onChange(of: authState.user?.id) { _, newUserID in
            // Consent and child caches are scoped to the active principal.
            viewModel.clearFeedbackSuccessMessage()
            isAnalyticsCollectionEnabled = analyticsService.isCollectionEnabled
            registrationsViewModel.resetForAuthChange()
            myFeedbackViewModel.reset()
            feedbackMessage = ""
            selectedFeedbackType = .question
        }
        .onChange(of: eventsViewModel.contentVersion) { _, _ in
            guard authState.isAuthenticated else { return }
            registrationsViewModel.synchronize(with: eventsViewModel.events)
        }
        .onChange(of: notificationInboxViewModel.snapshotVersion) { _, _ in
            guard shouldLoadOwnerVisibility else { return }
            Task { await refreshOwnerVisibilityIfAllowed() }
        }
        .onAppear { isProfileVisible = true }
        .task(id: isProfileVisible && scenePhase == .active) {
            guard isProfileVisible, scenePhase == .active, shouldLoadOwnerVisibility else { return }
            await refreshOwnerVisibilityIfAllowed()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                guard !Task.isCancelled else { return }
                await refreshOwnerVisibilityIfAllowed()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .organizationsChanged)) { _ in
            guard authState.isAuthenticated else { return }
            Task {
                await refreshOwnerVisibilityIfAllowed()
            }
        }
        .onDisappear {
            isProfileVisible = false
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

            .accessibilityIdentifier("profile.logout.confirm")
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
                    .accessibilityIdentifier("profile.edit.open")
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
                eventRepository: eventRepository,
                legalDocumentRepository: legalDocumentRepository
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
                organizationsViewModel: organizationsViewModel,
                newsRepository: newsRepository,
                eventRepository: eventRepository,
                organizationRepository: organizationRepository
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
                bannerMeasurementService: bannerMeasurementService,
                isAnalyticsCollectionEnabled: $isAnalyticsCollectionEnabled,
                currentUser: displayUser
            )
        case .accountSecurity:
            AccountSecurityView().id(authState.user?.id)
        case .announcementManagement:
            if PermissionService.isAppOwner(user: displayUser) {
                AnnouncementOwnerView(repository: announcementCoordinator.repository)
            }
        case .announcementHistory:
            AnnouncementHistoryView(coordinator: announcementCoordinator)
        case .announcementFeedback(let item):
            if let user = displayUser {
                AnnouncementFeedbackView(item: item, user: user, viewModel: viewModel)
            }
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
        case .blockedOrganizations:
            BlockedOrganizationsView()
        case .organizationRequests:
            ModerationToolsView(
                scope: .organizationRequests,
                organizationRepository: organizationRepository
            )
        case .organizationRequestReview(let organizationID):
            ModerationToolsView(
                scope: .organizationRequests,
                requestedOrganizationID: organizationID,
                organizationRepository: organizationRepository
            )
            .id(organizationID)
        case .moderationTools:
            ContentModerationView()
        case let .moderationMaterial(contentType, id):
            ContentModerationDetail(contentType: contentType, contentID: id)
        case .userManagement:
            UserManagementView(reads: MockContentBuilder.userManagementRefreshFixture() ?? .live)
        case .directoryEditors:
            if PermissionService.isAppOwner(user: permissionUser) {
                if let fixture = MockContentBuilder.directoryAccessFixture() {
                    DirectoryEditorsView(users: fixture.users, access: fixture.access)
                } else {
                    DirectoryEditorsView()
                }
            }
        case .featuredBannerManagement:
            FeaturedBannerManagementView(
                repository: featuredBannerRepository,
                publicCache: featuredBannerCache,
                newsRepository: newsRepository,
                eventRepository: eventRepository,
                organizationRepository: organizationRepository
            )
        case let .contentPlanning(draftID):
            if PermissionService.isAppOwner(user: permissionUser), draftID == nil {
                PublicationControlView { kind, contentID in
                    switch kind {
                    case .news: navigationPath.append(.contentPlanningNews(id: contentID))
                    case .event: navigationPath.append(.contentPlanningEvent(id: contentID))
                    }
                }
            } else if PermissionService.isAppOwner(user: permissionUser) {
                OwnerContentPlanningView(
                    draftRepository: ownerContentDraftRepository,
                    newsRepository: newsRepository,
                    eventRepository: eventRepository,
                    organizationRepository: organizationRepository,
                    initialDraftID: draftID,
                    onDraftOpened: { draft in
                        Task {
                            await notificationInboxViewModel.markRead(
                                notificationID: "contentDraftReady_\(draft.id)"
                            )
                        }
                    },
                    onOpenPublishedContent: { kind, contentID in
                        switch kind {
                        case .news:
                            navigationPath.append(.contentPlanningNews(id: contentID))
                        case .event:
                            navigationPath.append(.contentPlanningEvent(id: contentID))
                        }
                    }
                )
            }
        case let .contentPlanningNews(id):
            NewsDetailView(
                viewModel: newsViewModel,
                postID: id,
                onNewsDeleted: { navigationPath.removeLast() },
                organizationRepository: organizationRepository,
                analyticsSourceScreen: "content_planning_history"
            )
        case let .contentPlanningEvent(id):
            EventDetailView(
                viewModel: eventsViewModel,
                eventID: id,
                onEventDeleted: { navigationPath.removeLast() },
                organizationRepository: organizationRepository,
                analyticsSourceScreen: "content_planning_history"
            )
        case .legalDocumentManagement:
            LegalDocumentManagementView(repository: legalDocumentRepository)
        case .legalEvidence:
            if PermissionService.isAppOwner(user: permissionUser) {
                LegalEvidenceView(legalRepository: legalDocumentRepository)
            }
        case .ownerAnalytics:
            if PermissionService.isAppOwner(user: permissionUser) {
                OwnerAnalyticsView(repository: ownerAnalyticsRepository)
            }
        case let .bannerAnalytics(period):
            if PermissionService.isAppOwner(user: permissionUser) {
                BannerMeasurementReportView(
                    bannerRepository: featuredBannerRepository,
                    initialPeriod: period
                )
            }
        case .donationSettings:
            DonationSettingsView(viewModel: donationConfigViewModel)
        case .feedbackInbox:
            FeedbackInboxView(
                repository: feedbackRepository,
                notificationInboxRepository: notificationInboxRepository
            )
        case let .feedbackDetail(feedbackID):
            FeedbackInboxView(
                repository: feedbackRepository,
                notificationInboxRepository: notificationInboxRepository,
                initialFeedbackID: feedbackID
            )
        case let .myFeedbackDetail(userID, feedbackID):
            MyFeedbackView(
                viewModel: myFeedbackViewModel,
                currentUserID: userID,
                initialFeedbackID: feedbackID
            )
        case let .systemLogDetail(logID):
            if PermissionService.isAppOwner(user: permissionUser) { SystemLogNotificationDestinationView(logID: logID) }
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
                onNotificationTap: onNotificationTap,
                subtitle: PermissionService.canManageFeedback(user: permissionUser) ? OwnerProfileText.notificationsSubtitle : nil
            )
        case let .myFeedback(userID):
            MyFeedbackView(viewModel: myFeedbackViewModel, currentUserID: userID)
        case let .dsaStatement(statementID):
            DsaStatementView(statementID: statementID)
        case let .legal(document):
            LegalDocumentView(document: document, repository: legalDocumentRepository)
        }
    }

    private var editProfileContent: some View {
        EditorScreenShell(
            title: AppStrings.Profile.editProfile,
            subtitle: AppStrings.Profile.editProfileSubtitle,
            closeStyle: .cancel,
            closeAction: {
                guard !viewModel.isSavingProfile else { return }
                if hasProfileChanges && !viewModel.hasPendingProfileSave {
                    isShowingProfileDiscardConfirmation = true
                } else {
                    isShowingEditProfileSheet = false
                }
            }
        ) {
            Group {
                ProfileAvatarEditorCard(
                    avatarURL: viewModel.pendingProfileSaveDraft?.avatarURL ?? displayUser?.avatarURL,
                    initials: displayUser?.initials ?? "UC",
                    previewImage: avatarPreviewImage,
                    selectedPhoto: $selectedAvatarPhoto,
                    isLoadingAvatar: isLoadingAvatarSelection,
                    isSavingAvatar: viewModel.isSavingProfile && selectedAvatarImageData != nil
                )

                editProfileIdentitySection
                editProfileLocationSection
                editProfileContactSection
            }
            .disabled(viewModel.isSavingProfile || viewModel.hasPendingProfileSave)

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
                    title: viewModel.hasPendingProfileSave ? SettingsPrivacyText.verifySavedProfile : AppStrings.Profile.saveChanges,
                    loadingTitle: viewModel.hasPendingProfileSave ? SettingsPrivacyText.verifyingProfile : AppStrings.Profile.savingProfile,
                    isEnabled: canSaveProfile,
                    isLoading: viewModel.isSavingProfile || isLoadingAvatarSelection,
                    systemImage: "checkmark"
                ) {
                    saveProfileChanges()
                }
                .accessibilityIdentifier("profile.edit.save")
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
        .interactiveDismissDisabled(viewModel.isSavingProfile || hasProfileChanges || isLoadingAvatarSelection)
        .confirmationDialog(
            AppLanguage.stored == .german ? "Profiländerungen verwerfen?" : "Відхилити зміни профілю?",
            isPresented: $isShowingProfileDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button(AppStrings.FeaturedEditor.discardChanges, role: .destructive) {
                isShowingEditProfileSheet = false
            }
            Button(AppStrings.Common.cancel, role: .cancel) {}
        }
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
            avatarSelectionTask?.cancel()
            avatarSelectionTask = Task {
                await loadSelectedAvatarPhoto(item: newValue)
            }
        }
        .onDisappear {
            avatarSelectionTask?.cancel()
            avatarSelectionTask = nil
            isLoadingAvatarSelection = false
        }
    }

    private var editProfileIdentitySection: some View {
        ProfileSectionCard(title: AppStrings.Profile.mainInformation) {
            VStack(spacing: AppTheme.dashboardSpacing) {
                AppEditorField(title: AppStrings.Profile.displayName) {
                    EditorTextField(AppStrings.Profile.displayName, text: $displayNameDraft, systemImage: "person", autocapitalization: .words)
                        .accessibilityIdentifier("profile.edit.displayName")
                }
                AppEditorField(title: AppStrings.Profile.fullName) {
                    EditorTextField(AppStrings.Profile.fullName, text: $fullNameDraft, systemImage: "person.text.rectangle", autocapitalization: .words)
                        .accessibilityIdentifier("profile.edit.fullName")
                }
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
                AppEditorField(title: AppStrings.Common.city) {
                    EditorTextField(AppStrings.Common.city, text: $cityDraft, systemImage: "mappin.and.ellipse", autocapitalization: .words)
                        .accessibilityIdentifier("profile.edit.city")
                }
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
                AppEditorField(title: AppStrings.Profile.telegramUsername) {
                    EditorTextField(
                        AppStrings.Profile.telegramUsername,
                        text: $telegramUsernameDraft,
                        systemImage: "paperplane",
                        autocapitalization: .never,
                        autocorrectionDisabled: true
                    )
                    .accessibilityIdentifier("profile.edit.telegram")
                }
            }
        }
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

            if accessPolicy.canUsePersonalFeatures {
                personalOrganizationsSection
                personalContentSection
                supportNavigationSection(for: user)
            }
            preferencesNavigationSection
            sessionActionSection
        }
    }

    @ViewBuilder
    private func platformProfileContent(for user: AppUser, mode: ProfileDashboardMode) -> some View {
        OwnerHeroCard(user: user, readableFederalState: readableFederalState, mode: mode)
        platformOperationsSection
        if PermissionService.isAppOwner(user: user) {
            ownerAdministrationSections
            personalContentSection
        } else {
            platformAdministrationSection
            if accessPolicy.canUsePersonalFeatures {
                personalOrganizationsSection
                personalContentSection
                supportNavigationSection(for: user)
            }
        }
        preferencesNavigationSection
        sessionActionSection
    }

    private var personalOrganizationsSection: some View {
        ProfileSectionCard(title: AppStrings.Organizations.title) {
            profileLink(.organizationManagement, title: AppStrings.Profile.myOrganizations,
                      subtitle: AppStrings.Profile.organizationManagementIntro,
                      icon: "building.2", id: "profile.organizationManagement")
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
        .accessibilityIdentifier("profile.supportSection")
    }

    private var preferencesNavigationSection: some View {
        ProfileSectionCard(
            title: PermissionService.isAppOwner(user: permissionUser) ? AppStrings.Profile.accountSection : AppStrings.Profile.settingsSection,
            subtitle: PermissionService.isAppOwner(user: permissionUser) ? OwnerProfileText.accountSubtitle : AppStrings.Settings.preferencesSubtitle
        ) {
            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                if accessPolicy.canUsePersonalFeatures {
                NavigationLink(value: ProfileNavigationRoute.notifications) {
                    ProfileModuleRow(
                        title: AppStrings.NotificationInbox.title,
                        subtitle: PermissionService.canManageFeedback(user: permissionUser) ? OwnerProfileText.notificationsSubtitle : AppStrings.NotificationInbox.subtitle,
                        systemImage: "tray.full",
                        countBadge: notificationInboxViewModel.unreadCount
                    )
                }
                .accessibilityIdentifier("profile.notifications.open")
                .buttonStyle(.plain)

                if !PermissionService.isAppOwner(user: permissionUser) {
                    profileLink(.announcementHistory, title: AnnouncementStrings.history,
                              icon: "megaphone", id: "profile.announcementHistory")
                }
                }

                NavigationLink(value: ProfileNavigationRoute.profileSettings) {
                    ProfileModuleRow(
                        title: AppStrings.Profile.settingsAndPrivacyTitle,
                        subtitle: AppStrings.Profile.settingsAndPrivacySubtitle,
                        systemImage: "gearshape"
                    )
                }
                .accessibilityIdentifier("profile.settings.open")
                .buttonStyle(.plain)
            }
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
                    systemImage: "rectangle.portrait.and.arrow.right",
                    tint: AppTheme.accentDestructiveForeground,
                    status: .available
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.logout.button")
        }
    }

    private var isProjectSupportAvailable: Bool {
        donationConfigViewModel.hasLoadedData
            && donationConfigViewModel.config.isEnabled
            && donationConfigViewModel.config.validDonationURL != nil
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
                                countState: ownerVisibilityViewModel.organizationRequestCountState
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("profile.organizationRequests")
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
                        .accessibilityIdentifier("profile.moderation")
                    }

                    if canShowFeedbackReports {
                        NavigationLink(value: ProfileNavigationRoute.feedbackInbox) {
                            ProfileModuleRow(
                                title: PermissionService.isAppOwner(user: permissionUser) ? AppStrings.Feedback.inboxTitle : AppStrings.Profile.ownerUserFeedback,
                                subtitle: AppStrings.Feedback.inboxSubtitle,
                                systemImage: "bubble.left.and.bubble.right",
                                status: .available,
                                countState: ownerVisibilityViewModel.feedbackCountState
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("profile.feedbackInbox")
                    }

                    if ownerVisibilityViewModel.hasCountLoadFailure {
                        Button {
                            Task {
                                await refreshOwnerVisibilityIfAllowed()
                            }
                        } label: {
                            Label(AppStrings.Action.retry, systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .appActionButtonStyle(.secondary)
                        .accessibilityIdentifier("profile.ownerVisibility.retry")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func profileLink(_ route: ProfileNavigationRoute, title: String, subtitle: String? = nil,
                             icon: String, id: String) -> some View {
        if accessPolicy.allows(route) {
            NavigationLink(value: route) {
                ProfileModuleRow(title: title, subtitle: subtitle, systemImage: icon)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(id)
        }
    }

    @ViewBuilder
    private var ownerAdministrationSections: some View {
        ProfileSectionCard(title: OwnerProfileText.accessTitle) {
            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                profileLink(.organizationManagement, title: OwnerProfileText.organizations,
                          subtitle: OwnerProfileText.organizationsSubtitle, icon: "building.2", id: "profile.organizationManagement")
                profileLink(.userManagement, title: AppStrings.Profile.ownerUsers,
                          subtitle: AppStrings.Profile.ownerUsersSubtitle, icon: "person.3", id: "profile.userManagement")
                profileLink(.directoryEditors, title: OwnerProfileText.directoryEditors,
                          subtitle: OwnerProfileText.directoryEditorsSubtitle, icon: "books.vertical", id: "profile.directoryEditors")
            }
        }
        ProfileSectionCard(title: OwnerProfileText.contentTitle) {
            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                profileLink(.contentPlanning(draftID: nil), title: PublicationControlText.title,
                          subtitle: PublicationControlText.subtitle, icon: "calendar.badge.clock", id: "profile.contentPlanning")
                profileLink(.featuredBannerManagement, title: AppStrings.FeaturedManagement.profileEntryTitle,
                          subtitle: AppStrings.FeaturedManagement.profileEntrySubtitle, icon: "sparkles.rectangle.stack", id: "profile.featuredBanners")
                profileLink(.announcementManagement, title: AnnouncementStrings.title,
                          subtitle: AnnouncementStrings.subtitle, icon: "megaphone", id: "profile.announcements")
            }
        }
        ProfileSectionCard(title: OwnerProfileText.reportsTitle) {
            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                profileLink(.ownerAnalytics, title: AppStrings.OwnerAnalytics.title,
                          subtitle: AppStrings.OwnerAnalytics.subtitle, icon: "chart.bar.xaxis", id: "profile.owner.analytics")
                profileLink(.systemLogs(.owner), title: AppStrings.SystemLogs.ownerTitle,
                          subtitle: AppStrings.SystemLogs.ownerProfileSubtitle, icon: "waveform.path.ecg.rectangle", id: "profile.owner.systemLogs")
            }
        }
        ProfileSectionCard(title: OwnerProfileText.platformSettingsTitle) {
            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                profileLink(.legalDocumentManagement, title: AppStrings.Profile.ownerLegalDocuments,
                          subtitle: OwnerProfileText.legalDocumentsSubtitle, icon: "doc.text", id: "profile.owner.legalDocuments")
                profileLink(.legalEvidence, title: AppStrings.LegalEvidence.title,
                          subtitle: AppStrings.LegalEvidence.profileSubtitle, icon: "signature", id: "profile.owner.legalEvidence")
                profileLink(.donationSettings, title: DonationLocalization.settingsTitle(for: appLanguage),
                          subtitle: DonationLocalization.platformEntrySubtitle(for: appLanguage), icon: "heart.circle", id: "profile.owner.donationSettings")
            }
        }
    }

    private var personalContentSection: some View {
        ProfileSectionCard(title: AppStrings.Profile.personalContentTitle) {
            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                profileLink(.registrations, title: OwnerProfileText.registrations,
                          subtitle: AppStrings.Profile.quickActionRegisteredEventsSubtitle, icon: "calendar", id: "profile.registrations")
                profileLink(.savedContent, title: AppStrings.Profile.savedContent,
                          icon: "bookmark", id: "profile.savedContent")
                profileLink(.followedOrganizations, title: AppStrings.Profile.organizationSubscriptions,
                          icon: "person.2", id: "profile.followedOrganizations")
                profileLink(.recentViews, title: AppStrings.Profile.recentlyViewed,
                          icon: "clock.arrow.circlepath", id: "profile.recentViews")
                profileLink(.activityHistory, title: AppStrings.Profile.activityHistoryModule,
                          subtitle: AppStrings.Profile.quickActionActivitySubtitle, icon: "list.bullet.rectangle", id: "profile.activityHistory")
            }
        }
    }

    @ViewBuilder
    private var platformAdministrationSection: some View {
        if canShowAdminTools || canShowFeaturedBanners || PermissionService.isAppAdmin(user: permissionUser) {
            ProfileSectionCard(title: AppStrings.Profile.platformAdministrationTitle,
                               subtitle: OwnerProfileText.adminToolsSubtitle) {
                VStack(spacing: AppTheme.eventsMetadataSpacing) {
                    if canShowAdminTools {
                        profileLink(.userManagement, title: AppStrings.Profile.ownerUsers,
                                  subtitle: OwnerProfileText.adminUsersSubtitle, icon: "person.3", id: "profile.userManagement")
                    }
                    if canShowFeaturedBanners {
                        profileLink(.featuredBannerManagement, title: AppStrings.FeaturedManagement.profileEntryTitle,
                                  subtitle: AppStrings.FeaturedManagement.profileEntrySubtitle, icon: "sparkles.rectangle.stack", id: "profile.featuredBanners")
                    }
                    if PermissionService.isAppAdmin(user: permissionUser) {
                        profileLink(.systemLogs(.appAdmin), title: AppStrings.SystemLogs.appAdminTitle,
                                  subtitle: AppStrings.SystemLogs.appAdminSubtitle, icon: "doc.text.magnifyingglass", id: "profile.admin.systemLogs")
                    }
                }
            }
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

        let pending = viewModel.pendingProfileSaveDraft
        fullNameDraft = pending?.fullName ?? displayUser?.fullName ?? ""
        avatarSelectionTask?.cancel()
        isLoadingAvatarSelection = false
        displayNameDraft = pending?.displayName ?? displayUser?.displayName ?? ""
        telegramUsernameDraft = pending.map { $0.telegramUsername ?? "" } ?? displayUser?.telegramUsername ?? ""
        cityDraft = pending?.city ?? displayUser?.city ?? ""
        bioDraft = pending?.bio ?? displayUser?.bio ?? ""
        selectedFederalStateDraft = pending?.selectedFederalState ?? displayUser?.selectedFederalState ?? .tirol
        selectedAvatarPhoto = nil
        selectedAvatarImageData = nil
        avatarPreviewImage = nil
        cropSourceAvatarImage = nil
        isShowingAvatarCrop = false
        isShowingProfileDiscardConfirmation = false
        ignoresNextAvatarPhotoClear = false
        if !viewModel.hasPendingProfileSave { viewModel.profileMessage = nil }
        isShowingEditProfileSheet = true
    }

    private func saveProfileChanges() {
        guard canSaveProfile else { return }

        Task {
            let updatedUser = await viewModel.saveProfile(
                profileDraft,
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
            guard !Task.isCancelled else { return }
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
            guard !Task.isCancelled else { return }
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
                localEventReminderService: MockLocalEventReminderService(),
                notificationRegistrationUpdater: { _, _ in }
            ),
            feedbackRepository: MockFeedbackRepository(),
            newsRepository: MockNewsRepository(),
            eventRepository: MockEventRepository(),
            organizationRepository: MockOrganizationRepository(),
            featuredBannerRepository: MockFeaturedBannerRepository(),
            ownerAnalyticsRepository: MockOwnerAnalyticsRepository(),
            bannerMeasurementService: BannerMeasurementService(startsObservers: false),
            notificationInboxRepository: MockNotificationInboxRepository(),
            notificationInboxViewModel: NotificationInboxViewModel(repository: MockNotificationInboxRepository()),
            userBlockingCoordinator: UserBlockingCoordinator(repository: MockUserBlockingRepository())
        )
    }
    .environmentObject(AuthState())
}
