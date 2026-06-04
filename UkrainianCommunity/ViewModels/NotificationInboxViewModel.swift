import Foundation
import Combine

enum NotificationInboxFilter: String, CaseIterable, Identifiable {
    case all
    case unread

    var id: String { rawValue }
}

@MainActor
final class NotificationInboxViewModel: ObservableObject {
    @Published private(set) var notifications: [AppNotification] = []
    @Published private(set) var unreadCount = 0
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?
    @Published var selectedFilter: NotificationInboxFilter = .all

    private let repository: NotificationInboxRepository
    private var listener: AppRealtimeListener?
    private var currentUserID: String?
    private let notificationLimit = 50

    init(repository: NotificationInboxRepository) {
        self.repository = repository
    }

    func configure(userID: String?) async {
        guard currentUserID != userID else { return }
        listener?.cancel()
        listener = nil
        currentUserID = userID
        notifications = []
        unreadCount = 0
        error = nil
        selectedFilter = .all

        guard let userID else { return }
        startListening(userID: userID)
        await refresh()
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
        guard let userID = currentUserID else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            notifications = try await repository.fetchNotifications(userID: userID, limit: notificationLimit)
            unreadCount = try await repository.fetchUnreadCount(userID: userID)
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    func markRead(_ notification: AppNotification) async {
        guard let userID = currentUserID, !notification.isRead else { return }

        do {
            try await repository.markNotificationRead(userID: userID, notificationID: notification.id)
            applyReadState(notificationID: notification.id, isRead: true, readAt: Date())
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    func markUnread(_ notification: AppNotification) async {
        guard let userID = currentUserID, notification.isRead else { return }

        do {
            try await repository.markNotificationUnread(userID: userID, notificationID: notification.id)
            applyReadState(notificationID: notification.id, isRead: false, readAt: nil)
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    func markAllRead() async {
        guard let userID = currentUserID, unreadCount > 0 else { return }

        do {
            try await repository.markAllNotificationsRead(userID: userID)
            notifications = notifications.map { notification in
                guard notification.countsAsUnread else { return notification }
                return notification.updatingReadState(isRead: true, readAt: notification.readAt ?? Date())
            }
            unreadCount = 0
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    func archive(_ notification: AppNotification) async {
        guard let userID = currentUserID else { return }

        do {
            try await repository.archiveNotification(userID: userID, notificationID: notification.id)
            applyArchiveState(notificationID: notification.id)
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    func delete(_ notification: AppNotification) async {
        guard let userID = currentUserID else { return }

        do {
            try await repository.deleteNotification(userID: userID, notificationID: notification.id)
            let wasUnread = notification.countsAsUnread
            notifications.removeAll { $0.id == notification.id }
            if wasUnread {
                unreadCount = max(0, unreadCount - 1)
            }
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    private func startListening(userID: String) {
        listener = repository.listenNotifications(userID: userID, limit: notificationLimit) { [weak self] notifications in
            guard let self else { return }
            self.notifications = notifications
            self.unreadCount = notifications.filter(\.countsAsUnread).count
            self.error = nil
        }
    }

    private func applyReadState(notificationID: String, isRead: Bool, readAt: Date?) {
        guard let index = notifications.firstIndex(where: { $0.id == notificationID }) else { return }
        let notification = notifications[index]
        let wasUnread = notification.countsAsUnread
        notifications[index] = notification.updatingReadState(isRead: isRead, readAt: readAt)
        let isUnread = notifications[index].countsAsUnread
        updateUnreadCount(wasUnread: wasUnread, isUnread: isUnread)
    }

    private func applyArchiveState(notificationID: String) {
        guard let index = notifications.firstIndex(where: { $0.id == notificationID }) else { return }
        let notification = notifications[index]
        let wasUnread = notification.countsAsUnread
        notifications[index] = notification.updatingArchiveState(archivedAt: Date())
        let isUnread = notifications[index].countsAsUnread
        updateUnreadCount(wasUnread: wasUnread, isUnread: isUnread)
    }

    private func updateUnreadCount(wasUnread: Bool, isUnread: Bool) {
        if wasUnread && !isUnread {
            unreadCount = max(0, unreadCount - 1)
        } else if !wasUnread && isUnread {
            unreadCount += 1
        }
    }
}
