import Combine
import FirebaseAuth
import Foundation

private nonisolated let recentPastEventPreviewSize = 3

struct EventRegistrationPresentationError: Equatable {
    let eventID: String
    let reason: EventRegistrationMutationError
}

@MainActor
final class EventsViewModel: ObservableObject {
    @Published var events: [Event]
    @Published private(set) var isLoading: Bool
    @Published private(set) var error: AppError?
    @Published private(set) var interactionError: AppError?
    @Published private(set) var isLoadingNextPage = false
    @Published private(set) var hasMorePages = false
    @Published private(set) var contentVersion = 0
    @Published private(set) var pendingEventLikeIDs = Set<String>()
    @Published private(set) var pendingEventRegistrationIDs = Set<String>()
    @Published private(set) var pendingEventBookmarkIDs = Set<String>()
    @Published private(set) var pendingEventViewIDs = Set<String>()
    @Published private(set) var commentLoadStates: [String: CommentLoadState] = [:]
    @Published private(set) var pendingEventCommentIDs = Set<String>()
    @Published private(set) var registrationError: EventRegistrationPresentationError?
    private let repository: EventRepository
    private let commentReadDeadline: RefreshRequest.Deadline
    private let registrationMutator: EventRegistrationMutating
    private let analyticsService: AnalyticsTracking
    private let notificationPreferencesRepository: NotificationPreferencesRepository?
    private let localEventReminderService: LocalEventReminderServiceProtocol?
    private let listenerBag = RealtimeListenerBag()
    private var loadTask: Task<Void, Never>?
    private var nextPageTask: Task<Void, Never>?
    private var hasLoaded = false
    private var lastLoadedAt: Date?
    private var nextPageCursor: EventPageCursor?
    private var activeFederalState: AustrianFederalState?
    private var trackedEventViewIDs = Set<String>()
    private(set) var visibilityPolicy = ContentVisibilityPolicy()
    private var registrationTasks: [String: Task<Void, Never>] = [:]
    private var registrationOperationIDs: [String: UUID] = [:]
    private var interactionTasks: [String: Task<Void, Never>] = [:]
    private var sessionGeneration = 0
    private var feedRevision: UInt = 0
    private var recommendationCandidateCache: [String: [Event]] = [:]
    private var recommendationCandidateTasks: [String: Task<[Event], Never>] = [:]

    init(
        repository: EventRepository,
        commentReadDeadline: @escaping RefreshRequest.Deadline = RefreshRequest.continuousDeadline,
        notificationPreferencesRepository: NotificationPreferencesRepository? = nil,
        localEventReminderService: LocalEventReminderServiceProtocol? = nil,
        analyticsService: AnalyticsTracking = NoopAnalyticsService(),
        registrationMutator: EventRegistrationMutating? = nil
    ) {
        self.repository = repository
        self.commentReadDeadline = commentReadDeadline
        self.analyticsService = analyticsService
        self.notificationPreferencesRepository = notificationPreferencesRepository
        self.localEventReminderService = localEventReminderService
        if let registrationMutator {
            self.registrationMutator = registrationMutator
        } else {
            self.registrationMutator = repository
        }
        events = []
        isLoading = false
    }

    func loadIfNeeded() async {
        await loadIfNeeded(federalState: activeFederalState, initialLimit: publicFeedPageSize)
    }

    func loadIfNeeded(
        federalState: AustrianFederalState?,
        initialLimit: Int = publicFeedPageSize
    ) async {
        prepareFeedIfRegionChanged(to: federalState)
        guard !hasLoaded else { return }
        await startLoad(force: false, limit: initialLimit)
    }

    func ensureLoaded(
        minimumCount: Int,
        federalState: AustrianFederalState?
    ) async {
        await loadIfNeeded(federalState: federalState, initialLimit: minimumCount)
        while events.count < minimumCount, hasMorePages, !Task.isCancelled {
            let previousCount = events.count
            await loadNextPage(pageSize: max(1, minimumCount - events.count))
            guard events.count > previousCount, error == nil else { return }
        }
    }

    func reload() {
        Task {
            await refresh()
        }
    }

    func refresh() async {
        await startLoad(force: true, limit: publicFeedPageSize)
    }

    func refresh(
        federalState: AustrianFederalState?,
        limit: Int
    ) async {
        prepareFeedIfRegionChanged(to: federalState)
        await startLoad(force: true, limit: limit)
    }

    func refreshIfStale(maxAge: TimeInterval = defaultRefreshStaleInterval) async {
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

    func refreshIfStale(
        federalState: AustrianFederalState?,
        limit: Int,
        maxAge: TimeInterval = defaultRefreshStaleInterval
    ) async {
        prepareFeedIfRegionChanged(to: federalState)
        guard hasLoaded else {
            await loadIfNeeded(federalState: federalState, initialLimit: limit)
            return
        }
        guard let lastLoadedAt, Date().timeIntervalSince(lastLoadedAt) <= maxAge else {
            await refresh(federalState: federalState, limit: limit)
            return
        }
    }

    func resetForAuthChange() {
        sessionGeneration &+= 1
        feedRevision &+= 1
        registrationTasks.values.forEach { $0.cancel() }
        interactionTasks.values.forEach { $0.cancel() }
        recommendationCandidateTasks.values.forEach { $0.cancel() }
        registrationTasks = [:]
        registrationOperationIDs = [:]
        interactionTasks = [:]
        recommendationCandidateTasks = [:]
        recommendationCandidateCache = [:]
        loadTask?.cancel()
        nextPageTask?.cancel()
        loadTask = nil
        nextPageTask = nil
        events = []
        isLoading = false
        isLoadingNextPage = false
        hasMorePages = false
        error = nil
        interactionError = nil
        contentVersion &+= 1
        pendingEventLikeIDs = []
        pendingEventRegistrationIDs = []
        pendingEventBookmarkIDs = []
        pendingEventViewIDs = []
        pendingEventCommentIDs = []
        commentLoadStates = [:]
        registrationError = nil
        trackedEventViewIDs = []
        listenerBag.removeAll()
        hasLoaded = false
        lastLoadedAt = nil
        nextPageCursor = nil
        activeFederalState = nil
    }

    var bookmarkedEvents: [Event] {
        events.filter(\.isBookmarked)
    }

    func applyContentVisibility(_ policy: ContentVisibilityPolicy) {
        visibilityPolicy = policy
        feedRevision &+= 1
        events = policy.visibleEvents(events)
        recommendationCandidateCache.removeAll()
        contentVersion &+= 1
    }

    func toggleLike(for eventID: String) {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        guard !pendingEventLikeIDs.contains(eventID) else { return }
        let shouldLike = events[index].likeState == .notLiked
        let previousState = events[index].likeState
        let previousCount = events[index].likeCount
        let desiredState: LikeState = shouldLike ? .liked : .notLiked
        let desiredCount = max(0, previousCount + (shouldLike ? 1 : -1))
        let generation = sessionGeneration
        let requestFeedRevision = feedRevision
        let taskKey = "like:\(eventID)"

        pendingEventLikeIDs.insert(eventID)
        interactionError = nil
        events[index].likeState = desiredState
        events[index].likeCount = desiredCount
        contentVersion &+= 1
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.isCurrentSession(generation) {
                    self.pendingEventLikeIDs.remove(eventID)
                    self.interactionTasks[taskKey] = nil
                }
            }

            do {
                if shouldLike {
                    try await repository.likeEvent(id: eventID)
                } else {
                    try await repository.unlikeEvent(id: eventID)
                }

                guard isCurrentSession(generation),
                      let currentIndex = events.firstIndex(where: { $0.id == eventID }) else { return }
                if events[currentIndex].likeState == previousState {
                    events[currentIndex].likeState = desiredState
                    events[currentIndex].likeCount = max(
                        0,
                        events[currentIndex].likeCount + (shouldLike ? 1 : -1)
                    )
                }
                contentVersion &+= 1
                interactionError = nil
            } catch let appError as AppError {
                guard isCurrentSession(generation) else { return }
                rollbackLike(
                    eventID: eventID,
                    optimisticState: desiredState,
                    optimisticCount: desiredCount,
                    previousState: previousState,
                    previousCount: previousCount,
                    requestFeedRevision: requestFeedRevision
                )
                interactionError = appError
            } catch {
                guard isCurrentSession(generation) else { return }
                rollbackLike(
                    eventID: eventID,
                    optimisticState: desiredState,
                    optimisticCount: desiredCount,
                    previousState: previousState,
                    previousCount: previousCount,
                    requestFeedRevision: requestFeedRevision
                )
                self.interactionError = .unknown
            }
        }
        interactionTasks[taskKey] = task
    }

    func toggleRegistration(for eventID: String) {
        guard let event = events.first(where: { $0.id == eventID }) else { return }
        guard !pendingEventRegistrationIDs.contains(eventID) else { return }
        let shouldRegister = event.registrationState != .registered
        let operationID = UUID()
        let generation = sessionGeneration
        let actionEvent = AppAnalyticsEvent.eventRegister(event: event)
        let actionCapture = shouldRegister ? analyticsService.actionCapture(for: actionEvent) : nil

        pendingEventRegistrationIDs.insert(eventID)
        registrationOperationIDs[eventID] = operationID
        if registrationError?.eventID == eventID {
            registrationError = nil
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performRegistrationMutation(
                eventID: eventID,
                shouldRegister: shouldRegister,
                operationID: operationID,
                generation: generation,
                actionCapture: actionCapture
            )
        }
        registrationTasks[eventID] = task
    }

    func dismissRegistrationError(for eventID: String) {
        guard registrationError?.eventID == eventID else { return }
        registrationError = nil
    }

    func waitForRegistrationMutation(for eventID: String) async {
        await registrationTasks[eventID]?.value
    }

    private func performRegistrationMutation(
        eventID: String,
        shouldRegister: Bool,
        operationID: UUID,
        generation: Int,
        actionCapture: AnalyticsActionCapture?
    ) async {
        defer { finishRegistrationMutation(eventID, operationID: operationID, generation: generation) }

        do {
            let result = if shouldRegister {
                try await registrationMutator.registerForEvent(id: eventID, actionCapture: actionCapture)
            } else {
                try await registrationMutator.cancelEventRegistration(id: eventID)
            }
            guard result.eventID == eventID, result.registeredCount >= 0 else {
                throw EventRegistrationMutationError.unavailable
            }
            guard isCurrentRegistrationMutation(eventID, operationID: operationID, generation: generation),
                  !Task.isCancelled,
                  let index = events.firstIndex(where: { $0.id == eventID }) else { return }

            let eventBeforeMutation = events[index]
            events[index] = eventBeforeMutation.applyingRegistrationMutation(result)
            contentVersion &+= 1
            registrationError = nil

            guard result.didChange else { return }
            ActivityLogRecorder.recordEvent(
                eventBeforeMutation,
                actionType: result.registrationState == .registered
                ? .registeredForEvent
                : .canceledEventRegistration
            )
            if result.registrationState == .registered {
                analyticsService.track(
                    .eventRegister(event: eventBeforeMutation),
                    actionCapture: actionCapture
                )
            } else {
                analyticsService.track(.eventCancelRegistration(event: eventBeforeMutation))
            }
            await updateLocalReminder(
                for: eventBeforeMutation,
                isRegistered: result.registrationState == .registered
            )
        } catch is CancellationError {
        } catch let mutationError as EventRegistrationMutationError {
            guard isCurrentRegistrationMutation(eventID, operationID: operationID, generation: generation) else { return }
            registrationError = EventRegistrationPresentationError(eventID: eventID, reason: mutationError)
        } catch let appError as AppError {
            guard isCurrentRegistrationMutation(eventID, operationID: operationID, generation: generation) else { return }
            registrationError = EventRegistrationPresentationError(
                eventID: eventID,
                reason: Self.registrationMutationError(from: appError)
            )
        } catch {
            guard isCurrentRegistrationMutation(eventID, operationID: operationID, generation: generation) else { return }
            registrationError = EventRegistrationPresentationError(eventID: eventID, reason: .unavailable)
        }
    }

    private func updateLocalReminder(for event: Event, isRegistered: Bool) async {
        guard let userID = AuthService.shared.currentUser?.uid,
              let localEventReminderService else { return }

        guard isRegistered else {
            localEventReminderService.cancelEventReminder(eventID: event.id, userID: userID)
            return
        }

        guard let notificationPreferencesRepository else { return }
        do {
            let preferences = try await notificationPreferencesRepository.fetchNotificationPreferences(userID: userID)
            guard preferences.notificationsEnabled, preferences.eventRemindersEnabled else { return }
            try await localEventReminderService.scheduleEventReminder(
                event: event,
                userID: userID,
                leadMinutes: preferences.reminderLeadMinutes
            )
        } catch {
            #if DEBUG
            print("[Notifications] Failed to schedule event reminder: \(error)")
            #endif
        }
    }

    private func finishRegistrationMutation(_ eventID: String, operationID: UUID, generation: Int) {
        guard isCurrentRegistrationMutation(eventID, operationID: operationID, generation: generation) else { return }
        pendingEventRegistrationIDs.remove(eventID)
        registrationOperationIDs[eventID] = nil
        registrationTasks[eventID] = nil
    }

    private func isCurrentRegistrationMutation(_ eventID: String, operationID: UUID, generation: Int) -> Bool {
        sessionGeneration == generation && registrationOperationIDs[eventID] == operationID
    }

    private static func registrationMutationError(from appError: AppError) -> EventRegistrationMutationError {
        switch appError {
        case .network:
            .network
        case .permissionDenied:
            .permissionDenied
        case .notFound:
            .notFound
        case .validationFailed,
             .unknown:
            .unavailable
        }
    }

    func toggleBookmark(for eventID: String) {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        guard !pendingEventBookmarkIDs.contains(eventID) else { return }
        let shouldBookmark = !events[index].isBookmarked
        let event = events[index]
        let actionEvent = AppAnalyticsEvent.eventBookmark(event: event)
        let actionCapture = shouldBookmark ? analyticsService.actionCapture(for: actionEvent) : nil
        let previousBookmarkState = events[index].isBookmarked
        let generation = sessionGeneration
        let requestFeedRevision = feedRevision
        let taskKey = "bookmark:\(eventID)"

        pendingEventBookmarkIDs.insert(eventID)
        interactionError = nil
        events[index].isBookmarked = shouldBookmark
        contentVersion &+= 1

        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.isCurrentSession(generation) {
                    self.pendingEventBookmarkIDs.remove(eventID)
                    self.interactionTasks[taskKey] = nil
                }
            }

            do {
                if shouldBookmark {
                    try await repository.bookmarkEvent(id: eventID, actionCapture: actionCapture)
                } else {
                    try await repository.unbookmarkEvent(id: eventID)
                }
                guard isCurrentSession(generation),
                      let currentIndex = events.firstIndex(where: { $0.id == eventID }) else { return }
                if events[currentIndex].isBookmarked == previousBookmarkState {
                    events[currentIndex].isBookmarked = shouldBookmark
                    contentVersion &+= 1
                }
                ActivityLogRecorder.recordEvent(event, actionType: shouldBookmark ? .savedEvent : .unsavedEvent)
                if shouldBookmark {
                    analyticsService.track(actionEvent, actionCapture: actionCapture)
                }
                interactionError = nil
            } catch let appError as AppError {
                guard isCurrentSession(generation) else { return }
                rollbackBookmark(
                    eventID: eventID,
                    optimisticState: shouldBookmark,
                    previousState: previousBookmarkState,
                    requestFeedRevision: requestFeedRevision
                )
                interactionError = appError
            } catch {
                guard isCurrentSession(generation) else { return }
                rollbackBookmark(
                    eventID: eventID,
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

    func recordView(for eventID: String) {
        guard let event = events.first(where: { $0.id == eventID }) else { return }
        guard !pendingEventViewIDs.contains(eventID) else { return }
        let baselineViewCount = event.viewCount
        let generation = sessionGeneration
        let taskKey = "view:\(eventID)"

        pendingEventViewIDs.insert(eventID)
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.isCurrentSession(generation) {
                    self.pendingEventViewIDs.remove(eventID)
                    self.interactionTasks[taskKey] = nil
                }
            }

            do {
                if try await repository.recordEventView(id: eventID) {
                    guard isCurrentSession(generation),
                          let currentIndex = events.firstIndex(where: { $0.id == eventID }) else { return }
                    events[currentIndex].viewCount = max(
                        events[currentIndex].viewCount,
                        baselineViewCount + 1
                    )
                } else {
                    guard isCurrentSession(generation) else { return }
                }
                error = nil
            } catch let appError as AppError {
                guard isCurrentSession(generation) else { return }
                error = appError
            } catch {
                guard isCurrentSession(generation) else { return }
                self.error = .unknown
            }
        }
        interactionTasks[taskKey] = task
    }

    func trackViewWhileVisible(for event: Event, sourceScreen: String = "event_detail") async {
        await analyticsService.observeVisibleView {
            self.trackViewIfNeeded(for: event, sourceScreen: sourceScreen)
        }
    }

    func trackViewIfNeeded(for event: Event, sourceScreen: String = "event_detail") {
        guard let collectionScopeID = analyticsService.collectionScopeID else { return }
        let trackingKey = AnalyticsTrackingKey.daily(
            contentID: event.id,
            collectionScopeID: collectionScopeID
        )
        guard !trackedEventViewIDs.contains(trackingKey) else { return }
        trackedEventViewIDs.insert(trackingKey)
        analyticsService.track(.eventView(
            contentID: event.id,
            contentTitle: event.title,
            category: event.category,
            federalState: event.federalState,
            regionScope: event.regionScope,
            organizationID: event.source.organizationId,
            sourceScreen: sourceScreen
        ))
    }

    func loadComments(for eventID: String, forceRefresh: Bool = false) async {
        let generation = sessionGeneration
        if forceRefresh || !listenerBag.contains("eventComments:\(eventID)") {
            commentLoadStates[eventID] = .loading
        }
        startListeningComments(for: eventID)
        guard forceRefresh || !(repository is EventRealtimeRepository) else { return }
        guard events.contains(where: { $0.id == eventID }) else { return }

        do {
            let comments = try await RefreshRequest.run(deadline: commentReadDeadline) { [repository] in try await repository.fetchEventComments(eventID: eventID) }
            guard isCurrentSession(generation),
                  let currentIndex = events.firstIndex(where: { $0.id == eventID }) else { return }
            let visibleComments = visibilityPolicy.visibleComments(comments.deduplicatedCommentsByID())
            events[currentIndex].comments = visibleComments
            events[currentIndex].commentCount = visibleComments.filter { !$0.isDeleted }.count
            commentLoadStates[eventID] = .loaded
            error = nil
        } catch let appError as AppError {
            guard isCurrentSession(generation) else { return }
            commentLoadStates[eventID] = .failed(appError)
            error = appError
        } catch {
            guard isCurrentSession(generation) else { return }
            let mapped = CommentErrorMapper.map(error)
            commentLoadStates[eventID] = .failed(mapped)
            self.error = mapped
        }
    }

    func stopListeningComments(for eventID: String) {
        listenerBag.remove("eventComments:\(eventID)")
    }

    private func startListeningComments(for eventID: String) {
        let key = "eventComments:\(eventID)"
        let generation = sessionGeneration
        guard !listenerBag.contains(key),
              let realtimeRepository = repository as? EventRealtimeRepository else { return }

        listenerBag.set(realtimeRepository.listenEventComments(eventID: eventID) { [weak self] comments in
            guard let self,
                  self.isCurrentSession(generation),
                  let index = self.events.firstIndex(where: { $0.id == eventID }) else { return }
            let visibleComments = self.visibilityPolicy.visibleComments(comments.deduplicatedCommentsByID())
            self.events[index].comments = visibleComments
            self.events[index].commentCount = visibleComments.filter { !$0.isDeleted }.count
            self.commentLoadStates[eventID] = .loaded
            self.error = nil
        } onError: { [weak self] appError in
            guard let self, self.isCurrentSession(generation) else { return }
            self.listenerBag.remove(key)
            self.commentLoadStates[eventID] = .failed(appError)
            self.error = appError
            #if DEBUG
            print("Realtime listener failed: purpose=eventComments key=\(key) error=\(appError)")
            #endif
        }, for: key)
    }

    @discardableResult
    func addComment(to eventID: String, text: String, author: AppUser) async -> CommentMutationResult {
        guard events.contains(where: { $0.id == eventID }) else { return .ignored }
        guard !pendingEventCommentIDs.contains(eventID) else { return .ignored }
        guard let text = CommentTextPolicy.validated(text) else { return .failure(.validationFailed) }
        let generation = sessionGeneration
        pendingEventCommentIDs.insert(eventID)
        defer {
            if isCurrentSession(generation) {
                pendingEventCommentIDs.remove(eventID)
            }
        }

        do {
            let comment = try await repository.addEventComment(eventID: eventID, text: text, author: author)
            guard isCurrentSession(generation),
                  let currentIndex = events.firstIndex(where: { $0.id == eventID }) else { return .ignored }
            events[currentIndex].comments.upsertCommentByID(comment)
            events[currentIndex].commentCount = events[currentIndex].comments.filter { !$0.isDeleted }.count
            error = nil
            return .success
        } catch {
            guard isCurrentSession(generation) else { return .ignored }
            let mapped = CommentErrorMapper.map(error)
            self.error = mapped
            return .failure(mapped)
        }
    }

    func updateComment(eventID: String, commentID: String, text: String) async {
        guard let event = events.first(where: { $0.id == eventID }),
              event.comments.contains(where: { $0.id == commentID }) else {
            return
        }
        let pendingID = "\(eventID)_\(commentID)"
        guard !pendingEventCommentIDs.contains(pendingID) else { return }
        let generation = sessionGeneration
        pendingEventCommentIDs.insert(pendingID)
        defer {
            if isCurrentSession(generation) {
                pendingEventCommentIDs.remove(pendingID)
            }
        }

        do {
            let comment = try await repository.updateEventComment(eventID: eventID, commentID: commentID, text: text)
            guard isCurrentSession(generation),
                  let currentEventIndex = events.firstIndex(where: { $0.id == eventID }),
                  let currentCommentIndex = events[currentEventIndex].comments.firstIndex(where: { $0.id == commentID }) else { return }
            events[currentEventIndex].comments[currentCommentIndex] = comment
            events[currentEventIndex].comments = events[currentEventIndex].comments.deduplicatedCommentsByID()
            error = nil
        } catch let appError as AppError {
            guard isCurrentSession(generation) else { return }
            error = appError
        } catch {
            guard isCurrentSession(generation) else { return }
            self.error = .unknown
        }
    }

    @discardableResult
    func deleteComment(eventID: String, commentID: String) async -> CommentMutationResult {
        guard events.contains(where: { $0.id == eventID }) else { return .ignored }
        let pendingID = "\(eventID)_\(commentID)"
        guard !pendingEventCommentIDs.contains(pendingID) else { return .ignored }
        let generation = sessionGeneration
        pendingEventCommentIDs.insert(pendingID)
        defer {
            if isCurrentSession(generation) {
                pendingEventCommentIDs.remove(pendingID)
            }
        }

        do {
            try await repository.deleteEventComment(eventID: eventID, commentID: commentID)
            guard isCurrentSession(generation),
                  let currentIndex = events.firstIndex(where: { $0.id == eventID }) else { return .ignored }
            events[currentIndex].comments.removeAll { $0.id == commentID }
            events[currentIndex].commentCount = events[currentIndex].comments.filter { !$0.isDeleted }.count
            error = nil
            return .success
        } catch {
            guard isCurrentSession(generation) else { return .ignored }
            let mapped = CommentErrorMapper.map(error)
            self.error = mapped
            return .failure(mapped)
        }
    }

    func event(for eventID: String) -> Event? {
        events.first(where: { $0.id == eventID })
    }

    @discardableResult
    func loadEventIfNeeded(eventID: String, force: Bool = false) async -> Bool {
        if case .loaded = await loadEventDetail(eventID: eventID, force: force) {
            return true
        }
        return false
    }

    func loadEventDetail(eventID: String, force: Bool = false) async -> ContentDetailLoadOutcome {
        guard force || event(for: eventID) == nil else { return .loaded }
        let generation = sessionGeneration

        do {
            let event = try await RefreshRequest.run { [repository] in try await repository.fetchEvent(id: eventID) }
            guard !Task.isCancelled, isCurrentSession(generation) else { return .cancelled }
            guard cacheEvent(event) else {
                error = .notFound
                return .failed(.notFound)
            }
            error = nil
            return .loaded
        } catch is CancellationError {
            return .cancelled
        } catch {
            guard !Task.isCancelled, isCurrentSession(generation) else { return .cancelled }
            let mappedError = FirebaseReadErrorMapper.map(error)
            removeCachedEventIfAccessWasLost(eventID: eventID, error: mappedError)
            self.error = mappedError
            return .failed(mappedError)
        }
    }

    @discardableResult
    func cacheEvent(_ event: Event) -> Bool {
        feedRevision &+= 1
        guard let visibleEvent = visibilityPolicy.visibleEvents([event]).first else {
            if events.contains(where: { $0.id == event.id }) {
                events.removeAll { $0.id == event.id }
                contentVersion &+= 1
            }
            return false
        }
        if let index = events.firstIndex(where: { $0.id == visibleEvent.id }) {
            events[index] = visibleEvent
        } else {
            events.append(visibleEvent)
        }
        contentVersion &+= 1
        return true
    }

    var editorRepository: EventRepository {
        repository
    }

    func deleteEvent(id: String) async throws {
        let organizationID = event(for: id)?.source.organizationId
        let generation = sessionGeneration

        do {
            try await repository.deleteEvent(id: id)
            guard isCurrentSession(generation) else { return }
            feedRevision &+= 1
            events.removeAll { $0.id == id }
            contentVersion &+= 1
            error = nil
            AppContentChangeBus.postEventsChanged(organizationID: organizationID)
        } catch let appError as AppError {
            guard isCurrentSession(generation) else { throw appError }
            error = appError
            throw appError
        } catch {
            guard isCurrentSession(generation) else { throw error }
            self.error = .unknown
            throw AppError.unknown
        }
    }

    func removeDeletedEvent(id: String) {
        feedRevision &+= 1
        events.removeAll { $0.id == id }
        contentVersion &+= 1
    }

    private func removeCachedEventIfAccessWasLost(eventID: String, error: AppError) {
        guard error == .notFound || error == .permissionDenied else { return }
        guard events.contains(where: { $0.id == eventID }) else { return }
        feedRevision &+= 1
        events.removeAll { $0.id == eventID }
        contentVersion &+= 1
    }

    private func startLoad(force: Bool, limit: Int) async {
        let generation = sessionGeneration
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
            await self.performLoad(generation: generation, limit: limit)
        }
        loadTask = task
        await task.value
        guard isCurrentSession(generation) else { return }
        self.loadTask = nil
    }

    func loadNextPageIfNeeded(currentItemID: String? = nil) async {
        let generation = sessionGeneration
        guard hasLoaded, hasMorePages, !isLoading, !isLoadingNextPage else { return }
        if let currentItemID, events.suffix(5).contains(where: { $0.id == currentItemID }) == false {
            return
        }

        if let nextPageTask {
            await nextPageTask.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoadNextPage(generation: generation, limit: publicFeedPageSize)
        }
        nextPageTask = task
        await task.value
        guard isCurrentSession(generation) else { return }
        nextPageTask = nil
    }

    func loadNextPage(pageSize: Int = publicFeedPageSize) async {
        let generation = sessionGeneration
        guard hasLoaded, hasMorePages, !isLoading, !isLoadingNextPage else { return }

        if let nextPageTask {
            await nextPageTask.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoadNextPage(generation: generation, limit: pageSize)
        }
        nextPageTask = task
        await task.value
        guard isCurrentSession(generation) else { return }
        nextPageTask = nil
    }

    func loadRemainingPagesForSearch(maximumLoadedCount: Int = 120) async {
        await loadIfNeeded()
        // Keep local search useful without turning a query into a full export.
        while hasMorePages, events.count < maximumLoadedCount, !Task.isCancelled {
            let previousCount = events.count
            await loadNextPageIfNeeded()
            guard events.count > previousCount, error == nil else { return }
        }
    }

    func recommendationCandidates(for source: Event, limit: Int = 12) async -> [Event] {
        let boundedLimit = min(max(1, limit), 12)
        if let cached = recommendationCandidateCache[source.id] {
            return Array(cached.prefix(boundedLimit))
        }
        if let existingTask = recommendationCandidateTasks[source.id] {
            return Array((await existingTask.value).prefix(boundedLimit))
        }

        let generation = sessionGeneration
        let fallback = Array(events
            .filter { $0.id != source.id && $0.category == source.category }
            .prefix(boundedLimit))
        let task = Task { [repository] in
            do {
                return try await repository.fetchEventRecommendationCandidates(
                    for: source,
                    limit: boundedLimit
                )
            } catch {
                return fallback
            }
        }
        recommendationCandidateTasks[source.id] = task
        let fetched = await task.value
        guard !Task.isCancelled, isCurrentSession(generation) else { return [] }
        recommendationCandidateTasks[source.id] = nil
        let visible = visibilityPolicy.visibleEvents(fetched)
            .filter { $0.id != source.id }
            .deduplicatedEventsByID()
        recommendationCandidateCache[source.id] = visible
        return Array(visible.prefix(boundedLimit))
    }

    private func performLoad(generation: Int, limit: Int) async {
        guard isCurrentSession(generation) else { return }
        isLoading = true
        defer {
            if isCurrentSession(generation) {
                isLoading = false
            }
        }

        do {
            let federalState = activeFederalState
            async let pageRequest = RefreshRequest.run { [repository] in
                try await repository.fetchEventsPage(
                    limit: max(1, limit),
                    after: nil,
                    federalState: federalState
                )
            }
            async let recentPastRequest = RefreshRequest.run { [repository] in
                try await repository.fetchRecentPastEvents(
                    limit: recentPastEventPreviewSize,
                    federalState: federalState
                )
            }
            let page = try await pageRequest
            let recentPastEvents = (try? await recentPastRequest) ?? []
            guard !Task.isCancelled, isCurrentSession(generation) else { return }
            feedRevision &+= 1
            events = visibilityPolicy.visibleEvents(page.items + recentPastEvents).deduplicatedEventsByID()
            nextPageCursor = page.nextCursor
            hasMorePages = page.hasMore
            contentVersion &+= 1
            error = nil
            hasLoaded = true
            lastLoadedAt = Date()
        } catch is CancellationError {
        } catch let appError as AppError {
            guard !Task.isCancelled, isCurrentSession(generation) else { return }
            error = appError
        } catch {
            guard !Task.isCancelled, isCurrentSession(generation) else { return }
            self.error = .unknown
        }
    }

    private func performLoadNextPage(generation: Int, limit: Int) async {
        guard isCurrentSession(generation) else { return }
        guard let nextPageCursor else { return }
        isLoadingNextPage = true
        defer {
            if isCurrentSession(generation) {
                isLoadingNextPage = false
            }
        }

        do {
            let federalState = activeFederalState
            let page = try await RefreshRequest.run { [repository, nextPageCursor] in
                try await repository.fetchEventsPage(
                    limit: max(1, limit),
                    after: nextPageCursor,
                    federalState: federalState
                )
            }
            guard !Task.isCancelled, isCurrentSession(generation) else { return }
            feedRevision &+= 1
            appendUniqueEvents(page.items)
            self.nextPageCursor = page.nextCursor
            hasMorePages = page.hasMore
            contentVersion &+= 1
            error = nil
            lastLoadedAt = Date()
        } catch is CancellationError {
        } catch let appError as AppError {
            guard !Task.isCancelled, isCurrentSession(generation) else { return }
            error = appError
        } catch {
            guard !Task.isCancelled, isCurrentSession(generation) else { return }
            self.error = .unknown
        }
    }

    private func appendUniqueEvents(_ newEvents: [Event]) {
        var seenIDs = Set(events.map(\.id))
        events.append(contentsOf: visibilityPolicy.visibleEvents(newEvents).filter {
            seenIDs.insert($0.id).inserted
        })
    }

    private func prepareFeedIfRegionChanged(to federalState: AustrianFederalState?) {
        guard activeFederalState != federalState else { return }
        sessionGeneration &+= 1
        feedRevision &+= 1
        loadTask?.cancel()
        nextPageTask?.cancel()
        loadTask = nil
        nextPageTask = nil
        events = []
        isLoading = false
        isLoadingNextPage = false
        hasMorePages = false
        error = nil
        nextPageCursor = nil
        hasLoaded = false
        lastLoadedAt = nil
        activeFederalState = federalState
        contentVersion &+= 1
    }

    private func rollbackBookmark(
        eventID: String,
        optimisticState: Bool,
        previousState: Bool,
        requestFeedRevision: UInt
    ) {
        guard feedRevision == requestFeedRevision,
              let currentIndex = events.firstIndex(where: { $0.id == eventID }),
              events[currentIndex].isBookmarked == optimisticState else { return }
        events[currentIndex].isBookmarked = previousState
        contentVersion &+= 1
    }

    private func rollbackLike(
        eventID: String,
        optimisticState: LikeState,
        optimisticCount: Int,
        previousState: LikeState,
        previousCount: Int,
        requestFeedRevision: UInt
    ) {
        guard feedRevision == requestFeedRevision,
              let currentIndex = events.firstIndex(where: { $0.id == eventID }),
              events[currentIndex].likeState == optimisticState,
              events[currentIndex].likeCount == optimisticCount else { return }
        events[currentIndex].likeState = previousState
        events[currentIndex].likeCount = max(0, previousCount)
        contentVersion &+= 1
    }

    private func isCurrentSession(_ generation: Int) -> Bool {
        sessionGeneration == generation
    }
}
