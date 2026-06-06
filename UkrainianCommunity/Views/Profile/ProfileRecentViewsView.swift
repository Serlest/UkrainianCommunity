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
            return item.itemType != .guide
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
    @StateObject private var recentViewsViewModel: RecentViewsViewModel
    @ObservedObject private var newsViewModel: NewsViewModel
    @ObservedObject private var eventsViewModel: EventsViewModel
    @ObservedObject private var organizationsViewModel: OrganizationsViewModel
    @State private var selectedSegment: RecentViewsSegment = .all
    @State private var configuredUserID: String?

    init(
        recentViewsRepository: RecentViewsRepository = FirestoreRecentViewsRepository(),
        newsViewModel: NewsViewModel? = nil,
        eventsViewModel: EventsViewModel? = nil,
        organizationsViewModel: OrganizationsViewModel? = nil,
        newsRepository: NewsRepository = FirestoreNewsRepository(),
        eventRepository: EventRepository = FirestoreEventRepository(),
        organizationRepository: OrganizationRepository = FirestoreOrganizationRepository()
    ) {
        _recentViewsViewModel = StateObject(wrappedValue: RecentViewsViewModel(repository: recentViewsRepository))
        self.newsViewModel = newsViewModel ?? NewsViewModel(repository: newsRepository)
        self.eventsViewModel = eventsViewModel ?? EventsViewModel(repository: eventRepository)
        self.organizationsViewModel = organizationsViewModel ?? OrganizationsViewModel(repository: organizationRepository)
    }

    private var filteredItems: [RecentViewItem] {
        recentViewsViewModel.items
            .filter { selectedSegment.matches($0) }
            .sorted { $0.viewedAt > $1.viewedAt }
    }

    private var isLoading: Bool {
        recentViewsViewModel.isLoading && recentViewsViewModel.items.isEmpty
    }

    var body: some View {
        ProfileDestinationLayout(
            title: AppStrings.Profile.recentlyViewed,
            introSubtitle: AppStrings.Profile.recentlyViewedIntro
        ) {
            AppHorizontalFilterRow {
                ForEach(RecentViewsSegment.allCases) { segment in
                    Button {
                        selectedSegment = segment
                    } label: {
                        AppFilterChip(
                            title: segment.title,
                            systemImage: segment.systemImage,
                            isSelected: selectedSegment == segment
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            recentViewsContent
        }
        .task(id: authState.user?.id) {
            guard configuredUserID != authState.user?.id else { return }
            configuredUserID = authState.user?.id
            resetRecentViewsState()
            guard authState.isAuthenticated else { return }
            await loadRecentViewsIfNeeded()
        }
        .refreshable {
            await refreshRecentViews()
        }
    }

    @ViewBuilder
    private var recentViewsContent: some View {
        if isLoading {
            LoadingStateCard(title: AppStrings.Profile.recentlyViewed)
        } else if let error = recentViewsViewModel.error, recentViewsViewModel.items.isEmpty {
            ProfileDestinationEmptyStateCard(
                systemImage: "exclamationmark.triangle",
                title: AppStrings.Profile.recentlyViewed,
                message: recentViewsErrorMessage(error)
            )
        } else if filteredItems.isEmpty {
            ProfileDestinationEmptyStateCard(
                systemImage: "clock.arrow.circlepath",
                title: AppStrings.Profile.recentlyViewedEmptyTitle,
                message: AppStrings.Profile.recentlyViewedEmptyMessage
            )
        } else {
            VStack(spacing: AppTheme.feedRowSpacing) {
                ForEach(filteredItems) { item in
                    recentItemLink(item)
                }
            }
        }
    }

    private func loadRecentViewsIfNeeded() async {
        async let recentViewsLoad: Void = recentViewsViewModel.loadIfNeeded()
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

    private func resetRecentViewsState() {
        recentViewsViewModel.resetForAuthChange()
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
        case .guide:
            RecentViewRow(item: item)
                .opacity(0.72)
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
                    tint: AppTheme.accentPrimary,
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
