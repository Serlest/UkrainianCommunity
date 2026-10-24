import Foundation

struct MockUserRepository: UserRepository {
    private let store = MockRepositoryStore.shared

    func fetchCurrentUser() async throws -> AppUser {
        await store.user
    }

    func fetchSettings() async throws -> UserSettings {
        .stored
    }

    func updateProfile(_ profile: EditableUserProfileDraft) async throws -> AppUser {
#if DEBUG && targetEnvironment(simulator)
        let pendingFixture = ProcessInfo.processInfo.arguments.contains("-ui-testing")
            && ProcessInfo.processInfo.environment["UITestProfileSaveReadback"] == "1"
        if pendingFixture { try await Task.sleep(for: .seconds(3)) }
#endif
        let user = await store.updateUserProfile(profile)
#if DEBUG && targetEnvironment(simulator)
        if pendingFixture { throw ProfileSaveReadbackPending(userID: user.id) }
#endif
        return user
    }

    func deleteAccount(currentUser: AppUser) async throws {
    }
}
