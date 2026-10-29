import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct DirectoryEditorAccessStoreTests {
    @Test func duplicateCandidateAppearanceDoesNotRestartTheSameRead() async {
        var reads = 0
        let model = DirectoryEditorCandidatesStore(page: { _, _, _ in
            reads += 1
            try await Task.sleep(for: .milliseconds(30))
            return .init(users: [], organizations: [], total: 0, cursor: nil)
        })
        let first = Task { await model.load(actorID: "owner", query: "same") }
        await Task.yield()
        await model.load(actorID: "owner", query: "same")
        await first.value
        #expect(reads == 1); #expect(model.hasLoaded); #expect(!model.isLoading)
    }
    private func user(name: String = "Olena Levytska", email: String = "olena@example.test") -> AppUser {
        AppUser(id: "editor-1", fullName: name, displayName: name, city: "Wien", email: email,
                bio: "", role: .user, blockState: .active, createdAt: .now, updatedAt: .now)
    }

    @Test func grantingImmediatelyKeepsNameAndEmailWithoutAnotherProfileRequest() async {
        let target = user()
        var grants = Set<String>()
        let store = DirectoryEditorAccessStore(api: .init(
            enabledIDs: { grants }, user: { _ in Issue.record("Known user's identity must not require another read"); return nil },
            setAccess: { enabled, id, actor in
                #expect(actor == "owner-1")
                if enabled { grants.insert(id) } else { grants.remove(id) }
            }
        ))
        await store.load(actorID: "owner-1")
        await store.setAccess(true, userID: target.id, knownUser: target, actorID: "owner-1")
        #expect(store.editorIDs == [target.id])
        #expect(store.profiles[target.id]?.preferredDisplayName == "Olena Levytska")
        #expect(store.profiles[target.id]?.email == "olena@example.test")
        await store.setAccess(false, userID: target.id, actorID: "owner-1")
        #expect(grants.isEmpty && store.editorIDs.isEmpty && store.profiles.isEmpty)
    }

    @Test func reopeningResolvesExistingGrantsAndRefreshesChangedProfile() async {
        var target = user()
        let store = DirectoryEditorAccessStore(api: .init(
            enabledIDs: { ["editor-1"] }, user: { _ in target }, setAccess: { _, _, _ in }
        ))
        await store.load(actorID: "owner-1")
        #expect(store.profiles[target.id]?.email == "olena@example.test")
        target = user(name: "Olena Updated", email: "new@example.test")
        await store.load(actorID: "owner-1")
        #expect(store.profiles[target.id]?.preferredDisplayName == "Olena Updated")
        #expect(store.profiles[target.id]?.email == "new@example.test")
    }

    @Test func failedIdentityReadCanBeRetriedAndDoesNotDiscardGrant() async {
        let target = user()
        var fail = true
        let store = DirectoryEditorAccessStore(api: .init(
            enabledIDs: { [target.id] }, user: { _ in
                if fail { throw AppError.network }
                return target
            }, setAccess: { _, _, _ in }
        ))
        await store.load(actorID: "owner-1")
        #expect(store.editorIDs.contains(target.id))
        #expect(store.failedProfileIDs.contains(target.id))
        fail = false
        await store.loadProfile(target.id, actorID: "owner-1")
        #expect(store.failedProfileIDs.isEmpty)
        #expect(store.profiles[target.id]?.email == target.email)
    }

    @Test func failedGrantListReadDoesNotPretendThereAreNoEditors() async {
        let target = user()
        var fail = false
        let store = DirectoryEditorAccessStore(api: .init(
            enabledIDs: {
                if fail { throw AppError.network }
                return [target.id]
            }, user: { _ in target }, setAccess: { _, _, _ in }
        ))
        await store.load(actorID: "owner-1")
        fail = true
        await store.load(actorID: "owner-1")
        #expect(store.loadFailed && !store.isLoading)
        #expect(store.editorIDs.contains(target.id))
        #expect(store.profiles[target.id]?.email == target.email)
        fail = false
        await store.load(actorID: "owner-1")
        #expect(!store.loadFailed)
    }

    @Test func deletedAccountAndRejectedRevocationRemainExplicit() async {
        let store = DirectoryEditorAccessStore(api: .init(
            enabledIDs: { ["editor-1"] }, user: { _ in nil },
            setAccess: { _, _, _ in throw AppError.permissionDenied }
        ))
        await store.load(actorID: "owner-1")
        #expect(store.missingProfileIDs == ["editor-1"])
        await store.setAccess(false, userID: "editor-1", actorID: "owner-1")
        #expect(store.editorIDs == ["editor-1"])
        #expect(store.errorMessage != nil && store.busyIDs.isEmpty)
    }
}

@MainActor struct DirectoryAccessReviewedTests {
    @Test func rightsAvailableWhileProfileIsLoadingAndOldProfileResponseCannotRestoreRevokedAccess() async {
        let previous = DirectoryEditorGrant(id: "editor", enabled: true, revision: "reviewed", grantedAt: 1000)
        var resume: CheckedContinuation<[AppUser], any Error>?
        let store = DirectoryEditorAccessStore(api: .init(enabledIDs: { [] }, user: { _ in nil }, setAccess: { _,_,_ in },
            page: { _,_ in DirectoryEditorGrantPage(grants: [previous]) },
            mutate: { _, reviewed, enabled, _ in
                #expect(reviewed == previous && !enabled)
                return .init(id: reviewed.id, enabled: false, revision: "revoked", grantedAt: nil)
            }, profiles: { _ in try await withCheckedThrowingContinuation { resume = $0 } }))
        let load = Task { await store.load(actorID: "owner") }
        while resume == nil { await Task.yield() }
        #expect(!store.isLoading && store.editorIDs == ["editor"])
        await store.setAccess(false, userID: "editor", actorID: "owner", reviewed: previous)
        resume?.resume(returning: [])
        await load.value
        #expect(store.editorIDs.isEmpty && store.profiles.isEmpty && store.missingProfileIDs.isEmpty)
        #expect(store.grants["editor"]?.revision == "revoked")
    }
    @Test func mutationReusesOperationAfterNetworkFailureAndCannotWriteIntoAnotherSession() async {
        let previous = DirectoryEditorGrant(id: "editor", enabled: true, revision: "reviewed", grantedAt: nil)
        var operations: [String] = []
        var resume: CheckedContinuation<DirectoryEditorGrant, any Error>?
        let store = DirectoryEditorAccessStore(api: .init(enabledIDs: { [] }, user: { _ in nil }, setAccess: { _,_,_ in },
            page: { _,_ in DirectoryEditorGrantPage(grants: [previous]) },
            mutate: { _, _, _, operation in
                operations.append(operation)
                if operations.count == 1 { throw AppError.network }
                return try await withCheckedThrowingContinuation { resume = $0 }
            }))
        await store.load(actorID: "owner")
        await store.setAccess(false, userID: "editor", actorID: "owner", reviewed: previous)
        let mutation = Task { await store.setAccess(false, userID: "editor", actorID: "owner", reviewed: previous) }
        while resume == nil { await Task.yield() }
        #expect(operations.count == 2 && operations[0] == operations[1])
        store.reset()
        await store.load(actorID: "owner")
        resume?.resume(returning: .init(id: "editor", enabled: false, revision: "new", grantedAt: nil))
        await mutation.value
        #expect(store.grants["editor"] == previous && store.editorIDs == ["editor"])
    }
    @Test func candidateSearchPagesBeyond100AndDiscardsLateAccountResponse() async {
        func user(_ id: Int) -> AppUser { .init(id: "candidate-\(id)", fullName: "Candidate \(id)", displayName: "Candidate \(id)", city: "", email: "\(id)@example.test", bio: "", role: .user, blockState: .active, createdAt: .now, updatedAt: .now) }
        var resume: CheckedContinuation<UserDirectoryPage, any Error>?
        let store = DirectoryEditorCandidatesStore(page: { actor, _, cursor in
            if actor == "old" { return try await withCheckedThrowingContinuation { resume = $0 } }
            let start = cursor.flatMap(Int.init) ?? 0, end = min(start + 40, 137)
            return UserDirectoryPage(users: (start..<end).map(user), organizations: [], total: 137, cursor: end < 137 ? String(end) : nil)
        })
        await store.load(actorID: "owner", query: "Candidate")
        while store.canLoadMore { await store.loadMore() }
        #expect(store.users.count == 137 && store.total == 137)
        let old = Task { await store.load(actorID: "old", query: "old") }
        while resume == nil { await Task.yield() }
        await store.load(actorID: "new", query: "new")
        resume?.resume(returning: UserDirectoryPage(users: [], organizations: [], total: 0, cursor: nil))
        await old.value
        #expect(store.users.count == 40 && store.total == 137 && !store.isLoading)
    }
}
