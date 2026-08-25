import FirebaseFunctions
import Foundation
import Testing
@testable import UkrainianCommunity

private actor RecordingNotificationPushTokenRepository: NotificationPushTokenRepository {
    enum Mutation: Equatable, Sendable {
        case save(userID: String, registration: NotificationPushRegistration)
        case delete(userID: String, registration: NotificationPushRegistration)
    }

    enum RepositoryError: Error {
        case deleteRejected
    }

    private var mutations: [Mutation] = []
    private let rejectsDeletes: Bool

    init(rejectsDeletes: Bool = false) {
        self.rejectsDeletes = rejectsDeletes
    }

    func saveCurrentDeviceRegistration(
        userID: String,
        registration: NotificationPushRegistration
    ) async throws {
        mutations.append(.save(userID: userID, registration: registration))
    }

    func deleteCurrentDeviceRegistration(
        userID: String,
        registration: NotificationPushRegistration
    ) async throws {
        if rejectsDeletes {
            throw RepositoryError.deleteRejected
        }
        mutations.append(.delete(userID: userID, registration: registration))
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

    func saveCurrentDeviceRegistration(
        userID: String,
        registration: NotificationPushRegistration
    ) async throws {
        mutations.append(.save(userID: userID, registration: registration))
        guard !hasStartedFirstSave else { return }

        hasStartedFirstSave = true
        firstSaveStartedContinuation?.resume()
        firstSaveStartedContinuation = nil
        await withCheckedContinuation { continuation in
            firstSaveReleaseContinuation = continuation
        }
    }

    func deleteCurrentDeviceRegistration(
        userID: String,
        registration: NotificationPushRegistration
    ) async throws {
        mutations.append(.delete(userID: userID, registration: registration))
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

    func saveCurrentDeviceRegistration(
        userID: String,
        registration: NotificationPushRegistration
    ) async throws {
        mutations.append(.save(userID: userID, registration: registration))
    }

    func deleteCurrentDeviceRegistration(
        userID: String,
        registration: NotificationPushRegistration
    ) async throws {
        mutations.append(.delete(userID: userID, registration: registration))
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
    @Test func onlyUnauthenticatedCallableErrorsUseTheFirestoreFallback() {
        let unauthenticated = NSError(
            domain: FunctionsErrorDomain,
            code: FunctionsErrorCode.unauthenticated.rawValue
        )
        let permissionDenied = NSError(
            domain: FunctionsErrorDomain,
            code: FunctionsErrorCode.permissionDenied.rawValue
        )

        #expect(FirestoreNotificationPushTokenRepository.isUnauthenticatedFunctionsError(unauthenticated))
        #expect(!FirestoreNotificationPushTokenRepository.isUnauthenticatedFunctionsError(permissionDenied))
        #expect(!FirestoreNotificationPushTokenRepository.isUnauthenticatedFunctionsError(NSError(domain: NSURLErrorDomain, code: -1009)))
    }

    private func fid(_ identifier: String) -> NotificationPushRegistration {
        NotificationPushRegistration(identifier: identifier, kind: .firebaseInstallationID)
    }

    private func legacyToken(_ identifier: String) -> NotificationPushRegistration {
        NotificationPushRegistration(identifier: identifier, kind: .legacyFCMToken)
    }

    @Test func registrationKindsUseIndependentStorageIdentities() {
        let identifier = "shared-id"
        let legacyDocumentID = FirestoreNotificationPushTokenRepository.documentID(
            for: legacyToken(identifier)
        )
        let fidDocumentID = FirestoreNotificationPushTokenRepository.documentID(
            for: fid(identifier)
        )

        #expect(legacyDocumentID != fidDocumentID)
    }

    @Test func signOutDeletesRegistrationWhileOriginalUserIsStillConfigured() async throws {
        let repository = RecordingNotificationPushTokenRepository()
        let coordinator = NotificationPushTokenOwnershipCoordinator(repository: repository)

        coordinator.configureUser("user-a", notificationsEnabled: true)
        await coordinator.receiveRegistration("fid-a", kind: .firebaseInstallationID)
        try await coordinator.prepareForSignOut()

        let mutations = await repository.recordedMutations()
        #expect(mutations == [
            .save(userID: "user-a", registration: fid("fid-a")),
            .delete(userID: "user-a", registration: fid("fid-a"))
        ])
        #expect(coordinator.currentUserID == "user-a")

        coordinator.completeSignOut()
        #expect(coordinator.currentUserID == nil)
    }

    @Test func immediateSignOutResolvesFIDBeforeMessagingCallback() async throws {
        let repository = RecordingNotificationPushTokenRepository()
        let coordinator = NotificationPushTokenOwnershipCoordinator(repository: repository)

        coordinator.configureUser("user-a", notificationsEnabled: true)
        try await coordinator.prepareForSignOut {
            self.fid("a123456789012345678901")
        }

        let mutations = await repository.recordedMutations()
        #expect(mutations == [
            .save(
                userID: "user-a",
                registration: fid("a123456789012345678901")
            ),
            .delete(
                userID: "user-a",
                registration: fid("a123456789012345678901")
            )
        ])
    }

    @Test func refreshedRegistrationReplacesPreviousOwnedRegistration() async {
        let repository = RecordingNotificationPushTokenRepository()
        let coordinator = NotificationPushTokenOwnershipCoordinator(repository: repository)

        coordinator.configureUser("user-a", notificationsEnabled: true)
        await coordinator.receiveRegistration("fid-old", kind: .firebaseInstallationID)
        await coordinator.receiveRegistration("fid-new", kind: .firebaseInstallationID)

        let mutations = await repository.recordedMutations()
        #expect(mutations == [
            .save(userID: "user-a", registration: fid("fid-old")),
            .save(userID: "user-a", registration: fid("fid-new")),
            .delete(userID: "user-a", registration: fid("fid-old"))
        ])
    }

    @Test func disabledNotificationsRemoveRegistrationAndRejectLaterUploads() async {
        let repository = RecordingNotificationPushTokenRepository()
        let coordinator = NotificationPushTokenOwnershipCoordinator(repository: repository)

        coordinator.configureUser("user-a", notificationsEnabled: true)
        await coordinator.receiveRegistration("fid-a", kind: .firebaseInstallationID)
        coordinator.configureUser("user-a", notificationsEnabled: false)
        await coordinator.removeCurrentRegistration()
        await coordinator.receiveRegistration("fid-b", kind: .firebaseInstallationID)

        let mutations = await repository.recordedMutations()
        #expect(mutations == [
            .save(userID: "user-a", registration: fid("fid-a")),
            .delete(userID: "user-a", registration: fid("fid-a"))
        ])
    }

    @Test func failedCleanupKeepsOriginalOwnershipForRetry() async {
        let repository = RecordingNotificationPushTokenRepository(rejectsDeletes: true)
        let coordinator = NotificationPushTokenOwnershipCoordinator(repository: repository)

        coordinator.configureUser("user-a", notificationsEnabled: true)
        await coordinator.receiveRegistration("fid-a", kind: .firebaseInstallationID)

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
            await coordinator.receiveRegistration("shared-device-fid", kind: .firebaseInstallationID)
        }
        await repository.waitUntilFirstSaveStarts()

        coordinator.configureUser("user-b", notificationsEnabled: true)
        await coordinator.receiveRegistration("shared-device-fid", kind: .firebaseInstallationID)
        await repository.releaseFirstSave()
        await oldUserSave.value

        await coordinator.receiveRegistration("shared-device-fid", kind: .firebaseInstallationID)

        let mutations = await repository.recordedMutations()
        #expect(mutations == [
            .save(userID: "user-a", registration: fid("shared-device-fid")),
            .save(userID: "user-b", registration: fid("shared-device-fid")),
            .delete(userID: "user-a", registration: fid("shared-device-fid"))
        ])
        #expect(coordinator.currentUserID == "user-b")
    }

    @Test func staleDisableDeletionResavesRegistrationAfterSameUserReenables() async {
        let repository = GatedDeleteNotificationPushTokenRepository()
        let coordinator = NotificationPushTokenOwnershipCoordinator(repository: repository)

        coordinator.configureUser("user-a", notificationsEnabled: true)
        await coordinator.receiveRegistration("fid-a", kind: .firebaseInstallationID)

        coordinator.configureUser("user-a", notificationsEnabled: false)
        let disable = Task { @MainActor in
            await coordinator.removeCurrentRegistration()
        }
        await repository.waitUntilFirstDeleteStarts()

        coordinator.configureUser("user-a", notificationsEnabled: true)
        await coordinator.saveCachedRegistrationIfNeeded()
        await repository.releaseFirstDelete()
        await disable.value

        let mutations = await repository.recordedMutations()
        #expect(mutations == [
            .save(userID: "user-a", registration: fid("fid-a")),
            .delete(userID: "user-a", registration: fid("fid-a")),
            .save(userID: "user-a", registration: fid("fid-a"))
        ])
        #expect(coordinator.currentUserID == "user-a")
    }

    @Test func registrationKindParticipatesInOwnershipAndReplacement() async {
        let repository = RecordingNotificationPushTokenRepository()
        let coordinator = NotificationPushTokenOwnershipCoordinator(repository: repository)

        coordinator.configureUser("user-a", notificationsEnabled: true)
        await coordinator.receiveRegistration("shared-id", kind: .legacyFCMToken)
        await coordinator.receiveRegistration("shared-id", kind: .firebaseInstallationID)

        let mutations = await repository.recordedMutations()
        #expect(mutations == [
            .save(userID: "user-a", registration: legacyToken("shared-id")),
            .save(userID: "user-a", registration: fid("shared-id")),
            .delete(userID: "user-a", registration: legacyToken("shared-id"))
        ])
    }
}
