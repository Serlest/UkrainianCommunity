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
    case moderationTools
    case guideManagement
    case userManagement
    case featuredBannerManagement
    case legalDocumentManagement
    case donationSettings
    case feedbackInbox
    case systemLogs(SystemLogsAccessMode)
    case notifications
    case myFeedback(userID: String)
    case legal(LegalDocumentKind)
}

struct ProfileView: View {
    @ObservedObject var viewModel: ProfileViewModel
    private let feedbackRepository: FeedbackRepository
    private let newsRepository: NewsRepository
    private let eventRepository: EventRepository
    private let organizationRepository: OrganizationRepository
    private let guideRepository: LegacyGuideRepository
    private let featuredBannerRepository: FeaturedBannerRepository
    private let legalDocumentRepository: LegalDocumentRepository
    private let donationConfigRepository: DonationConfigRepository
    private let notificationInboxRepository: NotificationInboxRepository
    private let onNotificationTap: (AppNotification) -> Void
    @EnvironmentObject var authState: AuthState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @StateObject private var registrationsViewModel: MyRegistrationsViewModel
    @StateObject private var myFeedbackViewModel: MyFeedbackViewModel
    @StateObject private var notificationInboxViewModel: NotificationInboxViewModel
    @StateObject private var ownerOrganizationsViewModel: OrganizationsViewModel
    @StateObject private var ownerVisibilityViewModel: OwnerProfileVisibilityViewModel
    @StateObject private var donationConfigViewModel: DonationConfigViewModel
    @ObservedObject private var newsViewModel: NewsViewModel
    @ObservedObject private var eventsViewModel: EventsViewModel
    @ObservedObject private var organizationsViewModel: OrganizationsViewModel
    @ObservedObject private var guideReaderViewModel: GuideReaderViewModel
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
        guideReaderViewModel: GuideReaderViewModel? = nil,
        guideRepository: LegacyGuideRepository = LegacyFirestoreGuideRepository(),
        featuredBannerRepository: FeaturedBannerRepository = FirestoreFeaturedBannerRepository(),
        legalDocumentRepository: LegalDocumentRepository = FirestoreLegalDocumentRepository(),
        donationConfigRepository: DonationConfigRepository = FirestoreDonationConfigRepository(),
        notificationInboxRepository: NotificationInboxRepository = FirestoreNotificationInboxRepository(),
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
        self.guideReaderViewModel = guideReaderViewModel ?? GuideReaderViewModel(repository: FirestoreGuideRepository())
        self.guideRepository = guideRepository
        self.featuredBannerRepository = featuredBannerRepository
        self.legalDocumentRepository = legalDocumentRepository
        self.donationConfigRepository = donationConfigRepository
        self.notificationInboxRepository = notificationInboxRepository
        self.onNotificationTap = onNotificationTap
        self.scrollResetToken = scrollResetToken
        _navigationPath = navigationPath
        _registrationsViewModel = StateObject(wrappedValue: MyRegistrationsViewModel(
            repository: eventRepository,
            localEventReminderService: localEventReminderService
        ))
        _myFeedbackViewModel = StateObject(wrappedValue: MyFeedbackViewModel(repository: feedbackRepository))
        _notificationInboxViewModel = StateObject(wrappedValue: NotificationInboxViewModel(
            repository: notificationInboxRepository
        ))
        _ownerOrganizationsViewModel = StateObject(wrappedValue: OrganizationsViewModel(
            repository: organizationRepository,
            notificationInboxRepository: notificationInboxRepository
        ))
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
                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        Color.clear
                            .frame(height: 0)
                            .id(profileRootScrollTopID)

                        VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                            profileHeader

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
                        .padding(.bottom, AppTheme.homeBottomContentPadding + 32)
                        .frame(width: proxy.size.width, alignment: .topLeading)
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
        }
        .task {
            await viewModel.loadIfNeeded()
            await donationConfigViewModel.loadIfNeeded()
            if authState.isAuthenticated {
                await registrationsViewModel.loadIfNeeded()
                await registrationsViewModel.refreshIfStale()
                if let userID = authState.user?.id {
                    await myFeedbackViewModel.loadIfNeeded(userID: userID)
                    await notificationInboxViewModel.configure(userID: userID)
                    await viewModel.loadNotificationPreferencesIfNeeded(userID: userID)
                }
                await ownerOrganizationsViewModel.loadIfNeeded()
                await ownerOrganizationsViewModel.refreshIfStale()
                await loadOwnerVisibilityIfAllowed()
            } else {
                registrationsViewModel.resetForGuest()
                myFeedbackViewModel.reset()
                ownerVisibilityViewModel.reset()
            }
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
                await ownerOrganizationsViewModel.refresh()
                await refreshOwnerVisibilityIfAllowed()
            }
        }
        .onChange(of: authState.isAuthenticated) { _, isAuthenticated in
            Task {
                if isAuthenticated {
                    await registrationsViewModel.refresh()
                    if let userID = authState.user?.id {
                        await myFeedbackViewModel.refresh(userID: userID)
                        await notificationInboxViewModel.configure(userID: userID)
                        await viewModel.refreshNotificationPreferences(userID: userID)
                    }
                    await ownerOrganizationsViewModel.refresh()
                    await refreshOwnerVisibilityIfAllowed()
                } else {
                    registrationsViewModel.resetForGuest()
                    myFeedbackViewModel.reset()
                    await notificationInboxViewModel.configure(userID: nil)
                    ownerOrganizationsViewModel.resetForAuthChange()
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
                await notificationInboxViewModel.configure(userID: nil)
                ownerOrganizationsViewModel.resetForAuthChange()
                ownerVisibilityViewModel.reset()
                guard let newUserID else { return }
                await registrationsViewModel.refresh()
                await myFeedbackViewModel.refresh(userID: newUserID)
                await notificationInboxViewModel.configure(userID: newUserID)
                await viewModel.refreshNotificationPreferences(userID: newUserID)
                await ownerOrganizationsViewModel.refresh()
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
                await ownerOrganizationsViewModel.refresh()
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
        .observesKeyboardDismissTaps()
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
            OrganizationManagementHubView()
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
                guideReaderViewModel: guideReaderViewModel,
                feedbackRepository: feedbackRepository
            )
        case .followedOrganizations:
            FollowedOrganizationsView(
                organizationsViewModel: organizationsViewModel,
                organizationRepository: organizationRepository
            )
        case .recentViews:
            RecentViewsView(
                newsViewModel: newsViewModel,
                eventsViewModel: eventsViewModel,
                organizationsViewModel: organizationsViewModel
            )
        case .activityHistory:
            ActivityHistoryView(
                newsViewModel: newsViewModel,
                eventsViewModel: eventsViewModel,
                organizationsViewModel: organizationsViewModel
            )
        case .moderationTools:
            ModerationToolsView(
                organizationRepository: organizationRepository,
                notificationInboxRepository: notificationInboxRepository
            )
        case .guideManagement:
            GuideManagementView()
        case .userManagement:
            UserManagementView()
        case .featuredBannerManagement:
            FeaturedBannerManagementView(
                repository: featuredBannerRepository,
                newsRepository: newsRepository,
                eventRepository: eventRepository,
                organizationRepository: organizationRepository
            )
        case .legalDocumentManagement:
            LegalDocumentManagementView(repository: legalDocumentRepository)
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
        ZStack(alignment: .bottom) {
            AppBackgroundView()
                .allowsHitTesting(false)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    HStack(alignment: .center, spacing: AppTheme.pushedScreenHeaderSpacing) {
                        AppGlassIconButton(systemImage: "xmark", accessibilityLabel: AppStrings.Common.cancel) {
                            guard !viewModel.isSavingProfile else { return }
                            isShowingEditProfileSheet = false
                        }

                        Spacer(minLength: 0)
                    }

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
        .toolbar(.hidden, for: .navigationBar)
        .interactiveDismissDisabled(viewModel.isSavingProfile)
        .observesKeyboardDismissTaps()
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
                NavigationLink(value: ProfileNavigationRoute.notifications) {
                    ProfileModuleRow(
                        title: AppStrings.NotificationInbox.title,
                        subtitle: AppStrings.NotificationInbox.subtitle,
                        systemImage: "bell",
                        status: .available,
                        countBadge: notificationInboxViewModel.unreadCount
                    )
                }
                .buttonStyle(.plain)

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

        donationSupportSection
        guestSettingsSupportSection
    }

    @ViewBuilder
    private func userProfileContent(for user: AppUser) -> some View {
        if let profileDashboardMode {
            platformProfileContent(for: user, mode: profileDashboardMode)
        } else {
            ProfileHeroCard(
                user: user,
                readableFederalState: readableFederalState,
                onEditProfile: beginEditingProfile
            )

            quickActionsSection(for: user)
            donationSupportSection
            supportSection(for: user)
            settingsSection
            accountDeletionSection
            logoutSection
        }
    }

    @ViewBuilder
    private func platformProfileContent(for user: AppUser, mode: ProfileDashboardMode) -> some View {
        OwnerHeroCard(user: user, readableFederalState: readableFederalState, mode: mode)
        platformManagementSection
        quickActionsSection(for: user)
        donationSupportSection
        supportSection(for: user)
        settingsSection
        accountDeletionSection
        logoutSection
    }

    private func quickActionsSection(for user: AppUser, includeMyOrganizations: Bool = true) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: AppTheme.eventsMetadataSpacing),
                GridItem(.flexible(), spacing: AppTheme.eventsMetadataSpacing)
            ],
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

            NavigationLink(value: ProfileNavigationRoute.recentViews) {
                ProfileQuickActionCard(item: ProfileQuickActionItem(
                    title: AppStrings.Profile.recentlyViewed,
                    subtitle: AppStrings.Profile.recentlyViewedSubtitle,
                    systemImage: "clock.arrow.circlepath",
                    status: .available
                ))
            }
            .buttonStyle(.plain)

            NavigationLink(value: ProfileNavigationRoute.activityHistory) {
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

    private var moderatorQuickActionsSection: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: AppTheme.eventsMetadataSpacing),
                GridItem(.flexible(), spacing: AppTheme.eventsMetadataSpacing)
            ],
            spacing: AppTheme.eventsMetadataSpacing
        ) {
            NavigationLink(value: ProfileNavigationRoute.moderationTools) {
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
    private var platformManagementSection: some View {
        if hasPlatformManagementItems {
            ProfileSectionCard(title: platformManagementTitle, subtitle: platformManagementSubtitle) {
                VStack(spacing: AppTheme.eventsMetadataSpacing) {
                    if canShowAdminTools {
                        NavigationLink(value: ProfileNavigationRoute.userManagement) {
                            ProfileModuleRow(title: AppStrings.Profile.ownerUsers, subtitle: AppStrings.Profile.ownerUsersSubtitle, systemImage: "person.3", status: .active)
                        }
                        .buttonStyle(.plain)
                    }

                    if canShowGuideManagement {
                        NavigationLink(value: ProfileNavigationRoute.guideManagement) {
                            ProfileModuleRow(
                                title: AppStrings.GuideManagement.title,
                                subtitle: AppStrings.GuideManagement.entrySubtitle,
                                systemImage: "book.closed",
                                status: .available
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if canShowFeaturedBanners {
                        NavigationLink(value: ProfileNavigationRoute.featuredBannerManagement) {
                            ProfileModuleRow(
                                title: AppStrings.FeaturedManagement.profileEntryTitle,
                                subtitle: AppStrings.FeaturedManagement.profileEntrySubtitle,
                                systemImage: "sparkles.rectangle.stack",
                                status: .active
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if PermissionService.isAppOwner(user: permissionUser) {
                        NavigationLink(value: ProfileNavigationRoute.donationSettings) {
                            ProfileModuleRow(
                                title: DonationLocalization.publicSectionTitle(for: appLanguage),
                                subtitle: DonationLocalization.platformEntrySubtitle(for: appLanguage),
                                systemImage: "heart.circle",
                                status: .available
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink(value: ProfileNavigationRoute.legalDocumentManagement) {
                            ProfileModuleRow(
                                title: AppStrings.Profile.ownerLegalDocuments,
                                subtitle: AppStrings.Profile.ownerLegalDocumentsSubtitle,
                                systemImage: "doc.text.magnifyingglass",
                                status: .available
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink(value: ProfileNavigationRoute.systemLogs(.owner)) {
                            ProfileModuleRow(
                                title: AppStrings.SystemLogs.ownerTitle,
                                subtitle: AppStrings.SystemLogs.ownerProfileSubtitle,
                                systemImage: "doc.text.magnifyingglass",
                                status: .available
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if PermissionService.isAppAdmin(user: permissionUser) {
                        NavigationLink(value: ProfileNavigationRoute.systemLogs(.appAdmin)) {
                            ProfileModuleRow(
                                title: AppStrings.SystemLogs.appAdminTitle,
                                subtitle: AppStrings.SystemLogs.appAdminSubtitle,
                                systemImage: "doc.text.magnifyingglass",
                                status: .available
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if canShowOrganizationRequests {
                        NavigationLink(value: ProfileNavigationRoute.moderationTools) {
                            ProfileModuleRow(
                                title: AppStrings.Profile.ownerOrganizationRequests,
                                subtitle: AppStrings.Profile.moderatorOrganizationsReviewSubtitle,
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

    private var hasPlatformManagementItems: Bool {
        canShowAdminTools
            || canShowGuideManagement
            || canShowFeaturedBanners
            || PermissionService.isAppOwner(user: permissionUser)
            || canShowOrganizationRequests
            || canShowModerationTools
            || canShowFeedbackReports
    }

    private var platformManagementTitle: String {
        if PermissionService.isAppOwner(user: permissionUser) {
            return AppStrings.Profile.ownerPlatformManagement
        }
        if PermissionService.isAppAdmin(user: permissionUser) {
            return AppStrings.Profile.adminPlatformManagement
        }
        if PermissionService.isAppModerator(user: permissionUser) {
            return AppStrings.Profile.moderatorReviewQueues
        }
        return AppStrings.Profile.guideEditorManagement
    }

    private var platformManagementSubtitle: String {
        if PermissionService.isAppOwner(user: permissionUser) {
            return AppStrings.Profile.ownerPlatformManagementSubtitle
        }
        if PermissionService.isAppAdmin(user: permissionUser) {
            return AppStrings.Profile.adminAssistanceSubtitle
        }
        if PermissionService.isAppModerator(user: permissionUser) {
            return AppStrings.Profile.moderatorReviewQueuesSubtitle
        }
        return AppStrings.Profile.guideEditorManagementSubtitle
    }

    private var ownerPlatformManagementSection: some View {
        ProfileSectionCard(title: AppStrings.Profile.ownerPlatformManagement, subtitle: AppStrings.Profile.ownerPlatformManagementSubtitle) {
            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                NavigationLink(value: ProfileNavigationRoute.userManagement) {
                    ProfileModuleRow(title: AppStrings.Profile.ownerUsers, subtitle: AppStrings.Profile.ownerUsersSubtitle, systemImage: "person.3", status: canShowAdminTools ? .active : .locked)
                }
                .buttonStyle(.plain)

                if canShowGuideManagement {
                    NavigationLink(value: ProfileNavigationRoute.guideManagement) {
                        ProfileModuleRow(
                            title: AppStrings.GuideManagement.title,
                            subtitle: AppStrings.GuideManagement.entrySubtitle,
                            systemImage: "book.closed",
                            status: .available
                        )
                    }
                    .buttonStyle(.plain)
                }

                NavigationLink(value: ProfileNavigationRoute.featuredBannerManagement) {
                    ProfileModuleRow(
                        title: AppStrings.FeaturedManagement.profileEntryTitle,
                        subtitle: AppStrings.FeaturedManagement.profileEntrySubtitle,
                        systemImage: "sparkles.rectangle.stack",
                        status: canShowAdminTools ? .active : .locked
                    )
                }
                .buttonStyle(.plain)

                NavigationLink(value: ProfileNavigationRoute.moderationTools) {
                    ProfileModuleRow(
                        title: AppStrings.Profile.ownerOrganizationRequests,
                        subtitle: AppStrings.Profile.moderatorOrganizationsReviewSubtitle,
                        systemImage: "clock.badge.exclamationmark",
                        status: canShowOrganizationRequests ? .available : .locked,
                        countBadge: canShowOrganizationRequests ? ownerVisibilityViewModel.pendingOrganizationRequestCount : nil
                    )
                }
                .buttonStyle(.plain)

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
                    status: PermissionService.canManageOrganizationRequests(user: user) ? .active : .locked,
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

                NavigationLink(value: ProfileNavigationRoute.legal(.terms)) {
                    ProfileModuleRow(title: AppStrings.Settings.terms, subtitle: AppStrings.authCurrentTermsVersion(AuthService.currentTermsVersion), systemImage: "doc.text", status: .available)
                }
                .buttonStyle(.plain)

                NavigationLink(value: ProfileNavigationRoute.legal(.privacy)) {
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
                NavigationLink(value: ProfileNavigationRoute.myFeedback(userID: user.id)) {
                    ProfileModuleRow(
                        title: AppStrings.Feedback.myFeedbackTitle,
                        subtitle: AppStrings.Feedback.myFeedbackSubtitle,
                        systemImage: "tray.full",
                        status: .available
                    )
                }
                .buttonStyle(.plain)

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

                NavigationLink(value: ProfileNavigationRoute.legal(.terms)) {
                    ProfileModuleRow(title: AppStrings.Profile.termsOfUse, subtitle: AppStrings.authCurrentTermsVersion(AuthService.currentTermsVersion), systemImage: "doc.text", status: .available)
                }
                .buttonStyle(.plain)

                NavigationLink(value: ProfileNavigationRoute.legal(.privacy)) {
                    ProfileModuleRow(title: AppStrings.Profile.privacyPolicy, subtitle: AppStrings.authCurrentPrivacyVersion(AuthService.currentPrivacyVersion), systemImage: "lock.doc", status: .available)
                }
                .buttonStyle(.plain)

            }
        }
    }

    private var donationSupportSection: some View {
        ProfileSectionCard(title: DonationLocalization.publicSectionTitle(for: appLanguage)) {
            ProfileDonationSupportCard(config: donationConfigViewModel.config, language: appLanguage)
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


private struct ProfileDonationSupportCard: View {
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
                    .foregroundStyle(AppTheme.accentSupport)
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
            guideRepository: LegacyMockGuideRepository(),
            featuredBannerRepository: MockFeaturedBannerRepository(),
            notificationInboxRepository: MockNotificationInboxRepository()
        )
    }
    .environmentObject(AuthState())
}
