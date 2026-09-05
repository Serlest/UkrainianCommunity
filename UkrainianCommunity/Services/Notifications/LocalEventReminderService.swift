import Foundation
import UserNotifications

protocol LocalEventReminderServiceProtocol {
    func scheduleEventReminder(event: Event, userID: String, leadMinutes: Int) async throws
    func scheduleTestNotification(userID: String) async throws
    func cancelEventReminder(eventID: String, userID: String)
    func reconcileEventReminders(events: [Event], userID: String, preferences: NotificationPreferences) async throws
}

struct LocalEventReminderService: LocalEventReminderServiceProtocol {
    func scheduleEventReminder(event: Event, userID: String, leadMinutes: Int) async throws {
        try await LocalReminderSession.shared.perform(for: userID) {
            try await scheduleReminder(event: event, userID: userID, leadMinutes: leadMinutes)
        }
    }

    private func scheduleReminder(event: Event, userID: String, leadMinutes: Int) async throws {
        guard let occurrence = event.nextOccurrence() else { return }
        let reminderDate = occurrence.startDate.addingTimeInterval(TimeInterval(-max(0, leadMinutes) * 60))
        guard reminderDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = event.localizedTitle
        content.body = reminderBody(for: event)
        content.sound = .default

        let dateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminderDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(
            identifier: notificationIdentifier(eventID: event.id, userID: userID),
            content: content,
            trigger: trigger
        )

        try await UNUserNotificationCenter.current().add(request)
    }

    func scheduleTestNotification(userID: String) async throws {
        try await LocalReminderSession.shared.perform(for: userID) {
            try await scheduleTest(userID: userID)
        }
    }

    private func scheduleTest(userID: String) async throws {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus.canShowLocalNotifications else {
            throw AppError.permissionDenied
        }

        let content = UNMutableNotificationContent()
        content.title = AppStrings.LocalNotifications.testTitle
        content.body = AppStrings.LocalNotifications.testBody
        content.sound = .default

        let identifier = testNotificationIdentifier(userID: userID)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 4, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [identifier]
        )
        try await UNUserNotificationCenter.current().add(request)

        let pendingRequests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        guard pendingRequests.contains(where: { $0.identifier == identifier }) else {
            throw AppError.unknown
        }
    }

    func cancelEventReminder(eventID: String, userID: String) {
        LocalReminderSession.shared.enqueue(for: userID) {
            let identifiers = [notificationIdentifier(eventID: eventID, userID: userID)]
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
        }
    }

    func reconcileEventReminders(
        events: [Event],
        userID: String,
        preferences: NotificationPreferences
    ) async throws {
        try await LocalReminderSession.shared.perform(for: userID) {
            try await reconcileCurrentSession(events: events, userID: userID, preferences: preferences)
        }
    }

    private func reconcileCurrentSession(events: [Event], userID: String, preferences: NotificationPreferences) async throws {
        let pendingRequests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let userSuffix = ":\(userID)"
        let reminderIdentifiers = pendingRequests
            .map(\.identifier)
            .filter { $0.hasPrefix("eventReminder:") && $0.hasSuffix(userSuffix) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: reminderIdentifiers
        )

        let activeIDs = Set(events.filter { !$0.isCancelled && $0.moderationStatus != .archived }
            .map { notificationIdentifier(eventID: $0.id, userID: userID) })
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications().map { $0.request.identifier }
        let obsolete = delivered.filter { id in
            id.hasPrefix("eventReminder:") && id.hasSuffix(userSuffix)
                && (!preferences.notificationsEnabled || !preferences.eventRemindersEnabled || !activeIDs.contains(id))
        }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: obsolete)
        if !preferences.notificationsEnabled {
            let test = [testNotificationIdentifier(userID: userID)]
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: test)
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: test)
        }
        guard preferences.notificationsEnabled, preferences.eventRemindersEnabled else { return }
        for event in events where event.nextOccurrence() != nil {
            try await scheduleReminder(
                event: event,
                userID: userID,
                leadMinutes: preferences.reminderLeadMinutes
            )
        }
    }

    private func notificationIdentifier(eventID: String, userID: String) -> String {
        "eventReminder:\(eventID):\(userID)"
    }

    private func testNotificationIdentifier(userID: String) -> String {
        "testNotification:\(userID)"
    }

    private func reminderBody(for event: Event) -> String {
        let venue = event.venue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !venue.isEmpty {
            return venue
        }

        let city = event.city.trimmingCharacters(in: .whitespacesAndNewlines)
        if !city.isEmpty {
            return city
        }

        return AppStrings.LocalNotifications.eventReminderFallbackBody
    }
}

private extension UNAuthorizationStatus {
    var canShowLocalNotifications: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            true
        case .denied, .notDetermined:
            false
        @unknown default:
            false
        }
    }
}

struct MockLocalEventReminderService: LocalEventReminderServiceProtocol {
    func scheduleEventReminder(event: Event, userID: String, leadMinutes: Int) async throws {}
    func scheduleTestNotification(userID: String) async throws {}
    func cancelEventReminder(eventID: String, userID: String) {}
    func reconcileEventReminders(events: [Event], userID: String, preferences: NotificationPreferences) async throws {}
}
