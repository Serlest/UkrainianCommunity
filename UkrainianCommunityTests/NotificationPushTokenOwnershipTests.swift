import Testing
@testable import UkrainianCommunity

private actor RecordingNotificationPushTokenRepository: NotificationPushTokenRepository {
    enum Mutation: Equatable, Sendable {
        case save(userID: String, token: String)
        case delete(userID: String, token: String)
    }

    enum RepositoryError: Error {
        case deleteRejected
    }

    private var mutations: [Mutation] = []
    private let rejectsDeletes: Bool

    init(rejectsDeletes: Bool = false) {
        self.rejectsDeletes = rejectsDeletes
    }

    func saveCurrentDeviceToken(userID: String, token: String) async throws {
        mutations.append(.save(userID: userID, token: token))
    }

    func deleteCurrentDeviceToken(userID: String, token: String) async throws {
        if rejectsDeletes {
            throw RepositoryError.deleteRejected
        }
        mutations.append(.delete(userID: userID, token: token))
    }

    func recordedMutations() -> [Mutation] {
        mutations
    }
}

private actor GatedNotificationPushTokenRepository: NotificationPushTokenRepository {
    typealias Mutation = RecordingNotificationPushTokenRepository.Mutation

    private var mutations: [Mutation] = []
    private var hasStartedFirstSave = false
    private var firstSaveStartedContinuation: CheckedContinuation<Void, Never>?
    private var firstSaveReleaseContinuation: CheckedContinuation<Void, Never>?

    func saveCurrentDeviceToken(userID: String, token: String) async throws {
        mutations.append(.save(userID: userID, token: token))
        guard !hasStartedFirstSave else { return }

        hasStartedFirstSave = true
        firstSaveStartedContinuation?.resume()
        firstSaveStartedContinuation = nil
        await withCheckedContinuation { continuation in
            firstSaveReleaseContinuation = continuation
        }
    }

    func deleteCurrentDeviceToken(userID: String, token: String) async throws {
        mutations.append(.delete(userID: userID, token: token))
    }

    func waitUntilFirstSaveStarts() async {
        guard !hasStartedFirstSave else { return }
        await withCheckedContinuation { continuation in
            firstSaveStartedContinuation = continuation
        }
    }

    func releaseFirstSave() {
        firstSaveReleaseContinuation?.resume()
        firstSaveReleaseContinuation = nil
    }

    func recordedMutations() -> [Mutation] {
        mutations
    }
}

private actor GatedDeleteNotificationPushTokenRepository: NotificationPushTokenRepository {
    typealias Mutation = RecordingNotificationPushTokenRepository.Mutation

    private var mutations: [Mutation] = []
    private var hasStartedFirstDelete = false
    private var firstDeleteStartedContinuation: CheckedContinuation<Void, Never>?
    private var firstDeleteReleaseContinuation: CheckedContinuation<Void, Never>?

    func saveCurrentDeviceToken(userID: String, token: String) async throws {
        mutations.append(.save(userID: userID, token: token))
    }

    func deleteCurrentDeviceToken(userID: String, token: String) async throws {
        mutations.append(.delete(userID: userID, token: token))
        guard !hasStartedFirstDelete else { return }

        hasStartedFirstDelete = true
        firstDeleteStartedContinuation?.resume()
        firstDeleteStartedContinuation = nil
        await withCheckedContinuation { continuation in
            firstDeleteReleaseContinuation = continuation
        }
    }

    func waitUntilFirstDeleteStarts() async {
        guard !hasStartedFirstDelete else { return }
        await withCheckedContinuation { continuation in
            firstDeleteStartedContinuation = continuation
        }
    }

    func releaseFirstDelete() {
        firstDeleteReleaseContinuation?.resume()
        firstDeleteReleaseContinuation = nil
    }

    func recordedMutations() -> [Mutation] {
        mutations
    }
}

@MainActor
struct NotificationPushTokenOwnershipTests {
    @Test func signOutDeletesTokenWhileOriginalUserIsStillConfigured() async throws {
        let repository = RecordingNotificationPushTokenRepository()
        let coordinator = NotificationPushTokenOwnershipCoordinator(repository: repository)

        coordinator.configureUser("user-a", notificationsEnabled: true)
        await coordinator.receiveToken("token-a")
        try await coordinator.prepareForSignOut()

        let mutations = await repository.recordedMutations()
        #expect(mutations == [
            .save(userID: "user-a", token: "token-a"),
            .delete(userID: "user-a", token: "token-a")
        ])
        #expect(coordinator.currentUserID == "user-a")

        coordinator.completeSignOut()
        #expect(coordinator.currentUserID == nil)
    }

    @Test func refreshedTokenReplacesPreviousOwnedToken() async {
        let repository = RecordingNotificationPushTokenRepository()
        let coordinator = NotificationPushTokenOwnershipCoordinator(repository: repository)

        coordinator.configureUser("user-a", notificationsEnabled: true)
        await coordinator.receiveToken("token-old")
        await coordinator.receiveToken("token-new")

        let mutations = await repository.recordedMutations()
        #expect(mutations == [
            .save(userID: "user-a", token: "token-old"),
            .save(userID: "user-a", token: "token-new"),
            .delete(userID: "user-a", token: "token-old")
        ])
    }

    @Test func disabledNotificationsRemoveTokenAndRejectLaterUploads() async {
        let repository = RecordingNotificationPushTokenRepository()
        let coordinator = NotificationPushTokenOwnershipCoordinator(repository: repository)

        coordinator.configureUser("user-a", notificationsEnabled: true)
        await coordinator.receiveToken("token-a")
        coordinator.configureUser("user-a", notificationsEnabled: false)
        await coordinator.removeCurrentToken()
        await coordinator.receiveToken("token-b")

        let mutations = await repository.recordedMutations()
        #expect(mutations == [
            .save(userID: "user-a", token: "token-a"),
            .delete(userID: "user-a", token: "token-a")
        ])
    }

    @Test func failedCleanupKeepsOriginalOwnershipForRetry() async {
        let repository = RecordingNotificationPushTokenRepository(rejectsDeletes: true)
        let coordinator = NotificationPushTokenOwnershipCoordinator(repository: repository)

        coordinator.configureUser("user-a", notificationsEnabled: true)
        await coordinator.receiveToken("token-a")

        var cleanupFailed = false
        do {
            try await coordinator.prepareForSignOut()
        } catch {
            cleanupFailed = true
        }

        #expect(cleanupFailed)
        #expect(coordinator.currentUserID == "user-a")
    }

    @Test func staleSaveCompletionCannotReplaceNewUserOwnershipState() async {
        let repository = GatedNotificationPushTokenRepository()
        let coordinator = NotificationPushTokenOwnershipCoordinator(repository: repository)

        coordinator.configureUser("user-a", notificationsEnabled: true)
        let oldUserSave = Task { @MainActor in
            await coordinator.receiveToken("shared-device-token")
        }
        await repository.waitUntilFirstSaveStarts()

        coordinator.configureUser("user-b", notificationsEnabled: true)
        await coordinator.receiveToken("shared-device-token")
        await repository.releaseFirstSave()
        await oldUserSave.value

        await coordinator.receiveToken("shared-device-token")

        let mutations = await repository.recordedMutations()
        #expect(mutations == [
            .save(userID: "user-a", token: "shared-device-token"),
            .save(userID: "user-b", token: "shared-device-token"),
            .delete(userID: "user-a", token: "shared-device-token")
        ])
        #expect(coordinator.currentUserID == "user-b")
    }

    @Test func staleDisableDeletionResavesTokenAfterSameUserReenables() async {
        let repository = GatedDeleteNotificationPushTokenRepository()
        let coordinator = NotificationPushTokenOwnershipCoordinator(repository: repository)

        coordinator.configureUser("user-a", notificationsEnabled: true)
        await coordinator.receiveToken("token-a")

        coordinator.configureUser("user-a", notificationsEnabled: false)
        let disable = Task { @MainActor in
            await coordinator.removeCurrentToken()
        }
        await repository.waitUntilFirstDeleteStarts()

        coordinator.configureUser("user-a", notificationsEnabled: true)
        await coordinator.saveCachedTokenIfNeeded()
        await repository.releaseFirstDelete()
        await disable.value

        let mutations = await repository.recordedMutations()
        #expect(mutations == [
            .save(userID: "user-a", token: "token-a"),
            .delete(userID: "user-a", token: "token-a"),
            .save(userID: "user-a", token: "token-a")
        ])
        #expect(coordinator.currentUserID == "user-a")
    }
}
