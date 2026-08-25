import CryptoKit
import FirebaseFirestore
import FirebaseFunctions
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
        do {
            _ = try await functionsClient.deleteNotificationPushRegistration(
                PushRegistrationDeletionFunctionRequest(
                    userId: userID,
                    identifier: normalizedRegistration.identifier,
                    registrationType: normalizedRegistration.kind.rawValue
                )
            )
        } catch {
            guard Self.shouldUseFirestoreFallback(error) else { throw error }

            // App Check can reject a legitimate Debug/Simulator callable even
            // while Firebase Auth and the user's Firestore session are valid.
            // Removing the exact current-device document is allowed only to its
            // authenticated owner and prevents that diagnostics configuration
            // from trapping the user inside the account.
            try await registrationDocument(
                userID: userID,
                registration: normalizedRegistration
            ).delete()
        }
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

    static func isUnauthenticatedFunctionsError(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == FunctionsErrorDomain
            && FunctionsErrorCode(rawValue: error.code) == .unauthenticated
    }

    static func shouldUseFirestoreFallback(_ error: Error) -> Bool {
        if isUnauthenticatedFunctionsError(error) {
            return true
        }

        let error = error as NSError
        if error.domain == NSURLErrorDomain {
            return true
        }
        guard error.domain == FunctionsErrorDomain,
              let code = FunctionsErrorCode(rawValue: error.code) else {
            return false
        }
        return code == .unavailable || code == .deadlineExceeded
    }
}
