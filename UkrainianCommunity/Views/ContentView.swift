import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var authState: AuthState
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
    @StateObject private var infoViewModel: InfoViewModel
    @StateObject private var profileViewModel: ProfileViewModel
    @StateObject private var notificationInboxViewModel: NotificationInboxViewModel
    @State private var selectedTab: AppTab = .home
    @State private var isShowingNotificationInbox = false
    @State private var homeNavigationPath: [HomeFeedDestinationReference] = []
    @State private var lastHandledAuthSessionKey: String?

    init(container: AppContainer) {
        self.container = container
        _homeViewModel = StateObject(wrappedValue: HomeViewModel(
            newsRepository: container.newsRepository,
            eventRepository: container.eventRepository,
            organizationRepository: container.organizationRepository,
            homeBannerService: container.homeBannerService
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
        _infoViewModel = StateObject(wrappedValue: InfoViewModel(repository: container.infoRepository))
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
        TabView(selection: $selectedTab) {
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
            infoViewModel.reload()
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
        infoTab
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
                navigationPath: $homeNavigationPath
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
        NavigationStack {
            EventsListView(
                viewModel: eventsViewModel,
                eventRepository: container.eventRepository,
                bannerService: container.homeBannerService,
                onEventPublished: {},
                onEventDeleted: {}
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
        NavigationStack {
            OrganizationsListView(
                viewModel: organizationsViewModel,
                bannerService: container.homeBannerService,
                onOrganizationSaved: {},
                onOrganizationDeleted: {}
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

    private var infoTab: some View {
        NavigationStack {
            InfoView(
                viewModel: infoViewModel,
                bannerService: container.homeBannerService
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
        NavigationStack {
            ProfileView(
                viewModel: profileViewModel,
                feedbackRepository: container.feedbackRepository,
                eventRepository: container.eventRepository,
                organizationRepository: container.organizationRepository,
                notificationInboxRepository: container.notificationInboxRepository,
                localEventReminderService: container.localEventReminderService
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
}

#Preview {
    ContentView(container: .development)
}
