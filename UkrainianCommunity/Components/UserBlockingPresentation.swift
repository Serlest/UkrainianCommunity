import Combine
import SwiftUI

struct UserBlockingPresentationConfiguration {
    var present: (UserBlockTarget) -> Void

    static let unavailable = UserBlockingPresentationConfiguration(present: { _ in })
}

private struct UserBlockingPresentationConfigurationKey: EnvironmentKey {
    static let defaultValue = UserBlockingPresentationConfiguration.unavailable
}

extension EnvironmentValues {
    var userBlockingPresentation: UserBlockingPresentationConfiguration {
        get { self[UserBlockingPresentationConfigurationKey.self] }
        set { self[UserBlockingPresentationConfigurationKey.self] = newValue }
    }
}

@MainActor
final class UserBlockingCoordinator: ObservableObject {
    @Published private(set) var blockedUsers: [BlockedUser] = []
    @Published private(set) var isLoading = false
    @Published private(set) var mutatingUserIDs = Set<String>()
    @Published private(set) var loadErrorMessage: String?
    @Published var pendingTarget: UserBlockTarget?
    @Published var errorMessage: String?

    private let repository: UserBlockingRepository
    private var configuredUserID: String?
    private var sessionGeneration = 0
    private var loadGeneration = 0

    init(repository: UserBlockingRepository) {
        self.repository = repository
    }

    var blockedUserIDs: Set<String> {
        Set(blockedUsers.map(\.targetUserId))
    }

    func configure(userID: String?) async {
        if configuredUserID == userID {
            guard let userID else { return }
            await reload(expectedUserID: userID)
            return
        }
        configuredUserID = userID
        sessionGeneration += 1
        loadGeneration += 1
        pendingTarget = nil
        errorMessage = nil
        loadErrorMessage = nil
        isLoading = false
        mutatingUserIDs = []
        blockedUsers = []
        guard let userID else { return }
        await reload(expectedUserID: userID)
    }

    func reload() async {
        guard let userID = configuredUserID else { return }
        await reload(expectedUserID: userID)
    }

    private func reload(expectedUserID userID: String) async {
        guard configuredUserID == userID, mutatingUserIDs.isEmpty else { return }
        loadGeneration += 1
        let requestLoadGeneration = loadGeneration
        let requestSessionGeneration = sessionGeneration
        isLoading = true
        defer {
            if sessionGeneration == requestSessionGeneration,
               loadGeneration == requestLoadGeneration {
                isLoading = false
            }
        }
        do {
            let users = try await RefreshRequest.run {
                try await self.repository.fetchBlockedUsers(userID: userID)
            }
            guard isCurrentSession(userID, generation: requestSessionGeneration),
                  loadGeneration == requestLoadGeneration else { return }
            blockedUsers = users
            loadErrorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentSession(userID, generation: requestSessionGeneration),
                  loadGeneration == requestLoadGeneration else { return }
            loadErrorMessage = Self.message(for: error)
        }
    }

    func present(_ target: UserBlockTarget) {
        guard configuredUserID != nil,
              mutatingUserIDs.isEmpty,
              !blockedUserIDs.contains(target.userId) else { return }
        errorMessage = nil
        pendingTarget = target
    }

    func confirmPendingBlock() async {
        guard let target = pendingTarget else { return }
        pendingTarget = nil
        await setBlocked(targetUserID: target.userId, isBlocked: true)
    }

    func unblock(_ user: BlockedUser) async {
        await setBlocked(targetUserID: user.targetUserId, isBlocked: false)
    }

    private func setBlocked(targetUserID: String, isBlocked: Bool) async {
        guard let userID = configuredUserID,
              mutatingUserIDs.isEmpty else { return }
        let requestSessionGeneration = sessionGeneration
        loadGeneration += 1
        isLoading = false
        errorMessage = nil
        mutatingUserIDs.insert(targetUserID)
        defer {
            if isCurrentSession(userID, generation: requestSessionGeneration) {
                mutatingUserIDs.remove(targetUserID)
            }
        }

        do {
            let receipt = try await repository.setBlocked(
                targetUserID: targetUserID,
                isBlocked: isBlocked
            )
            guard isCurrentSession(userID, generation: requestSessionGeneration) else { return }
            guard receipt.targetUserId == targetUserID,
                  receipt.isBlocked == isBlocked else {
                throw UserBlockingError.malformedResponse
            }
            apply(receipt)
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentSession(userID, generation: requestSessionGeneration) else { return }
            if Self.requiresReconciliation(error),
               await reconcile(
                userID: userID,
                targetUserID: targetUserID,
                expectedBlocked: isBlocked,
                sessionGeneration: requestSessionGeneration
               ) {
                errorMessage = nil
                return
            }
            guard isCurrentSession(userID, generation: requestSessionGeneration) else { return }
            errorMessage = Self.message(for: error)
        }
    }

    private func reconcile(
        userID: String,
        targetUserID: String,
        expectedBlocked: Bool,
        sessionGeneration: Int
    ) async -> Bool {
        do {
            let users = try await RefreshRequest.run {
                try await self.repository.fetchBlockedUsers(userID: userID)
            }
            guard isCurrentSession(userID, generation: sessionGeneration) else { return false }
            blockedUsers = users
            loadErrorMessage = nil
            return users.contains { $0.targetUserId == targetUserID } == expectedBlocked
        } catch {
            return false
        }
    }

    private func apply(_ receipt: UserBlockMutationReceipt) {
        blockedUsers.removeAll { $0.targetUserId == receipt.targetUserId }
        guard receipt.isBlocked else { return }
        blockedUsers.insert(
            BlockedUser(
                targetUserId: receipt.targetUserId,
                displayName: receipt.displayName,
                avatarURL: receipt.avatarURL,
                blockedAt: receipt.updatedAt,
                updatedAt: receipt.updatedAt
            ),
            at: 0
        )
    }

    private func isCurrentSession(_ userID: String, generation: Int) -> Bool {
        configuredUserID == userID && sessionGeneration == generation
    }

    private static func requiresReconciliation(_ error: Error) -> Bool {
        guard let error = error as? UserBlockingError else { return true }
        switch error {
        case .network, .malformedResponse, .unknown:
            return true
        case .authenticationRequired, .permissionDenied, .ownAccount, .targetUnavailable:
            return false
        }
    }

    private static func message(for error: Error) -> String {
        if let error = error as? AppError {
            switch error {
            case .network:
                return AppStrings.Safety.blockErrorNetwork
            case .permissionDenied:
                return AppStrings.Safety.blockErrorPermission
            case .validationFailed, .notFound, .unknown:
                return AppStrings.Safety.blockErrorUnknown
            }
        }
        guard let error = error as? UserBlockingError else {
            return AppStrings.Safety.blockErrorUnknown
        }
        switch error {
        case .authenticationRequired:
            return AppStrings.Safety.blockErrorAuthentication
        case .permissionDenied:
            return AppStrings.Safety.blockErrorPermission
        case .ownAccount:
            return AppStrings.Safety.blockErrorOwnAccount
        case .targetUnavailable:
            return AppStrings.Safety.blockErrorUnavailable
        case .network:
            return AppStrings.Safety.blockErrorNetwork
        case .malformedResponse, .unknown:
            return AppStrings.Safety.blockErrorUnknown
        }
    }
}
