import FirebaseFirestore
import Foundation
import Testing
@testable import UkrainianCommunity

@Suite(.serialized) @MainActor struct UserDirectoryTests {
    private func reads() -> UserManagementReads {
        .init(users: { _ in .init(users: [], cursor: nil, hasMore: false) }, user: { _ in nil }, organizations: { Issue.record("Directory must not eagerly fetch every organization"); return [] }, securityMetadata: { id in .init(response: .init(targetUserId: id, emailVerified: true, authDisabled: false, creationTime: nil, lastSignInTime: nil, providerIds: [])) }, totalCount: { 137 })
    }
    private func user(_ id: String) -> AppUser { UserManagementViewModel.makeUser(id: id, data: ["displayName": id,"accountStatus":"active","globalRole":"user"]) }
    @Test func organizationSnapshotCarriesExactRevisionAndStatus() {
        let model = UserManagementViewModel.makeManagedOrganization(id: "org", data: ["updatedAt": Timestamp(seconds: 123,nanoseconds:456789000),"moderationStatus":"archived"])
        #expect(model.asOrganization().accessRevision == "123:456789000")
        #expect(model.asOrganization().moderationStatus == .archived)
    }
    @Test func reviewedStateHashMatchesServerAndJournalReusesExactRequest() throws {
        let data: [String:Any] = ["accountStatus":"active","globalRole":"user","blockState":"warned","warningCount":3,"isBlocked":false,"statusUpdatedAt":Timestamp(seconds:12,nanoseconds:34)]
        let revision = UserManagementViewModel.adminReviewRevision(data)
        #expect(revision == "b67b214b23081af5639162586e602327df6ec8d90cc718613815f1fe61b313d3")
        var target = UserManagementViewModel.makeUser(id: "target",data:data)
        var journal = AdminUserMutationJournal()
        let firstValue = journal.request(actor:"owner",target:target,action:"suspended",reason:"Review",days:7,now:Date(timeIntervalSince1970:1000))
        let first = try #require(firstValue)
        let retryValue = journal.request(actor:"owner",target:target,action:"suspended",reason:"Review",days:7,now:Date(timeIntervalSince1970:2000))
        let retry = try #require(retryValue)
        #expect(first.review == retry.review); #expect(first.until == retry.until)
        target.managementRevision = "changed"
        let changed = journal.request(actor:"owner",target:target,action:"suspended",reason:"Review",days:7)
        #expect(changed?.review != first.review)
        let request = AccountStatusChangeFunctionRequest(targetUserId: target.id, reason: "Review", review: first.review)
        let encoded = try #require(JSONSerialization.jsonObject(with:JSONEncoder().encode(request)) as? [String:Any])
        #expect(encoded["principalId"] as? String == "owner"); #expect(encoded["expectedRevision"] as? String == revision)
    }
    @Test func directoryPassesAllFiltersAndPaginatesBeyond100WithoutClientSorting() async {
        let owner = MockContentBuilder.ownerUser(); let all = (0..<137).map { user(String(format:"user-%03d",$0)) }
        var calls:[UserDirectoryQuery] = []; var reader = reads()
        reader.directory = { _,query,cursor in
            calls.append(query); let start = cursor.flatMap(Int.init) ?? 0; let end = min(start+40,all.count)
            return .init(users:Array(all[start..<end]),organizations:[],total:all.count,cursor:end<all.count ? String(end):nil)
        }
        let model = UserManagementViewModel(reads:reader)
        let query = UserDirectoryQuery(search:"shared",region:"wien",filter:"banned",sort:"oldest")
        await model.loadDirectory(actor:owner,query:query)
        while model.directoryCursor != nil { await model.loadDirectory(actor:owner,query:query,more:true) }
        #expect(model.users.count == 137); #expect(Set(model.users.map(\.id)).count == 137)
        #expect(model.directoryTotal == 137); #expect(calls.count == 4); #expect(calls.allSatisfy { $0 == query })
    }
    @Test func staleQueryAndAccountResponsesCannotRestoreOldRows() async {
        let owner=MockContentBuilder.ownerUser();var reader=reads();let gate=DirectoryReadGate()
        reader.directory = { _,query,_ in
            if query.search == "old" { return await gate.wait() }
            return .init(users:[self.user("new")],organizations:[],total:1,cursor:nil)
        }
        let model=UserManagementViewModel(reads:reader)
        let pending=Task { await model.loadDirectory(actor:owner,query:.init(search:"old")) }
        while !gate.started { await Task.yield() }
        model.prepareDirectory();await model.loadDirectory(actor:owner,query:.init(search:"new"))
        gate.finish(.init(users:[user("old")],organizations:[],total:100,cursor:"old"));await pending.value
        #expect(model.users.map(\.id) == ["new"]);#expect(model.directoryCursor == nil)
        await model.loadDirectory(actor:nil,query:.init());#expect(model.users.isEmpty)
    }
    @Test func failedRefreshKeepsConfirmedRowsAndNextPageCursor() async {
        let owner = MockContentBuilder.ownerUser()
        var reader = reads(); var fails = false; var requested: [String?] = []
        reader.directory = { _, _, cursor in
            requested.append(cursor)
            if fails { throw AppError.network }
            return .init(users: [self.user(cursor == nil ? "first" : "second")], organizations: [], total: 2, cursor: cursor == nil ? "next-page" : nil)
        }
        let model = UserManagementViewModel(reads: reader)
        await model.loadDirectory(actor: owner, query: .init())
        fails = true
        await model.loadDirectory(actor: owner, query: .init())
        #expect(model.users.map(\.id) == ["first"])
        #expect(model.directoryCursor == "next-page")
        fails = false
        await model.loadDirectory(actor: owner, query: .init(), more: true)
        #expect(requested.last! == "next-page")
        #expect(model.users.map(\.id) == ["first", "second"])
    }
    @Test func preparingSameDirectoryDoesNotEraseConfirmedPage() async {
        var reader = reads()
        reader.directory = { _, _, _ in .init(users: [self.user("confirmed")], organizations: [], total: 2, cursor: "next") }
        let model = UserManagementViewModel(reads: reader)
        await model.loadDirectory(actor: MockContentBuilder.ownerUser(), query: .init())
        model.prepareDirectory()
        #expect(model.users.map(\.id) == ["confirmed"])
        #expect(model.directoryCursor == "next")
    }
    @Test func duplicateDirectoryRefreshesShareOneRequestAndBothAwaitIt() async {
        var reader = reads(); var calls = 0
        var releases: [CheckedContinuation<UserDirectoryPage, Never>] = []
        reader.directory = { _, _, _ in
            calls += 1
            return await withCheckedContinuation { releases.append($0) }
        }
        let model = UserManagementViewModel(reads: reader); let owner = MockContentBuilder.ownerUser()
        let first = Task { await model.loadDirectory(actor: owner, query: .init()) }
        while calls < 1 { await Task.yield() }
        let second = Task { await model.loadDirectory(actor: owner, query: .init()) }
        for _ in 0..<30 { await Task.yield() }
        #expect(calls == 1)
        let page = UserDirectoryPage(users: [user("shared")], organizations: [], total: 1, cursor: nil)
        for release in releases { release.resume(returning: page) }
        await first.value; await second.value
        #expect(model.users.map(\.id) == ["shared"])
    }
    @Test func deletedDetailIsRemovedFromConfirmedCachedUsers() async {
        var reader = reads()
        reader.directory = { _, _, _ in .init(users: [self.user("deleted")], organizations: [], total: 1, cursor: nil) }
        reader.memberships = { _, _ in [] }
        reader.user = { _ in nil }
        let model = UserManagementViewModel(reads: reader); let owner = MockContentBuilder.ownerUser()
        await model.loadDirectory(actor: owner, query: .init())
        await model.refreshDetail(userID: "deleted", actor: owner)
        #expect(model.user(withID: "deleted") == nil)
        #expect(model.error == .notFound)
    }
    @Test func freshMembershipReplacesAlreadyKnownOrganizationInsteadOfDroppingUpdate() async {
        let owner = MockContentBuilder.ownerUser(); var reader = reads()
        let old = ManagedOrganization(id: "shared", name: "Before", city: "", logoURL: nil, ownerId: owner.id, adminIds: [], moderatorIds: [])
        let updated = ManagedOrganization(id: "shared", name: "After", city: "", logoURL: nil, ownerId: owner.id, adminIds: ["member"], moderatorIds: [])
        reader.directory = { _, _, _ in .init(users: [self.user("member")], organizations: [old], total: 1, cursor: nil) }
        reader.memberships = { _, _ in [updated] }
        let model = UserManagementViewModel(reads: reader)
        await model.loadDirectory(actor: owner, query: .init())
        await model.loadMemberships(userID: "member", actor: owner)
        #expect(model.organizationRoles(for: user("member")).map(\.organization.name) == ["After"])
        #expect(model.organizations.count == 1)
    }
    @Test func reviewedActionRejectsChangedTargetAndDifferentCurrentPrincipal() async {
        let owner = MockContentBuilder.ownerUser()
        let original = user("member")
        var current = original; var reader = reads()
        reader.directory = { _, _, _ in .init(users: [original], organizations: [], total: 1, cursor: nil) }
        reader.memberships = { _, _ in [] }
        reader.user = { _ in current }
        let model = UserManagementViewModel(reads: reader)
        await model.loadDirectory(actor: owner, query: .init())
        #expect(!model.isReviewCurrent(target: original, actor: owner, currentActor: owner))
        await model.refreshDetail(userID: original.id, actor: owner)
        #expect(model.isReviewCurrent(target: original, actor: owner, currentActor: owner))
        #expect(!model.isReviewCurrent(target: original, actor: owner, currentActor: nil))
        #expect(!model.isReviewCurrent(target: original, actor: owner, currentActor: user("other")))
        current = UserManagementViewModel.makeUser(id: original.id, data: ["displayName":"member", "accountStatus":"warned", "globalRole":"user", "warningCount":1])
        await model.refreshDetail(userID: original.id, actor: owner)
        #expect(!model.isReviewCurrent(target: original, actor: owner, currentActor: owner))
        #expect(model.isReviewCurrent(target: current, actor: owner, currentActor: owner))
    }
    @Test func oldFilterLoadMoreCannotReplaceTheSelectedDirectory() async {
        var reader = reads(); var requested: [String] = []
        reader.directory = { _, query, _ in
            requested.append(query.filter)
            return .init(users: [self.user(query.filter)], organizations: [], total: 2, cursor: "next")
        }
        let owner = MockContentBuilder.ownerUser(); let model = UserManagementViewModel(reads: reader)
        await model.loadDirectory(actor: owner, query: .init(filter: "active"))
        await model.loadDirectory(actor: owner, query: .init(filter: "banned"))
        await model.loadDirectory(actor: owner, query: .init(filter: "active"), more: true)
        #expect(requested == ["active", "banned"])
        #expect(model.users.map(\.id) == ["banned"])
    }
    @Test func organizationChoicesAreOnDemandAndPaginated() async {
        let owner=MockContentBuilder.ownerUser();var reader=reads();var calls=0
        reader.directory={_,_,_ in .init(users:[self.user("member")],organizations:[],total:1,cursor:nil)}
        reader.organizationPage={_,search,cursor in calls+=1;return .init(organizations:[.init(id:cursor ?? search,name:"Org",city:"",logoURL:nil,ownerId:owner.id,adminIds:[],moderatorIds:[])],cursor:cursor==nil ? "second":nil)}
        let model=UserManagementViewModel(reads:reader);await model.loadDirectory(actor:owner,query:.init())
        #expect(calls==0);await model.loadOrganizationChoices(actor:owner,search:"first");await model.loadOrganizationChoices(actor:owner,search:"first",more:true)
        #expect(model.organizationChoices.count==2);#expect(model.organizationCursor==nil)
    }
}
@MainActor private final class DirectoryReadGate {
    var started=false
    private var continuation:CheckedContinuation<UserDirectoryPage,Never>?
    func wait() async -> UserDirectoryPage { started=true;return await withCheckedContinuation { continuation=$0 } }
    func finish(_ value:UserDirectoryPage) { continuation?.resume(returning:value);continuation=nil }
}
