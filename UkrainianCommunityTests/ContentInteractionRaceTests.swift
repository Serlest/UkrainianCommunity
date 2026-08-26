import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct ContentInteractionRaceTests {
    @Test func forcedNewsDetailRefreshPreservesOtherCachedPages() async {
        let repository = ControlledNewsRepository()
        let model = NewsViewModel(repository: repository)
        let old = makeNewsPost(id: "older-page", likeCount: 1)
        let other = makeNewsPost(id: "another-page")
        model.posts = [other, old]
        repository.news = [makeNewsPost(id: old.id, likeCount: 8)]
        #expect(await model.loadPostIfNeeded(postID: old.id, force: true))
        #expect(model.posts.map(\.id) == [other.id, old.id])
        #expect(model.post(for: old.id)?.likeCount == 8)
        repository.news = []
        #expect(!(await model.loadPostIfNeeded(postID: old.id, force: true)))
        #expect(model.post(for: old.id)?.likeCount == 8)
        #expect(model.error != nil)
    }

    @Test func forcedOrganizationDetailRefreshBypassesCacheWithoutReplacingFeed() async {
        let repository = ControlledOrganizationRepository()
        let model = OrganizationsViewModel(repository: repository)
        let old = makeOrganization(id: "older-page", likeCount: 1)
        let other = makeOrganization(id: "another-page")
        model.organizations = [other, old]
        repository.organizations = [makeOrganization(id: old.id, likeCount: 8)]
        #expect(await model.resolveOrganization(id: old.id)?.likeCount == 1)
        #expect(await model.resolveOrganization(id: old.id, force: true)?.likeCount == 8)
        #expect(model.organizations.map(\.id) == [other.id, old.id])
    }

    @Test func commentDraftSurvivesFailureAndClearsOnlyAfterSuccess() async {
        let state = CommentComposerState()
        state.text = "  My comment  "
        #expect(!(await state.submit { _ in .failure(.network) }))
        #expect(state.text == "  My comment  ")
        #expect(state.error == .network)
        #expect(!state.isSending)
        var submitted = ""
        let cleared = await state.submit { text in
            submitted = text
            return .success
        }
        #expect(cleared)
        #expect(submitted == "My comment")
        #expect(state.text.isEmpty)
        #expect(state.error == nil)
    }

    @Test func commentDraftPreservesNewTypingAndRejectsDuplicateSends() async {
        let state = CommentComposerState()
        state.text = "First message"
        var completion: CheckedContinuation<CommentMutationResult, Never>?
        let task = Task { await state.submit { _ in await withCheckedContinuation { completion = $0 } } }
        #expect(await eventually { completion != nil })
        #expect(!(await state.submit { _ in Issue.record("Duplicate send"); return .success }))
        state.text = "Next message"
        completion?.resume(returning: .success)
        #expect(!(await task.value))
        #expect(state.text == "Next message")
    }

    @Test func oldCommentSendCannotClearAnotherAccountsDraft() async {
        let state = CommentComposerState()
        state.text = "Account A"
        var completion: CheckedContinuation<CommentMutationResult, Never>?
        let task = Task { await state.submit { _ in await withCheckedContinuation { completion = $0 } } }
        #expect(await eventually { completion != nil })
        state.reset()
        state.text = "Account B"
        completion?.resume(returning: .success)
        _ = await task.value
        #expect(state.text == "Account B")
        #expect(!state.isSending)
    }

    @Test func commentLengthMatchesFirestoreWithoutSilentTruncation() {
        #expect(CommentTextPolicy.validated("  \n ") == nil)
        #expect(CommentTextPolicy.validated(String(repeating: "a", count: 1000)) != nil)
        #expect(CommentTextPolicy.validated(String(repeating: "a", count: 1001)) == nil)
        #expect(CommentTextPolicy.validated(String(repeating: "😀", count: 500)) != nil)
        #expect(CommentTextPolicy.validated(String(repeating: "😀", count: 501)) == nil)
        #expect(CommentTextPolicy.length("e\u{0301}") == 2)
        #expect(CommentTextPolicy.validated("  hello  ") == "hello")
    }

    @Test func newsAndOrganizationCommentFailuresAreNotEmptyOrSuccessful() async {
        let newsRepository = ControlledNewsRepository()
        let organizationRepository = ControlledOrganizationRepository()
        let news = NewsViewModel(repository: newsRepository)
        let organizations = OrganizationsViewModel(repository: organizationRepository)
        news.posts = [makeNewsPost(id: "news")]
        newsRepository.commentFailure = .network
        organizationRepository.commentFailure = .permissionDenied
        await news.loadComments(for: "news")
        await organizations.loadComments(for: "org")
        #expect(news.commentLoadStates["news"] == .failed(.network))
        #expect(organizations.commentLoadStates["org"] == .failed(.permissionDenied))
        #expect(await news.addComment(to: "news", text: "Keep this", author: MockContentBuilder.currentUser()) == .failure(.network))
        #expect(await organizations.addComment(to: "org", text: "Keep this", author: MockContentBuilder.currentUser()) == .failure(.permissionDenied))
        #expect(await organizations.deleteComment(organizationID: "org", commentID: "comment") == .failure(.permissionDenied))
        #expect(news.pendingNewsCommentIDs.isEmpty)
        #expect(organizations.pendingOrganizationCommentIDs.isEmpty)
        newsRepository.commentFailure = nil
        organizationRepository.commentFailure = nil
        await news.loadComments(for: "news", forceRefresh: true)
        await organizations.loadComments(for: "org", forceRefresh: true)
        #expect(news.commentLoadStates["news"] == .loaded)
        #expect(organizations.commentLoadStates["org"] == .loaded)
        #expect(await news.addComment(to: "news", text: "Posted", author: MockContentBuilder.currentUser()) == .success)
        #expect(await organizations.addComment(to: "org", text: "Posted", author: MockContentBuilder.currentUser()) == .success)
    }

    @Test func organizationCommentModerationMatchesPlatformAndOrganizationRoles() {
        let organization = makeOrganization(id: "org")
        func user(_ role: GlobalRole, block: UserBlockState = .active) -> AppUser {
            AppUser(id: "unrelated-user", fullName: "User", city: "", email: "", bio: "",
                    role: .user, globalRole: role, blockState: block, createdAt: .now, updatedAt: .now)
        }
        #expect(PermissionService.canModerateOrganizationComments(organization, user: user(.admin)))
        #expect(PermissionService.canModerateOrganizationComments(organization, user: user(.owner)))
        #expect(!PermissionService.canModerateOrganizationComments(organization, user: user(.user)))
        #expect(!PermissionService.canModerateOrganizationComments(organization, user: user(.admin, block: .bannedPermanent)))
        #expect(!PermissionService.canModerateOrganizationComments(organization, user: nil))
    }


    @Test func newsLikeRejectsTwoSynchronousInvocations() async {
        let repository = ControlledNewsRepository()
        let viewModel = NewsViewModel(repository: repository)
        let post = makeNewsPost(id: "news-double-tap")
        viewModel.posts = [post]

        viewModel.toggleLike(for: post.id)
        #expect(viewModel.pendingNewsLikeIDs == [post.id])
        #expect(viewModel.post(for: post.id)?.likeState == .liked)
        #expect(viewModel.post(for: post.id)?.likeCount == 1)
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
        #expect(viewModel.interactionError == .network)
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
        #expect(viewModel.post(for: contentID)?.likeState == .liked)
        #expect(viewModel.post(for: contentID)?.likeCount == 41)

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
        _ = await deletionTask.value

        #expect(viewModel.post(for: contentID)?.comments.map(\.id) == [remainingComment.id])
        #expect(viewModel.post(for: contentID)?.commentCount == 1)
    }

    @Test(arguments: [false, true], [false, true])
    func organizationCreationAndEditingPreserveAllFields(isOwner: Bool, withLogo: Bool) async throws {
        let repository = ControlledOrganizationRepository()
        let viewModel = OrganizationsViewModel(repository: repository)
        let user = AppUser(
            id: "organization-field-audit", fullName: "Test User", displayName: "Tester",
            city: "Innsbruck", email: "test@example.org", bio: "", role: .user,
            globalRole: isOwner ? .owner : .user, blockState: .active, createdAt: .now, updatedAt: .now
        )
        let profile = OrganizationDirectoryProfile(
            profileKind: .business, secondaryCategories: ["retail", "culture"],
            serviceModes: [.online, .inStore], serviceArea: "Tirol",
            regularHours: ["monday": "09:00-18:00", "sunday": "closed"],
            specialHoursNote: "By appointment", services: ["Consultation", "Delivery"],
            orderURL: "https://example.org/order", bookingURL: "https://example.org/book",
            currentOfferTitle: "Offer", currentOfferDetails: "Details",
            currentOfferURL: "https://example.org/offer", currentOfferValidUntil: .now
        )
        let organization = Organization(
            id: UUID().uuidString, name: "All fields", description: "Short description",
            shortDescription: "Short description", fullDescription: "Full description",
            regionScope: .federalState, federalState: .tirol, city: "Innsbruck",
            coverURL: "https://example.org/cover.jpg", contactEmail: "contact@example.org",
            email: "mail@example.org", phone: "+43 123456789", website: "https://example.org",
            address: "Museumstrasse 1", latitude: 47.269, longitude: 11.404,
            organizationType: "culture", directoryProfile: profile, foundedYear: 2020, foundedMonth: 5,
            languages: ["Українська", "Deutsch"], socialLinks: ["other": "https://example.org/social"],
            telegramURL: "https://t.me/example", donationURL: "https://example.org/support",
            facebookURL: "https://facebook.com/example", instagramURL: "https://instagram.com/example",
            whatsappURL: "https://wa.me/43123456789", youtubeURL: "https://youtube.com/@example",
            linkedinURL: "https://linkedin.com/company/example", missionStatement: "Mission",
            contactPerson: "Contact", submittedByUserId: isOwner ? nil : user.id,
            createdAt: .now, updatedAt: .now, moderationStatus: isOwner ? .approved : .pendingReview,
            likeCount: 0, likeState: .notLiked
        )
        let imageData: Data? = withLogo ? Data([1, 2, 3]) : nil
        try await viewModel.createOrganization(organization, imageData: imageData, user: user)
        let created = try #require(repository.organizations.first)
        try expectOrganizationFieldsEqual(created, organization)
        #expect((created.logoURL != nil) == withLogo)
        #expect(repository.createRequestCount == 1)
        #expect(repository.updateRequestCount == (withLogo ? 1 : 0))
        viewModel.organizations = [created]
        try await viewModel.updateOrganization(created, imageData: imageData, user: user)
        let updated = try #require(repository.organizations.first)
        try expectOrganizationFieldsEqual(updated, organization)
        #expect(repository.updateRequestCount == (withLogo ? 2 : 1))
        let decoded = Organization(dto: updated.dto)
        #expect(decoded.directoryProfile == profile)
    }

    private func expectOrganizationFieldsEqual(_ actual: Organization, _ expected: Organization) throws {
        let encoder = JSONEncoder()
        var actualFields = try JSONSerialization.jsonObject(with: encoder.encode(actual.dto)) as! [String: Any]
        var expectedFields = try JSONSerialization.jsonObject(with: encoder.encode(expected.dto)) as! [String: Any]
        // Only these fields intentionally change in the image/save pipeline.
        for key in ["imageURL", "logoURL", "updatedAt"] {
            actualFields.removeValue(forKey: key)
            expectedFields.removeValue(forKey: key)
        }
        #expect(NSDictionary(dictionary: actualFields).isEqual(to: expectedFields))
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
        #expect(viewModel.interactionError == .network)
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
        #expect(viewModel.interactionError == .network)
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

    @Test(arguments: ["owner", "admin", "moderator", "unrelated"])
    func authoringDiscoveryUsesCanonicalRolesBeyondThePublicPage(role: String) async {
        let user = MockContentBuilder.currentUser()
        let repository = ControlledOrganizationRepository()
        let target = Organization(
            id: "not-on-public-first-page", name: "Authoring organization", description: "Description", city: "Vienna",
            ownerId: role == "owner" ? user.id : "another-owner",
            adminIds: role == "admin" ? [user.id] : [],
            moderatorIds: role == "moderator" ? [user.id] : [],
            createdAt: .now, updatedAt: .now, moderationStatus: .approved,
            likeCount: 0, likeState: .notLiked
        )
        repository.organizations = []
        repository.authoringHandler = { [target] _ in [target] }
        let model = AuthoringOrganizationsViewModel(repository: repository)
        await model.load(for: user)
        #expect(model.organizations.map(\.id) == (role == "unrelated" ? [] : [target.id]))
        #expect(!model.isLoading && model.error == nil)
        await model.load(for: nil)
        #expect(model.organizations.isEmpty)
    }

    @Test
    func authoringDiscoveryDiscardsAResponseAfterLogout() async {
        let repository = ControlledOrganizationRepository()
        let target = makeOrganization(id: "org")
        var continuation: CheckedContinuation<[Organization], Never>?
        repository.authoringHandler = { _ in await withCheckedContinuation { continuation = $0 } }
        let model = AuthoringOrganizationsViewModel(repository: repository)
        let task = Task { await model.load(for: MockContentBuilder.ownerUser()) }
        #expect(await eventually { continuation != nil })
        await model.load(for: nil)
        continuation?.resume(returning: [target])
        await task.value
        #expect(model.organizations.isEmpty && !model.isLoading)
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
    var commentFailure: AppError?

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
    func fetchNewsComments(newsID: String) async throws -> [UkrainianCommunity.Comment] {
        if let commentFailure { throw commentFailure }
        return []
    }
    func addNewsComment(newsID: String, text: String, author: AppUser) async throws -> UkrainianCommunity.Comment {
        if let commentFailure { throw commentFailure }
        return UkrainianCommunity.Comment(id: UUID().uuidString, authorName: author.preferredDisplayName, body: text, createdAt: .now)
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
    var authoringHandler: ((AppUser) async throws -> [Organization])?
    func fetchAuthoringOrganizations(user: AppUser) async throws -> [Organization] {
        if let authoringHandler { return try await authoringHandler(user) }
        return PermissionService.manageableOrganizations(from: organizations, user: user)
    }
    var commentFailure: AppError?

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
    private(set) var createRequestCount = 0
    private(set) var updateRequestCount = 0
    func createOrganization(_ organization: Organization) async throws {
        createRequestCount += 1
        organizations.append(organization)
    }
    func updateOrganization(_ organization: Organization) async throws {
        updateRequestCount += 1
        organizations.removeAll { $0.id == organization.id }
        organizations.append(organization)
    }
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
    func fetchOrganizationComments(organizationID: String) async throws -> [UkrainianCommunity.Comment] {
        if let commentFailure { throw commentFailure }
        return []
    }
    func addOrganizationComment(organizationID: String, text: String, author: AppUser) async throws -> UkrainianCommunity.Comment {
        if let commentFailure { throw commentFailure }
        return UkrainianCommunity.Comment(id: UUID().uuidString, authorName: author.preferredDisplayName, body: text, createdAt: .now)
    }
    func updateOrganizationComment(organizationID: String, commentID: String, text: String) async throws -> UkrainianCommunity.Comment {
        UkrainianCommunity.Comment(id: commentID, authorName: "Author", body: text, createdAt: .now)
    }
    func deleteOrganizationComment(organizationID: String, commentID: String) async throws {
        if let commentFailure { throw commentFailure }
    }
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
