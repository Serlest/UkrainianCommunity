import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.openURL) private var openURL
    private enum AppTab: Hashable {
        case home
        case events
        case organizations
        case guide
        case profile
    }

    @AppStorage("selectedAppLanguage") private var selectedLanguageCode = AppLanguage.stored.rawValue
    @AppStorage("selectedAppAppearance") private var selectedAppearanceCode = AppAppearance.stored.rawValue
    private let container: AppContainer
    @StateObject private var homeViewModel: HomeViewModel
    @StateObject private var newsViewModel: NewsViewModel
    @StateObject private var eventsViewModel: EventsViewModel
    @StateObject private var organizationsViewModel: OrganizationsViewModel
    @StateObject private var guideReaderViewModel: GuideReaderViewModel
    @StateObject private var profileViewModel: ProfileViewModel
    @StateObject private var notificationInboxViewModel: NotificationInboxViewModel
    @StateObject private var notificationPopupCoordinator: NotificationPopupCoordinatorService
    @StateObject private var remoteNotificationRouteCoordinator = RemoteNotificationRouteCoordinator.shared
    @StateObject private var accountStatusMonitor = AccountStatusMonitorService()
    @StateObject private var legalComplianceMonitor: LegalComplianceMonitorService
    @State private var tabSelectionCoordinator = AppTabSelectionCoordinator()
    @State private var selectedTab: AppTab = .home
    @State private var isShowingNotificationInbox = false
    @State private var homeNavigationPath: [HomeFeedDestinationReference] = []
    @State private var eventsNavigationPath: [EventNavigationRoute] = []
    @State private var organizationsNavigationPath: [OrganizationNavigationRoute] = []
    @State private var profileNavigationPath: [ProfileNavigationRoute] = []
    @State private var guideBannerCategoryTarget: GuideCategory?
    @State private var guideMaterialTargetID: String?
    @State private var homeScrollResetToken = 0
    @State private var eventsScrollResetToken = 0
    @State private var organizationsScrollResetToken = 0
    @State private var homeSearchResetToken = 0
    @State private var eventsSearchResetToken = 0
    @State private var organizationsSearchResetToken = 0
    @State private var guideScrollResetToken = 0
    @State private var guideNavigationResetToken = 0
    @State private var profileScrollResetToken = 0
    @State private var lastHandledAuthSessionKey: String?
    @State private var notificationRouteErrorMessage: String?
    private let featuredBannerActionResolver = FeaturedBannerActionResolver()

    init(container: AppContainer) {
        self.container = container
        _homeViewModel = StateObject(wrappedValue: HomeViewModel(
            newsRepository: container.newsRepository,
            eventRepository: container.eventRepository,
            organizationRepository: container.organizationRepository
        ))
        _newsViewModel = StateObject(wrappedValue: NewsViewModel(
            repository: container.newsRepository,
            analyticsService: container.analyticsService
        ))
        _eventsViewModel = StateObject(wrappedValue: EventsViewModel(
            repository: container.eventRepository,
            notificationPreferencesRepository: container.notificationPreferencesRepository,
            localEventReminderService: container.localEventReminderService,
            analyticsService: container.analyticsService
        ))
        _organizationsViewModel = StateObject(wrappedValue: OrganizationsViewModel(
            repository: container.organizationRepository,
            notificationInboxRepository: container.notificationInboxRepository,
            analyticsService: container.analyticsService
        ))
        _guideReaderViewModel = StateObject(wrappedValue: GuideReaderViewModel(
            repository: FirestoreGuideRepository(),
            analyticsService: container.analyticsService
        ))
        _profileViewModel = StateObject(wrappedValue: ProfileViewModel(
            repository: container.userRepository,
            feedbackRepository: container.feedbackRepository,
            notificationPreferencesRepository: container.notificationPreferencesRepository,
            notificationPermissionService: container.notificationPermissionService,
            localEventReminderService: container.localEventReminderService
        ))
        _notificationInboxViewModel = StateObject(wrappedValue: NotificationInboxViewModel(
            repository: container.notificationInboxRepository
        ))
        _notificationPopupCoordinator = StateObject(wrappedValue: NotificationPopupCoordinatorService(
            repository: container.notificationInboxRepository
        ))
        _legalComplianceMonitor = StateObject(wrappedValue: LegalComplianceMonitorService(
            legalDocumentRepository: container.legalDocumentRepository,
            userRepository: container.userRepository
        ))
        RemoteNotificationRegistrationService.shared.configure(repository: container.notificationPushTokenRepository)
    }

    var body: some View {
        TabView(selection: tabSelection) {
            rootTabs
        }
        .background {
            ActiveTabReselectionObserver {
                handleActiveTabReselection()
            }
            .frame(width: 0, height: 0)
        }
        .tint(AppTheme.primaryBlue)
        .preferredColorScheme(selectedAppearance.colorScheme)
        .environment(\.locale, Locale(identifier: selectedLanguageCode))
        .environment(\.appNotificationBellConfiguration, notificationBellConfiguration)
        .task(id: authSessionKey) {
            notificationPopupCoordinator.configure(userID: notificationInboxUserID)
            await notificationInboxViewModel.configure(userID: notificationInboxUserID)
            accountStatusMonitor.configure(userID: notificationInboxUserID, authState: authState)
            await configureRemoteNotifications(for: notificationInboxUserID)
            handlePendingRemoteNotificationRouteIfReady()
        }
        .task(id: legalComplianceKey) {
            await legalComplianceMonitor.configure(user: authState.user)
        }
        .onChange(of: authSessionKey) { _, newKey in
            handleAuthIdentityChange(for: newKey)
        }
        .onChange(of: notificationInboxViewModel.snapshotVersion) { _, _ in
            bridgeNotificationInboxSnapshotToPopupCoordinator()
        }
        .onChange(of: remoteNotificationRouteCoordinator.pendingRoute) { _, _ in
            handlePendingRemoteNotificationRouteIfReady()
        }
        .onChange(of: profileViewModel.settings.language) { _, newLanguage in
            selectedLanguageCode = newLanguage.rawValue
            LocalizationStore.language = newLanguage
            UserSettings.stored = profileViewModel.settings
            newsViewModel.reload()
            eventsViewModel.reload()
            organizationsViewModel.reload()
            profileViewModel.reload()
        }
        .onChange(of: profileViewModel.settings.appearance) { _, newAppearance in
            selectedAppearanceCode = newAppearance.rawValue
            UserSettings.stored = profileViewModel.settings
        }
        .onReceive(NotificationCenter.default.publisher(for: .moderationStatusDidChange)) { _ in
            Task {
                await newsViewModel.refresh()
                await eventsViewModel.refresh()
                await organizationsViewModel.refresh()
            }
        }
        .sheet(item: $authState.presentedAuthFlow) { destination in
            AuthFlowContainerView(initialDestination: destination)
                .environmentObject(authState)
        }
        .fullScreenCover(isPresented: $isShowingNotificationInbox) {
            NotificationInboxView(
                viewModel: notificationInboxViewModel,
                onNotificationTap: handleNotificationTap
            )
        }
        .sheet(item: $accountStatusMonitor.activeNotice) { notice in
            AccountStatusNoticeView(
                notice: notice,
                isAcknowledging: accountStatusMonitor.isAcknowledging,
                errorMessage: accountStatusMonitor.acknowledgementError,
                acknowledge: {
                    Task {
                        await accountStatusMonitor.acknowledgeActiveNotice()
                    }
                }
            )
            .interactiveDismissDisabled(true)
        }
        .fullScreenCover(item: $legalComplianceMonitor.activeRequirement) { requirement in
            LegalComplianceView(
                requirement: requirement,
                isAccepting: legalComplianceMonitor.isAccepting,
                errorMessage: legalComplianceMonitor.errorMessage,
                accept: {
                    Task {
                        await legalComplianceMonitor.acceptRequiredDocuments(authState: authState)
                    }
                },
                decline: {
                    legalComplianceMonitor.declineAndSignOut()
                }
            )
        }
        .sheet(item: Binding(
            get: { notificationPopupCoordinator.activeNotification },
            set: { _ in }
        )) { notification in
            NotificationPopupView(
                notification: notification,
                errorMessage: notificationPopupCoordinator.errorMessage,
                dismiss: {
                    Task {
                        await notificationPopupCoordinator.dismissActiveNotification(markRead: false)
                    }
                },
                performAction: {
                    Task {
                        await notificationPopupCoordinator.dismissActiveNotification(markRead: true)
                        handleNotificationTap(notification)
                    }
                }
            )
        }
        .appErrorDialog(Binding(
            get: {
                notificationRouteErrorMessage.map {
                    AppErrorDialog(
                        title: AppStrings.NotificationInbox.destinationUnavailableTitle,
                        message: $0
                    )
                }
            },
            set: { if $0 == nil { notificationRouteErrorMessage = nil } }
        ))
    }

    private var selectedAppearance: AppAppearance {
        AppAppearance(rawValue: selectedAppearanceCode) ?? .system
    }

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                if newTab == selectedTab {
                    handleActiveTabReselection()
                    return
                }

                tabSelectionCoordinator.recordTabSwitch()
                selectedTab = newTab
                scheduleNavigationReset(for: newTab, scrollToTop: false)
            }
        )
    }

    private func handleActiveTabReselection() {
        guard tabSelectionCoordinator.shouldHandleActiveTabReselection() else { return }
        scheduleNavigationReset(for: selectedTab, scrollToTop: true)
    }

    private var authSessionKey: String {
        if let userID = authState.user?.id, authState.isAuthenticated {
            return "authenticated:\(userID)"
        }

        switch authState.sessionState {
        case .guest:
            return "guest"
        case .restoring:
            return "loading:restoring"
        case .authenticated:
            return "loading:authenticated"
        case .verificationPending:
            return "verificationPending:\(authState.pendingVerificationEmail ?? "pending")"
        }
    }

    private var notificationInboxUserID: String? {
        guard authState.isAuthenticated else { return nil }
        return authState.user?.id
    }

    private var legalComplianceKey: String {
        guard authState.isAuthenticated, let user = authState.user else {
            return "guest"
        }

        return [
            user.id,
            user.acceptedTermsVersion ?? "",
            user.acceptedPrivacyVersion ?? ""
        ].joined(separator: ":")
    }

    private var notificationBellConfiguration: AppNotificationBellConfiguration {
        AppNotificationBellConfiguration(
            isVisible: notificationInboxUserID != nil,
            unreadCount: notificationInboxViewModel.unreadCount,
            action: {
                isShowingNotificationInbox = true
            }
        )
    }

    @ViewBuilder
    private var rootTabs: some View {
        homeTab
        eventsTab
        organizationsTab
        guideTab
        profileTab
    }

    private var homeTab: some View {
        NavigationStack(path: $homeNavigationPath) {
            HomeView(
                viewModel: homeViewModel,
                newsViewModel: newsViewModel,
                eventsViewModel: eventsViewModel,
                organizationsViewModel: organizationsViewModel,
                newsRepository: container.newsRepository,
                featuredBannerRepository: container.featuredBannerRepository,
                featuredBannerCache: container.featuredBannerCache,
                navigationPath: $homeNavigationPath,
                onFeaturedBannerTap: handleFeaturedBannerTap,
                scrollResetToken: homeScrollResetToken,
                searchResetToken: homeSearchResetToken
            )
        }
        .environment(\.appNotificationBellConfiguration, notificationBellConfiguration)
        .accessibilityIdentifier("screen.home")
        .tabItem {
            Label(AppStrings.Tabs.home, systemImage: "house.fill")
                .accessibilityIdentifier("tab.home")
        }
        .tag(AppTab.home)
    }

    private var eventsTab: some View {
        NavigationStack(path: $eventsNavigationPath) {
            EventsListView(
                viewModel: eventsViewModel,
                eventRepository: container.eventRepository,
                featuredBannerRepository: container.featuredBannerRepository,
                featuredBannerCache: container.featuredBannerCache,
                navigationPath: $eventsNavigationPath,
                onEventPublished: {},
                onEventDeleted: {},
                onFeaturedBannerTap: handleFeaturedBannerTap,
                scrollResetToken: eventsScrollResetToken,
                searchResetToken: eventsSearchResetToken
            )
        }
        .environment(\.appNotificationBellConfiguration, notificationBellConfiguration)
        .accessibilityIdentifier("screen.events")
        .tabItem {
            Label(AppStrings.Tabs.events, systemImage: "calendar")
                .accessibilityIdentifier("tab.events")
        }
        .tag(AppTab.events)
    }

    private var organizationsTab: some View {
        NavigationStack(path: $organizationsNavigationPath) {
            OrganizationsListView(
                viewModel: organizationsViewModel,
                newsViewModel: newsViewModel,
                eventsViewModel: eventsViewModel,
                featuredBannerRepository: container.featuredBannerRepository,
                featuredBannerCache: container.featuredBannerCache,
                navigationPath: $organizationsNavigationPath,
                onOrganizationSaved: {},
                onOrganizationDeleted: {},
                onFeaturedBannerTap: handleFeaturedBannerTap,
                scrollResetToken: organizationsScrollResetToken,
                searchResetToken: organizationsSearchResetToken
            )
        }
        .environment(\.appNotificationBellConfiguration, notificationBellConfiguration)
        .accessibilityIdentifier("screen.organizations")
        .tabItem {
            Label(AppStrings.Tabs.organizations, systemImage: "building.2.fill")
                .accessibilityIdentifier("tab.organizations")
        }
        .tag(AppTab.organizations)
    }

    private var guideTab: some View {
        NavigationStack {
            InfoView(
                guideReaderViewModel: guideReaderViewModel,
                featuredBannerRepository: container.featuredBannerRepository,
                featuredBannerCache: container.featuredBannerCache,
                feedbackRepository: container.feedbackRepository,
                onFeaturedBannerTap: handleFeaturedBannerTap,
                guideBannerCategoryTarget: $guideBannerCategoryTarget,
                guideMaterialTargetID: $guideMaterialTargetID,
                navigationResetToken: guideNavigationResetToken,
                scrollResetToken: guideScrollResetToken
            )
        }
        .environment(\.appNotificationBellConfiguration, notificationBellConfiguration)
        .accessibilityIdentifier("screen.guide")
        .tabItem {
            Label(AppStrings.Tabs.info, systemImage: "info.circle.fill")
                .accessibilityIdentifier("tab.guide")
        }
        .tag(AppTab.guide)
    }

    private var profileTab: some View {
        NavigationStack(path: $profileNavigationPath) {
            ProfileView(
                viewModel: profileViewModel,
                feedbackRepository: container.feedbackRepository,
                newsRepository: container.newsRepository,
                eventRepository: container.eventRepository,
                organizationRepository: container.organizationRepository,
                newsViewModel: newsViewModel,
                eventsViewModel: eventsViewModel,
                organizationsViewModel: organizationsViewModel,
                guideReaderViewModel: guideReaderViewModel,
                featuredBannerRepository: container.featuredBannerRepository,
                featuredBannerCache: container.featuredBannerCache,
                legalDocumentRepository: container.legalDocumentRepository,
                ownerAnalyticsRepository: container.ownerAnalyticsRepository,
                notificationInboxRepository: container.notificationInboxRepository,
                notificationInboxViewModel: notificationInboxViewModel,
                localEventReminderService: container.localEventReminderService,
                onNotificationTap: handleNotificationTap,
                onBrowseDestinationSelected: handleProfileBrowseDestination,
                navigationPath: $profileNavigationPath,
                scrollResetToken: profileScrollResetToken
            )
        }
        .environment(\.appNotificationBellConfiguration, notificationBellConfiguration)
        .accessibilityIdentifier("screen.profile")
        .tabItem {
            Label(AppStrings.Tabs.profile, systemImage: "person.crop.circle.fill")
                .accessibilityIdentifier("tab.profile")
        }
        .tag(AppTab.profile)
    }

    private func handleAuthIdentityChange(for key: String) {
        guard lastHandledAuthSessionKey != key else { return }
        guard lastHandledAuthSessionKey != nil else {
            lastHandledAuthSessionKey = key
            return
        }

        lastHandledAuthSessionKey = key

        selectTabIfNeeded(.home)
        isShowingNotificationInbox = false
        resetNavigationStateAfterAuthChange()
        authState.dismissAuthFlow()

        homeViewModel.resetForAuthChange()
        newsViewModel.resetForAuthChange()
        eventsViewModel.resetForAuthChange()
        organizationsViewModel.resetForAuthChange()
        guideReaderViewModel.resetSavedMaterialsState()
        profileViewModel.resetForAuthChange()

        Task {
            notificationPopupCoordinator.configure(userID: notificationInboxUserID)
            await notificationInboxViewModel.configure(userID: notificationInboxUserID)
            await configureRemoteNotifications(for: notificationInboxUserID)
            await newsViewModel.refresh()
            await eventsViewModel.refresh()
            await organizationsViewModel.refresh()
            if authState.isAuthenticated {
                await profileViewModel.refresh()
            }
        }
    }

    private func scheduleNavigationReset(for tab: AppTab, scrollToTop: Bool) {
        Task { @MainActor in
            await Task.yield()
            guard selectedTab == tab else { return }
            resetNavigationState(for: tab)
            resetSearchState(for: tab)
            if scrollToTop {
                scheduleScrollReset(for: tab)
            }
        }
    }

    private func resetNavigationState(for tab: AppTab) {
        switch tab {
        case .home:
            if !homeNavigationPath.isEmpty {
                homeNavigationPath.removeAll()
            }
        case .events:
            if !eventsNavigationPath.isEmpty {
                eventsNavigationPath.removeAll()
            }
        case .organizations:
            if !organizationsNavigationPath.isEmpty {
                organizationsNavigationPath.removeAll()
            }
        case .guide:
            guideBannerCategoryTarget = nil
            guideMaterialTargetID = nil
            guideNavigationResetToken += 1
        case .profile:
            if !profileNavigationPath.isEmpty {
                profileNavigationPath.removeAll()
            }
        }
    }

    private func resetSearchState(for tab: AppTab) {
        switch tab {
        case .home:
            homeSearchResetToken += 1
        case .events:
            eventsSearchResetToken += 1
        case .organizations:
            organizationsSearchResetToken += 1
        case .guide, .profile:
            break
        }
    }

    private func resetNavigationStateAfterAuthChange() {
        if !homeNavigationPath.isEmpty {
            homeNavigationPath.removeAll()
        }
        if !eventsNavigationPath.isEmpty {
            eventsNavigationPath.removeAll()
        }
        if !organizationsNavigationPath.isEmpty {
            organizationsNavigationPath.removeAll()
        }
        if !profileNavigationPath.isEmpty {
            profileNavigationPath.removeAll()
        }

        scheduleScrollReset(for: selectedTab)
    }

    private func selectTabIfNeeded(_ tab: AppTab) {
        guard selectedTab != tab else { return }
        tabSelectionCoordinator.recordTabSwitch()
        selectedTab = tab
    }

    private func scheduleScrollReset(for tab: AppTab) {
        Task { @MainActor in
            await Task.yield()
            switch tab {
            case .home:
                homeScrollResetToken += 1
            case .events:
                eventsScrollResetToken += 1
            case .organizations:
                organizationsScrollResetToken += 1
            case .guide:
                guideScrollResetToken += 1
            case .profile:
                profileScrollResetToken += 1
            }
        }
    }

    private func configureRemoteNotifications(for userID: String?) async {
        RemoteNotificationRegistrationService.shared.configureUser(userID)
        guard let userID else { return }

        do {
            let preferences = try await container.notificationPreferencesRepository.fetchNotificationPreferences(userID: userID)
            RemoteNotificationRegistrationService.shared.configureUser(
                userID,
                notificationsEnabled: preferences.notificationsEnabled
            )
        } catch {
            #if DEBUG
            print("[Notifications] Notification preferences fetch failed during remote registration setup: \(error)")
            #endif
        }
    }

    private func bridgeNotificationInboxSnapshotToPopupCoordinator() {
        guard notificationInboxViewModel.snapshotVersion > 0,
              let userID = notificationInboxUserID else { return }

        notificationPopupCoordinator.receiveInboxSnapshot(
            notificationInboxViewModel.notifications,
            userID: userID
        )
    }

    private func handleFeaturedBannerTap(_ banner: FeaturedBanner) {
        switch featuredBannerActionResolver.resolve(banner) {
        case .noAction:
            return
        case let .openURL(url):
            openURL(url)
        case let .openNews(id):
            selectTabIfNeeded(.home)
            homeNavigationPath = [.news(id: id)]
        case let .openEvent(id):
            selectTabIfNeeded(.events)
            eventsNavigationPath = [EventNavigationRoute(eventID: id)]
        case let .openOrganization(id):
            Task {
                guard let organization = await organizationsViewModel.resolveOrganization(id: id) else { return }
                selectTabIfNeeded(.organizations)
                organizationsNavigationPath = [OrganizationNavigationRoute(organizationID: organization.id)]
            }
        case let .openGuide(targetID):
            if let targetID, let category = GuideCategory(rawValue: targetID) {
                guideBannerCategoryTarget = category
            } else {
                #if DEBUG
                if let targetID {
                    debugPrint("Guide featured banner deep link target is unsupported and falls back to root:", targetID)
                }
                #endif
                guideBannerCategoryTarget = nil
            }
            selectTabIfNeeded(.guide)
        }
    }

    private func handleNotificationTap(_ notification: AppNotification) {
        guard notification.actionType != .none else { return }

        isShowingNotificationInbox = false

        switch notification.actionType {
        case .none:
            return
        case .openNews:
            routeToNews(notification)
        case .openFeedback:
            routeToFeedback(notification)
        case .openOrganization:
            routeToOrganization(notification)
        case .openOrganizationRequest:
            routeToOrganizationRequest(notification)
        case .openEvent:
            routeToEvent(notification)
        case .openGuideMaterial:
            routeToGuideMaterial(notification)
        case .openGuideReport:
            selectTabIfNeeded(.profile)
            profileNavigationPath = [.guideManagement]
        case .openLegalDocuments:
            selectTabIfNeeded(.profile)
            profileNavigationPath = [.legal(.terms)]
        case .openProfile:
            selectTabIfNeeded(.profile)
            if !profileNavigationPath.isEmpty {
                profileNavigationPath.removeAll()
            }
        case .openURL:
            routeToURL(notification)
        }
    }

    private func routeToFeedback(_ notification: AppNotification) {
        routeToFeedback(feedbackID: notificationTargetID(notification))
    }

    private func routeToFeedback(feedbackID: String?) {
        selectTabIfNeeded(.profile)
        if PermissionService.canManageFeedback(user: authState.user) {
            profileNavigationPath = [.feedbackInbox]
        } else if let userID = authState.user?.id {
            profileNavigationPath = [.myFeedback(userID: userID)]
        } else {
            profileNavigationPath = [.feedbackInbox]
        }
    }

    private func routeToNews(_ notification: AppNotification) {
        guard let newsID = notificationTargetID(notification) else {
            showNotificationRouteUnavailable()
            return
        }

        routeToNews(newsID: newsID)
    }

    private func routeToNews(newsID: String) {
        selectTabIfNeeded(.home)
        homeNavigationPath = [.news(id: newsID)]
    }

    private func routeToOrganizationRequest(_ notification: AppNotification) {
        switch notification.type {
        case .organizationRequestApproved:
            if let organizationID = notificationTargetID(notification) {
                routeToOrganization(organizationID: organizationID)
            } else {
                routeToOrganizationManagement()
            }
        case .organizationRequestNeedsRevision, .organizationRequestRejected:
            routeToOrganizationManagement()
        default:
            routeToOrganizationManagement()
        }
    }

    private func routeToOrganizationManagement() {
        selectTabIfNeeded(.profile)
        profileNavigationPath = [.organizationManagement]
    }

    private func routeToOrganization(_ notification: AppNotification) {
        guard let organizationID = notificationTargetID(notification) else {
            showNotificationRouteUnavailable()
            return
        }

        routeToOrganization(organizationID: organizationID)
    }

    private func routeToOrganization(organizationID: String) {
        selectTabIfNeeded(.organizations)
        organizationsNavigationPath = [OrganizationNavigationRoute(organizationID: organizationID)]
    }

    private func routeToEvent(_ notification: AppNotification) {
        guard let eventID = notificationTargetID(notification) else {
            showNotificationRouteUnavailable()
            return
        }

        routeToEvent(eventID: eventID)
    }

    private func routeToEvent(eventID: String) {
        selectTabIfNeeded(.events)
        eventsNavigationPath = [EventNavigationRoute(eventID: eventID)]
    }

    private func routeToGuideMaterial(_ notification: AppNotification) {
        guard let materialID = guideMaterialTargetID(notification) else {
            showNotificationRouteUnavailable()
            return
        }

        guideBannerCategoryTarget = nil
        guideMaterialTargetID = materialID
        selectTabIfNeeded(.guide)
    }

    private func routeToURL(_ notification: AppNotification) {
        guard let urlString = notificationURLString(notification),
              let url = URL(string: urlString) else {
            showNotificationRouteUnavailable()
            return
        }

        openURL(url)
    }

    private func handlePendingRemoteNotificationRouteIfReady() {
        guard authState.sessionState != .restoring,
              let route = remoteNotificationRouteCoordinator.pendingRoute else {
            return
        }

        handleRemoteNotificationRoute(route)
        remoteNotificationRouteCoordinator.consume(route)
    }

    private func handleRemoteNotificationRoute(_ route: RemoteNotificationRoute) {
        isShowingNotificationInbox = false

        switch route.destination {
        case .openNews(let newsId):
            routeToNews(newsID: newsId)
        case .openEvent(let eventId):
            routeToEvent(eventID: eventId)
        case .openOrganization(let organizationId):
            routeToOrganization(organizationID: organizationId)
        case .openFeedback(let feedbackId):
            routeToFeedback(feedbackID: feedbackId)
        case .openProfile:
            selectTabIfNeeded(.profile)
            if !profileNavigationPath.isEmpty {
                profileNavigationPath.removeAll()
            }
        case .openURL(let urlString):
            guard let url = URL(string: urlString) else {
                showNotificationRouteUnavailable()
                return
            }
            openURL(url)
        case .systemAnnouncement:
            if notificationInboxUserID != nil {
                selectTabIfNeeded(.profile)
                profileNavigationPath = [.notifications]
            }
        }
    }

    private func notificationURLString(_ notification: AppNotification) -> String? {
        [
            notification.actionTargetId,
            notification.metadata["url"],
            notification.payload["url"]
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }
    }

    private func notificationTargetID(_ notification: AppNotification) -> String? {
        [
            notification.actionTargetId,
            notification.sourceId,
            notification.payload["routeTargetId"],
            notification.metadata["routeTargetId"],
            notification.metadata["targetId"],
            notification.metadata["targetID"],
            notification.metadata["url"]
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }
    }

    private func guideMaterialTargetID(_ notification: AppNotification) -> String? {
        [
            notification.actionTargetId,
            notification.sourceId,
            notification.metadata["guideMaterialId"],
            notification.metadata["guideMaterialID"],
            notification.metadata["materialId"],
            notification.metadata["materialID"],
            notification.metadata["articleId"],
            notification.metadata["articleID"],
            notification.metadata["targetId"],
            notification.metadata["targetID"],
            notification.payload["guideMaterialId"],
            notification.payload["guideMaterialID"],
            notification.payload["materialId"],
            notification.payload["materialID"],
            notification.payload["articleId"],
            notification.payload["articleID"],
            notification.payload["targetId"],
            notification.payload["targetID"]
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }
    }

    private func handleProfileBrowseDestination(_ destination: ProfileBrowseDestination) {
        switch destination {
        case .home:
            selectTabIfNeeded(.home)
        case .events:
            selectTabIfNeeded(.events)
        case .organizations:
            selectTabIfNeeded(.organizations)
        case .guide:
            selectTabIfNeeded(.guide)
        }
    }

    private func showNotificationRouteUnavailable() {
        notificationRouteErrorMessage = AppStrings.NotificationInbox.destinationUnavailableMessage
    }
}

@MainActor
private final class AppTabSelectionCoordinator {
    private var lastTabSwitchTime = Date.timeIntervalSinceReferenceDate
    private var lastActiveTabResetTime = Date.distantPast.timeIntervalSinceReferenceDate
    private let tabSwitchQuietInterval: TimeInterval = 0.35
    private let activeResetQuietInterval: TimeInterval = 0.35

    func recordTabSwitch() {
        lastTabSwitchTime = Date.timeIntervalSinceReferenceDate
    }

    func shouldHandleActiveTabReselection() -> Bool {
        let now = Date.timeIntervalSinceReferenceDate
        guard now - lastTabSwitchTime >= tabSwitchQuietInterval,
              now - lastActiveTabResetTime >= activeResetQuietInterval else {
            return false
        }

        lastActiveTabResetTime = now
        return true
    }
}

@MainActor
private struct ActiveTabReselectionObserver: UIViewControllerRepresentable {
    let onReselect: @MainActor () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        context.coordinator.attach(from: viewController, onReselect: onReselect)
        return viewController
    }

    func updateUIViewController(_ viewController: UIViewController, context: Context) {
        context.coordinator.attach(from: viewController, onReselect: onReselect)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator: NSObject, UITabBarControllerDelegate {
        private weak var tabBarController: UITabBarController?
        private weak var lastSelectedViewController: UIViewController?
        private var onReselect: (@MainActor () -> Void)?

        func attach(from viewController: UIViewController, onReselect: @escaping @MainActor () -> Void) {
            self.onReselect = onReselect

            Task { @MainActor in
                guard let tabBarController = viewController.nearestTabBarController(),
                      self.tabBarController !== tabBarController else { return }
                self.tabBarController = tabBarController
                self.lastSelectedViewController = tabBarController.selectedViewController
                tabBarController.delegate = self
            }
        }

        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            defer { lastSelectedViewController = viewController }

            guard lastSelectedViewController === viewController else { return }
            onReselect?()
        }
    }
}

private extension UIViewController {
    func nearestTabBarController() -> UITabBarController? {
        if let tabBarController {
            return tabBarController
        }

        if let parent {
            return parent.nearestTabBarController()
        }

        return nil
    }
}

#Preview {
    ContentView(container: .development)
}
