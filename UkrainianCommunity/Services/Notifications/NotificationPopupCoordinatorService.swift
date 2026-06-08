import Foundation
import Combine

@MainActor
final class NotificationPopupCoordinatorService: ObservableObject {
    @Published private(set) var activeNotification: AppNotification?
    @Published private(set) var errorMessage: String?

    private let repository: NotificationInboxRepository
    private var currentUserID: String?
    private var queuedNotifications: [AppNotification] = []
    private var hasReceivedInitialSnapshot = false
    private var seenNotificationIDs: Set<String> = []

    init(repository: NotificationInboxRepository) {
        self.repository = repository
    }

    func configure(userID: String?) {
        guard currentUserID != userID else { return }

        currentUserID = userID
        queuedNotifications = []
        activeNotification = nil
        errorMessage = nil
        hasReceivedInitialSnapshot = false
        seenNotificationIDs = []
    }

    func receiveInboxSnapshot(_ notifications: [AppNotification], userID: String) {
        guard currentUserID == userID else { return }

        let notificationIDs = Set(notifications.map(\.id))
        guard hasReceivedInitialSnapshot else {
            seenNotificationIDs = notificationIDs
            hasReceivedInitialSnapshot = true
            return
        }

        reconcileActiveNotification(with: notifications)
        reconcileQueuedNotifications(with: notifications)

        let newPopupCandidates = notifications
            .filter { !seenNotificationIDs.contains($0.id) }
            .filter(isEligibleForPopup)

        queuedNotifications.append(contentsOf: newPopupCandidates)
        queuedNotifications.sort { $0.createdAt < $1.createdAt }
        seenNotificationIDs.formUnion(notificationIDs)

        presentNextIfPossible()
    }

    func dismissActiveNotification(markRead: Bool) async {
        guard let userID = currentUserID, let notification = activeNotification else { return }
        activeNotification = nil
        queuedNotifications.removeAll { $0.id == notification.id }

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

    private func presentNextIfPossible() {
        guard activeNotification == nil else { return }
        activeNotification = queuedNotifications.isEmpty ? nil : queuedNotifications.removeFirst()
    }

    private func reconcileActiveNotification(with notifications: [AppNotification]) {
        guard let activeNotification else { return }
        guard let updatedNotification = notifications.first(where: { $0.id == activeNotification.id }),
              isEligibleForPopup(updatedNotification) else {
            self.activeNotification = nil
            return
        }

        self.activeNotification = updatedNotification
    }

    private func reconcileQueuedNotifications(with notifications: [AppNotification]) {
        let notificationsByID = Dictionary(uniqueKeysWithValues: notifications.map { ($0.id, $0) })
        queuedNotifications = queuedNotifications.compactMap { queuedNotification in
            guard let updatedNotification = notificationsByID[queuedNotification.id],
                  isEligibleForPopup(updatedNotification) else { return nil }
            return updatedNotification
        }
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
