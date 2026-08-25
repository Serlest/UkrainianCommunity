import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.openURL) private var openURL
    private enum AppTab: Hashable {
        case home
        case events
        case organizations
        case profile
    }

    @AppStorage("selectedAppLanguage") private var selectedLanguageCode = AppLanguage.stored.rawValue
    @AppStorage("selectedAppAppearance") private var selectedAppearanceCode = AppAppearance.stored.rawValue
    private let container: AppContainer
    @StateObject private var homeViewModel: HomeViewModel
    @StateObject private var newsViewModel: NewsViewModel
    @StateObject private var eventsViewModel: EventsViewModel
    @StateObject private var organizationsViewModel: OrganizationsViewModel
    @StateObject private var profileViewModel: ProfileViewModel
    @StateObject private var notificationInboxViewModel: NotificationInboxViewModel
    @StateObject private var notificationPopupCoordinator: NotificationPopupCoordinatorService
    @StateObject private var remoteNotificationRouteCoordinator = RemoteNotificationRouteCoordinator.shared
    @StateObject private var accountStatusMonitor = AccountStatusMonitorService()
    @StateObject private var legalComplianceMonitor: LegalComplianceMonitorService
    @StateObject private var contentReportCoordinator: ContentReportCoordinator
    @StateObject private var userBlockingCoordinator: UserBlockingCoordinator
    @State private var tabSelectionCoordinator = AppTabSelectionCoordinator()
    @State private var selectedTab: AppTab = .home
    @State private var isShowingNotificationInbox = false
    @State private var homeNavigationPath: [HomeFeedDestinationReference] = []
    @State private var eventsNavigationPath: [EventNavigationRoute] = []
    @State private var organizationsNavigationPath: [OrganizationNavigationRoute] = []
    @State private var profileNavigationPath: [ProfileNavigationRoute] = []
    @State private var homeScrollResetToken = 0
    @State private var eventsScrollResetToken = 0
    @State private var organizationsScrollResetToken = 0
    @State private var homeSearchResetToken = 0
    @State private var eventsSearchResetToken = 0
    @State private var organizationsSearchResetToken = 0
    @State private var profileScrollResetToken = 0
    @State private var lastHandledAuthIdentityResetKey: String?
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
        _profileViewModel = StateObject(wrappedValue: ProfileViewModel(
            repository: container.userRepository,
            feedbackRepository: container.feedbackRepository,
            notificationPreferencesRepository: container.notificationPreferencesRepository,
            notificationPermissionService: container.notificationPermissionService,
            localEventReminderService: container.localEventReminderService,
            eventRepository: container.eventRepository
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
        _contentReportCoordinator = StateObject(wrappedValue: ContentReportCoordinator(
            repository: container.contentSafetyRepository
        ))
        _userBlockingCoordinator = StateObject(wrappedValue: UserBlockingCoordinator(
            repository: container.userBlockingRepository
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
        .environment(\.contentReportPresentation, ContentReportPresentationConfiguration(
            present: contentReportCoordinator.present
        ))
        .environment(\.userBlockingPresentation, UserBlockingPresentationConfiguration(
            present: userBlockingCoordinator.present
        ))
        .task(id: authTaskKey) {
            await SessionDataCache.shared.resetForAuthChange(userID: notificationInboxUserID)
            notificationPopupCoordinator.configure(userID: notificationInboxUserID)
            await notificationInboxViewModel.configure(userID: notificationInboxUserID)
            accountStatusMonitor.configure(userID: notificationInboxUserID, authState: authState)
            await configureRemoteNotifications(for: notificationInboxUserID)
            await userBlockingCoordinator.configure(userID: notificationInboxUserID)
            handlePendingRemoteNotificationRouteIfReady()
        }
        .task(id: legalComplianceKey) {
            await legalComplianceMonitor.configure(user: authState.user)
        }
        .onChange(of: authIdentityResetKey, initial: true) { _, newKey in
            handleAuthIdentityChange(for: newKey)
        }
        .onChange(of: notificationInboxViewModel.snapshotVersion) { _, _ in
            bridgeNotificationInboxSnapshotToPopupCoordinator()
        }
        .onChange(of: userBlockingCoordinator.blockedUserIDs) { oldIDs, newIDs in
            applyContentVisibility(blockedUserIDs: newIDs)
            guard !newIDs.isSuperset(of: oldIDs) else { return }
            Task {
                await refreshPublicContentAfterUnblock()
            }
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
        .sheet(item: $contentReportCoordinator.target) { target in
            ContentReportSheet(target: target, coordinator: contentReportCoordinator)
                .presentationDetents([.large])
        }
        .confirmationDialog(
            AppStrings.Safety.blockConfirmationTitle,
            isPresented: Binding(
                get: { userBlockingCoordinator.pendingTarget != nil },
                set: { isPresented in
                    guard !isPresented else { return }
                    Task { @MainActor in
                        await Task.yield()
                        userBlockingCoordinator.pendingTarget = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(AppStrings.Safety.blockAction, role: .destructive) {
                Task { await userBlockingCoordinator.confirmPendingBlock() }
            }
            Button(AppStrings.Common.cancel, role: .cancel) {
                userBlockingCoordinator.pendingTarget = nil
            }
        } message: {
            Text(AppStrings.Safety.blockConfirmationMessage(
                userBlockingCoordinator.pendingTarget?.contextTitle ?? ""
            ))
        }
        .alert(
            AppStrings.Safety.blockErrorTitle,
            isPresented: Binding(
                get: { userBlockingCoordinator.errorMessage != nil },
                set: { isPresented in
                    guard !isPresented else { return }
                    Task { @MainActor in
                        await Task.yield()
                        userBlockingCoordinator.errorMessage = nil
                    }
                }
            )
        ) {
            Button(AppStrings.Common.ok, role: .cancel) {
                userBlockingCoordinator.errorMessage = nil
            }
        } message: {
            Text(userBlockingCoordinator.errorMessage ?? AppStrings.Safety.blockErrorUnknown)
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
                        await accountStatusMonitor.completeActiveNotice()
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
                    Task {
                        await legalComplianceMonitor.declineAndSignOut()
                    }
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

    private var authTaskKey: String {
        ContentAuthLifecyclePolicy.taskKey(
            sessionState: authState.sessionState,
            authenticatedUserID: notificationInboxUserID,
            pendingSessionUserID: authState.pendingSessionUserID,
            pendingVerificationEmail: authState.pendingVerificationEmail
        )
    }

    private var authIdentityResetKey: String {
        ContentAuthLifecyclePolicy.identityResetKey(
            sessionState: authState.sessionState,
            authenticatedUserID: notificationInboxUserID
        )
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
                featuredBannerRepository: container.featuredBannerRepository,
                featuredBannerCache: container.featuredBannerCache,
                legalDocumentRepository: container.legalDocumentRepository,
                ownerAnalyticsRepository: container.ownerAnalyticsRepository,
                analyticsService: container.analyticsService,
                notificationInboxRepository: container.notificationInboxRepository,
                notificationInboxViewModel: notificationInboxViewModel,
                userBlockingCoordinator: userBlockingCoordinator,
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

    private func applyContentVisibility(blockedUserIDs: Set<String>) {
        let policy = ContentVisibilityPolicy(blockedUserIDs: blockedUserIDs)
        newsViewModel.applyContentVisibility(policy)
        eventsViewModel.applyContentVisibility(policy)
        organizationsViewModel.applyContentVisibility(policy)
    }

    private func refreshPublicContentAfterUnblock() async {
        await newsViewModel.refresh()
        await eventsViewModel.refresh()
        await organizationsViewModel.refresh()
        applyContentVisibility(blockedUserIDs: userBlockingCoordinator.blockedUserIDs)
    }

    private func handleAuthIdentityChange(for key: String) {
        guard lastHandledAuthIdentityResetKey != key else { return }
        guard lastHandledAuthIdentityResetKey != nil else {
            lastHandledAuthIdentityResetKey = key
            return
        }

        lastHandledAuthIdentityResetKey = key

        selectTabIfNeeded(.home)
        isShowingNotificationInbox = false
        resetNavigationStateAfterAuthChange()

        homeViewModel.resetForAuthChange()
        newsViewModel.resetForAuthChange()
        eventsViewModel.resetForAuthChange()
        organizationsViewModel.resetForAuthChange()
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
        case .profile:
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
            guard !Task.isCancelled,
                  authState.isAuthenticated,
                  authState.user?.id == userID else { return }
            RemoteNotificationRegistrationService.shared.configureUser(
                userID,
                notificationsEnabled: preferences.notificationsEnabled
            )
            await reconcileEventReminders(for: userID, preferences: preferences)
        } catch is CancellationError {
        } catch {
            #if DEBUG
            print("[Notifications] Notification preferences fetch failed during remote registration setup: \(error)")
            #endif
        }
    }

    private func reconcileEventReminders(
        for userID: String?,
        preferences: NotificationPreferences
    ) async {
        guard let userID else { return }
        do {
            let registeredEvents = try await container.eventRepository.fetchRegisteredEvents()
            guard authState.isAuthenticated, authState.user?.id == userID else { return }
            try await container.localEventReminderService.reconcileEventReminders(
                events: registeredEvents,
                userID: userID,
                preferences: preferences
            )
        } catch {
            #if DEBUG
            print("[Notifications] Failed to reconcile event reminders: \(error)")
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

    private func routeToURL(_ notification: AppNotification) {
        guard let urlString = notificationURLString(notification),
              let url = URL(string: urlString) else {
            showNotificationRouteUnavailable()
            return
        }

        openURL(url)
    }

    private func handlePendingRemoteNotificationRouteIfReady() {
        guard ContentAuthLifecyclePolicy.canHandlePendingRoute(in: authState.sessionState),
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
        case .openOrganizationRequest(let organizationId):
            if route.type == .organizationRequestApproved, let organizationId {
                routeToOrganization(organizationID: organizationId)
            } else {
                routeToOrganizationManagement()
            }
        case .openFeedback(let feedbackId):
            routeToFeedback(feedbackID: feedbackId)
        case .openLegalDocuments:
            selectTabIfNeeded(.profile)
            profileNavigationPath = [.legal(.terms)]
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

    private func handleProfileBrowseDestination(_ destination: ProfileBrowseDestination) {
        switch destination {
        case .home:
            selectTabIfNeeded(.home)
        case .events:
            selectTabIfNeeded(.events)
        case .organizations:
            selectTabIfNeeded(.organizations)
        }
    }

    private func showNotificationRouteUnavailable() {
        notificationRouteErrorMessage = AppStrings.NotificationInbox.destinationUnavailableMessage
    }
}

enum ContentAuthLifecyclePolicy {
    static func taskKey(
        sessionState: AuthSessionState,
        authenticatedUserID: String?,
        pendingSessionUserID: String?,
        pendingVerificationEmail: String?
    ) -> String {
        if let authenticatedUserID {
            return "authenticated:\(authenticatedUserID)"
        }

        switch sessionState {
        case .guest:
            return "guest"
        case .restoring:
            return "loading:restoring"
        case .authenticating:
            return "loading:authenticating:\(pendingSessionUserID ?? "pending")"
        case .authenticated:
            return "loading:authenticated"
        case .verificationPending:
            return "verificationPending:\(pendingVerificationEmail ?? "pending")"
        case .sessionUnavailable:
            return "sessionUnavailable:\(pendingSessionUserID ?? "pending")"
        }
    }

    static func identityResetKey(
        sessionState: AuthSessionState,
        authenticatedUserID: String?
    ) -> String {
        guard sessionState == .authenticated,
              let authenticatedUserID else { return "guest" }
        return "authenticated:\(authenticatedUserID)"
    }

    static func canHandlePendingRoute(in sessionState: AuthSessionState) -> Bool {
        switch sessionState {
        case .guest, .authenticated:
            return true
        case .restoring, .authenticating, .verificationPending, .sessionUnavailable:
            return false
        }
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
