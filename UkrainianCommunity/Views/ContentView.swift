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
        _homeViewModel = StateObject(wrappedValue: HomeViewModel())
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
        .onReceive(NotificationCenter.default.publisher(for: .moderationStatusDidChange)) { _ in
            Task {
                await newsViewModel.refresh()
                await eventsViewModel.refresh()
                await organizationsViewModel.refresh()
                await marketplaceViewModel.refresh()
            }
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
            HomeView(
                viewModel: homeViewModel,
                newsViewModel: newsViewModel,
                eventsViewModel: eventsViewModel,
                organizationsViewModel: organizationsViewModel,
                marketplaceViewModel: marketplaceViewModel
            )
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
                onNewsPublished: {
                    await newsViewModel.refresh()
                },
                onNewsChanged: {}
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
                    await eventsViewModel.refresh()
                },
                onEventDeleted: {}
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
                    Text(communityOverviewText)
                        .font(.subheadline.weight(.semibold))
                }

                VStack(alignment: .leading, spacing: 14) {
                    communitySectionHeader(
                        title: AppStrings.Tabs.organizations,
                        subtitle: organizationsSubtitle,
                        systemImage: "building.2.fill"
                    ) {
                        OrganizationsListView(viewModel: organizationsViewModel)
                    }

                    if organizationsViewModel.isLoading && latestOrganizations.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    } else if organizationsViewModel.error != nil && latestOrganizations.isEmpty {
                        CommunityCard {
                            Text(AppStrings.Organizations.loadUnknownError)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else if latestOrganizations.isEmpty {
                        CommunityCard {
                            Text(AppStrings.Organizations.empty)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(latestOrganizations) { organization in
                            NavigationLink {
                                OrganizationDetailView(viewModel: organizationsViewModel, organizationID: organization.id)
                            } label: {
                                CommunityOrganizationPreviewCard(organization: organization)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    communitySectionHeader(
                        title: AppStrings.Tabs.marketplace,
                        subtitle: marketplaceSubtitle,
                        systemImage: "basket.fill"
                    ) {
                        MarketplaceListView(viewModel: marketplaceViewModel)
                    }

                    if marketplaceViewModel.isLoading && latestMarketplaceItems.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    } else if marketplaceViewModel.error != nil && latestMarketplaceItems.isEmpty {
                        CommunityCard {
                            Text(AppStrings.Marketplace.loadUnknownError)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else if latestMarketplaceItems.isEmpty {
                        CommunityCard {
                            Text(AppStrings.Marketplace.empty)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(latestMarketplaceItems) { item in
                            NavigationLink {
                                MarketplaceDetailView(viewModel: marketplaceViewModel, itemID: item.id)
                            } label: {
                                CommunityMarketplacePreviewCard(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                communitySectionHeader(
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
        .task {
            async let organizationsLoad: Void = organizationsViewModel.loadIfNeeded()
            async let marketplaceLoad: Void = marketplaceViewModel.loadIfNeeded()
            _ = await (organizationsLoad, marketplaceLoad)
        }
    }

    private var organizationsSubtitle: String {
        AppStrings.homeHighlightOrganizations(organizationsViewModel.organizations.count)
    }

    private var marketplaceSubtitle: String {
        AppStrings.homeHighlightMarketplace(marketplaceViewModel.items.count)
    }

    private var latestOrganizations: [Organization] {
        Array(organizationsViewModel.organizations.prefix(2))
    }

    private var latestMarketplaceItems: [MarketplaceItem] {
        Array(marketplaceViewModel.items.prefix(2))
    }

    private var communityOverviewText: String {
        let resourceCount = organizationsViewModel.organizations.count + marketplaceViewModel.items.count
        return resourceCount > 0 ? AppStrings.homeHighlightOrganizations(resourceCount) : AppStrings.Community.subtitle
    }

    private func communitySectionHeader<Destination: View>(
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(title, systemImage: systemImage)
                        .font(.headline)
                        .foregroundStyle(AppTheme.primaryBlue)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct CommunityOrganizationPreviewCard: View {
    let organization: Organization

    var body: some View {
        CommunityCard {
            RemoteCardImage(imageURL: organization.imageURL, height: 160, source: "CommunityOrganizationPreviewCard")

            Text(organization.name)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(organization.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            MetadataRow(label: AppStrings.Common.city, value: organization.city, systemImage: "mappin")
        }
    }
}

private struct CommunityMarketplacePreviewCard: View {
    let item: MarketplaceItem

    var body: some View {
        CommunityCard {
            RemoteCardImage(imageURL: item.imageURL, height: 160, source: "CommunityMarketplacePreviewCard")

            Text(item.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(item.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(alignment: .center, spacing: 12) {
                Text(item.city)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(CurrencyFormatter.priceString(for: item.price, currencyCode: item.currency))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryBlue)
            }
        }
    }
}

#Preview {
    ContentView(container: .development)
}
