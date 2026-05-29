import SwiftUI

private enum SavedContentSegment: String, CaseIterable, Identifiable {
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
            return "newspaper"
        case .events:
            return "calendar"
        case .organizations:
            return "building.2"
        }
    }
}

private enum SavedContentItem: Identifiable {
    case news(NewsPost)
    case event(Event)
    case organization(Organization)

    var id: String {
        switch self {
        case let .news(post):
            return "news-\(post.id)"
        case let .event(event):
            return "event-\(event.id)"
        case let .organization(organization):
            return "organization-\(organization.id)"
        }
    }

    var savedSortDate: Date {
        switch self {
        case let .news(post):
            return post.publishedAt
        case let .event(event):
            return event.startDate
        case let .organization(organization):
            return organization.updatedAt
        }
    }
}


struct SavedContentView: View {
    @StateObject private var newsViewModel: NewsViewModel
    @StateObject private var eventsViewModel: EventsViewModel
    @StateObject private var organizationsViewModel: OrganizationsViewModel
    @State private var selectedSegment: SavedContentSegment = .all

    init(
        newsRepository: NewsRepository = FirestoreNewsRepository(),
        eventRepository: EventRepository = FirestoreEventRepository(),
        organizationRepository: OrganizationRepository = FirestoreOrganizationRepository()
    ) {
        _newsViewModel = StateObject(wrappedValue: NewsViewModel(repository: newsRepository))
        _eventsViewModel = StateObject(wrappedValue: EventsViewModel(repository: eventRepository))
        _organizationsViewModel = StateObject(wrappedValue: OrganizationsViewModel(repository: organizationRepository))
    }

    private var isLoading: Bool {
        (newsViewModel.isLoading || eventsViewModel.isLoading || organizationsViewModel.isLoading)
            && newsViewModel.bookmarkedPosts.isEmpty
            && eventsViewModel.bookmarkedEvents.isEmpty
            && bookmarkedOrganizations.isEmpty
    }

    private var loadError: AppError? {
        newsViewModel.error ?? eventsViewModel.error ?? organizationsViewModel.error
    }

    var body: some View {
        ProfileDestinationLayout(
            title: AppStrings.Profile.savedContent,
            introSubtitle: AppStrings.Profile.savedContentIntro
        ) {
            AppHorizontalFilterRow {
                ForEach(SavedContentSegment.allCases) { segment in
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

            savedContent
        }
        .task {
            await loadSavedContentIfNeeded()
        }
        .refreshable {
            await refreshSavedContent()
        }
        .onReceive(NotificationCenter.default.publisher(for: .newsChanged)) { _ in
            Task { await newsViewModel.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eventsChanged)) { _ in
            Task { await eventsViewModel.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .organizationsChanged)) { _ in
            Task { await organizationsViewModel.refresh() }
        }
    }

    @ViewBuilder
    private var savedContent: some View {
        if isLoading {
            LoadingStateCard(title: AppStrings.Profile.savedContent)
        } else if let loadError, currentItemsAreEmpty {
            ProfileDestinationEmptyStateCard(
                systemImage: "exclamationmark.triangle",
                title: AppStrings.Profile.savedContent,
                message: savedErrorMessage(loadError)
            )
        } else if currentItemsAreEmpty {
            ProfileDestinationEmptyStateCard(
                systemImage: emptyStateSystemImage,
                title: selectedSegment.title,
                message: emptyStateMessage
            )
        } else {
            VStack(spacing: AppTheme.feedRowSpacing) {
                switch selectedSegment {
                case .all:
                    ForEach(savedItems) { item in
                        savedItemLink(item)
                    }
                case .news:
                    ForEach(newsViewModel.bookmarkedPosts) { post in
                        savedNewsLink(post)
                    }
                case .events:
                    ForEach(eventsViewModel.bookmarkedEvents) { event in
                        savedEventLink(event)
                    }
                case .organizations:
                    ForEach(bookmarkedOrganizations) { organization in
                        savedOrganizationLink(organization)
                    }
                }
            }
        }
    }

    private var savedItems: [SavedContentItem] {
        (
            newsViewModel.bookmarkedPosts.map(SavedContentItem.news)
            + eventsViewModel.bookmarkedEvents.map(SavedContentItem.event)
            + bookmarkedOrganizations.map(SavedContentItem.organization)
        )
        .sorted { $0.savedSortDate > $1.savedSortDate }
    }

    private var bookmarkedOrganizations: [Organization] {
        organizationsViewModel.organizations.filter(\.isBookmarked)
    }

    private var currentItemsAreEmpty: Bool {
        switch selectedSegment {
        case .all:
            return savedItems.isEmpty
        case .news:
            return newsViewModel.bookmarkedPosts.isEmpty
        case .events:
            return eventsViewModel.bookmarkedEvents.isEmpty
        case .organizations:
            return bookmarkedOrganizations.isEmpty
        }
    }

    private var emptyStateSystemImage: String {
        switch selectedSegment {
        case .all:
            return "bookmark"
        case .news:
            return "newspaper"
        case .events:
            return "calendar"
        case .organizations:
            return "building.2"
        }
    }

    private var emptyStateMessage: String {
        switch selectedSegment {
        case .all:
            return AppStrings.Profile.savedEmptyAll
        case .news:
            return AppStrings.Profile.savedEmptyNews
        case .events:
            return AppStrings.Profile.savedEmptyEvents
        case .organizations:
            return AppStrings.Profile.savedEmptyOrganizations
        }
    }

    private func loadSavedContentIfNeeded() async {
        async let newsLoad: Void = newsViewModel.loadIfNeeded()
        async let eventsLoad: Void = eventsViewModel.loadIfNeeded()
        async let organizationsLoad: Void = organizationsViewModel.loadIfNeeded()
        _ = await (newsLoad, eventsLoad, organizationsLoad)
    }

    private func refreshSavedContent() async {
        async let newsRefresh: Void = newsViewModel.refresh()
        async let eventsRefresh: Void = eventsViewModel.refresh()
        async let organizationsRefresh: Void = organizationsViewModel.refresh()
        _ = await (newsRefresh, eventsRefresh, organizationsRefresh)
    }

    private func savedErrorMessage(_ error: AppError) -> String {
        switch error {
        case .network:
            return AppStrings.News.loadNetworkError
        case .permissionDenied:
            return AppStrings.News.loadPermissionError
        case .validationFailed, .notFound:
            return AppStrings.News.loadValidationError
        case .unknown:
            return AppStrings.News.loadUnknownError
        }
    }

    @ViewBuilder
    private func savedItemLink(_ item: SavedContentItem) -> some View {
        switch item {
        case let .news(post):
            savedNewsLink(post)
        case let .event(event):
            savedEventLink(event)
        case let .organization(organization):
            savedOrganizationLink(organization)
        }
    }

    private func savedNewsLink(_ post: NewsPost) -> some View {
        NavigationLink {
            NewsDetailView(
                viewModel: newsViewModel,
                postID: post.id,
                onNewsDeleted: { newsViewModel.reload() }
            )
        } label: {
            SavedNewsCard(post: post)
        }
        .buttonStyle(.plain)
    }

    private func savedEventLink(_ event: Event) -> some View {
        NavigationLink {
            EventDetailView(
                viewModel: eventsViewModel,
                eventID: event.id,
                onEventDeleted: { @MainActor @Sendable in
                    eventsViewModel.reload()
                }
            )
        } label: {
            SavedEventCard(event: event)
        }
        .buttonStyle(.plain)
    }

    private func savedOrganizationLink(_ organization: Organization) -> some View {
        NavigationLink {
            OrganizationDetailView(viewModel: organizationsViewModel, organizationID: organization.id)
        } label: {
            ProfileOrganizationListCard(organization: organization)
        }
        .buttonStyle(.plain)
    }
}

struct FollowedOrganizationsView: View {
    @StateObject private var organizationsViewModel: OrganizationsViewModel

    init(organizationRepository: OrganizationRepository = FirestoreOrganizationRepository()) {
        _organizationsViewModel = StateObject(wrappedValue: OrganizationsViewModel(repository: organizationRepository))
    }

    private var followedOrganizations: [Organization] {
        organizationsViewModel.organizations
            .filter { $0.isSubscribed }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private var isLoading: Bool {
        organizationsViewModel.isLoading && followedOrganizations.isEmpty
    }

    var body: some View {
        ProfileDestinationLayout(
            title: AppStrings.Profile.organizationSubscriptions,
            introSubtitle: AppStrings.Profile.subscriptionsIntro
        ) {
            followedOrganizationsContent
        }
        .task {
            await organizationsViewModel.loadIfNeeded()
        }
        .refreshable {
            await organizationsViewModel.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .organizationsChanged)) { _ in
            Task { await organizationsViewModel.refresh() }
        }
    }

    @ViewBuilder
    private var followedOrganizationsContent: some View {
        if isLoading {
            LoadingStateCard(title: AppStrings.Profile.organizationSubscriptions)
        } else if let error = organizationsViewModel.error, followedOrganizations.isEmpty {
            ProfileDestinationEmptyStateCard(
                systemImage: "exclamationmark.triangle",
                title: AppStrings.Profile.organizationSubscriptions,
                message: followedOrganizationsErrorMessage(error)
            )
        } else if followedOrganizations.isEmpty {
            ProfileDestinationEmptyStateCard(
                systemImage: "person.2",
                title: AppStrings.Profile.organizationSubscriptions,
                message: AppStrings.Profile.subscriptionsEmpty
            )
        } else {
            VStack(spacing: AppTheme.feedRowSpacing) {
                ForEach(followedOrganizations) { organization in
                    NavigationLink {
                        OrganizationDetailView(
                            viewModel: organizationsViewModel,
                            organizationID: organization.id
                        )
                    } label: {
                        ProfileOrganizationListCard(organization: organization)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func followedOrganizationsErrorMessage(_ error: AppError) -> String {
        switch error {
        case .network:
            return AppStrings.Organizations.loadNetworkError
        case .permissionDenied:
            return AppStrings.Organizations.actionPermissionError
        case .validationFailed:
            return AppStrings.Organizations.actionValidationError
        case .notFound:
            return AppStrings.Organizations.actionNotFoundError
        case .unknown:
            return AppStrings.Organizations.actionUnknownError
        }
    }
}

private struct SavedNewsCard: View {
    let post: NewsPost

    var body: some View {
        AppEditorSectionCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "newspaper")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimary)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.accentPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(post.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)

                    Text(post.subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)

                    Label(LocalizationStore.dateString(from: post.publishedAt), systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }
}

private struct SavedEventCard: View {
    let event: Event

    var body: some View {
        AppEditorSectionCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimary)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.accentPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(event.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)

                    Text(event.summary)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)

                    Label(LocalizationStore.dateString(from: event.startDate), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }
}

struct ProfileOrganizationListCard: View {
    let organization: Organization

    var body: some View {
        AppEditorSectionCard {
            HStack(alignment: .center, spacing: 12) {
                AppFeedThumbnail(
                    imageURL: organization.imageURL,
                    fallbackSystemImage: "building.2",
                    tint: AppTheme.accentPrimary,
                    fill: AppTheme.accentPrimary.opacity(0.10),
                    size: thumbnailSize,
                    source: "ProfileOrganizationListCard"
                )
                .frame(width: thumbnailSize, height: thumbnailSize, alignment: .center)

                VStack(alignment: .leading, spacing: 6) {
                    Text(organization.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)

                    Text(organization.shortDescription)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)

                    Label(metadataText, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    private var thumbnailSize: CGFloat {
        50
    }

    @MainActor private var metadataText: String {
        let region = organization.federalState.map(AppStrings.FederalStates.title(for:)) ?? organization.city
        if organization.city.isEmpty || organization.city == region {
            return region
        }
        return "\(organization.city), \(region)"
    }
}
