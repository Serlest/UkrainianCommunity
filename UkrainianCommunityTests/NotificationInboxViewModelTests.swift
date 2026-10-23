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
        await repository.emit([item])
        await model.refreshBadge()
        model.selectedFilter = .unread
        await model.markRead(item)
        #expect(model.filteredNotifications.isEmpty)
        #expect(model.notifications.first?.id == item.id)
        #expect(model.notifications.first?.isRead == true)
        #expect(model.unreadCount == 0)
    }

    @Test func destinationOpenedOutsideInboxMarksNotificationByIdentifier() async {
        let repository = InboxTestRepository()
        let model = NotificationInboxViewModel(repository: repository)
        await model.configure(userID: "user-1")
        let item = notification("contentDraftReady_draft-1")
        await repository.emit([item])
        await model.refreshBadge()

        await model.markRead(notificationID: item.id)

        #expect(repository.markReadIDs == [item.id])
        #expect(model.notifications.first?.isRead == true)
        #expect(model.unreadCount == 0)
    }

    @Test func failedDeleteKeepsNotificationAndAllowsRetry() async {
        let repository = InboxTestRepository()
        let model = NotificationInboxViewModel(repository: repository)
        await model.configure(userID: "user-1")
        let item = notification("first")
        await repository.emit([item])
        await model.refreshBadge()
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
        await repository.emit([first, second])
        await model.refreshBadge()
        repository.beforeDeleteReturns = {
            await repository.emit([second])
            await model.refreshBadge()
        }
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
        await repository.emit([current])
        await model.refreshBadge()
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
        await repository.emit([old])
        await model.refreshBadge()
        let current = notification("same-id", user: "user-2")
        repository.beforeDeleteReturns = {
            await model.configure(userID: "user-2")
            await repository.emit([current])
            await model.refreshBadge()
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
        await repository.emit([item])
        await model.refreshBadge()
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
        await repository.emit([notification("new")])
        await model.refreshBadge()
        await model.clearAll()
        #expect(badge.counts.last == 0)
    }

    @Test func badgePreservesCountOnFailureAndRejectsOldAccountCallbacks() async {
        let repository = InboxTestRepository(), badge = BadgeRecorder()
        let model = NotificationInboxViewModel(repository: repository, badgeUpdater: badge)
        await model.configure(userID: "user-1")
        await repository.emit([notification("first")])
        await model.refreshBadge()
        repository.countFails = true
        await model.refreshBadge()
        #expect(badge.counts.last == 1)
        #expect(model.error == nil)
        await model.configure(userID: "user-2")
        #expect(badge.counts.last == 0)
        repository.countFails = false
        await repository.emit([notification("second", user: "user-2")])
        await model.refreshBadge()
        #expect(badge.counts.last == 1)
        await model.configure(userID: nil)
        #expect(badge.counts.last == 0)
    }

    @Test func listenerSnapshotDoesNotClearMutationFailure() async {
        let repository = InboxTestRepository()
        let model = NotificationInboxViewModel(repository: repository)
        await model.configure(userID: "user-1")
        let item = notification("first")
        await repository.emit([item])
        repository.deleteFails = true

        #expect(await model.delete(item) == false)
        #expect(model.error == .unknown)

        await repository.emit([item])

        #expect(model.notifications == [item])
        #expect(model.error == .unknown)
    }

    @Test func badgePermissionFailureRemainsVisibleUntilBadgeReadRecovers() async {
        let repository = InboxTestRepository()
        let model = NotificationInboxViewModel(repository: repository)
        await model.configure(userID: "user-1")
        let item = notification("first")
        await repository.emit([item])
        repository.countError = .permissionDenied

        await model.refreshBadge()
        #expect(model.error == .permissionDenied)

        await repository.emit([item])
        #expect(model.error == .permissionDenied)

        repository.countError = nil
        await model.refreshBadge()
        #expect(model.error == nil)
    }

    @Test func successfulFallbackReadDoesNotPretendListenerRecovered() async {
        let repository = InboxTestRepository()
        let model = NotificationInboxViewModel(repository: repository)
        await model.configure(userID: "user-1")
        let item = notification("cached")
        await repository.emit([item])
        repository.fetchedNotifications = [item]

        repository.errors.last?(.network)
        while model.snapshotVersion < 2 { await Task.yield() }

        #expect(model.notifications == [item])
        #expect(model.error == .network)
        await model.configure(userID: nil)
    }

    @Test func delayedBadgeFetchCannotOverwriteNewerListenerOrLogout() async {
        let repository = InboxTestRepository(), badge = BadgeRecorder()
        let model = NotificationInboxViewModel(repository: repository, badgeUpdater: badge)
        await model.configure(userID: "user-1")
        await repository.emit([notification("first")])
        await model.refreshBadge()
        var pending: CheckedContinuation<Int, Never>?
        repository.fetchCount = { await withCheckedContinuation { pending = $0 } }
        let refresh = Task { await model.refreshBadge() }
        while pending == nil { await Task.yield() }
        repository.fetchCount = { 8 }
        await model.refreshBadge()
        pending?.resume(returning: 1)
        await refresh.value
        #expect(badge.counts.last == 8)
        pending = nil
        repository.fetchCount = { await withCheckedContinuation { pending = $0 } }
        let oldSessionRefresh = Task { await model.refreshBadge() }
        while pending == nil { await Task.yield() }
        await model.configure(userID: nil)
        pending?.resume(returning: 8)
        await oldSessionRefresh.value
        #expect(badge.counts.last == 0)
    }

    @Test func cancelledBadgeFetchDoesNotPublishUnknownError() async {
        let repository = InboxTestRepository(), badge = BadgeRecorder()
        let model = NotificationInboxViewModel(repository: repository, badgeUpdater: badge)
        await model.configure(userID: "user-1")
        await repository.emit([notification("first")])
        await model.refreshBadge()
        var fetchStarted = false
        repository.fetchCount = {
            fetchStarted = true
            try await Task.sleep(for: .seconds(60))
            return 9
        }

        let refresh = Task { await model.refreshBadge() }
        while !fetchStarted { await Task.yield() }
        refresh.cancel()
        await refresh.value

        #expect(model.error == nil)
        #expect(badge.counts.last == 1)
    }

    @Test func deletedHeadCannotHideOlderVisibleNotifications() async {
        let repository = InboxTestRepository()
        let model = NotificationInboxViewModel(repository: repository)
        await model.configure(userID: "user-1")
        let deleted = (0..<50).map { notification("deleted-\($0)").updatingDeleteState(deletedAt: .now) }
        await repository.emit(deleted)
        #expect(model.filteredNotifications.isEmpty)
        #expect(model.hasMoreNotifications)
        let older = notification("older")
        repository.pageFetch = { unread, cursor in
            #expect(!unread)
            #expect(cursor != nil)
            return NotificationInboxPage(items: [older], nextCursor: nil, hasMore: false)
        }
        await model.loadMore()
        #expect(model.filteredNotifications.map(\.id) == ["older"])
        #expect(!model.hasMoreNotifications)
        #expect(repository.callbacks.count == 1)
    }

    @Test func unreadQueryFindsOldRecordBeyondReadHead() async {
        let repository = InboxTestRepository()
        let model = NotificationInboxViewModel(repository: repository)
        await model.configure(userID: "user-1")
        await repository.emit((0..<50).map { notification("read-\($0)").updatingReadState(isRead: true, readAt: .now) })
        let older = notification("old-unread")
        repository.pageFetch = { unread, cursor in
            #expect(unread)
            #expect(cursor == nil)
            return NotificationInboxPage(items: [older], nextCursor: nil, hasMore: false)
        }
        model.selectedFilter = .unread
        await model.loadInitialFilterIfNeeded()
        #expect(model.filteredNotifications.map(\.id) == ["old-unread"])
        #expect(repository.callbacks.count == 1)
    }

    @Test func archiveCanBeRestoredOrMarkedUnreadConsistently() async {
        let repository = InboxTestRepository()
        let model = NotificationInboxViewModel(repository: repository)
        await model.configure(userID: "user-1")
        let item = notification("archived").updatingArchiveState(archivedAt: .now).updatingReadState(isRead: true, readAt: .now)
        await repository.emit([item])
        #expect(model.filteredNotifications.isEmpty)
        model.selectedFilter = .archived
        #expect(model.filteredNotifications.count == 1)
        await model.restore(item)
        #expect(model.filteredNotifications.isEmpty)
        model.selectedFilter = .all
        #expect(model.filteredNotifications.first?.isArchived == false)
        await repository.emit([item])
        await model.markUnread(item)
        model.selectedFilter = .unread
        #expect(model.filteredNotifications.first?.id == item.id)
        #expect(model.unreadCount == 1)
    }

    @Test func repeatedActionsAreBlockedUntilWriteCompletes() async {
        let repository = InboxTestRepository()
        let model = NotificationInboxViewModel(repository: repository)
        await model.configure(userID: "user-1")
        let first = notification("first"), second = notification("second")
        await repository.emit([first, second])
        repository.beforeDeleteReturns = {
            #expect(model.isBusy)
            #expect(await model.delete(second) == false)
            await model.markRead(second)
            await model.clearAll()
        }
        #expect(await model.delete(first))
        #expect(repository.deleteCount == 1)
        #expect(repository.markReadIDs.isEmpty)
        #expect(model.notifications.map(\.id) == ["second"])
        #expect(!model.isBusy)
    }

    @Test func staleRefreshCannotRestoreDeletedRecord() async {
        let repository = InboxTestRepository()
        let model = NotificationInboxViewModel(repository: repository)
        await model.configure(userID: "user-1")
        let item = notification("old")
        await repository.emit([item])
        var resume: CheckedContinuation<NotificationInboxPage, Never>?
        repository.pageFetch = { _, _ in
            await withCheckedContinuation { resume = $0 }
        }
        let refresh = Task { await model.refresh() }
        while resume == nil { await Task.yield() }
        #expect(await model.delete(item))
        resume?.resume(returning: NotificationInboxPage(items: [item], nextCursor: nil, hasMore: false))
        await refresh.value
        #expect(model.notifications.isEmpty)
    }

    @Test func staleRefreshCannotOverwriteLiveReadReceipt() async {
        let repository = InboxTestRepository()
        let model = NotificationInboxViewModel(repository: repository)
        await model.configure(userID: "user-1")
        let item = notification("old")
        await repository.emit([item])
        var resume: CheckedContinuation<NotificationInboxPage, Never>?
        repository.pageFetch = { _, _ in await withCheckedContinuation { resume = $0 } }
        let refresh = Task { await model.refresh() }
        while resume == nil { await Task.yield() }
        await repository.emit([item.updatingReadState(isRead: true, readAt: .now)])
        resume?.resume(returning: NotificationInboxPage(items: [item], nextCursor: nil, hasMore: false))
        await refresh.value
        #expect(model.notifications.first?.isRead == true)
    }

    @Test func clearPreservesNotificationsArrivingDuringTheWrite() async {
        let repository = InboxTestRepository()
        let model = NotificationInboxViewModel(repository: repository)
        await model.configure(userID: "user-1")
        let old = notification("old")
        await repository.emit([old])
        repository.beforeClearReturns = {
            await repository.emit([self.notification("new")])
        }
        await model.clearAll()
        #expect(model.notifications.map(\.id) == ["new"])
        #expect(model.unreadCount == 1)
    }

    @Test func legacyUnreadArchiveIsRestoredWhenMarkedUnread() async {
        let repository = InboxTestRepository()
        let model = NotificationInboxViewModel(repository: repository)
        await model.configure(userID: "user-1")
        let legacy = notification("legacy").updatingArchiveState(archivedAt: .now)
        await repository.emit([legacy])
        #expect(model.unreadCount == 0)
        await model.markUnread(legacy)
        #expect(model.notifications.first?.isArchived == false)
        #expect(model.unreadCount == 1)
    }

    @Test func liveHeadDoesNotUnlockOrOverwritePendingHistoricalPage() async {
        let repository = InboxTestRepository()
        let model = NotificationInboxViewModel(repository: repository)
        await model.configure(userID: "user-1")
        let head = (0..<50).map { notification("head-\($0)") }
        await repository.emit(head)
        var resume: CheckedContinuation<NotificationInboxPage, Never>?
        var requests = 0
        repository.pageFetch = { _, _ in
            requests += 1
            return await withCheckedContinuation { resume = $0 }
        }
        let load = Task { await model.loadMore() }
        while resume == nil { await Task.yield() }
        await repository.emit(head.map { $0.updatingReadState(isRead: true, readAt: .now) })
        #expect(model.isLoadingMore)
        await model.loadMore()
        #expect(requests == 1)
        let old = notification("older")
        resume?.resume(returning: NotificationInboxPage(items: [head[0], old], nextCursor: nil, hasMore: false))
        await load.value
        #expect(model.notifications.first(where: { $0.id == head[0].id })?.isRead == true)
        #expect(model.notifications.contains { $0.id == old.id })
        #expect(!model.isLoadingMore)
    }

    @Test func equalTimestampHeadEvictionPreservesTheCursorBoundaryRecord() async {
        let repository = InboxTestRepository()
        let model = NotificationInboxViewModel(repository: repository)
        await model.configure(userID: "user-1")
        func item(_ index: Int) -> AppNotification {
            AppNotification(id: String(format: "%03d", index), recipientUserId: "user-1", type: .systemAnnouncement,
                            sourceType: .system, sourceId: "", payload: [:], isRead: false, readAt: nil,
                            createdAt: Date(timeIntervalSince1970: 1000))
        }
        let head = (1...50).reversed().map(item)
        await repository.emit(head)
        await repository.emit([item(51)] + Array(head.prefix(49)))
        #expect(model.notifications.contains { $0.id == "001" })
        #expect(model.notifications.count == 51)
    }

    @Test func aCompleteHeadReplacementReopensPaginationToAvoidAGap() async {
        let repository = InboxTestRepository()
        let model = NotificationInboxViewModel(repository: repository)
        await model.configure(userID: "user-1")
        await repository.emit([notification("initial")])
        #expect(!model.hasMoreNotifications)
        let newer = (0..<50).map { notification("new-\($0)") }
        await repository.emit(newer)
        #expect(model.hasMoreNotifications)
        repository.pageFetch = { _, cursor in
            #expect(cursor?.documentID == newer.last?.id)
            return NotificationInboxPage(items: [], nextCursor: nil, hasMore: false)
        }
        await model.loadMore()
    }

    @Test func failedPageCanRetrySameCursorAndDoesNotRestartListener() async {
        let repository = InboxTestRepository()
        let model = NotificationInboxViewModel(repository: repository)
        await model.configure(userID: "user-1")
        await repository.emit((0..<50).map { notification("row-\($0)") })
        var originalCursor: NotificationInboxCursor?
        repository.pageFetch = { _, cursor in
            originalCursor = cursor
            throw AppError.network
        }
        await model.loadMore()
        #expect(model.error == .network)
        #expect(model.hasMoreNotifications)
        repository.pageFetch = { _, cursor in
            #expect(cursor == originalCursor)
            return NotificationInboxPage(items: [], nextCursor: nil, hasMore: false)
        }
        await model.loadMore()
        #expect(model.error == nil)
        #expect(repository.callbacks.count == 1)
    }

}

@MainActor
private final class InboxTestRepository: NotificationInboxRepository {
    var callbacks: [@MainActor ([AppNotification]) -> Void] = []
    var errors: [@MainActor (AppError) -> Void] = []
    var items: [AppNotification] = []
    var additionalUnread = 0
    var countFails = false
    var countError: AppError?
    var fetchCount: (() async throws -> Int)?
    var fetchedNotifications: [AppNotification] = []
    var deleteFails = false
    var deleteCount = 0
    var beforeDeleteReturns: (@MainActor () async -> Void)?
    var badgeFetchCount = 0
    var markReadIDs: [String] = []
    var pageFetch: ((Bool, NotificationInboxCursor?) async throws -> NotificationInboxPage)?
    var beforeClearReturns: (@MainActor () async -> Void)?

    func fetchNotificationPage(userID: String, unreadOnly: Bool, limit: Int, after: NotificationInboxCursor?) async throws -> NotificationInboxPage {
        if let pageFetch { return try await pageFetch(unreadOnly, after) }
        return NotificationInboxPage(items: Array(fetchedNotifications.prefix(limit)), nextCursor: nil, hasMore: false)
    }

    func restoreNotification(userID: String, notificationID: String) async throws {
        items = items.map { $0.id == notificationID ? $0.updatingArchiveState(archivedAt: nil).updatingReadState(isRead: true, readAt: .now) : $0 }
    }


    func emit(_ notifications: [AppNotification]) async {
        let previousFetchCount = badgeFetchCount
        items = notifications
        callbacks.last?(notifications)
        // Production schedules an aggregation refresh from the bounded inbox
        // listener. Wait for the mock aggregation to observe this snapshot.
        while badgeFetchCount == previousFetchCount { await Task.yield() }
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
    func fetchNotifications(userID: String, limit: Int) async throws -> [AppNotification] {
        return Array(fetchedNotifications.prefix(limit))
    }
    func fetchUnreadCount(userID: String) async throws -> Int {
        badgeFetchCount += 1
        if let countError { throw countError }
        if countFails { throw AppError.network }
        if let fetchCount { return try await fetchCount() }
        return items.filter(\.countsAsUnread).count + additionalUnread
    }
    func markNotificationRead(userID: String, notificationID: String) async throws {
        markReadIDs.append(notificationID)
        items = items.map { $0.id == notificationID ? $0.updatingReadState(isRead: true, readAt: .now) : $0 }
    }
    func markNotificationUnread(userID: String, notificationID: String) async throws {
        items = items.map { $0.id == notificationID ? $0.updatingArchiveState(archivedAt: nil).updatingReadState(isRead: false, readAt: nil) : $0 }
    }
    func markAllNotificationsRead(userID: String) async throws {
        items = items.map { $0.updatingReadState(isRead: true, readAt: .now) }
        additionalUnread = 0
    }
    func markNotificationPopupPresented(userID: String, notificationID: String) async throws {}
    func archiveNotification(userID: String, notificationID: String) async throws {
        items = items.map { $0.id == notificationID ? $0.updatingArchiveState(archivedAt: .now) : $0 }
    }
    func clearNotifications(userID: String) async throws { items = []; additionalUnread = 0; await beforeClearReturns?() }
    func createNotification(userID: String, notification: AppNotification) async throws {}
}

private struct InboxTestListener: AppRealtimeListener { func cancel() {} }

@MainActor
private final class BadgeRecorder: NotificationBadgeUpdating {
    var counts: [Int] = []
    func setCount(_ count: Int) { counts.append(count) }
}
