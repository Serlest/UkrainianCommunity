import Foundation
import Combine

enum NotificationInboxFilter: String, CaseIterable, Identifiable {
    case all
    case unread
    case archived

    var id: String { rawValue }
}

enum NotificationDetailLoadState {
    case loading, ready, unavailable
    case failed(AppError)
    var isReady: Bool { if case .ready = self { true } else { false } }
    var isUnavailable: Bool { if case .unavailable = self { true } else { false } }
}

@MainActor
final class NotificationInboxViewModel: ObservableObject {
    private enum ErrorSource: Hashable {
        case listener
        case refresh
        case badge
        case mutation
    }

    @Published private(set) var notifications: [AppNotification] = []
    @Published private(set) var unreadCount = 0
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var isClearing = false
    @Published private(set) var error: AppError?
    @Published private(set) var snapshotVersion = 0
    @Published private(set) var sessionVersion = 0
    @Published private(set) var isMutating = false
    @Published private(set) var isMarkingAllRead = false
    @Published private(set) var isFilterLoading = false
    @Published private(set) var failedLoadMore = false
    @Published private(set) var detailStates: [String: NotificationDetailLoadState] = [:]
    @Published var selectedFilter: NotificationInboxFilter = .all {
        didSet {
            guard selectedFilter != oldValue else { return }
            filterVersion += 1
            pageGeneration += 1
            isLoadingMore = false
            isFilterLoading = false
            failedLoadMore = false
            clearError(from: [.refresh])
        }
    }

    private let repository: NotificationInboxRepository
    private let badgeUpdater: (any NotificationBadgeUpdating)?
    private var unreadRevision = 0
    private var listener: AppRealtimeListener?
    private var listenerRecoveryTask: Task<Void, Never>?
    private var listenerGeneration = 0
    private var listenerRecoveryAttempt = 0
    private var badgeRefreshTask: Task<Void, Never>?
    private var errorSource: ErrorSource?
    private var mutationErrorNotificationID: String?
    private var detailReadTokens: [String: UUID] = [:]
    private var currentUserID: String?
    private let notificationPageSize = 50
    private var cursors: [NotificationInboxFilter: NotificationInboxCursor] = [:]
    private var morePages: [NotificationInboxFilter: Bool] = [:]
    private var loadedFilters: Set<NotificationInboxFilter> = []
    private var headIDs: Set<String> = []
    private var deletedIDs: Set<String> = []
    private var clearedThrough: Date?
    private var filterVersion = 0
    private var dataRevision = 0
    private var pageGeneration = 0
    private var refreshGeneration = 0
    private var pendingRefresh: (id: UUID, session: Int, revision: Int, filterVersion: Int)?

    var hasMoreNotifications: Bool { morePages[selectedFilter] ?? false }
    var isBusy: Bool { isMutating || isClearing }
    var canClear: Bool { !notifications.isEmpty && !isBusy }


    init(repository: NotificationInboxRepository, badgeUpdater: (any NotificationBadgeUpdating)? = nil) {
        self.repository = repository
        self.badgeUpdater = badgeUpdater
    }

    func configure(userID: String?) async {
        if currentUserID == userID {
            if let userID {
                if listener == nil { startListening(userID: userID) }
            } else {
                badgeUpdater?.setCount(0)
            }
            return
        }

        // Do not erase a valid APNs badge during a cold-start fetch for the same
        // restored session. Logout/account switching must clear the previous user.
        if currentUserID != nil || userID == nil { badgeUpdater?.setCount(0) }
        unreadRevision += 1
        badgeRefreshTask?.cancel()
        badgeRefreshTask = nil
        listenerRecoveryTask?.cancel()
        listenerRecoveryTask = nil
        listener?.cancel()
        listener = nil
        listenerGeneration += 1
        listenerRecoveryAttempt = 0
        currentUserID = userID
        sessionVersion += 1
        isLoading = false
        isLoadingMore = false
        isClearing = false
        notifications = []
        unreadCount = 0
        snapshotVersion = 0
        error = nil
        errorSource = nil
        mutationErrorNotificationID = nil
        detailStates = [:]; detailReadTokens = [:]
        selectedFilter = .all
        cursors = [:]
        morePages = [:]
        loadedFilters = []
        headIDs = []
        deletedIDs = []
        clearedThrough = nil
        pendingRefresh = nil
        failedLoadMore = false
        filterVersion += 1
        dataRevision += 1
        refreshGeneration += 1
        pageGeneration += 1
        isLoadingMore = false
        isFilterLoading = false
        isMutating = false
        isMarkingAllRead = false
        isFilterLoading = false

        guard let userID else { return }
        startListening(userID: userID)
    }

    var filteredNotifications: [AppNotification] {
        switch selectedFilter {
        case .all:
            notifications.filter { $0.isVisibleInInbox && !$0.isArchived }
        case .archived:
            notifications.filter { $0.isVisibleInInbox && $0.isArchived }
        case .unread:
            notifications.filter(\.countsAsUnread)
        }
    }

    func detailActionError(for id: String) -> AppError? {
        errorSource == .mutation && mutationErrorNotificationID == id ? error : nil
    }

    func prepareDetail(notificationID: String) async -> AppNotification? {
        guard let userID = currentUserID else { return nil }
        let session = sessionVersion, token = UUID()
        detailReadTokens[notificationID] = token
        detailStates[notificationID] = .loading
        do {
            let item = try await repository.fetchNotification(userID: userID, notificationID: notificationID)
            guard sessionVersion == session, detailReadTokens[notificationID] == token, !Task.isCancelled else { return nil }
            guard item.id == notificationID, item.recipientUserId == userID, item.isVisibleInInbox,
                  !deletedIDs.contains(notificationID), clearedThrough.map({ item.createdAt > $0 }) ?? true else { detailStates[notificationID] = .unavailable; return nil }
            merge([item]); detailStates[notificationID] = .ready
            return item
        } catch {
            guard sessionVersion == session, detailReadTokens[notificationID] == token, !Task.isCancelled else { return nil }
            let appError = (error as? AppError) ?? .unknown
            detailStates[notificationID] = [.notFound, .permissionDenied].contains(appError) ? .unavailable : .failed(appError)
            return nil
        }
    }

    func refresh() async {
        await refresh(clearErrorOnSuccess: true)
        await refreshBadge()
        if let userID = currentUserID, listener == nil {
            startListening(userID: userID)
        }
    }

    func loadMoreIfNeeded(currentNotification: AppNotification) async {
        guard currentNotification.id == filteredNotifications.last?.id else { return }
        await loadMore()
    }

    func loadInitialFilterIfNeeded() async {
        guard !loadedFilters.contains(selectedFilter) else { return }
        if selectedFilter == .all && isLoading && listener != nil { return }
        await loadPage(first: true)
    }

    func loadMore() async {
        guard hasMoreNotifications else { return }
        await loadPage(first: false)
    }

    func retry() async {
        if failedLoadMore && hasMoreNotifications { await loadMore() }
        else { await refresh() }
    }

    private func loadPage(first: Bool) async {
        guard let userID = currentUserID, !isBusy, !isLoadingMore, !isFilterLoading else { return }
        let session = sessionVersion, filter = selectedFilter, version = filterVersion, revision = dataRevision
        let snapshot = snapshotVersion
        pageGeneration += 1
        let generation = pageGeneration
        let cursor = first ? nil : cursors[filter]
        if first { isFilterLoading = true } else { isLoadingMore = true }
        defer {
            if sessionVersion == session && filterVersion == version && pageGeneration == generation {
                isFilterLoading = false
                isLoadingMore = false
            }
        }
        do {
            let page = try await repository.fetchNotificationPage(userID: userID, unreadOnly: filter == .unread,
                                                                  limit: notificationPageSize, after: cursor)
            guard sessionVersion == session, filterVersion == version, dataRevision == revision, pageGeneration == generation else { return }
            merge(page.items.filter { snapshotVersion == snapshot || !headIDs.contains($0.id) })
            cursors[filter] = page.nextCursor
            morePages[filter] = hasHistory(after: page)
            loadedFilters.insert(filter)
            snapshotVersion += 1
            failedLoadMore = false
            clearError(from: [.refresh])
        } catch {
            guard sessionVersion == session, filterVersion == version, pageGeneration == generation, !Task.isCancelled else { return }
            failedLoadMore = !first
            setError((error as? AppError) ?? .unknown, source: .refresh)
        }
    }

    func refreshBadge() async {
        guard let userID = currentUserID else { return }
        let session = sessionVersion
        unreadRevision += 1
        let revision = unreadRevision
        do {
            let count = try await RefreshRequest.run { [self] in
                try await repository.fetchUnreadCount(userID: userID)
            }
            guard sessionVersion == session, unreadRevision == revision else { return }
            setUnreadCount(count)
            clearError(from: [.badge])
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            // A failed/offline refresh must not erase a known badge.
            guard sessionVersion == session, unreadRevision == revision else { return }
            let appError = (error as? AppError) ?? .unknown
            // A transient badge-only network failure does not invalidate a
            // successfully loaded inbox snapshot. Authorization and query/schema
            // failures remain visible until the badge read itself recovers.
            if appError != .network {
                setError(appError, source: .badge)
            }
        }
    }

    private func setUnreadCount(_ count: Int) {
        unreadCount = max(0, count)
        badgeUpdater?.setCount(unreadCount)
    }

    private func refresh(clearErrorOnSuccess: Bool) async {
        guard let userID = currentUserID, !isBusy else { return }
        let session = sessionVersion, revision = dataRevision, version = filterVersion
        if let pendingRefresh, pendingRefresh.session == session, pendingRefresh.revision == revision,
           pendingRefresh.filterVersion == version { return }
        let requestID = UUID()
        pendingRefresh = (requestID, session, revision, version)
        defer { if pendingRefresh?.id == requestID { pendingRefresh = nil } }
        let snapshot = snapshotVersion
        let filter = selectedFilter
        let targetCount = max(notificationPageSize, notifications.filter { filter == .unread ? $0.countsAsUnread : $0.isVisibleInInbox }.count)
        refreshGeneration += 1
        pageGeneration += 1
        isLoadingMore = false
        isFilterLoading = false
        let generation = refreshGeneration
        isLoading = true
        failedLoadMore = false
        defer { if sessionVersion == session && refreshGeneration == generation { isLoading = false } }
        do {
            var page = try await repository.fetchNotificationPage(userID: userID, unreadOnly: filter == .unread,
                                                                  limit: notificationPageSize, after: nil)
            var records = page.items
            var ids = Set(records.map(\.id))
            var cursorsSeen = Set<String>()
            while records.count < targetCount, page.hasMore, let cursor = page.nextCursor {
                guard sessionVersion == session, dataRevision == revision, refreshGeneration == generation,
                      filterVersion == version, snapshotVersion == snapshot, !Task.isCancelled else { return }
                guard cursorsSeen.insert(cursor.documentID).inserted else { throw AppError.unknown }
                page = try await repository.fetchNotificationPage(userID: userID, unreadOnly: filter == .unread,
                    limit: notificationPageSize, after: cursor)
                records += page.items.filter { ids.insert($0.id).inserted }
            }
            guard sessionVersion == session, dataRevision == revision, refreshGeneration == generation,
                  filterVersion == version, snapshotVersion == snapshot else { return }
            // Refresh the selected page, retaining the bounded global head for popup routing.
            notifications.removeAll { !headIDs.contains($0.id) }
            merge(records)
            cursors = [:]
            morePages = [:]
            loadedFilters = []
            cursors[filter] = page.nextCursor
            morePages[filter] = hasHistory(after: page)
            loadedFilters.insert(filter)
            failedLoadMore = false
            snapshotVersion += 1
            if clearErrorOnSuccess { clearError(from: [.refresh]) }
        } catch {
            guard sessionVersion == session, dataRevision == revision, refreshGeneration == generation,
                  filterVersion == version, !Task.isCancelled else { return }
            setError((error as? AppError) ?? .unknown, source: .refresh)
        }
    }

    func markRead(_ notification: AppNotification) async {
        guard let userID = currentUserID, notification.recipientUserId == userID, !notification.isRead else { return }
        await markRead(notificationID: notification.id)
    }

    /// Marks an inbox record viewed when its destination was opened outside the
    /// inbox list (for example from an APNs route or the content-planning screen).
    func markRead(notificationID: String) async {
        guard let userID = currentUserID, !notificationID.isEmpty else { return }
        if let notification = notifications.first(where: { $0.id == notificationID }), notification.isRead {
            return
        }
        guard beginMutation() else { return }
        let session = sessionVersion
        defer { endMutation(session: session) }

        do {
            try await repository.markNotificationRead(userID: userID, notificationID: notificationID)
            guard sessionVersion == session else { return }
            applyReadState(notificationID: notificationID, isRead: true, readAt: Date())
            clearError(from: [.mutation])
            await refreshBadge()
        } catch let appError as AppError {
            guard sessionVersion == session else { return }
            setError(appError, source: .mutation, notificationID: notificationID)
        } catch {
            guard sessionVersion == session else { return }
            setError(.unknown, source: .mutation, notificationID: notificationID)
        }
    }

    func markUnread(_ notification: AppNotification) async {
        guard let userID = currentUserID, notification.recipientUserId == userID,
              notifications.first(where: { $0.id == notification.id }).map({ $0.isRead || $0.isArchived }) == true else { return }
        guard beginMutation() else { return }
        let session = sessionVersion
        defer { endMutation(session: session) }

        do {
            try await repository.markNotificationUnread(userID: userID, notificationID: notification.id)
            guard sessionVersion == session else { return }
            if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
                notifications[index] = notifications[index].updatingArchiveState(archivedAt: nil)
            }
            applyReadState(notificationID: notification.id, isRead: false, readAt: nil)
            clearError(from: [.mutation])
            await refreshBadge()
        } catch let appError as AppError {
            guard sessionVersion == session else { return }
            setError(appError, source: .mutation, notificationID: notification.id)
        } catch {
            guard sessionVersion == session else { return }
            setError(.unknown, source: .mutation, notificationID: notification.id)
        }
    }

    func markAllRead() async {
        guard let userID = currentUserID, unreadCount > 0 else { return }
        guard beginMutation() else { return }
        let session = sessionVersion
        defer { endMutation(session: session) }

        let existingIDs = Set(notifications.map(\.id))
        isMarkingAllRead = true
        defer { if sessionVersion == session { isMarkingAllRead = false } }
        do {
            try await repository.markAllNotificationsRead(userID: userID)
            guard sessionVersion == session else { return }
            notifications = notifications.map { notification in
                guard existingIDs.contains(notification.id), notification.countsAsUnread else { return notification }
                return notification.updatingReadState(isRead: true, readAt: notification.readAt ?? Date())
            }
            clearError(from: [.mutation])
            await refreshBadge()
        } catch let appError as AppError {
            guard sessionVersion == session else { return }
            setError(appError, source: .mutation)
        } catch {
            guard sessionVersion == session else { return }
            setError(.unknown, source: .mutation)
        }
    }

    func archive(_ notification: AppNotification) async {
        guard let userID = currentUserID, notification.recipientUserId == userID else { return }
        guard beginMutation() else { return }
        let session = sessionVersion
        defer { endMutation(session: session) }

        do {
            try await repository.archiveNotification(userID: userID, notificationID: notification.id)
            guard sessionVersion == session else { return }
            applyArchiveState(notificationID: notification.id)
            clearError(from: [.mutation])
            await refreshBadge()
        } catch let appError as AppError {
            guard sessionVersion == session else { return }
            setError(appError, source: .mutation, notificationID: notification.id)
        } catch {
            guard sessionVersion == session else { return }
            setError(.unknown, source: .mutation, notificationID: notification.id)
        }
    }

    @discardableResult
    func delete(_ notification: AppNotification) async -> Bool {
        guard let userID = currentUserID, notification.recipientUserId == userID else { return false }
        guard beginMutation() else { return false }
        let session = sessionVersion
        defer { endMutation(session: session) }
        do {
            try await repository.deleteNotification(userID: userID, notificationID: notification.id)
            guard sessionVersion == session else { return false }
            markUnavailable(notification.id)
            notifications.removeAll { $0.id == notification.id }
            clearError(from: [.mutation])
            await refreshBadge()
            return sessionVersion == session
        } catch {
            guard sessionVersion == session else { return false }
            setError((error as? AppError) ?? .unknown, source: .mutation, notificationID: notification.id)
            return false
        }
    }

    func clearAll() async {
        guard let userID = currentUserID, !notifications.isEmpty, !isClearing else { return }
        guard beginMutation() else { return }
        let session = sessionVersion
        defer { endMutation(session: session) }
        let cutoff = Date()
        isClearing = true
        defer { if sessionVersion == session { isClearing = false } }

        do {
            try await repository.clearNotifications(userID: userID)
            guard sessionVersion == session else { return }
            clearedThrough = cutoff
            notifications.removeAll { $0.createdAt <= cutoff }
            cursors = [:]
            morePages = [:]
            loadedFilters = []
            snapshotVersion += 1
            clearError(from: [.mutation])
            await refreshBadge()
        } catch let appError as AppError {
            guard sessionVersion == session else { return }
            setError(appError, source: .mutation)
        } catch {
            guard sessionVersion == session else { return }
            setError(.unknown, source: .mutation)
        }
    }

    func restore(_ notification: AppNotification) async {
        guard let userID = currentUserID, notification.recipientUserId == userID,
              notification.isArchived, beginMutation() else { return }
        let session = sessionVersion
        defer { endMutation(session: session) }
        do {
            try await repository.restoreNotification(userID: userID, notificationID: notification.id)
            guard sessionVersion == session else { return }
            if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
                notifications[index] = notifications[index].updatingArchiveState(archivedAt: nil)
                    .updatingReadState(isRead: true, readAt: Date())
            }
            clearError(from: [.mutation])
        } catch {
            guard sessionVersion == session else { return }
            setError((error as? AppError) ?? .unknown, source: .mutation, notificationID: notification.id)
        }
    }

    private func beginMutation() -> Bool {
        guard !isBusy else { return false }
        isMutating = true
        dataRevision += 1
        refreshGeneration += 1
        pageGeneration += 1
        isLoadingMore = false
        isFilterLoading = false
        isLoading = false
        return true
    }

    private func endMutation(session: Int) {
        guard sessionVersion == session else { return }
        isMutating = false
        Task { await loadInitialFilterIfNeeded() }
    }

    private func hasHistory(after page: NotificationInboxPage) -> Bool {
        guard page.hasMore else { return false }
        guard let clearedThrough else { return true }
        return page.nextCursor.map { $0.createdAt > clearedThrough } ?? false
    }

    private func markUnavailable(_ id: String) {
        deletedIDs.insert(id); detailReadTokens[id] = UUID(); detailStates[id] = .unavailable
    }

    private func merge(_ items: [AppNotification]) {
        var records = Dictionary(notifications.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for item in items {
            if !item.isVisibleInInbox { markUnavailable(item.id) }
            guard item.isVisibleInInbox, !deletedIDs.contains(item.id),
                  clearedThrough.map({ item.createdAt > $0 }) ?? true else {
                records.removeValue(forKey: item.id)
                continue
            }
            records[item.id] = item
        }
        notifications = records.values.sorted {
            $0.createdAt == $1.createdAt ? $0.id > $1.id : $0.createdAt > $1.createdAt
        }
    }

    private func startListening(userID: String) {
        let session = sessionVersion
        listenerRecoveryTask?.cancel()
        listenerRecoveryTask = nil
        listenerGeneration += 1
        let generation = listenerGeneration
        isLoading = notifications.isEmpty
        listener = repository.listenNotificationHead(
            userID: userID,
            limit: notificationPageSize,
            onChange: { [weak self] page in
                guard let self,
                      self.sessionVersion == session,
                      self.listenerGeneration == generation else { return }
                let incomingIDs = Set(page.items.map(\.id))
                let boundary = page.items.last
                let headWasReplaced = !self.headIDs.isEmpty && self.headIDs.isDisjoint(with: incomingIDs)
                self.notifications.removeAll { item in
                    guard self.headIDs.contains(item.id), !incomingIDs.contains(item.id) else { return false }
                    // Keep rows pushed out of a full live head; remove actual disappearances.
                    guard page.hasMore, let boundary else { return true }
                    return item.createdAt > boundary.createdAt
                        || (item.createdAt == boundary.createdAt && item.id >= boundary.id)
                }
                self.headIDs = incomingIDs
                self.merge(page.items)
                if !self.loadedFilters.contains(.all) || (headWasReplaced && page.hasMore) {
                    self.cursors[.all] = page.nextCursor
                    self.morePages[.all] = self.hasHistory(after: page)
                    self.loadedFilters.insert(.all)
                }
                self.snapshotVersion += 1
                self.isLoading = false
                self.clearError(from: [.listener])
                self.listenerRecoveryAttempt = 0
                self.scheduleBadgeRefresh()
            },
            onError: { [weak self] appError in
                guard let self,
                      self.sessionVersion == session,
                      self.listenerGeneration == generation else { return }
                self.handleListenerError(appError, userID: userID, session: session)
            }
        )
    }

    private func scheduleBadgeRefresh() {
        badgeRefreshTask?.cancel()
        badgeRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            await self.refreshBadge()
            guard !Task.isCancelled else { return }
            self.badgeRefreshTask = nil
        }
    }

    private func handleListenerError(_ appError: AppError, userID: String, session: Int) {
        listener?.cancel()
        listener = nil
        isLoading = false
        isLoadingMore = false
        setError(appError, source: .listener)

        Task { [weak self] in
            guard let self, self.sessionVersion == session else { return }
            await refresh(clearErrorOnSuccess: false)
            guard self.sessionVersion == session, self.listener == nil else { return }
            self.scheduleListenerRecovery(userID: userID, session: session)
        }
    }

    private func scheduleListenerRecovery(userID: String, session: Int) {
        listenerRecoveryTask?.cancel()
        listenerRecoveryAttempt += 1
        let exponent = min(listenerRecoveryAttempt - 1, 5)
        let delaySeconds = min(30, 1 << exponent)

        listenerRecoveryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(Double(delaySeconds)))
            } catch {
                return
            }
            guard !Task.isCancelled,
                  let self,
                  self.sessionVersion == session,
                  self.currentUserID == userID,
                  self.listener == nil else { return }
            self.listenerRecoveryTask = nil
            self.startListening(userID: userID)
        }
    }

    private func applyReadState(notificationID: String, isRead: Bool, readAt: Date?) {
        guard let index = notifications.firstIndex(where: { $0.id == notificationID }) else { return }
        let notification = notifications[index]
        notifications[index] = notification.updatingReadState(isRead: isRead, readAt: readAt)
    }

    private func setError(_ error: AppError, source: ErrorSource, notificationID: String? = nil) {
        self.error = error
        errorSource = source
        mutationErrorNotificationID = source == .mutation ? notificationID : nil
    }

    private func clearError(from sources: Set<ErrorSource>) {
        guard let errorSource, sources.contains(errorSource) else { return }
        error = nil
        self.errorSource = nil
        mutationErrorNotificationID = nil
    }

    private func applyArchiveState(notificationID: String) {
        guard let index = notifications.firstIndex(where: { $0.id == notificationID }) else { return }
        let notification = notifications[index]
        notifications[index] = notification.updatingArchiveState(archivedAt: Date()).updatingReadState(isRead: true, readAt: Date())
    }

}
