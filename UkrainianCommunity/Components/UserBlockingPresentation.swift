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

    init(repository: UserBlockingRepository) {
        self.repository = repository
    }

    var blockedUserIDs: Set<String> {
        Set(blockedUsers.map(\.targetUserId))
    }

    func configure(userID: String?) async {
        guard configuredUserID != userID else { return }
        configuredUserID = userID
        pendingTarget = nil
        errorMessage = nil
        loadErrorMessage = nil
        blockedUsers = []
        guard let userID else { return }

        isLoading = true
        defer { isLoading = false }
        do {
            blockedUsers = try await repository.fetchBlockedUsers(userID: userID)
            loadErrorMessage = nil
        } catch {
            loadErrorMessage = Self.message(for: error)
        }
    }

    func reload() async {
        guard let userID = configuredUserID else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            blockedUsers = try await repository.fetchBlockedUsers(userID: userID)
            loadErrorMessage = nil
        } catch {
            loadErrorMessage = Self.message(for: error)
        }
    }

    func present(_ target: UserBlockTarget) {
        guard !blockedUserIDs.contains(target.userId) else { return }
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
        guard !mutatingUserIDs.contains(targetUserID) else { return }
        mutatingUserIDs.insert(targetUserID)
        defer { mutatingUserIDs.remove(targetUserID) }

        do {
            let receipt = try await repository.setBlocked(
                targetUserID: targetUserID,
                isBlocked: isBlocked
            )
            if receipt.isBlocked {
                blockedUsers.removeAll { $0.targetUserId == receipt.targetUserId }
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
            } else {
                blockedUsers.removeAll { $0.targetUserId == receipt.targetUserId }
            }
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private static func message(for error: Error) -> String {
        guard let error = error as? UserBlockingError else {
            return AppStrings.Safety.blockErrorUnknown
        }
        switch error {
        case .authenticationRequired:
            AppStrings.Safety.blockErrorAuthentication
        case .permissionDenied:
            AppStrings.Safety.blockErrorPermission
        case .ownAccount:
            AppStrings.Safety.blockErrorOwnAccount
        case .targetUnavailable:
            AppStrings.Safety.blockErrorUnavailable
        case .network:
            AppStrings.Safety.blockErrorNetwork
        case .malformedResponse, .unknown:
            AppStrings.Safety.blockErrorUnknown
        }
    }
}
