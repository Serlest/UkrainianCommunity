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
    @ObservedObject private var recentViewsViewModel: RecentViewsViewModel
    @ObservedObject private var newsViewModel: NewsViewModel
    @ObservedObject private var eventsViewModel: EventsViewModel
    @ObservedObject private var organizationsViewModel: OrganizationsViewModel
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

    private var filteredItems: [RecentViewItem] {
        recentViewsViewModel.items
            .filter { selectedSegment.matches($0) }
            .sorted(by: recentViewSort)
    }

    private var isLoading: Bool {
        recentViewsViewModel.isLoading && recentViewsViewModel.items.isEmpty
    }

    var body: some View {
        ProfileDestinationLayout(
            title: AppStrings.Profile.recentlyViewed,
            introSubtitle: AppStrings.Profile.recentlyViewedIntro,
            clearAction: recentViewsViewModel.items.isEmpty ? nil : ProfileDestinationClearAction(
                accessibilityLabel: AppStrings.Profile.recentlyViewedClear,
                isLoading: recentViewsViewModel.isClearing,
                action: { isShowingClearConfirmation = true }
            )
        ) {
            AppHorizontalFilterRow {
                ForEach(RecentViewsSegment.allCases) { segment in
                    Button {
                        selectedSegment = segment
                    } label: {
                        AppFilterChip(
                            title: "\(segment.title): \(recentViewsViewModel.items.filter { segment.matches($0) }.count)",
                            systemImage: segment.systemImage,
                            isSelected: selectedSegment == segment
                        )
                    }
                    .buttonStyle(.plain)
                }

                AppSortMenu(
                    selection: $sortOption,
                    options: [.newest, .oldest, .nameAscending, .nameDescending]
                )
            }

            recentViewsContent
        }
        .task(id: authState.user?.id) {
            guard let userID = authState.user?.id, authState.isAuthenticated else {
                recentViewsViewModel.resetForAuthChange()
                return
            }
            await loadRecentViewsIfNeeded(userID: userID)
        }
        .refreshable {
            await refreshRecentViews()
        }
        .confirmationDialog(
            AppStrings.Profile.recentlyViewedClearConfirmationTitle,
            isPresented: $isShowingClearConfirmation
        ) {
            Button(AppStrings.Profile.recentlyViewedClear, role: .destructive) {
                Task { await recentViewsViewModel.clearHistory() }
            }
            Button(AppStrings.Common.cancel, role: .cancel) {}
        } message: {
            Text(AppStrings.Profile.recentlyViewedClearConfirmationMessage)
        }
        .confirmationDialog(
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
            }
            Button(AppStrings.Common.cancel, role: .cancel) { itemPendingDeletion = nil }
        }
    }

    @ViewBuilder
    private var recentViewsContent: some View {
        if isLoading {
            LoadingStateCard(title: AppStrings.Profile.recentlyViewed)
        } else if let error = recentViewsViewModel.error, recentViewsViewModel.items.isEmpty {
            ErrorStateCard(
                title: AppStrings.Profile.recentlyViewed,
                message: recentViewsErrorMessage(error),
                retryTitle: AppStrings.Action.retry
            ) {
                Task { await recentViewsViewModel.refresh() }
            }
        } else if filteredItems.isEmpty {
            ProfileDestinationEmptyStateCard(
                systemImage: "clock.arrow.circlepath",
                title: AppStrings.Profile.recentlyViewedEmptyTitle,
                message: AppStrings.Profile.recentlyViewedEmptyMessage
            )
        } else {
            LazyVStack(spacing: AppTheme.feedRowSpacing) {
                if let error = recentViewsViewModel.error {
                    InlineMessageCard(style: .error, message: recentViewsErrorMessage(error))
                }
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
                            .accessibilityIdentifier("recentViews.delete.\(item.id)")
                        }
                    }
                }
            }
        }
    }

    private func loadRecentViewsIfNeeded(userID: String) async {
        async let recentViewsLoad: Void = recentViewsViewModel.loadIfNeeded(userID: userID)
        async let newsLoad: Void = newsViewModel.loadIfNeeded()
        async let eventsLoad: Void = eventsViewModel.loadIfNeeded()
        async let organizationsLoad: Void = organizationsViewModel.loadIfNeeded()
        _ = await (recentViewsLoad, newsLoad, eventsLoad, organizationsLoad)
    }

    private func refreshRecentViews() async {
        async let recentViewsRefresh: Void = recentViewsViewModel.refresh()
        async let newsRefresh: Void = newsViewModel.refresh()
        async let eventsRefresh: Void = eventsViewModel.refresh()
        async let organizationsRefresh: Void = organizationsViewModel.refresh()
        _ = await (recentViewsRefresh, newsRefresh, eventsRefresh, organizationsRefresh)
    }

    private func recentViewsErrorMessage(_ error: AppError) -> String {
        switch error {
        case .permissionDenied:
            return AppStrings.Auth.requiredTitle
        case .network:
            return AppStrings.News.loadNetworkError
        case .validationFailed, .notFound:
            return AppStrings.News.loadValidationError
        case .unknown:
            return AppStrings.News.loadUnknownError
        }
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
                    onNewsDeleted: { newsViewModel.reload() }
                )
            } label: {
                RecentViewRow(item: item)
            }
            .buttonStyle(.plain)
        case .event:
            NavigationLink {
                EventDetailView(
                    viewModel: eventsViewModel,
                    eventID: item.itemId,
                    onEventDeleted: { @MainActor @Sendable in
                        eventsViewModel.reload()
                    }
                )
            } label: {
                RecentViewRow(item: item)
            }
            .buttonStyle(.plain)
        case .organization:
            NavigationLink {
                OrganizationDetailView(viewModel: organizationsViewModel, organizationID: item.itemId)
            } label: {
                RecentViewRow(item: item)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct RecentViewRow: View {
    let item: RecentViewItem

    private var subtitle: String {
        let trimmedSubtitle = item.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedSubtitle.isEmpty ? item.itemType.title : trimmedSubtitle
    }

    private var viewedAtText: String {
        LocalizationStore.dateString(from: item.viewedAt, dateStyle: .medium, timeStyle: .short)
    }

    var body: some View {
        AppEditorSectionCard {
            HStack(alignment: .center, spacing: 12) {
                AppFeedThumbnail(
                    imageURL: item.imageURL,
                    fallbackSystemImage: item.itemType.systemImage,
                    tint: AppTheme.accentPrimaryForeground,
                    fill: AppTheme.accentPrimary.opacity(0.10),
                    size: 58,
                    cornerRadius: 12,
                    source: "RecentViewRow"
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)

                    Label(viewedAtText, systemImage: "clock")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
