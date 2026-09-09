import Foundation
import Combine

enum NotificationInboxFilter: String, CaseIterable, Identifiable {
    case all
    case unread

    var id: String { rawValue }
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
    @Published var selectedFilter: NotificationInboxFilter = .all

    private let repository: NotificationInboxRepository
    private let badgeUpdater: (any NotificationBadgeUpdating)?
    private var unreadRevision = 0
    private var listener: AppRealtimeListener?
    private var listenerRecoveryTask: Task<Void, Never>?
    private var listenerGeneration = 0
    private var listenerRecoveryAttempt = 0
    private var badgeRefreshTask: Task<Void, Never>?
    private var errorSource: ErrorSource?
    private var currentUserID: String?
    private let notificationPageSize = 50
    private var notificationLimit = 50
    private var canLoadMoreNotifications = false

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
        selectedFilter = .all
        notificationLimit = notificationPageSize
        canLoadMoreNotifications = false

        guard let userID else { return }
        startListening(userID: userID)
    }

    var filteredNotifications: [AppNotification] {
        switch selectedFilter {
        case .all:
            notifications
        case .unread:
            notifications.filter(\.countsAsUnread)
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
        guard currentNotification.id == filteredNotifications.last?.id,
              canLoadMoreNotifications,
              !isLoadingMore,
              error == nil,
              let userID = currentUserID else { return }

        isLoadingMore = true
        notificationLimit += notificationPageSize
        restartListener(userID: userID)
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
        guard let userID = currentUserID else { return }
        let session = sessionVersion
        isLoading = true
        defer { if sessionVersion == session { isLoading = false } }

        do {
            let loadedNotifications = try await RefreshRequest.run { [self] in try await repository.fetchNotifications(userID: userID, limit: notificationLimit) }
            guard sessionVersion == session else { return }
            notifications = loadedNotifications
            canLoadMoreNotifications = loadedNotifications.count >= notificationLimit
            isLoadingMore = false
            snapshotVersion += 1
            if clearErrorOnSuccess {
                clearError(from: [.listener, .refresh])
            }
        } catch let appError as AppError {
            guard sessionVersion == session else { return }
            setError(appError, source: .refresh)
        } catch {
            guard sessionVersion == session else { return }
            setError(.unknown, source: .refresh)
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
        let session = sessionVersion

        do {
            try await repository.markNotificationRead(userID: userID, notificationID: notificationID)
            guard sessionVersion == session else { return }
            applyReadState(notificationID: notificationID, isRead: true, readAt: Date())
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

    func markUnread(_ notification: AppNotification) async {
        guard let userID = currentUserID, notification.recipientUserId == userID, notification.isRead else { return }
        let session = sessionVersion

        do {
            try await repository.markNotificationUnread(userID: userID, notificationID: notification.id)
            guard sessionVersion == session else { return }
            applyReadState(notificationID: notification.id, isRead: false, readAt: nil)
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

    func markAllRead() async {
        guard let userID = currentUserID, unreadCount > 0 else { return }
        let session = sessionVersion

        do {
            try await repository.markAllNotificationsRead(userID: userID)
            guard sessionVersion == session else { return }
            notifications = notifications.map { notification in
                guard notification.countsAsUnread else { return notification }
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
        let session = sessionVersion

        do {
            try await repository.archiveNotification(userID: userID, notificationID: notification.id)
            guard sessionVersion == session else { return }
            applyArchiveState(notificationID: notification.id)
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

    @discardableResult
    func delete(_ notification: AppNotification) async -> Bool {
        guard let userID = currentUserID, notification.recipientUserId == userID else { return false }
        let session = sessionVersion
        do {
            try await repository.deleteNotification(userID: userID, notificationID: notification.id)
            guard sessionVersion == session else { return false }
            notifications.removeAll { $0.id == notification.id }
            clearError(from: [.mutation])
            await refreshBadge()
            return sessionVersion == session
        } catch {
            guard sessionVersion == session else { return false }
            setError((error as? AppError) ?? .unknown, source: .mutation)
            return false
        }
    }

    func clearAll() async {
        guard let userID = currentUserID, !notifications.isEmpty, !isClearing else { return }
        let session = sessionVersion
        isClearing = true
        defer { if sessionVersion == session { isClearing = false } }

        do {
            try await repository.clearNotifications(userID: userID)
            guard sessionVersion == session else { return }
            notifications = []
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

    private func startListening(userID: String) {
        let session = sessionVersion
        listenerRecoveryTask?.cancel()
        listenerRecoveryTask = nil
        listenerGeneration += 1
        let generation = listenerGeneration
        isLoading = notifications.isEmpty
        listener = repository.listenNotifications(
            userID: userID,
            limit: notificationLimit,
            onChange: { [weak self] notifications in
                guard let self,
                      self.sessionVersion == session,
                      self.listenerGeneration == generation else { return }
                self.notifications = notifications
                self.canLoadMoreNotifications = notifications.count >= self.notificationLimit
                self.snapshotVersion += 1
                self.isLoading = false
                self.isLoadingMore = false
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

    private func restartListener(userID: String) {
        listener?.cancel()
        listener = nil
        startListening(userID: userID)
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

    private func setError(_ error: AppError, source: ErrorSource) {
        self.error = error
        errorSource = source
    }

    private func clearError(from sources: Set<ErrorSource>) {
        guard let errorSource, sources.contains(errorSource) else { return }
        error = nil
        self.errorSource = nil
    }

    private func applyArchiveState(notificationID: String) {
        guard let index = notifications.firstIndex(where: { $0.id == notificationID }) else { return }
        let notification = notifications[index]
        notifications[index] = notification.updatingArchiveState(archivedAt: Date())
    }

}
