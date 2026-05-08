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
    @State private var selectedTab: AppTab = .home
    @State private var homeNavigationRootID = UUID()
    @State private var eventsNavigationRootID = UUID()
    @State private var organizationsNavigationRootID = UUID()
    @State private var guideNavigationRootID = UUID()
    @State private var profileNavigationRootID = UUID()

    init(container: AppContainer) {
        self.container = container
        _homeViewModel = StateObject(wrappedValue: HomeViewModel(
            newsRepository: container.newsRepository,
            eventRepository: container.eventRepository,
            organizationRepository: container.organizationRepository
        ))
        _newsViewModel = StateObject(wrappedValue: NewsViewModel(repository: container.newsRepository))
        _eventsViewModel = StateObject(wrappedValue: EventsViewModel(repository: container.eventRepository))
        _organizationsViewModel = StateObject(wrappedValue: OrganizationsViewModel(repository: container.organizationRepository))
        _infoViewModel = StateObject(wrappedValue: InfoViewModel(repository: container.infoRepository))
        _profileViewModel = StateObject(wrappedValue: ProfileViewModel(
            repository: container.userRepository,
            feedbackRepository: container.feedbackRepository
        ))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            rootTabs
        }
        .tint(AppTheme.primaryBlue)
        .preferredColorScheme(selectedAppearance.colorScheme)
        .environment(\.locale, Locale(identifier: selectedLanguageCode))
        .onChange(of: selectedTab) { _, newTab in
            resetNavigationStack(for: newTab)
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
    }

    private var selectedAppearance: AppAppearance {
        AppAppearance(rawValue: selectedAppearanceCode) ?? .system
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
        NavigationStack {
            HomeView(
                viewModel: homeViewModel,
                newsViewModel: newsViewModel,
                eventsViewModel: eventsViewModel,
                organizationsViewModel: organizationsViewModel
            )
        }
        .accessibilityIdentifier("screen.home")
        .id(homeNavigationRootID)
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
                onEventPublished: {},
                onEventDeleted: {}
            )
        }
        .accessibilityIdentifier("screen.events")
        .id(eventsNavigationRootID)
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
                onOrganizationSaved: {},
                onOrganizationDeleted: {}
            )
        }
        .accessibilityIdentifier("screen.organizations")
        .id(organizationsNavigationRootID)
        .tabItem {
            Label(AppStrings.Tabs.organizations, systemImage: "building.2.fill")
                .accessibilityIdentifier("tab.organizations")
        }
        .tag(AppTab.organizations)
    }

    private var infoTab: some View {
        NavigationStack {
            InfoView(viewModel: infoViewModel)
        }
        .accessibilityIdentifier("screen.guide")
        .id(guideNavigationRootID)
        .tabItem {
            Label(AppStrings.Tabs.info, systemImage: "info.circle.fill")
                .accessibilityIdentifier("tab.guide")
        }
        .tag(AppTab.guide)
    }

    private var profileTab: some View {
        NavigationStack {
            ProfileView(viewModel: profileViewModel)
        }
        .accessibilityIdentifier("screen.profile")
        .id(profileNavigationRootID)
        .tabItem {
            Label(AppStrings.Tabs.profile, systemImage: "person.crop.circle.fill")
                .accessibilityIdentifier("tab.profile")
        }
        .tag(AppTab.profile)
    }

    private func resetNavigationStack(for tab: AppTab) {
        switch tab {
        case .home:
            homeNavigationRootID = UUID()
        case .events:
            eventsNavigationRootID = UUID()
        case .organizations:
            organizationsNavigationRootID = UUID()
        case .guide:
            guideNavigationRootID = UUID()
        case .profile:
            profileNavigationRootID = UUID()
        }
    }
}

#Preview {
    ContentView(container: .development)
}
