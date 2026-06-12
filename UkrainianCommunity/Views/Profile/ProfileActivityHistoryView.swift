import SwiftUI

private enum ActivityHistorySegment: String, CaseIterable, Identifiable {
    case all
    case events
    case organizations
    case saved

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return AppStrings.Home.filterAll
        case .events:
            return AppStrings.Events.title
        case .organizations:
            return AppStrings.Tabs.organizations
        case .saved:
            return AppStrings.Profile.activityHistorySavedFilter
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "square.grid.2x2"
        case .events:
            return ActivityLogTargetType.event.systemImage
        case .organizations:
            return ActivityLogTargetType.organization.systemImage
        case .saved:
            return "bookmark"
        }
    }

    func matches(_ item: ActivityLogItem) -> Bool {
        switch self {
        case .all:
            return true
        case .events:
            return item.targetType == .event
        case .organizations:
            return item.targetType == .organization
        case .saved:
            return item.actionType.isSavedAction
        }
    }
}


struct ActivityHistoryView: View {
    @EnvironmentObject private var authState: AuthState
    @ObservedObject private var activityLogViewModel: ActivityLogViewModel
    @ObservedObject private var newsViewModel: NewsViewModel
    @ObservedObject private var eventsViewModel: EventsViewModel
    @ObservedObject private var organizationsViewModel: OrganizationsViewModel
    @State private var selectedSegment: ActivityHistorySegment = .all

    init(
        activityLogViewModel: ActivityLogViewModel? = nil,
        activityLogRepository: ActivityLogRepository = FirestoreActivityLogRepository(),
        newsViewModel: NewsViewModel? = nil,
        eventsViewModel: EventsViewModel? = nil,
        organizationsViewModel: OrganizationsViewModel? = nil,
        newsRepository: NewsRepository = FirestoreNewsRepository(),
        eventRepository: EventRepository = FirestoreEventRepository(),
        organizationRepository: OrganizationRepository = FirestoreOrganizationRepository()
    ) {
        self.activityLogViewModel = activityLogViewModel ?? ActivityLogViewModel(repository: activityLogRepository)
        self.newsViewModel = newsViewModel ?? NewsViewModel(repository: newsRepository)
        self.eventsViewModel = eventsViewModel ?? EventsViewModel(repository: eventRepository)
        self.organizationsViewModel = organizationsViewModel ?? OrganizationsViewModel(repository: organizationRepository)
    }

    private var filteredItems: [ActivityLogItem] {
        activityLogViewModel.items
            .filter { selectedSegment.matches($0) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var isLoading: Bool {
        activityLogViewModel.isLoading && activityLogViewModel.items.isEmpty
    }

    var body: some View {
        ProfileDestinationLayout(
            title: AppStrings.Profile.activityHistoryModule,
            introSubtitle: AppStrings.Profile.activityHistoryIntro
        ) {
            AppHorizontalFilterRow {
                ForEach(ActivityHistorySegment.allCases) { segment in
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

            activityHistoryContent
        }
        .task(id: authState.user?.id) {
            guard let userID = authState.user?.id, authState.isAuthenticated else {
                activityLogViewModel.resetForAuthChange()
                return
            }
            await loadActivityHistoryIfNeeded(userID: userID)
        }
        .refreshable {
            await refreshActivityHistory()
        }
    }

    @ViewBuilder
    private var activityHistoryContent: some View {
        if isLoading {
            LoadingStateCard(title: AppStrings.Profile.activityHistoryModule)
        } else if let error = activityLogViewModel.error, activityLogViewModel.items.isEmpty {
            ProfileDestinationEmptyStateCard(
                systemImage: "exclamationmark.triangle",
                title: AppStrings.Profile.activityHistoryModule,
                message: activityHistoryErrorMessage(error)
            )
        } else if filteredItems.isEmpty {
            ProfileDestinationEmptyStateCard(
                systemImage: "list.bullet.rectangle",
                title: AppStrings.Profile.activityHistoryEmptyTitle,
                message: AppStrings.Profile.activityHistoryEmptyMessage
            )
        } else {
            VStack(spacing: AppTheme.feedRowSpacing) {
                ForEach(filteredItems) { item in
                    activityItemLink(item)
                }
            }
        }
    }

    private func loadActivityHistoryIfNeeded(userID: String) async {
        async let activityLoad: Void = activityLogViewModel.loadIfNeeded(userID: userID)
        async let newsLoad: Void = newsViewModel.loadIfNeeded()
        async let eventsLoad: Void = eventsViewModel.loadIfNeeded()
        async let organizationsLoad: Void = organizationsViewModel.loadIfNeeded()
        _ = await (activityLoad, newsLoad, eventsLoad, organizationsLoad)
    }

    private func refreshActivityHistory() async {
        async let activityRefresh: Void = activityLogViewModel.refresh()
        async let newsRefresh: Void = newsViewModel.refresh()
        async let eventsRefresh: Void = eventsViewModel.refresh()
        async let organizationsRefresh: Void = organizationsViewModel.refresh()
        _ = await (activityRefresh, newsRefresh, eventsRefresh, organizationsRefresh)
    }

    private func activityHistoryErrorMessage(_ error: AppError) -> String {
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
    private func activityItemLink(_ item: ActivityLogItem) -> some View {
        switch item.targetType {
        case .news:
            if newsViewModel.post(for: item.targetId) != nil {
                NavigationLink {
                    NewsDetailView(
                        viewModel: newsViewModel,
                        postID: item.targetId,
                        onNewsDeleted: { newsViewModel.reload() }
                    )
                } label: {
                    ActivityHistoryRow(item: item, canOpenTarget: true)
                }
                .buttonStyle(.plain)
            } else {
                ActivityHistoryRow(item: item, canOpenTarget: false)
            }
        case .event:
            if eventsViewModel.event(for: item.targetId) != nil {
                NavigationLink {
                    EventDetailView(
                        viewModel: eventsViewModel,
                        eventID: item.targetId,
                        onEventDeleted: { @MainActor @Sendable in
                            eventsViewModel.reload()
                        }
                    )
                } label: {
                    ActivityHistoryRow(item: item, canOpenTarget: true)
                }
                .buttonStyle(.plain)
            } else {
                ActivityHistoryRow(item: item, canOpenTarget: false)
            }
        case .organization:
            if organizationsViewModel.organization(for: item.targetId) != nil {
                NavigationLink {
                    OrganizationDetailView(viewModel: organizationsViewModel, organizationID: item.targetId)
                } label: {
                    ActivityHistoryRow(item: item, canOpenTarget: true)
                }
                .buttonStyle(.plain)
            } else {
                ActivityHistoryRow(item: item, canOpenTarget: false)
            }
        }
    }
}

private struct ActivityHistoryRow: View {
    let item: ActivityLogItem
    let canOpenTarget: Bool

    private var subtitle: String {
        let trimmedSubtitle = item.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedSubtitle.isEmpty ? item.targetType.title : trimmedSubtitle
    }

    private var createdAtText: String {
        LocalizationStore.dateString(from: item.createdAt, dateStyle: .medium, timeStyle: .short)
    }

    var body: some View {
        AppEditorSectionCard {
            HStack(alignment: .center, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    AppFeedThumbnail(
                        imageURL: item.imageURL,
                        fallbackSystemImage: item.targetType.systemImage,
                        tint: AppTheme.accentPrimary,
                        fill: AppTheme.accentPrimary.opacity(0.10),
                        size: 58,
                        cornerRadius: 12,
                        source: "ActivityHistoryRow"
                    )

                    Image(systemName: item.actionType.systemImage)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(item.actionType.tint)
                        .frame(width: 22, height: 22)
                        .background(AppTheme.surfacePrimary, in: Circle())
                        .overlay(Circle().strokeBorder(AppTheme.borderSubtle))
                        .offset(x: 4, y: 4)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.actionType.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(item.actionType.tint)
                        .lineLimit(1)

                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)

                    Label(createdAtText, systemImage: "clock")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if canOpenTarget {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
        .opacity(canOpenTarget ? 1 : 0.72)
        .accessibilityElement(children: .combine)
    }
}
