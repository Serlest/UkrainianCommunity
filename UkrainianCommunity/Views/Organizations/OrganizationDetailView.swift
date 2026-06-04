import Combine
import MapKit
import PhotosUI
import SwiftUI

enum OrganizationDetailSection: CaseIterable, Identifiable {
    case about
    case news
    case events
    case photos
    case team
    case contacts

    var id: Self { self }

    static var selectableCases: [OrganizationCategoryFilter] {
        [.support, .integration, .culture, .education, .other]
    }

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
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?

    private let organizationID: String
    private let organizationName: String
    private let newsRepository: NewsRepository
    private let eventRepository: EventRepository
    private var hasLoaded = false
    private var loadTask: Task<Void, Never>?

    init(
        organizationID: String,
        organizationName: String,
        newsRepository: NewsRepository,
        eventRepository: EventRepository
    ) {
        self.organizationID = organizationID
        self.organizationName = organizationName
        self.newsRepository = newsRepository
        self.eventRepository = eventRepository
    }

    func loadIfNeeded(for organization: Organization) async {
        guard !hasLoaded else { return }
        await startLoad(for: organization, force: false)
    }

    func refresh(for organization: Organization) async {
        await startLoad(for: organization, force: true)
    }

    private func startLoad(for organization: Organization, force: Bool) async {
        guard force || !hasLoaded else { return }

        if let loadTask {
            await loadTask.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoad(for: organization)
        }
        loadTask = task
        await task.value
        self.loadTask = nil
    }

    private func performLoad(for organization: Organization) async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let newsLoad = newsRepository.fetchNews()
            async let eventsLoad = eventRepository.fetchEvents()

            let filteredNews = try await newsLoad
                .filter { belongsToOrganization($0.source, organization: organization) }
                .map(OrganizationActivityItem.init(post:))
            let filteredEvents = try await eventsLoad
                .filter { belongsToOrganization($0.source, organization: organization) }
                .map(OrganizationActivityItem.init(event:))

            guard !Task.isCancelled else { return }

            let profileItem = OrganizationActivityItem(profile: organization)
            let activityItems = (filteredNews + filteredEvents)
                .sorted { $0.publishedAt > $1.publishedAt }
            items = [profileItem] + activityItems
            error = nil
            hasLoaded = true
        } catch is CancellationError {
        } catch let appError as AppError {
            guard !Task.isCancelled else { return }
            error = appError
        } catch {
            guard !Task.isCancelled else { return }
            self.error = .unknown
        }
    }

    var isEmptyStateWithoutProfile: Bool {
        items.filter { $0.itemType != .organizationProfile }.isEmpty
    }

    private func belongsToOrganization(_ source: ContentSourceMetadata, organization: Organization) -> Bool {
        if organization.isSystemOrganization {
            return source.sourceType == .app || source.organizationId == Organization.systemOrganizationID
        }
        return source.organizationId == organizationID
    }
}

struct OrganizationDetailView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.organizationPresentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @EnvironmentObject var authState: AuthState
    @ObservedObject var viewModel: OrganizationsViewModel
    let organizationID: String
    let onOrganizationSaved: @MainActor () async -> Void
    let onOrganizationDeleted: @MainActor () -> Void
    let onNavigateBack: (() -> Void)?
    @State var showDeleteConfirmation = false
    @State var deleteErrorMessage: String?
    @State var pendingRemovalOrganizationID: String?
    @State var guestAccessAction: GuestAccessAction?
    @State var isAboutExpanded = false
    @State var selectedSection: OrganizationDetailSection = .about
    @State var recordedRecentViewKeys = Set<String>()
    @State var previewPhotos: [OrganizationPhoto] = []
    @State var loadedPreviewPhotoOrganizationID: String?
    @State var communityMembers: [OrganizationCommunityMember] = []
    @State var communitySubscriberReferences: [OrganizationSubscriberReference] = []
    @State var communitySubscriberCursor: OrganizationSubscriberCursor?
    @State var hasMoreCommunitySubscribers = false
    @State var isLoadingCommunityPage = false
    @State var loadedCommunityOrganizationID: String?
    @State var commentText = ""
    @State var editingCommentID: String?
    @State var pendingCommentDeleteID: String?
    @State var commentDeleteErrorMessage: String?
    @State var pendingSubscriptionConfirmation: OrganizationSubscriptionConfirmation?
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
        photoRepository: OrganizationPhotoRepository = FirestoreOrganizationPhotoRepository(),
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
        _newsDetailViewModel = StateObject(wrappedValue: NewsViewModel(repository: newsRepository))
        _eventsDetailViewModel = StateObject(wrappedValue: EventsViewModel(repository: eventRepository))
    }

    var isDeletingCurrentOrganization: Bool {
        viewModel.pendingOrganizationDeleteIDs.contains(organizationID)
    }

    var body: some View {
        Group {
            if let organization = viewModel.organization(for: organizationID) {
                GeometryReader { proxy in
                    let contentHorizontalPadding = AppTheme.pageHorizontal
                    let contentWidth = max(proxy.size.width - (contentHorizontalPadding * 2), 0)

                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: detailSectionSpacing) {
                            detailHeader(for: organization)

                            organizationHero(for: organization)
                                .onTapGesture { isCommentFieldFocused = false }
                            heroMetadata(for: organization)
                                .onTapGesture { isCommentFieldFocused = false }
                            supportCard(for: organization)
                                .onTapGesture { isCommentFieldFocused = false }
                            organizationSectionTabs
                                .onTapGesture { isCommentFieldFocused = false }
                            selectedSectionContent(for: organization)
                                .onTapGesture { isCommentFieldFocused = false }
                            actionButtons(for: organization)
                                .onTapGesture { isCommentFieldFocused = false }
                            commentsSection(for: organization)
                                .id("organizationCommentsSection")
                        }
                        .frame(width: contentWidth, alignment: .leading)
                        .padding(.horizontal, contentHorizontalPadding)
                        .padding(.bottom, AppTheme.homeBottomContentPadding + 160)
                    }
                    .frame(width: proxy.size.width)
                    .scrollDismissesKeyboard(.interactively)
                    .refreshable {
                        await refreshOrganizationDetail(for: organization)
                    }
                }
                .task(id: organization.id) {
                    await activityViewModel.loadIfNeeded(for: organization)
                    await newsDetailViewModel.loadIfNeeded()
                    await eventsDetailViewModel.loadIfNeeded()
                    await viewModel.loadComments(for: organization.id)
                    await loadPreviewPhotosIfNeeded(for: organization.id)
                    await loadCommunityMembersIfNeeded(for: organization)
                    recordRecentView(for: organization)
                }
            } else {
                EmptyStateView(title: AppStrings.Common.noItems)
            }
        }
        .background(AppBackgroundView().allowsHitTesting(false))
        .toolbar(.hidden, for: .navigationBar)
        .dismissesKeyboardOnBackgroundTap()
        .confirmationDialog(AppStrings.Organizations.deleteConfirmation, isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button(AppStrings.Organizations.delete, role: .destructive) {
                guard !isDeletingCurrentOrganization else { return }
                Task {
                    await deleteCurrentOrganization()
                }
            }
            Button(AppStrings.Organizations.cancel, role: .cancel) {}
        }
        .confirmationDialog(organizationSubscriptionConfirmationTitle, isPresented: Binding(
            get: { pendingSubscriptionConfirmation != nil },
            set: { if !$0 { pendingSubscriptionConfirmation = nil } }
        ), titleVisibility: .visible) {
            Button(organizationSubscriptionConfirmationButton, role: pendingSubscriptionConfirmation?.isUnsubscribe == true ? .destructive : nil) {
                confirmPendingSubscriptionChange()
            }
            Button(AppStrings.Organizations.cancel, role: .cancel) {
                pendingSubscriptionConfirmation = nil
            }
        } message: {
            Text(organizationSubscriptionConfirmationMessage)
        }
        .confirmationDialog(AppStrings.Common.deleteCommentConfirmation, isPresented: Binding(
            get: { pendingCommentDeleteID != nil },
            set: { if !$0 { pendingCommentDeleteID = nil } }
        ), titleVisibility: .visible) {
            Button(AppStrings.Action.delete, role: .destructive) {
                guard let pendingCommentDeleteID else { return }
                Task {
                    await deleteComment(commentID: pendingCommentDeleteID)
                }
            }
            Button(AppStrings.Organizations.cancel, role: .cancel) {
                pendingCommentDeleteID = nil
            }
        }
        .alert(AppStrings.Organizations.deleteFailed, isPresented: Binding(
            get: { deleteErrorMessage != nil },
            set: { if !$0 { deleteErrorMessage = nil } }
        )) {
            Button(AppStrings.Organizations.dismissError, role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "")
        }
        .alert(AppStrings.Common.deleteCommentFailed, isPresented: Binding(
            get: { commentDeleteErrorMessage != nil },
            set: { if !$0 { commentDeleteErrorMessage = nil } }
        )) {
            Button(AppStrings.Organizations.dismissError, role: .cancel) {}
        } message: {
            Text(commentDeleteErrorMessage ?? readableOrganizationErrorText(.unknown))
        }
        .guestAccessAlert($guestAccessAction)
        .onChange(of: authState.user?.id) { _, _ in
            guard let organization = viewModel.organization(for: organizationID) else { return }
            recordRecentView(for: organization)
        }
        .onReceive(NotificationCenter.default.publisher(for: .organizationsChanged).debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { notification in
            guard AppContentChangeBus.organizationID(from: notification) == organizationID else { return }
            Task {
                await viewModel.refresh()
                if let organization = viewModel.organization(for: organizationID) {
                    await activityViewModel.refresh(for: organization)
                    await reloadPreviewPhotos(for: organization.id)
                    await reloadCommunityMembers(for: organization)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newsChanged).debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { notification in
            guard AppContentChangeBus.organizationID(from: notification) == organizationID else { return }
            guard let organization = viewModel.organization(for: organizationID) else { return }
            Task {
                await activityViewModel.refresh(for: organization)
                await newsDetailViewModel.refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eventsChanged).debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { notification in
            guard AppContentChangeBus.organizationID(from: notification) == organizationID else { return }
            guard let organization = viewModel.organization(for: organizationID) else { return }
            Task {
                await activityViewModel.refresh(for: organization)
                await eventsDetailViewModel.refresh()
            }
        }
        .onDisappear {
            viewModel.stopListeningComments(for: organizationID)
            guard let pendingRemovalOrganizationID else { return }
            withTransaction(Transaction(animation: nil)) {
                viewModel.removeDeletedOrganization(id: pendingRemovalOrganizationID)
            }
            self.pendingRemovalOrganizationID = nil
        }
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
        ? AppStrings.Organizations.confirmUnsubscribeMessage(organization.name)
        : AppStrings.Organizations.confirmSubscribeMessage(organization.name)
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
            previewPhotos = try await photoRepository.fetchPhotos(organizationId: organizationID)
        } catch {
            previewPhotos = []
        }
    }

    @MainActor
    func reloadPreviewPhotos(for organizationID: String) async {
        loadedPreviewPhotoOrganizationID = nil
        previewPhotos = []
        await loadPreviewPhotosIfNeeded(for: organizationID)
    }

    @MainActor
    func refreshOrganizationDetail(for organization: Organization) async {
        await viewModel.refresh()
        let refreshedOrganization = viewModel.organization(for: organization.id) ?? organization
        await activityViewModel.refresh(for: refreshedOrganization)
        await newsDetailViewModel.refresh()
        await eventsDetailViewModel.refresh()
        await viewModel.loadComments(for: refreshedOrganization.id)
        await reloadPreviewPhotos(for: refreshedOrganization.id)
        await reloadCommunityMembers(for: refreshedOrganization)
    }

    @MainActor
    func loadCommunityMembersIfNeeded(for organization: Organization) async {
        guard loadedCommunityOrganizationID != organization.id else { return }
        loadedCommunityOrganizationID = organization.id
        communityMembers = []
        communitySubscriberReferences = []
        communitySubscriberCursor = nil
        hasMoreCommunitySubscribers = false
        await loadCommunityMembersPage(for: organization, reset: true)
    }

    @MainActor
    func reloadCommunityMembers(for organization: Organization) async {
        loadedCommunityOrganizationID = nil
        communityMembers = []
        communitySubscriberReferences = []
        communitySubscriberCursor = nil
        hasMoreCommunitySubscribers = false
        await loadCommunityMembersIfNeeded(for: organization)
    }

    @MainActor
    func loadCommunityMembersPage(for organization: Organization, reset: Bool) async {
        guard !isLoadingCommunityPage else { return }
        isLoadingCommunityPage = true
        defer { isLoadingCommunityPage = false }

        let roleByUserID = communityRoleMap(for: organization)
        let roleUserIDs = Array(roleByUserID.keys)

        do {
            let page = try await organizationRepository.fetchOrganizationSubscriberPage(
                organizationID: organization.id,
                limit: communityPageSize,
                after: reset ? nil : communitySubscriberCursor
            )
            communitySubscriberCursor = page.nextCursor
            hasMoreCommunitySubscribers = page.hasMore
            mergeCommunitySubscriberReferences(page.items, reset: reset)
        } catch {
            if reset {
                communitySubscriberReferences = []
                communitySubscriberCursor = nil
                hasMoreCommunitySubscribers = false
            }
        }

        let followedAtByUserID = Dictionary(uniqueKeysWithValues: communitySubscriberReferences.map { ($0.userID, $0.followedAt) })
        let userIDs = Array(Set(roleUserIDs + communitySubscriberReferences.map(\.userID)))

        do {
            let profiles = try await organizationRepository.fetchPublicUserProfiles(userIDs: userIDs)
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
        } catch {
            communityMembers = roleByUserID.map { userID, role in
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
                    followedAt: nil,
                    isPlaceholder: true
                )
            }
            .sorted(by: communityMemberSort)
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
