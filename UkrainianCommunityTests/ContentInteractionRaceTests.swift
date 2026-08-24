import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct ContentInteractionRaceTests {
    @Test func newsLikeRejectsTwoSynchronousInvocations() async {
        let repository = ControlledNewsRepository()
        let viewModel = NewsViewModel(repository: repository)
        let post = makeNewsPost(id: "news-double-tap")
        viewModel.posts = [post]

        viewModel.toggleLike(for: post.id)
        #expect(viewModel.pendingNewsLikeIDs == [post.id])
        viewModel.toggleLike(for: post.id)

        #expect(await eventually { repository.likeRequestCount == 1 })
        #expect(repository.likeRequestCount == 1)

        repository.completeLikeRequest(1)
        #expect(await eventually { viewModel.pendingNewsLikeIDs.isEmpty })
        #expect(viewModel.post(for: post.id)?.likeState == .liked)
        #expect(viewModel.post(for: post.id)?.likeCount == 1)
    }

    @Test func newsLikeResolvesCurrentIndexAfterRefreshReordersPosts() async {
        let repository = ControlledNewsRepository()
        let viewModel = NewsViewModel(repository: repository)
        let target = makeNewsPost(id: "news-target")
        let other = makeNewsPost(id: "news-other", likeCount: 7)
        viewModel.posts = [target, other]

        viewModel.toggleLike(for: target.id)
        #expect(await eventually { repository.likeRequestCount == 1 })

        repository.news = [other, target]
        await viewModel.refresh()
        #expect(viewModel.posts.map(\.id) == [other.id, target.id])

        repository.completeLikeRequest(1)
        #expect(await eventually { viewModel.pendingNewsLikeIDs.isEmpty })
        #expect(viewModel.post(for: target.id)?.likeState == .liked)
        #expect(viewModel.post(for: target.id)?.likeCount == 1)
        #expect(viewModel.post(for: other.id)?.likeState == .notLiked)
        #expect(viewModel.post(for: other.id)?.likeCount == 7)
    }

    @Test func newsLikeDoesNotDoubleApplyStateAlreadyLoadedByRefresh() async {
        let repository = ControlledNewsRepository()
        let viewModel = NewsViewModel(repository: repository)
        let contentID = "news-server-like"
        viewModel.posts = [makeNewsPost(id: contentID)]

        viewModel.toggleLike(for: contentID)
        #expect(await eventually { repository.likeRequestCount == 1 })

        repository.news = [makeNewsPost(id: contentID, likeState: .liked, likeCount: 1)]
        await viewModel.refresh()
        repository.completeLikeRequest(1)

        #expect(await eventually { viewModel.pendingNewsLikeIDs.isEmpty })
        #expect(viewModel.post(for: contentID)?.likeState == .liked)
        #expect(viewModel.post(for: contentID)?.likeCount == 1)
    }

    @Test func newsLikeIgnoresCompletionAfterRefreshRemovesPost() async {
        let repository = ControlledNewsRepository()
        let viewModel = NewsViewModel(repository: repository)
        let post = makeNewsPost(id: "news-removed")
        viewModel.posts = [post]

        viewModel.toggleLike(for: post.id)
        #expect(await eventually { repository.likeRequestCount == 1 })

        repository.news = []
        await viewModel.refresh()
        repository.completeLikeRequest(1)

        #expect(await eventually { viewModel.pendingNewsLikeIDs.isEmpty })
        #expect(viewModel.posts.isEmpty)
    }

    @Test func newsUnlikeClampsCounterAtZero() async {
        let repository = ControlledNewsRepository()
        let viewModel = NewsViewModel(repository: repository)
        let post = makeNewsPost(id: "news-zero", likeState: .liked, likeCount: 0)
        viewModel.posts = [post]

        viewModel.toggleLike(for: post.id)
        #expect(await eventually { repository.likeRequestCount == 1 })
        repository.completeLikeRequest(1)

        #expect(await eventually { viewModel.pendingNewsLikeIDs.isEmpty })
        #expect(viewModel.post(for: post.id)?.likeState == .notLiked)
        #expect(viewModel.post(for: post.id)?.likeCount == 0)
    }

    @Test func newsViewDoesNotDoubleApplyCountAlreadyLoadedByRefresh() async {
        let repository = ControlledNewsRepository()
        let viewModel = NewsViewModel(repository: repository)
        let contentID = "news-server-view"
        viewModel.posts = [makeNewsPost(id: contentID)]

        viewModel.recordView(for: contentID)
        #expect(await eventually { repository.viewRequestCount == 1 })

        repository.news = [makeNewsPost(id: contentID, viewCount: 1)]
        await viewModel.refresh()
        repository.completeViewRequest(1, didRecord: true)

        #expect(await eventually { viewModel.pendingNewsViewIDs.isEmpty })
        #expect(viewModel.post(for: contentID)?.viewCount == 1)
    }

    @Test func newsBookmarkFailureDoesNotOverwriteStateLoadedByRefresh() async {
        let repository = ControlledNewsRepository()
        let viewModel = NewsViewModel(repository: repository)
        let contentID = "news-server-bookmark"
        viewModel.posts = [makeNewsPost(id: contentID)]

        viewModel.toggleBookmark(for: contentID)
        #expect(await eventually { repository.bookmarkRequestCount == 1 })

        repository.news = [makeNewsPost(id: contentID, isBookmarked: true)]
        await viewModel.refresh()
        repository.completeBookmarkRequest(1, error: .network)

        #expect(await eventually { viewModel.pendingNewsBookmarkIDs.isEmpty })
        #expect(viewModel.post(for: contentID)?.isBookmarked == true)
        #expect(viewModel.error == .network)
    }

    @Test func oldNewsTaskCannotMutateOrClearPendingForSameIDInNewSession() async {
        let repository = ControlledNewsRepository()
        let viewModel = NewsViewModel(repository: repository)
        let contentID = "news-shared-id"
        viewModel.posts = [makeNewsPost(id: contentID)]

        viewModel.toggleLike(for: contentID)
        #expect(await eventually { repository.likeRequestCount == 1 })

        viewModel.resetForAuthChange()
        viewModel.posts = [makeNewsPost(id: contentID, likeCount: 40)]
        viewModel.toggleLike(for: contentID)
        #expect(await eventually { repository.likeRequestCount == 2 })
        #expect(viewModel.pendingNewsLikeIDs == [contentID])

        repository.completeLikeRequest(1)
        #expect(await eventually { repository.completedLikeRequestCount == 1 })
        #expect(viewModel.pendingNewsLikeIDs == [contentID])
        #expect(viewModel.post(for: contentID)?.likeState == .notLiked)
        #expect(viewModel.post(for: contentID)?.likeCount == 40)

        repository.completeLikeRequest(2)
        #expect(await eventually { viewModel.pendingNewsLikeIDs.isEmpty })
        #expect(viewModel.post(for: contentID)?.likeState == .liked)
        #expect(viewModel.post(for: contentID)?.likeCount == 41)
    }

    @Test func newsCommentDeleteDoesNotDoubleDecrementCountAfterRefresh() async {
        let repository = ControlledNewsRepository()
        let viewModel = NewsViewModel(repository: repository)
        let contentID = "news-comment-refresh"
        let deletedComment = makeComment(id: "comment-deleted")
        let remainingComment = makeComment(id: "comment-remaining")
        viewModel.posts = [makeNewsPost(
            id: contentID,
            comments: [deletedComment, remainingComment],
            commentCount: 2
        )]

        let deletionTask = Task {
            await viewModel.deleteComment(postID: contentID, commentID: deletedComment.id)
        }
        #expect(await eventually { repository.commentDeleteRequestCount == 1 })

        repository.news = [makeNewsPost(
            id: contentID,
            comments: [remainingComment],
            commentCount: 1
        )]
        await viewModel.refresh()
        repository.completeCommentDeleteRequest(1)
        await deletionTask.value

        #expect(viewModel.post(for: contentID)?.comments.map(\.id) == [remainingComment.id])
        #expect(viewModel.post(for: contentID)?.commentCount == 1)
    }

    @Test func organizationLikeRejectsTwoSynchronousInvocations() async {
        let repository = ControlledOrganizationRepository()
        let viewModel = OrganizationsViewModel(repository: repository)
        let organization = makeOrganization(id: "organization-double-tap")
        viewModel.organizations = [organization]

        viewModel.toggleLike(for: organization.id)
        #expect(viewModel.pendingOrganizationLikeIDs == [organization.id])
        viewModel.toggleLike(for: organization.id)

        #expect(await eventually { repository.likeRequestCount == 1 })
        #expect(repository.likeRequestCount == 1)
        repository.completeLikeRequest(1)

        #expect(await eventually { viewModel.pendingOrganizationLikeIDs.isEmpty })
        #expect(viewModel.organization(for: organization.id)?.likeState == .liked)
        #expect(viewModel.organization(for: organization.id)?.likeCount == 1)
    }

    @Test func organizationLikeRollbackResolvesCurrentIndexAfterReorder() async {
        let repository = ControlledOrganizationRepository()
        let viewModel = OrganizationsViewModel(repository: repository)
        let target = makeOrganization(id: "organization-target")
        let other = makeOrganization(id: "organization-other", likeCount: 8)
        viewModel.organizations = [target, other]

        viewModel.toggleLike(for: target.id)
        #expect(await eventually { repository.likeRequestCount == 1 })

        let optimisticTarget = makeOrganization(id: target.id, likeState: .liked, likeCount: 1)
        viewModel.organizations = [other, optimisticTarget]
        #expect(viewModel.organizations.map(\.id) == [other.id, target.id])

        repository.completeLikeRequest(1, error: .network)
        #expect(await eventually { viewModel.pendingOrganizationLikeIDs.isEmpty })
        #expect(viewModel.organization(for: target.id)?.likeState == .notLiked)
        #expect(viewModel.organization(for: target.id)?.likeCount == 0)
        #expect(viewModel.organization(for: other.id)?.likeState == .notLiked)
        #expect(viewModel.organization(for: other.id)?.likeCount == 8)
        #expect(viewModel.error == .network)
    }

    @Test func organizationLikeFailureDoesNotOverwriteStateLoadedByRefresh() async {
        let repository = ControlledOrganizationRepository()
        let viewModel = OrganizationsViewModel(repository: repository)
        let contentID = "organization-server-like"
        viewModel.organizations = [makeOrganization(id: contentID)]

        viewModel.toggleLike(for: contentID)
        #expect(await eventually { repository.likeRequestCount == 1 })

        repository.organizations = [makeOrganization(id: contentID, likeState: .liked, likeCount: 1)]
        await viewModel.refresh()
        repository.completeLikeRequest(1, error: .network)

        #expect(await eventually { viewModel.pendingOrganizationLikeIDs.isEmpty })
        #expect(viewModel.organization(for: contentID)?.likeState == .liked)
        #expect(viewModel.organization(for: contentID)?.likeCount == 1)
        #expect(viewModel.error == .network)
    }

    @Test func oldOrganizationTaskCannotClearPendingForSameIDInNewSession() async {
        let repository = ControlledOrganizationRepository()
        let viewModel = OrganizationsViewModel(repository: repository)
        let contentID = "organization-shared-id"
        viewModel.organizations = [makeOrganization(id: contentID)]

        viewModel.toggleLike(for: contentID)
        #expect(await eventually { repository.likeRequestCount == 1 })

        viewModel.resetForAuthChange()
        viewModel.organizations = [makeOrganization(id: contentID, likeCount: 20)]
        viewModel.toggleLike(for: contentID)
        #expect(await eventually { repository.likeRequestCount == 2 })
        #expect(viewModel.pendingOrganizationLikeIDs == [contentID])
        #expect(viewModel.organization(for: contentID)?.likeCount == 21)

        repository.completeLikeRequest(1)
        #expect(await eventually { repository.completedLikeRequestCount == 1 })
        #expect(viewModel.pendingOrganizationLikeIDs == [contentID])
        #expect(viewModel.organization(for: contentID)?.likeState == .liked)
        #expect(viewModel.organization(for: contentID)?.likeCount == 21)

        repository.completeLikeRequest(2)
        #expect(await eventually { viewModel.pendingOrganizationLikeIDs.isEmpty })
        #expect(viewModel.organization(for: contentID)?.likeState == .liked)
        #expect(viewModel.organization(for: contentID)?.likeCount == 21)
    }

    private func makeNewsPost(
        id: String,
        likeState: LikeState = .notLiked,
        likeCount: Int = 0,
        viewCount: Int = 0,
        isBookmarked: Bool = false,
        comments: [UkrainianCommunity.Comment] = [],
        commentCount: Int? = nil
    ) -> NewsPost {
        NewsPost(
            id: id,
            title: id,
            subtitle: "Subtitle",
            city: "Vienna",
            body: "Body",
            authorName: "Author",
            publishedAt: .now,
            createdAt: .now,
            updatedAt: .now,
            comments: comments,
            moderationStatus: .approved,
            likeCount: likeCount,
            likeState: likeState,
            viewCount: viewCount,
            isBookmarked: isBookmarked,
            commentCount: commentCount
        )
    }

    private func makeComment(id: String) -> UkrainianCommunity.Comment {
        UkrainianCommunity.Comment(
            id: id,
            authorName: "Author",
            body: id,
            createdAt: .now
        )
    }

    private func makeOrganization(
        id: String,
        likeState: LikeState = .notLiked,
        likeCount: Int = 0
    ) -> Organization {
        Organization(
            id: id,
            name: id,
            description: "Description",
            city: "Vienna",
            createdAt: .now,
            updatedAt: .now,
            moderationStatus: .approved,
            likeCount: likeCount,
            likeState: likeState
        )
    }

    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<1_000 {
            if condition() {
                return true
            }
            await Task.yield()
        }
        return condition()
    }
}

@MainActor
private final class ControlledNewsRepository: NewsRepository {
    var news: [NewsPost] = []
    private(set) var likeRequestCount = 0
    private(set) var completedLikeRequestCount = 0
    private(set) var viewRequestCount = 0
    private(set) var bookmarkRequestCount = 0
    private(set) var commentDeleteRequestCount = 0
    private var likeContinuations: [Int: CheckedContinuation<Void, Error>] = [:]
    private var viewContinuations: [Int: CheckedContinuation<Bool, Error>] = [:]
    private var bookmarkContinuations: [Int: CheckedContinuation<Void, Error>] = [:]
    private var commentDeleteContinuations: [Int: CheckedContinuation<Void, Error>] = [:]

    func fetchNews() async throws -> [NewsPost] { news }
    func fetchPendingNews() async throws -> [NewsPost] { [] }
    func fetchOrganizationModerationNews(organizationID: String) async throws -> [NewsPost] { [] }
    func fetchOrganizationNewsCount(organizationID: String) async throws -> Int { 0 }
    func createNews(_ news: NewsPost) async throws {}
    func updateNews(_ news: NewsPost) async throws {}
    func updateNewsImageURL(id: String, imageURL: String?) async throws {}
    func deleteNews(id: String) async throws {}

    func likeNews(id: String, actionCapture: AnalyticsActionCapture?) async throws {
        try await suspendLikeRequest()
    }

    func unlikeNews(id: String) async throws {
        try await suspendLikeRequest()
    }

    func recordNewsView(id: String) async throws -> Bool {
        viewRequestCount += 1
        let requestNumber = viewRequestCount
        return try await withCheckedThrowingContinuation { continuation in
            viewContinuations[requestNumber] = continuation
        }
    }
    func fetchNewsComments(newsID: String) async throws -> [UkrainianCommunity.Comment] { [] }
    func addNewsComment(newsID: String, text: String, author: AppUser) async throws -> UkrainianCommunity.Comment {
        UkrainianCommunity.Comment(id: UUID().uuidString, authorName: author.preferredDisplayName, body: text, createdAt: .now)
    }
    func updateNewsComment(newsID: String, commentID: String, text: String) async throws -> UkrainianCommunity.Comment {
        UkrainianCommunity.Comment(id: commentID, authorName: "Author", body: text, createdAt: .now)
    }
    func deleteNewsComment(newsID: String, commentID: String) async throws {
        commentDeleteRequestCount += 1
        let requestNumber = commentDeleteRequestCount
        try await withCheckedThrowingContinuation { continuation in
            commentDeleteContinuations[requestNumber] = continuation
        }
    }
    func bookmarkNews(id: String, actionCapture: AnalyticsActionCapture?) async throws {
        try await suspendBookmarkRequest()
    }
    func unbookmarkNews(id: String) async throws {
        try await suspendBookmarkRequest()
    }
    func updateModerationStatus(id: String, newStatus: ModerationStatus) async throws {}

    func completeLikeRequest(_ requestNumber: Int, error: AppError? = nil) {
        guard let continuation = likeContinuations.removeValue(forKey: requestNumber) else {
            Issue.record("Missing news like continuation \(requestNumber)")
            return
        }
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume(returning: ())
        }
    }

    func completeViewRequest(_ requestNumber: Int, didRecord: Bool, error: AppError? = nil) {
        guard let continuation = viewContinuations.removeValue(forKey: requestNumber) else {
            Issue.record("Missing news view continuation \(requestNumber)")
            return
        }
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume(returning: didRecord)
        }
    }

    func completeBookmarkRequest(_ requestNumber: Int, error: AppError? = nil) {
        guard let continuation = bookmarkContinuations.removeValue(forKey: requestNumber) else {
            Issue.record("Missing news bookmark continuation \(requestNumber)")
            return
        }
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume(returning: ())
        }
    }

    func completeCommentDeleteRequest(_ requestNumber: Int, error: AppError? = nil) {
        guard let continuation = commentDeleteContinuations.removeValue(forKey: requestNumber) else {
            Issue.record("Missing news comment delete continuation \(requestNumber)")
            return
        }
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume(returning: ())
        }
    }

    private func suspendLikeRequest() async throws {
        likeRequestCount += 1
        let requestNumber = likeRequestCount
        defer { completedLikeRequestCount += 1 }
        try await withCheckedThrowingContinuation { continuation in
            likeContinuations[requestNumber] = continuation
        }
    }

    private func suspendBookmarkRequest() async throws {
        bookmarkRequestCount += 1
        let requestNumber = bookmarkRequestCount
        try await withCheckedThrowingContinuation { continuation in
            bookmarkContinuations[requestNumber] = continuation
        }
    }
}

@MainActor
private final class ControlledOrganizationRepository: OrganizationRepository {
    var organizations: [Organization] = []
    private(set) var likeRequestCount = 0
    private(set) var completedLikeRequestCount = 0
    private var likeContinuations: [Int: CheckedContinuation<Void, Error>] = [:]

    func fetchOrganizations() async throws -> [Organization] { organizations }
    func fetchOrganization(id: String) async throws -> Organization {
        guard let organization = organizations.first(where: { $0.id == id }) else {
            throw AppError.notFound
        }
        return organization
    }
    func fetchPendingOrganizations() async throws -> [Organization] { [] }
    func fetchOrganizationRequests(submittedByUserID: String) async throws -> [Organization] { [] }
    func createOrganization(_ organization: Organization) async throws {}
    func updateOrganization(_ organization: Organization) async throws {}
    func deleteOrganization(id: String) async throws {}
    func uploadOrganizationImage(data: Data, organizationID: String) async throws -> URL {
        URL(string: "https://example.com/\(organizationID).jpg")!
    }

    func likeOrganization(id: String) async throws {
        try await suspendLikeRequest()
    }

    func unlikeOrganization(id: String) async throws {
        try await suspendLikeRequest()
    }

    func subscribeOrganization(id: String, actionCapture: AnalyticsActionCapture?) async throws {}
    func unsubscribeOrganization(id: String) async throws {}
    func fetchOrganizationSubscriberPage(
        organizationID: String,
        limit: Int,
        after cursor: OrganizationSubscriberCursor?
    ) async throws -> OrganizationSubscriberPage {
        OrganizationSubscriberPage(items: [], nextCursor: nil, hasMore: false)
    }
    func fetchPublicUserProfiles(userIDs: [String]) async throws -> [PublicUserProfile] { [] }
    func fetchOrganizationComments(organizationID: String) async throws -> [UkrainianCommunity.Comment] { [] }
    func addOrganizationComment(organizationID: String, text: String, author: AppUser) async throws -> UkrainianCommunity.Comment {
        UkrainianCommunity.Comment(id: UUID().uuidString, authorName: author.preferredDisplayName, body: text, createdAt: .now)
    }
    func updateOrganizationComment(organizationID: String, commentID: String, text: String) async throws -> UkrainianCommunity.Comment {
        UkrainianCommunity.Comment(id: commentID, authorName: "Author", body: text, createdAt: .now)
    }
    func deleteOrganizationComment(organizationID: String, commentID: String) async throws {}
    func bookmarkOrganization(id: String, actionCapture: AnalyticsActionCapture?) async throws {}
    func unbookmarkOrganization(id: String) async throws {}
    func isOrganizationBookmarked(id: String) async throws -> Bool { false }
    func fetchBookmarkedOrganizationIDs() async throws -> Set<String> { [] }
    func updateModerationStatus(id: String, newStatus: ModerationStatus) async throws {}
    func approveOrganizationRequest(id: String, reviewerID: String) async throws {}
    func requestOrganizationRevision(id: String, message: String, reviewerID: String) async throws {}
    func rejectOrganizationRequest(id: String, reason: String, reviewerID: String) async throws {}

    func completeLikeRequest(_ requestNumber: Int, error: AppError? = nil) {
        guard let continuation = likeContinuations.removeValue(forKey: requestNumber) else {
            Issue.record("Missing organization like continuation \(requestNumber)")
            return
        }
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume(returning: ())
        }
    }

    private func suspendLikeRequest() async throws {
        likeRequestCount += 1
        let requestNumber = likeRequestCount
        defer { completedLikeRequestCount += 1 }
        try await withCheckedThrowingContinuation { continuation in
            likeContinuations[requestNumber] = continuation
        }
    }
}
