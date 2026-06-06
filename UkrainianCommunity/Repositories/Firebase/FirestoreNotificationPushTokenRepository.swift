import CryptoKit
import FirebaseFirestore
import Foundation
import UIKit

struct FirestoreNotificationPushTokenRepository: NotificationPushTokenRepository {
    private let database = Firestore.firestore()

    func saveCurrentDeviceToken(userID: String, token: String) async throws {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { return }

        try await tokenDocument(userID: userID, token: trimmedToken).setData([
            "id": documentID(for: trimmedToken),
            "token": trimmedToken,
            "platform": "ios",
            "deviceName": UIDevice.current.name,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            "updatedAt": FieldValue.serverTimestamp(),
            "createdAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    func deleteCurrentDeviceToken(userID: String, token: String) async throws {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { return }
        try await tokenDocument(userID: userID, token: trimmedToken).delete()
    }

    private func tokenDocument(userID: String, token: String) -> DocumentReference {
        database
            .collection("users")
            .document(userID)
            .collection("notificationPushTokens")
            .document(documentID(for: token))
    }

    private func documentID(for token: String) -> String {
        let digest = SHA256.hash(data: Data(token.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
