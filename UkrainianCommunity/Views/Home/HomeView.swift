import Combine
import Foundation
import SwiftUI

private enum HomeContentRefreshReason: Hashable {
    case news
    case events
    case organizations
}

private let homeRootScrollTopID = "homeRootScrollTop"

struct HomeView: View {
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: HomeViewModel
    @ObservedObject var newsViewModel: NewsViewModel
    @ObservedObject var eventsViewModel: EventsViewModel
    @ObservedObject var organizationsViewModel: OrganizationsViewModel
    let newsRepository: NewsRepository
    @Binding var navigationPath: [HomeFeedDestinationReference]
    let onFeaturedBannerTap: (FeaturedBanner) -> Void
    let scrollResetToken: Int
    let searchResetToken: Int
    let isActive: Bool
    @Binding var selectedFederalState: AustrianFederalState?
    @StateObject private var featuredBannerViewModel: FeaturedBannerListViewModel
    @State private var selectedContentType: HomeContentTypeFilter = .all
    @State private var newsFilter = NewsBrowseFilter()
    @StateObject private var newsBrowser: NewsBrowseViewModel
    @State private var newsReferenceDate = Date()
    @State private var selectedFeedFilter: HomeFeedFilter = .all
    @State private var isSearchPresented = false
    @State private var searchText = ""
    @State private var pendingContentRefreshReasons: Set<HomeContentRefreshReason> = []
    @State private var pendingContentRefreshTask: Task<Void, Never>?
    @State private var visibleFeedItems: [HomeFeedItem] = []
    @State private var isLoadingNextPage = false

    private var featuredBannerLoadKey: String {
        "\(selectedFederalState?.rawValue ?? "allAustria"):\(isActive)"
    }

    init(
        viewModel: HomeViewModel,
        newsViewModel: NewsViewModel,
        eventsViewModel: EventsViewModel,
        organizationsViewModel: OrganizationsViewModel,
        newsRepository: NewsRepository,
        featuredBannerRepository: FeaturedBannerRepository,
        featuredBannerCache: FeaturedBannerCache = FeaturedBannerCache(),
        navigationPath: Binding<[HomeFeedDestinationReference]>,
        onFeaturedBannerTap: @escaping (FeaturedBanner) -> Void = { _ in },
        scrollResetToken: Int = 0,
        searchResetToken: Int = 0,
        isActive: Bool = true,
        selectedFederalState: Binding<AustrianFederalState?> = .constant(nil)
    ) {
        self.viewModel = viewModel
        self.newsViewModel = newsViewModel
        self.eventsViewModel = eventsViewModel
        self.organizationsViewModel = organizationsViewModel
        self.newsRepository = newsRepository
        _newsBrowser = StateObject(wrappedValue: NewsBrowseViewModel(repository: newsRepository))
        self.onFeaturedBannerTap = onFeaturedBannerTap
        self.scrollResetToken = scrollResetToken
        self.searchResetToken = searchResetToken
        self.isActive = isActive
        _selectedFederalState = selectedFederalState
        _featuredBannerViewModel = StateObject(wrappedValue: FeaturedBannerListViewModel(
            repository: featuredBannerRepository,
            cache: featuredBannerCache
        ))
        _navigationPath = navigationPath
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical, showsIndicators: false) {
                Color.clear
                    .frame(height: 0)
                    .id(homeRootScrollTopID)

                VStack(alignment: .leading, spacing: 0) {
                    homeHeader
                        .padding(.bottom, AppTheme.homeHeaderHeroSpacing)

                    homeHero
                        .padding(
                            .bottom,
                            featuredBannerViewModel.banners.isEmpty && featuredBannerViewModel.error == nil
                                ? 0
                                : AppTheme.homeSectionSpacing
                        )

                    HomeFilterRow(
                        selectedContentType: selectedContentType,
                        selectedFilter: selectedFeedFilter,
                        selectedFederalState: selectedFederalState,
                        onSelectRegion: selectRegion,
                        onSelectContentType: { selectedContentType = $0 },
                        onToggleSaved: { toggleFeedFilter(.saved) },
                        onToggleSubscribed: { toggleFeedFilter(.subscribed) },
                        newsFilter: $newsFilter,
                        authenticated: authState.isAuthenticated
                    )
                        .padding(.bottom, AppTheme.homeSectionSpacing)

                    VStack(alignment: .leading, spacing: 0) {
                        feedContent
                    }
                }
                .padding(.horizontal, AppTheme.pageHorizontal)
                .padding(.bottom, AppTheme.homeBottomContentPadding)
                .appCenteredContent(maxWidth: AppTheme.feedContentMaxWidth)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: scrollResetToken) {
                scrollToTop(with: scrollProxy)
            }
        }
        .background(AppBackgroundView())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: HomeFeedDestinationReference.self) { destination in
            destinationView(for: destination)
        }
        .appRefreshable {
            await refreshContentWhenAuthIsReady(force: true)
        }
        .task(id: contentLoadKey) {
            await loadContentWhenAuthIsReady()
        }
        .task(id: newsBrowseLoadKey) {
            guard selectedContentType == .news, isAuthBootstrapReady, isActive else { return }
            await newsBrowser.reload(newsBrowseQuery, visibility: newsViewModel.visibilityPolicy)
        }
        .onChange(of: newsViewModel.contentVersion) { _, _ in
            guard selectedContentType == .news else { return }
            newsReferenceDate = Date()
        }
        .task(id: featuredBannerLoadKey) {
            guard isActive, isAuthBootstrapReady else { return }
            await loadFeaturedBannersIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .newsChanged)) { _ in
            guard isActive else { return }
            scheduleContentRefresh(for: .news)
        }
        .onReceive(NotificationCenter.default.publisher(for: .eventsChanged)) { _ in
            guard isActive else { return }
            scheduleContentRefresh(for: .events)
        }
        .onReceive(NotificationCenter.default.publisher(for: .organizationsChanged)) { _ in
            guard isActive else { return }
            scheduleContentRefresh(for: .organizations)
        }
        .onChange(of: newsViewModel.contentVersion) { _, _ in
            synchronizeHomeFeed()
        }
        .onChange(of: eventsViewModel.contentVersion) { _, _ in
            synchronizeHomeFeed()
        }
        .onChange(of: organizationsViewModel.contentVersion) { _, _ in
            synchronizeHomeFeed()
        }
        .onChange(of: viewModel.feedItems) { _, _ in
            rebuildVisibleFeedItems()
        }
        .onChange(of: selectedContentType) { _, _ in
            rebuildVisibleFeedItems()
        }
        .onChange(of: selectedFeedFilter) { _, _ in
            rebuildVisibleFeedItems()
        }
        .onChange(of: selectedFederalState) { _, _ in
            rebuildVisibleFeedItems()
        }
        .onChange(of: searchText) { _, _ in
            rebuildVisibleFeedItems()
        }
        .onChange(of: authState.user?.id) { _, _ in
            newsBrowser.clear()
            newsFilter.scope = .all
            rebuildVisibleFeedItems()
        }
        .observesKeyboardDismissTaps()
    }

    private func scrollToTop(with scrollProxy: ScrollViewProxy) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            scrollProxy.scrollTo(homeRootScrollTopID, anchor: .top)
        }
    }

    @ViewBuilder
    private var homeHero: some View {
        if !featuredBannerViewModel.banners.isEmpty {
            FeaturedBannerCarouselView(
                banners: featuredBannerViewModel.banners,
                sizing: .fixedHeight(176),
                onBannerTap: onFeaturedBannerTap
            )
        } else if let error = featuredBannerViewModel.error {
            FeaturedBannerLoadFailureView(error: error) {
                await refreshFeaturedBanners()
            }
        }
    }

    private var homeHeader: some View {
        AppSearchableBrandHeader(
            isSearchPresented: $isSearchPresented,
            searchText: $searchText,
            placeholder: AppStrings.Search.homePlaceholder,
            collapseToken: searchResetToken,
            creationKind: .news
        )
    }

    @ViewBuilder
    private var feedContent: some View {
        if selectedContentType == .news {
            newsBrowseContent
        } else if viewModel.isLoading && viewModel.feedItems.isEmpty {
            LoadingStateCard(title: nil)
                .frame(maxWidth: .infinity, minHeight: 180)
        } else if viewModel.feedItems.isEmpty && viewModel.error != nil {
            ErrorStateCard(
                title: AppStrings.Tabs.home,
                message: homeErrorText,
                retryTitle: AppStrings.News.retry
            ) {
                Task {
                    await refreshContentWhenAuthIsReady(force: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 180)
        } else if viewModel.feedItems.isEmpty {
            EmptyStateCard(
                systemImage: "tray",
                title: AppStrings.Tabs.home,
                message: AppStrings.Common.noItems
            )
            .frame(maxWidth: .infinity, minHeight: 180)
        } else if visibleFeedItems.isEmpty {
            UnifiedEmptyStateCard(
                systemImage: emptyStateSystemImage,
                title: hasActiveSearch ? AppStrings.Search.noResultsTitle : AppStrings.Tabs.home,
                message: emptyStateMessage
            ) {
                if hasMoreVisiblePages {
                    loadMoreButton
                }
            }
            .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            VStack(spacing: AppTheme.feedRowSpacing) {
                DashboardFeedContainer(
                    items: visibleFeedItems,
                    spacing: AppTheme.feedRowSpacing
                ) { item in
                    VStack(alignment: .leading, spacing: 0) {
                        NavigationLink(value: item.destination) {
                            ContentFeedCard(item: item, includesFooter: false)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("home.card.\(item.id)")
                        ContentCardMetadataFooter(item: item, selectNewsTopic: selectNewsTopic)
                    }
                }

                if hasMoreVisiblePages {
                    loadMoreButton
                }
            }
        }
    }

    private var newsBrowseQuery: NewsBrowseQuery {
        NewsBrowseQuery(filter: newsFilter, region: selectedFederalState, search: searchText, accountKey: authBootstrapKey, referenceDate: newsReferenceDate)
    }
    private var newsBrowseLoadKey: String {
        "\(newsBrowseQuery.hashValue):\(authBootstrapKey):\(selectedContentType):\(isActive)"
    }
    private func selectNewsTopic(_ topic: NewsCategory) {
        newsFilter.topic = topic
        selectedContentType = .news
    }
    @ViewBuilder private var newsBrowseContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.feedRowSpacing) {
            Text([newsFilter.period.title,
                  NewsBrowseStrings.text(newsFilter.oldestFirst ? "oldest" : "newest"),
                  newsFilter.scope == .all ? nil : newsFilter.scope.title].compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(AppTheme.textSecondary)
                .accessibilityIdentifier("home.news.summary")
            if newsFilter.period == .custom {
                Text("\(LocalizationStore.dateString(from: newsFilter.startDate, dateStyle: .medium, timeStyle: .none)) – \(LocalizationStore.dateString(from: newsFilter.endDate, dateStyle: .medium, timeStyle: .none))")
                    .font(.caption).foregroundStyle(AppTheme.textSecondary)
            }
            if let error = newsBrowser.error {
                ErrorStateCard(title: AppStrings.Tabs.home, message: error, retryTitle: AppStrings.News.retry) {
                    Task { await newsBrowser.loadMore(visibility: newsViewModel.visibilityPolicy) }
                }
            }
            ForEach(newsViewModel.visibilityPolicy.visibleNews(newsBrowser.posts)) { post in
                let item = HomeFeedItem(post: post)
                VStack(alignment: .leading, spacing: 0) {
                    NavigationLink(value: item.destination) { ContentFeedCard(item: item, includesFooter: false) }
                        .buttonStyle(.plain).accessibilityIdentifier("home.card.\(item.id)")
                    ContentCardMetadataFooter(item: item, selectNewsTopic: selectNewsTopic)
                }
            }
            if newsBrowser.loading {
                ProgressView().frame(maxWidth: .infinity).accessibilityIdentifier("home.news.loading")
            } else if newsBrowser.hasMore {
                if newsBrowser.posts.isEmpty { Text(NewsBrowseStrings.text("continueHint")).font(.caption) }
                Button(NewsBrowseStrings.text("more")) {
                    Task { await newsBrowser.loadMore(visibility: newsViewModel.visibilityPolicy) }
                }.accessibilityIdentifier("home.news.more")
            } else if newsBrowser.posts.isEmpty && newsBrowser.error == nil {
                Text(NewsBrowseStrings.text("empty")).accessibilityIdentifier("home.news.empty")
                if newsFilter.period != .all {
                    Button(NewsBrowseStrings.text("expandPeriod")) { newsFilter.period = .all }
                }
                Button(NewsBrowseStrings.text("reset")) {
                    newsFilter = NewsBrowseFilter(); searchText = ""; selectedFederalState = nil
                }.accessibilityIdentifier("home.news.clear")
            }
        }
    }

    private var hasActiveSearch: Bool {
        LocalSearchMatcher.hasQuery(searchText)
    }

    private var hasMoreVisiblePages: Bool {
        switch selectedContentType {
        case .all:
            return newsViewModel.hasMorePages
                || eventsViewModel.hasMorePages
                || organizationsViewModel.hasMorePages
        case .news:
            return newsViewModel.hasMorePages
        case .events:
            return eventsViewModel.hasMorePages
        case .organizations:
            return organizationsViewModel.hasMorePages
        }
    }

    private var loadMoreButton: some View {
        PrimaryActionButton(
            title: hasActiveSearch ? AppStrings.Search.loadMoreResults : AppStrings.Search.loadMoreContent,
            loadingTitle: hasActiveSearch ? AppStrings.Search.loadingMoreResults : AppStrings.Search.loadingMoreContent,
            isLoading: isLoadingNextPage,
            systemImage: "ellipsis.circle"
        ) {
            Task {
                await loadNextVisiblePage()
            }
        }
        .accessibilityIdentifier("home.feed.loadMore")
    }

    private func rebuildVisibleFeedItems() {
        let bookmarkedNewsIDs = Set(newsViewModel.posts.filter(\.isBookmarked).map(\.id))
        let bookmarkedEventIDs = Set(eventsViewModel.events.filter(\.isBookmarked).map(\.id))
        let bookmarkedOrganizationIDs = Set(organizationsViewModel.organizations.filter(\.isBookmarked).map(\.id))
        let subscribedOrganizationIDs = Set(organizationsViewModel.organizations.filter(\.isSubscribed).map(\.id))

        let rebuiltItems = HomeFeedSnapshotBuilder.buildSnapshot(
            from: viewModel.feedItems,
            selectedContentType: selectedContentType,
            selectedFeedFilter: selectedFeedFilter,
            selectedFederalState: selectedFederalState,
            searchText: searchText,
            bookmarkedNewsIDs: bookmarkedNewsIDs,
            bookmarkedEventIDs: bookmarkedEventIDs,
            bookmarkedOrganizationIDs: bookmarkedOrganizationIDs,
            subscribedOrganizationIDs: subscribedOrganizationIDs,
            isAuthenticated: authState.isAuthenticated
        )

        if visibleFeedItems != rebuiltItems {
            visibleFeedItems = rebuiltItems
        }

    }

    private func toggleFeedFilter(_ filter: HomeFeedFilter) {
        selectedFeedFilter = selectedFeedFilter == filter ? .all : filter
    }

    private func selectRegion(_ federalState: AustrianFederalState?) {
        selectedFederalState = federalState
    }

    private var authBootstrapKey: String {
        switch authState.sessionState {
        case .restoring:
            "restoring"
        case .authenticating:
            "authenticating:\(authState.pendingSessionUserID ?? "pending")"
        case .guest:
            "guest"
        case .authenticated:
            "authenticated:\(authState.user?.id ?? "pending")"
        case .verificationPending:
            "verificationPending:\(authState.pendingVerificationEmail ?? "pending")"
        case .sessionUnavailable:
            "sessionUnavailable:\(authState.pendingSessionUserID ?? "pending")"
        }
    }

    private var isAuthBootstrapReady: Bool {
        authState.sessionState != .restoring && authState.sessionState != .authenticating
    }

    private var contentLoadKey: String {
        "\(authBootstrapKey):\(selectedFederalState?.rawValue ?? "allAustria"):\(isActive)"
    }

    private func loadContentWhenAuthIsReady() async {
        guard isActive, isAuthBootstrapReady else { return }
        await loadContentIfNeeded()
        await refreshContentIfStale()
    }

    private func refreshContentWhenAuthIsReady(force: Bool) async {
        guard isAuthBootstrapReady else { return }

        if force {
            await refreshAllContent()
        } else {
            await loadContentWhenAuthIsReady()
        }
    }

    private var emptyStateSystemImage: String {
        if hasActiveSearch {
            return "magnifyingglass"
        }

        if selectedContentType != .all {
            return selectedContentType.systemImage
        }

        return switch selectedFeedFilter {
        case .all:
            selectedFederalState == nil ? "tray" : "mappin.and.ellipse"
        case .saved:
            "bookmark"
        case .subscribed:
            "person.2"
        }
    }

    private var emptyStateMessage: String {
        if hasActiveSearch {
            return AppStrings.Search.noResultsMessage
        }

        return switch selectedFeedFilter {
        case .all:
            selectedFederalState == nil ? AppStrings.Common.noItems : AppStrings.Home.emptyRegion
        case .saved:
            AppStrings.Home.emptySaved
        case .subscribed:
            AppStrings.Home.emptySubscribed
        }
    }

    private func loadContentIfNeeded() async {
        synchronizeHomeFeed(isLoading: true)
        async let featuredBannerLoad: Void = loadFeaturedBannersIfNeeded()
        async let newsLoad: Void = newsViewModel.loadIfNeeded(
            federalState: selectedFederalState,
            initialLimit: homeNewsPageSize
        )
        async let eventsLoad: Void = eventsViewModel.loadIfNeeded(
            federalState: selectedFederalState,
            initialLimit: homeEventPageSize
        )
        async let organizationsLoad: Void = organizationsViewModel.loadIfNeeded(
            federalState: selectedFederalState,
            initialLimit: homeOrganizationPageSize
        )
        _ = await (featuredBannerLoad, newsLoad, eventsLoad, organizationsLoad)
        synchronizeHomeFeed()
    }

    private func refreshContentIfStale() async {
        synchronizeHomeFeed(isLoading: true)
        async let featuredBannerRefresh: Void = refreshFeaturedBannersIfStale()
        async let newsRefresh: Void = newsViewModel.refreshIfStale(
            federalState: selectedFederalState,
            limit: homeNewsPageSize
        )
        async let eventsRefresh: Void = eventsViewModel.refreshIfStale(
            federalState: selectedFederalState,
            limit: homeEventPageSize
        )
        async let organizationsRefresh: Void = organizationsViewModel.refreshIfStale(
            federalState: selectedFederalState,
            limit: homeOrganizationPageSize
        )
        _ = await (featuredBannerRefresh, newsRefresh, eventsRefresh, organizationsRefresh)
        synchronizeHomeFeed()
    }

    private func refreshAllContent() async {
        synchronizeHomeFeed(isLoading: true)
        async let featuredBannerRefresh: Void = refreshFeaturedBanners()
        async let newsRefresh: Void = newsViewModel.refresh(
            federalState: selectedFederalState,
            limit: homeNewsPageSize
        )
        async let eventsRefresh: Void = eventsViewModel.refresh(
            federalState: selectedFederalState,
            limit: homeEventPageSize
        )
        async let organizationsRefresh: Void = organizationsViewModel.refresh(
            federalState: selectedFederalState,
            limit: homeOrganizationPageSize
        )
        _ = await (featuredBannerRefresh, newsRefresh, eventsRefresh, organizationsRefresh)
        synchronizeHomeFeed()
    }

    private func loadNextVisiblePage() async {
        guard !isLoadingNextPage else { return }
        isLoadingNextPage = true
        defer { isLoadingNextPage = false }

        switch selectedContentType {
        case .all:
            async let news: Void = newsViewModel.loadNextPage(pageSize: homeNewsPageSize)
            async let events: Void = eventsViewModel.loadNextPage(pageSize: homeEventPageSize)
            async let organizations: Void = organizationsViewModel.loadNextPage(pageSize: homeOrganizationPageSize)
            _ = await (news, events, organizations)
        case .news:
            await newsViewModel.loadNextPage()
        case .events:
            await eventsViewModel.loadNextPage()
        case .organizations:
            await organizationsViewModel.loadNextPage()
        }
    }

    private func scheduleContentRefresh(for reason: HomeContentRefreshReason) {
        pendingContentRefreshReasons.insert(reason)
        pendingContentRefreshTask?.cancel()
        pendingContentRefreshTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            let reasons = await MainActor.run {
                let reasons = pendingContentRefreshReasons
                pendingContentRefreshReasons.removeAll()
                pendingContentRefreshTask = nil
                return reasons
            }

            await refreshChangedContent(for: reasons)
        }
    }

    private func loadFeaturedBannersIfNeeded() async {
        await featuredBannerViewModel.loadIfNeeded(
            for: .home,
            federalState: selectedFederalState
        )
    }

    private func refreshFeaturedBannersIfStale() async {
        await featuredBannerViewModel.refreshIfStale(
            for: .home,
            federalState: selectedFederalState
        )
    }

    private func refreshFeaturedBanners() async {
        await featuredBannerViewModel.refresh(
            for: .home,
            federalState: selectedFederalState
        )
    }

    private func refreshChangedContent(for reasons: Set<HomeContentRefreshReason>) async {
        guard !reasons.isEmpty else { return }

        synchronizeHomeFeed(isLoading: true)

        if reasons.contains(.news) {
            await newsViewModel.refresh()
        }

        if reasons.contains(.events) {
            await eventsViewModel.refresh()
        }

        if reasons.contains(.organizations) {
            await organizationsViewModel.refresh()
        }

        synchronizeHomeFeed()
    }

    private func synchronizeHomeFeed(isLoading: Bool? = nil) {
        viewModel.updateFeed(
            posts: newsViewModel.posts,
            events: eventsViewModel.events,
            organizations: organizationsViewModel.organizations,
            isLoading: isLoading ?? (newsViewModel.isLoading || eventsViewModel.isLoading || organizationsViewModel.isLoading),
            error: newsViewModel.error ?? eventsViewModel.error ?? organizationsViewModel.error
        )
    }

    private var homeErrorText: String {
        switch viewModel.error {
        case .network:
            AppStrings.News.loadNetworkError
        case .permissionDenied:
            AppStrings.News.loadPermissionError
        case .validationFailed:
            AppStrings.News.loadValidationError
        case .notFound:
            AppStrings.Common.noItems
        case .unknown:
            AppStrings.News.loadUnknownError
        case nil:
            ""
        }
    }

    @ViewBuilder
    private func destinationView(for item: HomeFeedItem) -> some View {
        destinationView(for: item.destination)
    }

    @ViewBuilder
    private func destinationView(for destination: HomeFeedDestinationReference) -> some View {
        switch destination {
        case let .news(id):
            NewsDetailView(viewModel: newsViewModel, postID: id, onNewsDeleted: {}, onNavigateBack: popHomeDetail)
        case let .event(id):
            EventDetailView(viewModel: eventsViewModel, eventID: id, onEventDeleted: {}, onNavigateBack: popHomeDetail)
        case let .organization(id):
            OrganizationDetailView(
                viewModel: organizationsViewModel,
                organizationID: id,
                newsViewModel: newsViewModel,
                eventsViewModel: eventsViewModel,
                onNavigateBack: popHomeDetail
            )
        }
    }

    private func popHomeDetail() {
        guard !navigationPath.isEmpty else { return }
        navigationPath.removeLast()
    }
}

private struct HomeFeedSnapshotBuilder {
    static func buildSnapshot(
        from feedItems: [HomeFeedItem],
        selectedContentType: HomeContentTypeFilter,
        selectedFeedFilter: HomeFeedFilter,
        selectedFederalState: AustrianFederalState?,
        searchText: String,
        bookmarkedNewsIDs: Set<String>,
        bookmarkedEventIDs: Set<String>,
        bookmarkedOrganizationIDs: Set<String>,
        subscribedOrganizationIDs: Set<String>,
        isAuthenticated: Bool
    ) -> [HomeFeedItem] {
        let normalizedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return feedItems.filter { item in
            guard selectedContentType.matches(item) else { return false }
            guard isMatchingRegion(item, selectedFederalState: selectedFederalState) else { return false }

            if !isMatchingFilter(
                item,
                selectedFilter: selectedFeedFilter,
                isAuthenticated: isAuthenticated,
                bookmarkedNewsIDs: bookmarkedNewsIDs,
                bookmarkedEventIDs: bookmarkedEventIDs,
                bookmarkedOrganizationIDs: bookmarkedOrganizationIDs,
                subscribedOrganizationIDs: subscribedOrganizationIDs
            ) {
                return false
            }

            if normalizedSearchText.isEmpty {
                return true
            }

            return matchesSearch(item, query: normalizedSearchText)
        }
    }

    private static func isMatchingRegion(_ item: HomeFeedItem, selectedFederalState: AustrianFederalState?) -> Bool {
        RegionVisibilityMatcher.isVisible(
            regionScope: item.regionScope,
            federalState: item.federalState,
            selectedFederalState: selectedFederalState
        )
    }

    private static func isMatchingFilter(
        _ item: HomeFeedItem,
        selectedFilter: HomeFeedFilter,
        isAuthenticated: Bool,
        bookmarkedNewsIDs: Set<String>,
        bookmarkedEventIDs: Set<String>,
        bookmarkedOrganizationIDs: Set<String>,
        subscribedOrganizationIDs: Set<String>
    ) -> Bool {
        guard selectedFilter != .all else { return true }
        guard isAuthenticated else { return false }

        switch selectedFilter {
        case .all:
            return true
        case .saved:
            return isSaved(
                item,
                bookmarkedNewsIDs: bookmarkedNewsIDs,
                bookmarkedEventIDs: bookmarkedEventIDs,
                bookmarkedOrganizationIDs: bookmarkedOrganizationIDs
            )
        case .subscribed:
            return isSubscribedSource(item, subscribedOrganizationIDs: subscribedOrganizationIDs)
        }
    }

    private static func isSaved(
        _ item: HomeFeedItem,
        bookmarkedNewsIDs: Set<String>,
        bookmarkedEventIDs: Set<String>,
        bookmarkedOrganizationIDs: Set<String>
    ) -> Bool {
        switch item.destination {
        case let .news(id):
            return bookmarkedNewsIDs.contains(id)
        case let .event(id):
            return bookmarkedEventIDs.contains(id)
        case let .organization(id):
            return bookmarkedOrganizationIDs.contains(id)
        }
    }

    private static func isSubscribedSource(_ item: HomeFeedItem, subscribedOrganizationIDs: Set<String>) -> Bool {
        guard let organizationId = item.organizationId else { return false }
        return subscribedOrganizationIDs.contains(organizationId)
    }

    private static func matchesSearch(_ item: HomeFeedItem, query: String) -> Bool {
        LocalSearchMatcher.matches(
            query: query,
            values: [
                item.title,
                item.summary,
                item.organizationName,
                item.organizationType,
                item.authorName,
                item.city,
                item.eventVenue,
                item.itemType.searchTitle
            ]
        )
    }
}

private enum HomeContentTypeFilter: CaseIterable {
    case all
    case news
    case events
    case organizations

    var title: String {
        switch self {
        case .all:
            AppStrings.Home.filterAll
        case .news:
            AppStrings.Home.filterNews
        case .events:
            AppStrings.Home.filterEvents
        case .organizations:
            AppStrings.Home.filterOrganizations
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            "square.grid.2x2"
        case .news:
            "newspaper"
        case .events:
            "calendar"
        case .organizations:
            "building.2"
        }
    }

    func matches(_ item: HomeFeedItem) -> Bool {
        switch self {
        case .all:
            return true
        case .news:
            return item.itemType == .news
        case .events:
            return item.itemType == .event
        case .organizations:
            return item.itemType == .organization
        }
    }
}

private enum HomeFeedFilter {
    case all
    case saved
    case subscribed
}

private struct HomeFilterRow: View {
    let selectedContentType: HomeContentTypeFilter
    let selectedFilter: HomeFeedFilter
    let selectedFederalState: AustrianFederalState?
    let onSelectRegion: (AustrianFederalState?) -> Void
    let onSelectContentType: (HomeContentTypeFilter) -> Void
    let onToggleSaved: () -> Void
    let onToggleSubscribed: () -> Void
    @Binding var newsFilter: NewsBrowseFilter
    let authenticated: Bool
    @State private var showNewsFilters = false

    private enum Filter: String {
        case type, region, subscribed, saved, topic, options
    }

    var body: some View {
        AppPrioritizedFilterRow(
            pinned: [.type, .region],
            filters: selectedContentType == .news ? [.topic, .options] : [.subscribed, .saved],
            isActive: isActive
        ) { filter in
            filterControl(filter)
                .accessibilityIdentifier("home.filter.\(filter.rawValue)")
        }
        .accessibilityIdentifier("home.filters")
        .sheet(isPresented: $showNewsFilters) {
            NewsBrowseFilterSheet(selection: $newsFilter, authenticated: authenticated)
        }
    }

    private func isActive(_ filter: Filter) -> Bool {
        switch filter {
        case .topic: newsFilter.topic != nil
        case .options: newsFilter.activeCount > 0
        case .type: selectedContentType != .all
        case .region: selectedFederalState != nil
        case .subscribed: selectedFilter == .subscribed
        case .saved: selectedFilter == .saved
        }
    }

    @ViewBuilder
    private func filterControl(_ filter: Filter) -> some View {
        switch filter {
        case .topic:
            NewsTopicMenu(selection: $newsFilter.topic)
        case .options:
            Button { showNewsFilters = true } label: {
                AppFilterChip(title: NewsBrowseStrings.text("filters") + (newsFilter.activeCount > 0 ? " (\(newsFilter.activeCount))" : ""),
                              systemImage: "line.3.horizontal.decrease", isSelected: newsFilter.activeCount > 0)
            }.accessibilityIdentifier("home.news.filters")
        case .type:
            Menu {
                ForEach(HomeContentTypeFilter.allCases, id: \.self) { contentType in
                    Button {
                        onSelectContentType(contentType)
                    } label: {
                        Label(contentType.title, systemImage: contentType.systemImage)
                    }
                }
            } label: {
                AppFilterChip(
                    title: selectedContentType.title,
                    systemImage: selectedContentType.systemImage,
                    isSelected: selectedContentType != .all,
                    trailingSystemImage: "chevron.down"
                )
            }
            .buttonStyle(.plain)
        case .region:
            AppRegionFilterMenu(selection: Binding(get: { selectedFederalState }, set: onSelectRegion))
        case .subscribed:
            Button(action: onToggleSubscribed) {
                AppFilterChip(title: AppStrings.Home.filterSubscribed, systemImage: "person.2.fill", isSelected: selectedFilter == .subscribed)
            }
            .buttonStyle(.plain)
        case .saved:
            Button(action: onToggleSaved) {
                AppFilterChip(title: AppStrings.Home.filterSaved, systemImage: "bookmark", isSelected: selectedFilter == .saved)
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    NavigationStack {
        HomeView(
            viewModel: HomeViewModel(
                newsRepository: MockNewsRepository(),
                eventRepository: MockEventRepository(),
                organizationRepository: MockOrganizationRepository()
            ),
            newsViewModel: NewsViewModel(repository: MockNewsRepository()),
            eventsViewModel: EventsViewModel(repository: MockEventRepository()),
            organizationsViewModel: OrganizationsViewModel(repository: MockOrganizationRepository()),
            newsRepository: MockNewsRepository(),
            featuredBannerRepository: MockFeaturedBannerRepository(),
            navigationPath: .constant([])
        )
    }
    .environmentObject(AuthState())
}

private extension HomeFeedItemType {
    var searchTitle: String {
        switch self {
        case .news:
            return AppStrings.News.title
        case .event:
            return AppStrings.Tabs.events
        case .organization:
            return AppStrings.Tabs.organizations
        }
    }
}
