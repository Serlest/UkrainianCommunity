import Foundation

struct MockOrganizationRepository: OrganizationRepository {
    private let store = MockRepositoryStore.shared

    func fetchOrganizations() async throws -> [Organization] {
        await store.organizations
            .filter { $0.moderationStatus == .approved }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func fetchOrganization(id: String) async throws -> Organization {
        try await store.organization(id: id)
    }

    func fetchPendingOrganizations() async throws -> [Organization] {
        await store.pendingOrganizations()
    }

    func fetchOrganizationRequests(submittedByUserID: String) async throws -> [Organization] {
        await store.organizationRequests(submittedByUserID: submittedByUserID)
    }

    func createOrganization(_ organization: Organization) async throws {
        await store.createOrganization(organization)
    }

    func updateOrganization(_ organization: Organization) async throws {
        try await store.updateOrganization(organization)
    }

    func deleteOrganization(id: String) async throws {
        try await store.deleteOrganization(id: id)
    }

    func uploadOrganizationImage(data: Data, organizationID: String) async throws -> URL {
        URL(string: "https://example.com/organizations/\(organizationID)/logo.jpg")!
    }

    func likeOrganization(id: String) async throws {
        try await store.toggleOrganizationLike(id: id, isLiked: true)
    }

    func unlikeOrganization(id: String) async throws {
        try await store.toggleOrganizationLike(id: id, isLiked: false)
    }

    func subscribeOrganization(id: String) async throws {
        try await store.toggleOrganizationSubscription(id: id, isSubscribed: true)
    }

    func unsubscribeOrganization(id: String) async throws {
        try await store.toggleOrganizationSubscription(id: id, isSubscribed: false)
    }

    func fetchOrganizationSubscriberPage(
        organizationID: String,
        limit: Int,
        after cursor: OrganizationSubscriberCursor?
    ) async throws -> OrganizationSubscriberPage {
        try await store.organizationSubscriberPage(organizationID: organizationID, limit: limit, after: cursor)
    }

    func fetchPublicUserProfiles(userIDs: [String]) async throws -> [PublicUserProfile] {
        []
    }

    func fetchOrganizationComments(organizationID: String) async throws -> [Comment] {
        try await store.organizationComments(organizationID: organizationID)
    }

    func addOrganizationComment(organizationID: String, text: String, author: AppUser) async throws -> Comment {
        try await store.addOrganizationComment(organizationID: organizationID, text: text, author: author)
    }

    func updateOrganizationComment(organizationID: String, commentID: String, text: String) async throws -> Comment {
        try await store.updateOrganizationComment(organizationID: organizationID, commentID: commentID, text: text)
    }

    func deleteOrganizationComment(organizationID: String, commentID: String) async throws {
        try await store.deleteOrganizationComment(organizationID: organizationID, commentID: commentID)
    }

    func bookmarkOrganization(id: String) async throws {
        try await store.setOrganizationBookmark(id: id, isBookmarked: true)
    }

    func unbookmarkOrganization(id: String) async throws {
        try await store.setOrganizationBookmark(id: id, isBookmarked: false)
    }

    func isOrganizationBookmarked(id: String) async throws -> Bool {
        await store.bookmarkedOrganizationIDs().contains(id)
    }

    func fetchBookmarkedOrganizationIDs() async throws -> Set<String> {
        await store.bookmarkedOrganizationIDs()
    }

    func updateModerationStatus(id: String, newStatus: ModerationStatus) async throws {
        try await store.updateOrganizationModerationStatus(id: id, newStatus: newStatus)
    }

    func approveOrganizationRequest(id: String, reviewerID: String) async throws {
        try await store.approveOrganizationRequest(id: id, reviewerID: reviewerID)
    }

    func requestOrganizationRevision(id: String, message: String, reviewerID: String) async throws {
        try await store.requestOrganizationRevision(id: id, message: message, reviewerID: reviewerID)
    }

    func rejectOrganizationRequest(id: String, reason: String, reviewerID: String) async throws {
        try await store.deleteOrganization(id: id)
    }
}
