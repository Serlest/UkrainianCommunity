import Combine
import Foundation

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
    private let repository: EventRepository
    private let analyticsService: AnalyticsTracking
    private let listenerBag = RealtimeListenerBag()
    private var loadTask: Task<Void, Never>?
    private var nextPageTask: Task<Void, Never>?
    private var hasLoaded = false
    private var lastLoadedAt: Date?
    private var nextPageCursor: EventPageCursor?
    private var trackedEventViewIDs = Set<String>()

    init(
        repository: EventRepository,
        notificationPreferencesRepository: NotificationPreferencesRepository? = nil,
        localEventReminderService: LocalEventReminderServiceProtocol? = nil,
        analyticsService: AnalyticsTracking = NoopAnalyticsService()
    ) {
        self.repository = repository
        self.analyticsService = analyticsService
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
        trackedEventViewIDs = []
        listenerBag.removeAll()
        hasLoaded = false
        lastLoadedAt = nil
        nextPageCursor = nil
    }

    var bookmarkedEvents: [Event] {
        events.filter(\.isBookmarked)
    }

    func toggleLike(for eventID: String) {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        guard !pendingEventLikeIDs.contains(eventID) else { return }
        let shouldLike = events[index].likeState == .notLiked

        Task {
            pendingEventLikeIDs.insert(eventID)
            defer { pendingEventLikeIDs.remove(eventID) }

            do {
                if shouldLike {
                    try await repository.likeEvent(id: eventID)
                } else {
                    try await repository.unlikeEvent(id: eventID)
                }

                events[index].likeState = shouldLike ? .liked : .notLiked
                events[index].likeCount += shouldLike ? 1 : -1
                contentVersion &+= 1
                error = nil
            } catch let appError as AppError {
                error = appError
            } catch {
                self.error = .unknown
            }
        }
    }

    func toggleRegistration(for eventID: String) {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        guard !pendingEventRegistrationIDs.contains(eventID) else { return }
        let shouldRegister = events[index].registrationState != .registered
        let event = events[index]

        Task {
            pendingEventRegistrationIDs.insert(eventID)
            defer { pendingEventRegistrationIDs.remove(eventID) }

            do {
                if shouldRegister {
                    try await repository.registerForEvent(id: eventID)
                } else {
                    try await repository.cancelEventRegistration(id: eventID)
                }

                let updatedRegisteredCount = shouldRegister
                    ? events[index].registeredCount + 1
                    : max(0, events[index].registeredCount - 1)

                events[index] = Event(
                    id: events[index].id,
                    title: events[index].title,
                    summary: events[index].summary,
                    details: events[index].details,
                    regionScope: events[index].regionScope,
                    federalState: events[index].federalState,
                    source: events[index].source,
                    authorId: events[index].authorId,
                    authorName: events[index].authorName,
                    city: events[index].city,
                    venue: events[index].venue,
                    address: events[index].address,
                    locationNote: events[index].locationNote,
                    latitude: events[index].latitude,
                    longitude: events[index].longitude,
                    organizerName: events[index].organizerName,
                    organizerURL: events[index].organizerURL,
                    contactPhone: events[index].contactPhone,
                    contactEmail: events[index].contactEmail,
                    contactURL: events[index].contactURL,
                    imageURL: events[index].imageURL,
                    startDate: events[index].startDate,
                    endDate: events[index].endDate,
                    createdAt: events[index].createdAt,
                    updatedAt: events[index].updatedAt,
                    requiresRegistration: events[index].requiresRegistration,
                    price: events[index].price,
                    capacity: events[index].capacity,
                    registeredCount: updatedRegisteredCount,
                    comments: events[index].comments,
                    moderationStatus: events[index].moderationStatus,
                    registrationState: shouldRegister ? .registered : .notRegistered,
                    likeCount: events[index].likeCount,
                    likeState: events[index].likeState,
                    viewCount: events[index].viewCount,
                    category: events[index].category,
                    tags: events[index].tags,
                    isAllDay: events[index].isAllDay,
                    isBookmarked: events[index].isBookmarked,
                    commentCount: events[index].commentCount
                )
                contentVersion &+= 1
                ActivityLogRecorder.recordEvent(event, actionType: shouldRegister ? .registeredForEvent : .canceledEventRegistration)
                analyticsService.track(shouldRegister ? .eventRegister(event: event) : .eventCancelRegistration(event: event))
                error = nil
            } catch let appError as AppError {
                error = appError
            } catch {
                self.error = .unknown
            }
        }
    }

    func toggleBookmark(for eventID: String) {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        guard !pendingEventBookmarkIDs.contains(eventID) else { return }
        let shouldBookmark = !events[index].isBookmarked
        let event = events[index]

        Task {
            pendingEventBookmarkIDs.insert(eventID)
            events[index].isBookmarked = shouldBookmark
            contentVersion &+= 1
            defer { pendingEventBookmarkIDs.remove(eventID) }

            do {
                if shouldBookmark {
                    try await repository.bookmarkEvent(id: eventID)
                } else {
                    try await repository.unbookmarkEvent(id: eventID)
                }
                ActivityLogRecorder.recordEvent(event, actionType: shouldBookmark ? .savedEvent : .unsavedEvent)
                if shouldBookmark {
                    analyticsService.track(.eventBookmark(event: event))
                }
                error = nil
            } catch let appError as AppError {
                events[index].isBookmarked.toggle()
                contentVersion &+= 1
                error = appError
            } catch {
                events[index].isBookmarked.toggle()
                contentVersion &+= 1
                self.error = .unknown
            }
        }
    }

    func recordView(for eventID: String) {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        guard !pendingEventViewIDs.contains(eventID) else { return }

        Task {
            pendingEventViewIDs.insert(eventID)
            defer { pendingEventViewIDs.remove(eventID) }

            do {
                if try await repository.recordEventView(id: eventID) {
                    events[index].viewCount += 1
                }
                error = nil
            } catch let appError as AppError {
                error = appError
            } catch {
                self.error = .unknown
            }
        }
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
        startListeningComments(for: eventID)
        guard forceRefresh || !(repository is EventRealtimeRepository) else { return }
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }

        do {
            let comments = try await repository.fetchEventComments(eventID: eventID)
            let visibleComments = comments.deduplicatedCommentsByID()
            events[index].comments = visibleComments
            events[index].commentCount = visibleComments.filter { !$0.isDeleted }.count
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    func stopListeningComments(for eventID: String) {
        listenerBag.remove("eventComments:\(eventID)")
    }

    private func startListeningComments(for eventID: String) {
        let key = "eventComments:\(eventID)"
        guard !listenerBag.contains(key),
              let realtimeRepository = repository as? EventRealtimeRepository else { return }

        listenerBag.set(realtimeRepository.listenEventComments(eventID: eventID) { [weak self] comments in
            guard let self, let index = self.events.firstIndex(where: { $0.id == eventID }) else { return }
            let visibleComments = comments.deduplicatedCommentsByID()
            self.events[index].comments = visibleComments
            self.events[index].commentCount = visibleComments.filter { !$0.isDeleted }.count
            self.error = nil
        } onError: { [weak self] appError in
            self?.listenerBag.remove(key)
            self?.error = appError
            #if DEBUG
            print("Realtime listener failed: purpose=eventComments key=\(key) error=\(appError)")
            #endif
        }, for: key)
    }

    func addComment(to eventID: String, text: String, author: AppUser) async {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        guard !pendingEventCommentIDs.contains(eventID) else { return }
        pendingEventCommentIDs.insert(eventID)
        defer { pendingEventCommentIDs.remove(eventID) }

        do {
            let comment = try await repository.addEventComment(eventID: eventID, text: text, author: author)
            events[index].comments.upsertCommentByID(comment)
            events[index].commentCount = events[index].comments.filter { !$0.isDeleted }.count
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    func updateComment(eventID: String, commentID: String, text: String) async {
        guard let eventIndex = events.firstIndex(where: { $0.id == eventID }),
              let commentIndex = events[eventIndex].comments.firstIndex(where: { $0.id == commentID }) else {
            return
        }
        let pendingID = "\(eventID)_\(commentID)"
        guard !pendingEventCommentIDs.contains(pendingID) else { return }
        pendingEventCommentIDs.insert(pendingID)
        defer { pendingEventCommentIDs.remove(pendingID) }

        do {
            let comment = try await repository.updateEventComment(eventID: eventID, commentID: commentID, text: text)
            events[eventIndex].comments[commentIndex] = comment
            events[eventIndex].comments = events[eventIndex].comments.deduplicatedCommentsByID()
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    func deleteComment(eventID: String, commentID: String) async {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        let pendingID = "\(eventID)_\(commentID)"
        guard !pendingEventCommentIDs.contains(pendingID) else { return }
        pendingEventCommentIDs.insert(pendingID)
        defer { pendingEventCommentIDs.remove(pendingID) }

        do {
            try await repository.deleteEventComment(eventID: eventID, commentID: commentID)
            events[index].comments.removeAll { $0.id == commentID }
            events[index].commentCount = max(0, events[index].commentCount - 1)
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    func event(for eventID: String) -> Event? {
        events.first(where: { $0.id == eventID })
    }

    func loadEventIfNeeded(eventID: String, force: Bool = false) async {
        guard force || event(for: eventID) == nil else { return }

        do {
            let event = try await repository.fetchEvent(id: eventID)
            cacheEvent(event)
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    func cacheEvent(_ event: Event) {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            events[index] = event
        } else {
            events.append(event)
        }
        contentVersion &+= 1
    }

    var editorRepository: EventRepository {
        repository
    }

    func deleteEvent(id: String) async throws {
        let organizationID = event(for: id)?.source.organizationId

        do {
            try await repository.deleteEvent(id: id)
            events.removeAll { $0.id == id }
            contentVersion &+= 1
            error = nil
            AppContentChangeBus.postEventsChanged(organizationID: organizationID)
        } catch let appError as AppError {
            error = appError
            throw appError
        } catch {
            self.error = .unknown
            throw AppError.unknown
        }
    }

    func removeDeletedEvent(id: String) {
        events.removeAll { $0.id == id }
        contentVersion &+= 1
    }

    private func startLoad(force: Bool) async {
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
            await self.performLoad()
        }
        loadTask = task
        await task.value
        self.loadTask = nil
    }

    func loadNextPageIfNeeded(currentItemID: String? = nil) async {
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
            await self.performLoadNextPage()
        }
        nextPageTask = task
        await task.value
        nextPageTask = nil
    }

    private func performLoad() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let page = try await repository.fetchEventsPage(limit: publicFeedPageSize, after: nil)
            guard !Task.isCancelled else { return }
            events = page.items
            nextPageCursor = page.nextCursor
            hasMorePages = page.hasMore
            contentVersion &+= 1
            error = nil
            hasLoaded = true
            lastLoadedAt = Date()
        } catch is CancellationError {
        } catch let appError as AppError {
            guard !Task.isCancelled else { return }
            error = appError
        } catch {
            guard !Task.isCancelled else { return }
            self.error = .unknown
        }
    }

    private func performLoadNextPage() async {
        guard let nextPageCursor else { return }
        isLoadingNextPage = true
        defer { isLoadingNextPage = false }

        do {
            let page = try await repository.fetchEventsPage(limit: publicFeedPageSize, after: nextPageCursor)
            guard !Task.isCancelled else { return }
            appendUniqueEvents(page.items)
            self.nextPageCursor = page.nextCursor
            hasMorePages = page.hasMore
            contentVersion &+= 1
            error = nil
            lastLoadedAt = Date()
        } catch is CancellationError {
        } catch let appError as AppError {
            guard !Task.isCancelled else { return }
            error = appError
        } catch {
            guard !Task.isCancelled else { return }
            self.error = .unknown
        }
    }

    private func appendUniqueEvents(_ newEvents: [Event]) {
        let existingIDs = Set(events.map(\.id))
        events.append(contentsOf: newEvents.filter { !existingIDs.contains($0.id) })
    }
}
