import Combine
import Foundation

@MainActor
final class NewsViewModel: ObservableObject {
    @Published var posts: [NewsPost]
    @Published private(set) var isLoading: Bool
    @Published private(set) var error: AppError?
    @Published private(set) var isLoadingNextPage = false
    @Published private(set) var hasMorePages = false
    @Published private(set) var contentVersion = 0
    @Published private(set) var pendingNewsLikeIDs = Set<String>()
    @Published private(set) var pendingNewsBookmarkIDs = Set<String>()
    @Published private(set) var pendingNewsViewIDs = Set<String>()
    @Published private(set) var pendingNewsCommentIDs = Set<String>()
    private let repository: NewsRepository
    private let analyticsService: AnalyticsTracking
    private let listenerBag = RealtimeListenerBag()
    private var loadTask: Task<Void, Never>?
    private var nextPageTask: Task<Void, Never>?
    private var hasLoaded = false
    private var lastLoadedAt: Date?
    private var nextPageCursor: NewsPageCursor?
    private var trackedNewsViewIDs = Set<String>()
    private var visibilityPolicy = ContentVisibilityPolicy()
    private var authGeneration: UInt = 0
    private var feedRevision: UInt = 0
    private var interactionTasks: [String: Task<Void, Never>] = [:]

    init(repository: NewsRepository, analyticsService: AnalyticsTracking = NoopAnalyticsService()) {
        self.repository = repository
        self.analyticsService = analyticsService
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
        authGeneration &+= 1
        feedRevision &+= 1
        loadTask?.cancel()
        nextPageTask?.cancel()
        interactionTasks.values.forEach { $0.cancel() }
        loadTask = nil
        nextPageTask = nil
        interactionTasks.removeAll()
        posts = []
        isLoading = false
        isLoadingNextPage = false
        hasMorePages = false
        error = nil
        contentVersion &+= 1
        pendingNewsLikeIDs = []
        pendingNewsBookmarkIDs = []
        pendingNewsViewIDs = []
        pendingNewsCommentIDs = []
        trackedNewsViewIDs = []
        listenerBag.removeAll()
        hasLoaded = false
        lastLoadedAt = nil
        nextPageCursor = nil
    }

    var bookmarkedPosts: [NewsPost] {
        posts.filter(\.isBookmarked)
    }

    func applyContentVisibility(_ policy: ContentVisibilityPolicy) {
        visibilityPolicy = policy
        posts = policy.visibleNews(posts)
        contentVersion &+= 1
    }

    func toggleLike(for postID: String) {
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }
        guard !pendingNewsLikeIDs.contains(postID) else { return }
        let shouldLike = posts[index].likeState == .notLiked
        let previousLikeState = posts[index].likeState
        let targetLikeState: LikeState = shouldLike ? .liked : .notLiked
        let post = posts[index]
        let actionEvent = AppAnalyticsEvent.newsLike(post: post)
        let actionCapture = shouldLike ? analyticsService.actionCapture(for: actionEvent) : nil
        let generation = authGeneration
        let taskKey = "like:\(postID)"

        pendingNewsLikeIDs.insert(postID)
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.isCurrentAuthGeneration(generation) {
                    self.pendingNewsLikeIDs.remove(postID)
                    self.interactionTasks[taskKey] = nil
                }
            }

            do {
                if shouldLike {
                    try await repository.likeNews(id: postID, actionCapture: actionCapture)
                } else {
                    try await repository.unlikeNews(id: postID)
                }

                guard isCurrentAuthGeneration(generation),
                      let currentIndex = posts.firstIndex(where: { $0.id == postID }) else { return }
                if posts[currentIndex].likeState == previousLikeState {
                    posts[currentIndex].likeState = targetLikeState
                    posts[currentIndex].likeCount = max(0, posts[currentIndex].likeCount + (shouldLike ? 1 : -1))
                    contentVersion &+= 1
                }
                if shouldLike {
                    analyticsService.track(actionEvent, actionCapture: actionCapture)
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
        interactionTasks[taskKey] = task
    }

    func recordView(for postID: String) {
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }
        guard !pendingNewsViewIDs.contains(postID) else { return }
        let previousViewCount = posts[index].viewCount
        let generation = authGeneration
        let taskKey = "view:\(postID)"

        pendingNewsViewIDs.insert(postID)
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.isCurrentAuthGeneration(generation) {
                    self.pendingNewsViewIDs.remove(postID)
                    self.interactionTasks[taskKey] = nil
                }
            }

            do {
                if try await repository.recordNewsView(id: postID) {
                    guard isCurrentAuthGeneration(generation),
                          let currentIndex = posts.firstIndex(where: { $0.id == postID }) else { return }
                    if posts[currentIndex].viewCount == previousViewCount {
                        posts[currentIndex].viewCount += 1
                    }
                } else {
                    guard isCurrentAuthGeneration(generation) else { return }
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
        interactionTasks[taskKey] = task
    }

    func trackViewIfNeeded(for post: NewsPost, sourceScreen: String = "news_detail") {
        guard let collectionScopeID = analyticsService.collectionScopeID else { return }
        let trackingKey = AnalyticsTrackingKey.daily(
            contentID: post.id,
            collectionScopeID: collectionScopeID
        )
        guard !trackedNewsViewIDs.contains(trackingKey) else { return }
        trackedNewsViewIDs.insert(trackingKey)
        analyticsService.track(.newsView(
            contentID: post.id,
            contentTitle: post.title,
            category: post.category,
            federalState: post.federalState,
            regionScope: post.regionScope,
            organizationID: post.source.organizationId,
            sourceScreen: sourceScreen
        ))
    }

    func toggleBookmark(for postID: String) {
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }
        guard !pendingNewsBookmarkIDs.contains(postID) else { return }
        let shouldBookmark = !posts[index].isBookmarked
        let post = posts[index]
        let actionEvent = AppAnalyticsEvent.newsBookmark(post: post)
        let actionCapture = shouldBookmark ? analyticsService.actionCapture(for: actionEvent) : nil
        let previousBookmarkState = posts[index].isBookmarked
        let generation = authGeneration
        let requestFeedRevision = feedRevision
        let taskKey = "bookmark:\(postID)"

        pendingNewsBookmarkIDs.insert(postID)
        posts[index].isBookmarked = shouldBookmark
        contentVersion &+= 1

        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.isCurrentAuthGeneration(generation) {
                    self.pendingNewsBookmarkIDs.remove(postID)
                    self.interactionTasks[taskKey] = nil
                }
            }

            do {
                if shouldBookmark {
                    try await repository.bookmarkNews(id: postID, actionCapture: actionCapture)
                } else {
                    try await repository.unbookmarkNews(id: postID)
                }
                guard isCurrentAuthGeneration(generation),
                      let currentIndex = posts.firstIndex(where: { $0.id == postID }) else { return }
                if posts[currentIndex].isBookmarked == previousBookmarkState {
                    posts[currentIndex].isBookmarked = shouldBookmark
                    contentVersion &+= 1
                }
                ActivityLogRecorder.recordNews(post, actionType: shouldBookmark ? .savedNews : .unsavedNews)
                if shouldBookmark {
                    analyticsService.track(actionEvent, actionCapture: actionCapture)
                }
                error = nil
            } catch let appError as AppError {
                guard isCurrentAuthGeneration(generation) else { return }
                rollbackBookmark(
                    postID: postID,
                    optimisticState: shouldBookmark,
                    previousState: previousBookmarkState,
                    requestFeedRevision: requestFeedRevision
                )
                error = appError
            } catch {
                guard isCurrentAuthGeneration(generation) else { return }
                rollbackBookmark(
                    postID: postID,
                    optimisticState: shouldBookmark,
                    previousState: previousBookmarkState,
                    requestFeedRevision: requestFeedRevision
                )
                self.error = .unknown
            }
        }
        interactionTasks[taskKey] = task
    }

    func loadComments(for postID: String, forceRefresh: Bool = false) async {
        let generation = authGeneration
        startListeningComments(for: postID)
        guard forceRefresh || !(repository is NewsRealtimeRepository) else { return }
        guard posts.contains(where: { $0.id == postID }) else { return }

        do {
            let comments = try await repository.fetchNewsComments(newsID: postID)
            guard isCurrentAuthGeneration(generation),
                  let currentIndex = posts.firstIndex(where: { $0.id == postID }) else { return }
            let visibleComments = visibilityPolicy.visibleComments(comments.deduplicatedCommentsByID())
            posts[currentIndex].comments = visibleComments
            posts[currentIndex].commentCount = visibleComments.filter { !$0.isDeleted }.count
            error = nil
        } catch let appError as AppError {
            guard isCurrentAuthGeneration(generation) else { return }
            error = appError
        } catch {
            guard isCurrentAuthGeneration(generation) else { return }
            self.error = .unknown
        }
    }

    func stopListeningComments(for postID: String) {
        listenerBag.remove("newsComments:\(postID)")
    }

    private func startListeningComments(for postID: String) {
        let key = "newsComments:\(postID)"
        let generation = authGeneration
        guard !listenerBag.contains(key),
              let realtimeRepository = repository as? NewsRealtimeRepository else { return }

        listenerBag.set(realtimeRepository.listenNewsComments(newsID: postID) { [weak self] comments in
            guard let self,
                  self.isCurrentAuthGeneration(generation),
                  let index = self.posts.firstIndex(where: { $0.id == postID }) else { return }
            let visibleComments = self.visibilityPolicy.visibleComments(comments.deduplicatedCommentsByID())
            self.posts[index].comments = visibleComments
            self.posts[index].commentCount = visibleComments.filter { !$0.isDeleted }.count
            self.error = nil
        } onError: { [weak self] appError in
            guard let self, self.isCurrentAuthGeneration(generation) else { return }
            self.listenerBag.remove(key)
            self.error = appError
            #if DEBUG
            print("Realtime listener failed: purpose=newsComments key=\(key) error=\(appError)")
            #endif
        }, for: key)
    }

    func addComment(to postID: String, text: String, author: AppUser) async {
        guard posts.contains(where: { $0.id == postID }) else { return }
        guard !pendingNewsCommentIDs.contains(postID) else { return }
        let generation = authGeneration
        pendingNewsCommentIDs.insert(postID)
        defer {
            if isCurrentAuthGeneration(generation) {
                pendingNewsCommentIDs.remove(postID)
            }
        }

        do {
            let comment = try await repository.addNewsComment(newsID: postID, text: text, author: author)
            guard isCurrentAuthGeneration(generation),
                  let currentIndex = posts.firstIndex(where: { $0.id == postID }) else { return }
            posts[currentIndex].comments.upsertCommentByID(comment)
            posts[currentIndex].commentCount = posts[currentIndex].comments.filter { !$0.isDeleted }.count
            error = nil
        } catch let appError as AppError {
            guard isCurrentAuthGeneration(generation) else { return }
            error = appError
        } catch {
            guard isCurrentAuthGeneration(generation) else { return }
            self.error = .unknown
        }
    }

    func updateComment(postID: String, commentID: String, text: String) async {
        guard let post = posts.first(where: { $0.id == postID }),
              post.comments.contains(where: { $0.id == commentID }) else {
            return
        }
        let pendingID = "\(postID)_\(commentID)"
        guard !pendingNewsCommentIDs.contains(pendingID) else { return }
        let generation = authGeneration
        pendingNewsCommentIDs.insert(pendingID)
        defer {
            if isCurrentAuthGeneration(generation) {
                pendingNewsCommentIDs.remove(pendingID)
            }
        }

        do {
            let comment = try await repository.updateNewsComment(newsID: postID, commentID: commentID, text: text)
            guard isCurrentAuthGeneration(generation),
                  let currentPostIndex = posts.firstIndex(where: { $0.id == postID }),
                  let currentCommentIndex = posts[currentPostIndex].comments.firstIndex(where: { $0.id == commentID }) else { return }
            posts[currentPostIndex].comments[currentCommentIndex] = comment
            posts[currentPostIndex].comments = posts[currentPostIndex].comments.deduplicatedCommentsByID()
            error = nil
        } catch let appError as AppError {
            guard isCurrentAuthGeneration(generation) else { return }
            error = appError
        } catch {
            guard isCurrentAuthGeneration(generation) else { return }
            self.error = .unknown
        }
    }

    func deleteComment(postID: String, commentID: String) async {
        guard posts.contains(where: { $0.id == postID }) else { return }
        let pendingID = "\(postID)_\(commentID)"
        guard !pendingNewsCommentIDs.contains(pendingID) else { return }
        let generation = authGeneration
        pendingNewsCommentIDs.insert(pendingID)
        defer {
            if isCurrentAuthGeneration(generation) {
                pendingNewsCommentIDs.remove(pendingID)
            }
        }

        do {
            try await repository.deleteNewsComment(newsID: postID, commentID: commentID)
            guard isCurrentAuthGeneration(generation),
                  let currentIndex = posts.firstIndex(where: { $0.id == postID }) else { return }
            posts[currentIndex].comments.removeAll { $0.id == commentID }
            posts[currentIndex].commentCount = posts[currentIndex].comments.filter { !$0.isDeleted }.count
            error = nil
        } catch let appError as AppError {
            guard isCurrentAuthGeneration(generation) else { return }
            error = appError
        } catch {
            guard isCurrentAuthGeneration(generation) else { return }
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
        let generation = authGeneration

        do {
            try await repository.deleteNews(id: id)
            guard isCurrentAuthGeneration(generation) else { return }
            posts.removeAll { $0.id == id }
            contentVersion &+= 1
            error = nil
            AppContentChangeBus.postNewsChanged(organizationID: organizationID)
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

    func removeDeletedNews(id: String) {
        posts.removeAll { $0.id == id }
        contentVersion &+= 1
    }

    func loadNextPageIfNeeded(currentItemID: String? = nil) async {
        let generation = authGeneration
        guard hasLoaded, hasMorePages, !isLoading, !isLoadingNextPage else { return }
        if let currentItemID, posts.suffix(5).contains(where: { $0.id == currentItemID }) == false {
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

    private func performLoad(generation: UInt) async {
        guard isCurrentAuthGeneration(generation) else { return }
        isLoading = true
        defer {
            if isCurrentAuthGeneration(generation) {
                isLoading = false
            }
        }

        do {
            let page = try await repository.fetchNewsPage(limit: publicFeedPageSize, after: nil)
            guard !Task.isCancelled, isCurrentAuthGeneration(generation) else { return }
            feedRevision &+= 1
            posts = visibilityPolicy.visibleNews(page.items)
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
            let page = try await repository.fetchNewsPage(limit: publicFeedPageSize, after: nextPageCursor)
            guard !Task.isCancelled, isCurrentAuthGeneration(generation) else { return }
            appendUniquePosts(page.items)
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

    private func appendUniquePosts(_ newPosts: [NewsPost]) {
        let existingIDs = Set(posts.map(\.id))
        posts.append(contentsOf: visibilityPolicy.visibleNews(newPosts).filter { !existingIDs.contains($0.id) })
    }

    private func rollbackBookmark(
        postID: String,
        optimisticState: Bool,
        previousState: Bool,
        requestFeedRevision: UInt
    ) {
        guard feedRevision == requestFeedRevision,
              let currentIndex = posts.firstIndex(where: { $0.id == postID }),
              posts[currentIndex].isBookmarked == optimisticState else { return }
        posts[currentIndex].isBookmarked = previousState
        contentVersion &+= 1
    }

    private func isCurrentAuthGeneration(_ generation: UInt) -> Bool {
        generation == authGeneration
    }
}
