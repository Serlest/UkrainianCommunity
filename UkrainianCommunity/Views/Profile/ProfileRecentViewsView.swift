import SwiftUI

private enum RecentViewsSegment: String, CaseIterable, Identifiable {
    case all
    case news
    case events
    case organizations

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return AppStrings.Home.filterAll
        case .news:
            return AppStrings.News.title
        case .events:
            return AppStrings.Events.title
        case .organizations:
            return AppStrings.Tabs.organizations
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "square.grid.2x2"
        case .news:
            return RecentViewItemType.news.systemImage
        case .events:
            return RecentViewItemType.event.systemImage
        case .organizations:
            return RecentViewItemType.organization.systemImage
        }
    }

    func matches(_ item: RecentViewItem) -> Bool {
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


struct RecentViewsView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var recentViewsViewModel: RecentViewsViewModel
    @ObservedObject private var newsViewModel: NewsViewModel
    @ObservedObject private var eventsViewModel: EventsViewModel
    @ObservedObject private var organizationsViewModel: OrganizationsViewModel
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var selectedSegment: RecentViewsSegment = .all
    @State private var sortOption: AppListSortOption = .newest
    @State private var isShowingClearConfirmation = false
    @State private var itemPendingDeletion: RecentViewItem?

    init(
        recentViewsViewModel: RecentViewsViewModel? = nil,
        recentViewsRepository: RecentViewsRepository = FirestoreRecentViewsRepository(),
        newsViewModel: NewsViewModel? = nil,
        eventsViewModel: EventsViewModel? = nil,
        organizationsViewModel: OrganizationsViewModel? = nil,
        newsRepository: NewsRepository = FirestoreNewsRepository(),
        eventRepository: EventRepository = FirestoreEventRepository(),
        organizationRepository: OrganizationRepository = FirestoreOrganizationRepository()
    ) {
        self.recentViewsViewModel = recentViewsViewModel ?? RecentViewsViewModel(repository: recentViewsRepository)
        self.newsViewModel = newsViewModel ?? NewsViewModel(repository: newsRepository)
        self.eventsViewModel = eventsViewModel ?? EventsViewModel(repository: eventRepository)
        self.organizationsViewModel = organizationsViewModel ?? OrganizationsViewModel(repository: organizationRepository)
    }

    private var visibleItems: [RecentViewItem] {
        recentViewsViewModel.items
            .filter(isVisibleRecentView)
    }

    private var filteredItems: [RecentViewItem] {
        visibleItems
            .filter { selectedSegment.matches($0) }
            .filter { item in
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                return query.isEmpty || item.title.localizedStandardContains(query)
                    || (item.subtitle?.localizedStandardContains(query) ?? false)
            }
            .sorted(by: recentViewSort)
    }

    private var isLoading: Bool {
        recentViewsViewModel.isLoading && recentViewsViewModel.items.isEmpty
    }

    var body: some View {
        ProfileDestinationLayout(
            title: AppStrings.Profile.recentlyViewed,
            introSubtitle: AppStrings.Profile.recentlyViewedIntro,
            clearAction: recentViewsViewModel.items.isEmpty || recentViewsViewModel.isLoading || !recentViewsViewModel.deletingIDs.isEmpty ? nil : ProfileDestinationClearAction(
                accessibilityLabel: AppStrings.Profile.recentlyViewedClear,
                isLoading: recentViewsViewModel.isClearing,
                action: { isShowingClearConfirmation = true }
            )
        ) {
            AppSearchField(placeholder: RecentViewsText.search, text: $searchText, focus: $isSearchFocused, fieldID: "recentViews.search")
            Text(RecentViewsText.limit).font(.footnote).foregroundStyle(AppTheme.textSecondary)
            historyFilters

            recentViewsContent
        }
        .task(id: authState.user?.id) {
            guard let userID = authState.user?.id, authState.isAuthenticated else {
                recentViewsViewModel.resetForAuthChange()
                return
            }
            await loadRecentViewsOnAppearance(userID: userID)
        }
        .onChange(of: authState.user?.id) { _, _ in
            searchText = ""
            selectedSegment = .all
            sortOption = .newest
            isShowingClearConfirmation = false
            itemPendingDeletion = nil
        }
        .onReceive(RecentViewRecorder.didRecord) { event in
            guard authState.isAuthenticated, authState.user?.id == event.userID else { return }
            recentViewsViewModel.applyRecordedView(event.item, userID: event.userID)
        }
        .appRefreshable {
            await refreshRecentViews()
        }
        .alert(
            AppStrings.Profile.recentlyViewedClearConfirmationTitle,
            isPresented: $isShowingClearConfirmation
        ) {
            Button(AppStrings.Profile.recentlyViewedClear, role: .destructive) {
                Task { await recentViewsViewModel.clearHistory() }
            }.accessibilityIdentifier("recentViews.clear.confirm")
            Button(AppStrings.Common.cancel, role: .cancel) {}
        } message: {
            Text(AppStrings.Profile.recentlyViewedClearConfirmationMessage)
        }
        .alert(
            AppStrings.Profile.recentlyViewedDeleteConfirmationTitle,
            isPresented: Binding(
                get: { itemPendingDeletion != nil },
                set: { if !$0 { itemPendingDeletion = nil } }
            )
        ) {
            Button(AppStrings.Action.delete, role: .destructive) {
                guard let item = itemPendingDeletion else { return }
                itemPendingDeletion = nil
                Task { await recentViewsViewModel.delete(item) }
            }.accessibilityIdentifier("recentViews.delete.confirm")
            Button(AppStrings.Common.cancel, role: .cancel) { itemPendingDeletion = nil }
        }
    }

    @ViewBuilder
    private var historyFilters: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                Picker(RecentViewsText.contentType, selection: $selectedSegment) {
                    ForEach(RecentViewsSegment.allCases) { segment in
                        Text("\(segment.title): \(visibleItems.filter { segment.matches($0) }.count)")
                            .tag(segment)
                    }
                }
                .pickerStyle(.menu)
                .tint(AppTheme.accentPrimaryForeground)
                .accessibilityIdentifier("recentViews.filter")
                historySortMenu
            }
        } else {
            AppHorizontalFilterRow {
                ForEach(RecentViewsSegment.allCases) { segment in
                    Button {
                        selectedSegment = segment
                    } label: {
                        AppFilterChip(
                            title: "\(segment.title): \(visibleItems.filter { segment.matches($0) }.count)",
                            systemImage: segment.systemImage,
                            isSelected: selectedSegment == segment
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("recentViews.filter.\(segment.rawValue)")
                }
                historySortMenu
            }
        }
    }

    private var historySortMenu: some View {
        AppSortMenu(selection: $sortOption, options: [.newest, .oldest, .nameAscending, .nameDescending])
    }

    @ViewBuilder
    private var recentViewsContent: some View {
        if isLoading {
            LoadingStateCard(title: AppStrings.Profile.recentlyViewed).accessibilityIdentifier("recentViews.loading")
        } else if let error = recentViewsViewModel.error, recentViewsViewModel.items.isEmpty {
            ErrorStateCard(
                title: AppStrings.Profile.recentlyViewed,
                message: recentViewsErrorMessage(error),
                retryTitle: AppStrings.Action.retry
            ) {
                Task { await recentViewsViewModel.refresh() }
            }.accessibilityIdentifier("recentViews.error")
        } else {
            if let error = recentViewsViewModel.error {
                InlineMessageCard(style: .error, message: recentViewsErrorMessage(error))
            }
            if filteredItems.isEmpty {
                ProfileDestinationEmptyStateCard(
                    systemImage: "clock.arrow.circlepath",
                    title: visibleItems.isEmpty ? AppStrings.Profile.recentlyViewedEmptyTitle : AppStrings.Search.noResultsTitle,
                    message: visibleItems.isEmpty ? AppStrings.Profile.recentlyViewedEmptyMessage : RecentViewsText.filteredEmpty
                )
            } else {
                LazyVStack(spacing: AppTheme.feedRowSpacing) {
                    ForEach(filteredItems) { item in
                        HStack(spacing: AppTheme.eventsMetadataSpacing) {
                            recentItemLink(item)
                            if recentViewsViewModel.deletingIDs.contains(item.id) {
                                ProgressView().controlSize(.small)
                                    .frame(width: AppTheme.minimumInteractiveTarget, height: AppTheme.minimumInteractiveTarget)
                            } else {
                                AppGlassIconButton(
                                    systemImage: "trash",
                                    accessibilityLabel: AppStrings.Action.delete,
                                    role: .destructive
                                ) { itemPendingDeletion = item }
                                .disabled(recentViewsViewModel.isLoading || recentViewsViewModel.isMutating)
                                .accessibilityIdentifier("recentViews.delete.\(item.id)")
                            }
                        }
                    }
                }
            }
        }
    }

    private func loadRecentViewsOnAppearance(userID: String) async {
        await recentViewsViewModel.refresh(userID: userID)
    }

    private func isVisibleRecentView(_ item: RecentViewItem) -> Bool {
        let policy = organizationsViewModel.visibilityPolicy
        switch item.itemType {
        case .organization:
            return policy.allows(organizationID: item.itemId)
        case .news, .event:
            guard let organizationID = item.organizationID else {
                // Legacy snapshots predate organizationID. Preserve their private
                // historical metadata; detail resolution still enforces visibility.
                return true
            }
            return policy.allows(organizationID: organizationID)
        }
    }

    private func refreshRecentViews() async {
        guard let userID = authState.user?.id, authState.isAuthenticated else { return }
        await recentViewsViewModel.refresh(userID: userID)
    }

    private func recentViewsErrorMessage(_ error: AppError) -> String {
        error == .network ? RecentViewsText.networkError : RecentViewsText.loadError
    }

    private func recentViewSort(_ lhs: RecentViewItem, _ rhs: RecentViewItem) -> Bool {
        switch sortOption {
        case .newest:
            lhs.viewedAt == rhs.viewedAt ? lhs.id < rhs.id : lhs.viewedAt > rhs.viewedAt
        case .oldest:
            lhs.viewedAt == rhs.viewedAt ? lhs.id < rhs.id : lhs.viewedAt < rhs.viewedAt
        case .nameAscending:
            compareTitles(lhs.title, rhs.title, lhsID: lhs.id, rhsID: rhs.id, ascending: true)
        case .nameDescending:
            compareTitles(lhs.title, rhs.title, lhsID: lhs.id, rhsID: rhs.id, ascending: false)
        case .popular:
            lhs.viewedAt == rhs.viewedAt ? lhs.id < rhs.id : lhs.viewedAt > rhs.viewedAt
        }
    }

    private func compareTitles(
        _ lhs: String,
        _ rhs: String,
        lhsID: String,
        rhsID: String,
        ascending: Bool
    ) -> Bool {
        let result = LocalizationStore.compareForSorting(lhs, rhs)
        guard result != .orderedSame else { return lhsID < rhsID }
        return ascending ? result == .orderedAscending : result == .orderedDescending
    }

    @ViewBuilder
    private func recentItemLink(_ item: RecentViewItem) -> some View {
        switch item.itemType {
        case .news:
            NavigationLink {
                NewsDetailView(
                    viewModel: newsViewModel,
                    postID: item.itemId,
                    onNewsDeleted: { Task { await recentViewsViewModel.delete(item) } }
                )
            } label: {
                RecentViewRow(item: item)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("recentViews.open.\(item.id)")
        case .event:
            NavigationLink {
                EventDetailView(
                    viewModel: eventsViewModel,
                    eventID: item.itemId,
                    onEventDeleted: { @MainActor @Sendable in
                        Task { await recentViewsViewModel.delete(item) }
                    }
                )
            } label: {
                RecentViewRow(item: item)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("recentViews.open.\(item.id)")
        case .organization:
            NavigationLink {
                OrganizationDetailView(viewModel: organizationsViewModel, organizationID: item.itemId)
            } label: {
                RecentViewRow(item: item)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("recentViews.open.\(item.id)")
        }
    }
}

private struct RecentViewRow: View {
    let item: RecentViewItem
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var subtitle: String {
        let trimmedSubtitle = item.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedSubtitle.isEmpty ? item.itemType.title : trimmedSubtitle
    }

    private var viewedAtText: String {
        LocalizationStore.dateString(from: item.viewedAt, dateStyle: .medium, timeStyle: .short)
    }

    var body: some View {
        AppEditorSectionCard {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                compactLayout
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var compactLayout: some View {
        HStack(alignment: .center, spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 6) {
                title
                subtitleText
                viewedAtLabel
            }

            Spacer(minLength: 0)
        }
    }

    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            thumbnail
            title
                .frame(maxWidth: .infinity, alignment: .leading)
            subtitleText
            viewedAtLabel
        }
    }

    private var thumbnail: some View {
        AppFeedThumbnail(
            imageURL: item.imageURL,
            fallbackSystemImage: item.itemType.systemImage,
            tint: AppTheme.accentPrimaryForeground,
            fill: AppTheme.accentPrimary.opacity(0.10),
            size: 58,
            cornerRadius: 12,
            source: "RecentViewRow"
        )
    }

    private var title: some View {
        Text(item.title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.textPrimary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var subtitleText: some View {
        Text(subtitle)
            .font(.caption)
            .foregroundStyle(AppTheme.textSecondary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var viewedAtLabel: some View {
        Label(viewedAtText, systemImage: "clock")
            .font(.caption2.weight(.medium))
            .foregroundStyle(AppTheme.textSecondary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .fixedSize(horizontal: false, vertical: true)
    }

}
