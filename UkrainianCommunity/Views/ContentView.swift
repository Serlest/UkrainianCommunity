import SwiftUI

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
    @StateObject private var guideViewModel: LegacyGuideListViewModel
    @StateObject private var profileViewModel: ProfileViewModel
    @StateObject private var notificationInboxViewModel: NotificationInboxViewModel
    @State private var selectedTab: AppTab = .home
    @State private var isShowingNotificationInbox = false
    @State private var homeNavigationPath: [HomeFeedDestinationReference] = []
    @State private var eventsNavigationPath: [EventNavigationRoute] = []
    @State private var organizationsNavigationPath: [OrganizationNavigationRoute] = []
    @State private var profileNavigationPath: [ProfileNavigationRoute] = []
    @State private var guideBannerCategoryTarget: GuideCategory?
    @State private var homeScrollResetToken = 0
    @State private var eventsScrollResetToken = 0
    @State private var organizationsScrollResetToken = 0
    @State private var guideScrollResetToken = 0
    @State private var profileScrollResetToken = 0
    @State private var lastHandledAuthSessionKey: String?
    private let featuredBannerActionResolver = FeaturedBannerActionResolver()

    init(container: AppContainer) {
        self.container = container
        _homeViewModel = StateObject(wrappedValue: HomeViewModel(
            newsRepository: container.newsRepository,
            eventRepository: container.eventRepository,
            organizationRepository: container.organizationRepository
        ))
        _newsViewModel = StateObject(wrappedValue: NewsViewModel(repository: container.newsRepository))
        _eventsViewModel = StateObject(wrappedValue: EventsViewModel(
            repository: container.eventRepository,
            notificationPreferencesRepository: container.notificationPreferencesRepository,
            localEventReminderService: container.localEventReminderService
        ))
        _organizationsViewModel = StateObject(wrappedValue: OrganizationsViewModel(
            repository: container.organizationRepository,
            notificationInboxRepository: container.notificationInboxRepository
        ))
        _guideViewModel = StateObject(wrappedValue: LegacyGuideListViewModel(repository: container.guideRepository))
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
    }

    var body: some View {
        TabView(selection: tabSelection) {
            rootTabs
        }
        .tint(AppTheme.primaryBlue)
        .preferredColorScheme(selectedAppearance.colorScheme)
        .environment(\.locale, Locale(identifier: selectedLanguageCode))
        .environment(\.appNotificationBellConfiguration, notificationBellConfiguration)
        .task(id: authSessionKey) {
            await notificationInboxViewModel.configure(userID: notificationInboxUserID)
        }
        .onChange(of: authSessionKey) { _, newKey in
            handleAuthIdentityChange(for: newKey)
        }
        .onChange(of: profileViewModel.settings.language) { _, newLanguage in
            selectedLanguageCode = newLanguage.rawValue
            LocalizationStore.language = newLanguage
            UserSettings.stored = profileViewModel.settings
            homeViewModel.reload()
            newsViewModel.reload()
            eventsViewModel.reload()
            organizationsViewModel.reload()
            guideViewModel.reload()
            profileViewModel.reload()
        }
        .onChange(of: profileViewModel.settings.appearance) { _, newAppearance in
            selectedAppearanceCode = newAppearance.rawValue
            UserSettings.stored = profileViewModel.settings
        }
        .onReceive(NotificationCenter.default.publisher(for: .moderationStatusDidChange)) { _ in
            Task {
                await homeViewModel.refresh()
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
            NotificationInboxView(viewModel: notificationInboxViewModel)
        }
    }

    private var selectedAppearance: AppAppearance {
        AppAppearance(rawValue: selectedAppearanceCode) ?? .system
    }

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                guard newTab != selectedTab else { return }
                let previousTab = selectedTab
                selectedTab = newTab
                resetNavigationPathAfterTabSwitch(for: previousTab)
            }
        )
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
        }
    }

    private var notificationInboxUserID: String? {
        guard authState.isAuthenticated else { return nil }
        return authState.user?.id
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
                guideViewModel: guideViewModel,
                newsRepository: container.newsRepository,
                featuredBannerRepository: container.featuredBannerRepository,
                navigationPath: $homeNavigationPath,
                onFeaturedBannerTap: handleFeaturedBannerTap,
                scrollResetToken: homeScrollResetToken
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
                navigationPath: $eventsNavigationPath,
                onEventPublished: {},
                onEventDeleted: {},
                onFeaturedBannerTap: handleFeaturedBannerTap,
                scrollResetToken: eventsScrollResetToken
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
                featuredBannerRepository: container.featuredBannerRepository,
                navigationPath: $organizationsNavigationPath,
                onOrganizationSaved: {},
                onOrganizationDeleted: {},
                onFeaturedBannerTap: handleFeaturedBannerTap,
                scrollResetToken: organizationsScrollResetToken
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
                viewModel: guideViewModel,
                featuredBannerRepository: container.featuredBannerRepository,
                feedbackRepository: container.feedbackRepository,
                onFeaturedBannerTap: handleFeaturedBannerTap,
                guideBannerCategoryTarget: $guideBannerCategoryTarget,
                scrollResetToken: guideScrollResetToken
            )
        }
        .id(guideScrollResetToken)
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
                guideRepository: container.guideRepository,
                featuredBannerRepository: container.featuredBannerRepository,
                notificationInboxRepository: container.notificationInboxRepository,
                localEventReminderService: container.localEventReminderService,
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
        lastHandledAuthSessionKey = key

        selectedTab = .home
        isShowingNotificationInbox = false
        homeNavigationPath.removeAll()
        eventsNavigationPath.removeAll()
        organizationsNavigationPath.removeAll()
        profileNavigationPath.removeAll()
        homeScrollResetToken += 1
        eventsScrollResetToken += 1
        organizationsScrollResetToken += 1
        guideScrollResetToken += 1
        profileScrollResetToken += 1
        authState.dismissAuthFlow()

        homeViewModel.resetForAuthChange()
        newsViewModel.resetForAuthChange()
        eventsViewModel.resetForAuthChange()
        organizationsViewModel.resetForAuthChange()
        profileViewModel.resetForAuthChange()

        Task {
            await notificationInboxViewModel.configure(userID: notificationInboxUserID)
            await homeViewModel.refresh()
            await newsViewModel.refresh()
            await eventsViewModel.refresh()
            await organizationsViewModel.refresh()
            if authState.isAuthenticated {
                await profileViewModel.refresh()
            }
        }
    }

    private func resetNavigationPath(for tab: AppTab) {
        switch tab {
        case .home:
            homeNavigationPath.removeAll()
            homeScrollResetToken += 1
        case .events:
            eventsNavigationPath.removeAll()
            eventsScrollResetToken += 1
        case .organizations:
            organizationsNavigationPath.removeAll()
            organizationsScrollResetToken += 1
        case .guide:
            guideScrollResetToken += 1
        case .profile:
            profileNavigationPath.removeAll()
            profileScrollResetToken += 1
        }
    }

    private func resetNavigationPathAfterTabSwitch(for tab: AppTab) {
        DispatchQueue.main.async {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                resetNavigationPath(for: tab)
            }
        }
    }

    private func handleFeaturedBannerTap(_ banner: FeaturedBanner) {
        switch featuredBannerActionResolver.resolve(banner) {
        case .noAction:
            return
        case let .openURL(url):
            openURL(url)
        case let .openNews(id):
            selectedTab = .home
            homeNavigationPath = [.news(id: id)]
        case let .openEvent(id):
            selectedTab = .events
            eventsNavigationPath = [EventNavigationRoute(eventID: id)]
        case let .openOrganization(id):
            Task {
                guard let organization = await organizationsViewModel.resolveOrganization(id: id) else { return }
                selectedTab = .organizations
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
            selectedTab = .guide
        }
    }
}

#Preview {
    ContentView(container: .development)
}
