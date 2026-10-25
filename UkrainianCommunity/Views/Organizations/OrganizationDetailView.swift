import Combine
import MapKit
import PhotosUI
import SwiftUI

enum OrganizationDetailSection: CaseIterable, Identifiable {
    case about
    case contacts
    case news
    case events
    case photos
    case team

    var id: Self { self }

    var title: String {
        switch self {
        case .events:
            AppStrings.Organizations.tabEvents
        case .news:
            AppStrings.Organizations.tabNews
        case .about:
            AppStrings.Organizations.tabAbout
        case .contacts:
            AppStrings.Organizations.tabContacts
        case .team:
            AppStrings.Organizations.tabTeam
        case .photos:
            AppStrings.Organizations.tabPhoto
        }
    }

    var systemImage: String {
        switch self {
        case .events:
            "calendar"
        case .news:
            "newspaper"
        case .about:
            "info.circle"
        case .contacts:
            "person.crop.circle.badge"
        case .team:
            "person.3"
        case .photos:
            "photo.on.rectangle"
        }
    }
}

enum OrganizationCommunityRole: Int {
    case owner = 0
    case admin = 1
    case moderator = 2
    case subscriber = 3

    var title: String {
        switch self {
        case .owner:
            AppStrings.Organizations.communityOwner
        case .admin:
            AppStrings.Organizations.communityAdmin
        case .moderator:
            AppStrings.Organizations.communityModerator
        case .subscriber:
            AppStrings.Organizations.communityMember
        }
    }
}

enum OrganizationEventAgeFilter: String, CaseIterable, Identifiable {
    case any, child, teen, adult
    var id: String { rawValue }
    var title: String {
        switch self {
        case .any: AppStrings.Events.ageFilterAny
        case .child: AppStrings.Events.ageFilterChildren
        case .teen: AppStrings.Events.ageFilterTeens
        case .adult: AppStrings.Events.ageFilterAdults
        }
    }
    var ageRange: ClosedRange<Int>? {
        switch self { case .any: nil; case .child: 0...12; case .teen: 13...17; case .adult: 18...120 }
    }
}

enum OrganizationSubscriptionConfirmation: Equatable {
    case subscribe(String)
    case unsubscribe(String)

    var organizationID: String {
        switch self {
        case .subscribe(let organizationID), .unsubscribe(let organizationID):
            organizationID
        }
    }

    var isUnsubscribe: Bool {
        if case .unsubscribe = self {
            return true
        }
        return false
    }
}

struct OrganizationCommunityMember: Identifiable {
    let profile: PublicUserProfile
    let role: OrganizationCommunityRole
    let followedAt: Date?
    let isPlaceholder: Bool

    var id: String { profile.id }
}

@MainActor
final class OrganizationActivityViewModel: ObservableObject {
    @Published private(set) var items: [OrganizationActivityItem] = []
    @Published private(set) var loadingTypes = Set<OrganizationActivityItemType>()
    @Published private(set) var errors: [OrganizationActivityItemType: AppError] = [:]
    @Published private(set) var loadedItemTypes = Set<OrganizationActivityItemType>()
    @Published private(set) var hasMoreTypes = Set<OrganizationActivityItemType>()
    private var generation = 0
    private var cursors: [OrganizationActivityItemType: OrganizationActivityCursor] = [:]
    private var loadTasks: [OrganizationActivityItemType: Task<Void, Never>] = [:]
    private let organizationID: String
    private let newsRepository: NewsRepository
    private let eventRepository: EventRepository
    private let activityLoader: (@MainActor (OrganizationActivityItemType) async throws -> [OrganizationActivityItem])?
    private let pageLoader: (@MainActor (OrganizationActivityItemType, OrganizationActivityCursor?) async throws -> OrganizationActivityPage)?
    private let activityLimit = 12

    init(organizationID: String, organizationName: String, newsRepository: NewsRepository, eventRepository: EventRepository,
         activityLoader: (@MainActor (OrganizationActivityItemType) async throws -> [OrganizationActivityItem])? = nil,
         pageLoader: (@MainActor (OrganizationActivityItemType, OrganizationActivityCursor?) async throws -> OrganizationActivityPage)? = nil) {
        self.organizationID = organizationID
        self.newsRepository = newsRepository
        self.eventRepository = eventRepository
        self.activityLoader = activityLoader
        self.pageLoader = pageLoader
    }

    func reset() {
        generation &+= 1
        loadTasks.values.forEach { $0.cancel() }
        loadTasks.removeAll()
        cursors.removeAll()
        loadingTypes.removeAll()
        errors.removeAll()
        loadedItemTypes.removeAll()
        hasMoreTypes.removeAll()
        items.removeAll()
    }

    var isLoading: Bool { !loadingTypes.isEmpty }
    var error: AppError? { errors[.news] ?? errors[.event] }
    private func type(for section: OrganizationDetailSection) -> OrganizationActivityItemType? {
        switch section { case .news: .news; case .events: .event; default: nil }
    }
    func isLoading(section: OrganizationDetailSection) -> Bool { type(for: section).map(loadingTypes.contains) ?? false }
    func hasLoaded(section: OrganizationDetailSection) -> Bool { type(for: section).map(loadedItemTypes.contains) ?? true }
    func error(section: OrganizationDetailSection) -> AppError? { type(for: section).flatMap { errors[$0] } }
    func hasMore(section: OrganizationDetailSection) -> Bool { type(for: section).map(hasMoreTypes.contains) ?? false }

    func loadIfNeeded(for organization: Organization, section: OrganizationDetailSection) async {
        ensureProfileItem(for: organization)
        guard let type = type(for: section), !loadedItemTypes.contains(type) else { return }
        await load(for: organization, type: type, reset: true)
    }
    func refresh(for organization: Organization, section: OrganizationDetailSection) async {
        ensureProfileItem(for: organization)
        guard let type = type(for: section) else { return }
        await load(for: organization, type: type, reset: true)
    }
    func loadMore(for organization: Organization, section: OrganizationDetailSection) async {
        guard let type = type(for: section), hasMoreTypes.contains(type) else { return }
        await load(for: organization, type: type, reset: false)
    }

    private func load(for organization: Organization, type: OrganizationActivityItemType, reset: Bool) async {
        if let existing = loadTasks[type] { await existing.value; return }
        let currentGeneration = generation
        let task = Task { [weak self] in
            guard let self else { return }
            self.loadingTypes.insert(type)
            self.errors[type] = nil
            defer { if self.generation == currentGeneration { self.loadingTypes.remove(type) } }
            do {
                let cursor = reset ? nil : self.cursors[type]
                let page = try await self.fetchPage(type: type, after: cursor)
                guard !Task.isCancelled, self.generation == currentGeneration else { return }
                let retained = self.items.filter { $0.itemType != .organizationProfile && (!reset || $0.itemType != type) }
                var seen = Set<String>()
                let content = (retained + page.items.filter { $0.organizationId == self.organizationID })
                    .filter { seen.insert($0.id).inserted }
                    .sorted { $0.publishedAt == $1.publishedAt ? $0.id < $1.id : $0.publishedAt > $1.publishedAt }
                self.items = [OrganizationActivityItem(profile: organization)] + content
                self.cursors[type] = page.nextCursor
                if page.hasMore && page.nextCursor != nil { self.hasMoreTypes.insert(type) }
                else { self.hasMoreTypes.remove(type) }
                self.loadedItemTypes.insert(type)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, self.generation == currentGeneration else { return }
                self.errors[type] = error as? AppError ?? FirebaseReadErrorMapper.map(error)
            }
        }
        loadTasks[type] = task
        await task.value
        if generation == currentGeneration { loadTasks[type] = nil }
    }

    private func fetchPage(type: OrganizationActivityItemType, after cursor: OrganizationActivityCursor?) async throws -> OrganizationActivityPage {
        if let pageLoader { return try await pageLoader(type, cursor) }
        if let activityLoader {
            return OrganizationActivityPage(items: try await activityLoader(type), nextCursor: nil, hasMore: false)
        }
        let pagingRepository = type == .news
            ? newsRepository as? OrganizationActivityPageRepository
            : eventRepository as? OrganizationActivityPageRepository
        if let pagingRepository {
            return try await RefreshRequest.run { [self] in
                try await pagingRepository.fetchOrganizationActivityPage(organizationID: organizationID, limit: activityLimit, after: cursor)
            }
        }
        // Compatibility for other repository implementations; production uses cursor pages.
        if type == .news {
            let posts = try await newsRepository.fetchOrganizationNews(organizationID: organizationID, limit: activityLimit)
            return OrganizationActivityPage(items: posts.map(OrganizationActivityItem.init(post:)), nextCursor: nil, hasMore: false)
        }
        let events = try await eventRepository.fetchOrganizationEvents(organizationID: organizationID, limit: activityLimit)
        return OrganizationActivityPage(items: events.map(OrganizationActivityItem.init(event:)), nextCursor: nil, hasMore: false)
    }

    func update(for organization: Organization, posts: [NewsPost], events: [Event], isLoading: Bool, error: AppError?) {
        items = [OrganizationActivityItem(profile: organization)]
            + posts.filter { $0.source.displayOrganizationId == organizationID }.map(OrganizationActivityItem.init(post:))
            + events.filter { $0.source.displayOrganizationId == organizationID }.map(OrganizationActivityItem.init(event:))
        loadingTypes = isLoading ? [.news, .event] : []
        errors = error.map { [.news: $0, .event: $0] } ?? [:]
        loadedItemTypes = [.news, .event]
    }
    private func ensureProfileItem(for organization: Organization) {
        let profile = OrganizationActivityItem(profile: organization)
        items.removeAll { $0.itemType == .organizationProfile }
        items.insert(profile, at: 0)
    }
    var isEmptyStateWithoutProfile: Bool { items.allSatisfy { $0.itemType == .organizationProfile } }
}

struct OrganizationDetailView: View {
    @ObservedObject private var accessStore = OrganizationAccessStore.shared
    @EnvironmentObject var organizationBlockingCoordinator: OrganizationBlockingCoordinator
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) private var analyticsScenePhase
    @Environment(\.organizationPresentationMode) var presentationMode
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @Environment(\.contentReportPresentation) var contentReportPresentation
    @Environment(\.userBlockingPresentation) var userBlockingPresentation
    @EnvironmentObject var authState: AuthState
    @ObservedObject var viewModel: OrganizationsViewModel
    let organizationID: String
    let onOrganizationSaved: @MainActor () async -> Void
    let onOrganizationDeleted: @MainActor () -> Void
    let onNavigateBack: (() -> Void)?
    @State private var detailLoadState: ContentDetailLoadState = .loading
    @State var photoRefreshToken = 0
    @State private var refreshError: AppError?
    @State var showDeleteConfirmation = false
    @State var isShowingEditSheet = false
    @State var deleteErrorMessage: String?
    @State var pendingRemovalOrganizationID: String?
    @State var guestAccessAction: GuestAccessAction?
    @State var isAboutExpanded = false
    @State var selectedSection: OrganizationDetailSection = .about
    @State var selectedOrganizationEventCategory: EventCategory?
    @State var selectedOrganizationEventAudience: EventAudience?
    @State var selectedOrganizationEventAge: OrganizationEventAgeFilter = .any
    @State var recordedRecentViewKeys = Set<String>()
    @State var previewPhotos: [OrganizationPhoto] = []
    @State var loadedPreviewPhotoOrganizationID: String?
    @State var communityMembers: [OrganizationCommunityMember] = []
    @State var communitySubscriberReferences: [OrganizationSubscriberReference] = []
    @State var communitySubscriberCursor: OrganizationSubscriberCursor?
    @State var hasMoreCommunitySubscribers = false
    @State var communityLoadGeneration = UUID()
    @State var isLoadingCommunityPage = false
    @State var communityLoadErrorMessage: String?
    @State var loadedCommunityOrganizationID: String?
    @State var pendingCommentDeleteID: String?
    @State var commentDeleteErrorMessage: String?
    @State var pendingSubscriptionConfirmation: OrganizationSubscriptionConfirmation?
    @State var loadedCommentsOrganizationID: String?
    @StateObject var activityViewModel: OrganizationActivityViewModel
    @StateObject var newsDetailViewModel: NewsViewModel
    @StateObject var eventsDetailViewModel: EventsViewModel
    @FocusState var isCommentFieldFocused: Bool
    let newsRepository: NewsRepository
    let eventRepository: EventRepository
    let organizationRepository: OrganizationRepository
    let photoRepository: OrganizationPhotoRepository
    let heroLogoSize: CGFloat = 88
    let detailCardPadding: CGFloat = AppTheme.detailCardPadding
    let detailSectionSpacing: CGFloat = AppTheme.detailSectionSpacing
    let communityPageSize = 50

    init(
        viewModel: OrganizationsViewModel,
        organizationID: String,
        newsRepository: NewsRepository = FirestoreNewsRepository(),
        eventRepository: EventRepository = FirestoreEventRepository(),
        organizationRepository: OrganizationRepository = FirestoreOrganizationRepository(),
        photoRepository: OrganizationPhotoRepository = OrganizationPhotoRepositoryFactory.make(),
        newsViewModel: NewsViewModel? = nil,
        eventsViewModel: EventsViewModel? = nil,
        analyticsService: AnalyticsTracking = NoopAnalyticsService(),
        onOrganizationSaved: @escaping @MainActor () async -> Void = {},
        onOrganizationDeleted: @escaping @MainActor () -> Void = {},
        onNavigateBack: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.organizationID = organizationID
        self.newsRepository = newsRepository
        self.eventRepository = eventRepository
        self.organizationRepository = organizationRepository
        self.photoRepository = photoRepository
        self.onOrganizationSaved = onOrganizationSaved
        self.onOrganizationDeleted = onOrganizationDeleted
        self.onNavigateBack = onNavigateBack
        _activityViewModel = StateObject(wrappedValue: OrganizationActivityViewModel(
            organizationID: organizationID,
            organizationName: "",
            newsRepository: newsRepository,
            eventRepository: eventRepository
        ))
        _newsDetailViewModel = StateObject(wrappedValue: newsViewModel ?? NewsViewModel(
            repository: newsRepository,
            analyticsService: analyticsService
        ))
        _eventsDetailViewModel = StateObject(wrappedValue: eventsViewModel ?? EventsViewModel(
            repository: eventRepository,
            analyticsService: analyticsService
        ))
    }

    var isDeletingCurrentOrganization: Bool {
        viewModel.pendingOrganizationDeleteIDs.contains(organizationID)
    }

    var deleteErrorDialog: Binding<AppErrorDialog?> {
        Binding(
            get: {
                deleteErrorMessage.map {
                    AppErrorDialog(
                        title: AppStrings.Organizations.deleteFailed,
                        message: $0,
                        okTitle: AppStrings.Organizations.dismissError
                    )
                }
            },
            set: { if $0 == nil { deleteErrorMessage = nil } }
        )
    }

    var commentDeleteErrorDialog: Binding<AppErrorDialog?> {
        Binding(
            get: {
                commentDeleteErrorMessage.map {
                    AppErrorDialog(
                        title: AppStrings.Common.deleteCommentFailed,
                        message: $0,
                        okTitle: AppStrings.Organizations.dismissError
                    )
                }
            },
            set: { if $0 == nil { commentDeleteErrorMessage = nil } }
        )
    }

    var body: some View {
        Group {
            if let organization = viewModel.organization(for: organizationID) {
                DetailScreenShell(
                    contentSpacing: detailSectionSpacing,
                    backAction: navigateBack,
                    refreshAction: {
                        await refreshOrganizationDetail(for: organization)
                    }
                ) {
                    organizationHeaderActions(for: organization)
                } content: {
                    if let refreshError {
                        InlineMessageCard(style: .error, message: readableOrganizationErrorText(refreshError))
                    }
                    organizationHero(for: organization)
                        .onTapGesture { isCommentFieldFocused = false }
                    heroMetadata(for: organization)
                        .onTapGesture { isCommentFieldFocused = false }
                    supportCard(for: organization)
                        .onTapGesture { isCommentFieldFocused = false }
                    organizationSectionTabs
                        .onTapGesture { isCommentFieldFocused = false }
                    VStack(spacing: 0) {
                        selectedSectionContent(for: organization)
                    }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("organization.content.\(selectedSection)")
                        .onTapGesture { isCommentFieldFocused = false }
                    actionButtons(for: organization)
                        .onTapGesture { isCommentFieldFocused = false }
                    LazyVStack(spacing: 0) {
                        commentsSection(for: organization)
                            .id("organizationCommentsSection")
                            .onAppear {
                                Task {
                                    await loadCommentsIfNeeded(for: organization.id)
                                }
                            }
                    }
                }
                .task(id: analyticsScenePhase == .active ? organization.id : nil) {
                    guard analyticsScenePhase == .active else { return }
                    await viewModel.trackViewWhileVisible(for: organization)
                }
                .task(id: organization.id) {
                    recordRecentView(for: organization)
                }
            } else {
                DetailScreenShell(backAction: navigateBack) {
                    ContentDetailLoadStateCard(
                        state: detailLoadState == .content ? .loading : detailLoadState,
                        accessibilityPrefix: "organization.detail.state",
                        retryAction: { Task { await loadOrganizationDetail(force: true) } }
                    )
                }
            }
        }
        .task(id: "\(organizationID):\(authState.user?.id ?? "guest")") {
            activityViewModel.reset()
            communityLoadGeneration = UUID()
            isLoadingCommunityPage = false
            communityMembers = []
            communitySubscriberReferences = []
            communitySubscriberCursor = nil
            hasMoreCommunitySubscribers = false
            loadedCommunityOrganizationID = nil
            communityLoadErrorMessage = nil
            await loadOrganizationDetail(force: false)
        }
        .appDestructiveActionDialog(Binding(
            get: {
                guard showDeleteConfirmation else { return nil }
                return AppDestructiveActionDialog(
                    title: AppStrings.Organizations.deleteConfirmation,
                    message: "",
                    destructiveActionTitle: AppStrings.Organizations.delete,
                    cancelTitle: AppStrings.Organizations.cancel
                ) {
                    guard !isDeletingCurrentOrganization else { return }
                    Task {
                        await deleteCurrentOrganization()
                    }
                }
            },
            set: { if $0 == nil { showDeleteConfirmation = false } }
        ))
        .confirmationDialog(organizationSubscriptionConfirmationTitle, isPresented: Binding(
            get: { pendingSubscriptionConfirmation != nil },
            set: { if !$0 { pendingSubscriptionConfirmation = nil } }
        ), titleVisibility: .visible) {
            Button(organizationSubscriptionConfirmationButton, role: pendingSubscriptionConfirmation?.isUnsubscribe == true ? .destructive : nil) {
                confirmPendingSubscriptionChange()
            }
            .accessibilityIdentifier("organization.subscription.confirm")
            Button(AppStrings.Organizations.cancel, role: .cancel) {
                pendingSubscriptionConfirmation = nil
            }
        } message: {
            Text(organizationSubscriptionConfirmationMessage)
        }
        .appDestructiveActionDialog(Binding(
            get: {
                guard let commentID = pendingCommentDeleteID else { return nil }
                return AppDestructiveActionDialog(
                    title: AppStrings.Common.deleteCommentConfirmation,
                    message: "",
                    destructiveActionTitle: AppStrings.Action.delete,
                    cancelTitle: AppStrings.Organizations.cancel
                ) {
                    Task {
                        await deleteComment(commentID: commentID)
                    }
                }
            },
            set: { if $0 == nil { pendingCommentDeleteID = nil } }
        ))
        .appErrorDialog(deleteErrorDialog)
        .appErrorDialog(commentDeleteErrorDialog)
        .sheet(isPresented: $isShowingEditSheet) {
            if let organization = viewModel.organization(for: organizationID) {
                NavigationStack {
                    OrganizationEditorView(
                        organizationsViewModel: viewModel,
                        organization: organization,
                        onSaved: {
                            await onOrganizationSaved()
                            await refreshOrganizationDetail(for: organization)
                        }
                    )
                }
                .environmentObject(authState)
            }
        }
        .guestAccessAlert($guestAccessAction)
        .appErrorDialog(Binding(
            get: {
                viewModel.interactionError.map {
                    AppErrorDialog(message: readableOrganizationErrorText($0))
                }
            },
            set: { if $0 == nil { viewModel.dismissInteractionError() } }
        ))
        .onChange(of: authState.user?.id) { _, _ in
            loadedCommentsOrganizationID = nil
            Task { await loadCommentsIfNeeded(for: organizationID) }
            guard let organization = viewModel.organization(for: organizationID) else { return }
            recordRecentView(for: organization)
        }
        .onChange(of: selectedSection) { _, _ in
            guard let organization = viewModel.organization(for: organizationID) else { return }
            Task {
                await loadSelectedSectionDataIfNeeded(for: organization)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .organizationsChanged).debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { notification in
            guard AppContentChangeBus.organizationID(from: notification) == organizationID else { return }
            Task {
                await loadOrganizationDetail(force: true)
                if let organization = viewModel.organization(for: organizationID) {
                    await refreshSelectedSectionData(for: organization)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newsChanged).debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { notification in
            guard AppContentChangeBus.organizationID(from: notification) == organizationID else { return }
            guard let organization = viewModel.organization(for: organizationID) else { return }
            Task {
                guard selectedSection == .news else { return }
                await refreshOrganizationActivity(for: organization, section: .news)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eventsChanged).debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { notification in
            guard AppContentChangeBus.organizationID(from: notification) == organizationID else { return }
            guard let organization = viewModel.organization(for: organizationID) else { return }
            Task {
                guard selectedSection == .events else { return }
                await refreshOrganizationActivity(for: organization, section: .events)
            }
        }
        .onDisappear {
            viewModel.stopListeningComments(for: organizationID)
            loadedCommentsOrganizationID = nil
            guard let pendingRemovalOrganizationID else { return }
            withTransaction(Transaction(animation: nil)) {
                viewModel.removeDeletedOrganization(id: pendingRemovalOrganizationID)
            }
            self.pendingRemovalOrganizationID = nil
        }
    }

    var canInteractWithOrganization: Bool {
        !authState.isAuthenticated || PermissionService.isUsableAccount(user: authState.user)
    }

    @MainActor
    func loadOrganizationDetail(force: Bool) async {
        if viewModel.organization(for: organizationID) == nil { detailLoadState = .loading }
        let organization = await viewModel.resolveOrganization(id: organizationID, force: force)
        guard !Task.isCancelled else { return }
        guard let organization else {
            detailLoadState = .failed(viewModel.error ?? .notFound)
            return
        }
        detailLoadState = .content
        await loadSelectedSectionDataIfNeeded(for: organization)
    }

    func recordRecentView(for organization: Organization) {
        guard authState.user != nil else { return }
        let key = "\(organization.id)-\(authState.user?.id ?? "guest")"
        guard !recordedRecentViewKeys.contains(key) else { return }
        recordedRecentViewKeys.insert(key)
        RecentViewRecorder.recordOrganization(organization)
    }

    var organizationSubscriptionConfirmationTitle: String {
        guard let pendingSubscriptionConfirmation else {
            return AppStrings.Organizations.confirmSubscribeTitle
        }
        return pendingSubscriptionConfirmation.isUnsubscribe
        ? AppStrings.Organizations.confirmUnsubscribeTitle
        : AppStrings.Organizations.confirmSubscribeTitle
    }

    var organizationSubscriptionConfirmationButton: String {
        guard let pendingSubscriptionConfirmation else {
            return AppStrings.Organizations.confirmSubscribeButton
        }
        return pendingSubscriptionConfirmation.isUnsubscribe
        ? AppStrings.Organizations.confirmUnsubscribeButton
        : AppStrings.Organizations.confirmSubscribeButton
    }

    var organizationSubscriptionConfirmationMessage: String {
        guard let pendingSubscriptionConfirmation,
              let organization = viewModel.organization(for: pendingSubscriptionConfirmation.organizationID) else {
            return ""
        }
        return pendingSubscriptionConfirmation.isUnsubscribe
        ? AppStrings.Organizations.confirmUnsubscribeMessage(organization.localizedName)
        : AppStrings.Organizations.confirmSubscribeMessage(organization.localizedName)
    }

    func confirmPendingSubscriptionChange() {
        guard let pendingSubscriptionConfirmation,
              let organization = viewModel.organization(for: pendingSubscriptionConfirmation.organizationID) else {
            self.pendingSubscriptionConfirmation = nil
            return
        }
        toggleSubscription(for: organization)
        self.pendingSubscriptionConfirmation = nil
    }

    @MainActor
    func loadPreviewPhotosIfNeeded(for organizationID: String) async {
        guard loadedPreviewPhotoOrganizationID != organizationID else { return }
        loadedPreviewPhotoOrganizationID = organizationID

        do {
            previewPhotos = try await RefreshRequest.run { [self] in try await photoRepository.fetchPhotos(organizationId: organizationID) }
        } catch {
            loadedPreviewPhotoOrganizationID = nil
        }
    }

    @MainActor
    func reloadPreviewPhotos(for organizationID: String) async {
        loadedPreviewPhotoOrganizationID = nil
        await loadPreviewPhotosIfNeeded(for: organizationID)
    }

    @MainActor
    func refreshOrganizationDetail(for organization: Organization) async {
        refreshError = nil
        guard let refreshedOrganization = await viewModel.resolveOrganization(id: organization.id, force: true) else {
            refreshError = viewModel.error
            if viewModel.organization(for: organization.id) == nil { detailLoadState = .failed(viewModel.error ?? .notFound) }
            return
        }
        detailLoadState = .content
        async let comments: Void = refreshCommentsIfLoaded(for: refreshedOrganization.id)
        async let section: Void = refreshSelectedSectionData(for: refreshedOrganization)
        _ = await (comments, section)
    }

    @MainActor
    func loadCommentsIfNeeded(for organizationID: String) async {
        guard loadedCommentsOrganizationID != organizationID else { return }
        loadedCommentsOrganizationID = organizationID
        await viewModel.loadComments(for: organizationID)
    }

    @MainActor
    func refreshCommentsIfLoaded(for organizationID: String) async {
        guard loadedCommentsOrganizationID == organizationID else { return }
        await viewModel.loadComments(for: organizationID, forceRefresh: true)
    }

    @MainActor
    func loadSelectedSectionDataIfNeeded(for organization: Organization) async {
        switch selectedSection {
        case .news, .events:
            await loadOrganizationActivityIfNeeded(for: organization, section: selectedSection)
        case .team:
            await loadCommunityMembersIfNeeded(for: organization)
        case .about, .photos, .contacts:
            break
        }
    }

    @MainActor
    func refreshSelectedSectionData(for organization: Organization) async {
        switch selectedSection {
        case .news, .events:
            await refreshOrganizationActivity(for: organization, section: selectedSection)
        case .team:
            await reloadCommunityMembers(for: organization)
        case .photos:
            photoRefreshToken += 1
        case .about, .contacts:
            break
        }
    }

    @MainActor
    func loadOrganizationActivityIfNeeded(for organization: Organization, section: OrganizationDetailSection) async {
        await activityViewModel.loadIfNeeded(for: organization, section: section)
    }

    @MainActor
    func refreshOrganizationActivity(for organization: Organization, section: OrganizationDetailSection) async {
        await activityViewModel.refresh(for: organization, section: section)
    }

    @MainActor
    func loadCommunityMembersIfNeeded(for organization: Organization) async {
        guard loadedCommunityOrganizationID != organization.id else { return }
        loadedCommunityOrganizationID = organization.id
        communityMembers = []
        communitySubscriberReferences = []
        communitySubscriberCursor = nil
        hasMoreCommunitySubscribers = false
        communityLoadErrorMessage = nil
        await loadCommunityMembersPage(for: organization, reset: true)
    }

    @MainActor
    func reloadCommunityMembers(for organization: Organization) async {
        await loadCommunityMembersPage(for: organization, reset: true)
    }

    @MainActor
    func loadCommunityMembersPage(for organization: Organization, reset: Bool) async {
        guard !isLoadingCommunityPage else { return }
        if reset {
            communityLoadErrorMessage = nil
        }
        let generation = communityLoadGeneration
        let accountID = authState.user?.id
        var subscriberReadFailed = false
        isLoadingCommunityPage = true
        defer { if generation == communityLoadGeneration { isLoadingCommunityPage = false } }

        let roleByUserID = communityRoleMap(for: organization)
        let roleUserIDs = Array(roleByUserID.keys)

        if PermissionService.canViewOrganizationSubscriberIdentities(organization, user: authState.user) {
            do {
                let page = try await RefreshRequest.run { [self] in try await organizationRepository.fetchOrganizationSubscriberPage(
                    organizationID: organization.id,
                    limit: communityPageSize,
                    after: reset ? nil : communitySubscriberCursor
                ) }
                guard !Task.isCancelled, generation == communityLoadGeneration, accountID == authState.user?.id else { return }
                communitySubscriberCursor = page.nextCursor
                hasMoreCommunitySubscribers = page.hasMore
                mergeCommunitySubscriberReferences(page.items, reset: reset)
            } catch {
                guard !Task.isCancelled, generation == communityLoadGeneration, accountID == authState.user?.id else { return }
                subscriberReadFailed = true
                if reset {
                    communitySubscriberReferences = []
                    communitySubscriberCursor = nil
                    hasMoreCommunitySubscribers = false
                }
            }
        } else {
            // Public team pages show official roles without exposing subscriber identities.
            communitySubscriberReferences = []
            communitySubscriberCursor = nil
            hasMoreCommunitySubscribers = false
        }

        let followedAtByUserID = Dictionary(uniqueKeysWithValues: communitySubscriberReferences.map { ($0.userID, $0.followedAt) })
        let userIDs = Array(Set(roleUserIDs + communitySubscriberReferences.map(\.userID)))

        do {
            let profiles = try await RefreshRequest.run { [self] in try await organizationRepository.fetchPublicUserProfiles(userIDs: userIDs) }
            guard !Task.isCancelled, generation == communityLoadGeneration, accountID == authState.user?.id else { return }
            var loadedProfileIDs = Set<String>()
            var members: [OrganizationCommunityMember] = []
            for profile in profiles {
                loadedProfileIDs.insert(profile.id)
                members.append(OrganizationCommunityMember(
                    profile: profile,
                    role: roleByUserID[profile.id] ?? .subscriber,
                    followedAt: followedAtByUserID[profile.id] ?? nil,
                    isPlaceholder: false
                ))
            }

            let missingRoleMembers = roleByUserID
                .filter { userID, _ in !loadedProfileIDs.contains(userID) }
                .map { userID, role in
                    OrganizationCommunityMember(
                        profile: PublicUserProfile(
                            id: userID,
                            displayName: AppStrings.Organizations.communityProfileUnavailable,
                            avatarURL: nil,
                            city: "",
                            federalState: nil,
                            updatedAt: nil
                        ),
                        role: role,
                        followedAt: followedAtByUserID[userID] ?? nil,
                        isPlaceholder: true
                    )
                }

            members.append(contentsOf: missingRoleMembers)
            communityMembers = members.sorted(by: communityMemberSort)
            communityLoadErrorMessage = subscriberReadFailed ? AppStrings.Organizations.communityLoadFailed : nil
        } catch {
            guard !Task.isCancelled, generation == communityLoadGeneration, accountID == authState.user?.id else { return }
            if reset {
                communityMembers = []
            }
            communityLoadErrorMessage = AppStrings.Organizations.communityLoadFailed
        }
    }

    @MainActor
    func mergeCommunitySubscriberReferences(_ references: [OrganizationSubscriberReference], reset: Bool) {
        if reset {
            communitySubscriberReferences = []
        }

        var seenUserIDs = Set(communitySubscriberReferences.map(\.userID))
        let newReferences = references.filter { reference in
            seenUserIDs.insert(reference.userID).inserted
        }
        communitySubscriberReferences.append(contentsOf: newReferences)
    }
}
