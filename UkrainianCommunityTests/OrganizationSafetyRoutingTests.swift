import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct OrganizationSafetyRoutingTests {
    @Test func pushSubmissionRetainsTheExactRequestAndReviewerDestination() throws {
        let push = try #require(RemoteNotificationRoute(userInfo: [
            "notificationId": "notice-1", "type": "organizationRequestSubmitted",
            "sourceType": "organization", "sourceId": "org-1",
            "actionType": "openOrganizationRequest", "actionTargetId": "org-1",
        ]))
        #expect(push.destination == .openOrganizationRequest(organizationId: "org-1"))
        #expect(OrganizationRequestNotificationDestination.resolve(
            type: push.type, organizationID: push.actionTargetId, canReviewRequests: true
        ) == .review(organizationID: "org-1"))
        #expect(OrganizationRequestNotificationDestination.resolve(
            type: .organizationRequestSubmitted, organizationID: nil, canReviewRequests: true
        ) == .review(organizationID: nil))
        #expect(OrganizationRequestNotificationDestination.resolve(
            type: push.type, organizationID: "org-1", canReviewRequests: false
        ) == .unavailable)
    }

    @Test func applicantAndReviewerNotificationsHaveDifferentDestinations() {
        #expect(OrganizationRequestNotificationDestination.resolve(
            type: .organizationRequestApproved, organizationID: "org-1", canReviewRequests: false
        ) == .organization(organizationID: "org-1"))
        for type in [AppNotificationType.organizationRequestNeedsRevision, .organizationRequestRejected] {
            #expect(OrganizationRequestNotificationDestination.resolve(
                type: type, organizationID: "org-1", canReviewRequests: true
            ) == .management)
        }
    }

    @Test func notificationLoadsExactlyItsRequestAndHandlesAlreadyReviewedAndDeleted() async throws {
        let repository = MockOrganizationRepository()
        let id = "request-test-\(UUID().uuidString)"
        let organization = makeOrganization(id: id, status: .approved)
        try await repository.createOrganization(organization)
        let model = ModerationQueueViewModel(
            newsRepository: MockNewsRepository(), eventRepository: MockEventRepository(),
            organizationRepository: repository, requestedOrganizationID: id
        )
        model.setAllowedSections([.organizations])
        await model.loadIfNeeded()
        #expect(model.items.map(\.contentID) == [id])
        #expect(model.items.first?.organization?.ownerId == "same-owner")
        #expect(model.items.first?.canReview == false)
        try await repository.deleteOrganization(id: id)
        await model.refresh()
        #expect(model.error == .notFound)
        #expect(model.items.isEmpty)
        model.setAllowedSections([])
        await model.refresh()
        #expect(model.items.isEmpty)
        #expect(model.error == .permissionDenied)
    }

    @Test func blockingOneOrganizationDoesNotBlockItsOwnerOrOtherOrganizations() {
        let first = makeOrganization(id: "org-a")
        let second = makeOrganization(id: "org-b")
        let policy = ContentVisibilityPolicy(blockedOrganizationIDs: ["org-a"])
        #expect(policy.visibleOrganizations([first, second]).map(\.id) == ["org-b"])
        #expect(policy.allows(authorID: "same-owner"))
        #expect(policy.visibleNews([news("org-a"), news("org-b")]).map(\.id) == ["news-org-b"])
        #expect(policy.visibleEvents([event("org-a"), event("org-b")]).map(\.id) == ["event-org-b"])
        let comment = Comment(id: "comment", authorId: "same-owner", authorName: "Owner", text: "Text", createdAt: .now)
        #expect(policy.visibleComments([comment]).count == 1)
        #expect(ContentVisibilityPolicy().visibleOrganizations([first, second]).count == 2)
    }

    @Test func organizationBlockResponseUsesServerDatesAndRejectsWrongTarget() throws {
        let data = Data("""
        {"organizationId":"org-a","isBlocked":true,"block":{"organizationId":"org-a","name":"First","blockedAt":"2026-09-02T18:00:00.123Z"}}
        """.utf8)
        let response = try JSONDecoder().decode(OrganizationBlockFunctionResponse.self, from: data)
        #expect(try response.validated(for: "org-a", isBlocked: true)?.organizationID == "org-a")
        #expect(throws: AppError.validationFailed) { try response.validated(for: "org-b", isBlocked: true) }
        #expect(throws: AppError.validationFailed) { try response.validated(for: "org-a", isBlocked: false) }
        let request = OrganizationBlockFunctionRequest(organizationId: "org-a", isBlocked: true)
        let fields = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(Set(fields.keys) == ["organizationId", "isBlocked"])
    }

    @Test func publicVisibilityDoesNotRemoveAuthoringPermissions() async throws {
        let repository = MockOrganizationRepository()
        let organization = makeOrganization(id: "managed-\(UUID().uuidString)")
        try await repository.createOrganization(organization)
        let user = MockContentBuilder.ownerUser()
        let authoring = AuthoringOrganizationsViewModel(repository: repository)
        await authoring.load(for: user)
        let policy = ContentVisibilityPolicy(blockedOrganizationIDs: [organization.id])
        #expect(policy.visibleOrganizations([organization]).isEmpty)
        #expect(authoring.organizations.contains { $0.id == organization.id })
        #expect(PermissionService.canEditOrganizationInfo(organization, user: user))
        let publicOrganizations = OrganizationsViewModel(repository: repository)
        publicOrganizations.applyContentVisibility(policy)
        #expect(publicOrganizations.visibilityPolicy.visibleOrganizations([organization]).isEmpty)
        publicOrganizations.applyContentVisibility(ContentVisibilityPolicy())
        #expect(publicOrganizations.visibilityPolicy.visibleOrganizations([organization]).count == 1)
        try await repository.deleteOrganization(id: organization.id)
    }

    @Test func coordinatorUnblocksAndIgnoresPreviousAccountResponses() async {
        let repository = OrganizationBlockingTestRepository()
        let coordinator = OrganizationBlockingCoordinator(repository: repository, cache: nil)
        await coordinator.configure(userID: "viewer-a")
        #expect(await coordinator.setBlocked(organizationID: "org-a", isBlocked: true))
        #expect(coordinator.blockedOrganizationIDs == ["org-a"])
        #expect(await coordinator.setBlocked(organizationID: "org-a", isBlocked: false))
        #expect(coordinator.blockedOrganizationIDs.isEmpty)
        repository.beforeMutationReturns = { await coordinator.configure(userID: nil) }
        #expect(await coordinator.setBlocked(organizationID: "org-a", isBlocked: true) == false)
        #expect(coordinator.blockedOrganizationIDs.isEmpty)
        #expect(!coordinator.isMutating)
    }

    @Test func failedMutationDoesNotPretendTheOrganizationWasBlocked() async {
        let repository = OrganizationBlockingTestRepository()
        repository.failMutation = true
        let coordinator = OrganizationBlockingCoordinator(repository: repository, cache: nil)
        await coordinator.configure(userID: "viewer")
        #expect(await coordinator.setBlocked(organizationID: "org-a", isBlocked: true) == false)
        #expect(coordinator.blockedOrganizationIDs.isEmpty)
        #expect(coordinator.errorMessage != nil)
    }

    private func makeOrganization(id: String, status: ModerationStatus = .approved) -> Organization {
        Organization(id: id, name: id, description: "Description", city: "Innsbruck", ownerId: "same-owner",
                     createdAt: .now, updatedAt: .now, moderationStatus: status, likeCount: 0, likeState: .notLiked)
    }

    private func news(_ organizationID: String) -> NewsPost {
        NewsPost(id: "news-\(organizationID)", title: "News", subtitle: "Summary",
                 source: ContentSourceMetadata(sourceType: .organization, organizationId: organizationID),
                 body: "Body", authorId: "same-owner", authorName: "Owner", publishedAt: .now,
                 createdAt: .now, updatedAt: .now, comments: [], moderationStatus: .approved,
                 likeCount: 0, likeState: .notLiked)
    }

    private func event(_ organizationID: String) -> Event {
        Event(id: "event-\(organizationID)", title: "Event", summary: "Summary", details: "Details",
              source: ContentSourceMetadata(sourceType: .organization, organizationId: organizationID),
              authorId: "same-owner", city: "Innsbruck", venue: "Venue", startDate: .now, endDate: .now,
              createdAt: .now, updatedAt: .now, requiresRegistration: false, price: 0, capacity: nil,
              registeredCount: 0, comments: [], moderationStatus: .approved, registrationState: .notRegistered,
              likeCount: 0, likeState: .notLiked)
    }
}

@MainActor
private final class OrganizationBlockingTestRepository: OrganizationBlockingRepository {
    var beforeMutationReturns: (() async -> Void)?
    var failMutation = false
    func fetchBlockedOrganizations() async throws -> [BlockedOrganization] { [] }
    func setBlocked(organizationID: String, isBlocked: Bool) async throws -> BlockedOrganization? {
        if failMutation { throw AppError.network }
        await beforeMutationReturns?()
        return isBlocked ? BlockedOrganization(organizationID: organizationID, name: "First", blockedAt: .now) : nil
    }
}
