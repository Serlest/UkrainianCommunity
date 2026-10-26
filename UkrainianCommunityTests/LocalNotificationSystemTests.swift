import Foundation
import Testing
import UserNotifications
@testable import UkrainianCommunity

@MainActor
@Suite(.serialized)
struct LocalNotificationSystemTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["UAC_REAL_NOTIFICATION_PROBE"] == "1"))
    func realReminderQueueKeepsExactTargetAndReschedulesThenCancels() async throws {
        let center = UNUserNotificationCenter.current()
        #expect(try await center.requestAuthorization(options: [.provisional]))
        let uid = "reminder-audit-" + UUID().uuidString, eventID = "event-" + UUID().uuidString
        LocalReminderSession.shared.transition(to: uid); await LocalReminderSession.shared.waitUntilIdle()
        let start = Date().addingTimeInterval(7200)
        let event = Event(id: eventID, title: "Isolated reminder", summary: "", details: "", city: "Innsbruck", venue: "Fixture",
            startDate: start, endDate: start.addingTimeInterval(3600), createdAt: .now, updatedAt: .now,
            capacity: nil, registeredCount: 1, comments: [], moderationStatus: .approved,
            registrationState: .registered, likeCount: 0, likeState: .notLiked)
        let service = LocalEventReminderService(), identifier = "eventReminder:\(eventID):\(uid)"
        defer { center.removePendingNotificationRequests(withIdentifiers: [identifier]) }
        try await service.scheduleEventReminder(event: event, userID: uid, leadMinutes: 30)
        let first = try #require(await center.pendingNotificationRequests().first { $0.identifier == identifier })
        #expect(RemoteNotificationRoute(userInfo: first.content.userInfo)?.destination == .openEvent(eventId: eventID))
        #expect(RemoteNotificationRoute(userInfo: first.content.userInfo)?.recipientUserID == uid)
        let firstDate = try #require((first.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate())
        #expect(abs(firstDate.timeIntervalSince(start.addingTimeInterval(-1800))) < 60)
        try await service.scheduleEventReminder(event: event, userID: uid, leadMinutes: 60)
        let replacements = await center.pendingNotificationRequests().filter { $0.identifier == identifier }
        #expect(replacements.count == 1)
        let replacementDate = try #require((replacements.first?.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate())
        #expect(abs(replacementDate.timeIntervalSince(start.addingTimeInterval(-3600))) < 60)
        try await service.scheduleEventReminder(event: event, userID: uid, leadMinutes: 1440)
        #expect(await center.pendingNotificationRequests().contains { $0.identifier == identifier } == false,
                "An already passed lead time must remove the previous pending reminder")
        try await service.scheduleEventReminder(event: event, userID: uid, leadMinutes: 30)
        service.cancelEventReminder(eventID: eventID, userID: uid); await LocalReminderSession.shared.waitUntilIdle()
        #expect(await center.pendingNotificationRequests().contains { $0.identifier == identifier } == false)
        LocalReminderSession.shared.transition(to: nil); await LocalReminderSession.shared.waitUntilIdle()
    }
    @Test func reminderPayloadOpensExactEventOnlyForItsAccountWithoutForgingInboxReceipt() throws {
        let route = try #require(RemoteNotificationRoute(userInfo: LocalEventReminderService.routePayload(eventID: "exact-event", userID: "first")))
        #expect(route.destination == .openEvent(eventId: "exact-event"))
        #expect(route.notificationId == nil)
        #expect(route.canOpen(for: "first"))
        #expect(!route.canOpen(for: "second"))
        #expect(!route.canOpen(for: nil))
    }
    // Run separately so other auth/session tests cannot clear the shared OS queue.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["UAC_REAL_NOTIFICATION_PROBE"] == "1"))
    func confirmedAccountTransitionsCleanTheRealSimulatorNotificationQueue() async throws {
        let center = UNUserNotificationCenter.current()
        let allowed = try await center.requestAuthorization(options: [.provisional])
        #expect(allowed)
        let suffix = UUID().uuidString
        let oldUser = "old-\(suffix)", newUser = "new-\(suffix)"
        let oldID = "eventReminder:fixture:\(oldUser)"
        let newID = "eventReminder:fixture:\(newUser)"
        let unrelatedID = "unrelated-fixture-\(suffix)"
        let ids = [oldID, newID, unrelatedID]
        defer { center.removePendingNotificationRequests(withIdentifiers: ids) }
        for id in ids {
            let content = UNMutableNotificationContent()
            content.title = "Local audit fixture"
            try await center.add(UNNotificationRequest(identifier: id, content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)))
        }
        let before = Set(await center.pendingNotificationRequests().map(\.identifier))
        #expect(Set(ids).isSubset(of: before))
        let session = LocalReminderSession()
        session.transition(to: newUser)
        await session.waitUntilIdle()
        let switched = Set(await center.pendingNotificationRequests().map(\.identifier))
        #expect(!switched.contains(oldID))
        #expect(switched.contains(newID))
        #expect(switched.contains(unrelatedID))
        session.transition(to: nil)
        await session.waitUntilIdle()
        let signedOut = Set(await center.pendingNotificationRequests().map(\.identifier))
        #expect(!signedOut.contains(newID))
        #expect(signedOut.contains(unrelatedID))
    }
}
