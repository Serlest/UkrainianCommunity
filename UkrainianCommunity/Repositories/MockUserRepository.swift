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
        await store.updateUserProfile(profile)
    }

    func deleteAccount(currentUser: AppUser) async throws {
    }
}
