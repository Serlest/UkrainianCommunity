import Foundation
import Testing
@testable import UkrainianCommunity

private final class OwnerContentDraftRepositoryStub: OwnerContentDraftRepository {
    struct PageRequest {
        let userID: String
        let section: OwnerContentPlanningSection
        let limit: Int
        let cursor: OwnerContentDraftPageCursor?
    }

    var pages: [OwnerContentPlanningSection: [OwnerContentDraftPage]] = [:]
    var exactDraft: OwnerContentDraft?
    var lease: OwnerContentPublicationLease?
    var beginResponseData: Data?
    var beginError: Error?
    var finalizeError: Error?
    private(set) var pageRequests: [PageRequest] = []
    private(set) var exactRequests: [(userID: String, draftID: String)] = []
    private(set) var finalizedPublications: [ContentPlanningPublicationResult] = []
    private(set) var beginRequests: [(draftID: String, attemptID: String)] = []

    func fetchDraftPage(
        userID: String,
        section: OwnerContentPlanningSection,
        limit: Int,
        after cursor: OwnerContentDraftPageCursor?
    ) async throws -> OwnerContentDraftPage {
        pageRequests.append(PageRequest(userID: userID, section: section, limit: limit, cursor: cursor))
        guard var queued = pages[section], !queued.isEmpty else {
            return OwnerContentDraftPage(items: [], nextCursor: nil, hasMore: false)
        }
        let page = queued.removeFirst()
        pages[section] = queued
        return page
    }

    func fetchDraft(userID: String, draftID: String) async throws -> OwnerContentDraft {
        exactRequests.append((userID, draftID))
        guard let exactDraft, exactDraft.id == draftID else { throw AppError.notFound }
        return exactDraft
    }

    func beginPublication(
        userID: String,
        draftID: String,
        attemptID: String
    ) async throws -> OwnerContentPublicationLease {
        beginRequests.append((draftID, attemptID))
        if let beginError { throw beginError }
        if let beginResponseData {
            let response = try JSONDecoder().decode(OwnerContentPublicationResponse.self, from: beginResponseData)
            return try response.lease(forDraftID: draftID)
        }
        guard let lease, lease.draftID == draftID else { throw AppError.notFound }
        return lease
    }

    func finalizePublication(
        userID: String,
        draftID: String,
        publication: ContentPlanningPublicationResult
    ) async throws {
        finalizedPublications.append(publication)
        if let finalizeError { throw finalizeError }
    }

    func failPublication(userID: String, draftID: String, leaseID: String, message: String) async throws {}
    func archive(userID: String, draftID: String) async throws {}
    func delete(userID: String, draftID: String) async throws {}
}

@MainActor
struct OwnerContentPlanningViewModelTests {
    @Test func loadsEachSectionFromTheServerInPagesOfFifteen() async {
        let repository = OwnerContentDraftRepositoryStub()
        repository.pages[.drafts] = [OwnerContentDraftPage(
            items: (0..<15).map { makeDraft(id: "draft-\($0)") },
            nextCursor: OwnerContentDraftPageCursor(sortDate: Date(timeIntervalSince1970: 10), documentID: "draft-14"),
            hasMore: true
        )]
        let viewModel = OwnerContentPlanningViewModel(repository: repository)

        await viewModel.load(.drafts, userID: "owner")

        #expect(viewModel.snapshot(for: .drafts).items.count == 15)
        #expect(viewModel.snapshot(for: .drafts).hasMore)
        #expect(repository.pageRequests.count == 1)
        #expect(repository.pageRequests.first?.userID == "owner")
        #expect(repository.pageRequests.first?.section == .drafts)
        #expect(repository.pageRequests.first?.limit == 15)
        #expect(repository.pageRequests.first?.cursor == nil)
    }

    @Test func nextPageUsesTheCursorAndDoesNotDuplicateDocuments() async {
        let repository = OwnerContentDraftRepositoryStub()
        let cursor = OwnerContentDraftPageCursor(
            sortDate: Date(timeIntervalSince1970: 20),
            documentID: "draft-1"
        )
        repository.pages[.drafts] = [
            OwnerContentDraftPage(
                items: [makeDraft(id: "draft-1")],
                nextCursor: cursor,
                hasMore: true
            ),
            OwnerContentDraftPage(
                items: [makeDraft(id: "draft-1"), makeDraft(id: "draft-2")],
                nextCursor: nil,
                hasMore: false
            ),
        ]
        let viewModel = OwnerContentPlanningViewModel(repository: repository)
        await viewModel.load(.drafts, userID: "owner")

        await viewModel.loadNextPageIfNeeded(.drafts, currentItemID: "draft-1")

        #expect(viewModel.snapshot(for: .drafts).items.map(\.id) == ["draft-1", "draft-2"])
        #expect(repository.pageRequests.last?.cursor == cursor)
    }

    @Test func deepLinkFetchesExactlyOneDraftAndRevealsItsRealSection() async {
        let repository = OwnerContentDraftRepositoryStub()
        repository.exactDraft = makeDraft(id: "history-1", state: .completed)
        let viewModel = OwnerContentPlanningViewModel(repository: repository)
        viewModel.start(userID: "owner")

        let draft = await viewModel.fetchDraftForDeepLink("history-1")
        if let draft { viewModel.reveal(draft) }

        #expect(repository.exactRequests.count == 1)
        #expect(repository.pageRequests.isEmpty)
        #expect(viewModel.snapshot(for: .history).items.map(\.id) == ["history-1"])
    }

    @Test func finalizationUsesTheServerLeaseAndInvalidatesHistory() async throws {
        let repository = OwnerContentDraftRepositoryStub()
        let draft = makeDraft(id: "draft-1")
        repository.lease = OwnerContentPublicationLease(
            draftID: draft.id,
            kind: .news,
            contentID: "planning-draft-1",
            leaseID: "lease-1",
            expiresAt: Date().addingTimeInterval(600),
            contentAlreadyExists: false,
            existingModerationStatus: nil,
            existingScheduledAt: nil
        )
        repository.pages[.history] = [OwnerContentDraftPage(items: [], nextCursor: nil, hasMore: false)]
        let viewModel = OwnerContentPlanningViewModel(repository: repository)
        await viewModel.load(.history, userID: "owner")
        let leaseResult = await viewModel.beginPublishing(draft)
        let lease = try #require(leaseResult)

        let succeeded = await viewModel.finishPublishing(
            draft,
            publication: ContentPlanningPublicationResult(
                kind: .news,
                contentID: lease.contentID,
                scheduledAt: nil,
                publicationLeaseID: lease.leaseID
            )
        )

        #expect(succeeded)
        #expect(repository.finalizedPublications.first?.publicationLeaseID == "lease-1")
        #expect(viewModel.snapshot(for: .history).hasLoaded == false)
    }

    @Test func reusingAnUnfinishedLeaseDoesNotInventExistingContent() async throws {
        let repository = OwnerContentDraftRepositoryStub()
        let draft = makeDraft(id: "draft-1")
        repository.lease = makeLease(for: draft, contentAlreadyExists: false)
        let viewModel = OwnerContentPlanningViewModel(repository: repository)
        viewModel.start(userID: "owner")

        let firstResult = await viewModel.beginPublishing(draft)
        let first = try #require(firstResult)
        let secondResult = await viewModel.beginPublishing(draft)
        let second = try #require(secondResult)

        #expect(first.leaseID == second.leaseID)
        #expect(second.contentAlreadyExists == false)
    }

    @Test func ambiguousFinalizeMarksTheReservedContentAsExistingForRetry() async throws {
        let repository = OwnerContentDraftRepositoryStub()
        let draft = makeDraft(id: "draft-1")
        repository.lease = makeLease(for: draft, contentAlreadyExists: false)
        repository.finalizeError = AppError.network
        let viewModel = OwnerContentPlanningViewModel(repository: repository)
        viewModel.start(userID: "owner")
        let firstResult = await viewModel.beginPublishing(draft)
        let first = try #require(firstResult)

        let succeeded = await viewModel.finishPublishing(
            draft,
            publication: ContentPlanningPublicationResult(
                kind: .news,
                contentID: first.contentID,
                scheduledAt: nil,
                publicationLeaseID: first.leaseID
            )
        )
        let retryResult = await viewModel.beginPublishing(draft)
        let retry = try #require(retryResult)

        #expect(succeeded == false)
        #expect(retry.contentAlreadyExists)
        #expect(viewModel.actionErrorMessage == nil)
        #expect(repository.beginRequests.count == 1)
    }

    @Test(arguments: OwnerContentDraftKind.allCases)
    func serverJSONReachesFinalizationUsingTheSameReservedContent(kind: OwnerContentDraftKind) async throws {
        let repository = OwnerContentDraftRepositoryStub()
        let contentID = "planning-editor-test-\(UUID().uuidString)"
        repository.beginResponseData = try OwnerContentPublicationResponseFixture.data(
            kind: kind, overrides: ["contentId": contentID]
        )
        let draft = makeDraft(id: "draft-1", kind: kind)
        let viewModel = OwnerContentPlanningViewModel(repository: repository)
        viewModel.start(userID: "owner")

        let lease = try #require(await viewModel.beginPublishing(draft))
        let retry = try #require(await viewModel.beginPublishing(draft))
        #expect(lease == retry)
        #expect(repository.beginRequests.count == 1)
        #expect(!retry.contentAlreadyExists)

        let publication = try await publishThroughEditor(draft: draft, lease: lease)
        let succeeded = await viewModel.finishPublishing(draft, publication: publication)
        #expect(succeeded)
        #expect(repository.finalizedPublications.count == 1)
        #expect(repository.finalizedPublications.first?.contentID == contentID)
        #expect(repository.finalizedPublications.first?.publicationLeaseID == "lease-1")
    }

    @Test(arguments: OwnerContentDraftKind.allCases)
    func retryAfterLostResponseKeepsTheOriginalAttemptID(kind: OwnerContentDraftKind) async throws {
        let repository = OwnerContentDraftRepositoryStub()
        repository.beginResponseData = try OwnerContentPublicationResponseFixture.data(kind: kind)
        repository.beginError = AppError.network
        let draft = makeDraft(id: "draft-1", kind: kind)
        let viewModel = OwnerContentPlanningViewModel(repository: repository)
        viewModel.start(userID: "owner")

        #expect(await viewModel.beginPublishing(draft) == nil)
        #expect(viewModel.actionErrorMessage != nil)
        #expect(!viewModel.isPerformingAction(on: draft.id))
        repository.beginError = nil
        let lease = try #require(await viewModel.beginPublishing(draft))

        #expect(repository.beginRequests.count == 2)
        #expect(repository.beginRequests.first?.attemptID == repository.beginRequests.last?.attemptID)
        #expect(lease.contentID == "planning-draft-1")
        #expect(!lease.contentAlreadyExists)
        #expect(viewModel.actionErrorMessage == nil)
    }

    @Test func malformedResponseCannotBeFinalizedAndRetryKeepsTheAttemptID() async throws {
        let repository = OwnerContentDraftRepositoryStub()
        repository.beginResponseData = try OwnerContentPublicationResponseFixture.data(overrides: ["expiresAt": "invalid"])
        let draft = makeDraft(id: "draft-1")
        let viewModel = OwnerContentPlanningViewModel(repository: repository)
        viewModel.start(userID: "owner")

        #expect(await viewModel.beginPublishing(draft) == nil)
        #expect(await viewModel.finishPublishing(draft, publication: ContentPlanningPublicationResult(
            kind: .news, contentID: "planning-draft-1", scheduledAt: nil, publicationLeaseID: "lease-1"
        )) == false)
        #expect(repository.finalizedPublications.isEmpty)

        repository.beginResponseData = try OwnerContentPublicationResponseFixture.data()
        #expect(await viewModel.beginPublishing(draft) != nil)
        #expect(repository.beginRequests.count == 2)
        #expect(repository.beginRequests.first?.attemptID == repository.beginRequests.last?.attemptID)
    }

    private func publishThroughEditor(
        draft: OwnerContentDraft,
        lease: OwnerContentPublicationLease
    ) async throws -> ContentPlanningPublicationResult {
        switch draft.kind {
        case .news:
            let contentRepository = MockNewsRepository()
            let editor = NewsEditorViewModel(
                repository: contentRepository,
                mode: .create(context: .init(
                    organizationId: "organization-1", organizationName: "Community",
                    organizationImageURL: nil, organizationFederalState: .tirol
                )),
                sourceDraft: draft
            )
            editor.title = "Новина"
            editor.summary = "Короткий опис"
            editor.body = "Повний текст"
            editor.selectedRegionScope = .federalState
            #expect(await editor.publish(
                contentID: lease.contentID,
                contentAlreadyExists: lease.contentAlreadyExists,
                existingModerationStatus: lease.existingModerationStatus,
                existingScheduledAt: lease.existingScheduledAt,
                publicationLeaseID: lease.leaseID
            ))
            #expect(editor.errorMessage == nil)
            let result = try #require(editor.lastPublicationResult)
            let saved = try await contentRepository.fetchNews(id: lease.contentID)
            #expect(saved.title == editor.title)
            #expect(saved.source.organizationId == "organization-1")
            try await contentRepository.deleteNews(id: lease.contentID)
            return result
        case .event:
            let contentRepository = MockEventRepository()
            let editor = EventEditorViewModel(
                repository: contentRepository,
                mode: .create(context: .init(
                    organizationId: "organization-1", organizationName: "Community",
                    organizationImageURL: nil, organizationFederalState: .tirol
                )),
                sourceDraft: draft
            )
            editor.title = "Подія"
            editor.summary = "Короткий опис"
            editor.details = "Повний опис"
            editor.city = "Innsbruck"
            editor.venue = "Community Center"
            // This test covers the publication lease, not CoreLocation's external service.
            // Both coordinates prevent publish() from awaiting a real CLGeocoder request.
            editor.latitude = 47.2692
            editor.longitude = 11.4041
            editor.startDate = Date().addingTimeInterval(86_400)
            editor.endDate = editor.startDate.addingTimeInterval(3_600)
            #expect(await editor.publish(
                contentID: lease.contentID,
                contentAlreadyExists: lease.contentAlreadyExists,
                reservedModerationStatus: lease.existingModerationStatus,
                existingScheduledAt: lease.existingScheduledAt,
                publicationLeaseID: lease.leaseID
            ))
            #expect(editor.errorMessage == nil)
            let result = try #require(editor.lastPublicationResult)
            let saved = try await contentRepository.fetchEvent(id: lease.contentID)
            #expect(saved.latitude == 47.2692)
            #expect(saved.longitude == 11.4041)
            #expect(saved.title == editor.title)
            #expect(saved.source.organizationId == "organization-1")
            try await contentRepository.deleteEvent(id: lease.contentID)
            return result
        }
    }

    private func makeLease(
        for draft: OwnerContentDraft,
        contentAlreadyExists: Bool
    ) -> OwnerContentPublicationLease {
        OwnerContentPublicationLease(
            draftID: draft.id,
            kind: draft.kind,
            contentID: "planning-\(draft.id)",
            leaseID: "lease-1",
            expiresAt: Date().addingTimeInterval(600),
            contentAlreadyExists: contentAlreadyExists,
            existingModerationStatus: contentAlreadyExists ? .approved : nil,
            existingScheduledAt: nil
        )
    }

    private func makeDraft(
        id: String,
        state: OwnerContentDraftState = .readyForReview,
        kind: OwnerContentDraftKind = .news
    ) -> OwnerContentDraft {
        OwnerContentDraft(
            id: id,
            schemaVersion: 3,
            ownerUserID: "owner",
            kind: kind,
            state: state,
            title: "Test",
            sourceReferences: [],
            verificationNotes: [],
            missingFields: [],
            newsDraft: nil,
            eventDraft: nil,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2),
            scheduledAt: nil,
            completedAt: state == .completed ? Date(timeIntervalSince1970: 3) : nil,
            archivedAt: nil,
            failureMessage: nil,
            publicationLeaseExpiresAt: nil,
            generatedImage: nil,
            publishedContentID: state == .completed ? "news-1" : nil,
            publishedContentKind: state == .completed ? .news : nil,
            publishedOrganizationID: state == .completed ? "org-1" : nil,
            publishedOrganizationName: state == .completed ? "Organization" : nil,
            publicationOutcome: state == .completed ? .approved : nil
        )
    }
}
