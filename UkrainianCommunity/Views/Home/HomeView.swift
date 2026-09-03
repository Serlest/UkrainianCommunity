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
                        onToggleSubscribed: { toggleFeedFilter(.subscribed) }
                    )
                        .padding(.bottom, AppTheme.homeSectionSpacing)

                    AppGroupedContentPlane(padding: AppTheme.homeFeedPlanePadding) {
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
                sizing: .responsiveHero,
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
        if viewModel.isLoading && viewModel.feedItems.isEmpty {
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
                    NavigationLink(value: item.destination) {
                        HomeFeedCard(item: item)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.card.\(item.id)")
                }

                if hasMoreVisiblePages {
                    loadMoreButton
                }
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

    private enum Filter: String {
        case type, region, subscribed, saved
    }

    var body: some View {
        AppPrioritizedFilterRow(
            pinned: [.type, .region],
            filters: [.subscribed, .saved],
            isActive: isActive
        ) { filter in
            filterControl(filter)
                .accessibilityIdentifier("home.filter.\(filter.rawValue)")
        }
        .accessibilityIdentifier("home.filters")
    }

    private func isActive(_ filter: Filter) -> Bool {
        switch filter {
        case .type: selectedContentType != .all
        case .region: selectedFederalState != nil
        case .subscribed: selectedFilter == .subscribed
        case .saved: selectedFilter == .saved
        }
    }

    @ViewBuilder
    private func filterControl(_ filter: Filter) -> some View {
        switch filter {
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

@MainActor
private enum HomeFeedRelativeDateFormatter {
    private static let formatter = RelativeDateTimeFormatter()
    private static var configuredLocaleIdentifier: String?

    static func string(for date: Date, relativeTo referenceDate: Date = Date()) -> String {
        let locale = LocalizationStore.locale
        if configuredLocaleIdentifier != locale.identifier {
            formatter.locale = locale
            formatter.unitsStyle = .short
            configuredLocaleIdentifier = locale.identifier
        }
        return formatter.localizedString(for: date, relativeTo: referenceDate)
    }
}

private struct HomeFeedCard: View {
    let item: HomeFeedItem
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        SoftContentCard(
            padding: AppTheme.homeFeedCardPadding,
            shadowRadius: 0,
            shadowY: 0
        ) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppTheme.compactCardInnerSpacing) {
                    HStack(alignment: .top, spacing: AppTheme.compactCardInnerSpacing) {
                        leadingMedia

                        Spacer(minLength: 0)

                        rightAccessory
                    }

                    cardDetails
                }
            } else {
                HStack(alignment: .center, spacing: AppTheme.compactCardInnerSpacing) {
                    leadingMedia
                    cardDetails

                    if item.itemType != .organization {
                        Spacer(minLength: 2)

                        rightAccessory
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var cardDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            typeChip

            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)

            if item.itemType == .organization {
                organizationMetadataLine
                    .padding(.top, 1)
            }

            if shouldShowPreview, !item.summary.isEmpty {
                Text(item.summary)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let publisherText {
                publisherLine(title: publisherText)
                    .padding(.top, 1)
            }

            if item.itemType == .event {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: AppTheme.compactCardInnerSpacing) {
                        metadataLine
                        if let secondaryMetadataText {
                            AppMetadataLine(title: secondaryMetadataText, systemImage: "mappin.and.ellipse")
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        metadataLine
                        if let secondaryMetadataText {
                            AppMetadataLine(title: secondaryMetadataText, systemImage: "mappin.and.ellipse")
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var leadingMedia: some View {
        AppFeedThumbnail(
            imageURL: item.imageURL,
            fallbackSystemImage: itemTypeSystemImage,
            tint: itemTypeTint,
            fill: itemTypeFill,
            size: thumbnailSize,
            source: "HomeFeedCard"
        )
        .frame(width: thumbnailSize, height: thumbnailSize, alignment: .center)
    }

    private var typeChip: some View {
        AppInfoChip(
            title: itemTypeTitle.uppercased(),
            systemImage: itemTypeSystemImage,
            tint: itemTypeTint,
            fill: itemTypeFill,
            size: .small,
            fallbackUsesMaterial: false,
            shadowRadius: 0,
            shadowY: 0
        )
    }

    private var timestampText: some View {
        Text(publishedDateText)
            .font(.caption2.weight(.medium))
            .foregroundStyle(AppTheme.textSecondary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var rightAccessory: some View {
        if item.itemType == .news {
            timestampText
                .padding(.top, 1)
        } else if item.itemType == .event {
            if let eventStartDate = item.eventStartDate {
                VStack {
                    Spacer(minLength: 6)
                    HomeEventDateBadge(date: eventStartDate)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: thumbnailSize + AppTheme.compactCardInnerSpacingRelaxed, alignment: .center)
            }
        }
    }

    private func publisherLine(title: String) -> some View {
        Label(title, systemImage: "person.crop.circle")
            .font(.caption2.weight(.medium))
            .foregroundStyle(AppTheme.textSecondary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var metadataLine: some View {
        AppMetadataLine(title: primaryMetadataText, systemImage: primaryMetadataIcon)
    }

    private var organizationMetadataLine: some View {
        Text(organizationMetadataText)
            .font(.caption2.weight(.medium))
            .foregroundStyle(AppTheme.textSecondary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var itemTypeTitle: String {
        switch item.itemType {
        case .news:
            AppStrings.News.title
        case .event:
            AppStrings.Tabs.events
        case .organization:
            AppStrings.Tabs.organizations
        }
    }

    private var itemTypeSystemImage: String {
        switch item.itemType {
        case .news:
            "newspaper"
        case .event:
            "calendar"
        case .organization:
            "building.2"
        }
    }

    private var itemTypeTint: Color {
        switch item.itemType {
        case .news:
            AppTheme.accentSuccessForeground
        case .event:
            AppTheme.accentPrimaryForeground
        case .organization:
            AppTheme.accentIndigoForeground
        }
    }

    private var itemTypeFill: Color {
        switch item.itemType {
        case .news:
            AppTheme.badgeGreenFill
        case .event:
            AppTheme.badgeBlueFill
        case .organization:
            AppTheme.badgePurpleFill
        }
    }

    private var thumbnailSize: CGFloat {
        AppTheme.feedThumbnailSize + 14
    }

    private var shouldShowPreview: Bool {
        item.itemType == .news || item.itemType == .event
    }

    private var publishedDateText: String {
        HomeFeedRelativeDateFormatter.string(for: item.publishedAt)
    }

    private var primaryMetadataText: String {
        if item.itemType == .event, let eventStartDate = item.eventStartDate {
            return LocalizationStore.timeRangeString(startDate: eventStartDate, endDate: item.eventEndDate)
        }

        if let city = item.city, !city.isEmpty {
            return city
        }

        if let organizationName = item.organizationName, !organizationName.isEmpty {
            return organizationName
        }

        return sourceTypeTitle
    }

    private var primaryMetadataIcon: String {
        item.itemType == .event ? "clock" : "mappin.and.ellipse"
    }

    private var organizationMetadataText: String {
        [
            organizationRegionText,
            organizationCategoryText,
            subscriberCountText
        ]
        .compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        .joined(separator: " • ")
    }

    private var organizationRegionText: String? {
        if let federalState = item.federalState {
            return AppStrings.FederalStates.title(for: federalState)
        }

        if let city = item.city, !city.isEmpty {
            return city
        }

        return nil
    }

    private var organizationCategoryText: String? {
        guard let organizationType = item.organizationType,
              let category = OrganizationEditorCategory(rawValue: organizationType) else {
            return AppStrings.Organizations.detailBadge
        }

        return category.title
    }

    private var subscriberCountText: String {
        let count = item.subscriberCount
        let mod10 = count % 10
        let mod100 = count % 100
        let suffix: String

        if mod10 == 1 && mod100 != 11 {
            suffix = AppStrings.Home.subscriberSuffixOne
        } else if (2...4).contains(mod10) && !(12...14).contains(mod100) {
            suffix = AppStrings.Home.subscriberSuffixFew
        } else {
            suffix = AppStrings.Home.subscriberSuffixMany
        }

        return "\(count) \(suffix)"
    }

    private var secondaryMetadataText: String? {
        guard item.itemType == .event else { return nil }
        if let city = item.city, !city.isEmpty {
            return city
        }
        return nil
    }

    private var publisherText: String? {
        guard item.itemType == .news || item.itemType == .event else { return nil }

        let authorName = normalizedPublisherName(item.authorName)
        let sourceName = normalizedPublisherName(item.organizationName) ?? (item.itemType == .news ? AppStrings.News.missingOrganization : AppStrings.Home.brandTitle)

        guard let authorName else {
            return sourceName
        }

        return "\(authorName) · \(sourceName)"
    }

    private func normalizedPublisherName(_ value: String?) -> String? {
        guard let value else { return nil }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != AppStrings.NewsEditor.authorFallback else {
            return nil
        }

        return trimmed
    }

    private var sourceTypeTitle: String {
        switch item.sourceType {
        case .app:
            AppStrings.Common.app
        case .organization:
            AppStrings.Tabs.organizations
        }
    }

    private var accessibilitySummary: String {
        var parts = [itemTypeTitle, item.title]

        if !item.summary.isEmpty {
            parts.append(item.summary)
        }

        if let publisherText {
            parts.append(publisherText)
        }

        parts.append(primaryMetadataText)

        if item.itemType == .organization {
            parts.append(subscriberCountText)
        } else {
            parts.append("\(item.likeCount) \(AppStrings.Common.likes)")
        }
        return parts.joined(separator: ", ")
    }
}

private struct HomeEventDateBadge: View {
    let date: Date
    let calendar: Calendar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(date: Date, calendar: Calendar = .current) {
        self.date = date
        self.calendar = calendar
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                Text("\(weekdayText), \(dayText) \(monthText)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(AppTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                            .strokeBorder(AppTheme.borderSubtle)
                    )
            } else {
                VStack(spacing: 3) {
                    VStack(spacing: 1) {
                        Text(dayText)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(AppTheme.accentPrimaryForeground)

                        Text(monthText.uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppTheme.accentDestructiveForeground)
                    }
                    .frame(width: AppTheme.homeFeedDateBadgeSize, height: AppTheme.homeFeedDateBadgeSize)
                    .background(AppTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                            .strokeBorder(AppTheme.borderSubtle)
                    )
                    .shadow(color: AppTheme.textPrimary.opacity(0.06), radius: 5, y: 2)

                    Text(weekdayText.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }
                .frame(width: AppTheme.homeFeedDateBadgeSize)
            }
        }
    }

    private var dayText: String {
        "\(calendar.component(.day, from: date))"
    }

    private var weekdayText: String {
        LocalizationStore.dateString(from: date, localizedTemplate: "EEE")
    }

    private var monthText: String {
        LocalizationStore.dateString(from: date, localizedTemplate: "MMM")
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
