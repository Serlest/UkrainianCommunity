import Foundation

nonisolated struct BlockedUser: Identifiable, Equatable {
    let targetUserId: String
    let displayName: String
    let avatarURL: URL?
    let blockedAt: Date
    let updatedAt: Date

    var id: String { targetUserId }
}

nonisolated struct UserBlockMutationReceipt: Equatable {
    let targetUserId: String
    let isBlocked: Bool
    let displayName: String
    let avatarURL: URL?
    let updatedAt: Date
}

nonisolated enum UserBlockingError: Error, Equatable {
    case authenticationRequired
    case permissionDenied
    case ownAccount
    case targetUnavailable
    case network
    case malformedResponse
    case unknown
}
