import Combine
import Foundation

@MainActor
final class OrganizationsViewModel: ObservableObject {
    @Published var organizations: [Organization]
    @Published private(set) var isLoading: Bool
    @Published private(set) var error: AppError?
    @Published private(set) var interactionError: AppError?
    @Published private(set) var isLoadingNextPage = false
    @Published private(set) var hasMorePages = false
    @Published private(set) var contentVersion = 0
    @Published private(set) var pendingOrganizationLikeIDs = Set<String>()
    @Published private(set) var pendingOrganizationSubscriptionIDs = Set<String>()
    @Published private(set) var pendingOrganizationBookmarkIDs = Set<String>()
    @Published private(set) var pendingOrganizationDeleteIDs = Set<String>()
    @Published private(set) var organizationRequests: [Organization] = []
    @Published private(set) var organizationCommentsByID: [String: [Comment]] = [:]
    @Published private(set) var commentLoadStates: [String: CommentLoadState] = [:]
    @Published private(set) var pendingOrganizationCommentIDs = Set<String>()
    @Published private(set) var isSavingOrganization = false
    @Published private(set) var isUploadingOrganizationImage = false
    @Published private(set) var validationErrorMessage: String?
    private let repository: OrganizationRepository
    private let notificationInboxRepository: NotificationInboxRepository?
    private let analyticsService: AnalyticsTracking
    private let listenerBag = RealtimeListenerBag()
    private var loadTask: Task<Void, Never>?
    private var nextPageTask: Task<Void, Never>?
    private var hasLoaded = false
    private var lastLoadedAt: Date?
    private var nextPageCursor: OrganizationPageCursor?
    private var trackedOrganizationViewIDs = Set<String>()
    private var visibilityPolicy = ContentVisibilityPolicy()
    private var authGeneration: UInt = 0
    private var feedRevision: UInt = 0
    private var interactionTasks: [String: Task<Void, Never>] = [:]

    init(
        repository: OrganizationRepository,
        notificationInboxRepository: NotificationInboxRepository? = nil,
        analyticsService: AnalyticsTracking = NoopAnalyticsService()
    ) {
        self.repository = repository
        self.notificationInboxRepository = notificationInboxRepository
        self.analyticsService = analyticsService
        organizations = []
        isLoading = false
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await startLoad(force: false)
    }

    func reload() {
        Task {
            await refresh()
        }
    }

    func refresh() async {
        await startLoad(force: true)
    }

    func refreshIfStale(maxAge: TimeInterval = organizationRefreshStaleInterval) async {
        guard hasLoaded else {
            await loadIfNeeded()
            return
        }

        guard let lastLoadedAt else {
            await refresh()
            return
        }

        guard Date().timeIntervalSince(lastLoadedAt) > maxAge else { return }
        await refresh()
    }

    func resetForAuthChange() {
        authGeneration &+= 1
        feedRevision &+= 1
        loadTask?.cancel()
        nextPageTask?.cancel()
        interactionTasks.values.forEach { $0.cancel() }
        loadTask = nil
        nextPageTask = nil
        interactionTasks.removeAll()
        organizations = []
        isLoading = false
        isLoadingNextPage = false
        hasMorePages = false
        error = nil
        interactionError = nil
        contentVersion &+= 1
        pendingOrganizationLikeIDs = []
        pendingOrganizationSubscriptionIDs = []
        pendingOrganizationBookmarkIDs = []
        pendingOrganizationDeleteIDs = []
        trackedOrganizationViewIDs = []
        organizationRequests = []
        organizationCommentsByID = [:]
        pendingOrganizationCommentIDs = []
        commentLoadStates = [:]
        listenerBag.removeAll()
        isSavingOrganization = false
        isUploadingOrganizationImage = false
        validationErrorMessage = nil
        hasLoaded = false
        lastLoadedAt = nil
        nextPageCursor = nil
    }

    func toggleLike(for organizationID: String) {
        guard let index = organizations.firstIndex(where: { $0.id == organizationID }) else { return }
        guard !pendingOrganizationLikeIDs.contains(organizationID) else { return }
        let shouldLike = organizations[index].likeState == .notLiked
        let previousLikeState = organizations[index].likeState
        let previousLikeCount = organizations[index].likeCount
        let optimisticLikeState: LikeState = shouldLike ? .liked : .notLiked
        let optimisticLikeCount = max(0, previousLikeCount + (shouldLike ? 1 : -1))
        let generation = authGeneration
        let requestFeedRevision = feedRevision
        let taskKey = "like:\(organizationID)"

        pendingOrganizationLikeIDs.insert(organizationID)
        interactionError = nil
        organizations[index].likeState = optimisticLikeState
        organizations[index].likeCount = optimisticLikeCount
        contentVersion &+= 1

        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.isCurrentAuthGeneration(generation) {
                    self.pendingOrganizationLikeIDs.remove(organizationID)
                    self.interactionTasks[taskKey] = nil
                }
            }

            do {
                if shouldLike {
                    try await repository.likeOrganization(id: organizationID)
                } else {
                    try await repository.unlikeOrganization(id: organizationID)
                }

                guard isCurrentAuthGeneration(generation),
                      let currentIndex = organizations.firstIndex(where: { $0.id == organizationID }) else { return }
                if organizations[currentIndex].likeState == previousLikeState {
                    organizations[currentIndex].likeState = optimisticLikeState
                    organizations[currentIndex].likeCount = max(
                        0,
                        organizations[currentIndex].likeCount + (shouldLike ? 1 : -1)
                    )
                    contentVersion &+= 1
                }
                interactionError = nil
            } catch let appError as AppError {
                guard isCurrentAuthGeneration(generation) else { return }
                rollbackLike(
                    organizationID: organizationID,
                    optimisticState: optimisticLikeState,
                    optimisticCount: optimisticLikeCount,
                    previousState: previousLikeState,
                    previousCount: previousLikeCount,
                    requestFeedRevision: requestFeedRevision
                )
                interactionError = appError
            } catch {
                guard isCurrentAuthGeneration(generation) else { return }
                rollbackLike(
                    organizationID: organizationID,
                    optimisticState: optimisticLikeState,
                    optimisticCount: optimisticLikeCount,
                    previousState: previousLikeState,
                    previousCount: previousLikeCount,
                    requestFeedRevision: requestFeedRevision
                )
                self.interactionError = .unknown
            }
        }
        interactionTasks[taskKey] = task
    }

    func toggleSubscription(for organizationID: String) {
        guard let index = organizations.firstIndex(where: { $0.id == organizationID }) else { return }
        guard !pendingOrganizationSubscriptionIDs.contains(organizationID) else { return }
        let shouldSubscribe = !organizations[index].isSubscribed
        let previousSubscriptionState = organizations[index].isSubscribed
        let previousSubscriberCount = organizations[index].subscriberCount
        let optimisticSubscriberCount = max(0, previousSubscriberCount + (shouldSubscribe ? 1 : -1))
        let organization = organizations[index]
        let actionEvent = AppAnalyticsEvent.organizationFollow(organization: organization)
        let actionCapture = shouldSubscribe ? analyticsService.actionCapture(for: actionEvent) : nil
        let generation = authGeneration
        let requestFeedRevision = feedRevision
        let taskKey = "subscription:\(organizationID)"

        pendingOrganizationSubscriptionIDs.insert(organizationID)
        interactionError = nil
        organizations[index].isSubscribed = shouldSubscribe
        organizations[index].subscriberCount = optimisticSubscriberCount
        contentVersion &+= 1

        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.isCurrentAuthGeneration(generation) {
                    self.pendingOrganizationSubscriptionIDs.remove(organizationID)
                    self.interactionTasks[taskKey] = nil
                }
            }

            do {
                if shouldSubscribe {
                    try await repository.subscribeOrganization(id: organizationID, actionCapture: actionCapture)
                } else {
                    try await repository.unsubscribeOrganization(id: organizationID)
                }

                guard isCurrentAuthGeneration(generation),
                      let currentIndex = organizations.firstIndex(where: { $0.id == organizationID }) else { return }
                if organizations[currentIndex].isSubscribed == previousSubscriptionState {
                    organizations[currentIndex].isSubscribed = shouldSubscribe
                    organizations[currentIndex].subscriberCount = max(
                        0,
                        organizations[currentIndex].subscriberCount + (shouldSubscribe ? 1 : -1)
                    )
                    contentVersion &+= 1
                }
                let currentOrganization = organizations[currentIndex]
                ActivityLogRecorder.recordOrganization(currentOrganization, actionType: shouldSubscribe ? .followedOrganization : .unfollowedOrganization)
                if shouldSubscribe {
                    analyticsService.track(actionEvent, actionCapture: actionCapture)
                } else {
                    analyticsService.track(.organizationUnfollow(organization: currentOrganization))
                }
                interactionError = nil
            } catch let appError as AppError {
                guard isCurrentAuthGeneration(generation) else { return }
                rollbackSubscription(
                    organizationID: organizationID,
                    optimisticState: shouldSubscribe,
                    optimisticCount: optimisticSubscriberCount,
                    previousState: previousSubscriptionState,
                    previousCount: previousSubscriberCount,
                    requestFeedRevision: requestFeedRevision
                )
                interactionError = appError
            } catch {
                guard isCurrentAuthGeneration(generation) else { return }
                rollbackSubscription(
                    organizationID: organizationID,
                    optimisticState: shouldSubscribe,
                    optimisticCount: optimisticSubscriberCount,
                    previousState: previousSubscriptionState,
                    previousCount: previousSubscriberCount,
                    requestFeedRevision: requestFeedRevision
                )
                self.interactionError = .unknown
            }
        }
        interactionTasks[taskKey] = task
    }

    func toggleBookmark(for organizationID: String) {
        guard let index = organizations.firstIndex(where: { $0.id == organizationID }) else { return }
        guard !pendingOrganizationBookmarkIDs.contains(organizationID) else { return }
        let shouldBookmark = !organizations[index].isBookmarked
        let organization = organizations[index]
        let actionEvent = AppAnalyticsEvent.organizationBookmark(organization: organization)
        let actionCapture = shouldBookmark ? analyticsService.actionCapture(for: actionEvent) : nil
        let previousBookmarkState = organizations[index].isBookmarked
        let generation = authGeneration
        let requestFeedRevision = feedRevision
        let taskKey = "bookmark:\(organizationID)"

        pendingOrganizationBookmarkIDs.insert(organizationID)
        interactionError = nil
        organizations[index].isBookmarked = shouldBookmark
        contentVersion &+= 1

        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.isCurrentAuthGeneration(generation) {
                    self.pendingOrganizationBookmarkIDs.remove(organizationID)
                    self.interactionTasks[taskKey] = nil
                }
            }

            do {
                if shouldBookmark {
                    try await repository.bookmarkOrganization(id: organizationID, actionCapture: actionCapture)
                } else {
                    try await repository.unbookmarkOrganization(id: organizationID)
                }

                guard isCurrentAuthGeneration(generation),
                      let currentIndex = organizations.firstIndex(where: { $0.id == organizationID }) else { return }
                if organizations[currentIndex].isBookmarked == previousBookmarkState {
                    organizations[currentIndex].isBookmarked = shouldBookmark
                    contentVersion &+= 1
                }
                let currentOrganization = organizations[currentIndex]
                ActivityLogRecorder.recordOrganization(currentOrganization, actionType: shouldBookmark ? .savedOrganization : .unsavedOrganization)
                if shouldBookmark {
                    analyticsService.track(actionEvent, actionCapture: actionCapture)
                }
                interactionError = nil
            } catch let appError as AppError {
                guard isCurrentAuthGeneration(generation) else { return }
                rollbackBookmark(
                    organizationID: organizationID,
                    optimisticState: shouldBookmark,
                    previousState: previousBookmarkState,
                    requestFeedRevision: requestFeedRevision
                )
                interactionError = appError
            } catch {
                guard isCurrentAuthGeneration(generation) else { return }
                rollbackBookmark(
                    organizationID: organizationID,
                    optimisticState: shouldBookmark,
                    previousState: previousBookmarkState,
                    requestFeedRevision: requestFeedRevision
                )
                self.interactionError = .unknown
            }
        }
        interactionTasks[taskKey] = task
    }

    func dismissInteractionError() {
        interactionError = nil
    }

    func organization(for organizationID: String) -> Organization? {
        return organizations.first(where: { $0.id == organizationID })
    }

    func applyContentVisibility(_ policy: ContentVisibilityPolicy) {
        visibilityPolicy = policy
        organizations = policy.visibleOrganizations(organizations)
        organizationCommentsByID = organizationCommentsByID.mapValues(policy.visibleComments)
        contentVersion &+= 1
    }

    func trackViewWhileVisible(for organization: Organization) async {
        await analyticsService.observeVisibleView {
            self.trackViewIfNeeded(for: organization)
        }
    }

    func trackViewIfNeeded(for organization: Organization, sourceScreen: String = "organization_detail") {
        guard let collectionScopeID = analyticsService.collectionScopeID else { return }
        let trackingKey = AnalyticsTrackingKey.daily(
            contentID: organization.id,
            collectionScopeID: collectionScopeID
        )
        guard !trackedOrganizationViewIDs.contains(trackingKey) else { return }
        trackedOrganizationViewIDs.insert(trackingKey)
        analyticsService.track(.organizationView(
            organizationID: organization.id,
            organizationName: organization.name,
            federalState: organization.federalState,
            regionScope: organization.regionScope,
            sourceScreen: sourceScreen
        ))
    }

    func resolveOrganization(id organizationID: String, force: Bool = false) async -> Organization? {
        let trimmedID = organizationID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return nil }
        let generation = authGeneration

        if !force, let organization = organization(for: trimmedID) {
            return organization
        }

        do {
            let organization = try await RefreshRequest.run { [repository] in try await repository.fetchOrganization(id: trimmedID) }
            guard isCurrentAuthGeneration(generation) else { return nil }
            guard visibilityPolicy.visibleOrganizations([organization]).isEmpty == false else {
                return nil
            }
            organizations.upsertOrganizationByID(organization)
            contentVersion &+= 1
            error = nil
            return organization
        } catch let appError as AppError {
            guard isCurrentAuthGeneration(generation) else { return nil }
            error = appError
            return nil
        } catch {
            guard isCurrentAuthGeneration(generation) else { return nil }
            self.error = .unknown
            return nil
        }
    }

    func comments(for organizationID: String) -> [Comment] {
        organizationCommentsByID[organizationID] ?? []
    }

    func loadComments(for organizationID: String, forceRefresh: Bool = false) async {
        let generation = authGeneration
        if forceRefresh || !listenerBag.contains("organizationComments:\(organizationID)") {
            commentLoadStates[organizationID] = .loading
        }
        startListeningComments(for: organizationID)
        guard forceRefresh || !(repository is OrganizationRealtimeRepository) else { return }
        do {
            let comments = try await RefreshRequest.run { [repository] in try await repository.fetchOrganizationComments(organizationID: organizationID) }
            guard isCurrentAuthGeneration(generation) else { return }
            organizationCommentsByID[organizationID] = visibilityPolicy.visibleComments(
                comments.deduplicatedCommentsByID()
            )
            commentLoadStates[organizationID] = .loaded
            error = nil
        } catch let appError as AppError {
            guard isCurrentAuthGeneration(generation) else { return }
            commentLoadStates[organizationID] = .failed(appError)
            error = appError
        } catch {
            guard isCurrentAuthGeneration(generation) else { return }
            let mapped = CommentErrorMapper.map(error)
            commentLoadStates[organizationID] = .failed(mapped)
            self.error = mapped
        }
    }

    func stopListeningComments(for organizationID: String) {
        listenerBag.remove("organizationComments:\(organizationID)")
    }

    private func startListeningComments(for organizationID: String) {
        let key = "organizationComments:\(organizationID)"
        let generation = authGeneration
        guard !listenerBag.contains(key),
              let realtimeRepository = repository as? OrganizationRealtimeRepository else { return }

        listenerBag.set(realtimeRepository.listenOrganizationComments(organizationID: organizationID) { [weak self] comments in
            guard let self, self.isCurrentAuthGeneration(generation) else { return }
            self.organizationCommentsByID[organizationID] = self.visibilityPolicy.visibleComments(
                comments.deduplicatedCommentsByID()
            )
            self.commentLoadStates[organizationID] = .loaded
            self.error = nil
        } onError: { [weak self] appError in
            guard let self, self.isCurrentAuthGeneration(generation) else { return }
            self.listenerBag.remove(key)
            self.commentLoadStates[organizationID] = .failed(appError)
            self.error = appError
            #if DEBUG
            print("Realtime listener failed: purpose=organizationComments key=\(key) error=\(appError)")
            #endif
        }, for: key)
    }

    @discardableResult
    func addComment(to organizationID: String, text: String, author: AppUser) async -> CommentMutationResult {
        guard !pendingOrganizationCommentIDs.contains(organizationID) else { return .ignored }
        guard let text = CommentTextPolicy.validated(text) else { return .failure(.validationFailed) }
        let generation = authGeneration
        pendingOrganizationCommentIDs.insert(organizationID)
        defer {
            if isCurrentAuthGeneration(generation) {
                pendingOrganizationCommentIDs.remove(organizationID)
            }
        }

        do {
            let comment = try await repository.addOrganizationComment(organizationID: organizationID, text: text, author: author)
            guard isCurrentAuthGeneration(generation) else { return .ignored }
            organizationCommentsByID[organizationID, default: []].upsertCommentByID(comment)
            error = nil
            return .success
        } catch {
            guard isCurrentAuthGeneration(generation) else { return .ignored }
            let mapped = CommentErrorMapper.map(error)
            self.error = mapped
            return .failure(mapped)
        }
    }

    func updateComment(organizationID: String, commentID: String, text: String) async {
        guard !pendingOrganizationCommentIDs.contains(organizationID) else { return }
        let generation = authGeneration
        pendingOrganizationCommentIDs.insert(organizationID)
        defer {
            if isCurrentAuthGeneration(generation) {
                pendingOrganizationCommentIDs.remove(organizationID)
            }
        }

        do {
            let updated = try await repository.updateOrganizationComment(organizationID: organizationID, commentID: commentID, text: text)
            guard isCurrentAuthGeneration(generation) else { return }
            if let index = organizationCommentsByID[organizationID]?.firstIndex(where: { $0.id == commentID }) {
                organizationCommentsByID[organizationID]?[index] = updated
                organizationCommentsByID[organizationID] = organizationCommentsByID[organizationID]?.deduplicatedCommentsByID()
            }
            error = nil
        } catch let appError as AppError {
            guard isCurrentAuthGeneration(generation) else { return }
            error = appError
        } catch {
            guard isCurrentAuthGeneration(generation) else { return }
            self.error = .unknown
        }
    }

    @discardableResult
    func deleteComment(organizationID: String, commentID: String) async -> CommentMutationResult {
        guard !pendingOrganizationCommentIDs.contains(organizationID) else { return .ignored }
        let generation = authGeneration
        pendingOrganizationCommentIDs.insert(organizationID)
        defer {
            if isCurrentAuthGeneration(generation) {
                pendingOrganizationCommentIDs.remove(organizationID)
            }
        }

        do {
            try await repository.deleteOrganizationComment(organizationID: organizationID, commentID: commentID)
            guard isCurrentAuthGeneration(generation) else { return .ignored }
            organizationCommentsByID[organizationID]?.removeAll { $0.id == commentID }
            error = nil
            return .success
        } catch {
            guard isCurrentAuthGeneration(generation) else { return .ignored }
            let mapped = CommentErrorMapper.map(error)
            self.error = mapped
            return .failure(mapped)
        }
    }

    var editorRepository: OrganizationRepository {
        repository
    }

    func createOrganization(
        _ organization: Organization,
        imageData: Data?,
        user: AppUser?
    ) async throws {
        guard PermissionService.canCreateOrganization(user: user) else {
            validationErrorMessage = AppStrings.Organizations.actionPermissionError
            throw AppError.permissionDenied
        }

        try await saveOrganization(organization, imageData: imageData, isEditing: false)
    }

    func loadOrganizationRequests(for user: AppUser?) async {
        let generation = authGeneration
        guard let user else {
            organizationRequests = []
            listenerBag.removeAll(matchingPrefix: "submittedOrganizationRequests:")
            return
        }

        if startListeningOrganizationRequests(for: user.id) {
            return
        }

        await fetchOrganizationRequestsOnce(userID: user.id, generation: generation)
    }

    private func fetchOrganizationRequestsOnce(userID: String, generation: UInt) async {
        do {
            let requests = try await RefreshRequest.run { [repository] in try await repository.fetchOrganizationRequests(submittedByUserID: userID) }
            guard isCurrentAuthGeneration(generation) else { return }
            organizationRequests = requests.deduplicatedOrganizationsByID()
            error = nil
        } catch let appError as AppError {
            guard isCurrentAuthGeneration(generation) else { return }
            error = appError
        } catch {
            guard isCurrentAuthGeneration(generation) else { return }
            self.error = .unknown
        }
    }

    private func startListeningOrganizationRequests(for userID: String) -> Bool {
        let key = "submittedOrganizationRequests:\(userID)"
        let generation = authGeneration
        listenerBag.removeAll(except: key, matchingPrefix: "submittedOrganizationRequests:")
        guard let realtimeRepository = repository as? OrganizationRealtimeRepository else { return false }
        guard !listenerBag.contains(key) else { return true }

        listenerBag.set(realtimeRepository.listenSubmittedOrganizationRequests(userID: userID) { [weak self] requests in
            guard let self, self.isCurrentAuthGeneration(generation) else { return }
            self.organizationRequests = requests.deduplicatedOrganizationsByID()
            self.error = nil
        } onError: { [weak self] appError in
            guard let self, self.isCurrentAuthGeneration(generation) else { return }
            self.listenerBag.remove(key)
            self.error = appError
            Task { await self.fetchOrganizationRequestsOnce(userID: userID, generation: generation) }
            #if DEBUG
            print("Realtime listener failed: purpose=submittedOrganizationRequests key=\(key) error=\(appError)")
            #endif
        }, for: key)
        return true
    }

    func updateOrganization(
        _ organization: Organization,
        imageData: Data?,
        user: AppUser?
    ) async throws {
        guard PermissionService.canEditOrganizationInfo(organization, user: user) else {
            validationErrorMessage = AppStrings.Organizations.actionPermissionError
            throw AppError.permissionDenied
        }

        try await saveOrganization(organization, imageData: imageData, isEditing: true)
    }

    func deleteOrganization(id: String, user: AppUser?) async throws {
        guard id != Organization.systemOrganizationID else {
            validationErrorMessage = AppStrings.Organizations.actionPermissionError
            throw AppError.permissionDenied
        }
        guard PermissionService.canDeleteOrganization(user: user) else {
            validationErrorMessage = AppStrings.Organizations.actionPermissionError
            throw AppError.permissionDenied
        }
        guard !pendingOrganizationDeleteIDs.contains(id) else { return }
        let generation = authGeneration

        pendingOrganizationDeleteIDs.insert(id)
        defer {
            if isCurrentAuthGeneration(generation) {
                pendingOrganizationDeleteIDs.remove(id)
            }
        }

        do {
            try await repository.deleteOrganization(id: id)
            guard isCurrentAuthGeneration(generation) else { return }
            error = nil
            validationErrorMessage = nil
            removeDeletedOrganization(id: id)
            organizationRequests.removeAll { $0.id == id }
            AppContentChangeBus.postOrganizationsChanged(organizationID: id)
        } catch let appError as AppError {
            guard isCurrentAuthGeneration(generation) else { throw appError }
            error = appError
            throw appError
        } catch {
            guard isCurrentAuthGeneration(generation) else { throw error }
            self.error = .unknown
            throw AppError.unknown
        }
    }

    func removeDeletedOrganization(id: String) {
        guard id != Organization.systemOrganizationID else { return }
        organizations.removeAll { $0.id == id }
        contentVersion &+= 1
    }

    private func startLoad(force: Bool) async {
        let generation = authGeneration
        guard force || !hasLoaded else { return }
        if force {
            nextPageTask?.cancel()
            nextPageTask = nil
            isLoadingNextPage = false
        }

        if let loadTask {
            await loadTask.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoad(generation: generation)
        }
        loadTask = task
        await task.value
        guard isCurrentAuthGeneration(generation) else { return }
        self.loadTask = nil
    }

    func loadNextPageIfNeeded(currentItemID: String? = nil) async {
        let generation = authGeneration
        guard hasLoaded, hasMorePages, !isLoading, !isLoadingNextPage else { return }
        if let currentItemID, organizations.suffix(5).contains(where: { $0.id == currentItemID }) == false {
            return
        }

        if let nextPageTask {
            await nextPageTask.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoadNextPage(generation: generation)
        }
        nextPageTask = task
        await task.value
        guard isCurrentAuthGeneration(generation) else { return }
        nextPageTask = nil
    }

    func loadRemainingPagesForSearch() async {
        await loadIfNeeded()
        while hasMorePages, !Task.isCancelled {
            let previousCount = organizations.count
            await loadNextPageIfNeeded()
            guard organizations.count > previousCount, error == nil else { return }
        }
    }

    private func performLoad(generation: UInt) async {
        guard isCurrentAuthGeneration(generation) else { return }
        isLoading = true
        defer {
            if isCurrentAuthGeneration(generation) {
                isLoading = false
            }
        }

        do {
            let page = try await RefreshRequest.run { [repository, publicFeedPageSize] in try await repository.fetchOrganizationsPage(limit: publicFeedPageSize, after: nil) }
            guard !Task.isCancelled, isCurrentAuthGeneration(generation) else { return }
            feedRevision &+= 1
            organizations = visibilityPolicy.visibleOrganizations(page.items).deduplicatedOrganizationsByID()
            nextPageCursor = page.nextCursor
            hasMorePages = page.hasMore
            contentVersion &+= 1
            error = nil
            hasLoaded = true
            lastLoadedAt = Date()
        } catch is CancellationError {
        } catch let appError as AppError {
            guard !Task.isCancelled, isCurrentAuthGeneration(generation) else { return }
            error = appError
        } catch {
            guard !Task.isCancelled, isCurrentAuthGeneration(generation) else { return }
            self.error = .unknown
        }
    }

    private func performLoadNextPage(generation: UInt) async {
        guard isCurrentAuthGeneration(generation) else { return }
        guard let nextPageCursor else { return }
        isLoadingNextPage = true
        defer {
            if isCurrentAuthGeneration(generation) {
                isLoadingNextPage = false
            }
        }

        do {
            let page = try await RefreshRequest.run { [repository, publicFeedPageSize, nextPageCursor] in try await repository.fetchOrganizationsPage(limit: publicFeedPageSize, after: nextPageCursor) }
            guard !Task.isCancelled, isCurrentAuthGeneration(generation) else { return }
            appendUniqueOrganizations(page.items)
            self.nextPageCursor = page.nextCursor
            hasMorePages = page.hasMore
            contentVersion &+= 1
            error = nil
            lastLoadedAt = Date()
        } catch is CancellationError {
        } catch let appError as AppError {
            guard !Task.isCancelled, isCurrentAuthGeneration(generation) else { return }
            error = appError
        } catch {
            guard !Task.isCancelled, isCurrentAuthGeneration(generation) else { return }
            self.error = .unknown
        }
    }

    private func appendUniqueOrganizations(_ newOrganizations: [Organization]) {
        var seenIDs = Set(organizations.map(\.id))
        organizations.append(contentsOf: visibilityPolicy.visibleOrganizations(newOrganizations).filter {
            seenIDs.insert($0.id).inserted
        })
    }

    private func saveOrganization(_ organization: Organization, imageData: Data?, isEditing: Bool) async throws {
        guard !isSavingOrganization else { return }
        let generation = authGeneration

        isSavingOrganization = true
        validationErrorMessage = nil
        defer {
            if isCurrentAuthGeneration(generation) {
                isSavingOrganization = false
                isUploadingOrganizationImage = false
            }
        }

        do {
            if isEditing {
                try await ensureOrganizationRequestIsStillEditable(organization, generation: generation)
                guard isCurrentAuthGeneration(generation) else { return }
            }

            if !isEditing {
                try await repository.createOrganization(organization)
                guard isCurrentAuthGeneration(generation) else { return }
                var organizationToInsert = organization

                if let imageData {
                    do {
                        isUploadingOrganizationImage = true
                        let uploadedURL = try await repository.uploadOrganizationImage(data: imageData, organizationID: organization.id)
                        guard isCurrentAuthGeneration(generation) else { return }
                        isUploadingOrganizationImage = false
                        organizationToInsert = organization.settingOrganizationImageURL(uploadedURL.absoluteString)
                        try await repository.updateOrganization(organizationToInsert)
                        guard isCurrentAuthGeneration(generation) else { return }
                    } catch {
                        guard isCurrentAuthGeneration(generation) else { throw error }
                        isUploadingOrganizationImage = false
                        do {
                            try await repository.deleteOrganization(id: organization.id)
                        } catch {}
                        guard isCurrentAuthGeneration(generation) else { throw error }
                        throw error
                    }
                }

                organizationRequests.upsertOrganizationByID(organizationToInsert)
                contentVersion &+= 1
                error = nil
                AppContentChangeBus.postOrganizationsChanged(organizationID: organizationToInsert.id)
                return
            }

            let resolvedImageURL: String?
            if let imageData {
                isUploadingOrganizationImage = true
                let uploadedURL = try await repository.uploadOrganizationImage(data: imageData, organizationID: organization.id)
                guard isCurrentAuthGeneration(generation) else { return }
                resolvedImageURL = uploadedURL.absoluteString
                isUploadingOrganizationImage = false
            } else {
                resolvedImageURL = organization.imageURL
            }

            let organizationToSave = Organization(
                id: organization.id,
                localizations: organization.localizations,
                name: organization.name,
                description: organization.description,
                shortDescription: organization.shortDescription,
                fullDescription: organization.fullDescription,
                regionScope: organization.regionScope,
                federalState: organization.federalState,
                city: organization.city,
                imageURL: resolvedImageURL,
                logoURL: resolvedImageURL ?? organization.logoURL,
                coverURL: organization.coverURL,
                contactEmail: organization.contactEmail,
                email: organization.email,
                phone: organization.phone,
                website: organization.website,
                address: organization.address,
                latitude: organization.latitude,
                longitude: organization.longitude,
                organizationType: organization.organizationType,
                directoryProfile: organization.directoryProfile,
                foundedYear: organization.foundedYear,
                foundedMonth: organization.foundedMonth,
                languages: organization.languages,
                socialLinks: organization.socialLinks,
                telegramURL: organization.telegramURL,
                donationURL: organization.donationURL,
                facebookURL: organization.facebookURL,
                instagramURL: organization.instagramURL,
                whatsappURL: organization.whatsappURL,
                youtubeURL: organization.youtubeURL,
                linkedinURL: organization.linkedinURL,
                missionStatement: organization.missionStatement,
                contactPerson: organization.contactPerson,
                subscriberCount: organization.subscriberCount,
                eventsHeldCount: organization.eventsHeldCount,
                volunteersCount: organization.volunteersCount,
                helpedPeopleCount: organization.helpedPeopleCount,
                ownerId: organization.ownerId,
                adminIds: organization.adminIds,
                moderatorIds: organization.moderatorIds,
                isSystemManaged: organization.isSystemManaged,
                sourceType: organization.sourceType,
                pinnedNewsId: organization.pinnedNewsId,
                pinnedEventId: organization.pinnedEventId,
                submittedByUserId: organization.submittedByUserId,
                submittedByDisplayName: organization.submittedByDisplayName,
                submittedAt: organization.submittedAt,
                reviewMessage: organization.reviewMessage,
                reviewedByUserId: organization.reviewedByUserId,
                reviewedAt: organization.reviewedAt,
                rejectionReason: organization.rejectionReason,
                createdAt: organization.createdAt,
                updatedAt: organization.updatedAt,
                moderationStatus: organization.moderationStatus,
                likeCount: organization.likeCount,
                likeState: organization.likeState,
                isSubscribed: organization.isSubscribed,
                isBookmarked: organization.isBookmarked
            )

            if isEditing {
                try await repository.updateOrganization(organizationToSave)
                guard isCurrentAuthGeneration(generation) else { return }
                replaceOrganization(organizationToSave)
                replaceOrganizationRequest(organizationToSave)
            } else {
                try await repository.createOrganization(organizationToSave)
                guard isCurrentAuthGeneration(generation) else { return }
                if organizationToSave.moderationStatus == .approved {
                    organizations.insert(organizationToSave, at: 0)
                } else {
                    organizationRequests.upsertOrganizationByID(organizationToSave)
                }
            }

            contentVersion &+= 1
            error = nil
            AppContentChangeBus.postOrganizationsChanged(organizationID: organizationToSave.id)
        } catch let appError as AppError {
            guard isCurrentAuthGeneration(generation) else { throw appError }
            error = appError
            throw appError
        } catch {
            guard isCurrentAuthGeneration(generation) else { throw error }
            self.error = .unknown
            validationErrorMessage = error.localizedDescription
            throw AppError.unknown
        }
    }

    private func ensureOrganizationRequestIsStillEditable(_ organization: Organization, generation: UInt) async throws {
        guard organization.submittedByUserId != nil else { return }
        guard [.pendingReview, .needsRevision, .rejected].contains(organization.moderationStatus) else { return }

        do {
            let latest = try await RefreshRequest.run { [repository] in try await repository.fetchOrganization(id: organization.id) }
            guard isCurrentAuthGeneration(generation) else { throw CancellationError() }
            guard latest.submittedByUserId == organization.submittedByUserId,
                  [.pendingReview, .needsRevision, .rejected].contains(latest.moderationStatus) else {
                validationErrorMessage = AppStrings.Organizations.requestAlreadyReviewed
                throw AppError.validationFailed
            }
        } catch AppError.notFound {
            guard isCurrentAuthGeneration(generation) else { throw AppError.notFound }
            validationErrorMessage = AppStrings.Organizations.requestAlreadyReviewed
            throw AppError.validationFailed
        }
    }

    private func replaceOrganization(_ organization: Organization) {
        guard let index = organizations.firstIndex(where: { $0.id == organization.id }) else { return }
        organizations[index] = organization
    }

    private func replaceOrganizationRequest(_ organization: Organization) {
        guard let index = organizationRequests.firstIndex(where: { $0.id == organization.id }) else { return }
        if organization.moderationStatus == .approved {
            organizationRequests.remove(at: index)
        } else {
            organizationRequests[index] = organization
        }
    }

    func approveOrganizationRequest(id: String, reviewerID: String) async throws {
        let generation = authGeneration
        try await repository.approveOrganizationRequest(id: id, reviewerID: reviewerID)
        guard isCurrentAuthGeneration(generation) else { return }
        organizationRequests.removeAll { $0.id == id }
        AppContentChangeBus.postOrganizationsChanged(organizationID: id)
    }

    func requestOrganizationRevision(id: String, message: String, reviewerID: String) async throws {
        let generation = authGeneration
        try await repository.requestOrganizationRevision(id: id, message: message, reviewerID: reviewerID)
        guard isCurrentAuthGeneration(generation) else { return }
        AppContentChangeBus.postOrganizationsChanged(organizationID: id)
    }

    func rejectOrganizationRequest(id: String, reason: String, reviewerID: String) async throws {
        let generation = authGeneration
        try await repository.rejectOrganizationRequest(id: id, reason: reason, reviewerID: reviewerID)
        guard isCurrentAuthGeneration(generation) else { return }
        organizationRequests.removeAll { $0.id == id }
        AppContentChangeBus.postOrganizationsChanged(organizationID: id)
    }

    private func rollbackLike(
        organizationID: String,
        optimisticState: LikeState,
        optimisticCount: Int,
        previousState: LikeState,
        previousCount: Int,
        requestFeedRevision: UInt
    ) {
        guard feedRevision == requestFeedRevision,
              let currentIndex = organizations.firstIndex(where: { $0.id == organizationID }),
              organizations[currentIndex].likeState == optimisticState,
              organizations[currentIndex].likeCount == optimisticCount else { return }
        organizations[currentIndex].likeState = previousState
        organizations[currentIndex].likeCount = max(0, previousCount)
        contentVersion &+= 1
    }

    private func rollbackSubscription(
        organizationID: String,
        optimisticState: Bool,
        optimisticCount: Int,
        previousState: Bool,
        previousCount: Int,
        requestFeedRevision: UInt
    ) {
        guard feedRevision == requestFeedRevision,
              let currentIndex = organizations.firstIndex(where: { $0.id == organizationID }),
              organizations[currentIndex].isSubscribed == optimisticState,
              organizations[currentIndex].subscriberCount == optimisticCount else { return }
        organizations[currentIndex].isSubscribed = previousState
        organizations[currentIndex].subscriberCount = max(0, previousCount)
        contentVersion &+= 1
    }

    private func rollbackBookmark(
        organizationID: String,
        optimisticState: Bool,
        previousState: Bool,
        requestFeedRevision: UInt
    ) {
        guard feedRevision == requestFeedRevision,
              let currentIndex = organizations.firstIndex(where: { $0.id == organizationID }),
              organizations[currentIndex].isBookmarked == optimisticState else { return }
        organizations[currentIndex].isBookmarked = previousState
        contentVersion &+= 1
    }

    private func isCurrentAuthGeneration(_ generation: UInt) -> Bool {
        generation == authGeneration
    }

}

private extension Organization {
    func settingOrganizationImageURL(_ imageURL: String?) -> Organization {
        Organization(
            id: id,
            localizations: localizations,
            name: name,
            description: description,
            shortDescription: shortDescription,
            fullDescription: fullDescription,
            regionScope: regionScope,
            federalState: federalState,
            city: city,
            imageURL: imageURL,
            logoURL: imageURL ?? logoURL,
            coverURL: coverURL,
            contactEmail: contactEmail,
            email: email,
            phone: phone,
            website: website,
            address: address,
            latitude: latitude,
            longitude: longitude,
            organizationType: organizationType,
            directoryProfile: directoryProfile,
            foundedYear: foundedYear,
            foundedMonth: foundedMonth,
            languages: languages,
            socialLinks: socialLinks,
            telegramURL: telegramURL,
            donationURL: donationURL,
            facebookURL: facebookURL,
            instagramURL: instagramURL,
            whatsappURL: whatsappURL,
            youtubeURL: youtubeURL,
            linkedinURL: linkedinURL,
            missionStatement: missionStatement,
            contactPerson: contactPerson,
            subscriberCount: subscriberCount,
            eventsHeldCount: eventsHeldCount,
            volunteersCount: volunteersCount,
            helpedPeopleCount: helpedPeopleCount,
            ownerId: ownerId,
            adminIds: adminIds,
            moderatorIds: moderatorIds,
            isSystemManaged: isSystemManaged,
            sourceType: sourceType,
            pinnedNewsId: pinnedNewsId,
            pinnedEventId: pinnedEventId,
            submittedByUserId: submittedByUserId,
            submittedByDisplayName: submittedByDisplayName,
            submittedAt: submittedAt,
            reviewMessage: reviewMessage,
            reviewedByUserId: reviewedByUserId,
            reviewedAt: reviewedAt,
            rejectionReason: rejectionReason,
            createdAt: createdAt,
            updatedAt: updatedAt,
            moderationStatus: moderationStatus,
            likeCount: likeCount,
            likeState: likeState,
            isSubscribed: isSubscribed,
            isBookmarked: isBookmarked
        )
    }
}
