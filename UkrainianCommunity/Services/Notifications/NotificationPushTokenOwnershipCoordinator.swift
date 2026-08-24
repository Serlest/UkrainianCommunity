import Foundation

enum NotificationPushTokenOwnershipError: Error {
    case pendingMutationTimedOut
}

@MainActor
final class NotificationPushTokenOwnershipCoordinator {
    private struct InFlightRegistrationMutation: Hashable {
        let generation: Int
        let userID: String
        let registration: NotificationPushRegistration
    }

    private static let pendingMutationTimeout: Duration = .seconds(10)
    private static let pendingMutationPollInterval: Duration = .milliseconds(50)

    private var repository: NotificationPushTokenRepository
    private(set) var currentUserID: String?
    private var currentRegistration: NotificationPushRegistration?
    private var lastSavedRegistrationKey: String?
    private var inFlightRegistrationMutations: Set<InFlightRegistrationMutation> = []
    private var registrationsPendingDeletionByUserID: [String: Set<NotificationPushRegistration>] = [:]
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
            lastSavedRegistrationKey = nil
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

    func receiveRegistration(
        _ rawIdentifier: String?,
        kind: NotificationPushRegistrationKind
    ) async {
        guard let identifier = normalizedIdentifier(rawIdentifier) else { return }
        let registration = NotificationPushRegistration(identifier: identifier, kind: kind)

        let previousRegistration = currentRegistration
        let previousSavedRegistrationKey = lastSavedRegistrationKey
        currentRegistration = registration

        guard notificationsEnabled,
              !isPreparingForSignOut,
              let userID = currentUserID else { return }

        let generation = configurationGeneration
        let newRegistrationKey = registrationKey(userID: userID, registration: registration)
        if lastSavedRegistrationKey == newRegistrationKey {
            try? await deletePendingRegistrations(userID: userID)
            return
        }
        let mutation = InFlightRegistrationMutation(
            generation: generation,
            userID: userID,
            registration: registration
        )
        guard !inFlightRegistrationMutations.contains(mutation) else { return }

        inFlightRegistrationMutations.insert(mutation)
        defer { inFlightRegistrationMutations.remove(mutation) }

        let repository = repository
        do {
            try await repository.saveCurrentDeviceRegistration(
                userID: userID,
                registration: registration
            )
            guard isCurrentOwnership(generation: generation, userID: userID) else {
                await removeStaleSavedRegistration(
                    userID: userID,
                    registration: registration,
                    repository: repository
                )
                return
            }
            guard notificationsEnabled,
                  !isPreparingForSignOut else { return }
            lastSavedRegistrationKey = newRegistrationKey
            registrationsPendingDeletionByUserID[userID]?.remove(registration)

            if let previousRegistration,
               previousRegistration != registration,
               previousSavedRegistrationKey == registrationKey(
                   userID: userID,
                   registration: previousRegistration
               ) {
                registrationsPendingDeletionByUserID[userID, default: []].insert(previousRegistration)
            }
            try await deletePendingRegistrations(userID: userID)
        } catch {
            // A later registration callback, lifecycle event, or sign-out retries
            // the unfinished upload or stale-registration cleanup.
        }
    }

    func saveCachedRegistrationIfNeeded() async {
        guard let currentRegistration else { return }
        await receiveRegistration(
            currentRegistration.identifier,
            kind: currentRegistration.kind
        )
    }

    func removeCurrentRegistration() async {
        setNotificationsEnabled(false)
        let generation = configurationGeneration
        guard let userID = currentUserID,
              let registration = currentRegistration else { return }

        do {
            try await waitForPendingMutations(userID: userID)
            try await deletePendingRegistrations(userID: userID)
            try await repository.deleteCurrentDeviceRegistration(
                userID: userID,
                registration: registration
            )
            clearSavedRegistrationKey(userID: userID, registration: registration)
            guard configurationGeneration != generation,
                  currentUserID == userID,
                  notificationsEnabled,
                  !isPreparingForSignOut,
                  currentRegistration == registration else { return }
            await saveCachedRegistrationIfNeeded()
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
                  let registration = currentRegistration else { return }

            try await waitForPendingMutations(userID: userID)
            try await deletePendingRegistrations(userID: userID)
            try await repository.deleteCurrentDeviceRegistration(
                userID: userID,
                registration: registration
            )
            clearSavedRegistrationKey(userID: userID, registration: registration)
        } catch {
            isPreparingForSignOut = false
            configurationGeneration &+= 1
            throw error
        }
    }

    func prepareForSignOut(
        resolvingRegistration: () async throws -> NotificationPushRegistration?
    ) async throws {
        if currentRegistration?.kind != .firebaseInstallationID,
           let resolvedRegistration = try await resolvingRegistration() {
            await receiveRegistration(
                resolvedRegistration.identifier,
                kind: resolvedRegistration.kind
            )
        }
        try await prepareForSignOut()
    }

    func completeSignOut() {
        configurationGeneration &+= 1
        currentUserID = nil
        lastSavedRegistrationKey = nil
        notificationsEnabled = false
        isPreparingForSignOut = false
    }

    func resumeAfterFailedSignOut() async {
        if isPreparingForSignOut {
            configurationGeneration &+= 1
            isPreparingForSignOut = false
        }
        await saveCachedRegistrationIfNeeded()
    }

    private func waitForPendingMutations(userID: String) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.pendingMutationTimeout)

        while inFlightRegistrationMutations.contains(where: { $0.userID == userID }) {
            guard clock.now < deadline else {
                throw NotificationPushTokenOwnershipError.pendingMutationTimedOut
            }
            try await Task.sleep(for: Self.pendingMutationPollInterval)
        }
    }

    private func clearSavedRegistrationKey(
        userID: String,
        registration: NotificationPushRegistration
    ) {
        let key = registrationKey(userID: userID, registration: registration)
        if lastSavedRegistrationKey == key {
            lastSavedRegistrationKey = nil
        }
    }

    private func deletePendingRegistrations(userID: String) async throws {
        if currentUserID == userID,
           notificationsEnabled,
           let currentRegistration {
            registrationsPendingDeletionByUserID[userID]?.remove(currentRegistration)
        }

        let pendingRegistrations = (registrationsPendingDeletionByUserID[userID] ?? []).sorted {
            registrationSortKey($0) < registrationSortKey($1)
        }
        for registration in pendingRegistrations {
            try await repository.deleteCurrentDeviceRegistration(
                userID: userID,
                registration: registration
            )
            registrationsPendingDeletionByUserID[userID]?.remove(registration)
        }

        if registrationsPendingDeletionByUserID[userID]?.isEmpty == true {
            registrationsPendingDeletionByUserID[userID] = nil
        }
    }

    private func isCurrentOwnership(generation: Int, userID: String) -> Bool {
        configurationGeneration == generation && currentUserID == userID
    }

    private func removeStaleSavedRegistration(
        userID: String,
        registration: NotificationPushRegistration,
        repository: NotificationPushTokenRepository
    ) async {
        do {
            try await repository.deleteCurrentDeviceRegistration(
                userID: userID,
                registration: registration
            )
            clearSavedRegistrationKey(userID: userID, registration: registration)

            guard currentUserID == userID,
                  notificationsEnabled,
                  !isPreparingForSignOut,
                  currentRegistration == registration else { return }
            await saveCachedRegistrationIfNeeded()
        } catch {
            registrationsPendingDeletionByUserID[userID, default: []].insert(registration)
            // Firestore rules can reject old-user cleanup after an account switch.
            // Keep that ownership queued in memory so the next authorized lifecycle
            // for that user can retry without publishing stale local completion state.
        }
    }

    private func registrationKey(
        userID: String,
        registration: NotificationPushRegistration
    ) -> String {
        "\(userID):\(registration.kind.rawValue):\(registration.identifier)"
    }

    private func registrationSortKey(_ registration: NotificationPushRegistration) -> String {
        "\(registration.kind.rawValue):\(registration.identifier)"
    }

    private func normalizedIdentifier(_ identifier: String?) -> String? {
        guard let identifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !identifier.isEmpty else { return nil }
        return identifier
    }
}
