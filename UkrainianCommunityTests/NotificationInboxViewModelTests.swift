import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct NotificationInboxViewModelTests {
    private func notification(_ id: String, user: String = "user-1") -> AppNotification {
        AppNotification(id: id, recipientUserId: user, type: .systemAnnouncement,
            sourceType: .system, sourceId: "", message: "Details", payload: [:],
            isRead: false, readAt: nil, createdAt: .now)
    }

    @Test func readReceiptRemovesUnreadRowButPreservesDetailsRecord() async {
        let repository = InboxTestRepository()
        let model = NotificationInboxViewModel(repository: repository)
        await model.configure(userID: "user-1")
        let item = notification("first")
        repository.emit([item])
        model.selectedFilter = .unread
        await model.markRead(item)
        #expect(model.filteredNotifications.isEmpty)
        #expect(model.notifications.first?.id == item.id)
        #expect(model.notifications.first?.isRead == true)
        #expect(model.unreadCount == 0)
    }

    @Test func failedDeleteKeepsNotificationAndAllowsRetry() async {
        let repository = InboxTestRepository()
        let model = NotificationInboxViewModel(repository: repository)
        await model.configure(userID: "user-1")
        let item = notification("first")
        repository.emit([item])
        repository.deleteFails = true
        #expect(await model.delete(item) == false)
        #expect(model.notifications == [item])
        #expect(model.unreadCount == 1)
        #expect(model.error != nil)
        repository.deleteFails = false
        #expect(await model.delete(item))
        #expect(model.notifications.isEmpty)
        #expect(model.unreadCount == 0)
        #expect(model.error == nil)
    }

    @Test func listenerDeletionBeforeWriteCompletionDoesNotDoubleDecrementBadge() async {
        let repository = InboxTestRepository()
        let model = NotificationInboxViewModel(repository: repository)
        await model.configure(userID: "user-1")
        let first = notification("first"), second = notification("second")
        repository.emit([first, second])
        repository.beforeDeleteReturns = { repository.emit([second]) }
        #expect(await model.delete(first))
        #expect(model.notifications == [second])
        #expect(model.unreadCount == 1)
    }

    @Test func oldListenerCannotRestorePreviousAccountDataEvenAfterReturningToSameUser() async {
        let repository = InboxTestRepository()
        let model = NotificationInboxViewModel(repository: repository)
        await model.configure(userID: "user-1")
        let oldCallback = repository.callbacks[0]
        let oldError = repository.errors[0]
        let initialVersion = model.sessionVersion
        await model.configure(userID: "user-2")
        await model.configure(userID: "user-1")
        let current = notification("current")
        repository.emit([current])
        oldCallback([notification("stale")])
        oldError(.unknown)
        #expect(model.notifications == [current])
        #expect(model.error == nil)
        #expect(model.sessionVersion > initialVersion)
    }

    @Test func pendingDeleteCannotRemoveNewAccountsNotification() async {
        let repository = InboxTestRepository()
        let model = NotificationInboxViewModel(repository: repository)
        await model.configure(userID: "user-1")
        let old = notification("same-id")
        repository.emit([old])
        let current = notification("same-id", user: "user-2")
        repository.beforeDeleteReturns = {
            await model.configure(userID: "user-2")
            repository.emit([current])
        }
        #expect(await model.delete(old) == false)
        #expect(model.notifications == [current])
        #expect(model.unreadCount == 1)
        #expect(await model.delete(old) == false)
        #expect(repository.deleteCount == 1)
    }
}

@MainActor
private final class InboxTestRepository: NotificationInboxRepository {
    var callbacks: [@MainActor ([AppNotification]) -> Void] = []
    var errors: [@MainActor (AppError) -> Void] = []
    var deleteFails = false
    var deleteCount = 0
    var beforeDeleteReturns: (@MainActor () async -> Void)?

    func emit(_ notifications: [AppNotification]) { callbacks.last?(notifications) }
    func listenNotifications(userID: String, limit: Int,
        onChange: @escaping @MainActor ([AppNotification]) -> Void,
        onError: @escaping @MainActor (AppError) -> Void) -> AppRealtimeListener {
        callbacks.append(onChange)
        errors.append(onError)
        return InboxTestListener()
    }
    func deleteNotification(userID: String, notificationID: String) async throws {
        deleteCount += 1
        if deleteFails { throw AppError.unknown }
        await beforeDeleteReturns?()
    }
    func fetchNotifications(userID: String, limit: Int) async throws -> [AppNotification] { [] }
    func fetchUnreadCount(userID: String) async throws -> Int { 0 }
    func markNotificationRead(userID: String, notificationID: String) async throws {}
    func markNotificationUnread(userID: String, notificationID: String) async throws {}
    func markAllNotificationsRead(userID: String) async throws {}
    func markNotificationPopupPresented(userID: String, notificationID: String) async throws {}
    func archiveNotification(userID: String, notificationID: String) async throws {}
    func clearNotifications(userID: String) async throws {}
    func createNotification(userID: String, notification: AppNotification) async throws {}
}

private struct InboxTestListener: AppRealtimeListener { func cancel() {} }
