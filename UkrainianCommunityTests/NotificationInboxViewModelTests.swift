import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct NotificationInboxViewModelTests {
    @Test func criticalPopupOldReceiptCannotCloseTheSameAccountsNewSession() async {
        let repo = InboxTestRepository()
        let subject = NotificationPopupCoordinatorService(repository: repo)
        let item = AppNotification(id: "critical", recipientUserId: "first", type: .systemAnnouncement,
            sourceType: .system, sourceId: "", severity: .critical, requiresPopup: true,
            message: "Important", payload: [:], isRead: false, readAt: nil, createdAt: .now)
        subject.configure(userID: "first"); subject.receiveInboxSnapshot([item], userID: "first")
        var continuation: CheckedContinuation<Void, Never>?
        repo.beforeMarkReadReturns = { await withCheckedContinuation { continuation = $0 } }
        let old = Task { await subject.dismissActiveNotification(markRead: true) }
        while continuation == nil { await Task.yield() }
        #expect(subject.isWritingReceipt)
        #expect(await subject.dismissActiveNotification(markRead: true) == false)
        subject.configure(userID: "second"); subject.configure(userID: "first")
        subject.receiveInboxSnapshot([item], userID: "first")
        continuation?.resume()
        #expect(await old.value == false)
        #expect(subject.activeNotification?.id == item.id)
        #expect(repo.popupReceiptIDs.isEmpty)
    }
    @Test func criticalPopupRejectsForeignArchivedExpiredAndExcludedTypes() {
        let subject = NotificationPopupCoordinatorService(repository: InboxTestRepository())
        subject.configure(userID: "first")
        func item(_ id: String, user: String = "first", type: AppNotificationType = .systemAnnouncement,
                  expires: Date? = nil, archived: Date? = nil) -> AppNotification {
            .init(id: id, recipientUserId: user, type: type, sourceType: .system, sourceId: "",
                  severity: .critical, requiresPopup: true, expiresAt: expires, archivedAt: archived,
                  payload: [:], isRead: false, readAt: nil, createdAt: .now)
        }
        subject.receiveInboxSnapshot([item("foreign", user: "second"), item("expired", expires: .distantPast),
            item("archived", archived: .now), item("legal", type: .legalDocumentsUpdated),
            item("restriction", type: .accountStatusChanged)], userID: "first")
        #expect(subject.activeNotification == nil)
        subject.receiveInboxSnapshot([item("eligible")], userID: "first")
        #expect(subject.activeNotification?.id == "eligible")
    }
    @Test func deletedDetailCannotOfferActionsFromItsCachedRow() async {
        let repo = InboxTestRepository()
        let inbox = NotificationInboxViewModel(repository: repo)
        await inbox.configure(userID: "user-1")
        let item = notification("gone")
        await repo.emit([item]); repo.detailFetch = { _ in throw AppError.notFound }
        #expect(await inbox.prepareDetail(notificationID: item.id) == nil)
        #expect(inbox.detailStates[item.id]?.isUnavailable == true)
    }

    @Test func failedDetailRetainsReadableCacheAndCanVerifyOnRetry() async {
        let repo = InboxTestRepository()
        let inbox = NotificationInboxViewModel(repository: repo)
        await inbox.configure(userID: "user-1")
        let item = notification("retry")
        await repo.emit([item]); repo.detailFetch = { _ in throw AppError.network }
        #expect(await inbox.prepareDetail(notificationID: item.id) == nil)
        #expect(inbox.notifications.contains { $0.id == item.id })
        #expect(inbox.detailStates[item.id]?.isReady == false)
        repo.detailFetch = { _ in item }
        #expect(await inbox.prepareDetail(notificationID: item.id)?.id == item.id)
        #expect(inbox.detailStates[item.id]?.isReady == true)
    }

    @Test func lateDetailCannotCrossAnAccountSwitch() async {
        let repo = InboxTestRepository()
        let model = NotificationInboxViewModel(repository: repo)
        await model.configure(userID: "user-1")
        var resume: CheckedContinuation<AppNotification, Never>?
        repo.detailFetch = { _ in await withCheckedContinuation { resume = $0 } }
        let task = Task { await model.prepareDetail(notificationID: "old") }
        while resume == nil { await Task.yield() }
        await model.configure(userID: "user-2")
        resume?.resume(returning: notification("old"))
        #expect(await task.value == nil); #expect(model.detailStates.isEmpty); #expect(model.notifications.isEmpty)
    }

    @Test func tombstoneDuringDetailReadCannotBeResurrectedByTheOlderResponse() async {
        let repo = InboxTestRepository()
        let model = NotificationInboxViewModel(repository: repo)
        await model.configure(userID: "user-1")
        let item = notification("deleted-during-read")
        await repo.emit([item])
        var resume: CheckedContinuation<AppNotification, Never>?
        repo.detailFetch = { _ in await withCheckedContinuation { resume = $0 } }
        let task = Task { await model.prepareDetail(notificationID: item.id) }
        while resume == nil { await Task.yield() }
        await repo.emit([item.updatingDeleteState(deletedAt: .now)])
        resume?.resume(returning: item)
        #expect(await task.value == nil); #expect(model.detailStates[item.id]?.isUnavailable == true)
        #expect(!model.notifications.contains { $0.id == item.id })
    }

    @Test func failedReceiptBelongsToItsNotificationNotAnotherDetail() async {
        let repo = InboxTestRepository()
        let model = NotificationInboxViewModel(repository: repo)
        await model.configure(userID: "user-1")
        let item = notification("receipt-failed")
        await repo.emit([item]); repo.markReadFails = true
        await model.markRead(item)
        #expect(model.detailActionError(for: item.id) == .network)
        #expect(model.detailActionError(for: "other") == nil)
    }
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

    @Test func refreshPreservesTheConfirmedLoadedHistoryRange() async {
        let repository = InboxTestRepository()
        let model = NotificationInboxViewModel(repository: repository)
        await model.configure(userID: "user-1")
        let head = (0..<50).map { notification("head-\($0)") }
        let older = (0..<50).map { notification("old-\($0)") }
        await repository.emit(head)
        repository.pageFetch = { _, cursor in
            let values = cursor == nil ? head : older
            return NotificationInboxPage(items: values, nextCursor: cursor == nil ? .init(createdAt: head.last!.createdAt, documentID: head.last!.id) : nil, hasMore: cursor == nil)
        }
        await model.loadMore()
        #expect(model.notifications.count == 100)
        await model.refresh()
        #expect(model.notifications.count == 100)
        #expect(Set(model.notifications.map(\.id)).count == 100)
    }

    @Test func identicalConcurrentRefreshesDoNotDuplicateThePageRead() async {
        let repository = InboxTestRepository()
        let model = NotificationInboxViewModel(repository: repository)
        await model.configure(userID: "user-1")
        await repository.emit([notification("first")])
        var reads = 0
        var waits: [CheckedContinuation<NotificationInboxPage, Never>] = []
        repository.pageFetch = { _, _ in
            reads += 1
            return await withCheckedContinuation { waits.append($0) }
        }
        let first = Task { await model.refresh() }
        while waits.isEmpty { await Task.yield() }
        let second = Task { await model.refresh() }
        for _ in 0..<60 { await Task.yield() }
        let observed = reads
        for wait in waits { wait.resume(returning: .init(items: [], nextCursor: nil, hasMore: false)) }
        await first.value; await second.value
        #expect(observed == 1)
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
        #expect(model.failedLoadMore)
        repository.pageFetch = { _, cursor in
            #expect(cursor == originalCursor)
            return NotificationInboxPage(items: [], nextCursor: nil, hasMore: false)
        }
        await model.retry()
        #expect(model.error == nil)
        #expect(!model.failedLoadMore)
        #expect(repository.callbacks.count == 1)
    }

}

@MainActor
private final class InboxTestRepository: NotificationInboxRepository {
    var detailFetch: ((String) async throws -> AppNotification)?
    var markReadFails = false
    func fetchNotification(userID: String, notificationID: String) async throws -> AppNotification {
        if let detailFetch { return try await detailFetch(notificationID) }
        guard let item = items.first(where: { $0.id == notificationID }), item.isVisibleInInbox else { throw AppError.notFound }
        return item
    }
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
    var popupReceiptIDs: [String] = []
    var beforeMarkReadReturns: (@MainActor () async -> Void)?
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
        if markReadFails { throw AppError.network }
        markReadIDs.append(notificationID)
        await beforeMarkReadReturns?()
        items = items.map { $0.id == notificationID ? $0.updatingReadState(isRead: true, readAt: .now) : $0 }
    }
    func markNotificationUnread(userID: String, notificationID: String) async throws {
        items = items.map { $0.id == notificationID ? $0.updatingArchiveState(archivedAt: nil).updatingReadState(isRead: false, readAt: nil) : $0 }
    }
    func markAllNotificationsRead(userID: String) async throws {
        items = items.map { $0.updatingReadState(isRead: true, readAt: .now) }
        additionalUnread = 0
    }
    func markNotificationPopupPresented(userID: String, notificationID: String) async throws { popupReceiptIDs.append(notificationID) }
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
