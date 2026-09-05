import Foundation
import UserNotifications

/// Serializes local notification work across confirmed account transitions.
/// No Auth/network dependency: offline sign-out still invalidates old work.
@MainActor
final class LocalReminderSession {
    static let shared = LocalReminderSession()
    private(set) var userID: String?
    private var generation = 0
    private var tail: Task<Void, Never>?
    private let cleanup: (String?) async -> Void

    init(cleanup: @escaping (String?) async -> Void = LocalReminderSession.cleanNotifications) {
        self.cleanup = cleanup
    }

    func transition(to userID: String?) {
        guard self.userID != userID || tail == nil else { return }
        self.userID = userID
        generation &+= 1
        let previous = tail
        let cleanup = self.cleanup
        tail = Task {
            await previous?.value
            await cleanup(userID)
        }
    }

    func perform(for userID: String, operation: @escaping () async throws -> Void) async throws {
        try await enqueue(for: userID, operation: operation).value
    }

    @discardableResult
    func enqueue(for userID: String, operation: @escaping () async throws -> Void) -> Task<Void, Error> {
        let expected = generation
        let previous = tail
        let task = Task { @MainActor in
            await previous?.value
            guard self.userID == userID, self.generation == expected else { throw CancellationError() }
            try await operation()
            // The transition cleanup is queued after this operation, so an
            // add that finishes after logout is removed before new work runs.
            guard self.userID == userID, self.generation == expected else { throw CancellationError() }
        }
        tail = Task { _ = await task.result }
        return task
    }

    func waitUntilIdle() async { await tail?.value }

    static func cleanNotifications(keeping userID: String?) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        let delivered = await center.deliveredNotifications().map { $0.request.identifier }
        func obsolete(_ id: String) -> Bool {
            guard id.hasPrefix("eventReminder:") || id.hasPrefix("testNotification:") else { return false }
            return userID.map { !id.hasSuffix(":" + $0) } ?? true
        }
        center.removePendingNotificationRequests(withIdentifiers: pending.filter(obsolete))
        center.removeDeliveredNotifications(withIdentifiers: delivered.filter(obsolete))
    }
}
