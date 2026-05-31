import Combine
import FirebaseAuth
import Foundation

nonisolated private let defaultRefreshStaleInterval: TimeInterval = 300

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var feedItems: [HomeFeedItem]
    @Published private(set) var isLoading: Bool
    @Published private(set) var error: AppError?
    private let feedViewModel: HomeFeedViewModel

    init(
        newsRepository: NewsRepository,
        eventRepository: EventRepository,
        organizationRepository: OrganizationRepository
    ) {
        feedItems = []
        isLoading = false
        feedViewModel = HomeFeedViewModel(
            newsRepository: newsRepository,
            eventRepository: eventRepository,
            organizationRepository: organizationRepository
        )
    }

    func loadIfNeeded() async {
        await feedViewModel.loadIfNeeded()
        feedItems = feedViewModel.items
        isLoading = feedViewModel.isLoading
        error = feedViewModel.error
    }

    func reload() {
        Task {
            await refresh()
        }
    }

    func refresh() async {
        await feedViewModel.refresh()
        feedItems = feedViewModel.items
        isLoading = feedViewModel.isLoading
        error = feedViewModel.error
    }

    func refreshIfStale(maxAge: TimeInterval = defaultRefreshStaleInterval) async {
        await feedViewModel.refreshIfStale(maxAge: maxAge)
        feedItems = feedViewModel.items
        isLoading = feedViewModel.isLoading
        error = feedViewModel.error
    }

    func resetForAuthChange() {
        feedViewModel.resetForAuthChange()
        feedItems = []
        isLoading = false
        error = nil
    }
}

@MainActor
final class HomeFeedViewModel: ObservableObject {
    @Published private(set) var items: [HomeFeedItem]
    @Published private(set) var isLoading: Bool
    @Published private(set) var error: AppError?

    private let newsRepository: NewsRepository
    private let eventRepository: EventRepository
    private let organizationRepository: OrganizationRepository
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false
    private var lastLoadedAt: Date?

    init(
        newsRepository: NewsRepository,
        eventRepository: EventRepository,
        organizationRepository: OrganizationRepository
    ) {
        self.newsRepository = newsRepository
        self.eventRepository = eventRepository
        self.organizationRepository = organizationRepository
        items = []
        isLoading = false
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await startLoad(force: false)
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
        loadTask = nil
        items = []
        isLoading = false
        error = nil
        hasLoaded = false
        lastLoadedAt = nil
    }


    private func startLoad(force: Bool) async {
        guard force || !hasLoaded else { return }

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

    private func performLoad() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let newsLoad = newsRepository.fetchNews()
            async let eventsLoad = eventRepository.fetchEvents()
            async let organizationsLoad = organizationRepository.fetchOrganizations()

            let newsItems = try await newsLoad.map(HomeFeedItem.init(post:))
            let eventItems = try await eventsLoad.map(HomeFeedItem.init(event:))
            let organizationItems = (try await organizationsLoad)
                .map(HomeFeedItem.init(organization:))

            guard !Task.isCancelled else { return }
            items = (newsItems + eventItems + organizationItems)
                .sorted { $0.publishedAt > $1.publishedAt }
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
}

@MainActor
final class NewsViewModel: ObservableObject {
    @Published var posts: [NewsPost]
    @Published private(set) var isLoading: Bool
    @Published private(set) var error: AppError?
    @Published private(set) var contentVersion = 0
    @Published private(set) var pendingNewsLikeIDs = Set<String>()
    @Published private(set) var pendingNewsBookmarkIDs = Set<String>()
    @Published private(set) var pendingNewsViewIDs = Set<String>()
    @Published private(set) var pendingNewsCommentIDs = Set<String>()
    private let repository: NewsRepository
    private let listenerBag = RealtimeListenerBag()
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false
    private var lastLoadedAt: Date?

    init(repository: NewsRepository) {
        self.repository = repository
        posts = []
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
        loadTask = nil
        posts = []
        isLoading = false
        error = nil
        contentVersion &+= 1
        pendingNewsLikeIDs = []
        pendingNewsBookmarkIDs = []
        pendingNewsViewIDs = []
        pendingNewsCommentIDs = []
        listenerBag.removeAll()
        hasLoaded = false
        lastLoadedAt = nil
    }

    var bookmarkedPosts: [NewsPost] {
        posts.filter(\.isBookmarked)
    }

    func toggleLike(for postID: String) {
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }
        guard !pendingNewsLikeIDs.contains(postID) else { return }
        let shouldLike = posts[index].likeState == .notLiked

        Task {
            pendingNewsLikeIDs.insert(postID)
            defer { pendingNewsLikeIDs.remove(postID) }

            do {
                if shouldLike {
                    try await repository.likeNews(id: postID)
                } else {
                    try await repository.unlikeNews(id: postID)
                }

                posts[index].likeState = shouldLike ? .liked : .notLiked
                posts[index].likeCount += shouldLike ? 1 : -1
                error = nil
            } catch let appError as AppError {
                error = appError
            } catch {
                self.error = .unknown
            }
        }
    }

    func recordView(for postID: String) {
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }
        guard !pendingNewsViewIDs.contains(postID) else { return }

        Task {
            pendingNewsViewIDs.insert(postID)
            defer { pendingNewsViewIDs.remove(postID) }

            do {
                if try await repository.recordNewsView(id: postID) {
                    posts[index].viewCount += 1
                }
                error = nil
            } catch let appError as AppError {
                error = appError
            } catch {
                self.error = .unknown
            }
        }
    }

    func toggleBookmark(for postID: String) {
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }
        guard !pendingNewsBookmarkIDs.contains(postID) else { return }
        let shouldBookmark = !posts[index].isBookmarked
        let post = posts[index]

        posts[index].isBookmarked = shouldBookmark

        Task {
            pendingNewsBookmarkIDs.insert(postID)
            defer { pendingNewsBookmarkIDs.remove(postID) }

            do {
                if shouldBookmark {
                    try await repository.bookmarkNews(id: postID)
                } else {
                    try await repository.unbookmarkNews(id: postID)
                }
                ActivityLogRecorder.recordNews(post, actionType: shouldBookmark ? .savedNews : .unsavedNews)
                error = nil
            } catch let appError as AppError {
                posts[index].isBookmarked.toggle()
                error = appError
            } catch {
                posts[index].isBookmarked.toggle()
                self.error = .unknown
            }
        }
    }

    func loadComments(for postID: String) async {
        startListeningComments(for: postID)
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }

        do {
            let comments = try await repository.fetchNewsComments(newsID: postID)
            let visibleComments = comments.deduplicatedByID()
            posts[index].comments = visibleComments
            posts[index].commentCount = visibleComments.filter { !$0.isDeleted }.count
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    func stopListeningComments(for postID: String) {
        listenerBag.remove("newsComments:\(postID)")
    }

    private func startListeningComments(for postID: String) {
        let key = "newsComments:\(postID)"
        guard !listenerBag.contains(key),
              let realtimeRepository = repository as? NewsRealtimeRepository else { return }

        listenerBag.set(realtimeRepository.listenNewsComments(newsID: postID) { [weak self] comments in
            guard let self, let index = self.posts.firstIndex(where: { $0.id == postID }) else { return }
            let visibleComments = comments.deduplicatedByID()
            self.posts[index].comments = visibleComments
            self.posts[index].commentCount = visibleComments.filter { !$0.isDeleted }.count
            self.error = nil
        } onError: { [weak self] appError in
            self?.listenerBag.remove(key)
            self?.error = appError
            #if DEBUG
            print("Realtime listener failed: purpose=newsComments key=\(key) error=\(appError)")
            #endif
        }, for: key)
    }

    func addComment(to postID: String, text: String, author: AppUser) async {
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }
        guard !pendingNewsCommentIDs.contains(postID) else { return }
        pendingNewsCommentIDs.insert(postID)
        defer { pendingNewsCommentIDs.remove(postID) }

        do {
            let comment = try await repository.addNewsComment(newsID: postID, text: text, author: author)
            posts[index].comments.upsertByID(comment)
            posts[index].commentCount = posts[index].comments.filter { !$0.isDeleted }.count
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    func updateComment(postID: String, commentID: String, text: String) async {
        guard let postIndex = posts.firstIndex(where: { $0.id == postID }),
              let commentIndex = posts[postIndex].comments.firstIndex(where: { $0.id == commentID }) else {
            return
        }
        let pendingID = "\(postID)_\(commentID)"
        guard !pendingNewsCommentIDs.contains(pendingID) else { return }
        pendingNewsCommentIDs.insert(pendingID)
        defer { pendingNewsCommentIDs.remove(pendingID) }

        do {
            let comment = try await repository.updateNewsComment(newsID: postID, commentID: commentID, text: text)
            posts[postIndex].comments[commentIndex] = comment
            posts[postIndex].comments = posts[postIndex].comments.deduplicatedByID()
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    func deleteComment(postID: String, commentID: String) async {
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }
        let pendingID = "\(postID)_\(commentID)"
        guard !pendingNewsCommentIDs.contains(pendingID) else { return }
        pendingNewsCommentIDs.insert(pendingID)
        defer { pendingNewsCommentIDs.remove(pendingID) }

        do {
            try await repository.deleteNewsComment(newsID: postID, commentID: commentID)
            posts[index].comments.removeAll { $0.id == commentID }
            posts[index].commentCount = max(0, posts[index].commentCount - 1)
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    func post(for postID: String) -> NewsPost? {
        posts.first(where: { $0.id == postID })
    }

    var editorRepository: NewsRepository {
        repository
    }

    func deleteNews(id: String) async throws {
        let organizationID = post(for: id)?.source.organizationId

        do {
            try await repository.deleteNews(id: id)
            error = nil
            AppContentChangeBus.postNewsChanged(organizationID: organizationID)
        } catch let appError as AppError {
            error = appError
            throw appError
        } catch {
            self.error = .unknown
            throw AppError.unknown
        }
    }

    func removeDeletedNews(id: String) {
        posts.removeAll { $0.id == id }
    }

    private func startLoad(force: Bool) async {
        guard force || !hasLoaded else { return }

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

    private func performLoad() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let loadedPosts = try await repository.fetchNews()
            guard !Task.isCancelled else { return }
            posts = loadedPosts
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
}

@MainActor
final class EventsViewModel: ObservableObject {
    @Published var events: [Event]
    @Published private(set) var isLoading: Bool
    @Published private(set) var error: AppError?
    @Published private(set) var contentVersion = 0
    @Published private(set) var pendingEventLikeIDs = Set<String>()
    @Published private(set) var pendingEventRegistrationIDs = Set<String>()
    @Published private(set) var pendingEventBookmarkIDs = Set<String>()
    @Published private(set) var pendingEventViewIDs = Set<String>()
    @Published private(set) var pendingEventCommentIDs = Set<String>()
    private let repository: EventRepository
    private let listenerBag = RealtimeListenerBag()
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false
    private var lastLoadedAt: Date?

    init(
        repository: EventRepository,
        notificationPreferencesRepository: NotificationPreferencesRepository? = nil,
        localEventReminderService: LocalEventReminderServiceProtocol? = nil
    ) {
        self.repository = repository
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
        loadTask = nil
        events = []
        isLoading = false
        error = nil
        contentVersion &+= 1
        pendingEventLikeIDs = []
        pendingEventRegistrationIDs = []
        pendingEventBookmarkIDs = []
        pendingEventViewIDs = []
        pendingEventCommentIDs = []
        listenerBag.removeAll()
        hasLoaded = false
        lastLoadedAt = nil
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
                    imageURL: events[index].imageURL,
                    startDate: events[index].startDate,
                    endDate: events[index].endDate,
                    createdAt: events[index].createdAt,
                    updatedAt: events[index].updatedAt,
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
                    isAllDay: events[index].isAllDay,
                    isBookmarked: events[index].isBookmarked,
                    commentCount: events[index].commentCount
                )
                ActivityLogRecorder.recordEvent(event, actionType: shouldRegister ? .registeredForEvent : .canceledEventRegistration)
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
            defer { pendingEventBookmarkIDs.remove(eventID) }

            do {
                if shouldBookmark {
                    try await repository.bookmarkEvent(id: eventID)
                } else {
                    try await repository.unbookmarkEvent(id: eventID)
                }
                ActivityLogRecorder.recordEvent(event, actionType: shouldBookmark ? .savedEvent : .unsavedEvent)
                error = nil
            } catch let appError as AppError {
                events[index].isBookmarked.toggle()
                error = appError
            } catch {
                events[index].isBookmarked.toggle()
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

    func loadComments(for eventID: String) async {
        startListeningComments(for: eventID)
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }

        do {
            let comments = try await repository.fetchEventComments(eventID: eventID)
            let visibleComments = comments.deduplicatedByID()
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
            let visibleComments = comments.deduplicatedByID()
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
            events[index].comments.upsertByID(comment)
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
            events[eventIndex].comments = events[eventIndex].comments.deduplicatedByID()
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

    var editorRepository: EventRepository {
        repository
    }

    func deleteEvent(id: String) async throws {
        let organizationID = event(for: id)?.source.organizationId

        do {
            try await repository.deleteEvent(id: id)
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
    }

    private func startLoad(force: Bool) async {
        guard force || !hasLoaded else { return }

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

    private func performLoad() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let loadedEvents = try await repository.fetchEvents()
            guard !Task.isCancelled else { return }
            events = loadedEvents
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
}

@MainActor
final class MyRegistrationsViewModel: ObservableObject {
    @Published private(set) var events: [Event]
    @Published private(set) var isLoading: Bool
    @Published private(set) var error: AppError?
    @Published private(set) var pendingCancellationIDs = Set<String>()

    private let repository: EventRepository
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false
    private var lastLoadedAt: Date?

    init(
        repository: EventRepository,
        localEventReminderService: LocalEventReminderServiceProtocol? = nil
    ) {
        self.repository = repository
        events = []
        isLoading = false
    }

    var registrationsCount: Int {
        events.count
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await startLoad(force: false)
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

    func resetForGuest() {
        events = []
        error = nil
        hasLoaded = false
        lastLoadedAt = nil
        pendingCancellationIDs = []
    }

    func resetForAuthChange() {
        resetForGuest()
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
    }

    func cancelRegistration(for eventID: String) async {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        guard !pendingCancellationIDs.contains(eventID) else { return }

        let event = events[index]
        pendingCancellationIDs.insert(eventID)
        defer { pendingCancellationIDs.remove(eventID) }

        do {
            try await repository.cancelEventRegistration(id: eventID)
            ActivityLogRecorder.recordEvent(event, actionType: .canceledEventRegistration)
            events.removeAll { $0.id == eventID }
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    private func startLoad(force: Bool) async {
        guard force || !hasLoaded else { return }

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

    private func performLoad() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let loadedEvents = try await repository.fetchRegisteredEvents()
            guard !Task.isCancelled else { return }
            events = loadedEvents
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
}

@MainActor
final class OrganizationsViewModel: ObservableObject {
    @Published var organizations: [Organization]
    @Published private(set) var isLoading: Bool
    @Published private(set) var error: AppError?
    @Published private(set) var contentVersion = 0
    @Published private(set) var pendingOrganizationLikeIDs = Set<String>()
    @Published private(set) var pendingOrganizationSubscriptionIDs = Set<String>()
    @Published private(set) var pendingOrganizationBookmarkIDs = Set<String>()
    @Published private(set) var pendingOrganizationDeleteIDs = Set<String>()
    @Published private(set) var organizationRequests: [Organization] = []
    @Published private(set) var organizationCommentsByID: [String: [Comment]] = [:]
    @Published private(set) var pendingOrganizationCommentIDs = Set<String>()
    @Published private(set) var isSavingOrganization = false
    @Published private(set) var isUploadingOrganizationImage = false
    @Published private(set) var validationErrorMessage: String?
    private let repository: OrganizationRepository
    private let notificationInboxRepository: NotificationInboxRepository?
    private let listenerBag = RealtimeListenerBag()
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false
    private var lastLoadedAt: Date?

    init(
        repository: OrganizationRepository,
        notificationInboxRepository: NotificationInboxRepository? = nil
    ) {
        self.repository = repository
        self.notificationInboxRepository = notificationInboxRepository
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
        loadTask = nil
        organizations = []
        isLoading = false
        error = nil
        contentVersion &+= 1
        pendingOrganizationLikeIDs = []
        pendingOrganizationSubscriptionIDs = []
        pendingOrganizationBookmarkIDs = []
        pendingOrganizationDeleteIDs = []
        organizationRequests = []
        organizationCommentsByID = [:]
        pendingOrganizationCommentIDs = []
        listenerBag.removeAll()
        isSavingOrganization = false
        isUploadingOrganizationImage = false
        validationErrorMessage = nil
        hasLoaded = false
        lastLoadedAt = nil
    }

    func toggleLike(for organizationID: String) {
        guard let index = organizations.firstIndex(where: { $0.id == organizationID }) else { return }
        guard !pendingOrganizationLikeIDs.contains(organizationID) else { return }
        let shouldLike = organizations[index].likeState == .notLiked
        let previousLikeState = organizations[index].likeState
        let previousLikeCount = organizations[index].likeCount

        organizations[index].likeState = shouldLike ? .liked : .notLiked
        organizations[index].likeCount = max(0, previousLikeCount + (shouldLike ? 1 : -1))

        Task {
            pendingOrganizationLikeIDs.insert(organizationID)
            defer { pendingOrganizationLikeIDs.remove(organizationID) }

            do {
                if shouldLike {
                    try await repository.likeOrganization(id: organizationID)
                } else {
                    try await repository.unlikeOrganization(id: organizationID)
                }

                error = nil
            } catch let appError as AppError {
                organizations[index].likeState = previousLikeState
                organizations[index].likeCount = previousLikeCount
                error = appError
            } catch {
                organizations[index].likeState = previousLikeState
                organizations[index].likeCount = previousLikeCount
                self.error = .unknown
            }
        }
    }

    func toggleSubscription(for organizationID: String) {
        guard let index = organizations.firstIndex(where: { $0.id == organizationID }) else { return }
        guard !pendingOrganizationSubscriptionIDs.contains(organizationID) else { return }
        let shouldSubscribe = !organizations[index].isSubscribed
        let organization = organizations[index]
        let previousSubscriptionState = organizations[index].isSubscribed
        let previousSubscriberCount = organizations[index].subscriberCount

        pendingOrganizationSubscriptionIDs.insert(organizationID)
        organizations[index].isSubscribed = shouldSubscribe
        organizations[index].subscriberCount = max(0, previousSubscriberCount + (shouldSubscribe ? 1 : -1))
        contentVersion &+= 1

        Task {
            defer { pendingOrganizationSubscriptionIDs.remove(organizationID) }

            do {
                if shouldSubscribe {
                    try await repository.subscribeOrganization(id: organizationID)
                } else {
                    try await repository.unsubscribeOrganization(id: organizationID)
                }

                ActivityLogRecorder.recordOrganization(organization, actionType: shouldSubscribe ? .followedOrganization : .unfollowedOrganization)
                error = nil
            } catch let appError as AppError {
                organizations[index].isSubscribed = previousSubscriptionState
                organizations[index].subscriberCount = previousSubscriberCount
                contentVersion &+= 1
                error = appError
            } catch {
                organizations[index].isSubscribed = previousSubscriptionState
                organizations[index].subscriberCount = previousSubscriberCount
                contentVersion &+= 1
                self.error = .unknown
            }
        }
    }

    func toggleBookmark(for organizationID: String) {
        guard let index = organizations.firstIndex(where: { $0.id == organizationID }) else { return }
        guard !pendingOrganizationBookmarkIDs.contains(organizationID) else { return }
        let shouldBookmark = !organizations[index].isBookmarked
        let organization = organizations[index]
        let previousBookmarkState = organizations[index].isBookmarked

        pendingOrganizationBookmarkIDs.insert(organizationID)
        organizations[index].isBookmarked = shouldBookmark

        Task {
            defer { pendingOrganizationBookmarkIDs.remove(organizationID) }

            do {
                if shouldBookmark {
                    try await repository.bookmarkOrganization(id: organizationID)
                } else {
                    try await repository.unbookmarkOrganization(id: organizationID)
                }

                ActivityLogRecorder.recordOrganization(organization, actionType: shouldBookmark ? .savedOrganization : .unsavedOrganization)
                error = nil
            } catch let appError as AppError {
                organizations[index].isBookmarked = previousBookmarkState
                error = appError
            } catch {
                organizations[index].isBookmarked = previousBookmarkState
                self.error = .unknown
            }
        }
    }

    func organization(for organizationID: String) -> Organization? {
        return organizations.first(where: { $0.id == organizationID })
    }

    func comments(for organizationID: String) -> [Comment] {
        organizationCommentsByID[organizationID] ?? []
    }

    func loadComments(for organizationID: String) async {
        startListeningComments(for: organizationID)
        do {
            organizationCommentsByID[organizationID] = try await repository.fetchOrganizationComments(organizationID: organizationID).deduplicatedByID()
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    func stopListeningComments(for organizationID: String) {
        listenerBag.remove("organizationComments:\(organizationID)")
    }

    private func startListeningComments(for organizationID: String) {
        let key = "organizationComments:\(organizationID)"
        guard !listenerBag.contains(key),
              let realtimeRepository = repository as? OrganizationRealtimeRepository else { return }

        listenerBag.set(realtimeRepository.listenOrganizationComments(organizationID: organizationID) { [weak self] comments in
            self?.organizationCommentsByID[organizationID] = comments.deduplicatedByID()
            self?.error = nil
        } onError: { [weak self] appError in
            self?.listenerBag.remove(key)
            self?.error = appError
            #if DEBUG
            print("Realtime listener failed: purpose=organizationComments key=\(key) error=\(appError)")
            #endif
        }, for: key)
    }

    func addComment(to organizationID: String, text: String, author: AppUser) async {
        guard !pendingOrganizationCommentIDs.contains(organizationID) else { return }
        pendingOrganizationCommentIDs.insert(organizationID)
        defer { pendingOrganizationCommentIDs.remove(organizationID) }

        do {
            let comment = try await repository.addOrganizationComment(organizationID: organizationID, text: text, author: author)
            organizationCommentsByID[organizationID, default: []].upsertByID(comment)
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    func updateComment(organizationID: String, commentID: String, text: String) async {
        guard !pendingOrganizationCommentIDs.contains(organizationID) else { return }
        pendingOrganizationCommentIDs.insert(organizationID)
        defer { pendingOrganizationCommentIDs.remove(organizationID) }

        do {
            let updated = try await repository.updateOrganizationComment(organizationID: organizationID, commentID: commentID, text: text)
            if let index = organizationCommentsByID[organizationID]?.firstIndex(where: { $0.id == commentID }) {
                organizationCommentsByID[organizationID]?[index] = updated
                organizationCommentsByID[organizationID] = organizationCommentsByID[organizationID]?.deduplicatedByID()
            }
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    func deleteComment(organizationID: String, commentID: String) async {
        guard !pendingOrganizationCommentIDs.contains(organizationID) else { return }
        pendingOrganizationCommentIDs.insert(organizationID)
        defer { pendingOrganizationCommentIDs.remove(organizationID) }

        do {
            try await repository.deleteOrganizationComment(organizationID: organizationID, commentID: commentID)
            organizationCommentsByID[organizationID]?.removeAll { $0.id == commentID }
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
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
        guard let user else {
            organizationRequests = []
            listenerBag.removeAll(matchingPrefix: "submittedOrganizationRequests:")
            return
        }

        startListeningOrganizationRequests(for: user.id)

        do {
            organizationRequests = try await repository.fetchOrganizationRequests(submittedByUserID: user.id).deduplicatedByID()
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    private func startListeningOrganizationRequests(for userID: String) {
        let key = "submittedOrganizationRequests:\(userID)"
        listenerBag.removeAll(except: key, matchingPrefix: "submittedOrganizationRequests:")
        guard !listenerBag.contains(key),
              let realtimeRepository = repository as? OrganizationRealtimeRepository else { return }

        listenerBag.set(realtimeRepository.listenSubmittedOrganizationRequests(userID: userID) { [weak self] requests in
            self?.organizationRequests = requests.deduplicatedByID()
            self?.error = nil
        } onError: { [weak self] appError in
            self?.listenerBag.remove(key)
            self?.error = appError
            #if DEBUG
            print("Realtime listener failed: purpose=submittedOrganizationRequests key=\(key) error=\(appError)")
            #endif
        }, for: key)
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

        pendingOrganizationDeleteIDs.insert(id)
        defer { pendingOrganizationDeleteIDs.remove(id) }

        do {
            try await repository.deleteOrganization(id: id)
            error = nil
            validationErrorMessage = nil
            organizationRequests.removeAll { $0.id == id }
            AppContentChangeBus.postOrganizationsChanged(organizationID: id)
        } catch let appError as AppError {
            error = appError
            throw appError
        } catch {
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
        guard force || !hasLoaded else { return }

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

    private func performLoad() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let loadedOrganizations = try await repository.fetchOrganizations()
            guard !Task.isCancelled else { return }
            organizations = loadedOrganizations
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

    private func saveOrganization(_ organization: Organization, imageData: Data?, isEditing: Bool) async throws {
        guard !isSavingOrganization else { return }

        isSavingOrganization = true
        validationErrorMessage = nil
        defer {
            isSavingOrganization = false
            isUploadingOrganizationImage = false
        }

        do {
            if isEditing {
                try await ensureOrganizationRequestIsStillEditable(organization)
            }

            if !isEditing && organization.moderationStatus != .approved {
                try await repository.createOrganization(organization)
                var organizationToInsert = organization

                if let imageData {
                    do {
                        isUploadingOrganizationImage = true
                        let uploadedURL = try await repository.uploadOrganizationImage(data: imageData, organizationID: organization.id)
                        isUploadingOrganizationImage = false
                        organizationToInsert = organization.settingOrganizationImageURL(uploadedURL.absoluteString)
                        try await repository.updateOrganization(organizationToInsert)
                    } catch {
                        isUploadingOrganizationImage = false
                        do {
                            try await repository.deleteOrganization(id: organization.id)
                        } catch {}
                        throw error
                    }
                }

                organizationRequests.upsertByID(organizationToInsert)
                contentVersion &+= 1
                error = nil
                AppContentChangeBus.postOrganizationsChanged(organizationID: organizationToInsert.id)
                return
            }

            let resolvedImageURL: String?
            if let imageData {
                isUploadingOrganizationImage = true
                let uploadedURL = try await repository.uploadOrganizationImage(data: imageData, organizationID: organization.id)
                resolvedImageURL = uploadedURL.absoluteString
                isUploadingOrganizationImage = false
            } else {
                resolvedImageURL = organization.imageURL
            }

            let organizationToSave = Organization(
                id: organization.id,
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
                foundedYear: organization.foundedYear,
                foundedMonth: organization.foundedMonth,
                languages: organization.languages,
                socialLinks: organization.socialLinks,
                telegramURL: organization.telegramURL,
                donationURL: organization.donationURL,
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
                replaceOrganization(organizationToSave)
                replaceOrganizationRequest(organizationToSave)
            } else {
                try await repository.createOrganization(organizationToSave)
                if organizationToSave.moderationStatus == .approved {
                    organizations.insert(organizationToSave, at: 0)
                } else {
                    organizationRequests.upsertByID(organizationToSave)
                }
            }

            contentVersion &+= 1
            error = nil
            AppContentChangeBus.postOrganizationsChanged(organizationID: organizationToSave.id)
        } catch let appError as AppError {
            error = appError
            throw appError
        } catch {
            self.error = .unknown
            validationErrorMessage = error.localizedDescription
            throw AppError.unknown
        }
    }

    private func ensureOrganizationRequestIsStillEditable(_ organization: Organization) async throws {
        guard organization.submittedByUserId != nil else { return }
        guard [.pendingReview, .needsRevision, .rejected].contains(organization.moderationStatus) else { return }

        do {
            let latest = try await repository.fetchOrganization(id: organization.id)
            guard latest.submittedByUserId == organization.submittedByUserId,
                  [.pendingReview, .needsRevision, .rejected].contains(latest.moderationStatus) else {
                validationErrorMessage = AppStrings.Organizations.requestAlreadyReviewed
                throw AppError.validationFailed
            }
        } catch AppError.notFound {
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
        try await repository.approveOrganizationRequest(id: id, reviewerID: reviewerID)
        organizationRequests.removeAll { $0.id == id }
        AppContentChangeBus.postOrganizationsChanged(organizationID: id)
    }

    func requestOrganizationRevision(id: String, message: String, reviewerID: String) async throws {
        try await repository.requestOrganizationRevision(id: id, message: message, reviewerID: reviewerID)
        AppContentChangeBus.postOrganizationsChanged(organizationID: id)
    }

    func rejectOrganizationRequest(id: String, reason: String, reviewerID: String) async throws {
        try await repository.rejectOrganizationRequest(id: id, reason: reason, reviewerID: reviewerID)
        organizationRequests.removeAll { $0.id == id }
        AppContentChangeBus.postOrganizationsChanged(organizationID: id)
    }

}

private extension Organization {
    func settingOrganizationImageURL(_ imageURL: String?) -> Organization {
        Organization(
            id: id,
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
            foundedYear: foundedYear,
            foundedMonth: foundedMonth,
            languages: languages,
            socialLinks: socialLinks,
            telegramURL: telegramURL,
            donationURL: donationURL,
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


@MainActor
final class ProfileViewModel: ObservableObject {
    @Published private(set) var user: AppUser
    @Published var settings: UserSettings
    @Published private(set) var error: AppError?
    @Published private(set) var isSavingProfile = false
    @Published private(set) var isSubmittingFeedback = false
    @Published private(set) var isDeletingAccount = false
    @Published private(set) var isLoading = false
    @Published var notificationPreferences: NotificationPreferences = .default
    @Published private(set) var isLoadingNotificationPreferences = false
    @Published private(set) var isSavingNotificationPreferences = false
    @Published var notificationPreferencesMessage: String?
    @Published var profileMessage: String?
    @Published var feedbackMessage: String?
    private let repository: UserRepository
    private let feedbackRepository: FeedbackRepository
    private let notificationPreferencesRepository: NotificationPreferencesRepository
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false
    private var lastLoadedAt: Date?
    private var loadedNotificationPreferencesUserID: String?

    init(
        repository: UserRepository,
        feedbackRepository: FeedbackRepository,
        notificationPreferencesRepository: NotificationPreferencesRepository,
        notificationPermissionService: NotificationPermissionServiceProtocol,
        localEventReminderService: LocalEventReminderServiceProtocol
    ) {
        self.repository = repository
        self.feedbackRepository = feedbackRepository
        self.notificationPreferencesRepository = notificationPreferencesRepository
        user = .placeholder
        settings = .stored
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
        loadTask = nil
        user = .placeholder
        error = nil
        isSavingProfile = false
        isSubmittingFeedback = false
        isDeletingAccount = false
        isLoading = false
        notificationPreferences = .default
        isLoadingNotificationPreferences = false
        isSavingNotificationPreferences = false
        notificationPreferencesMessage = nil
        loadedNotificationPreferencesUserID = nil
        profileMessage = nil
        feedbackMessage = nil
        hasLoaded = false
        lastLoadedAt = nil
    }

    func loadNotificationPreferencesIfNeeded(userID: String) async {
        guard loadedNotificationPreferencesUserID != userID else { return }
        await loadNotificationPreferences(userID: userID)
    }

    func refreshNotificationPreferences(userID: String) async {
        await loadNotificationPreferences(userID: userID)
    }

    func setNotificationsEnabled(_ isEnabled: Bool, userID: String) async {
        guard !isSavingNotificationPreferences else { return }

        var updatedPreferences = notificationPreferences
        updatedPreferences.notificationsEnabled = isEnabled
        await saveNotificationPreferences(updatedPreferences, userID: userID)
    }

    private func loadNotificationPreferences(userID: String) async {
        isLoadingNotificationPreferences = true
        defer { isLoadingNotificationPreferences = false }

        do {
            notificationPreferences = try await notificationPreferencesRepository.fetchNotificationPreferences(userID: userID)
            notificationPreferencesMessage = nil
            loadedNotificationPreferencesUserID = userID
        } catch let appError as AppError {
            error = appError
            notificationPreferencesMessage = AppStrings.Profile.notificationPreferencesLoadFailed
        } catch {
            self.error = .unknown
            notificationPreferencesMessage = AppStrings.Profile.notificationPreferencesLoadFailed
        }
    }

    private func saveNotificationPreferences(_ updatedPreferences: NotificationPreferences, userID: String) async {
        let previousPreferences = notificationPreferences
        notificationPreferences = updatedPreferences
        isSavingNotificationPreferences = true
        notificationPreferencesMessage = nil
        defer { isSavingNotificationPreferences = false }

        do {
            try await notificationPreferencesRepository.saveNotificationPreferences(updatedPreferences, userID: userID)
            notificationPreferencesMessage = AppStrings.Profile.notificationPreferencesSaved
            loadedNotificationPreferencesUserID = userID
        } catch let appError as AppError {
            notificationPreferences = previousPreferences
            error = appError
            notificationPreferencesMessage = AppStrings.Profile.notificationPreferencesSaveFailed
        } catch {
            notificationPreferences = previousPreferences
            self.error = .unknown
            notificationPreferencesMessage = AppStrings.Profile.notificationPreferencesSaveFailed
        }
    }

    func saveProfile(_ profile: EditableUserProfileDraft, avatarImageData: Data? = nil) async -> AppUser? {
        guard !isSavingProfile else { return nil }

        let trimmedDisplayName = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDisplayName.isEmpty else {
            profileMessage = AppStrings.Profile.displayNameRequired
            return nil
        }

        isSavingProfile = true
        profileMessage = nil
        defer { isSavingProfile = false }

        do {
            let resolvedProfile: EditableUserProfileDraft
            if let avatarImageData {
                let avatarUserID = AuthService.shared.currentUser?.uid ?? user.id
                let avatarURL = try await ImageUploadService.shared.uploadProfileAvatarImage(
                    data: avatarImageData,
                    userID: avatarUserID
                )
                resolvedProfile = EditableUserProfileDraft(
                    fullName: profile.fullName,
                    displayName: profile.displayName,
                    telegramUsername: profile.telegramUsername,
                    city: profile.city,
                    bio: profile.bio,
                    selectedFederalState: profile.selectedFederalState,
                    avatarURL: avatarURL
                )
            } else {
                resolvedProfile = profile
            }

            let updatedUser = try await repository.updateProfile(resolvedProfile)
            user = updatedUser
            error = nil
            profileMessage = AppStrings.Profile.profileSaved
            return updatedUser
        } catch let appError as AppError {
            error = appError
            profileMessage = avatarImageData != nil || appError == .network
                ? AppStrings.Profile.avatarUploadFailed
                : AppStrings.Profile.profileSaveFailed
            return nil
        } catch {
            self.error = .unknown
            profileMessage = avatarImageData != nil
                ? AppStrings.Profile.avatarUploadFailed
                : AppStrings.Profile.profileSaveFailed
            return nil
        }
    }

    func submitFeedback(type: FeedbackType, message: String, user: AppUser) async -> Bool {
        guard !isSubmittingFeedback else { return false }

        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            feedbackMessage = AppStrings.Feedback.messageRequired
            return false
        }

        isSubmittingFeedback = true
        feedbackMessage = nil
        defer { isSubmittingFeedback = false }

        do {
            let now = Date()
            try await feedbackRepository.submitFeedback(FeedbackItem(
                id: UUID().uuidString,
                type: type,
                subject: nil,
                message: trimmedMessage,
                status: .open,
                createdAt: now,
                updatedAt: now,
                userId: user.id,
                userDisplayName: user.preferredDisplayName,
                ownerReply: nil,
                repliedAt: nil,
                repliedByUserId: nil,
                lastMessageText: trimmedMessage,
                lastMessageAt: now,
                lastMessageByUserId: user.id,
                lastMessageByRole: .user,
                unreadForOwner: true,
                unreadForUser: false
            ))
            error = nil
            feedbackMessage = AppStrings.Feedback.submitted
            return true
        } catch let appError as AppError {
            error = appError
            feedbackMessage = AppStrings.Feedback.submitFailed
            return false
        } catch {
            self.error = .unknown
            feedbackMessage = AppStrings.Feedback.submitFailed
            return false
        }
    }

    func deleteAccount(currentUser: AppUser) async -> String? {
        guard !isDeletingAccount else { return nil }

        isDeletingAccount = true
        defer { isDeletingAccount = false }

        do {
            try await repository.deleteAccount(currentUser: currentUser)
            _ = AuthService.shared.signOut()
            resetForAuthChange()
            return nil
        } catch let deletionError as AccountDeletionError {
            switch deletionError {
            case .platformOwner:
                return AppStrings.Profile.deleteAccountPlatformOwnerBlocked
            case .ownsOrganization:
                return AppStrings.Profile.deleteAccountOrganizationOwnerBlocked
            case .requiresRecentLogin:
                return AppStrings.Profile.deleteAccountRequiresRecentLogin
            case .stageFailed(let stage, let permissionDenied):
                if permissionDenied {
                    return AppStrings.Profile.deleteAccountPermissionFailed
                }

                switch stage {
                case .privateDataCleanup,
                        .interactionCleanup,
                        .registrationCleanup,
                        .avatarCleanup,
                        .publicProfileDelete:
                    return AppStrings.Profile.deleteAccountCleanupFailed
                case .userDocumentDelete, .authUserDelete:
                    return AppStrings.Profile.deleteAccountFailed
                }
            }
        } catch let appError as AppError {
            error = appError
            return AppStrings.Profile.deleteAccountFailed
        } catch {
            self.error = .unknown
            return AppStrings.Profile.deleteAccountFailed
        }
    }

    private func startLoad(force: Bool) async {
        guard force || !hasLoaded else { return }

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

    private func performLoad() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if !(repository is FirestoreUserRepository) {
                user = try await repository.fetchCurrentUser()
            }
            settings = try await repository.fetchSettings()
            settings.language = LocalizationStore.language
            error = nil
            profileMessage = nil
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
}

@MainActor
final class MyFeedbackViewModel: ObservableObject {
    @Published private(set) var items: [FeedbackItem] = []
    @Published private(set) var messagesByFeedbackID: [String: [FeedbackMessage]] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var loadingMessageFeedbackIDs = Set<String>()
    @Published private(set) var sendingMessageFeedbackIDs = Set<String>()
    @Published private(set) var error: AppError?

    private let repository: FeedbackRepository
    private let listenerBag = RealtimeListenerBag()
    private var loadedUserID: String?

    init(repository: FeedbackRepository) {
        self.repository = repository
    }

    func loadIfNeeded(userID: String) async {
        startListeningMyFeedback(userID: userID)
        guard loadedUserID != userID || items.isEmpty else { return }
        await refresh(userID: userID)
    }

    func refresh(userID: String) async {
        startListeningMyFeedback(userID: userID)
        isLoading = true
        error = nil
        defer {
            isLoading = false
            loadedUserID = userID
        }

        do {
            items = try await repository.fetchFeedback(userID: userID)
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    func reset() {
        items = []
        messagesByFeedbackID = [:]
        isLoading = false
        loadingMessageFeedbackIDs = []
        sendingMessageFeedbackIDs = []
        listenerBag.removeAll()
        error = nil
        loadedUserID = nil
    }

    func messages(for item: FeedbackItem) -> [FeedbackMessage] {
        messagesByFeedbackID[item.id] ?? item.legacyMessages
    }

    func loadMessages(for item: FeedbackItem) async {
        startListeningMessages(for: item)
        guard !loadingMessageFeedbackIDs.contains(item.id) else { return }
        loadingMessageFeedbackIDs.insert(item.id)
        defer { loadingMessageFeedbackIDs.remove(item.id) }

        do {
            messagesByFeedbackID[item.id] = try await repository.fetchFeedbackMessages(feedback: item)
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    func stopListeningMessages(for feedbackID: String) {
        listenerBag.remove("feedbackMessages:\(feedbackID)")
    }

    private func startListeningMyFeedback(userID: String) {
        let key = "myFeedback:\(userID)"
        guard !listenerBag.contains(key),
              let realtimeRepository = repository as? FeedbackRealtimeRepository else { return }

        listenerBag.set(realtimeRepository.listenMyFeedback(userID: userID) { [weak self] items in
            self?.items = items
            self?.loadedUserID = userID
            self?.error = nil
        } onError: { [weak self] appError in
            self?.listenerBag.remove(key)
            self?.error = appError
            #if DEBUG
            print("Realtime listener failed: purpose=myFeedback key=\(key) error=\(appError)")
            #endif
        }, for: key)
    }

    private func startListeningMessages(for item: FeedbackItem) {
        let key = "feedbackMessages:\(item.id)"
        guard !listenerBag.contains(key),
              let realtimeRepository = repository as? FeedbackRealtimeRepository else { return }

        listenerBag.set(realtimeRepository.listenFeedbackMessages(feedback: item) { [weak self] messages in
            self?.messagesByFeedbackID[item.id] = messages
            self?.error = nil
        } onError: { [weak self] appError in
            self?.listenerBag.remove(key)
            self?.error = appError
            #if DEBUG
            print("Realtime listener failed: purpose=feedbackMessages key=\(key) error=\(appError)")
            #endif
        }, for: key)
    }

    func sendMessage(_ text: String, feedback: FeedbackItem, user: AppUser) async -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, trimmedText.count <= 2000, !feedback.status.isClosed else {
            error = .validationFailed
            return false
        }

        guard !sendingMessageFeedbackIDs.contains(feedback.id) else { return false }
        sendingMessageFeedbackIDs.insert(feedback.id)
        defer { sendingMessageFeedbackIDs.remove(feedback.id) }

        do {
            try await repository.sendUserFeedbackMessage(feedback: feedback, text: trimmedText, user: user)
            await refresh(userID: user.id)
            if let updatedItem = items.first(where: { $0.id == feedback.id }) {
                await loadMessages(for: updatedItem)
            }
            error = nil
            return true
        } catch let appError as AppError {
            error = appError
            return false
        } catch {
            self.error = .unknown
            return false
        }
    }
}

@MainActor
final class FeedbackInboxViewModel: ObservableObject {
    @Published private(set) var items: [FeedbackItem] = []
    @Published private(set) var messagesByFeedbackID: [String: [FeedbackMessage]] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var loadingMessageFeedbackIDs = Set<String>()
    @Published private(set) var error: AppError?
    @Published private(set) var updatingFeedbackIDs = Set<String>()

    private let repository: FeedbackRepository
    private let notificationInboxRepository: NotificationInboxRepository?
    private let listenerBag = RealtimeListenerBag()
    private var hasLoaded = false

    init(
        repository: FeedbackRepository,
        notificationInboxRepository: NotificationInboxRepository? = nil
    ) {
        self.repository = repository
        self.notificationInboxRepository = notificationInboxRepository
    }

    func loadIfNeeded() async {
        startListeningInbox()
        guard !hasLoaded else { return }
        await refresh()
    }

    func refresh() async {
        startListeningInbox()
        isLoading = true
        error = nil
        defer {
            isLoading = false
            hasLoaded = true
        }

        do {
            items = try await repository.fetchFeedback()
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    func markReviewed(_ item: FeedbackItem) async {
        await update(item, status: .answered)
    }

    func archive(_ item: FeedbackItem) async {
        await close(item)
    }

    func sendReply(_ reply: String, to item: FeedbackItem, owner: AppUser) async -> Bool {
        let trimmedReply = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReply.isEmpty else {
            error = .validationFailed
            return false
        }

        guard trimmedReply.count <= 2000 else {
            error = .validationFailed
            return false
        }

        guard !updatingFeedbackIDs.contains(item.id) else { return false }
        updatingFeedbackIDs.insert(item.id)
        defer { updatingFeedbackIDs.remove(item.id) }

        do {
            try await repository.sendOwnerFeedbackReply(feedback: item, text: trimmedReply, owner: owner)
            await createFeedbackReplyNotification(for: item, reply: trimmedReply, owner: owner)
            await refresh()
            if let updatedItem = items.first(where: { $0.id == item.id }) {
                await loadMessages(for: updatedItem)
            }
            error = nil
            return true
        } catch let appError as AppError {
            error = appError
            return false
        } catch {
            self.error = .unknown
            return false
        }
    }

    func close(_ item: FeedbackItem) async {
        guard !updatingFeedbackIDs.contains(item.id) else { return }
        updatingFeedbackIDs.insert(item.id)
        defer { updatingFeedbackIDs.remove(item.id) }

        do {
            try await repository.closeFeedback(id: item.id)
            items = items.map { current in
                guard current.id == item.id else { return current }
                return current.updating(status: .closed)
            }
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    func messages(for item: FeedbackItem) -> [FeedbackMessage] {
        messagesByFeedbackID[item.id] ?? item.legacyMessages
    }

    func loadMessages(for item: FeedbackItem) async {
        startListeningMessages(for: item)
        guard !loadingMessageFeedbackIDs.contains(item.id) else { return }
        loadingMessageFeedbackIDs.insert(item.id)
        defer { loadingMessageFeedbackIDs.remove(item.id) }

        do {
            messagesByFeedbackID[item.id] = try await repository.fetchFeedbackMessages(feedback: item)
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    func stopListeningMessages(for feedbackID: String) {
        listenerBag.remove("feedbackMessages:\(feedbackID)")
    }

    private func startListeningInbox() {
        let key = "feedbackInbox"
        guard !listenerBag.contains(key),
              let realtimeRepository = repository as? FeedbackRealtimeRepository else { return }

        listenerBag.set(realtimeRepository.listenOwnerFeedbackInbox { [weak self] items in
            self?.items = items
            self?.hasLoaded = true
            self?.error = nil
        } onError: { [weak self] appError in
            self?.listenerBag.remove(key)
            self?.error = appError
            #if DEBUG
            print("Realtime listener failed: purpose=feedbackInbox key=\(key) error=\(appError)")
            #endif
        }, for: key)
    }

    private func startListeningMessages(for item: FeedbackItem) {
        let key = "feedbackMessages:\(item.id)"
        guard !listenerBag.contains(key),
              let realtimeRepository = repository as? FeedbackRealtimeRepository else { return }

        listenerBag.set(realtimeRepository.listenFeedbackMessages(feedback: item) { [weak self] messages in
            self?.messagesByFeedbackID[item.id] = messages
            self?.error = nil
        } onError: { [weak self] appError in
            self?.listenerBag.remove(key)
            self?.error = appError
            #if DEBUG
            print("Realtime listener failed: purpose=feedbackMessages key=\(key) error=\(appError)")
            #endif
        }, for: key)
    }

    private func createFeedbackReplyNotification(for item: FeedbackItem, reply: String, owner: AppUser) async {
        guard let notificationInboxRepository else { return }
        var payload = [
            "feedbackId": item.id,
            "messagePreview": String(reply.prefix(160))
        ]
        if let subject = item.subject?.trimmingCharacters(in: .whitespacesAndNewlines), !subject.isEmpty {
            payload["subject"] = subject
        }

        let notification = AppNotification(
            id: UUID().uuidString,
            recipientUserId: item.userId,
            type: .feedbackReply,
            sourceType: .feedback,
            sourceId: item.id,
            actorUserId: owner.id,
            actorDisplayName: owner.preferredDisplayName,
            payload: payload,
            isRead: false,
            readAt: nil,
            createdAt: Date()
        )

        do {
            try await notificationInboxRepository.createNotification(userID: item.userId, notification: notification)
        } catch {
            #if DEBUG
            print("Notification inbox create failed: type=\(AppNotificationType.feedbackReply.rawValue) recipient=\(item.userId) source=\(item.id) error=\(error)")
            #endif
        }
    }

    private func update(_ item: FeedbackItem, status: FeedbackStatus) async {
        guard !updatingFeedbackIDs.contains(item.id) else { return }
        updatingFeedbackIDs.insert(item.id)
        defer { updatingFeedbackIDs.remove(item.id) }

        do {
            try await repository.updateFeedbackStatus(id: item.id, status: status)
            items = items.map { current in
                guard current.id == item.id else { return current }
                return current.updating(status: status)
            }
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }
}

private extension FeedbackItem {
    func updating(status: FeedbackStatus) -> FeedbackItem {
        FeedbackItem(
            id: id,
            type: type,
            subject: subject,
            message: message,
            status: status,
            createdAt: createdAt,
            updatedAt: .now,
            userId: userId,
            userDisplayName: userDisplayName,
            ownerReply: ownerReply,
            repliedAt: repliedAt,
            repliedByUserId: repliedByUserId,
            lastMessageText: lastMessageText,
            lastMessageAt: lastMessageAt,
            lastMessageByUserId: lastMessageByUserId,
            lastMessageByRole: lastMessageByRole,
            unreadForOwner: unreadForOwner,
            unreadForUser: unreadForUser
        )
    }
}

private extension Array where Element == Organization {
    func deduplicatedByID() -> [Organization] {
        var seenIDs = Set<String>()
        return filter { organization in
            seenIDs.insert(organization.id).inserted
        }
    }

    mutating func upsertByID(_ organization: Organization) {
        if let index = firstIndex(where: { $0.id == organization.id }) {
            self[index] = organization
        } else {
            insert(organization, at: 0)
        }
    }
}

private extension Array where Element == Comment {
    func deduplicatedByID() -> [Comment] {
        var seenIDs = Set<String>()
        return filter { comment in
            seenIDs.insert(comment.id).inserted
        }
    }

    mutating func upsertByID(_ comment: Comment) {
        if let index = firstIndex(where: { $0.id == comment.id }) {
            self[index] = comment
        } else {
            append(comment)
        }
    }
}
