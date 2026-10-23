import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct SettingsPrivacyReliabilityTests {
    private func model(_ preferences: SettingsPreferencesRepository, reminders: SettingsReminderService,
                       loader: @escaping (String) async throws -> [Event]) -> ProfileViewModel {
        ProfileViewModel(repository: MockUserRepository(), feedbackRepository: MockFeedbackRepository(),
                         notificationPreferencesRepository: preferences,
                         notificationPermissionService: MockNotificationPermissionService(),
                         localEventReminderService: reminders, reminderEventsLoader: loader, notificationRegistrationUpdater: { _, _ in })
    }

    @Test func turningOffNotificationsCancelsWithoutAnEventRead() async {
        let preferences = SettingsPreferencesRepository()
        let reminders = SettingsReminderService()
        var reads = 0
        let viewModel = model(preferences, reminders: reminders) { _ in reads += 1; throw AppError.network }
        await viewModel.loadNotificationPreferencesIfNeeded(userID: "a")
        await viewModel.setNotificationsEnabled(false, userID: "a")
        #expect(reads == 0)
        #expect(reminders.last?.notificationsEnabled == false)
        #expect(reminders.eventCount == 0)
        #expect(preferences.value.notificationsEnabled == false)
        #expect(viewModel.notificationPreferencesMessage == AppStrings.Profile.notificationPreferencesSaved)
    }

    @Test func turningOffRemindersAlsoSkipsTheNetwork() async {
        let preferences = SettingsPreferencesRepository(), reminders = SettingsReminderService()
        let viewModel = model(preferences, reminders: reminders) { _ in throw AppError.network }
        await viewModel.loadNotificationPreferencesIfNeeded(userID: "a")
        await viewModel.setEventRemindersEnabled(false, userID: "a")
        #expect(reminders.last?.eventRemindersEnabled == false)
        #expect(preferences.value.notificationsEnabled)
        #expect(viewModel.notificationPreferencesMessage == AppStrings.Profile.notificationPreferencesSaved)
    }

    @Test func missingEventSourceDoesNotClearEnabledReminders() async {
        let preferences = SettingsPreferencesRepository(), reminders = SettingsReminderService()
        let viewModel = ProfileViewModel(repository: MockUserRepository(), feedbackRepository: MockFeedbackRepository(),
            notificationPreferencesRepository: preferences,
            notificationPermissionService: MockNotificationPermissionService(),
            localEventReminderService: reminders, notificationRegistrationUpdater: { _, _ in })
        await viewModel.loadNotificationPreferencesIfNeeded(userID: "a")
        await viewModel.setReminderLeadMinutes(30, userID: "a")
        #expect(reminders.last == nil)
        #expect(preferences.value.reminderLeadMinutes == 30)
        #expect(viewModel.notificationPreferencesMessage == AppStrings.Profile.notificationPreferencesSaved)
    }

    @Test func saveFailureRestoresTheConfirmedChoice() async {
        let preferences = SettingsPreferencesRepository(), reminders = SettingsReminderService()
        let viewModel = model(preferences, reminders: reminders) { _ in [] }
        await viewModel.loadNotificationPreferencesIfNeeded(userID: "a")
        preferences.saveFails = true
        await viewModel.setNotificationsEnabled(false, userID: "a")
        #expect(viewModel.notificationPreferences.notificationsEnabled)
        #expect(reminders.last == nil)
        #expect(viewModel.notificationPreferencesMessage == AppStrings.Profile.notificationPreferencesSaveFailed)
    }

    @Test func failedSchedulingReadKeepsPersistedSettingsAndCanRecover() async {
        let preferences = SettingsPreferencesRepository(), reminders = SettingsReminderService()
        var failing = true, reads = 0
        let viewModel = model(preferences, reminders: reminders) { id in
            #expect(id == "a"); reads += 1
            if failing { throw AppError.network }
            return []
        }
        await viewModel.loadNotificationPreferencesIfNeeded(userID: "a")
        await viewModel.setReminderLeadMinutes(30, userID: "a")
        #expect(viewModel.notificationPreferences.reminderLeadMinutes == 30)
        #expect(viewModel.notificationPreferencesMessage == AppStrings.Profile.notificationPreferencesSyncFailed)
        failing = false
        await viewModel.setReminderLeadMinutes(15, userID: "a")
        #expect(reads == 2)
        #expect(reminders.last?.reminderLeadMinutes == 15)
        #expect(viewModel.notificationPreferencesMessage == AppStrings.Profile.notificationPreferencesSaved)
    }

    @Test func factorReadForPreviousAccountCannotPopulateTheNewAccount() async {
        var principal: String? = "a"
        var resume: CheckedContinuation<[AuthMultiFactorFactor], Never>?
        let current = AuthMultiFactorFactor(id: "b-factor", displayName: "B", enrollmentDate: .now)
        let viewModel = AccountSecurityViewModel(multiFactorService: .shared, loadFactors: {
            if principal == "a" { return await withCheckedContinuation { resume = $0 } }
            return [current]
        }, currentPrincipal: { principal })
        let old = Task { await viewModel.load() }
        while resume == nil { await Task.yield() }
        principal = "b"; viewModel.configure(userID: principal)
        await viewModel.load()
        resume?.resume(returning: [.init(id: "a-factor", displayName: "A", enrollmentDate: .now)])
        await old.value
        #expect(viewModel.factors == [current])
        #expect(!viewModel.isLoading)
    }

    @Test func oldFailureCannotOverwriteASuccessfulSecurityRetryForAnotherAccount() async {
        var principal: String? = "a"
        var resume: CheckedContinuation<[AuthMultiFactorFactor], Error>?
        let viewModel = AccountSecurityViewModel(multiFactorService: .shared, loadFactors: {
            if principal == "a" { return try await withCheckedThrowingContinuation { resume = $0 } }
            return []
        }, currentPrincipal: { principal })
        let old = Task { await viewModel.load() }
        while resume == nil { await Task.yield() }
        principal = "b"; viewModel.configure(userID: principal)
        await viewModel.load()
        resume?.resume(throwing: AppError.network)
        await old.value
        #expect(viewModel.hasLoadedFactors)
        #expect(viewModel.errorMessage == nil)
    }

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "SettingsPrivacyTests.\(UUID().uuidString)")!
    }

    @Test func failedInitialBannerReadRemainsRetryableAndNeverEnablesCollection() async {
        var fails = true
        let service = BannerMeasurementService(defaults: defaults(), startsObservers: false,
            principalProvider: { "a" }, backendCall: { _, _ in
                if fails { throw AppError.network }
                return ["available": true, "enabled": false]
            })
        await service.refresh()
        #expect(service.canConfigure && service.hasError && !service.isBusy)
        #expect(!service.isEnabled)
        fails = false
        await service.refresh()
        #expect(service.hasLoaded && service.isAvailable && !service.hasError)
    }

    @Test func simultaneousBannerReadsAreCoalesced() async {
        var resume: CheckedContinuation<[String: Any], Never>?
        var calls = 0
        let service = BannerMeasurementService(defaults: defaults(), startsObservers: false,
            principalProvider: { "a" }, backendCall: { _, _ in
                calls += 1
                return await withCheckedContinuation { resume = $0 }
            })
        let first = Task { await service.refresh() }
        while resume == nil { await Task.yield() }
        await service.refresh()
        #expect(calls == 1 && service.isBusy)
        resume?.resume(returning: ["available": true, "enabled": false])
        await first.value
        #expect(!service.isBusy)
    }

    @Test func oldBannerWriteCannotLockOrEnableAnotherAccount() async {
        var principal: String? = "a"
        var resume: CheckedContinuation<[String: Any], Never>?
        var pendingID = ""
        let service = BannerMeasurementService(defaults: defaults(), startsObservers: false,
            principalProvider: { principal }, backendCall: { name, payload in
                if name == "getBannerMeasurementConsent" { return ["available": true, "enabled": false] }
                pendingID = payload["consentID"] as? String ?? ""
                return await withCheckedContinuation { resume = $0 }
            })
        await service.refresh()
        let old = Task { await service.setEnabled(true) }
        while resume == nil { await Task.yield() }
        principal = "b"
        await service.refresh()
        #expect(service.hasLoaded && !service.isBusy && !service.isEnabled)
        resume?.resume(returning: ["enabled": true, "consentID": pendingID])
        await old.value
        #expect(!service.isBusy && !service.isEnabled && !service.hasError)
    }

    @Test func returningToTheSameAccountDoesNotAcceptItsOldRead() async {
        var principal: String? = "a"
        var resume: CheckedContinuation<[String: Any], Never>?
        var calls = 0
        let service = BannerMeasurementService(defaults: defaults(), startsObservers: false,
            principalProvider: { principal }, backendCall: { _, _ in
                calls += 1
                if calls == 1 { return await withCheckedContinuation { resume = $0 } }
                return ["available": true, "enabled": false]
            })
        let old = Task { await service.refresh() }
        while resume == nil { await Task.yield() }
        principal = "b"; await service.refresh()
        principal = "a"; await service.refresh()
        resume?.resume(returning: ["available": true, "enabled": true, "consentID": "old", "allowsRegion": true])
        await old.value
        #expect(!service.isEnabled && !service.allowsRegionalMeasurement && !service.isBusy)
    }

    @Test func failedWithdrawalSurvivesRestartAndRetriesBeforeReadingConsent() async {
        let storage = defaults()
        let first = BannerMeasurementService(defaults: storage, startsObservers: false,
            principalProvider: { "a" }, backendCall: { name, _ in
                if name == "getBannerMeasurementConsent" {
                    return ["available": true, "enabled": true, "consentID": "grant", "allowsRegion": true]
                }
                throw AppError.network
            })
        await first.refresh()
        await first.setEnabled(false)
        #expect(!first.isEnabled && first.hasError)
        var requests: [String] = []
        let restored = BannerMeasurementService(defaults: storage, startsObservers: false,
            principalProvider: { "a" }, backendCall: { name, payload in
                requests.append(name)
                if name == "updateBannerMeasurementConsent" {
                    #expect(payload["enabled"] as? Bool == false)
                    return ["enabled": false, "consentID": "grant"]
                }
                return ["available": true, "enabled": false]
            })
        await restored.refresh()
        #expect(requests == ["updateBannerMeasurementConsent", "getBannerMeasurementConsent"])
        #expect(!restored.isEnabled && !restored.hasError)
    }
}

@MainActor
private final class SettingsPreferencesRepository: NotificationPreferencesRepository {
    var value = NotificationPreferences(notificationsEnabled: true, eventRemindersEnabled: true, reminderLeadMinutes: 60, updatedAt: nil)
    var saveFails = false
    func fetchNotificationPreferences(userID: String) async throws -> NotificationPreferences { value }
    func saveNotificationPreferences(_ preferences: NotificationPreferences, userID: String) async throws {
        if saveFails { throw AppError.network }
        value = preferences
    }
}

@MainActor
private final class SettingsReminderService: LocalEventReminderServiceProtocol {
    var last: NotificationPreferences?
    var eventCount = -1
    func scheduleEventReminder(event: Event, userID: String, leadMinutes: Int) async throws {}
    func scheduleTestNotification(userID: String) async throws {}
    func cancelEventReminder(eventID: String, userID: String) {}
    func reconcileEventReminders(events: [Event], userID: String, preferences: NotificationPreferences) async throws {
        last = preferences; eventCount = events.count
    }
}
