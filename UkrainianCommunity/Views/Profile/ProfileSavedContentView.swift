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

    var title: String {
        switch self {
        case let .news(post): post.localizedTitle
        case let .event(event): event.localizedTitle
        case let .organization(organization): organization.name
        }
    }
}


struct SavedContentView: View {
    @ObservedObject private var newsViewModel: NewsViewModel
    @ObservedObject private var eventsViewModel: EventsViewModel
    @ObservedObject private var organizationsViewModel: OrganizationsViewModel
    @State private var selectedSegment: SavedContentSegment = .all
    @State private var sortOption: AppListSortOption = .newest
    @State private var savedNews: [NewsPost] = []
    @State private var savedEvents: [Event] = []
    @State private var savedOrganizations: [Organization] = []
    @State private var isLoadingSavedContent = false
    @State private var savedContentError: AppError?
    private let newsRepository: NewsRepository
    private let eventRepository: EventRepository
    private let organizationRepository: OrganizationRepository

    init(
        newsViewModel: NewsViewModel? = nil,
        eventsViewModel: EventsViewModel? = nil,
        organizationsViewModel: OrganizationsViewModel? = nil,
        newsRepository: NewsRepository = FirestoreNewsRepository(),
        eventRepository: EventRepository = FirestoreEventRepository(),
        organizationRepository: OrganizationRepository = FirestoreOrganizationRepository()
    ) {
        self.newsRepository = newsRepository
        self.eventRepository = eventRepository
        self.organizationRepository = organizationRepository
        self.newsViewModel = newsViewModel ?? NewsViewModel(repository: newsRepository)
        self.eventsViewModel = eventsViewModel ?? EventsViewModel(repository: eventRepository)
        self.organizationsViewModel = organizationsViewModel ?? OrganizationsViewModel(repository: organizationRepository)
    }

    private var isLoading: Bool {
        isLoadingSavedContent && savedItems.isEmpty
    }

    private var loadError: AppError? {
        savedContentError
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
                            title: "\(segment.title): \(savedCount(for: segment))",
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

            savedContent
        }
        .task {
            await loadSavedContentIfNeeded()
        }
        .appRefreshable {
            await refreshSavedContent()
        }
        .onReceive(NotificationCenter.default.publisher(for: .newsChanged)) { _ in
            Task { await refreshSavedContent() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eventsChanged)) { _ in
            Task { await refreshSavedContent() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .organizationsChanged)) { _ in
            Task { await refreshSavedContent() }
        }
    }

    @ViewBuilder
    private var savedContent: some View {
        if isLoading {
            LoadingStateCard(title: AppStrings.Profile.savedContent)
        } else if let loadError, currentItemsAreEmpty {
            ErrorStateCard(
                title: AppStrings.Profile.savedContent,
                message: savedErrorMessage(loadError),
                retryTitle: AppStrings.Action.retry
            ) {
                Task { await refreshSavedContent() }
            }
        } else if currentItemsAreEmpty {
            ProfileDestinationEmptyStateCard(
                systemImage: emptyStateSystemImage,
                title: selectedSegment.title,
                message: emptyStateMessage
            )
        } else {
            LazyVStack(spacing: AppTheme.feedRowSpacing) {
                if let loadError {
                    InlineMessageCard(style: .error, message: savedErrorMessage(loadError))
                }
                ForEach(currentItems) { item in
                    savedItemLink(item)
                }
            }
        }
    }

    private var savedItems: [SavedContentItem] {
        sortSavedItems(
            savedNews.map(SavedContentItem.news)
            + savedEvents.map(SavedContentItem.event)
            + savedOrganizations.map(SavedContentItem.organization)
        )
    }

    private var currentItems: [SavedContentItem] {
        switch selectedSegment {
        case .all:
            savedItems
        case .news:
            sortSavedItems(savedNews.map(SavedContentItem.news))
        case .events:
            sortSavedItems(savedEvents.map(SavedContentItem.event))
        case .organizations:
            sortSavedItems(savedOrganizations.map(SavedContentItem.organization))
        }
    }

    private var currentItemsAreEmpty: Bool {
        currentItems.isEmpty
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
        guard savedNews.isEmpty, savedEvents.isEmpty, savedOrganizations.isEmpty else { return }
        await refreshSavedContent()
    }

    private func refreshSavedContent() async {
        guard !isLoadingSavedContent else { return }
        isLoadingSavedContent = true
        defer { isLoadingSavedContent = false }

        async let newsLoad = RefreshRequest.run { [self] in try await newsRepository.fetchBookmarkedNews() }
        async let eventsLoad = RefreshRequest.run { [self] in try await eventRepository.fetchBookmarkedEvents() }
        async let organizationsLoad = RefreshRequest.run { [self] in try await organizationRepository.fetchBookmarkedOrganizations() }
        var firstError: AppError?

        do {
            savedNews = try await newsLoad
            mergeSavedNewsIntoSharedViewModel()
        } catch {
            firstError = appError(from: error)
        }
        do {
            savedEvents = try await eventsLoad
            mergeSavedEventsIntoSharedViewModel()
        } catch {
            firstError = firstError ?? appError(from: error)
        }
        do {
            savedOrganizations = try await organizationsLoad
            mergeSavedOrganizationsIntoSharedViewModel()
        } catch {
            firstError = firstError ?? appError(from: error)
        }
        savedContentError = firstError
    }

    private func savedCount(for segment: SavedContentSegment) -> Int {
        switch segment {
        case .all: savedItems.count
        case .news: savedNews.count
        case .events: savedEvents.count
        case .organizations: savedOrganizations.count
        }
    }

    private func appError(from error: Error) -> AppError {
        (error as? AppError) ?? .unknown
    }

    private func mergeSavedNewsIntoSharedViewModel() {
        let savedIDs = Set(savedNews.map(\.id))
        newsViewModel.posts.removeAll { $0.isBookmarked && !savedIDs.contains($0.id) }
        for post in savedNews {
            if let index = newsViewModel.posts.firstIndex(where: { $0.id == post.id }) {
                newsViewModel.posts[index] = post
            } else {
                newsViewModel.posts.append(post)
            }
        }
    }

    private func mergeSavedEventsIntoSharedViewModel() {
        let savedIDs = Set(savedEvents.map(\.id))
        eventsViewModel.events.removeAll { $0.isBookmarked && !savedIDs.contains($0.id) }
        for event in savedEvents {
            if let index = eventsViewModel.events.firstIndex(where: { $0.id == event.id }) {
                eventsViewModel.events[index] = event
            } else {
                eventsViewModel.events.append(event)
            }
        }
    }

    private func mergeSavedOrganizationsIntoSharedViewModel() {
        let savedIDs = Set(savedOrganizations.map(\.id))
        organizationsViewModel.organizations.removeAll { $0.isBookmarked && !savedIDs.contains($0.id) }
        for organization in savedOrganizations {
            if let index = organizationsViewModel.organizations.firstIndex(where: { $0.id == organization.id }) {
                organizationsViewModel.organizations[index] = organization
            } else {
                organizationsViewModel.organizations.append(organization)
            }
        }
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

    private func sortSavedItems(_ items: [SavedContentItem]) -> [SavedContentItem] {
        items.sorted { lhs, rhs in
            switch sortOption {
            case .newest:
                lhs.savedSortDate == rhs.savedSortDate ? lhs.id < rhs.id : lhs.savedSortDate > rhs.savedSortDate
            case .oldest:
                lhs.savedSortDate == rhs.savedSortDate ? lhs.id < rhs.id : lhs.savedSortDate < rhs.savedSortDate
            case .nameAscending:
                compareTitles(lhs, rhs, ascending: true)
            case .nameDescending:
                compareTitles(lhs, rhs, ascending: false)
            case .popular:
                lhs.savedSortDate == rhs.savedSortDate ? lhs.id < rhs.id : lhs.savedSortDate > rhs.savedSortDate
            }
        }
    }

    private func compareTitles(_ lhs: SavedContentItem, _ rhs: SavedContentItem, ascending: Bool) -> Bool {
        let result = LocalizationStore.compareForSorting(lhs.title, rhs.title)
        guard result != .orderedSame else { return lhs.id < rhs.id }
        return ascending ? result == .orderedAscending : result == .orderedDescending
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
                onNewsDeleted: {}
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
                onEventDeleted: {}
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
    @ObservedObject private var organizationsViewModel: OrganizationsViewModel
    @State private var followedOrganizations: [Organization] = []
    @State private var isLoadingSubscriptions = false
    @State private var subscriptionsError: AppError?
    @State private var sortOption: AppListSortOption = .nameAscending
    private let organizationRepository: OrganizationRepository

    init(
        organizationsViewModel: OrganizationsViewModel? = nil,
        organizationRepository: OrganizationRepository = FirestoreOrganizationRepository()
    ) {
        self.organizationRepository = organizationRepository
        self.organizationsViewModel = organizationsViewModel ?? OrganizationsViewModel(repository: organizationRepository)
    }

    private var isLoading: Bool {
        isLoadingSubscriptions && followedOrganizations.isEmpty
    }

    var body: some View {
        ProfileDestinationLayout(
            title: AppStrings.Profile.organizationSubscriptions,
            introSubtitle: AppStrings.Profile.subscriptionsIntro
        ) {
            if !followedOrganizations.isEmpty {
                AppHorizontalFilterRow {
                    AppSortMenu(
                        selection: $sortOption,
                        options: [.nameAscending, .nameDescending, .newest, .oldest]
                    )
                }
            }
            followedOrganizationsContent
        }
        .task {
            await refreshSubscriptions()
        }
        .appRefreshable {
            await refreshSubscriptions()
        }
        .onReceive(NotificationCenter.default.publisher(for: .organizationsChanged)) { _ in
            Task { await refreshSubscriptions() }
        }
    }

    @ViewBuilder
    private var followedOrganizationsContent: some View {
        if isLoading {
            LoadingStateCard(title: AppStrings.Profile.organizationSubscriptions)
        } else if let error = subscriptionsError, followedOrganizations.isEmpty {
            ErrorStateCard(
                title: AppStrings.Profile.organizationSubscriptions,
                message: followedOrganizationsErrorMessage(error),
                retryTitle: AppStrings.Action.retry
            ) {
                Task { await refreshSubscriptions() }
            }
        } else if followedOrganizations.isEmpty {
            ProfileDestinationEmptyStateCard(
                systemImage: "person.2",
                title: AppStrings.Profile.organizationSubscriptions,
                message: AppStrings.Profile.subscriptionsEmpty
            )
        } else {
            LazyVStack(spacing: AppTheme.feedRowSpacing) {
                if let error = subscriptionsError {
                    InlineMessageCard(style: .error, message: followedOrganizationsErrorMessage(error))
                }
                ForEach(sortedFollowedOrganizations) { organization in
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

    private var sortedFollowedOrganizations: [Organization] {
        followedOrganizations.sorted { lhs, rhs in
            switch sortOption {
            case .newest:
                lhs.createdAt == rhs.createdAt ? lhs.id < rhs.id : lhs.createdAt > rhs.createdAt
            case .oldest:
                lhs.createdAt == rhs.createdAt ? lhs.id < rhs.id : lhs.createdAt < rhs.createdAt
            case .nameAscending:
                compareOrganizations(lhs, rhs, ascending: true)
            case .nameDescending:
                compareOrganizations(lhs, rhs, ascending: false)
            case .popular:
                lhs.subscriberCount == rhs.subscriberCount ? lhs.id < rhs.id : lhs.subscriberCount > rhs.subscriberCount
            }
        }
    }

    private func compareOrganizations(_ lhs: Organization, _ rhs: Organization, ascending: Bool) -> Bool {
        let result = LocalizationStore.compareForSorting(lhs.name, rhs.name)
        guard result != .orderedSame else { return lhs.id < rhs.id }
        return ascending ? result == .orderedAscending : result == .orderedDescending
    }

    private func refreshSubscriptions() async {
        guard !isLoadingSubscriptions else { return }
        isLoadingSubscriptions = true
        defer { isLoadingSubscriptions = false }

        do {
            followedOrganizations = try await RefreshRequest.run { [self] in try await organizationRepository.fetchSubscribedOrganizations() }
            for organization in followedOrganizations {
                if let index = organizationsViewModel.organizations.firstIndex(where: { $0.id == organization.id }) {
                    organizationsViewModel.organizations[index] = organization
                } else {
                    organizationsViewModel.organizations.append(organization)
                }
            }
            subscriptionsError = nil
        } catch let error as AppError {
            subscriptionsError = error
        } catch {
            subscriptionsError = .unknown
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
        SoftContentCard(padding: AppTheme.rowCardPadding) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "newspaper")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.accentPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(post.localizedTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)

                    Text(post.localizedSubtitle)
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
        SoftContentCard(padding: AppTheme.rowCardPadding) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.accentPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(event.localizedTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)

                    Text(event.localizedSummary)
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
        SoftContentCard(padding: AppTheme.rowCardPadding) {
            HStack(alignment: .center, spacing: 12) {
                AppFeedThumbnail(
                    imageURL: organization.imageURL,
                    fallbackSystemImage: "building.2",
                    tint: AppTheme.accentPrimaryForeground,
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
