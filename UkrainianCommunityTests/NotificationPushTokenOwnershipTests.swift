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
}
