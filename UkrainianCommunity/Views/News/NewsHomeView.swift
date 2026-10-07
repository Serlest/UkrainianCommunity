import SwiftUI

private let newsHomeScrollTopID = "newsHomeScrollTop"

struct NewsHomeView: View {
    @EnvironmentObject private var authState: AuthState
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    @ObservedObject var newsViewModel: NewsViewModel
    @ObservedObject var eventsViewModel: EventsViewModel
    @ObservedObject var organizationsViewModel: OrganizationsViewModel
    @Binding var navigationPath: [HomeFeedDestinationReference]
    @Binding var selectedFederalState: AustrianFederalState?

    let onFeaturedBannerTap: (FeaturedBanner) -> Void
    let scrollResetToken: Int
    let searchResetToken: Int
    let isActive: Bool

    @StateObject private var featuredBannerViewModel: FeaturedBannerListViewModel
    @StateObject private var newsBrowser: NewsBrowseViewModel
    @State private var filter = NewsBrowseFilter()
    @State private var referenceDate = Date()
    @State private var isSearchPresented = false
    @State private var searchText = ""

    init(
        newsViewModel: NewsViewModel,
        eventsViewModel: EventsViewModel,
        organizationsViewModel: OrganizationsViewModel,
        newsRepository: NewsRepository,
        featuredBannerRepository: FeaturedBannerRepository,
        featuredBannerCache: FeaturedBannerCache = FeaturedBannerCache(),
        navigationPath: Binding<[HomeFeedDestinationReference]>,
        selectedFederalState: Binding<AustrianFederalState?> = .constant(nil),
        onFeaturedBannerTap: @escaping (FeaturedBanner) -> Void = { _ in },
        scrollResetToken: Int = 0,
        searchResetToken: Int = 0,
        isActive: Bool = true
    ) {
        self.newsViewModel = newsViewModel
        self.eventsViewModel = eventsViewModel
        self.organizationsViewModel = organizationsViewModel
        self.onFeaturedBannerTap = onFeaturedBannerTap
        self.scrollResetToken = scrollResetToken
        self.searchResetToken = searchResetToken
        self.isActive = isActive
        _navigationPath = navigationPath
        _selectedFederalState = selectedFederalState
        _newsBrowser = StateObject(wrappedValue: NewsBrowseViewModel(repository: newsRepository))
        _featuredBannerViewModel = StateObject(wrappedValue: FeaturedBannerListViewModel(
            repository: featuredBannerRepository, cache: featuredBannerCache
        ))
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0).id(newsHomeScrollTopID)

                    AppSearchableBrandHeader(
                        isSearchPresented: $isSearchPresented,
                        searchText: $searchText,
                        placeholder: AppStrings.Search.homePlaceholder,
                        collapseToken: searchResetToken,
                        creationKind: .news
                    )
                    .padding(.bottom, AppTheme.homeHeaderHeroSpacing)

                    featuredBanners
                        .padding(.bottom, featuredBannerViewModel.banners.isEmpty && featuredBannerViewModel.error == nil
                            ? 0 : AppTheme.homeSectionSpacing)

                    NewsHomeFilterRow(filter: $filter, selectedFederalState: $selectedFederalState,
                                      authenticated: authState.isAuthenticated)
                        .id(languageCode)
                        .padding(.bottom, AppTheme.homeSectionSpacing)

                    AppGroupedContentPlane(padding: AppTheme.homeFeedPlanePadding) {
                        newsContent
                            .id(languageCode)
                    }
                }
                .padding(.horizontal, AppTheme.pageHorizontal)
                .padding(.bottom, AppTheme.homeBottomContentPadding)
                .appCenteredContent(maxWidth: AppTheme.feedContentMaxWidth)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: scrollResetToken) {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { scrollProxy.scrollTo(newsHomeScrollTopID, anchor: .top) }
            }
        }
        .background(AppBackgroundView())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: HomeFeedDestinationReference.self) { destination in
            destinationView(for: destination)
        }
        .appRefreshable { await refresh() }
        .task(id: browseLoadKey) {
            guard isActive, isAuthBootstrapReady else { return }
            await newsBrowser.reload(browseQuery, visibility: newsViewModel.visibilityPolicy)
        }
        .task(id: bannerLoadKey) {
            guard isActive, isAuthBootstrapReady else { return }
            await featuredBannerViewModel.loadIfNeeded(for: .home, federalState: selectedFederalState)
            await featuredBannerViewModel.refreshIfStale(for: .home, federalState: selectedFederalState)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newsChanged)) { _ in
            guard isActive else { return }
            Task { await newsViewModel.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .organizationsChanged)) { _ in
            if isActive && filter.scope == .subscribed { referenceDate = Date() }
        }
        .onChange(of: newsViewModel.contentVersion) { _, _ in
            referenceDate = Date()
        }
        .onChange(of: authState.user?.id) { _, _ in
            newsBrowser.clear()
            filter.scope = .all
        }
        .observesKeyboardDismissTaps()
    }

    @ViewBuilder private var featuredBanners: some View {
        if !featuredBannerViewModel.banners.isEmpty {
            FeaturedBannerCarouselView(banners: featuredBannerViewModel.banners,
                                       sizing: .responsiveHero, onBannerTap: onFeaturedBannerTap)
        } else if let error = featuredBannerViewModel.error {
            FeaturedBannerLoadFailureView(error: error) {
                await featuredBannerViewModel.refresh(for: .home, federalState: selectedFederalState)
            }
        }
    }

    @ViewBuilder private var newsContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.feedRowSpacing) {
            Text([filter.period.title, NewsBrowseStrings.text(filter.oldestFirst ? "oldest" : "newest"),
                  filter.scope == .all ? nil : filter.scope.title].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .accessibilityIdentifier("home.news.summary")

            if filter.period == .custom {
                Text("\(LocalizationStore.dateString(from: filter.startDate, dateStyle: .medium, timeStyle: .none)) – \(LocalizationStore.dateString(from: filter.endDate, dateStyle: .medium, timeStyle: .none))")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            if let error = newsBrowser.error {
                ErrorStateCard(title: AppStrings.Tabs.home, message: error, retryTitle: AppStrings.News.retry) {
                    Task { await newsBrowser.loadMore(visibility: newsViewModel.visibilityPolicy) }
                }
            }

            ForEach(visiblePosts) { post in
                NavigationLink(value: HomeFeedDestinationReference.news(id: post.id)) {
                    NewsHomeCard(post: post)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.card.news-\(post.id)")
            }

            if newsBrowser.loading {
                ProgressView().frame(maxWidth: .infinity).accessibilityIdentifier("home.news.loading")
            } else if newsBrowser.hasMore {
                if visiblePosts.isEmpty {
                    Text(NewsBrowseStrings.text("continueHint")).font(.caption)
                }
                Button(NewsBrowseStrings.text("more")) {
                    Task { await newsBrowser.loadMore(visibility: newsViewModel.visibilityPolicy) }
                }
                .accessibilityIdentifier("home.news.more")
            } else if visiblePosts.isEmpty && newsBrowser.error == nil {
                Text(NewsBrowseStrings.text("empty")).accessibilityIdentifier("home.news.empty")
                if filter.period != .all {
                    Button(NewsBrowseStrings.text("expandPeriod")) { filter.period = .all }
                }
                Button(NewsBrowseStrings.text("reset")) {
                    filter = NewsBrowseFilter()
                    searchText = ""
                    selectedFederalState = nil
                }
                .accessibilityIdentifier("home.news.clear")
            }
        }
    }

    private var browseQuery: NewsBrowseQuery {
        NewsBrowseQuery(filter: filter, region: selectedFederalState, search: searchText,
                        accountKey: authBootstrapKey, referenceDate: referenceDate)
    }

    private var visiblePosts: [NewsPost] {
        newsViewModel.visibilityPolicy.visibleNews(newsBrowser.posts)
    }

    private var browseLoadKey: String { "\(browseQuery.hashValue):\(isActive)" }
    private var bannerLoadKey: String { "\(selectedFederalState?.rawValue ?? "allAustria"):\(isActive):\(authBootstrapKey)" }

    private var authBootstrapKey: String {
        switch authState.sessionState {
        case .restoring: "restoring"
        case .authenticating: "authenticating:\(authState.pendingSessionUserID ?? "pending")"
        case .guest: "guest"
        case .authenticated: "authenticated:\(authState.user?.id ?? "pending")"
        case .verificationPending: "verificationPending:\(authState.pendingVerificationEmail ?? "pending")"
        case .sessionUnavailable: "sessionUnavailable:\(authState.pendingSessionUserID ?? "pending")"
        }
    }

    private var isAuthBootstrapReady: Bool {
        authState.sessionState != .restoring && authState.sessionState != .authenticating
    }

    private func refresh() async {
        guard isAuthBootstrapReady else { return }
        referenceDate = Date()
        async let banners: Void = featuredBannerViewModel.refresh(for: .home, federalState: selectedFederalState)
        async let news: Void = newsBrowser.reload(browseQuery, visibility: newsViewModel.visibilityPolicy)
        _ = await (banners, news)
    }

    @ViewBuilder private func destinationView(for destination: HomeFeedDestinationReference) -> some View {
        switch destination {
        case let .news(id):
            NewsDetailView(viewModel: newsViewModel, postID: id, onNewsDeleted: {}, onNavigateBack: popDetail)
        case let .event(id):
            EventDetailView(viewModel: eventsViewModel, eventID: id, onEventDeleted: {}, onNavigateBack: popDetail)
        case let .organization(id):
            OrganizationDetailView(viewModel: organizationsViewModel, organizationID: id,
                                   newsViewModel: newsViewModel, eventsViewModel: eventsViewModel,
                                   onNavigateBack: popDetail)
        }
    }

    private func popDetail() {
        guard !navigationPath.isEmpty else { return }
        navigationPath.removeLast()
    }
}

#Preview {
    NavigationStack {
        NewsHomeView(newsViewModel: NewsViewModel(repository: MockNewsRepository()),
                     eventsViewModel: EventsViewModel(repository: MockEventRepository()),
                     organizationsViewModel: OrganizationsViewModel(repository: MockOrganizationRepository()),
                     newsRepository: MockNewsRepository(),
                     featuredBannerRepository: MockFeaturedBannerRepository(),
                     navigationPath: .constant([]))
    }
    .environmentObject(AuthState())
}
