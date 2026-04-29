import SwiftUI

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("selectedAppLanguage") private var selectedLanguageCode = AppLanguage.stored.rawValue
    @AppStorage("selectedAppAppearance") private var selectedAppearanceCode = AppAppearance.stored.rawValue
    private let container: AppContainer
    @StateObject private var homeViewModel: HomeViewModel
    @StateObject private var newsViewModel: NewsViewModel
    @StateObject private var eventsViewModel: EventsViewModel
    @StateObject private var organizationsViewModel: OrganizationsViewModel
    @StateObject private var marketplaceViewModel: MarketplaceViewModel
    @StateObject private var infoViewModel: InfoViewModel
    @StateObject private var profileViewModel: ProfileViewModel

    init(container: AppContainer) {
        self.container = container
        _homeViewModel = StateObject(wrappedValue: HomeViewModel(
            userRepository: container.userRepository,
            newsRepository: container.newsRepository,
            eventRepository: container.eventRepository,
            organizationRepository: container.organizationRepository,
            marketplaceRepository: container.marketplaceRepository
        ))
        _newsViewModel = StateObject(wrappedValue: NewsViewModel(repository: container.newsRepository))
        _eventsViewModel = StateObject(wrappedValue: EventsViewModel(repository: container.eventRepository))
        _organizationsViewModel = StateObject(wrappedValue: OrganizationsViewModel(repository: container.organizationRepository))
        _marketplaceViewModel = StateObject(wrappedValue: MarketplaceViewModel(repository: container.marketplaceRepository))
        _infoViewModel = StateObject(wrappedValue: InfoViewModel(repository: container.infoRepository))
        _profileViewModel = StateObject(wrappedValue: ProfileViewModel(repository: container.userRepository))
    }

    var body: some View {
        TabView {
            rootTabs
        }
        .tint(AppTheme.primaryBlue)
        .preferredColorScheme(selectedAppearance.colorScheme)
        .environment(\.locale, Locale(identifier: selectedLanguageCode))
        .onChange(of: profileViewModel.settings.language) { _, newLanguage in
            selectedLanguageCode = newLanguage.rawValue
            LocalizationStore.language = newLanguage
            UserSettings.stored = profileViewModel.settings
            homeViewModel.reload()
            newsViewModel.reload()
            eventsViewModel.reload()
            organizationsViewModel.reload()
            marketplaceViewModel.reload()
            infoViewModel.reload()
            profileViewModel.reload()
        }
        .onChange(of: profileViewModel.settings.appearance) { _, newAppearance in
            selectedAppearanceCode = newAppearance.rawValue
            UserSettings.stored = profileViewModel.settings
        }
    }

    private var selectedAppearance: AppAppearance {
        AppAppearance(rawValue: selectedAppearanceCode) ?? .system
    }

    @ViewBuilder
    private var rootTabs: some View {
        homeTab
        newsTab
        eventsTab

        if horizontalSizeClass == .compact {
            compactCommunityTab
        } else {
            organizationsTab
            marketplaceTab
            infoTab
        }

        profileTab
    }

    private var homeTab: some View {
        NavigationStack {
            HomeView(viewModel: homeViewModel)
        }
        .tabItem {
            Label(AppStrings.Tabs.home, systemImage: "house.fill")
        }
    }

    private var newsTab: some View {
        NavigationStack {
            NewsListView(
                viewModel: newsViewModel,
                newsRepository: container.newsRepository,
                onNewsChanged: {
                    homeViewModel.reload()
                }
            )
        }
        .tabItem {
            Label(AppStrings.Tabs.news, systemImage: "newspaper.fill")
        }
    }

    private var eventsTab: some View {
        NavigationStack {
            EventsListView(
                viewModel: eventsViewModel,
                eventRepository: container.eventRepository,
                onEventPublished: {
                    homeViewModel.reload()
                },
                onEventDeleted: {
                    homeViewModel.reload()
                }
            )
        }
        .tabItem {
            Label(AppStrings.Tabs.events, systemImage: "calendar")
        }
    }

    private var organizationsTab: some View {
        NavigationStack {
            OrganizationsListView(viewModel: organizationsViewModel)
        }
        .tabItem {
            Label(AppStrings.Tabs.organizations, systemImage: "building.2.fill")
        }
    }

    private var marketplaceTab: some View {
        NavigationStack {
            MarketplaceListView(viewModel: marketplaceViewModel)
        }
        .tabItem {
            Label(AppStrings.Tabs.marketplace, systemImage: "basket.fill")
        }
    }

    private var infoTab: some View {
        NavigationStack {
            InfoView(viewModel: infoViewModel)
        }
        .tabItem {
            Label(AppStrings.Tabs.info, systemImage: "info.circle.fill")
        }
    }

    private var compactCommunityTab: some View {
        NavigationStack {
            CommunityHubView(
                organizationsViewModel: organizationsViewModel,
                marketplaceViewModel: marketplaceViewModel,
                infoViewModel: infoViewModel
            )
        }
        .tabItem {
            Label(AppStrings.Tabs.community, systemImage: "person.3.fill")
        }
    }

    private var profileTab: some View {
        NavigationStack {
            ProfileView(viewModel: profileViewModel)
        }
        .tabItem {
            Label(AppStrings.Tabs.profile, systemImage: "person.crop.circle.fill")
        }
    }
}

private struct CommunityHubView: View {
    @ObservedObject var organizationsViewModel: OrganizationsViewModel
    @ObservedObject var marketplaceViewModel: MarketplaceViewModel
    @ObservedObject var infoViewModel: InfoViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GradientHeroCard(
                    title: AppStrings.Community.title,
                    subtitle: AppStrings.Community.subtitle
                ) {
                    EmptyView()
                }

                communityLink(
                    title: AppStrings.Tabs.organizations,
                    subtitle: organizationsSubtitle,
                    systemImage: "building.2.fill"
                ) {
                    OrganizationsListView(viewModel: organizationsViewModel)
                }

                communityLink(
                    title: AppStrings.Tabs.marketplace,
                    subtitle: marketplaceSubtitle,
                    systemImage: "basket.fill"
                ) {
                    MarketplaceListView(viewModel: marketplaceViewModel)
                }

                communityLink(
                    title: AppStrings.Tabs.info,
                    subtitle: AppStrings.Info.placeholderTitle,
                    systemImage: "info.circle.fill"
                ) {
                    InfoView(viewModel: infoViewModel)
                }
            }
            .padding()
        }
        .background(AppTheme.subtleGradient.ignoresSafeArea())
        .navigationTitle(AppStrings.Community.title)
    }

    private var organizationsSubtitle: String {
        AppStrings.homeHighlightOrganizations(organizationsViewModel.organizations.count)
    }

    private var marketplaceSubtitle: String {
        AppStrings.homeHighlightMarketplace(marketplaceViewModel.items.count)
    }

    private func communityLink<Destination: View>(
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            CommunityCard {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryBlue)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView(container: .development)
}
