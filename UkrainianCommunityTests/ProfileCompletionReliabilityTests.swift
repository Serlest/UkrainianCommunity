import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct ProfileCompletionReliabilityTests {
    private func model(_ repository: CompletionProfileRepository,
                       finalizer: @escaping (String) async -> Bool = { _ in true },
                       uploader: ((Data, String) async throws -> URL)? = nil) -> ProfileViewModel {
        ProfileViewModel(repository: repository, feedbackRepository: MockFeedbackRepository(),
            notificationPreferencesRepository: MockNotificationPreferencesRepository(),
            notificationPermissionService: MockNotificationPermissionService(),
            localEventReminderService: MockLocalEventReminderService(),
            notificationRegistrationUpdater: { _, _ in }, deletionFinalizer: finalizer, avatarUploader: uploader)
    }
    private var draft: EditableUserProfileDraft {
        .init(fullName: "Saved Name", displayName: "Saved Display", telegramUsername: nil,
              city: "Graz", bio: "Saved bio", selectedFederalState: .steiermark)
    }

    @Test func lateDeletionSuccessOrFailureCannotFinalizeOrPolluteAnotherAccount() async {
        for fails in [false, true] {
            let repository = CompletionProfileRepository()
            repository.holdDeletion = true
            repository.failDeletion = fails
            var finalizations = 0
            let model = model(repository, finalizer: { _ in finalizations += 1; return true })
            let deletion = Task { await model.deleteAccount(currentUser: repository.user) }
            while repository.deletionResume == nil { await Task.yield() }
            model.resetForAuthChange()
            repository.deletionResume?.resume()
            #expect(await deletion.value == nil)
            #expect(finalizations == 0)
            #expect(!model.isDeletingAccount)
            #expect(model.error == nil)
        }
    }

    @Test func duplicateDeletionDoesNotStartAnotherRequest() async {
        let repository = CompletionProfileRepository()
        repository.holdDeletion = true
        var finalizedIDs: [String] = []
        let model = model(repository, finalizer: { id in finalizedIDs.append(id); return true })
        let deletion = Task { await model.deleteAccount(currentUser: repository.user) }
        while repository.deletionResume == nil { await Task.yield() }
        #expect(await model.deleteAccount(currentUser: repository.user) != nil)
        #expect(repository.deletions == 1)
        repository.deletionResume?.resume()
        #expect(await deletion.value == nil)
        #expect(finalizedIDs == [repository.user.id])
    }

    @Test func acknowledgedWriteRetriesOnlyReadbackAndRetainsPendingStateAcrossFailure() async throws {
        let repository = CompletionProfileRepository()
        repository.pendingReadback = true
        let model = model(repository)
        #expect(await model.saveProfile(draft) == nil)
        #expect(model.hasPendingProfileSave)
        #expect(model.pendingProfileSaveDraft == draft)
        #expect(model.profileMessage == SettingsPrivacyText.profileSavedPending)
        repository.failRecovery = true
        #expect(await model.saveProfile(draft) == nil)
        #expect(model.hasPendingProfileSave)
        repository.failRecovery = false
        let saved = try #require(await model.saveProfile(draft))
        #expect(saved.displayName == draft.displayName)
        #expect(repository.writes == 1)
        #expect(repository.recoveries == 2)
        #expect(!model.hasPendingProfileSave)
        #expect(model.pendingProfileSaveDraft == nil)
    }

    @Test func lateReadbackCannotReplaceNewAccountState() async {
        let repository = CompletionProfileRepository()
        repository.pendingReadback = true
        let model = model(repository)
        _ = await model.saveProfile(draft)
        repository.holdRecovery = true
        let recovery = Task { await model.saveProfile(draft) }
        while repository.recoveryResume == nil { await Task.yield() }
        model.resetForAuthChange()
        repository.recoveryResume?.resume()
        #expect(await recovery.value == nil)
        #expect(!model.hasPendingProfileSave)
        #expect(model.user.id == AppUser.placeholder.id)
    }

    @Test func retryReusesUploadedAvatarInsteadOfUploadingItTwice() async {
        let repository = CompletionProfileRepository()
        repository.failWrite = true
        var uploads = 0
        let model = model(repository, uploader: { _, _ in
            uploads += 1
            return URL(string: "https://example.invalid/avatar.jpg")!
        })
        #expect(await model.saveProfile(draft, avatarImageData: Data([1, 2])) == nil)
        repository.failWrite = false
        #expect(await model.saveProfile(draft, avatarImageData: Data([1, 2])) != nil)
        #expect(uploads == 1)
        #expect(repository.writes == 2)
    }

    @Test func securityReadDeadlineRejectsLateFactorResult() async {
        var resume: CheckedContinuation<[AuthMultiFactorFactor], Never>?
        let model = AccountSecurityViewModel(multiFactorService: .shared, loadFactors: {
            await withCheckedContinuation { resume = $0 }
        }, readTimeout: .milliseconds(15))
        await model.load()
        #expect(!model.isLoading)
        #expect(!model.hasLoadedFactors)
        #expect(model.errorMessage != nil)
        resume?.resume(returning: [.init(id: "late", displayName: nil, enrollmentDate: .now)])
        for _ in 0..<10 { await Task.yield() }
        #expect(model.factors.isEmpty)
    }

    @Test func securityClaimReadFailureIsVisibleAndExplicitRetryRecovers() async {
        var fails = true
        let model = AccountSecurityViewModel(multiFactorService: .shared, sessionAuthentication: {
            if fails { throw AppError.network }
            return (true, false)
        })
        await model.refreshSessionAuthentication()
        #expect(model.sessionErrorMessage != nil)
        #expect(!model.isSessionTOTPAuthenticated)
        fails = false
        await model.refreshSessionAuthentication()
        #expect(model.sessionErrorMessage == nil)
        #expect(model.isSessionTOTPAuthenticated)
    }

    @Test func concurrentSecurityClaimReadsShareOneSnapshot() async {
        var reads = 0
        var resume: CheckedContinuation<Void, Never>?
        let model = AccountSecurityViewModel(multiFactorService: .shared, sessionAuthentication: {
            reads += 1
            await withCheckedContinuation { resume = $0 }
            return (true, false)
        })
        let first = Task { await model.refreshSessionAuthentication() }
        while resume == nil { await Task.yield() }
        let second = Task { await model.refreshSessionAuthentication() }
        for _ in 0..<10 { await Task.yield() }
        resume?.resume()
        await first.value; await second.value
        #expect(reads == 1)
        #expect(model.isSessionTOTPAuthenticated)
        #expect(!model.isSessionPasskeyAuthenticated)
    }

    @Test func sharedSecurityLeaseBlocksOtherKindsOfMutation() async throws {
        let interaction = AuthInteractionCoordinator()
        let model = AccountSecurityViewModel(multiFactorService: .shared, interaction: interaction)
        let lease = try #require(interaction.begin())
        await model.beginEnrollment()
        await model.sendPasswordChangeLink(email: "no-send@example.invalid")
        #expect(!(await model.activatePrivilegedRequirement()))
        #expect(!model.isStartingEnrollment)
        #expect(model.message == nil)
        #expect(model.errorMessage == nil)
        #expect(interaction.requestID == lease)
        interaction.finish(lease)
    }
}

@MainActor
private final class CompletionProfileRepository: UserRepository {
    var user = MockContentBuilder.ownerUser()
    var writes = 0, recoveries = 0, deletions = 0
    var pendingReadback = false, failRecovery = false, holdRecovery = false, failWrite = false
    var holdDeletion = false, failDeletion = false
    var deletionResume: CheckedContinuation<Void, Never>?
    var recoveryResume: CheckedContinuation<Void, Never>?
    func fetchCurrentUser() async throws -> AppUser { user }
    func fetchSettings() async throws -> UserSettings { .stored }
    func deleteAccount(currentUser: AppUser) async throws {
        deletions += 1
        if holdDeletion { await withCheckedContinuation { deletionResume = $0 } }
        if failDeletion { throw AppError.network }
    }
    func recoverSavedProfile(userID: String) async throws -> AppUser {
        recoveries += 1
        if holdRecovery { await withCheckedContinuation { recoveryResume = $0 } }
        if failRecovery { throw AppError.network }
        return user
    }
    func updateProfile(_ draft: EditableUserProfileDraft) async throws -> AppUser {
        writes += 1
        if failWrite { throw AppError.network }
        user = AppUser(id: user.id, fullName: draft.fullName, displayName: draft.displayName,
            city: draft.city, email: user.email, avatarURL: draft.avatarURL, bio: draft.bio,
            telegramUsername: draft.telegramUsername, role: user.role, globalRole: user.globalRole,
            blockState: user.blockState, selectedFederalState: draft.selectedFederalState,
            createdAt: user.createdAt, updatedAt: .now)
        if pendingReadback { throw ProfileSaveReadbackPending(userID: user.id) }
        return user
    }
}
