import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct ProfileEditingTests {
    @Test func failedSecurityReadIsNotAnEmptyFactorListAndRetryRecovers() async {
        var fails = true
        let model = AccountSecurityViewModel(multiFactorService: .shared, loadFactors: {
            if fails { throw AppError.network }
            return []
        })
        await model.load()
        #expect(!model.hasLoadedFactors)
        #expect(model.errorMessage != nil)
        fails = false
        await model.load()
        #expect(model.hasLoadedFactors)
        #expect(model.factors.isEmpty)
        #expect(model.errorMessage == nil)
    }
    private func model(_ repository: ProfileEditingRepository) -> ProfileViewModel {
        ProfileViewModel(repository: repository, feedbackRepository: MockFeedbackRepository(),
            notificationPreferencesRepository: MockNotificationPreferencesRepository(),
            notificationPermissionService: MockNotificationPermissionService(),
            localEventReminderService: MockLocalEventReminderService())
    }

    private func draft(name: String = "Updated Owner", fullName: String = "Owner Name",
                       city: String = "Graz", telegram: String = "owner_contact") -> EditableUserProfileDraft {
        .init(fullName: fullName, displayName: name, telegramUsername: telegram,
              city: city, bio: "Updated biography", selectedFederalState: .steiermark)
    }

    @Test func validatesRequiredFieldsAndServerLimitsBeforeWriting() async {
        let repository = ProfileEditingRepository()
        let viewModel = model(repository)
        for invalid in [draft(name: " "), draft(fullName: " "),
                        draft(name: String(repeating: "a", count: 161)),
                        draft(city: String(repeating: "a", count: 161)),
                        draft(telegram: String(repeating: "a", count: 81))] {
            #expect(await viewModel.saveProfile(invalid) == nil)
            #expect(viewModel.profileMessage != nil)
        }
        #expect(repository.writes == 0)
    }

    @Test func savesAllFieldsAndReloadsWithoutLosingOwnerRights() async throws {
        let repository = ProfileEditingRepository()
        let viewModel = model(repository)
        let updated = try #require(await viewModel.saveProfile(draft()))
        #expect(updated.displayName == "Updated Owner")
        #expect(updated.fullName == "Owner Name")
        #expect(updated.city == "Graz")
        #expect(updated.bio == "Updated biography")
        #expect(updated.telegramUsername == "owner_contact")
        #expect(updated.selectedFederalState == .steiermark)
        #expect(updated.globalRole == .owner)
        let reopened = model(repository)
        await reopened.loadIfNeeded()
        #expect(reopened.user.displayName == updated.displayName)
        #expect(reopened.user.id == updated.id)
    }

    @Test func textSaveNetworkFailureDoesNotClaimAvatarFailureAndCanRetry() async {
        let repository = ProfileEditingRepository()
        repository.failure = .network
        let viewModel = model(repository)
        #expect(await viewModel.saveProfile(draft()) == nil)
        #expect(viewModel.profileMessage == AppStrings.Profile.profileSaveFailed)
        #expect(!viewModel.isSavingProfile)
        repository.failure = nil
        #expect(await viewModel.saveProfile(draft()) != nil)
    }

    @Test func accountChangeDiscardsLateSaveSuccessAndFailure() async {
        for shouldFail in [false, true] {
            let repository = ProfileEditingRepository()
            repository.hold = true
            repository.failure = shouldFail ? .network : nil
            let viewModel = model(repository)
            let save = Task { await viewModel.saveProfile(draft()) }
            while repository.continuation == nil { await Task.yield() }
            viewModel.resetForAuthChange()
            repository.continuation?.resume()
            #expect(await save.value == nil)
            #expect(viewModel.user.id == AppUser.placeholder.id)
            #expect(viewModel.profileMessage == nil)
            #expect(viewModel.error == nil)
        }
    }

    @Test func duplicateSaveDoesNotIssueAnotherWrite() async {
        let repository = ProfileEditingRepository()
        repository.hold = true
        let viewModel = model(repository)
        let save = Task { await viewModel.saveProfile(draft()) }
        while repository.continuation == nil { await Task.yield() }
        #expect(await viewModel.saveProfile(draft(name: "Second")) == nil)
        #expect(repository.writes == 1)
        repository.continuation?.resume()
        #expect(await save.value != nil)
    }
}

@MainActor
private final class ProfileEditingRepository: UserRepository {
    var user = MockContentBuilder.ownerUser()
    var writes = 0
    var failure: AppError?
    var hold = false
    var continuation: CheckedContinuation<Void, Never>?
    func fetchCurrentUser() async throws -> AppUser { user }
    func fetchSettings() async throws -> UserSettings { .stored }
    func deleteAccount(currentUser: AppUser) async throws {}
    func updateProfile(_ draft: EditableUserProfileDraft) async throws -> AppUser {
        writes += 1
        if hold { await withCheckedContinuation { continuation = $0 } }
        if let failure { throw failure }
        user = AppUser(id: user.id, fullName: draft.fullName, displayName: draft.displayName,
            city: draft.city, email: user.email, avatarURL: draft.avatarURL, bio: draft.bio,
            telegramUsername: draft.telegramUsername, role: user.role, globalRole: user.globalRole,
            blockState: user.blockState, selectedFederalState: draft.selectedFederalState,
            createdAt: user.createdAt, updatedAt: .now)
        return user
    }
}
