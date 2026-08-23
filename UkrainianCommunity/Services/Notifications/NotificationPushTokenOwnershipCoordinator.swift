import Foundation

enum NotificationPushTokenOwnershipError: Error {
    case pendingMutationTimedOut
}

@MainActor
final class NotificationPushTokenOwnershipCoordinator {
    private static let pendingMutationTimeout: Duration = .seconds(10)
    private static let pendingMutationPollInterval: Duration = .milliseconds(50)

    private var repository: NotificationPushTokenRepository
    private(set) var currentUserID: String?
    private var currentToken: String?
    private var lastSavedTokenKey: String?
    private var inFlightTokenKeys: Set<String> = []
    private var tokensPendingDeletion: Set<String> = []
    private var notificationsEnabled = false
    private var isPreparingForSignOut = false

    init(repository: NotificationPushTokenRepository) {
        self.repository = repository
    }

    func configure(repository: NotificationPushTokenRepository) {
        self.repository = repository
    }

    func configureUser(_ userID: String?, notificationsEnabled: Bool) {
        if currentUserID != userID {
            lastSavedTokenKey = nil
        }

        currentUserID = userID
        self.notificationsEnabled = userID != nil && notificationsEnabled

        if userID == nil {
            isPreparingForSignOut = false
        }
    }

    func setNotificationsEnabled(_ isEnabled: Bool) {
        notificationsEnabled = currentUserID != nil && isEnabled
    }

    func receiveToken(_ rawToken: String?) async {
        guard let token = normalizedToken(rawToken) else { return }

        let previousToken = currentToken
        let previousSavedTokenKey = lastSavedTokenKey
        currentToken = token

        guard notificationsEnabled,
              !isPreparingForSignOut,
              let userID = currentUserID else { return }

        let newTokenKey = tokenKey(userID: userID, token: token)
        if lastSavedTokenKey == newTokenKey {
            try? await deletePendingTokens(userID: userID)
            return
        }
        guard !inFlightTokenKeys.contains(newTokenKey) else { return }

        inFlightTokenKeys.insert(newTokenKey)
        defer { inFlightTokenKeys.remove(newTokenKey) }

        do {
            try await repository.saveCurrentDeviceToken(userID: userID, token: token)
            lastSavedTokenKey = newTokenKey

            if let previousToken,
               previousToken != token,
               previousSavedTokenKey == tokenKey(userID: userID, token: previousToken) {
                tokensPendingDeletion.insert(previousToken)
                try await deletePendingTokens(userID: userID)
            }
        } catch {
            // A later token callback, lifecycle event, or sign-out retries the
            // unfinished upload or stale-token cleanup.
        }
    }

    func saveCachedTokenIfNeeded() async {
        await receiveToken(currentToken)
    }

    func removeCurrentToken() async {
        notificationsEnabled = false
        guard let userID = currentUserID,
              let token = currentToken else { return }

        do {
            try await waitForPendingMutations(userID: userID)
            try await deletePendingTokens(userID: userID)
            try await repository.deleteCurrentDeviceToken(userID: userID, token: token)
            clearSavedTokenKey(userID: userID, token: token)
        } catch {
            // Preference changes remain usable offline; the next authenticated
            // lifecycle event retries cleanup.
        }
    }

    func prepareForSignOut() async throws {
        isPreparingForSignOut = true

        do {
            guard let userID = currentUserID,
                  let token = currentToken else { return }

            try await waitForPendingMutations(userID: userID)
            try await deletePendingTokens(userID: userID)
            try await repository.deleteCurrentDeviceToken(userID: userID, token: token)
            clearSavedTokenKey(userID: userID, token: token)
        } catch {
            isPreparingForSignOut = false
            throw error
        }
    }

    func completeSignOut() {
        currentUserID = nil
        lastSavedTokenKey = nil
        tokensPendingDeletion.removeAll()
        notificationsEnabled = false
        isPreparingForSignOut = false
    }

    func resumeAfterFailedSignOut() async {
        isPreparingForSignOut = false
        await saveCachedTokenIfNeeded()
    }

    private func waitForPendingMutations(userID: String) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.pendingMutationTimeout)

        while inFlightTokenKeys.contains(where: { $0.hasPrefix("\(userID):") }) {
            guard clock.now < deadline else {
                throw NotificationPushTokenOwnershipError.pendingMutationTimedOut
            }
            try await Task.sleep(for: Self.pendingMutationPollInterval)
        }
    }

    private func clearSavedTokenKey(userID: String, token: String) {
        let key = tokenKey(userID: userID, token: token)
        if lastSavedTokenKey == key {
            lastSavedTokenKey = nil
        }
    }

    private func deletePendingTokens(userID: String) async throws {
        for token in tokensPendingDeletion.sorted() {
            try await repository.deleteCurrentDeviceToken(userID: userID, token: token)
            tokensPendingDeletion.remove(token)
        }
    }

    private func tokenKey(userID: String, token: String) -> String {
        "\(userID):\(token)"
    }

    private func normalizedToken(_ token: String?) -> String? {
        guard let token = token?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else { return nil }
        return token
    }
}
