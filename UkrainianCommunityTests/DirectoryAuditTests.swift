import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct DirectoryAuditTests {
    @Test func blockedOwnerCannotEditDirectory() {
        let store = DirectoryContentStore(cacheURL: nil)
        let user = MockContentBuilder.ownerUser()
        store.configure(user: user)
        #expect(store.canEdit)
        let blocked = AppUser(id: user.id, fullName: "Owner", displayName: "Owner", city: "Wien", email: "owner@example.test", bio: "", role: .owner, globalRole: .owner, blockState: .blocked, createdAt: .now, updatedAt: .now)
        store.configure(user: blocked)
        #expect(!store.canEdit)
    }
    @Test func sameCandidateQueryRefreshKeepsConfirmedRowsWhenOffline() async {
        var fail = false
        let target = MockContentBuilder.ownerUser()
        let store = DirectoryEditorCandidatesStore(page: { _, _, _ in
            if fail { throw AppError.network }
            return UserDirectoryPage(users: [target], organizations: [], total: 1, cursor: "next")
        })
        await store.load(actorID: "owner", query: "Name")
        fail = true
        await store.load(actorID: "owner", query: "Name")
        #expect(store.users.map(\.id) == [target.id])
        #expect(store.loadFailed)
    }
}

@MainActor
struct DirectoryPublicationAuditTests {
    @Test func saveRoundTripsAllFieldsAndRejectsDuplicateAndLateAccountResponse() async throws {
        var release: CheckedContinuation<DirectoryContentAPI.Receipt, Error>?
        var calls = 0
        let api = DirectoryContentAPI(save: { id, payload, revision in
            calls += 1
            let saved = try JSONDecoder().decode(DirectoryManagedCategory.self, from: Data(payload.utf8))
            #expect(saved.id == id && saved.title.german == "Geändert")
            return try await withCheckedThrowingContinuation { release = $0 }
        }, delete: { _, _ in throw AppError.permissionDenied })
        let store = DirectoryContentStore(cacheURL: nil, api: api)
        let owner = MockContentBuilder.ownerUser(); store.configure(user: owner)
        var category = DirectoryManagedCategory.bundled(DirectoryCatalog.categories[0])
        category.title = .init(ukrainian: category.title.ukrainian, german: "Geändert")
        let task = Task { try await store.save(category, expectedRevision: 1, actorID: owner.id) }
        while release == nil { await Task.yield() }
        do { try await store.save(category, expectedRevision: 1, actorID: owner.id); Issue.record("Duplicate write") } catch {}
        #expect(calls == 1)
        store.configure(user: nil)
        release?.resume(returning: .init(categoryID: category.id, revision: 2))
        do { try await task.value; Issue.record("Old account save must not update the UI") } catch {}
        #expect(store.published[category.id] == nil)
    }
    @Test func confirmedSaveCanBeIndependentlyReopenedAndDeleted() async throws {
        var savedPayload: String?
        let api = DirectoryContentAPI(save: { id, payload, revision in savedPayload = payload; return .init(categoryID: id, revision: revision + 1) },
            delete: { id, revision in .init(categoryID: id, revision: revision + 1) })
        let store = DirectoryContentStore(cacheURL: nil, api: api)
        let owner = MockContentBuilder.ownerUser(); store.configure(user: owner)
        var category = DirectoryManagedCategory.bundled(DirectoryCatalog.categories[0])
        category.id = "custom-12345678-1234-1234-1234-123456789abc"
        try await store.save(category, expectedRevision: 0, actorID: owner.id)
        let decoded = try JSONDecoder().decode(DirectoryManagedCategory.self, from: Data(try #require(savedPayload).utf8))
        #expect(decoded == category)
        #expect(store.category(category.id) == decoded && store.revision(category.id) == 1)
        store.applySnapshot([:], cached: false, activateAuthority: true)
        #expect(store.category(category.id) == decoded, "Older queued snapshot must not remove a just-confirmed publication")
        store.applySnapshot([category.id: .init(content: decoded, revision: 1, updatedAt: nil)], cached: false)
        store.applySnapshot([:], cached: false)
        #expect(store.category(category.id) == decoded, "Acknowledgement must not let an older refresh roll back the publication")
        try await store.deleteCustomCategory(category.id, expectedRevision: 1, actorID: owner.id)
        store.applySnapshot([category.id: .init(content: category, revision: 1, updatedAt: nil)], cached: false)
        #expect(store.category(category.id) == nil, "Older queued snapshot must not restore a just-deleted category")
    }
}
