import Foundation
import Combine

@MainActor
final class NotificationPopupCoordinatorService: ObservableObject {
    @Published private(set) var activeNotification: AppNotification?
    @Published private(set) var errorMessage: String?

    private let repository: NotificationInboxRepository
    private var listener: AppRealtimeListener?
    private var currentUserID: String?
    private var queuedNotifications: [AppNotification] = []
    private let notificationLimit = 50

    init(repository: NotificationInboxRepository) {
        self.repository = repository
    }

    func configure(userID: String?) {
        guard currentUserID != userID else { return }

        listener?.cancel()
        listener = nil
        currentUserID = userID
        queuedNotifications = []
        activeNotification = nil
        errorMessage = nil

        guard let userID else { return }
        listener = repository.listenNotifications(userID: userID, limit: notificationLimit) { [weak self] notifications in
            self?.receive(notifications)
        }
    }

    func dismissActiveNotification(markRead: Bool) async {
        guard let userID = currentUserID, let notification = activeNotification else { return }
        activeNotification = nil

        do {
            try await repository.markNotificationPopupPresented(userID: userID, notificationID: notification.id)
            if markRead {
                try await repository.markNotificationRead(userID: userID, notificationID: notification.id)
            }
            errorMessage = nil
        } catch {
            errorMessage = AppStrings.NotificationPopup.updateFailed
        }

        presentNextIfPossible()
    }

    private func receive(_ notifications: [AppNotification]) {
        queuedNotifications = notifications
            .filter(isEligibleForPopup)
            .sorted { $0.createdAt < $1.createdAt }

        presentNextIfPossible()
    }

    private func presentNextIfPossible() {
        guard activeNotification == nil else { return }
        activeNotification = queuedNotifications.first
    }

    private func isEligibleForPopup(_ notification: AppNotification) -> Bool {
        notification.requiresPopup
            && notification.popupPresentedAt == nil
            && notification.deletedAt == nil
            && notification.archivedAt == nil
            && notification.type != .accountStatusChanged
            && notification.type != .legalDocumentsUpdated
            && notification.severity == .critical
            && !isExpired(notification)
    }

    private func isExpired(_ notification: AppNotification) -> Bool {
        guard let expiresAt = notification.expiresAt else { return false }
        return expiresAt <= Date()
    }
}
