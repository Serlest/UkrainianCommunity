import Foundation
import Combine

@MainActor
final class NotificationInboxViewModel: ObservableObject {
    @Published private(set) var notifications: [AppNotification] = []
    @Published private(set) var unreadCount = 0
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?

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

        guard let userID else { return }
        startListening(userID: userID)
        await refresh()
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
            applyReadState(notificationID: notification.id)
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
                AppNotification(
                    id: notification.id,
                    recipientUserId: notification.recipientUserId,
                    type: notification.type,
                    sourceType: notification.sourceType,
                    sourceId: notification.sourceId,
                    actorUserId: notification.actorUserId,
                    actorDisplayName: notification.actorDisplayName,
                    payload: notification.payload,
                    isRead: true,
                    readAt: notification.readAt ?? Date(),
                    createdAt: notification.createdAt
                )
            }
            unreadCount = 0
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
            self.unreadCount = notifications.filter { !$0.isRead }.count
            self.error = nil
        }
    }

    private func applyReadState(notificationID: String) {
        guard let index = notifications.firstIndex(where: { $0.id == notificationID }) else { return }
        let notification = notifications[index]
        guard !notification.isRead else { return }

        notifications[index] = AppNotification(
            id: notification.id,
            recipientUserId: notification.recipientUserId,
            type: notification.type,
            sourceType: notification.sourceType,
            sourceId: notification.sourceId,
            actorUserId: notification.actorUserId,
            actorDisplayName: notification.actorDisplayName,
            payload: notification.payload,
            isRead: true,
            readAt: notification.readAt ?? Date(),
            createdAt: notification.createdAt
        )
        unreadCount = max(0, unreadCount - 1)
    }
}
