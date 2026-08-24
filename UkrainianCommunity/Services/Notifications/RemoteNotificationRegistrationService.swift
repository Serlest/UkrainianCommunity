import Foundation
import UIKit
import UserNotifications

#if canImport(FirebaseMessaging)
private import FirebaseMessaging
#endif
#if canImport(FirebaseInstallations)
private import FirebaseInstallations
#endif

private enum RemoteNotificationRegistrationError: Error {
    case missingFirebaseInstallationID
}

@MainActor
final class RemoteNotificationRegistrationService: NSObject {
    static let shared = RemoteNotificationRegistrationService()
    private static let isDebugLoggingEnabled = false

    private let registrationOwnership = NotificationPushTokenOwnershipCoordinator(
        repository: FirestoreNotificationPushTokenRepository()
    )
    private var hasAPNSToken = false
    private var hasRequestedRemoteRegistration = false
    private var isRefreshingMessagingRegistration = false
    private var lastAuthorizationRequestUserID: String?
    private var messagingDelegateAdapter: AnyObject?
    private var userConfigurationGeneration = 0

    private override init() {
        super.init()
        #if canImport(FirebaseMessaging)
        let adapter = FirebaseMessagingDelegateAdapter { [weak self] installationID in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.debugLog(
                    installationID == nil
                        ? "FCM registration callback received without an installation ID."
                        : "FCM installation ID received."
                )
                await self.registrationOwnership.receiveRegistration(
                    installationID,
                    kind: .firebaseInstallationID
                )
            }
        }
        messagingDelegateAdapter = adapter
        Messaging.messaging().delegate = adapter
        #endif
    }

    func configure(repository: NotificationPushTokenRepository) {
        registrationOwnership.configure(repository: repository)
    }

    func configureUser(_ userID: String?) {
        userConfigurationGeneration &+= 1
        if registrationOwnership.currentUserID != userID {
            lastAuthorizationRequestUserID = nil
        }
        registrationOwnership.configureUser(userID, notificationsEnabled: false)
    }

    func configureUser(_ userID: String?, notificationsEnabled: Bool) {
        userConfigurationGeneration &+= 1
        let generation = userConfigurationGeneration
        if registrationOwnership.currentUserID != userID {
            lastAuthorizationRequestUserID = nil
        }
        registrationOwnership.configureUser(userID, notificationsEnabled: notificationsEnabled)
        guard let userID else { return }

        Task { [weak self] in
            guard let self,
                  self.isCurrentUserConfiguration(generation: generation, userID: userID) else { return }
            if notificationsEnabled {
                await self.registrationOwnership.saveCachedRegistrationIfNeeded()
            } else {
                await self.registrationOwnership.removeCurrentRegistration()
            }
            guard self.isCurrentUserConfiguration(generation: generation, userID: userID) else { return }
            await self.registerIfAuthorizedOrRequestIfNeeded(
                notificationsEnabled: notificationsEnabled,
                generation: generation,
                userID: userID
            )
        }
    }

    func requestAuthorizationAndRegister() async throws -> Bool {
        let generation = userConfigurationGeneration
        let userID = registrationOwnership.currentUserID
        return try await requestAuthorizationAndRegister(
            generation: generation,
            userID: userID
        )
    }

    private func requestAuthorizationAndRegister(
        generation: Int,
        userID: String?
    ) async throws -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard isCurrentUserConfiguration(generation: generation, userID: userID) else { return false }
        debugLog("Notification authorization status before request: \(settings.authorizationStatus.debugDescription)")
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        guard isCurrentUserConfiguration(generation: generation, userID: userID) else { return false }
        debugLog("requestAuthorization result: granted=\(granted)")
        registrationOwnership.setNotificationsEnabled(granted)
        guard granted else { return false }

        registerForRemoteNotificationsIfNeeded()
        return true
    }

    func removeCurrentRegistration() async {
        userConfigurationGeneration &+= 1
        await registrationOwnership.removeCurrentRegistration()
    }

    func prepareForSignOut() async throws {
        userConfigurationGeneration &+= 1
        try await registrationOwnership.prepareForSignOut { [weak self] in
            guard let self else { return nil }
            return try await self.currentFirebaseInstallationRegistration()
        }
    }

    func completeSignOut() {
        userConfigurationGeneration &+= 1
        lastAuthorizationRequestUserID = nil
        registrationOwnership.completeSignOut()
    }

    func resumeAfterFailedSignOut() async {
        await registrationOwnership.resumeAfterFailedSignOut()
    }

    func didRegisterForRemoteNotifications(deviceToken: Data) {
        debugLog("didRegisterForRemoteNotifications received APNs token with \(deviceToken.count) bytes")
        #if canImport(FirebaseMessaging)
        hasAPNSToken = true
        Messaging.messaging().apnsToken = deviceToken
        Task {
            await refreshMessagingRegistrationIfAvailable()
        }
        #endif
    }

    func didFailToRegisterForRemoteNotifications(_ error: Error) {
        debugLog("Remote notification registration failed: \(error)")
    }

    private func registerIfAuthorizedOrRequestIfNeeded(
        notificationsEnabled: Bool,
        generation: Int,
        userID: String
    ) async {
        guard notificationsEnabled,
              isCurrentUserConfiguration(generation: generation, userID: userID) else { return }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard isCurrentUserConfiguration(generation: generation, userID: userID) else { return }
        debugLog("Notification authorization status: \(settings.authorizationStatus.debugDescription)")

        if settings.authorizationStatus.allowsRemoteRegistration {
            registerForRemoteNotificationsIfNeeded()
            return
        }

        guard notificationsEnabled,
              settings.authorizationStatus == .notDetermined,
              lastAuthorizationRequestUserID != userID else { return }

        lastAuthorizationRequestUserID = userID
        do {
            _ = try await requestAuthorizationAndRegister(
                generation: generation,
                userID: userID
            )
        } catch {
            debugLog("requestAuthorization failed: \(error)")
        }
    }

    private func refreshMessagingRegistrationIfAvailable() async {
        #if canImport(FirebaseMessaging)
        guard hasAPNSToken else {
            debugLog("Skipping FCM registration until an APNs token is available.")
            return
        }
        guard !isRefreshingMessagingRegistration else { return }
        isRefreshingMessagingRegistration = true
        defer { isRefreshingMessagingRegistration = false }

        do {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                Messaging.messaging().register { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
            // Firebase delivers the FID through the Messaging delegate both for a
            // new registration and an already registered installation.
            debugLog("FCM registration request completed.")
        } catch {
            debugLog("FCM registration failed: \(error)")
        }
        #else
        debugLog("FirebaseMessaging is not linked; remote push token upload is inactive.")
        #endif
    }

    private func currentFirebaseInstallationRegistration() async throws -> NotificationPushRegistration? {
        #if canImport(FirebaseInstallations)
        let identifier = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<String, any Error>) in
            Installations.installations().installationID { identifier, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let identifier {
                    continuation.resume(returning: identifier)
                } else {
                    continuation.resume(
                        throwing: RemoteNotificationRegistrationError.missingFirebaseInstallationID
                    )
                }
            }
        }
        return NotificationPushRegistration(
            identifier: identifier,
            kind: .firebaseInstallationID
        )
        #else
        return nil
        #endif
    }

    private func registerForRemoteNotificationsIfNeeded() {
        guard !hasRequestedRemoteRegistration else { return }
        hasRequestedRemoteRegistration = true
        UIApplication.shared.registerForRemoteNotifications()
    }

    private func isCurrentUserConfiguration(generation: Int, userID: String?) -> Bool {
        userConfigurationGeneration == generation && registrationOwnership.currentUserID == userID
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        guard Self.isDebugLoggingEnabled else { return }
        print("[Notifications] \(message)")
        #endif
    }
}

#if canImport(FirebaseMessaging)
private final class FirebaseMessagingDelegateAdapter: NSObject, MessagingDelegate {
    private let onRegistrationReceived: @Sendable (String?) -> Void

    init(onRegistrationReceived: @escaping @Sendable (String?) -> Void) {
        self.onRegistrationReceived = onRegistrationReceived
    }

    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistration installationID: String?) {
        onRegistrationReceived(installationID)
    }
}
#endif

private extension UNAuthorizationStatus {
    var allowsRemoteRegistration: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            true
        case .notDetermined, .denied:
            false
        @unknown default:
            false
        }
    }

    var debugDescription: String {
        switch self {
        case .notDetermined:
            "notDetermined"
        case .denied:
            "denied"
        case .authorized:
            "authorized"
        case .provisional:
            "provisional"
        case .ephemeral:
            "ephemeral"
        @unknown default:
            "unknown(\(rawValue))"
        }
    }
}
