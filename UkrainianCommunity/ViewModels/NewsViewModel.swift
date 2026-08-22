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
        loadTask?.cancel()
        nextPageTask?.cancel()
        loadTask = nil
        nextPageTask = nil
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

    func toggleLike(for postID: String) {
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }
        guard !pendingNewsLikeIDs.contains(postID) else { return }
        let shouldLike = posts[index].likeState == .notLiked
        let post = posts[index]

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
                contentVersion &+= 1
                if shouldLike {
                    analyticsService.track(.newsLike(post: post))
                }
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

    func trackViewIfNeeded(for post: NewsPost, sourceScreen: String = "news_detail") {
        guard !trackedNewsViewIDs.contains(post.id) else { return }
        trackedNewsViewIDs.insert(post.id)
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

        posts[index].isBookmarked = shouldBookmark
        contentVersion &+= 1

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
                if shouldBookmark {
                    analyticsService.track(.newsBookmark(post: post))
                }
                error = nil
            } catch let appError as AppError {
                posts[index].isBookmarked.toggle()
                contentVersion &+= 1
                error = appError
            } catch {
                posts[index].isBookmarked.toggle()
                contentVersion &+= 1
                self.error = .unknown
            }
        }
    }

    func loadComments(for postID: String, forceRefresh: Bool = false) async {
        startListeningComments(for: postID)
        guard forceRefresh || !(repository is NewsRealtimeRepository) else { return }
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }

        do {
            let comments = try await repository.fetchNewsComments(newsID: postID)
            let visibleComments = comments.deduplicatedCommentsByID()
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
            let visibleComments = comments.deduplicatedCommentsByID()
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
            posts[index].comments.upsertCommentByID(comment)
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
            posts[postIndex].comments = posts[postIndex].comments.deduplicatedCommentsByID()
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
            posts.removeAll { $0.id == id }
            contentVersion &+= 1
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
        contentVersion &+= 1
    }

    func loadNextPageIfNeeded(currentItemID: String? = nil) async {
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
            await self.performLoadNextPage()
        }
        nextPageTask = task
        await task.value
        nextPageTask = nil
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

    private func performLoad() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let page = try await repository.fetchNewsPage(limit: publicFeedPageSize, after: nil)
            guard !Task.isCancelled else { return }
            posts = page.items
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
            let page = try await repository.fetchNewsPage(limit: publicFeedPageSize, after: nextPageCursor)
            guard !Task.isCancelled else { return }
            appendUniquePosts(page.items)
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

    private func appendUniquePosts(_ newPosts: [NewsPost]) {
        let existingIDs = Set(posts.map(\.id))
        posts.append(contentsOf: newPosts.filter { !existingIDs.contains($0.id) })
    }
}
