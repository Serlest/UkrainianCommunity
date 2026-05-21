import Combine
import Foundation
import PhotosUI
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: HomeViewModel
    @ObservedObject var newsViewModel: NewsViewModel
    @ObservedObject var eventsViewModel: EventsViewModel
    @ObservedObject var organizationsViewModel: OrganizationsViewModel
    let newsRepository: NewsRepository
    @State private var selectedBannerPhoto: PhotosPickerItem?
    @State private var selectedFeedFilter: HomeFeedFilter = .all
    @State private var selectedFederalState: AustrianFederalState?
    @State private var isRegionPickerPresented = false
    @State private var isShowingCreateNewsSheet = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                homeHeader
                    .padding(.bottom, AppTheme.homeHeaderHeroSpacing)

                homeHero
                    .padding(.bottom, AppTheme.homeSectionSpacing)

                HomeFilterRow(
                    selectedFilter: selectedFeedFilter,
                    selectedFederalState: selectedFederalState,
                    onSelectAll: selectAllFeed,
                    onSelectRegion: { isRegionPickerPresented = true },
                    onSelectSaved: { selectedFeedFilter = .saved },
                    onSelectSubscribed: { selectedFeedFilter = .subscribed }
                )
                    .padding(.bottom, AppTheme.homeSectionSpacing)

                AppGroupedContentPlane(padding: AppTheme.homeFeedPlanePadding) {
                    feedContent
                }
            }
            .padding(.horizontal, AppTheme.pageHorizontal)
            .padding(.bottom, AppTheme.homeBottomContentPadding)
        }
        .background(AppBackgroundView())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog(AppStrings.Home.regionAllAustria, isPresented: $isRegionPickerPresented, titleVisibility: .visible) {
            Button(AppStrings.Home.regionAllAustria) {
                selectedFederalState = nil
            }

            ForEach(AustrianFederalState.allCases) { federalState in
                Button(federalState.homeDisplayName) {
                    selectedFederalState = federalState
                }
            }

            Button(AppStrings.Events.cancel, role: .cancel) {}
        }
        .refreshable {
            await refreshAllContent()
        }
        .task {
            await loadContentIfNeeded()
            await refreshContentIfStale()
        }
        .onChange(of: selectedBannerPhoto) { _, newItem in
            Task {
                await updateHomeBanner(from: newItem)
                selectedBannerPhoto = nil
            }
        }
        .alert(
            AppStrings.Home.bannerUploadFailed,
            isPresented: Binding(
                get: { viewModel.bannerError != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.clearBannerError()
                    }
                }
            )
        ) {
            Button(AppStrings.News.dismissError, role: .cancel) {
                viewModel.clearBannerError()
            }
        }
        .sheet(isPresented: $isShowingCreateNewsSheet) {
            NavigationStack {
                createNewsEditor
            }
            .environmentObject(authState)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newsChanged).debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { _ in
            Task {
                async let homeRefresh: Void = viewModel.refresh()
                async let newsRefresh: Void = newsViewModel.refresh()
                _ = await (homeRefresh, newsRefresh)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eventsChanged).debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { _ in
            Task {
                async let homeRefresh: Void = viewModel.refresh()
                async let eventsRefresh: Void = eventsViewModel.refresh()
                _ = await (homeRefresh, eventsRefresh)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .organizationsChanged).debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { _ in
            Task {
                async let homeRefresh: Void = viewModel.refresh()
                async let organizationsRefresh: Void = organizationsViewModel.refresh()
                _ = await (homeRefresh, organizationsRefresh)
            }
        }
    }

    private var homeHero: some View {
        ZStack(alignment: .bottomTrailing) {
            AppHeroBanner(
                title: AppStrings.Home.bannerTitle,
                subtitle: AppStrings.Home.bannerSubtitle,
                imageSource: viewModel.bannerImageSource
            )

            if PermissionService.canManageHomeBanner(user: authState.user) {
                AppHeroBannerEditButton(
                    selectedItem: $selectedBannerPhoto,
                    isUploading: viewModel.isBannerUploading
                )
                .padding(10)
            }
        }
    }

    private var homeHeader: some View {
        AppBrandHeader {
            HStack(spacing: AppTheme.eventsControlGroupSpacing) {
                if canCreateHomeNews {
                    AppGlassIconButton(systemImage: "doc.badge.plus", accessibilityLabel: AppStrings.NewsEditor.addTitle) {
                        isShowingCreateNewsSheet = true
                    }
                }

                AppNotificationBellButton()
            }
        }
    }

    private var canCreateHomeNews: Bool {
        PermissionService.canCreateNews(user: authState.user) || managedNewsOrganization != nil
    }

    private var managedNewsOrganization: Organization? {
        guard let user = authState.user else { return nil }
        guard !PermissionService.canCreateNews(user: user) else { return nil }

        return organizationsViewModel.organizations.first { organization in
            PermissionService.canCreateNews(for: organization.id, user: user)
        }
    }

    @ViewBuilder
    private var createNewsEditor: some View {
        if PermissionService.canCreateNews(user: authState.user) {
            NewsEditorView(repository: newsRepository, onPublished: refreshNewsAfterPublish)
        } else if let organization = managedNewsOrganization {
            NewsEditorView(
                repository: newsRepository,
                organizationId: organization.id,
                organizationName: organization.name,
                organizationImageURL: organization.imageURL,
                organizationFederalState: organization.federalState,
                onPublished: refreshNewsAfterPublish
            )
        } else {
            EmptyView()
        }
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
                title: AppStrings.Tabs.home,
                message: emptyStateMessage
            )
            .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            DashboardFeedContainer(items: filteredFeedItems, spacing: AppTheme.feedRowSpacing) { item in
                NavigationLink {
                    destinationView(for: item)
                } label: {
                    HomeFeedCard(item: item)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var filteredFeedItems: [HomeFeedItem] {
        viewModel.feedItems.filter { item in
            matchesSelectedRegion(item) && matchesSelectedFilter(item)
        }
    }

    private func matchesSelectedRegion(_ item: HomeFeedItem) -> Bool {
        guard let selectedFederalState else { return true }
        return item.federalState == selectedFederalState
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
        if item.isSaved {
            return true
        }

        guard case let .news(id) = item.destination else {
            return false
        }

        return newsViewModel.post(for: id)?.isBookmarked == true
    }

    private func isSubscribedSource(_ item: HomeFeedItem) -> Bool {
        guard item.sourceType == .organization else {
            return true
        }

        guard let organizationId = item.organizationId else {
            return false
        }

        return subscribedOrganizationIDs.contains(organizationId)
    }

    private var subscribedOrganizationIDs: Set<String> {
        Set(authState.user?.communityMemberships.map(\.organizationId) ?? [])
    }

    private func selectAllFeed() {
        selectedFeedFilter = .all
        selectedFederalState = nil
    }

    private var emptyStateSystemImage: String {
        switch selectedFeedFilter {
        case .all:
            selectedFederalState == nil ? "tray" : "mappin.and.ellipse"
        case .saved:
            "bookmark"
        case .subscribed:
            "person.2"
        }
    }

    private var emptyStateMessage: String {
        switch selectedFeedFilter {
        case .all:
            selectedFederalState == nil ? AppStrings.Common.noItems : AppStrings.Home.emptyRegion
        case .saved:
            AppStrings.Home.emptySaved
        case .subscribed:
            AppStrings.Home.emptySubscribed
        }
    }

    private func loadContentIfNeeded() async {
        async let homeLoad: Void = viewModel.loadIfNeeded()
        async let bannerLoad: Void = viewModel.loadBannerIfNeeded()
        async let newsLoad: Void = newsViewModel.loadIfNeeded()
        async let eventsLoad: Void = eventsViewModel.loadIfNeeded()
        async let organizationsLoad: Void = organizationsViewModel.loadIfNeeded()
        _ = await (homeLoad, bannerLoad, newsLoad, eventsLoad, organizationsLoad)
    }

    private func refreshContentIfStale() async {
        async let homeRefresh: Void = viewModel.refreshIfStale()
        async let bannerLoad: Void = viewModel.loadBannerIfNeeded()
        async let newsRefresh: Void = newsViewModel.refreshIfStale()
        async let eventsRefresh: Void = eventsViewModel.refreshIfStale()
        async let organizationsRefresh: Void = organizationsViewModel.refreshIfStale()
        _ = await (homeRefresh, bannerLoad, newsRefresh, eventsRefresh, organizationsRefresh)
    }

    private func refreshAllContent() async {
        async let homeRefresh: Void = viewModel.refresh()
        async let bannerRefresh: Void = viewModel.refreshBanner()
        async let newsRefresh: Void = newsViewModel.refresh()
        async let eventsRefresh: Void = eventsViewModel.refresh()
        async let organizationsRefresh: Void = organizationsViewModel.refresh()
        _ = await (homeRefresh, bannerRefresh, newsRefresh, eventsRefresh, organizationsRefresh)
    }

    @MainActor
    private func refreshNewsAfterPublish() async {
        async let homeRefresh: Void = viewModel.refresh()
        async let newsRefresh: Void = newsViewModel.refresh()
        _ = await (homeRefresh, newsRefresh)
    }

    private func updateHomeBanner(from item: PhotosPickerItem?) async {
        guard let item else { return }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                viewModel.setBannerSelectionFailed()
                return
            }

            await viewModel.updateHomeBannerImage(data: data, user: authState.user)
        } catch {
            viewModel.setBannerSelectionFailed()
        }
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
        switch item.destination {
        case let .news(id):
            NewsDetailView(viewModel: newsViewModel, postID: id, onNewsDeleted: {})
        case let .event(id):
            EventDetailView(viewModel: eventsViewModel, eventID: id, onEventDeleted: {})
        case let .organization(id):
            OrganizationDetailView(viewModel: organizationsViewModel, organizationID: id)
        }
    }
}

private enum HomeFeedFilter {
    case all
    case saved
    case subscribed
}

private struct HomeFilterRow: View {
    let selectedFilter: HomeFeedFilter
    let selectedFederalState: AustrianFederalState?
    let onSelectAll: () -> Void
    let onSelectRegion: () -> Void
    let onSelectSaved: () -> Void
    let onSelectSubscribed: () -> Void

    var body: some View {
        AppHorizontalFilterRow {
            Button(action: onSelectAll) {
                AppFilterChip(title: AppStrings.Home.filterAll, systemImage: "square.grid.2x2", isSelected: selectedFilter == .all && selectedFederalState == nil)
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

            Button(action: onSelectSaved) {
                AppFilterChip(title: AppStrings.Home.filterSaved, systemImage: "bookmark", isSelected: selectedFilter == .saved)
            }
            .buttonStyle(.plain)

            Button(action: onSelectSubscribed) {
                AppFilterChip(title: AppStrings.Home.filterSubscribed, systemImage: "person.2.fill", isSelected: selectedFilter == .subscribed)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct HomeFeedCard: View {
    let item: HomeFeedItem

    var body: some View {
        SoftContentCard(padding: AppTheme.homeFeedCardPadding) {
            HStack(alignment: cardVerticalAlignment, spacing: 10) {
                leadingMedia

                VStack(alignment: .leading, spacing: 4) {
                    typeChip

                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)

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

                Spacer(minLength: 2)

                rightAccessory
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
        .frame(width: thumbnailSize, alignment: .top)
    }

    private var cardVerticalAlignment: VerticalAlignment {
        item.itemType == .event ? .center : .top
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
                .frame(minHeight: AppTheme.feedThumbnailSize + 12, alignment: .center)
            }
        } else {
            VStack(alignment: .trailing, spacing: 8) {
                timestampText
                Spacer(minLength: 8)
                bookmarkIcon
            }
            .frame(minHeight: AppTheme.feedThumbnailSize)
        }
    }

    private func publisherLine(title: String) -> some View {
        Label(title, systemImage: "person.crop.circle")
            .font(.caption2.weight(.medium))
            .foregroundStyle(AppTheme.textSecondary.opacity(0.86))
            .lineLimit(1)
            .minimumScaleFactor(0.82)
    }

    private var bookmarkIcon: some View {
        Image(systemName: "bookmark")
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary.opacity(0.78))
            .frame(width: 20, height: 20)
    }

    private var metadataLine: some View {
        AppMetadataLine(title: primaryMetadataText, systemImage: primaryMetadataIcon)
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
        item.itemType == .event ? AppTheme.feedThumbnailSize + 2 : AppTheme.feedThumbnailSize + 8
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
        let sourceName = normalizedPublisherName(item.organizationName) ?? AppStrings.Home.brandTitle

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

        parts.append("\(item.likeCount) \(AppStrings.Common.likes)")
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
                organizationRepository: MockOrganizationRepository(),
                homeBannerService: MockHomeBannerService()
            ),
            newsViewModel: NewsViewModel(repository: MockNewsRepository()),
            eventsViewModel: EventsViewModel(repository: MockEventRepository()),
            organizationsViewModel: OrganizationsViewModel(repository: MockOrganizationRepository()),
            newsRepository: MockNewsRepository()
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
