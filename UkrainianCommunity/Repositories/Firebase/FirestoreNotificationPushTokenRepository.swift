import CryptoKit
import FirebaseFirestore
import Foundation
import UIKit

struct FirestoreNotificationPushTokenRepository: NotificationPushTokenRepository {
    private let database: Firestore
    private let functionsClient: CloudFunctionsClient

    init(
        database: Firestore = .firestore(),
        functionsClient: CloudFunctionsClient = .shared
    ) {
        self.database = database
        self.functionsClient = functionsClient
    }

    func saveCurrentDeviceRegistration(
        userID: String,
        registration: NotificationPushRegistration
    ) async throws {
        let identifier = registration.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty else { return }
        let normalizedRegistration = NotificationPushRegistration(
            identifier: identifier,
            kind: registration.kind
        )

        try await registrationDocument(
            userID: userID,
            registration: normalizedRegistration
        ).setData([
            "id": Self.documentID(for: normalizedRegistration),
            // Keep the historical field name while old app versions are supported.
            // `registrationType` tells Cloud Functions whether this value is a FID
            // or a legacy FCM registration token.
            "token": identifier,
            "registrationType": registration.kind.rawValue,
            "platform": "ios",
            "deviceName": UIDevice.current.name,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            "updatedAt": FieldValue.serverTimestamp(),
            "createdAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    func deleteCurrentDeviceRegistration(
        userID: String,
        registration: NotificationPushRegistration
    ) async throws {
        let identifier = registration.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty else { return }
        let normalizedRegistration = NotificationPushRegistration(
            identifier: identifier,
            kind: registration.kind
        )
        _ = try await functionsClient.deleteNotificationPushRegistration(
            PushRegistrationDeletionFunctionRequest(
                userId: userID,
                identifier: normalizedRegistration.identifier,
                registrationType: normalizedRegistration.kind.rawValue
            )
        )
    }

    private func registrationDocument(
        userID: String,
        registration: NotificationPushRegistration
    ) -> DocumentReference {
        database
            .collection("users")
            .document(userID)
            .collection("notificationPushTokens")
            .document(Self.documentID(for: registration))
    }

    static func documentID(for registration: NotificationPushRegistration) -> String {
        // Preserve the historical token path for old-client interoperability,
        // while keeping a FID with the same text in a separate key space.
        let identity = switch registration.kind {
        case .legacyFCMToken:
            registration.identifier
        case .firebaseInstallationID:
            "fid:\(registration.identifier)"
        }
        let digest = SHA256.hash(data: Data(identity.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
