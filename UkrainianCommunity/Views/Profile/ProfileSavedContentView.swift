import Combine
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
    case news(SavedContentRecord<NewsPost>)
    case event(SavedContentRecord<Event>)
    case organization(SavedContentRecord<Organization>)

    var id: String {
        switch self {
        case .news(let record):
            return "news-\(record.id)"
        case .event(let record):
            return "event-\(record.id)"
        case .organization(let record):
            return "organization-\(record.id)"
        }
    }

    var rawID: String {
        switch self {
        case .news(let record): record.id
        case .event(let record): record.id
        case .organization(let record): record.id
        }
    }

    var savedAt: Date? {
        switch self {
        case .news(let record): record.savedAt
        case .event(let record): record.savedAt
        case .organization(let record): record.savedAt
        }
    }

    var title: String {
        switch self {
        case .news(let record): record.content?.localizedTitle ?? AppStrings.DetailState.unavailableTitle
        case .event(let record): record.content?.localizedTitle ?? AppStrings.DetailState.unavailableTitle
        case .organization(let record): record.content?.localizedName ?? AppStrings.DetailState.unavailableTitle
        }
    }

    var systemImage: String {
        switch self {
        case .news: "newspaper"
        case .event: "calendar"
        case .organization: "building.2"
        }
    }

    var kindTitle: String {
        switch self {
        case .news: AppStrings.News.title
        case .event: AppStrings.Events.title
        case .organization: AppStrings.Tabs.organizations
        }
    }

    var isUnavailable: Bool {
        switch self {
        case .news(let record): record.content == nil
        case .event(let record): record.content == nil
        case .organization(let record): record.content == nil
        }
    }
}

@MainActor
private final class SavedContentViewModel: ObservableObject {
    @Published private(set) var news: [SavedContentRecord<NewsPost>] = []
    @Published private(set) var events: [SavedContentRecord<Event>] = []
    @Published private(set) var organizations: [SavedContentRecord<Organization>] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?
    @Published private(set) var pendingRemovalIDs = Set<String>()

    private let newsRepository: NewsRepository
    private let eventRepository: EventRepository
    private let organizationRepository: OrganizationRepository
    private let newsViewModel: NewsViewModel
    private let eventsViewModel: EventsViewModel
    private let organizationsViewModel: OrganizationsViewModel
    private var userID: String?
    private var generation: UInt = 0

    init(
        newsRepository: NewsRepository,
        eventRepository: EventRepository,
        organizationRepository: OrganizationRepository,
        newsViewModel: NewsViewModel,
        eventsViewModel: EventsViewModel,
        organizationsViewModel: OrganizationsViewModel
    ) {
        self.newsRepository = newsRepository
        self.eventRepository = eventRepository
        self.organizationRepository = organizationRepository
        self.newsViewModel = newsViewModel
        self.eventsViewModel = eventsViewModel
        self.organizationsViewModel = organizationsViewModel
    }

    func bind(userID newUserID: String?) {
        guard userID != newUserID else { return }
        userID = newUserID
        generation &+= 1
        news = []
        events = []
        organizations = []
        error = nil
        pendingRemovalIDs = []
        isLoading = false
    }

    func refresh() async {
        guard userID != nil, !isLoading else { return }
        generation &+= 1
        let requestGeneration = generation
        isLoading = true

        async let newsLoad = RefreshRequest.run { [newsRepository] in
            try await newsRepository.fetchSavedNews()
        }
        async let eventsLoad = RefreshRequest.run { [eventRepository] in
            try await eventRepository.fetchSavedEvents()
        }
        async let organizationsLoad = RefreshRequest.run { [organizationRepository] in
            try await organizationRepository.fetchSavedOrganizations()
        }
        var firstError: AppError?

        do {
            let records = try await newsLoad
            guard isCurrent(requestGeneration) else { return }
            news = records
            mergeNewsIntoSharedViewModel()
        } catch is CancellationError {
            finishLoading(requestGeneration)
            return
        } catch {
            firstError = appError(from: error)
        }

        do {
            let records = try await eventsLoad
            guard isCurrent(requestGeneration) else { return }
            events = records
            mergeEventsIntoSharedViewModel()
        } catch is CancellationError {
            finishLoading(requestGeneration)
            return
        } catch {
            firstError = firstError ?? appError(from: error)
        }

        do {
            let records = try await organizationsLoad
            guard isCurrent(requestGeneration) else { return }
            organizations = records
            mergeOrganizationsIntoSharedViewModel()
        } catch is CancellationError {
            finishLoading(requestGeneration)
            return
        } catch {
            firstError = firstError ?? appError(from: error)
        }

        guard isCurrent(requestGeneration) else { return }
        error = firstError
        isLoading = false
    }

    func reconcileNews(_ posts: [NewsPost], pendingIDs: Set<String>) {
        news.removeAll { record in
            guard record.content != nil,
                  !pendingIDs.contains(record.id),
                  let post = posts.first(where: { $0.id == record.id }) else { return false }
            return !post.isBookmarked
        }
    }

    func reconcileEvents(_ loadedEvents: [Event], pendingIDs: Set<String>) {
        events.removeAll { record in
            guard record.content != nil,
                  !pendingIDs.contains(record.id),
                  let event = loadedEvents.first(where: { $0.id == record.id }) else { return false }
            return !event.isBookmarked
        }
    }

    func reconcileOrganizations(_ loadedOrganizations: [Organization], pendingIDs: Set<String>) {
        organizations.removeAll { record in
            guard record.content != nil,
                  !pendingIDs.contains(record.id),
                  let organization = loadedOrganizations.first(where: { $0.id == record.id }) else { return false }
            return !organization.isBookmarked
        }
    }

    func removeUnavailable(_ item: SavedContentItem) async {
        guard item.isUnavailable, !pendingRemovalIDs.contains(item.id) else { return }
        let requestGeneration = generation
        pendingRemovalIDs.insert(item.id)
        error = nil
        defer {
            if isCurrent(requestGeneration) {
                pendingRemovalIDs.remove(item.id)
            }
        }

        do {
            switch item {
            case .news:
                try await newsRepository.unbookmarkNews(id: item.rawID)
            case .event:
                try await eventRepository.unbookmarkEvent(id: item.rawID)
            case .organization:
                try await organizationRepository.unbookmarkOrganization(id: item.rawID)
            }
            guard isCurrent(requestGeneration) else { return }
            removeRecord(item)
        } catch {
            guard isCurrent(requestGeneration) else { return }
            self.error = appError(from: error)
        }
    }

    private func removeRecord(_ item: SavedContentItem) {
        switch item {
        case .news:
            news.removeAll { $0.id == item.rawID }
        case .event:
            events.removeAll { $0.id == item.rawID }
        case .organization:
            organizations.removeAll { $0.id == item.rawID }
        }
    }

    private func mergeNewsIntoSharedViewModel() {
        let resolved = news.compactMap(\.content)
        let visible = newsViewModel.visibilityPolicy.visibleNews(resolved)
        let savedIDs = Set(resolved.map(\.id))
        newsViewModel.posts.removeAll { $0.isBookmarked && !savedIDs.contains($0.id) }
        for post in visible {
            if let index = newsViewModel.posts.firstIndex(where: { $0.id == post.id }) {
                newsViewModel.posts[index] = post
            } else {
                newsViewModel.posts.append(post)
            }
        }
    }

    private func mergeEventsIntoSharedViewModel() {
        let resolved = events.compactMap(\.content)
        let visible = eventsViewModel.visibilityPolicy.visibleEvents(resolved)
        let savedIDs = Set(resolved.map(\.id))
        eventsViewModel.events.removeAll { $0.isBookmarked && !savedIDs.contains($0.id) }
        for event in visible {
            if let index = eventsViewModel.events.firstIndex(where: { $0.id == event.id }) {
                eventsViewModel.events[index] = event
            } else {
                eventsViewModel.events.append(event)
            }
        }
    }

    private func mergeOrganizationsIntoSharedViewModel() {
        let resolved = organizations.compactMap(\.content)
        let visible = organizationsViewModel.visibilityPolicy.visibleOrganizations(resolved)
        let savedIDs = Set(resolved.map(\.id))
        organizationsViewModel.organizations.removeAll { $0.isBookmarked && !savedIDs.contains($0.id) }
        for organization in visible {
            if let index = organizationsViewModel.organizations.firstIndex(where: { $0.id == organization.id }) {
                organizationsViewModel.organizations[index] = organization
            } else {
                organizationsViewModel.organizations.append(organization)
            }
        }
    }

    private func isCurrent(_ requestGeneration: UInt) -> Bool {
        requestGeneration == generation && !Task.isCancelled
    }

    private func finishLoading(_ requestGeneration: UInt) {
        guard requestGeneration == generation else { return }
        isLoading = false
    }

    private func appError(from error: Error) -> AppError {
        (error as? AppError) ?? .unknown
    }
}

struct SavedContentView: View {
    @EnvironmentObject private var authState: AuthState
    @ObservedObject private var newsViewModel: NewsViewModel
    @ObservedObject private var eventsViewModel: EventsViewModel
    @ObservedObject private var organizationsViewModel: OrganizationsViewModel
    @StateObject private var viewModel: SavedContentViewModel
    @State private var selectedSegment: SavedContentSegment = .all
    @State private var sortOption: AppListSortOption = .newest

    init(
        newsViewModel: NewsViewModel? = nil,
        eventsViewModel: EventsViewModel? = nil,
        organizationsViewModel: OrganizationsViewModel? = nil,
        newsRepository: NewsRepository = FirestoreNewsRepository(),
        eventRepository: EventRepository = FirestoreEventRepository(),
        organizationRepository: OrganizationRepository = FirestoreOrganizationRepository()
    ) {
        let resolvedNewsViewModel = newsViewModel ?? NewsViewModel(repository: newsRepository)
        let resolvedEventsViewModel = eventsViewModel ?? EventsViewModel(repository: eventRepository)
        let resolvedOrganizationsViewModel = organizationsViewModel ?? OrganizationsViewModel(repository: organizationRepository)
        self.newsViewModel = resolvedNewsViewModel
        self.eventsViewModel = resolvedEventsViewModel
        self.organizationsViewModel = resolvedOrganizationsViewModel
        _viewModel = StateObject(
            wrappedValue: SavedContentViewModel(
                newsRepository: newsRepository,
                eventRepository: eventRepository,
                organizationRepository: organizationRepository,
                newsViewModel: resolvedNewsViewModel,
                eventsViewModel: resolvedEventsViewModel,
                organizationsViewModel: resolvedOrganizationsViewModel
            )
        )
    }

    private var isLoading: Bool {
        viewModel.isLoading && savedItems.isEmpty
    }

    private var visibleNews: [SavedContentRecord<NewsPost>] {
        viewModel.news.map { record in
            guard let post = record.content,
                  newsViewModel.visibilityPolicy.visibleNews([post]).isEmpty else { return record }
            return SavedContentRecord(id: record.id, savedAt: record.savedAt, content: nil)
        }
    }

    private var visibleEvents: [SavedContentRecord<Event>] {
        viewModel.events.map { record in
            guard let event = record.content,
                  eventsViewModel.visibilityPolicy.visibleEvents([event]).isEmpty else { return record }
            return SavedContentRecord(id: record.id, savedAt: record.savedAt, content: nil)
        }
    }

    private var visibleOrganizations: [SavedContentRecord<Organization>] {
        viewModel.organizations.map { record in
            guard let organization = record.content,
                  organizationsViewModel.visibilityPolicy.visibleOrganizations([organization]).isEmpty else { return record }
            return SavedContentRecord(id: record.id, savedAt: record.savedAt, content: nil)
        }
    }

    private var savedItems: [SavedContentItem] {
        sortSavedItems(
            visibleNews.map(SavedContentItem.news)
                + visibleEvents.map(SavedContentItem.event)
                + visibleOrganizations.map(SavedContentItem.organization)
        )
    }

    private var currentItems: [SavedContentItem] {
        switch selectedSegment {
        case .all:
            savedItems
        case .news:
            sortSavedItems(visibleNews.map(SavedContentItem.news))
        case .events:
            sortSavedItems(visibleEvents.map(SavedContentItem.event))
        case .organizations:
            sortSavedItems(visibleOrganizations.map(SavedContentItem.organization))
        }
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

            SavedContentResults(
                isLoading: isLoading,
                error: viewModel.error,
                items: currentItems,
                emptySystemImage: emptyStateSystemImage,
                emptyTitle: selectedSegment.title,
                emptyMessage: emptyStateMessage,
                pendingRemovalIDs: viewModel.pendingRemovalIDs,
                retry: refresh,
                removeUnavailable: removeUnavailable,
                destination: savedItemDestination
            )
        }
        .task(id: authState.user?.id) {
            viewModel.bind(userID: authState.user?.id)
            await viewModel.refresh()
        }
        .appRefreshable {
            await viewModel.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .newsChanged)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .eventsChanged)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .organizationsChanged)) { _ in refresh() }
        .onReceive(newsViewModel.$pendingNewsBookmarkIDs) { pendingIDs in
            viewModel.reconcileNews(newsViewModel.posts, pendingIDs: pendingIDs)
        }
        .onReceive(eventsViewModel.$pendingEventBookmarkIDs) { pendingIDs in
            viewModel.reconcileEvents(eventsViewModel.events, pendingIDs: pendingIDs)
        }
        .onReceive(organizationsViewModel.$pendingOrganizationBookmarkIDs) { pendingIDs in
            viewModel.reconcileOrganizations(organizationsViewModel.organizations, pendingIDs: pendingIDs)
        }
    }

    private var emptyStateSystemImage: String {
        switch selectedSegment {
        case .all: "bookmark"
        case .news: "newspaper"
        case .events: "calendar"
        case .organizations: "building.2"
        }
    }

    private var emptyStateMessage: String {
        switch selectedSegment {
        case .all: AppStrings.Profile.savedEmptyAll
        case .news: AppStrings.Profile.savedEmptyNews
        case .events: AppStrings.Profile.savedEmptyEvents
        case .organizations: AppStrings.Profile.savedEmptyOrganizations
        }
    }

    private func savedCount(for segment: SavedContentSegment) -> Int {
        switch segment {
        case .all: savedItems.count
        case .news: visibleNews.count
        case .events: visibleEvents.count
        case .organizations: visibleOrganizations.count
        }
    }

    private func sortSavedItems(_ items: [SavedContentItem]) -> [SavedContentItem] {
        items.sorted { lhs, rhs in
            switch sortOption {
            case .newest:
                compareSavedDates(lhs, rhs, ascending: false)
            case .oldest:
                compareSavedDates(lhs, rhs, ascending: true)
            case .nameAscending:
                compareTitles(lhs, rhs, ascending: true)
            case .nameDescending:
                compareTitles(lhs, rhs, ascending: false)
            case .popular:
                compareSavedDates(lhs, rhs, ascending: false)
            }
        }
    }

    private func compareSavedDates(_ lhs: SavedContentItem, _ rhs: SavedContentItem, ascending: Bool) -> Bool {
        switch (lhs.savedAt, rhs.savedAt) {
        case let (left?, right?) where left != right:
            return ascending ? left < right : left > right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return lhs.id < rhs.id
        }
    }

    private func compareTitles(_ lhs: SavedContentItem, _ rhs: SavedContentItem, ascending: Bool) -> Bool {
        let result = LocalizationStore.compareForSorting(lhs.title, rhs.title)
        guard result != .orderedSame else { return lhs.id < rhs.id }
        return ascending ? result == .orderedAscending : result == .orderedDescending
    }

    @ViewBuilder
    private func savedItemDestination(_ item: SavedContentItem) -> some View {
        switch item {
        case .news(let record):
            if let post = record.content {
                NewsDetailView(viewModel: newsViewModel, postID: post.id, onNewsDeleted: {})
            }
        case .event(let record):
            if let event = record.content {
                EventDetailView(viewModel: eventsViewModel, eventID: event.id, onEventDeleted: {})
            }
        case .organization(let record):
            if let organization = record.content {
                OrganizationDetailView(viewModel: organizationsViewModel, organizationID: organization.id)
            }
        }
    }

    private func refresh() {
        Task { await viewModel.refresh() }
    }

    private func removeUnavailable(_ item: SavedContentItem) {
        Task { await viewModel.removeUnavailable(item) }
    }
}

private struct SavedContentResults<Destination: View>: View {
    let isLoading: Bool
    let error: AppError?
    let items: [SavedContentItem]
    let emptySystemImage: String
    let emptyTitle: String
    let emptyMessage: String
    let pendingRemovalIDs: Set<String>
    let retry: () -> Void
    let removeUnavailable: (SavedContentItem) -> Void
    @ViewBuilder let destination: (SavedContentItem) -> Destination

    var body: some View {
        Group {
            if isLoading {
                LoadingStateCard(title: AppStrings.Profile.savedContent)
            } else if let error, items.isEmpty {
                ErrorStateCard(
                    title: AppStrings.Profile.savedContent,
                    message: savedErrorMessage(error),
                    retryTitle: AppStrings.Action.retry,
                    retryAction: retry
                )
            } else if items.isEmpty {
                ProfileDestinationEmptyStateCard(
                    systemImage: emptySystemImage,
                    title: emptyTitle,
                    message: emptyMessage
                )
            } else {
                LazyVStack(spacing: AppTheme.feedRowSpacing) {
                    if let error {
                        InlineMessageCard(style: .error, message: savedErrorMessage(error))
                    }
                    ForEach(items) { item in
                        if item.isUnavailable {
                            UnavailableSavedContentCard(
                                systemImage: item.systemImage,
                                kindTitle: item.kindTitle,
                                isRemoving: pendingRemovalIDs.contains(item.id),
                                remove: { removeUnavailable(item) }
                            )
                        } else {
                            NavigationLink {
                                destination(item)
                            } label: {
                                savedItemLabel(item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func savedItemLabel(_ item: SavedContentItem) -> some View {
        switch item {
        case .news(let record):
            if let post = record.content { SavedNewsCard(post: post) }
        case .event(let record):
            if let event = record.content { SavedEventCard(event: event) }
        case .organization(let record):
            if let organization = record.content { SavedOrganizationCard(organization: organization) }
        }
    }

    private func savedErrorMessage(_ error: AppError) -> String {
        switch error {
        case .network:
            AppStrings.News.loadNetworkError
        case .permissionDenied:
            AppStrings.News.loadPermissionError
        case .validationFailed, .notFound:
            AppStrings.News.loadValidationError
        case .unknown:
            AppStrings.News.loadUnknownError
        }
    }
}

private struct UnavailableSavedContentCard: View {
    let systemImage: String
    let kindTitle: String
    let isRemoving: Bool
    let remove: () -> Void

    var body: some View {
        CommunityCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    Text(kindTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)

                    Text(AppStrings.DetailState.unavailableTitle)
                        .font(.headline)
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(AppStrings.DetailState.unavailableMessage)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(role: .destructive, action: remove) {
                        if isRemoving {
                            ProgressView()
                        } else {
                            Text(AppStrings.Organizations.removeBookmark)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRemoving)
                    .accessibilityLabel(AppStrings.Organizations.removeBookmark)
                }

                Spacer(minLength: 0)
            }
        }
    }
}

struct FollowedOrganizationsView: View {
    @ObservedObject private var organizationsViewModel: OrganizationsViewModel
    @State private var subscriptions: [SavedContentRecord<Organization>] = []
    @State private var isLoadingSubscriptions = false
    @State private var subscriptionsError: AppError?
    @State private var sortOption: AppListSortOption = .nameAscending
    @State private var unavailableSubscriptionPendingConfirmation: String?
    @State private var pendingUnavailableSubscriptionRemovalIDs = Set<String>()
    private let organizationRepository: OrganizationRepository

    init(
        organizationsViewModel: OrganizationsViewModel? = nil,
        organizationRepository: OrganizationRepository = FirestoreOrganizationRepository()
    ) {
        self.organizationRepository = organizationRepository
        self.organizationsViewModel = organizationsViewModel ?? OrganizationsViewModel(repository: organizationRepository)
    }

    private var isLoading: Bool {
        isLoadingSubscriptions && visibleSubscriptions.isEmpty
    }

    private var visibleSubscriptions: [SavedContentRecord<Organization>] {
        subscriptions.compactMap { record in
            guard let organization = record.content else { return record }
            return organizationsViewModel.visibilityPolicy.visibleOrganizations([organization]).isEmpty ? nil : record
        }
    }

    var body: some View {
        ProfileDestinationLayout(
            title: AppStrings.Profile.organizationSubscriptions,
            introSubtitle: AppStrings.Profile.subscriptionsIntro
        ) {
            if !visibleSubscriptions.isEmpty {
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
            await refreshSubscriptions(forceRefresh: false)
        }
        .appRefreshable {
            await refreshSubscriptions(forceRefresh: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .organizationsChanged)) { _ in
            Task { await refreshSubscriptions(forceRefresh: false) }
        }
        .confirmationDialog(
            AppStrings.Organizations.confirmUnsubscribeTitle,
            isPresented: unavailableSubscriptionConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button(AppStrings.Organizations.confirmUnsubscribeButton, role: .destructive) {
                guard let id = unavailableSubscriptionPendingConfirmation else { return }
                unavailableSubscriptionPendingConfirmation = nil
                Task { await removeUnavailableSubscription(id: id) }
            }
            Button(AppStrings.Action.cancel, role: .cancel) {
                unavailableSubscriptionPendingConfirmation = nil
            }
        }
    }

    @ViewBuilder
    private var followedOrganizationsContent: some View {
        if isLoading {
            LoadingStateCard(title: AppStrings.Profile.organizationSubscriptions)
        } else if let error = subscriptionsError, visibleSubscriptions.isEmpty {
            ErrorStateCard(
                title: AppStrings.Profile.organizationSubscriptions,
                message: followedOrganizationsErrorMessage(error),
                retryTitle: AppStrings.Action.retry
            ) {
                Task { await refreshSubscriptions(forceRefresh: true) }
            }
        } else if visibleSubscriptions.isEmpty {
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
                ForEach(sortedSubscriptions, id: \.id) { record in
                    if let organization = record.content {
                        NavigationLink {
                            OrganizationDetailView(
                                viewModel: organizationsViewModel,
                                organizationID: organization.id
                            )
                        } label: {
                            ProfileOrganizationListCard(organization: organization)
                        }
                        .buttonStyle(.plain)
                    } else {
                        UnavailableOrganizationSubscriptionCard(
                            isRemoving: pendingUnavailableSubscriptionRemovalIDs.contains(record.id),
                            remove: { unavailableSubscriptionPendingConfirmation = record.id }
                        )
                    }
                }
            }
        }
    }

    private var sortedSubscriptions: [SavedContentRecord<Organization>] {
        visibleSubscriptions.sorted { lhs, rhs in
            switch sortOption {
            case .newest:
                return compareSubscriptionDates(lhs, rhs, ascending: false)
            case .oldest:
                return compareSubscriptionDates(lhs, rhs, ascending: true)
            case .nameAscending:
                return compareOrganizations(lhs, rhs, ascending: true)
            case .nameDescending:
                return compareOrganizations(lhs, rhs, ascending: false)
            case .popular:
                let left = lhs.content?.subscriberCount ?? -1
                let right = rhs.content?.subscriberCount ?? -1
                return left == right ? lhs.id < rhs.id : left > right
            }
        }
    }

    private func compareOrganizations(
        _ lhs: SavedContentRecord<Organization>,
        _ rhs: SavedContentRecord<Organization>,
        ascending: Bool
    ) -> Bool {
        switch (lhs.content, rhs.content) {
        case let (left?, right?):
            let result = LocalizationStore.compareForSorting(left.name, right.name)
            guard result != .orderedSame else { return lhs.id < rhs.id }
            return ascending ? result == .orderedAscending : result == .orderedDescending
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return lhs.id < rhs.id
        }
    }

    private func compareSubscriptionDates(
        _ lhs: SavedContentRecord<Organization>,
        _ rhs: SavedContentRecord<Organization>,
        ascending: Bool
    ) -> Bool {
        let leftDate = lhs.content?.createdAt ?? lhs.savedAt
        let rightDate = rhs.content?.createdAt ?? rhs.savedAt
        switch (leftDate, rightDate) {
        case let (left?, right?) where left != right:
            return ascending ? left < right : left > right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return lhs.id < rhs.id
        }
    }

    private var unavailableSubscriptionConfirmationBinding: Binding<Bool> {
        Binding(
            get: { unavailableSubscriptionPendingConfirmation != nil },
            set: { isPresented in
                if !isPresented { unavailableSubscriptionPendingConfirmation = nil }
            }
        )
    }

    private func removeUnavailableSubscription(id: String) async {
        guard !pendingUnavailableSubscriptionRemovalIDs.contains(id) else { return }
        pendingUnavailableSubscriptionRemovalIDs.insert(id)
        subscriptionsError = nil
        defer { pendingUnavailableSubscriptionRemovalIDs.remove(id) }

        do {
            try await organizationRepository.unsubscribeOrganization(id: id)
            subscriptions.removeAll { $0.id == id }
        } catch let error as AppError {
            subscriptionsError = error
        } catch {
            subscriptionsError = .unknown
        }
    }

    private func refreshSubscriptions(forceRefresh: Bool) async {
        guard !isLoadingSubscriptions else { return }
        isLoadingSubscriptions = true
        defer { isLoadingSubscriptions = false }

        do {
            subscriptions = try await RefreshRequest.run { [self] in
                try await organizationRepository.fetchOrganizationSubscriptions(forceRefresh: forceRefresh)
            }
            for organization in visibleSubscriptions.compactMap(\.content) {
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

private struct UnavailableOrganizationSubscriptionCard: View {
    let isRemoving: Bool
    let remove: () -> Void

    var body: some View {
        CommunityCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "building.2")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    Text(AppStrings.Profile.unavailableSubscriptionTitle)
                        .font(.headline)
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(AppStrings.Profile.unavailableSubscriptionMessage)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(role: .destructive, action: remove) {
                        if isRemoving {
                            ProgressView()
                        } else {
                            Text(AppStrings.Profile.removeUnavailableSubscription)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRemoving)
                    .accessibilityLabel(AppStrings.Profile.removeUnavailableSubscription)
                }

                Spacer(minLength: 0)
            }
        }
    }
}

private struct SavedNewsCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(post.localizedSubtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)

                    Label(LocalizationStore.dateString(from: post.publishedAt), systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(event.localizedSummary)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)

                    Label(LocalizationStore.dateString(from: event.startDate), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }
}

private struct SavedOrganizationCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
                    source: "SavedOrganizationCard"
                )
                .frame(width: thumbnailSize, height: thumbnailSize, alignment: .center)

                VStack(alignment: .leading, spacing: 6) {
                    Text(organization.localizedName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(organization.localizedShortDescription)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)

                    Label(metadataText, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    private var thumbnailSize: CGFloat { 50 }

    @MainActor private var metadataText: String {
        let region = organization.federalState.map(AppStrings.FederalStates.title(for:)) ?? organization.city
        if organization.city.isEmpty || organization.city == region {
            return region
        }
        return "\(organization.city), \(region)"
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
                    Text(organization.localizedName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)

                    Text(organization.localizedShortDescription)
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
