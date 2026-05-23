import Combine
import FirebaseAuth
import Foundation

nonisolated private let defaultRefreshStaleInterval: TimeInterval = 300

@MainActor
final class AppHeroBannerViewModel: ObservableObject {
    @Published private(set) var imageSource: AppHeroBannerImageSource
    @Published private(set) var isUploading = false
    @Published private(set) var error: AppError?

    private let section: AppHeroBannerSection
    private let bannerService: HomeBannerServiceProtocol
    private var hasLoaded = false

    init(
        section: AppHeroBannerSection,
        bannerService: HomeBannerServiceProtocol,
        fallbackImageSource: AppHeroBannerImageSource = .none
    ) {
        self.section = section
        self.bannerService = bannerService
        self.imageSource = fallbackImageSource
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await refresh()
    }

    func refresh() async {
        do {
            if let metadata = try await bannerService.fetchBanner(for: section) {
                imageSource = .remoteURL(metadata.imageURL)
            } else {
                imageSource = .none
            }
            error = nil
            hasLoaded = true
        } catch let appError as AppError {
            error = appError
            hasLoaded = true
        } catch {
            self.error = .unknown
            hasLoaded = true
        }
    }

    func updateImage(data: Data, user: AppUser?) async {
        guard PermissionService.canManageHomeBanner(user: user), let user else {
            error = .permissionDenied
            return
        }

        isUploading = true
        defer { isUploading = false }

        do {
            let metadata = try await bannerService.updateBannerImage(data: data, for: section, updatedBy: user.id)
            imageSource = .remoteURL(metadata.imageURL)
            error = nil
            hasLoaded = true
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    func setSelectionFailed() {
        error = .validationFailed
    }

    func clearError() {
        error = nil
    }
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var feedItems: [HomeFeedItem]
    @Published private(set) var isLoading: Bool
    @Published private(set) var error: AppError?
    @Published private(set) var bannerImageSource: AppHeroBannerImageSource
    @Published private(set) var isBannerUploading: Bool
    @Published private(set) var bannerError: AppError?
    private let feedViewModel: HomeFeedViewModel
    private let homeBannerService: HomeBannerServiceProtocol
    private var hasLoadedBanner = false

    init(
        newsRepository: NewsRepository,
        eventRepository: EventRepository,
        organizationRepository: OrganizationRepository,
        homeBannerService: HomeBannerServiceProtocol
    ) {
        feedItems = []
        isLoading = false
        bannerImageSource = .none
        isBannerUploading = false
        self.homeBannerService = homeBannerService
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

    func loadBannerIfNeeded() async {
        guard !hasLoadedBanner else { return }
        await refreshBanner()
    }

    func refreshBanner() async {
        do {
            if let metadata = try await homeBannerService.fetchHomeBanner() {
                bannerImageSource = .remoteURL(metadata.imageURL)
            } else {
                bannerImageSource = .none
            }
            bannerError = nil
            hasLoadedBanner = true
        } catch {
            hasLoadedBanner = true
        }
    }

    func updateHomeBannerImage(data: Data, user: AppUser?) async {
        guard PermissionService.canManageHomeBanner(user: user), let user else {
            bannerError = .permissionDenied
            return
        }

        isBannerUploading = true
        defer { isBannerUploading = false }

        do {
            let metadata = try await homeBannerService.updateHomeBannerImage(data: data, updatedBy: user.id)
            bannerImageSource = .remoteURL(metadata.imageURL)
            bannerError = nil
            hasLoadedBanner = true
        } catch let appError as AppError {
            bannerError = appError
        } catch {
            bannerError = .unknown
        }
    }

    func setBannerSelectionFailed() {
        bannerError = .validationFailed
    }

    func clearBannerError() {
        bannerError = nil
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
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }

        do {
            let comments = try await repository.fetchNewsComments(newsID: postID)
            posts[index].comments = comments
            posts[index].commentCount = comments.filter { !$0.isDeleted }.count
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    func addComment(to postID: String, text: String, author: AppUser) async {
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }
        guard !pendingNewsCommentIDs.contains(postID) else { return }
        pendingNewsCommentIDs.insert(postID)
        defer { pendingNewsCommentIDs.remove(postID) }

        do {
            let comment = try await repository.addNewsComment(newsID: postID, text: text, author: author)
            posts[index].comments.append(comment)
            posts[index].commentCount += 1
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
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false
    private var lastLoadedAt: Date?

    init(repository: EventRepository) {
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
        let organizationID = events[index].source.organizationId

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
                AppContentChangeBus.postRegistrationsChanged(organizationID: organizationID)
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
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }

        do {
            let comments = try await repository.fetchEventComments(eventID: eventID)
            events[index].comments = comments
            events[index].commentCount = comments.filter { !$0.isDeleted }.count
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    func addComment(to eventID: String, text: String, author: AppUser) async {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        guard !pendingEventCommentIDs.contains(eventID) else { return }
        pendingEventCommentIDs.insert(eventID)
        defer { pendingEventCommentIDs.remove(eventID) }

        do {
            let comment = try await repository.addEventComment(eventID: eventID, text: text, author: author)
            events[index].comments.append(comment)
            events[index].commentCount += 1
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

    init(repository: EventRepository) {
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
        let organizationID = events[index].source.organizationId
        pendingCancellationIDs.insert(eventID)
        defer { pendingCancellationIDs.remove(eventID) }

        do {
            try await repository.cancelEventRegistration(id: eventID)
            ActivityLogRecorder.recordEvent(event, actionType: .canceledEventRegistration)
            events.removeAll { $0.id == eventID }
            error = nil
            AppContentChangeBus.postEventsChanged(organizationID: organizationID)
            AppContentChangeBus.postRegistrationsChanged(organizationID: organizationID)
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
    @Published private(set) var pendingOrganizationBookmarkIDs = Set<String>()
    @Published private(set) var pendingOrganizationDeleteIDs = Set<String>()
    @Published private(set) var isSavingOrganization = false
    @Published private(set) var isUploadingOrganizationImage = false
    @Published private(set) var validationErrorMessage: String?
    private let repository: OrganizationRepository
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false
    private var lastLoadedAt: Date?

    init(repository: OrganizationRepository) {
        self.repository = repository
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
        pendingOrganizationBookmarkIDs = []
        pendingOrganizationDeleteIDs = []
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
        let organization = organizations[index]
        let previousLikeState = organizations[index].likeState
        let previousSubscriberCount = organizations[index].subscriberCount

        organizations[index].likeState = shouldLike ? .liked : .notLiked
        organizations[index].subscriberCount = max(0, previousSubscriberCount + (shouldLike ? 1 : -1))

        Task {
            pendingOrganizationLikeIDs.insert(organizationID)
            defer { pendingOrganizationLikeIDs.remove(organizationID) }

            do {
                if shouldLike {
                    try await repository.likeOrganization(id: organizationID)
                } else {
                    try await repository.unlikeOrganization(id: organizationID)
                }

                ActivityLogRecorder.recordOrganization(organization, actionType: shouldLike ? .followedOrganization : .unfollowedOrganization)
                error = nil
                AppContentChangeBus.postOrganizationsChanged(organizationID: organizationID)
            } catch let appError as AppError {
                organizations[index].likeState = previousLikeState
                organizations[index].subscriberCount = previousSubscriberCount
                error = appError
            } catch {
                organizations[index].likeState = previousLikeState
                organizations[index].subscriberCount = previousSubscriberCount
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
                AppContentChangeBus.postOrganizationsChanged(organizationID: organizationID)
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
                createdAt: organization.createdAt,
                updatedAt: organization.updatedAt,
                moderationStatus: organization.moderationStatus,
                likeCount: organization.likeCount,
                likeState: organization.likeState,
                isBookmarked: organization.isBookmarked
            )

            if isEditing {
                try await repository.updateOrganization(organizationToSave)
                replaceOrganization(organizationToSave)
            } else {
                try await repository.createOrganization(organizationToSave)
                organizations.insert(organizationToSave, at: 0)
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

    private func replaceOrganization(_ organization: Organization) {
        guard let index = organizations.firstIndex(where: { $0.id == organization.id }) else { return }
        organizations[index] = organization
    }
}

@MainActor
final class InfoViewModel: ObservableObject {
    @Published private(set) var articles: [GuideArticle]
    @Published private(set) var error: AppError?
    @Published private(set) var isLoading: Bool
    private let repository: InfoRepository
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false
    private var lastLoadedAt: Date?

    init(repository: InfoRepository) {
        self.repository = repository
        articles = []
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
            articles = try await repository.fetchGuideArticles()
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
final class ProfileViewModel: ObservableObject {
    @Published private(set) var user: AppUser
    @Published var settings: UserSettings
    @Published private(set) var error: AppError?
    @Published private(set) var isSavingProfile = false
    @Published private(set) var isSubmittingFeedback = false
    @Published private(set) var isLoading = false
    @Published var profileMessage: String?
    @Published var feedbackMessage: String?
    private let repository: UserRepository
    private let feedbackRepository: FeedbackRepository
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false
    private var lastLoadedAt: Date?

    init(repository: UserRepository, feedbackRepository: FeedbackRepository) {
        self.repository = repository
        self.feedbackRepository = feedbackRepository
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
        isLoading = false
        profileMessage = nil
        feedbackMessage = nil
        hasLoaded = false
        lastLoadedAt = nil
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
            try await feedbackRepository.submitFeedback(FeedbackItem(
                id: UUID().uuidString,
                type: type,
                message: trimmedMessage,
                status: .open,
                createdAt: .now,
                userId: user.id,
                userDisplayName: user.preferredDisplayName
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
final class FeedbackInboxViewModel: ObservableObject {
    @Published private(set) var items: [FeedbackItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?
    @Published private(set) var updatingFeedbackIDs = Set<String>()

    private let repository: FeedbackRepository
    private var hasLoaded = false

    init(repository: FeedbackRepository) {
        self.repository = repository
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await refresh()
    }

    func refresh() async {
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
        await update(item, status: .reviewed)
    }

    func archive(_ item: FeedbackItem) async {
        await update(item, status: .archived)
    }

    private func update(_ item: FeedbackItem, status: FeedbackStatus) async {
        guard !updatingFeedbackIDs.contains(item.id) else { return }
        updatingFeedbackIDs.insert(item.id)
        defer { updatingFeedbackIDs.remove(item.id) }

        do {
            try await repository.updateFeedbackStatus(id: item.id, status: status)
            items = items.map { current in
                guard current.id == item.id else { return current }
                return FeedbackItem(
                    id: current.id,
                    type: current.type,
                    message: current.message,
                    status: status,
                    createdAt: current.createdAt,
                    userId: current.userId,
                    userDisplayName: current.userDisplayName
                )
            }
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }
}
