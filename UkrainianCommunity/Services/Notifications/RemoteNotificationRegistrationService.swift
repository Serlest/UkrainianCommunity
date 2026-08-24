import Foundation
import UIKit
import UserNotifications

#if canImport(FirebaseMessaging)
private import FirebaseMessaging
#endif

@MainActor
final class RemoteNotificationRegistrationService: NSObject {
    static let shared = RemoteNotificationRegistrationService()
    private static let isDebugLoggingEnabled = false

    private let tokenOwnership = NotificationPushTokenOwnershipCoordinator(
        repository: FirestoreNotificationPushTokenRepository()
    )
    private var hasAPNSToken = false
    private var hasRequestedRemoteRegistration = false
    private var isRefreshingMessagingToken = false
    private var lastAuthorizationRequestUserID: String?
    private var messagingDelegateAdapter: AnyObject?
    private var userConfigurationGeneration = 0

    private override init() {
        super.init()
        #if canImport(FirebaseMessaging)
        let adapter = FirebaseMessagingDelegateAdapter { [weak self] fcmToken in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.debugLog(fcmToken == nil ? "FCM registration token callback received without a token." : "FCM registration token callback received.")
                await self.tokenOwnership.receiveToken(fcmToken)
            }
        }
        messagingDelegateAdapter = adapter
        Messaging.messaging().delegate = adapter
        #endif
    }

    func configure(repository: NotificationPushTokenRepository) {
        tokenOwnership.configure(repository: repository)
    }

    func configureUser(_ userID: String?) {
        userConfigurationGeneration &+= 1
        if tokenOwnership.currentUserID != userID {
            lastAuthorizationRequestUserID = nil
        }
        tokenOwnership.configureUser(userID, notificationsEnabled: false)
    }

    func configureUser(_ userID: String?, notificationsEnabled: Bool) {
        userConfigurationGeneration &+= 1
        let generation = userConfigurationGeneration
        if tokenOwnership.currentUserID != userID {
            lastAuthorizationRequestUserID = nil
        }
        tokenOwnership.configureUser(userID, notificationsEnabled: notificationsEnabled)
        guard let userID else { return }

        Task { [weak self] in
            guard let self,
                  self.isCurrentUserConfiguration(generation: generation, userID: userID) else { return }
            if notificationsEnabled {
                await self.tokenOwnership.saveCachedTokenIfNeeded()
            } else {
                await self.tokenOwnership.removeCurrentToken()
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
        let userID = tokenOwnership.currentUserID
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
        tokenOwnership.setNotificationsEnabled(granted)
        guard granted else { return false }

        registerForRemoteNotificationsIfNeeded()
        return true
    }

    func removeCurrentToken() async {
        userConfigurationGeneration &+= 1
        await tokenOwnership.removeCurrentToken()
    }

    func prepareForSignOut() async throws {
        userConfigurationGeneration &+= 1
        try await tokenOwnership.prepareForSignOut()
    }

    func completeSignOut() {
        userConfigurationGeneration &+= 1
        lastAuthorizationRequestUserID = nil
        tokenOwnership.completeSignOut()
    }

    func resumeAfterFailedSignOut() async {
        await tokenOwnership.resumeAfterFailedSignOut()
    }

    func didRegisterForRemoteNotifications(deviceToken: Data) {
        debugLog("didRegisterForRemoteNotifications received APNs token with \(deviceToken.count) bytes")
        #if canImport(FirebaseMessaging)
        hasAPNSToken = true
        Messaging.messaging().apnsToken = deviceToken
        Task {
            await refreshMessagingTokenIfAvailable()
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

    private func refreshMessagingTokenIfAvailable() async {
        #if canImport(FirebaseMessaging)
        guard hasAPNSToken else {
            debugLog("Skipping FCM token refresh until APNs token is available.")
            return
        }
        guard !isRefreshingMessagingToken else { return }
        isRefreshingMessagingToken = true
        defer { isRefreshingMessagingToken = false }

        do {
            let token = try await Messaging.messaging().token()
            debugLog("FCM token received.")
            await tokenOwnership.receiveToken(token)
        } catch {
            debugLog("FCM token refresh failed: \(error)")
        }
        #else
        debugLog("FirebaseMessaging is not linked; remote push token upload is inactive.")
        #endif
    }

    private func registerForRemoteNotificationsIfNeeded() {
        guard !hasRequestedRemoteRegistration else { return }
        hasRequestedRemoteRegistration = true
        UIApplication.shared.registerForRemoteNotifications()
    }

    private func isCurrentUserConfiguration(generation: Int, userID: String?) -> Bool {
        userConfigurationGeneration == generation && tokenOwnership.currentUserID == userID
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
    private let onTokenReceived: @Sendable (String?) -> Void

    init(onTokenReceived: @escaping @Sendable (String?) -> Void) {
        self.onTokenReceived = onTokenReceived
    }

    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        onTokenReceived(fcmToken)
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
