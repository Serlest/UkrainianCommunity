import Combine
import Foundation

struct EventRegistrationPresentationError: Equatable {
    let eventID: String
    let reason: EventRegistrationMutationError
}

@MainActor
final class EventsViewModel: ObservableObject {
    @Published var events: [Event]
    @Published private(set) var isLoading: Bool
    @Published private(set) var error: AppError?
    @Published private(set) var isLoadingNextPage = false
    @Published private(set) var hasMorePages = false
    @Published private(set) var contentVersion = 0
    @Published private(set) var pendingEventLikeIDs = Set<String>()
    @Published private(set) var pendingEventRegistrationIDs = Set<String>()
    @Published private(set) var pendingEventBookmarkIDs = Set<String>()
    @Published private(set) var pendingEventViewIDs = Set<String>()
    @Published private(set) var pendingEventCommentIDs = Set<String>()
    @Published private(set) var registrationError: EventRegistrationPresentationError?
    private let repository: EventRepository
    private let registrationMutator: EventRegistrationMutating
    private let analyticsService: AnalyticsTracking
    private let listenerBag = RealtimeListenerBag()
    private var loadTask: Task<Void, Never>?
    private var nextPageTask: Task<Void, Never>?
    private var hasLoaded = false
    private var lastLoadedAt: Date?
    private var nextPageCursor: EventPageCursor?
    private var trackedEventViewIDs = Set<String>()
    private var visibilityPolicy = ContentVisibilityPolicy()
    private var registrationTasks: [String: Task<Void, Never>] = [:]
    private var registrationOperationIDs: [String: UUID] = [:]
    private var interactionTasks: [String: Task<Void, Never>] = [:]
    private var sessionGeneration = 0
    private var feedRevision: UInt = 0

    init(
        repository: EventRepository,
        notificationPreferencesRepository: NotificationPreferencesRepository? = nil,
        localEventReminderService: LocalEventReminderServiceProtocol? = nil,
        analyticsService: AnalyticsTracking = NoopAnalyticsService(),
        registrationMutator: EventRegistrationMutating? = nil
    ) {
        self.repository = repository
        self.analyticsService = analyticsService
        if let registrationMutator {
            self.registrationMutator = registrationMutator
        } else {
            self.registrationMutator = repository
        }
        events = []
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

    func resetForAuthChange() {
        sessionGeneration &+= 1
        feedRevision &+= 1
        registrationTasks.values.forEach { $0.cancel() }
        interactionTasks.values.forEach { $0.cancel() }
        registrationTasks = [:]
        registrationOperationIDs = [:]
        interactionTasks = [:]
        loadTask?.cancel()
        nextPageTask?.cancel()
        loadTask = nil
        nextPageTask = nil
        events = []
        isLoading = false
        isLoadingNextPage = false
        hasMorePages = false
        error = nil
        contentVersion &+= 1
        pendingEventLikeIDs = []
        pendingEventRegistrationIDs = []
        pendingEventBookmarkIDs = []
        pendingEventViewIDs = []
        pendingEventCommentIDs = []
        registrationError = nil
        trackedEventViewIDs = []
        listenerBag.removeAll()
        hasLoaded = false
        lastLoadedAt = nil
        nextPageCursor = nil
    }

    var bookmarkedEvents: [Event] {
        events.filter(\.isBookmarked)
    }

    func applyContentVisibility(_ policy: ContentVisibilityPolicy) {
        visibilityPolicy = policy
        feedRevision &+= 1
        events = policy.visibleEvents(events)
        contentVersion &+= 1
    }

    func toggleLike(for eventID: String) {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        guard !pendingEventLikeIDs.contains(eventID) else { return }
        let shouldLike = events[index].likeState == .notLiked
        let desiredState: LikeState = shouldLike ? .liked : .notLiked
        let generation = sessionGeneration
        let taskKey = "like:\(eventID)"

        pendingEventLikeIDs.insert(eventID)
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
                if events[currentIndex].likeState != desiredState {
                    events[currentIndex].likeState = desiredState
                    events[currentIndex].likeCount = max(
                        0,
                        events[currentIndex].likeCount + (shouldLike ? 1 : -1)
                    )
                }
                contentVersion &+= 1
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

    func toggleRegistration(for eventID: String) {
        guard let event = events.first(where: { $0.id == eventID }) else { return }
        guard !pendingEventRegistrationIDs.contains(eventID) else { return }
        let shouldRegister = event.registrationState != .registered
        let operationID = UUID()
        let generation = sessionGeneration

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
                generation: generation
            )
        }
        registrationTasks[eventID] = task
    }

    func dismissRegistrationError(for eventID: String) {
        guard registrationError?.eventID == eventID else { return }
        registrationError = nil
    }

    private func performRegistrationMutation(
        eventID: String,
        shouldRegister: Bool,
        operationID: UUID,
        generation: Int
    ) async {
        defer { finishRegistrationMutation(eventID, operationID: operationID, generation: generation) }

        do {
            let result = if shouldRegister {
                try await registrationMutator.registerForEvent(id: eventID)
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
            analyticsService.track(
                result.registrationState == .registered
                ? .eventRegister(event: eventBeforeMutation)
                : .eventCancelRegistration(event: eventBeforeMutation)
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
        let previousBookmarkState = events[index].isBookmarked
        let generation = sessionGeneration
        let requestFeedRevision = feedRevision
        let taskKey = "bookmark:\(eventID)"

        pendingEventBookmarkIDs.insert(eventID)
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
                    try await repository.bookmarkEvent(id: eventID)
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
                    analyticsService.track(.eventBookmark(event: event))
                }
                error = nil
            } catch let appError as AppError {
                guard isCurrentSession(generation) else { return }
                rollbackBookmark(
                    eventID: eventID,
                    optimisticState: shouldBookmark,
                    previousState: previousBookmarkState,
                    requestFeedRevision: requestFeedRevision
                )
                error = appError
            } catch {
                guard isCurrentSession(generation) else { return }
                rollbackBookmark(
                    eventID: eventID,
                    optimisticState: shouldBookmark,
                    previousState: previousBookmarkState,
                    requestFeedRevision: requestFeedRevision
                )
                self.error = .unknown
            }
        }
        interactionTasks[taskKey] = task
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

    func trackViewIfNeeded(for event: Event, sourceScreen: String = "event_detail") {
        guard !trackedEventViewIDs.contains(event.id) else { return }
        trackedEventViewIDs.insert(event.id)
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
        startListeningComments(for: eventID)
        guard forceRefresh || !(repository is EventRealtimeRepository) else { return }
        guard events.contains(where: { $0.id == eventID }) else { return }

        do {
            let comments = try await repository.fetchEventComments(eventID: eventID)
            guard isCurrentSession(generation),
                  let currentIndex = events.firstIndex(where: { $0.id == eventID }) else { return }
            let visibleComments = visibilityPolicy.visibleComments(comments.deduplicatedCommentsByID())
            events[currentIndex].comments = visibleComments
            events[currentIndex].commentCount = visibleComments.filter { !$0.isDeleted }.count
            error = nil
        } catch let appError as AppError {
            guard isCurrentSession(generation) else { return }
            error = appError
        } catch {
            guard isCurrentSession(generation) else { return }
            self.error = .unknown
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
            self.error = nil
        } onError: { [weak self] appError in
            guard let self, self.isCurrentSession(generation) else { return }
            self.listenerBag.remove(key)
            self.error = appError
            #if DEBUG
            print("Realtime listener failed: purpose=eventComments key=\(key) error=\(appError)")
            #endif
        }, for: key)
    }

    func addComment(to eventID: String, text: String, author: AppUser) async {
        guard events.contains(where: { $0.id == eventID }) else { return }
        guard !pendingEventCommentIDs.contains(eventID) else { return }
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
                  let currentIndex = events.firstIndex(where: { $0.id == eventID }) else { return }
            events[currentIndex].comments.upsertCommentByID(comment)
            events[currentIndex].commentCount = events[currentIndex].comments.filter { !$0.isDeleted }.count
            error = nil
        } catch let appError as AppError {
            guard isCurrentSession(generation) else { return }
            error = appError
        } catch {
            guard isCurrentSession(generation) else { return }
            self.error = .unknown
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

    func deleteComment(eventID: String, commentID: String) async {
        guard events.contains(where: { $0.id == eventID }) else { return }
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
            try await repository.deleteEventComment(eventID: eventID, commentID: commentID)
            guard isCurrentSession(generation),
                  let currentIndex = events.firstIndex(where: { $0.id == eventID }) else { return }
            events[currentIndex].comments.removeAll { $0.id == commentID }
            events[currentIndex].commentCount = events[currentIndex].comments.filter { !$0.isDeleted }.count
            error = nil
        } catch let appError as AppError {
            guard isCurrentSession(generation) else { return }
            error = appError
        } catch {
            guard isCurrentSession(generation) else { return }
            self.error = .unknown
        }
    }

    func event(for eventID: String) -> Event? {
        events.first(where: { $0.id == eventID })
    }

    func loadEventIfNeeded(eventID: String, force: Bool = false) async {
        guard force || event(for: eventID) == nil else { return }
        let generation = sessionGeneration

        do {
            let event = try await repository.fetchEvent(id: eventID)
            guard isCurrentSession(generation) else { return }
            cacheEvent(event)
            error = nil
        } catch let appError as AppError {
            guard isCurrentSession(generation) else { return }
            error = appError
        } catch {
            guard isCurrentSession(generation) else { return }
            self.error = .unknown
        }
    }

    func cacheEvent(_ event: Event) {
        feedRevision &+= 1
        guard let visibleEvent = visibilityPolicy.visibleEvents([event]).first else {
            events.removeAll { $0.id == event.id }
            return
        }
        if let index = events.firstIndex(where: { $0.id == visibleEvent.id }) {
            events[index] = visibleEvent
        } else {
            events.append(visibleEvent)
        }
        contentVersion &+= 1
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

    private func startLoad(force: Bool) async {
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
            await self.performLoad(generation: generation)
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
            await self.performLoadNextPage(generation: generation)
        }
        nextPageTask = task
        await task.value
        guard isCurrentSession(generation) else { return }
        nextPageTask = nil
    }

    private func performLoad(generation: Int) async {
        guard isCurrentSession(generation) else { return }
        isLoading = true
        defer {
            if isCurrentSession(generation) {
                isLoading = false
            }
        }

        do {
            let page = try await repository.fetchEventsPage(limit: publicFeedPageSize, after: nil)
            guard !Task.isCancelled, isCurrentSession(generation) else { return }
            feedRevision &+= 1
            events = visibilityPolicy.visibleEvents(page.items)
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

    private func performLoadNextPage(generation: Int) async {
        guard isCurrentSession(generation) else { return }
        guard let nextPageCursor else { return }
        isLoadingNextPage = true
        defer {
            if isCurrentSession(generation) {
                isLoadingNextPage = false
            }
        }

        do {
            let page = try await repository.fetchEventsPage(limit: publicFeedPageSize, after: nextPageCursor)
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
        let existingIDs = Set(events.map(\.id))
        events.append(contentsOf: visibilityPolicy.visibleEvents(newEvents).filter { !existingIDs.contains($0.id) })
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

    private func isCurrentSession(_ generation: Int) -> Bool {
        sessionGeneration == generation
    }
}
