import Foundation
import Testing
@testable import UkrainianCommunity

@Suite(.serialized)
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

    @Test func reviewQueuePagesWithoutTruncatingTheProfileCount() async throws {
        let repository = MockOrganizationRepository()
        let prefix = "paged-review-\(UUID().uuidString)"
        for index in 0..<37 {
            try await repository.createOrganization(Organization(id: "\(prefix)-\(index)", name: "Request \(index)",
                description: "Description", city: "Innsbruck", submittedByUserId: "applicant",
                createdAt: Date(timeIntervalSince1970: Double(index)), updatedAt: .now,
                moderationStatus: .pendingReview, likeCount: 0, likeState: .notLiked))
        }
        let model = ModerationQueueViewModel(newsRepository: MockNewsRepository(), eventRepository: MockEventRepository(), organizationRepository: repository)
        model.setAllowedSections([.organizations])
        await model.loadIfNeeded()
        #expect(model.items.count == 30)
        #expect(model.hasMoreRequests)
        let profile = OwnerProfileVisibilityViewModel(feedbackRepository: MockFeedbackRepository(), organizationRepository: repository)
        await profile.loadIfNeeded(includeOrganizationRequests: true, includeFeedback: false)
        #expect(profile.pendingOrganizationRequestCount == 37)
        await model.loadMoreRequests()
        #expect(model.items.count == 37)
        #expect(Set(model.items.map(\.id)).count == 37)
        #expect(!model.hasMoreRequests)
        for index in 0..<37 { try await repository.deleteOrganization(id: "\(prefix)-\(index)") }
    }

    @Test func staleReviewAndRevokedAccessCannotApproveTheRequest() async throws {
        let repository = MockOrganizationRepository()
        let id = "stale-review-\(UUID().uuidString)"
        func request(updatedAt: Date) -> Organization {
            Organization(id: id, name: "Request", description: "Description", city: "Innsbruck",
                submittedByUserId: "applicant", createdAt: .now, updatedAt: updatedAt,
                moderationStatus: .pendingReview, likeCount: 0, likeState: .notLiked)
        }
        try await repository.createOrganization(request(updatedAt: Date(timeIntervalSince1970: 100)))
        let model = ModerationQueueViewModel(newsRepository: MockNewsRepository(), eventRepository: MockEventRepository(), organizationRepository: repository, requestedOrganizationID: id)
        model.setAllowedSections([.organizations]); await model.loadIfNeeded()
        let item = try #require(model.items.first)
        try await repository.updateOrganization(request(updatedAt: Date(timeIntervalSince1970: 101)))
        #expect(!(await model.updateStatus(for: item, to: .approved, reviewerID: "owner-1")))
        #expect(model.actionError == .validationFailed)
        #expect(try await repository.fetchOrganization(id: id).moderationStatus == .pendingReview)
        model.setAllowedSections([])
        #expect(!(await model.updateStatus(for: item, to: .approved, reviewerID: "owner-1")))
        #expect(model.actionError == .permissionDenied)
        try await repository.deleteOrganization(id: id)
    }

    @Test func historyDecodingPreservesReasonsAndExactPageCursor() throws {
        let data = Data(#"{"items":[{"id":"decision","organizationId":"org","organizationName":"Name","reviewerDisplayName":"Reviewer","status":"needsRevision","reason":"Add contact details","createdAtMilliseconds":1000}],"nextCursor":{"seconds":1,"nanoseconds":123456789,"id":"decision"}}"#.utf8)
        let page = try JSONDecoder().decode(OrganizationReviewHistoryPage.self, from: data)
        #expect(page.items.first?.reason == "Add contact details")
        #expect(page.items.first?.status == .needsRevision)
        #expect(page.nextCursor?.nanoseconds == 123456789)
    }

    @Test func allReviewDecisionsReachTheirStatusAndHistory() async throws {
        let repository = MockOrganizationRepository()
        for decision in OrganizationReviewDecision.allCases {
            let id = "decision-flow-\(UUID().uuidString)"
            let organization = Organization(id: id, name: "Decision fixture", description: "Description", city: "Innsbruck",
                submittedByUserId: "applicant", createdAt: Date(timeIntervalSince1970: 1000),
                updatedAt: Date(timeIntervalSince1970: 1000), moderationStatus: .pendingReview, likeCount: 0, likeState: .notLiked)
            try await repository.createOrganization(organization)
            let model = ModerationQueueViewModel(newsRepository: MockNewsRepository(), eventRepository: MockEventRepository(),
                organizationRepository: repository, requestedOrganizationID: id)
            model.setAllowedSections([.organizations]); await model.loadIfNeeded()
            let item = try #require(model.items.first)
            let succeeded: Bool
            let expected: ModerationStatus
            switch decision {
            case .approve:
                expected = .approved
                succeeded = await model.updateStatus(for: item, to: .approved, reviewerID: "owner-1")
            case .requestRevision:
                expected = .needsRevision
                succeeded = await model.requestRevision(for: item, message: "Add contacts", reviewerID: "owner-1")
            case .reject:
                expected = .rejected
                succeeded = await model.rejectOrganizationRequest(for: item, reason: "Duplicate", reviewerID: "owner-1")
            }
            #expect(succeeded)
            #expect(model.items.isEmpty)
            #expect(try await repository.fetchOrganization(id: id).moderationStatus == expected)
            await model.loadHistory(reset: true)
            let record = try #require(model.history.first(where: { $0.organizationId == id }))
            #expect(record.status == expected)
            #expect(record.reason == (decision == .approve ? "" : decision == .reject ? "Duplicate" : "Add contacts"))
            try await repository.deleteOrganization(id: id)
        }
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
