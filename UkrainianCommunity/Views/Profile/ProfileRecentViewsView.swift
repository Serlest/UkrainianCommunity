import SwiftUI

private enum RecentViewsSegment: String, CaseIterable, Identifiable {
    case all
    case news
    case events
    case organizations
    case guide

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
        case .guide:
            return AppStrings.Guide.title
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
        case .guide:
            return RecentViewItemType.guide.systemImage
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
        case .guide:
            return item.itemType == .guide
        }
    }
}


struct RecentViewsView: View {
    @EnvironmentObject private var authState: AuthState
    @ObservedObject private var recentViewsViewModel: RecentViewsViewModel
    @ObservedObject private var newsViewModel: NewsViewModel
    @ObservedObject private var eventsViewModel: EventsViewModel
    @ObservedObject private var organizationsViewModel: OrganizationsViewModel
    @StateObject private var guideReaderViewModel: GuideReaderViewModel
    private let feedbackRepository: FeedbackRepository
    @State private var selectedSegment: RecentViewsSegment = .all

    init(
        recentViewsViewModel: RecentViewsViewModel? = nil,
        recentViewsRepository: RecentViewsRepository = FirestoreRecentViewsRepository(),
        newsViewModel: NewsViewModel? = nil,
        eventsViewModel: EventsViewModel? = nil,
        organizationsViewModel: OrganizationsViewModel? = nil,
        newsRepository: NewsRepository = FirestoreNewsRepository(),
        eventRepository: EventRepository = FirestoreEventRepository(),
        organizationRepository: OrganizationRepository = FirestoreOrganizationRepository(),
        guideRepository: GuideRepositoryProtocol = FirestoreGuideRepository(),
        feedbackRepository: FeedbackRepository = FirestoreFeedbackRepository()
    ) {
        self.recentViewsViewModel = recentViewsViewModel ?? RecentViewsViewModel(repository: recentViewsRepository)
        self.newsViewModel = newsViewModel ?? NewsViewModel(repository: newsRepository)
        self.eventsViewModel = eventsViewModel ?? EventsViewModel(repository: eventRepository)
        self.organizationsViewModel = organizationsViewModel ?? OrganizationsViewModel(repository: organizationRepository)
        _guideReaderViewModel = StateObject(wrappedValue: GuideReaderViewModel(repository: guideRepository))
        self.feedbackRepository = feedbackRepository
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
            guard let userID = authState.user?.id, authState.isAuthenticated else {
                recentViewsViewModel.resetForAuthChange()
                return
            }
            await loadRecentViewsIfNeeded(userID: userID)
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
            NavigationLink {
                RecentGuideMaterialDetailContainer(
                    materialID: item.itemId,
                    viewModel: guideReaderViewModel,
                    feedbackRepository: feedbackRepository
                )
            } label: {
                RecentViewRow(item: item)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct RecentGuideMaterialDetailContainer: View {
    let materialID: String
    @ObservedObject var viewModel: GuideReaderViewModel
    let feedbackRepository: FeedbackRepository
    @State private var material: GuideMaterial?
    @State private var error: AppError?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let material {
                GuideMaterialDetailView(
                    material: material,
                    viewModel: viewModel,
                    feedbackRepository: feedbackRepository
                )
            } else {
                PushedScreenShell(title: AppStrings.Guide.title) {
                    AppGroupedContentPlane {
                        if isLoading {
                            LoadingStateCard(title: AppStrings.Guide.title)
                        } else {
                            UnifiedEmptyStateCard(
                                systemImage: "doc.questionmark",
                                title: AppStrings.NotificationInbox.destinationUnavailableTitle,
                                message: routeErrorMessage
                            )
                        }
                    }
                }
            }
        }
        .task(id: materialID) {
            await loadMaterial()
        }
    }

    private var routeErrorMessage: String {
        switch error {
        case .notFound:
            return AppStrings.NotificationInbox.destinationUnavailableMessage
        case .network:
            return AppStrings.News.loadNetworkError
        case .permissionDenied:
            return AppStrings.News.loadPermissionError
        case .validationFailed:
            return AppStrings.News.loadValidationError
        case .unknown, nil:
            return AppStrings.NotificationInbox.destinationUnavailableMessage
        }
    }

    private func loadMaterial() async {
        isLoading = true
        defer { isLoading = false }

        do {
            material = try await viewModel.material(id: materialID)
            error = nil
        } catch let appError as AppError {
            material = nil
            error = appError
        } catch {
            material = nil
            self.error = .unknown
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
