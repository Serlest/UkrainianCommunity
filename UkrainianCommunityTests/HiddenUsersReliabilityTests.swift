import Testing
import Foundation
@testable import UkrainianCommunity

@Suite @MainActor
struct HiddenUsersReliabilityTests {
    private func blocked(_ name: String = "Target") -> BlockedUser {
        .init(targetUserId: "target", displayName: name, avatarURL: nil, blockedAt: .now, updatedAt: .now)
    }

    @Test func loadAndMutationFailuresRemainRetryableWithoutLosingTheTarget() async {
        let repository = HiddenUsersAuditRepository()
        repository.users = [blocked()]; repository.readError = .network
        let coordinator = UserBlockingCoordinator(repository: repository)
        await coordinator.configure(userID: "first")
        #expect(coordinator.loadErrorMessage != nil)
        #expect(!coordinator.isLoading)
        repository.readError = nil
        await coordinator.reload()
        #expect(coordinator.blockedUserIDs == ["target"])
        repository.mutationError = .permissionDenied
        await coordinator.unblock(blocked())
        #expect(coordinator.blockedUserIDs == ["target"])
        #expect(coordinator.errorMessage != nil)
        #expect(coordinator.mutatingUserIDs.isEmpty)
        repository.mutationError = nil
        await coordinator.unblock(blocked())
        #expect(coordinator.blockedUsers.isEmpty)
        #expect(coordinator.errorMessage == nil)
        #expect(repository.targets == ["target", "target"])
    }

    @Test func oldAccountUnblockCannotRemoveTheNewAccountsSameTarget() async {
        let repository = HiddenUsersAuditRepository()
        repository.users = [blocked("First account target")]
        let coordinator = UserBlockingCoordinator(repository: repository)
        await coordinator.configure(userID: "first")
        repository.holdMutation = true
        let task = Task { await coordinator.unblock(blocked()) }
        while repository.continuation == nil { await Task.yield() }
        repository.users = [blocked("Second account target")]
        await coordinator.configure(userID: "second")
        repository.continuation?.resume(returning: .init(targetUserId: "target", isBlocked: false, displayName: "First account target", avatarURL: nil, updatedAt: .now))
        repository.continuation = nil
        await task.value
        #expect(coordinator.blockedUsers.map(\.displayName) == ["Second account target"])
        #expect(coordinator.errorMessage == nil)
    }

    @Test func wrongTargetReceiptCannotUnblockAnotherRelationship() async {
        let repository = HiddenUsersAuditRepository(); repository.users = [blocked()]
        let coordinator = UserBlockingCoordinator(repository: repository)
        await coordinator.configure(userID: "first")
        repository.receiptTarget = "different-target"
        await coordinator.unblock(blocked())
        #expect(coordinator.blockedUserIDs == ["target"])
        #expect(coordinator.errorMessage != nil)
        repository.readError = .network
        await coordinator.reload()
        #expect(coordinator.blockedUserIDs == ["target"])
        #expect(coordinator.loadErrorMessage != nil)
    }
}

@MainActor
private final class HiddenUsersAuditRepository: UserBlockingRepository {
    var users: [BlockedUser] = []
    var readError: UserBlockingError?
    var mutationError: UserBlockingError?
    var receiptTarget: String?
    var holdMutation = false
    var targets: [String] = []
    var continuation: CheckedContinuation<UserBlockMutationReceipt, Error>?

    func fetchBlockedUsers(userID: String) async throws -> [BlockedUser] {
        if let readError { throw readError }
        return users
    }
    func setBlocked(targetUserID: String, isBlocked: Bool) async throws -> UserBlockMutationReceipt {
        targets.append(targetUserID)
        if let mutationError { throw mutationError }
        if holdMutation {
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }
        return .init(targetUserId: receiptTarget ?? targetUserID, isBlocked: isBlocked,
                     displayName: "Target", avatarURL: nil, updatedAt: .now)
    }
}
