import Foundation
import Testing
@testable import UkrainianCommunity

@Suite(.serialized) @MainActor
struct OrganizationManagementWorkspaceTests {
    @Test func appearanceKeepsConfirmedEmptyPageAndRefreshStillReconcilesServer() async {
        var reads = 0
        let model = OrganizationManagementListModel(repository: MockOrganizationRepository(), fetch: { _, _ in
            reads += 1
            try await Task.sleep(for: .milliseconds(30))
            return .init(items: [], cursor: nil)
        })
        let owner = MockContentBuilder.ownerUser()
        let first = Task { await model.loadIfNeeded(actor: owner, search: "", region: nil) }
        await Task.yield()
        await model.loadIfNeeded(actor: owner, search: "", region: nil)
        await first.value
        await model.loadIfNeeded(actor: owner, search: "", region: nil)
        #expect(reads == 1)
        await model.load(actor: owner, search: "", region: nil)
        #expect(reads == 2)
        await model.loadIfNeeded(actor: owner, search: "new", region: nil)
        #expect(reads == 3)
        model.reset()
        await model.loadIfNeeded(actor: owner, search: "new", region: nil)
        #expect(reads == 4)
    }
    private func org(_ id: String = "workspace", region: AustrianFederalState = .tirol) -> Organization {
        .init(id: id, name: id, description: "Organization", federalState: region, city: "Innsbruck", subscriberCount: 50000,
              ownerId: MockContentBuilder.ownerUser().id, adminIds: ["admin"], moderatorIds: ["moderator"],
              createdAt: .now, updatedAt: .now, moderationStatus: .approved, likeCount: 0, likeState: .notLiked)
    }
    @Test func roleJournalReusesExactOperationAndBindsAccountAndReviewedVersion() throws {
        var journal = OrganizationRoleRequestJournal(); var organization = org(); let owner = MockContentBuilder.ownerUser()
        organization.accessRevision = "1792670000:123456000"
        let first = journal.request(organization: organization, target: "admin", actor: owner, action: "remove", reason: "Review")
        let retry = journal.request(organization: organization, target: "admin", actor: owner, action: "remove", reason: "Review")
        #expect(first.operationId == retry.operationId); #expect(first.principalId == owner.id)
        #expect(first.expectedRevision == "1792670000:123456000"); #expect(first.expectedRole == "communityAdmin")
        organization.accessRevision = "1792670000:123457000"
        #expect(journal.request(organization: organization, target: "admin", actor: owner, action: "remove", reason: "Review").operationId != first.operationId)
        let legacy = OrganizationRoleChangeFunctionRequest(organizationId: "workspace", targetUserId: "admin")
        let fields = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        #expect(fields["expectedRevision"] == nil); #expect(fields["principalId"] == nil)
        let nilRevision = OrganizationRoleChangeFunctionRequest(organizationId: "workspace", targetUserId: "admin", operationId: "stable", principalId: owner.id, expectedRole: "communityAdmin")
        let modern = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(nilRevision)) as? [String: Any])
        #expect(modern["expectedRevision"] is NSNull)
    }
    @Test func managementListPagesAll137WithoutDuplicatesAndResetsForRegion() async {
        let all = (0..<137).map { org(String(format: "org-%03d", $0)) }
        var requests: [String?] = []
        let model = OrganizationManagementListModel(repository: MockOrganizationRepository(), fetch: { query, cursor in
            requests.append(cursor)
            if query.region == .wien { return .init(items: [], cursor: nil) }
            let next = all.filter { cursor == nil || $0.id > cursor! }; let page = Array(next.prefix(30))
            return .init(items: page, cursor: next.count > 30 ? page.last?.id : nil)
        })
        let owner = MockContentBuilder.ownerUser()
        await model.load(actor: owner, search: "", region: nil)
        #expect(model.organizations.count == 30); #expect(model.hasMore)
        while model.hasMore { await model.load(actor: owner, search: "", region: nil, more: true) }
        #expect(model.organizations.count == 137); #expect(Set(model.organizations.map(\.id)).count == 137)
        #expect(requests.count == 5)
        await model.load(actor: owner, search: "", region: .wien)
        #expect(model.organizations.isEmpty); #expect(!model.hasMore)
    }
    @Test func staleSearchCannotRestoreOldOrganizationsOrCursor() async {
        let sample = org()
        let model = OrganizationManagementListModel(repository: MockOrganizationRepository(), fetch: { query, _ in
            if query.search == "old" { try await Task.sleep(for: .milliseconds(100)); return .init(items: [sample], cursor: "next") }
            return .init(items: [], cursor: nil)
        })
        let owner = MockContentBuilder.ownerUser()
        let pending = Task { await model.load(actor: owner, search: "old", region: nil) }
        await Task.yield(); await model.load(actor: owner, search: "new", region: nil); await pending.value
        #expect(model.organizations.isEmpty); #expect(!model.hasMore); #expect(!model.isLoading)
    }
    @Test func teamIncludesOnlyThreeRoleHoldersDespiteFiftyThousandSubscribers() async {
        let model = OrganizationTeamViewModel(organizationRepository: MockOrganizationRepository())
        await model.load(organization: org(), actor: MockContentBuilder.ownerUser())
        #expect(model.members.count == 3); #expect(model.members.map(\.role) == [.owner, .admin, .moderator])
        #expect(model.members.allSatisfy { $0.role != .member }); #expect(model.errorMessage == nil)
    }
    @Test func candidateSearchPaginatesAndResetDropsPreviousAccountResponse() async {
        var received: [OrganizationWorkspaceRequest] = []
        let model = OrganizationTeamViewModel(organizationRepository: MockOrganizationRepository(), workspaceRead: { request in
            received.append(request)
            if request.search == "old" { try await Task.sleep(for: .milliseconds(100)) }
            let id = request.cursor == nil ? "candidate-a" : "candidate-b"
            return .init(cursor: request.cursor == nil ? "candidate-a" : nil, users: [.init(id: id, displayName: "Candidate", city: "Wien", federalState: "wien", avatarURL: nil)])
        })
        let owner = MockContentBuilder.ownerUser(), sample = org()
        await model.loadCandidateUsers(excluding: sample, actor: owner, search: "Candidate")
        #expect(model.candidateMembers.count == 1); #expect(model.hasMoreCandidates)
        await model.loadCandidateUsers(excluding: sample, actor: owner, search: "Candidate", more: true)
        #expect(model.candidateMembers.count == 2); #expect(!model.hasMoreCandidates); #expect(received.last?.cursor == "candidate-a")
        let pending = Task { await model.loadCandidateUsers(excluding: sample, actor: owner, search: "old") }
        await Task.yield(); model.reset(); await pending.value
        #expect(model.candidateMembers.isEmpty); #expect(!model.isLoadingCandidates)
    }
    @Test func contentListCountsAndStatusCursorAreAuthoritativeAndResetOnFilterChange() async {
        var queries: [OrganizationWorkspaceRequest] = []
        let model = OrganizationWorkspaceListModel(read: { request in
            queries.append(request)
            let item = OrganizationWorkspaceContent(id: request.cursor ?? "first", title: "News", status: .needsRevision, reason: "Correct source")
            return .init(cursor: request.cursor == nil ? "second" : nil, counts: ["needsRevision": 44], items: [item])
        })
        let request = OrganizationWorkspaceRequest(action: "content", principalId: "owner", organizationId: "workspace", contentType: "news", status: "needsRevision")
        await model.load(request); await model.load(request, more: true)
        #expect(model.items.count == 2); #expect(model.counts["needsRevision"] == 44); #expect(!model.hasMore)
        #expect(queries.last?.cursor == "second")
        model.reset(); #expect(model.items.isEmpty); #expect(model.counts.isEmpty)
    }
}
