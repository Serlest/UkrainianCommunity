import Combine
import FirebaseAuth
import Foundation

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published private(set) var user: AppUser
    @Published var settings: UserSettings
    @Published private(set) var error: AppError?
    @Published private(set) var isSavingProfile = false
    @Published private(set) var isSubmittingFeedback = false
    @Published private(set) var isDeletingAccount = false
    @Published private(set) var isLoading = false
    @Published var notificationPreferences: NotificationPreferences = .default
    @Published private(set) var isLoadingNotificationPreferences = false
    @Published private(set) var isSavingNotificationPreferences = false
    @Published var notificationPreferencesMessage: String?
    @Published var profileMessage: String?
    @Published var feedbackMessage: String?
    private let repository: UserRepository
    private let feedbackRepository: FeedbackRepository
    private let notificationPreferencesRepository: NotificationPreferencesRepository
    private let notificationPermissionService: NotificationPermissionServiceProtocol
    private var loadTask: Task<Void, Never>?
    private var feedbackSuccessDismissTask: Task<Void, Never>?
    private var hasLoaded = false
    private var lastLoadedAt: Date?
    private var loadedNotificationPreferencesUserID: String?

    init(
        repository: UserRepository,
        feedbackRepository: FeedbackRepository,
        notificationPreferencesRepository: NotificationPreferencesRepository,
        notificationPermissionService: NotificationPermissionServiceProtocol,
        localEventReminderService: LocalEventReminderServiceProtocol
    ) {
        self.repository = repository
        self.feedbackRepository = feedbackRepository
        self.notificationPreferencesRepository = notificationPreferencesRepository
        self.notificationPermissionService = notificationPermissionService
        user = .placeholder
        settings = .stored
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await startLoad(force: false)
    }

    func reload() {
        Task {
            await refresh()
        }
    }

    func refresh() async {
        await startLoad(force: true)
    }

    func resetForAuthChange() {
        loadTask?.cancel()
        loadTask = nil
        cancelFeedbackSuccessDismiss()
        user = .placeholder
        error = nil
        isSavingProfile = false
        isSubmittingFeedback = false
        isDeletingAccount = false
        isLoading = false
        notificationPreferences = .default
        isLoadingNotificationPreferences = false
        isSavingNotificationPreferences = false
        notificationPreferencesMessage = nil
        loadedNotificationPreferencesUserID = nil
        profileMessage = nil
        feedbackMessage = nil
        hasLoaded = false
        lastLoadedAt = nil
    }

    deinit {
        loadTask?.cancel()
        feedbackSuccessDismissTask?.cancel()
    }

    func loadNotificationPreferencesIfNeeded(userID: String) async {
        guard loadedNotificationPreferencesUserID != userID else { return }
        await loadNotificationPreferences(userID: userID)
    }

    func refreshNotificationPreferences(userID: String) async {
        await loadNotificationPreferences(userID: userID)
    }

    func setNotificationsEnabled(_ isEnabled: Bool, userID: String) async {
        guard !isSavingNotificationPreferences else { return }

        var updatedPreferences = notificationPreferences
        updatedPreferences.notificationsEnabled = isEnabled
        await saveNotificationPreferences(updatedPreferences, userID: userID)
    }

    private func loadNotificationPreferences(userID: String) async {
        isLoadingNotificationPreferences = true
        defer { isLoadingNotificationPreferences = false }

        do {
            notificationPreferences = try await notificationPreferencesRepository.fetchNotificationPreferences(userID: userID)
            notificationPreferencesMessage = nil
            loadedNotificationPreferencesUserID = userID
        } catch let appError as AppError {
            error = appError
            notificationPreferencesMessage = AppStrings.Profile.notificationPreferencesLoadFailed
        } catch {
            self.error = .unknown
            notificationPreferencesMessage = AppStrings.Profile.notificationPreferencesLoadFailed
        }
    }

    private func saveNotificationPreferences(_ updatedPreferences: NotificationPreferences, userID: String) async {
        let previousPreferences = notificationPreferences
        notificationPreferences = updatedPreferences
        isSavingNotificationPreferences = true
        notificationPreferencesMessage = nil
        defer { isSavingNotificationPreferences = false }

        do {
            if updatedPreferences.notificationsEnabled {
                let granted = try await notificationPermissionService.requestNotificationAuthorization()
                guard granted else {
                    notificationPreferences = previousPreferences
                    notificationPreferencesMessage = AppStrings.Profile.notificationPreferencesSaveFailed
                    return
                }
            }

            try await notificationPreferencesRepository.saveNotificationPreferences(updatedPreferences, userID: userID)
            if !updatedPreferences.notificationsEnabled {
                await RemoteNotificationRegistrationService.shared.removeCurrentRegistration()
            }
            notificationPreferencesMessage = AppStrings.Profile.notificationPreferencesSaved
            loadedNotificationPreferencesUserID = userID
        } catch let appError as AppError {
            notificationPreferences = previousPreferences
            error = appError
            notificationPreferencesMessage = AppStrings.Profile.notificationPreferencesSaveFailed
        } catch {
            notificationPreferences = previousPreferences
            self.error = .unknown
            notificationPreferencesMessage = AppStrings.Profile.notificationPreferencesSaveFailed
        }
    }

    func saveProfile(_ profile: EditableUserProfileDraft, avatarImageData: Data? = nil) async -> AppUser? {
        guard !isSavingProfile else { return nil }

        let trimmedDisplayName = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDisplayName.isEmpty else {
            profileMessage = AppStrings.Profile.displayNameRequired
            return nil
        }

        isSavingProfile = true
        profileMessage = nil
        defer { isSavingProfile = false }

        do {
            let resolvedProfile: EditableUserProfileDraft
            if let avatarImageData {
                let avatarUserID = AuthService.shared.currentUser?.uid ?? user.id
                let avatarURL = try await ImageUploadService.shared.uploadProfileAvatarImage(
                    data: avatarImageData,
                    userID: avatarUserID
                )
                resolvedProfile = EditableUserProfileDraft(
                    fullName: profile.fullName,
                    displayName: profile.displayName,
                    telegramUsername: profile.telegramUsername,
                    city: profile.city,
                    bio: profile.bio,
                    selectedFederalState: profile.selectedFederalState,
                    avatarURL: avatarURL
                )
            } else {
                resolvedProfile = profile
            }

            let updatedUser = try await repository.updateProfile(resolvedProfile)
            user = updatedUser
            error = nil
            profileMessage = AppStrings.Profile.profileSaved
            return updatedUser
        } catch let appError as AppError {
            error = appError
            profileMessage = avatarImageData != nil || appError == .network
                ? AppStrings.Profile.avatarUploadFailed
                : AppStrings.Profile.profileSaveFailed
            return nil
        } catch {
            self.error = .unknown
            profileMessage = avatarImageData != nil
                ? AppStrings.Profile.avatarUploadFailed
                : AppStrings.Profile.profileSaveFailed
            return nil
        }
    }

    func submitFeedback(type: FeedbackType, message: String, user: AppUser) async -> Bool {
        guard !isSubmittingFeedback else { return false }
        cancelFeedbackSuccessDismiss()

        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            feedbackMessage = AppStrings.Feedback.messageRequired
            return false
        }

        isSubmittingFeedback = true
        feedbackMessage = nil
        defer { isSubmittingFeedback = false }

        do {
            let now = Date()
            try await feedbackRepository.submitFeedback(FeedbackItem(
                id: UUID().uuidString,
                type: type,
                subject: nil,
                message: trimmedMessage,
                status: .open,
                createdAt: now,
                updatedAt: now,
                userId: user.id,
                userDisplayName: user.preferredDisplayName,
                ownerReply: nil,
                repliedAt: nil,
                repliedByUserId: nil,
                lastMessageText: trimmedMessage,
                lastMessageAt: now,
                lastMessageByUserId: user.id,
                lastMessageByRole: .user,
                unreadForOwner: true,
                unreadForUser: false
            ))
            error = nil
            feedbackMessage = AppStrings.Feedback.submitted
            scheduleFeedbackSuccessDismiss()
            return true
        } catch let appError as AppError {
            error = appError
            feedbackMessage = AppStrings.Feedback.submitFailed
            return false
        } catch {
            self.error = .unknown
            feedbackMessage = AppStrings.Feedback.submitFailed
            return false
        }
    }

    func clearFeedbackSuccessMessage() {
        guard feedbackMessage == AppStrings.Feedback.submitted else { return }
        cancelFeedbackSuccessDismiss()
        feedbackMessage = nil
    }

    private func scheduleFeedbackSuccessDismiss() {
        feedbackSuccessDismissTask?.cancel()
        feedbackSuccessDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(7))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self?.feedbackMessage == AppStrings.Feedback.submitted else { return }
                self?.feedbackMessage = nil
                self?.feedbackSuccessDismissTask = nil
            }
        }
    }

    private func cancelFeedbackSuccessDismiss() {
        feedbackSuccessDismissTask?.cancel()
        feedbackSuccessDismissTask = nil
    }

    func deleteAccount(currentUser: AppUser) async -> String? {
        guard !isDeletingAccount else { return nil }

        isDeletingAccount = true
        defer { isDeletingAccount = false }

        do {
            try await repository.deleteAccount(currentUser: currentUser)
            _ = await AuthService.shared.completeAccountDeletionSignOut()
            resetForAuthChange()
            return nil
        } catch let deletionError as AccountDeletionError {
            switch deletionError {
            case .platformOwner:
                return AppStrings.Profile.deleteAccountPlatformOwnerBlocked
            case .ownsOrganization:
                return AppStrings.Profile.deleteAccountOrganizationOwnerBlocked
            case .requiresRecentLogin:
                return AppStrings.Profile.deleteAccountRequiresRecentLogin
            case .stageFailed(let stage, let permissionDenied):
                if permissionDenied {
                    return AppStrings.Profile.deleteAccountPermissionFailed
                }

                switch stage {
                case .serverDeletion:
                    return AppStrings.Profile.deleteAccountCleanupFailed
                }
            }
        } catch let appError as AppError {
            error = appError
            return AppStrings.Profile.deleteAccountFailed
        } catch {
            self.error = .unknown
            return AppStrings.Profile.deleteAccountFailed
        }
    }

    private func startLoad(force: Bool) async {
        guard force || !hasLoaded else { return }

        if let loadTask {
            await loadTask.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoad()
        }
        loadTask = task
        await task.value
        self.loadTask = nil
    }

    private func performLoad() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if !(repository is FirestoreUserRepository) {
                user = try await repository.fetchCurrentUser()
            }
            settings = try await repository.fetchSettings()
            settings.language = LocalizationStore.language
            error = nil
            profileMessage = nil
            hasLoaded = true
            lastLoadedAt = Date()
        } catch is CancellationError {
        } catch let appError as AppError {
            guard !Task.isCancelled else { return }
            error = appError
        } catch {
            guard !Task.isCancelled else { return }
            self.error = .unknown
        }
    }
}
