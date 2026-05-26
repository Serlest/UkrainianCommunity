import Foundation
import UserNotifications

protocol LocalEventReminderServiceProtocol {
    func scheduleEventReminder(event: Event, userID: String, leadMinutes: Int) async throws
    func scheduleTestNotification(userID: String) async throws
    func cancelEventReminder(eventID: String, userID: String)
}

struct LocalEventReminderService: LocalEventReminderServiceProtocol {
    func scheduleEventReminder(event: Event, userID: String, leadMinutes: Int) async throws {
        let reminderDate = event.startDate.addingTimeInterval(TimeInterval(-max(0, leadMinutes) * 60))
        guard reminderDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = event.title
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
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [notificationIdentifier(eventID: eventID, userID: userID)]
        )
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
}
