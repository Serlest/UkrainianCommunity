import Foundation
import FirebaseFirestore

struct FirestoreNotificationPreferencesRepository: NotificationPreferencesRepository {
    private let database = Firestore.firestore()

    func fetchNotificationPreferences(userID: String) async throws -> NotificationPreferences {
        let document = try await preferencesDocument(userID: userID).getDocument()
        guard document.exists, let data = document.data() else {
            return .default
        }

        return NotificationPreferences(
            notificationsEnabled: data["notificationsEnabled"] as? Bool ?? NotificationPreferences.default.notificationsEnabled,
            eventRemindersEnabled: data["eventRemindersEnabled"] as? Bool ?? NotificationPreferences.default.eventRemindersEnabled,
            reminderLeadMinutes: data["reminderLeadMinutes"] as? Int ?? NotificationPreferences.default.reminderLeadMinutes,
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue()
        )
    }

    func saveNotificationPreferences(_ preferences: NotificationPreferences, userID: String) async throws {
        try await preferencesDocument(userID: userID).setData([
            "notificationsEnabled": preferences.notificationsEnabled,
            "eventRemindersEnabled": preferences.eventRemindersEnabled,
            "reminderLeadMinutes": preferences.reminderLeadMinutes,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    private func preferencesDocument(userID: String) -> DocumentReference {
        database
            .collection("users")
            .document(userID)
            .collection("notificationPreferences")
            .document("settings")
    }
}
