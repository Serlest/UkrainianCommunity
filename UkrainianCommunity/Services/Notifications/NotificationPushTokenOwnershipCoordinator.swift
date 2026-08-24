import Foundation

enum NotificationPushTokenOwnershipError: Error {
    case pendingMutationTimedOut
}

@MainActor
final class NotificationPushTokenOwnershipCoordinator {
    private struct InFlightTokenMutation: Hashable {
        let generation: Int
        let userID: String
        let token: String
    }

    private static let pendingMutationTimeout: Duration = .seconds(10)
    private static let pendingMutationPollInterval: Duration = .milliseconds(50)

    private var repository: NotificationPushTokenRepository
    private(set) var currentUserID: String?
    private var currentToken: String?
    private var lastSavedTokenKey: String?
    private var inFlightTokenMutations: Set<InFlightTokenMutation> = []
    private var tokensPendingDeletionByUserID: [String: Set<String>] = [:]
    private var notificationsEnabled = false
    private var isPreparingForSignOut = false
    private var configurationGeneration = 0

    init(repository: NotificationPushTokenRepository) {
        self.repository = repository
    }

    func configure(repository: NotificationPushTokenRepository) {
        self.repository = repository
    }

    func configureUser(_ userID: String?, notificationsEnabled: Bool) {
        let identityChanged = currentUserID != userID
        let resolvedNotificationsEnabled = userID != nil && notificationsEnabled
        let preferenceChanged = self.notificationsEnabled != resolvedNotificationsEnabled
        if identityChanged || preferenceChanged {
            configurationGeneration &+= 1
        }
        if identityChanged {
            lastSavedTokenKey = nil
            isPreparingForSignOut = false
        }

        currentUserID = userID
        self.notificationsEnabled = resolvedNotificationsEnabled
    }

    func setNotificationsEnabled(_ isEnabled: Bool) {
        let resolvedNotificationsEnabled = currentUserID != nil && isEnabled
        if notificationsEnabled != resolvedNotificationsEnabled {
            configurationGeneration &+= 1
            notificationsEnabled = resolvedNotificationsEnabled
        }
    }

    func receiveToken(_ rawToken: String?) async {
        guard let token = normalizedToken(rawToken) else { return }

        let previousToken = currentToken
        let previousSavedTokenKey = lastSavedTokenKey
        currentToken = token

        guard notificationsEnabled,
              !isPreparingForSignOut,
              let userID = currentUserID else { return }

        let generation = configurationGeneration
        let newTokenKey = tokenKey(userID: userID, token: token)
        if lastSavedTokenKey == newTokenKey {
            try? await deletePendingTokens(userID: userID)
            return
        }
        let mutation = InFlightTokenMutation(
            generation: generation,
            userID: userID,
            token: token
        )
        guard !inFlightTokenMutations.contains(mutation) else { return }

        inFlightTokenMutations.insert(mutation)
        defer { inFlightTokenMutations.remove(mutation) }

        let repository = repository
        do {
            try await repository.saveCurrentDeviceToken(userID: userID, token: token)
            guard isCurrentOwnership(generation: generation, userID: userID) else {
                await removeStaleSavedToken(
                    userID: userID,
                    token: token,
                    repository: repository
                )
                return
            }
            guard notificationsEnabled,
                  !isPreparingForSignOut else { return }
            lastSavedTokenKey = newTokenKey
            tokensPendingDeletionByUserID[userID]?.remove(token)

            if let previousToken,
               previousToken != token,
               previousSavedTokenKey == tokenKey(userID: userID, token: previousToken) {
                tokensPendingDeletionByUserID[userID, default: []].insert(previousToken)
            }
            try await deletePendingTokens(userID: userID)
        } catch {
            // A later token callback, lifecycle event, or sign-out retries the
            // unfinished upload or stale-token cleanup.
        }
    }

    func saveCachedTokenIfNeeded() async {
        await receiveToken(currentToken)
    }

    func removeCurrentToken() async {
        setNotificationsEnabled(false)
        let generation = configurationGeneration
        guard let userID = currentUserID,
              let token = currentToken else { return }

        do {
            try await waitForPendingMutations(userID: userID)
            try await deletePendingTokens(userID: userID)
            try await repository.deleteCurrentDeviceToken(userID: userID, token: token)
            clearSavedTokenKey(userID: userID, token: token)
            guard configurationGeneration != generation,
                  currentUserID == userID,
                  notificationsEnabled,
                  !isPreparingForSignOut,
                  currentToken == token else { return }
            await saveCachedTokenIfNeeded()
        } catch {
            // Preference changes remain usable offline; the next authenticated
            // lifecycle event retries cleanup.
        }
    }

    func prepareForSignOut() async throws {
        if !isPreparingForSignOut {
            configurationGeneration &+= 1
        }
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
            configurationGeneration &+= 1
            throw error
        }
    }

    func completeSignOut() {
        configurationGeneration &+= 1
        currentUserID = nil
        lastSavedTokenKey = nil
        notificationsEnabled = false
        isPreparingForSignOut = false
    }

    func resumeAfterFailedSignOut() async {
        if isPreparingForSignOut {
            configurationGeneration &+= 1
            isPreparingForSignOut = false
        }
        await saveCachedTokenIfNeeded()
    }

    private func waitForPendingMutations(userID: String) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.pendingMutationTimeout)

        while inFlightTokenMutations.contains(where: { $0.userID == userID }) {
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
        if currentUserID == userID,
           notificationsEnabled,
           let currentToken {
            tokensPendingDeletionByUserID[userID]?.remove(currentToken)
        }

        for token in (tokensPendingDeletionByUserID[userID] ?? []).sorted() {
            try await repository.deleteCurrentDeviceToken(userID: userID, token: token)
            tokensPendingDeletionByUserID[userID]?.remove(token)
        }

        if tokensPendingDeletionByUserID[userID]?.isEmpty == true {
            tokensPendingDeletionByUserID[userID] = nil
        }
    }

    private func isCurrentOwnership(generation: Int, userID: String) -> Bool {
        configurationGeneration == generation && currentUserID == userID
    }

    private func removeStaleSavedToken(
        userID: String,
        token: String,
        repository: NotificationPushTokenRepository
    ) async {
        do {
            try await repository.deleteCurrentDeviceToken(userID: userID, token: token)
            clearSavedTokenKey(userID: userID, token: token)

            guard currentUserID == userID,
                  notificationsEnabled,
                  !isPreparingForSignOut,
                  currentToken == token else { return }
            await saveCachedTokenIfNeeded()
        } catch {
            tokensPendingDeletionByUserID[userID, default: []].insert(token)
            // Firestore rules can reject old-user cleanup after an account switch.
            // Keep that ownership queued in memory so the next authorized lifecycle
            // for that user can retry without publishing stale local completion state.
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
