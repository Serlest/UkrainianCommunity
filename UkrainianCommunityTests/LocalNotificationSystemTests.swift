import Foundation
import Testing
import UserNotifications
@testable import UkrainianCommunity

@MainActor
struct LocalNotificationSystemTests {
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
