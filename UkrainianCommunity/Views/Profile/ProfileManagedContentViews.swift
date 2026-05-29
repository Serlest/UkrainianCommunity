import SwiftUI

struct ManagedNewsContentView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel: NewsViewModel
    @State private var editingPost: NewsPost?
    private let repository: NewsRepository
    private let organizationRepository: OrganizationRepository
    private let manageableOrganizations: [Organization]

    init(
        repository: NewsRepository,
        organizationRepository: OrganizationRepository,
        manageableOrganizations: [Organization]
    ) {
        self.repository = repository
        self.organizationRepository = organizationRepository
        self.manageableOrganizations = manageableOrganizations
        _viewModel = StateObject(wrappedValue: NewsViewModel(repository: repository))
    }

    private var organizationsByID: [String: Organization] {
        Dictionary(uniqueKeysWithValues: manageableOrganizations.map { ($0.id, $0) })
    }

    private var managedPosts: [NewsPost] {
        viewModel.posts
            .filter { post in
                guard let organizationID = post.source.organizationId,
                      let organization = organizationsByID[organizationID] else {
                    return false
                }
                return PermissionService.canEditOrganizationNews(organization, user: authState.user)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        ZStack {
            AppBackgroundView()
                .allowsHitTesting(false)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    SectionHeaderBlock(
                        title: AppStrings.Profile.managedNewsTitle,
                        subtitle: AppStrings.Profile.managedNewsSubtitle
                    )

                    if viewModel.isLoading && managedPosts.isEmpty {
                        LoadingStateCard(title: nil)
                    } else if managedPosts.isEmpty {
                        EmptyStateCard(
                            systemImage: "newspaper",
                            title: AppStrings.Profile.managedNewsEmptyTitle,
                            message: AppStrings.Profile.managedNewsEmptyMessage
                        )
                    } else {
                        VStack(spacing: AppTheme.eventsMetadataSpacing) {
                            ForEach(managedPosts) { post in
                                ManagedContentCard(
                                    title: post.title,
                                    subtitle: organizationTitle(for: post.source.organizationId),
                                    metadata: managedNewsMetadata(for: post),
                                    status: post.moderationStatus.title,
                                    systemImage: "newspaper"
                                ) {
                                    NavigationLink {
                                        NewsDetailView(
                                            viewModel: viewModel,
                                            postID: post.id,
                                            onNewsDeleted: {
                                                viewModel.reload()
                                            },
                                            organizationRepository: organizationRepository
                                        )
                                        .environment(\.newsPresentationMode, .management)
                                    } label: {
                                        Label(AppStrings.Action.open, systemImage: "arrow.up.right")
                                    }

                                    Button {
                                        editingPost = post
                                    } label: {
                                        Label(AppStrings.Action.edit, systemImage: "pencil")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, AppTheme.pageHorizontal)
                .padding(.vertical, AppTheme.sectionSpacing)
            }
        }
        .navigationTitle(AppStrings.Profile.managedNewsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .sheet(item: $editingPost) { post in
            NavigationStack {
                NewsEditorView(repository: repository, news: post) {
                    await viewModel.refresh()
                }
            }
            .environmentObject(authState)
        }
    }

    private func organizationTitle(for organizationID: String?) -> String {
        guard let organizationID else { return AppStrings.News.missingOrganization }
        return organizationsByID[organizationID]?.name ?? AppStrings.News.missingOrganization
    }

    private func managedNewsMetadata(for post: NewsPost) -> String {
        LocalizationStore.dateString(from: post.createdAt, dateStyle: .medium, timeStyle: .none)
    }
}


struct ManagedEventsContentView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel: EventsViewModel
    @State private var editingEvent: Event?
    private let repository: EventRepository
    private let organizationRepository: OrganizationRepository
    private let manageableOrganizations: [Organization]

    init(
        repository: EventRepository,
        organizationRepository: OrganizationRepository,
        manageableOrganizations: [Organization]
    ) {
        self.repository = repository
        self.organizationRepository = organizationRepository
        self.manageableOrganizations = manageableOrganizations
        _viewModel = StateObject(wrappedValue: EventsViewModel(repository: repository))
    }

    private var organizationsByID: [String: Organization] {
        Dictionary(uniqueKeysWithValues: manageableOrganizations.map { ($0.id, $0) })
    }

    private var managedEvents: [Event] {
        viewModel.events
            .filter { event in
                guard let organizationID = event.source.organizationId,
                      let organization = organizationsByID[organizationID] else {
                    return false
                }
                return PermissionService.canEditOrganizationEvent(organization, user: authState.user)
            }
            .sorted { $0.startDate > $1.startDate }
    }

    var body: some View {
        ZStack {
            AppBackgroundView()
                .allowsHitTesting(false)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    SectionHeaderBlock(
                        title: AppStrings.Profile.managedEventsTitle,
                        subtitle: AppStrings.Profile.managedEventsSubtitle
                    )

                    if viewModel.isLoading && managedEvents.isEmpty {
                        LoadingStateCard(title: nil)
                    } else if managedEvents.isEmpty {
                        EmptyStateCard(
                            systemImage: "calendar",
                            title: AppStrings.Profile.managedEventsEmptyTitle,
                            message: AppStrings.Profile.managedEventsEmptyMessage
                        )
                    } else {
                        VStack(spacing: AppTheme.eventsMetadataSpacing) {
                            ForEach(managedEvents) { event in
                                ManagedContentCard(
                                    title: event.title,
                                    subtitle: organizationTitle(for: event.source.organizationId),
                                    metadata: managedEventMetadata(for: event),
                                    status: event.moderationStatus.title,
                                    systemImage: "calendar"
                                ) {
                                    NavigationLink {
                                        EventDetailView(
                                            viewModel: viewModel,
                                            eventID: event.id,
                                            onEventDeleted: {
                                                viewModel.reload()
                                            },
                                            organizationRepository: organizationRepository
                                        )
                                        .environment(\.eventPresentationMode, .management)
                                    } label: {
                                        Label(AppStrings.Action.open, systemImage: "arrow.up.right")
                                    }

                                    Button {
                                        editingEvent = event
                                    } label: {
                                        Label(AppStrings.Action.edit, systemImage: "pencil")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, AppTheme.pageHorizontal)
                .padding(.vertical, AppTheme.sectionSpacing)
            }
        }
        .navigationTitle(AppStrings.Profile.managedEventsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .sheet(item: $editingEvent) { event in
            NavigationStack {
                EventEditorView(repository: repository, event: event) {
                    await viewModel.refresh()
                }
            }
            .environmentObject(authState)
        }
    }

    private func organizationTitle(for organizationID: String?) -> String {
        guard let organizationID else { return AppStrings.News.missingOrganization }
        return organizationsByID[organizationID]?.name ?? AppStrings.News.missingOrganization
    }

    private func managedEventMetadata(for event: Event) -> String {
        LocalizationStore.dateString(from: event.startDate, dateStyle: .medium, timeStyle: .short)
    }
}


struct AppNewsManagementView: View {
    private let repository: NewsRepository
    @StateObject private var viewModel: NewsViewModel

    init(repository: NewsRepository = FirestoreNewsRepository()) {
        self.repository = repository
        _viewModel = StateObject(wrappedValue: NewsViewModel(repository: repository))
    }

    var body: some View {
        NewsListView(
            viewModel: viewModel,
            newsRepository: repository,
            onNewsPublished: {},
            onNewsChanged: {},
            presentationMode: .management
        )
    }
}


struct AppEventsManagementView: View {
    private let repository: EventRepository
    @StateObject private var viewModel: EventsViewModel

    init(repository: EventRepository = FirestoreEventRepository()) {
        self.repository = repository
        _viewModel = StateObject(wrappedValue: EventsViewModel(repository: repository))
    }

    var body: some View {
        EventsListView(
            viewModel: viewModel,
            eventRepository: repository,
            onEventPublished: {},
            onEventDeleted: { @MainActor @Sendable in },
            presentationMode: .management
        )
    }
}
