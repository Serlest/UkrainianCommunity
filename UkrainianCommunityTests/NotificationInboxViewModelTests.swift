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
    @Test func iconBadgeUsesWholeInboxAndTracksReadArchiveDeleteAndClear() async {
        let repository = InboxTestRepository()
        let badge = BadgeRecorder()
        let model = NotificationInboxViewModel(repository: repository, badgeUpdater: badge)
        await model.configure(userID: "user-1")
        #expect(badge.counts.isEmpty) // Cold start must not erase an existing APNs badge.
        repository.additionalUnread = 75
        let item = notification("visible")
        repository.emit([item])
        #expect(model.unreadCount == 76)
        #expect(badge.counts.last == 76)
        await model.markRead(item)
        #expect(badge.counts.last == 75)
        await model.markUnread(model.notifications[0])
        #expect(badge.counts.last == 76)
        await model.archive(item)
        #expect(badge.counts.last == 75)
        #expect(await model.delete(item))
        #expect(badge.counts.last == 75)
        await model.markAllRead()
        #expect(badge.counts.last == 0)
        repository.emit([notification("new")])
        await model.clearAll()
        #expect(badge.counts.last == 0)
    }

    @Test func badgePreservesCountOnFailureAndRejectsOldAccountCallbacks() async {
        let repository = InboxTestRepository(), badge = BadgeRecorder()
        let model = NotificationInboxViewModel(repository: repository, badgeUpdater: badge)
        await model.configure(userID: "user-1")
        repository.emit([notification("first")])
        let oldCount = repository.unreadCallbacks[0]
        repository.countFails = true
        await model.refreshBadge()
        #expect(badge.counts.last == 1)
        await model.configure(userID: "user-2")
        #expect(badge.counts.last == 0)
        repository.emit([notification("second", user: "user-2")])
        oldCount(99)
        #expect(badge.counts.last == 1)
        await model.configure(userID: nil)
        repository.unreadCallbacks.last?(99)
        #expect(badge.counts.last == 0)
    }

    @Test func delayedBadgeFetchCannotOverwriteNewerListenerOrLogout() async {
        let repository = InboxTestRepository(), badge = BadgeRecorder()
        let model = NotificationInboxViewModel(repository: repository, badgeUpdater: badge)
        await model.configure(userID: "user-1")
        repository.emit([notification("first")])
        var pending: CheckedContinuation<Int, Never>?
        repository.fetchCount = { await withCheckedContinuation { pending = $0 } }
        let refresh = Task { await model.refreshBadge() }
        while pending == nil { await Task.yield() }
        repository.unreadCallbacks.last?(8)
        pending?.resume(returning: 1)
        await refresh.value
        #expect(badge.counts.last == 8)
        pending = nil
        let oldSessionRefresh = Task { await model.refreshBadge() }
        while pending == nil { await Task.yield() }
        await model.configure(userID: nil)
        pending?.resume(returning: 8)
        await oldSessionRefresh.value
        #expect(badge.counts.last == 0)
    }

}

@MainActor
private final class InboxTestRepository: NotificationInboxRepository {
    var callbacks: [@MainActor ([AppNotification]) -> Void] = []
    var errors: [@MainActor (AppError) -> Void] = []
    var unreadCallbacks: [@MainActor (Int) -> Void] = []
    var items: [AppNotification] = []
    var additionalUnread = 0
    var countFails = false
    var fetchCount: (() async throws -> Int)?
    var deleteFails = false
    var deleteCount = 0
    var beforeDeleteReturns: (@MainActor () async -> Void)?

    func emit(_ notifications: [AppNotification]) {
        items = notifications
        callbacks.last?(notifications)
        unreadCallbacks.last?(items.filter(\.countsAsUnread).count + additionalUnread)
    }
    func listenUnreadCount(userID: String, onChange: @escaping @MainActor (Int) -> Void,
        onError: @escaping @MainActor (AppError) -> Void) -> AppRealtimeListener {
        unreadCallbacks.append(onChange)
        return InboxTestListener()
    }
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
        items.removeAll { $0.id == notificationID }
        await beforeDeleteReturns?()
    }
    func fetchNotifications(userID: String, limit: Int) async throws -> [AppNotification] { [] }
    func fetchUnreadCount(userID: String) async throws -> Int {
        if countFails { throw AppError.network }
        if let fetchCount { return try await fetchCount() }
        return items.filter(\.countsAsUnread).count + additionalUnread
    }
    func markNotificationRead(userID: String, notificationID: String) async throws {
        items = items.map { $0.id == notificationID ? $0.updatingReadState(isRead: true, readAt: .now) : $0 }
    }
    func markNotificationUnread(userID: String, notificationID: String) async throws {
        items = items.map { $0.id == notificationID ? $0.updatingReadState(isRead: false, readAt: nil) : $0 }
    }
    func markAllNotificationsRead(userID: String) async throws {
        items = items.map { $0.updatingReadState(isRead: true, readAt: .now) }
        additionalUnread = 0
    }
    func markNotificationPopupPresented(userID: String, notificationID: String) async throws {}
    func archiveNotification(userID: String, notificationID: String) async throws {
        items = items.map { $0.id == notificationID ? $0.updatingArchiveState(archivedAt: .now) : $0 }
    }
    func clearNotifications(userID: String) async throws { items = []; additionalUnread = 0 }
    func createNotification(userID: String, notification: AppNotification) async throws {}
}

private struct InboxTestListener: AppRealtimeListener { func cancel() {} }

@MainActor
private final class BadgeRecorder: NotificationBadgeUpdating {
    var counts: [Int] = []
    func setCount(_ count: Int) { counts.append(count) }
}
