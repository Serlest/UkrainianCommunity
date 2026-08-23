import Foundation

protocol UserBlockingRepository {
    func fetchBlockedUsers(userID: String) async throws -> [BlockedUser]
    func setBlocked(targetUserID: String, isBlocked: Bool) async throws -> UserBlockMutationReceipt
}

struct MockUserBlockingRepository: UserBlockingRepository {
    var blockedUsers: [BlockedUser] = []

    func fetchBlockedUsers(userID: String) async throws -> [BlockedUser] {
        blockedUsers
    }

    func setBlocked(targetUserID: String, isBlocked: Bool) async throws -> UserBlockMutationReceipt {
        let existing = blockedUsers.first { $0.targetUserId == targetUserID }
        return UserBlockMutationReceipt(
            targetUserId: targetUserID,
            isBlocked: isBlocked,
            displayName: existing?.displayName ?? "Community member",
            avatarURL: existing?.avatarURL,
            updatedAt: .now
        )
    }
}
