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
    @ObservedObject var guideViewModel: LegacyGuideListViewModel
    let newsRepository: NewsRepository
    @Binding var navigationPath: [HomeFeedDestinationReference]
    let onFeaturedBannerTap: (FeaturedBanner) -> Void
    let scrollResetToken: Int
    @StateObject private var featuredBannerViewModel: FeaturedBannerListViewModel
    @State private var selectedContentType: HomeContentTypeFilter = .all
    @State private var selectedFeedFilter: HomeFeedFilter = .all
    @State private var selectedFederalState: AustrianFederalState?
    @State private var didManuallyChangeRegion = false
    @State private var isRegionPickerPresented = false
    @State private var isSearchPresented = false
    @State private var searchText = ""
    @State private var pendingContentRefreshReasons: Set<HomeContentRefreshReason> = []
    @State private var pendingContentRefreshTask: Task<Void, Never>?

    init(
        viewModel: HomeViewModel,
        newsViewModel: NewsViewModel,
        eventsViewModel: EventsViewModel,
        organizationsViewModel: OrganizationsViewModel,
        guideViewModel: LegacyGuideListViewModel,
        newsRepository: NewsRepository,
        featuredBannerRepository: FeaturedBannerRepository,
        navigationPath: Binding<[HomeFeedDestinationReference]>,
        onFeaturedBannerTap: @escaping (FeaturedBanner) -> Void = { _ in },
        scrollResetToken: Int = 0
    ) {
        self.viewModel = viewModel
        self.newsViewModel = newsViewModel
        self.eventsViewModel = eventsViewModel
        self.organizationsViewModel = organizationsViewModel
        self.guideViewModel = guideViewModel
        self.newsRepository = newsRepository
        self.onFeaturedBannerTap = onFeaturedBannerTap
        self.scrollResetToken = scrollResetToken
        _featuredBannerViewModel = StateObject(wrappedValue: FeaturedBannerListViewModel(repository: featuredBannerRepository))
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
                        .padding(.bottom, featuredBannerViewModel.banners.isEmpty ? 0 : AppTheme.homeSectionSpacing)

                    HomeFilterRow(
                        selectedContentType: selectedContentType,
                        selectedFilter: selectedFeedFilter,
                        selectedFederalState: selectedFederalState,
                        onSelectRegion: { isRegionPickerPresented = true },
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
            }
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
        .confirmationDialog(AppStrings.Home.regionAllAustria, isPresented: $isRegionPickerPresented, titleVisibility: .visible) {
            Button(AppStrings.Home.regionAllAustria) {
                selectRegion(nil)
            }

            ForEach(AustrianFederalState.allCases) { federalState in
                Button(federalState.homeDisplayName) {
                    selectRegion(federalState)
                }
            }

            Button(AppStrings.Events.cancel, role: .cancel) {}
        }
        .refreshable {
            await refreshContentWhenAuthIsReady(force: true)
        }
        .task(id: authBootstrapKey) {
            await loadContentWhenAuthIsReady()
        }
        .onChange(of: authState.user?.selectedFederalState) { _, newRegion in
            guard !didManuallyChangeRegion else { return }
            selectedFederalState = newRegion
        }
        .onReceive(NotificationCenter.default.publisher(for: .newsChanged)) { _ in
            scheduleContentRefresh(for: .news)
        }
        .onReceive(NotificationCenter.default.publisher(for: .eventsChanged)) { _ in
            scheduleContentRefresh(for: .events)
        }
        .onReceive(NotificationCenter.default.publisher(for: .organizationsChanged)) { _ in
            scheduleContentRefresh(for: .organizations)
        }
        .dismissesKeyboardOnBackgroundTap()
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
        }
    }

    private var homeHeader: some View {
        AppSearchableBrandHeader(
            isSearchPresented: $isSearchPresented,
            searchText: $searchText,
            placeholder: AppStrings.Search.homePlaceholder,
            collapseToken: scrollResetToken
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
                viewModel.reload()
            }
            .frame(maxWidth: .infinity, minHeight: 180)
        } else if viewModel.feedItems.isEmpty {
            EmptyStateCard(
                systemImage: "tray",
                title: AppStrings.Tabs.home,
                message: AppStrings.Common.noItems
            )
            .frame(maxWidth: .infinity, minHeight: 180)
        } else if filteredFeedItems.isEmpty {
            EmptyStateCard(
                systemImage: emptyStateSystemImage,
                title: hasActiveSearch ? AppStrings.Search.noResultsTitle : AppStrings.Tabs.home,
                message: emptyStateMessage
            )
            .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            DashboardFeedContainer(items: filteredFeedItems, spacing: AppTheme.feedRowSpacing) { item in
                NavigationLink(value: item.destination) {
                    HomeFeedCard(item: item)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var filteredHomeItems: [HomeFeedItem] {
        viewModel.feedItems.filter { item in
            matchesSelectedRegion(item)
                && selectedContentType.matches(item)
                && matchesSelectedFilter(item)
        }
    }

    private var filteredFeedItems: [HomeFeedItem] {
        filteredHomeItems.filter(matchesSearch)
    }

    private var hasActiveSearch: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func matchesSelectedRegion(_ item: HomeFeedItem) -> Bool {
        RegionVisibilityMatcher.isVisible(
            regionScope: item.regionScope,
            federalState: item.federalState,
            selectedFederalState: selectedFederalState
        )
    }

    private func matchesSelectedFilter(_ item: HomeFeedItem) -> Bool {
        switch selectedFeedFilter {
        case .all:
            return true
        case .saved:
            return isSaved(item)
        case .subscribed:
            return isSubscribedSource(item)
        }
    }

    private func isSaved(_ item: HomeFeedItem) -> Bool {
        guard authState.user != nil else { return false }

        switch item.destination {
        case let .news(id):
            return bookmarkedNewsIDs.contains(id)
        case let .event(id):
            return bookmarkedEventIDs.contains(id)
        case let .organization(id):
            return bookmarkedOrganizationIDs.contains(id)
        case .guide:
            return false
        }
    }

    private var bookmarkedNewsIDs: Set<String> {
        Set(newsViewModel.posts.filter(\.isBookmarked).map(\.id))
    }

    private var bookmarkedEventIDs: Set<String> {
        Set(eventsViewModel.events.filter(\.isBookmarked).map(\.id))
    }

    private var bookmarkedOrganizationIDs: Set<String> {
        Set(organizationsViewModel.organizations.filter(\.isBookmarked).map(\.id))
    }

    private func isSubscribedSource(_ item: HomeFeedItem) -> Bool {
        guard authState.user != nil else { return false }
        guard let organizationId = item.organizationId else { return false }
        return subscribedOrganizationIDs.contains(organizationId)
    }

    private var subscribedOrganizationIDs: Set<String> {
        Set(organizationsViewModel.organizations.filter(\.isSubscribed).map(\.id))
    }

    private func toggleFeedFilter(_ filter: HomeFeedFilter) {
        selectedFeedFilter = selectedFeedFilter == filter ? .all : filter
    }

    private func selectRegion(_ federalState: AustrianFederalState?) {
        selectedFederalState = federalState
        didManuallyChangeRegion = true
    }

    private func applyDefaultRegion() {
        guard !didManuallyChangeRegion else { return }
        selectedFederalState = authState.user?.selectedFederalState
    }

    private var authBootstrapKey: String {
        switch authState.sessionState {
        case .restoring:
            "restoring"
        case .guest:
            "guest"
        case .authenticated:
            "authenticated:\(authState.user?.id ?? "pending")"
        }
    }

    private var isAuthBootstrapReady: Bool {
        authState.sessionState != .restoring
    }

    private func loadContentWhenAuthIsReady() async {
        guard isAuthBootstrapReady else { return }
        applyDefaultRegion()
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

    private func matchesSearch(_ item: HomeFeedItem) -> Bool {
        LocalSearchMatcher.matches(
            query: searchText,
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

    private func loadContentIfNeeded() async {
        async let homeLoad: Void = viewModel.loadIfNeeded()
        async let featuredBannerLoad: Void = loadFeaturedBannersIfNeeded()
        async let newsLoad: Void = newsViewModel.loadIfNeeded()
        async let eventsLoad: Void = eventsViewModel.loadIfNeeded()
        async let organizationsLoad: Void = organizationsViewModel.loadIfNeeded()
        async let guideLoad: Void = guideViewModel.loadIfNeeded()
        _ = await (homeLoad, featuredBannerLoad, newsLoad, eventsLoad, organizationsLoad, guideLoad)
    }

    private func refreshContentIfStale() async {
        async let homeRefresh: Void = viewModel.refreshIfStale()
        async let featuredBannerRefresh: Void = refreshFeaturedBannersIfStale()
        async let newsRefresh: Void = newsViewModel.refreshIfStale()
        async let eventsRefresh: Void = eventsViewModel.refreshIfStale()
        async let organizationsRefresh: Void = organizationsViewModel.refreshIfStale()
        async let guideRefresh: Void = guideViewModel.refreshIfStale()
        _ = await (homeRefresh, featuredBannerRefresh, newsRefresh, eventsRefresh, organizationsRefresh, guideRefresh)
    }

    private func refreshAllContent() async {
        async let homeRefresh: Void = viewModel.refresh()
        async let featuredBannerRefresh: Void = refreshFeaturedBanners()
        async let newsRefresh: Void = newsViewModel.refresh()
        async let eventsRefresh: Void = eventsViewModel.refresh()
        async let organizationsRefresh: Void = organizationsViewModel.refresh()
        async let guideRefresh: Void = guideViewModel.refresh()
        _ = await (homeRefresh, featuredBannerRefresh, newsRefresh, eventsRefresh, organizationsRefresh, guideRefresh)
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
            federalState: authState.user?.selectedFederalState
        )
    }

    private func refreshFeaturedBannersIfStale() async {
        await featuredBannerViewModel.refreshIfStale(
            for: .home,
            federalState: authState.user?.selectedFederalState
        )
    }

    private func refreshFeaturedBanners() async {
        await featuredBannerViewModel.refresh(
            for: .home,
            federalState: authState.user?.selectedFederalState
        )
    }

    private func refreshChangedContent(for reasons: Set<HomeContentRefreshReason>) async {
        guard !reasons.isEmpty else { return }

        async let homeRefresh: Void = viewModel.refresh()

        if reasons.contains(.news) {
            await newsViewModel.refresh()
        }

        if reasons.contains(.events) {
            await eventsViewModel.refresh()
        }

        if reasons.contains(.organizations) {
            await organizationsViewModel.refresh()
        }

        _ = await homeRefresh
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
            OrganizationDetailView(viewModel: organizationsViewModel, organizationID: id, onNavigateBack: popHomeDetail)
        case let .guide(id):
            if let article = guideViewModel.articles.first(where: { $0.id == id }) {
                LegacyGuideDetailView(article: article)
            }
        }
    }

    private func popHomeDetail() {
        guard !navigationPath.isEmpty else { return }
        navigationPath.removeLast()
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
    let onSelectRegion: () -> Void
    let onSelectContentType: (HomeContentTypeFilter) -> Void
    let onToggleSaved: () -> Void
    let onToggleSubscribed: () -> Void

    var body: some View {
        AppHorizontalFilterRow {
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

            Button(action: onSelectRegion) {
                AppFilterChip(
                    title: selectedFederalState?.homeDisplayName ?? AppStrings.Home.regionAllAustria,
                    systemImage: "mappin.and.ellipse",
                    isSelected: selectedFederalState != nil,
                    trailingSystemImage: "chevron.down"
                )
            }
            .buttonStyle(.plain)

            Button(action: onToggleSubscribed) {
                AppFilterChip(title: AppStrings.Home.filterSubscribed, systemImage: "person.2.fill", isSelected: selectedFilter == .subscribed)
            }
            .buttonStyle(.plain)

            Button(action: onToggleSaved) {
                AppFilterChip(title: AppStrings.Home.filterSaved, systemImage: "bookmark", isSelected: selectedFilter == .saved)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct HomeFeedCard: View {
    let item: HomeFeedItem

    var body: some View {
        SoftContentCard(padding: AppTheme.homeFeedCardPadding) {
            HStack(alignment: .center, spacing: 10) {
                leadingMedia

                VStack(alignment: .leading, spacing: 4) {
                    typeChip

                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)

                    if item.itemType == .organization {
                        organizationMetadataLine
                            .padding(.top, 1)
                    }

                    if shouldShowPreview, !item.summary.isEmpty {
                        Text(item.summary)
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textSecondary.opacity(0.78))
                            .lineLimit(1)
                    }

                    if let publisherText {
                        publisherLine(title: publisherText)
                            .padding(.top, 1)
                    }

                    if item.itemType == .event {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 10) {
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

                if item.itemType != .organization {
                    Spacer(minLength: 2)

                    rightAccessory
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
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
            size: .small
        )
    }

    private var timestampText: some View {
        Text(publishedDateText)
            .font(.caption2.weight(.medium))
            .foregroundStyle(AppTheme.textSecondary)
            .lineLimit(1)
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
                .frame(minHeight: thumbnailSize + 12, alignment: .center)
            }
        }
    }

    private func publisherLine(title: String) -> some View {
        Label(title, systemImage: "person.crop.circle")
            .font(.caption2.weight(.medium))
            .foregroundStyle(AppTheme.textSecondary.opacity(0.86))
            .lineLimit(1)
            .minimumScaleFactor(0.82)
    }

    private var metadataLine: some View {
        AppMetadataLine(title: primaryMetadataText, systemImage: primaryMetadataIcon)
    }

    private var organizationMetadataLine: some View {
        Text(organizationMetadataText)
            .font(.caption2.weight(.medium))
            .foregroundStyle(AppTheme.textSecondary.opacity(0.86))
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.82)
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
            Color.green
        case .event:
            AppTheme.accentPrimary
        case .organization:
            Color.purple
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
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = LocalizationStore.locale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: item.publishedAt, relativeTo: Date())
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

    init(date: Date, calendar: Calendar = .current) {
        self.date = date
        self.calendar = calendar
    }

    var body: some View {
        VStack(spacing: 3) {
            VStack(spacing: 1) {
                Text(dayText)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.accentPrimary)
                    .lineLimit(1)

                Text(monthText.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.accentDestructive)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(width: 42, height: 42)
            .background(AppTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                    .strokeBorder(AppTheme.borderSubtle)
            )
            .shadow(color: AppTheme.textPrimary.opacity(0.06), radius: 5, y: 2)

            Text(weekdayText.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(AppTheme.textSecondary.opacity(0.62))
                .lineLimit(1)
        }
        .frame(width: 42)
    }

    private var dayText: String {
        "\(calendar.component(.day, from: date))"
    }

    private var weekdayText: String {
        let formatter = DateFormatter()
        formatter.locale = LocalizationStore.locale
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date)
    }

    private var monthText: String {
        let formatter = DateFormatter()
        formatter.locale = LocalizationStore.locale
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter.string(from: date)
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
            guideViewModel: LegacyGuideListViewModel(repository: LegacyMockGuideRepository()),
            newsRepository: MockNewsRepository(),
            featuredBannerRepository: MockFeaturedBannerRepository(),
            navigationPath: .constant([])
        )
    }
    .environmentObject(AuthState())
}

private extension AustrianFederalState {
    var homeDisplayName: String {
        switch self {
        case .burgenland:
            "Burgenland"
        case .kaernten:
            "Kärnten"
        case .niederoesterreich:
            "Niederösterreich"
        case .oberoesterreich:
            "Oberösterreich"
        case .salzburg:
            "Salzburg"
        case .steiermark:
            "Steiermark"
        case .tirol:
            "Tirol"
        case .vorarlberg:
            "Vorarlberg"
        case .wien:
            "Wien"
        }
    }
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
