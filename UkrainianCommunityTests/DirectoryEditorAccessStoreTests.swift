import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct DirectoryEditorAccessStoreTests {
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
