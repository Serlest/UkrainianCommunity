import Foundation
import UIKit
import UserNotifications

#if canImport(FirebaseMessaging)
private import FirebaseMessaging
#endif

@MainActor
final class RemoteNotificationRegistrationService: NSObject {
    static let shared = RemoteNotificationRegistrationService()

    private var repository: NotificationPushTokenRepository = FirestoreNotificationPushTokenRepository()
    private var currentUserID: String?
    private var currentToken: String?
    private var lastSavedTokenKey: String?
    private var hasAPNSToken = false
    private var hasRequestedRemoteRegistration = false
    private var isRefreshingMessagingToken = false
    private var lastAuthorizationRequestUserID: String?
    private var messagingDelegateAdapter: AnyObject?

    private override init() {
        super.init()
        #if canImport(FirebaseMessaging)
        let adapter = FirebaseMessagingDelegateAdapter { [weak self] fcmToken in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.debugLog("FCM registration token callback received: \(fcmToken ?? "nil")")
                await self.saveToken(fcmToken)
            }
        }
        messagingDelegateAdapter = adapter
        Messaging.messaging().delegate = adapter
        #endif
    }

    func configure(repository: NotificationPushTokenRepository) {
        self.repository = repository
    }

    func configureUser(_ userID: String?) {
        if currentUserID != userID {
            lastAuthorizationRequestUserID = nil
        }
        currentUserID = userID
        guard userID != nil else {
            currentToken = nil
            lastSavedTokenKey = nil
            return
        }
        Task {
            await saveToken(currentToken)
            await registerIfAlreadyAuthorized()
        }
    }

    func configureUser(_ userID: String?, notificationsEnabled: Bool) {
        if currentUserID != userID {
            lastAuthorizationRequestUserID = nil
        }
        currentUserID = userID
        guard userID != nil else {
            currentToken = nil
            lastSavedTokenKey = nil
            return
        }

        Task {
            await saveToken(currentToken)
            await registerIfAuthorizedOrRequestIfNeeded(notificationsEnabled: notificationsEnabled)
        }
    }

    func requestAuthorizationAndRegister() async throws -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        debugLog("Notification authorization status before request: \(settings.authorizationStatus.debugDescription)")
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        debugLog("requestAuthorization result: granted=\(granted)")
        guard granted else { return false }

        registerForRemoteNotificationsIfNeeded()
        return true
    }

    func removeCurrentToken() async {
        guard let userID = currentUserID, let currentToken else { return }
        try? await repository.deleteCurrentDeviceToken(userID: userID, token: currentToken)
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

    private func registerIfAlreadyAuthorized() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        debugLog("Notification authorization status: \(settings.authorizationStatus.debugDescription)")
        guard settings.authorizationStatus.allowsRemoteRegistration else { return }

        registerForRemoteNotificationsIfNeeded()
    }

    private func registerIfAuthorizedOrRequestIfNeeded(notificationsEnabled: Bool) async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        debugLog("Notification authorization status: \(settings.authorizationStatus.debugDescription)")

        if settings.authorizationStatus.allowsRemoteRegistration {
            registerForRemoteNotificationsIfNeeded()
            return
        }

        guard notificationsEnabled,
              settings.authorizationStatus == .notDetermined,
              lastAuthorizationRequestUserID != currentUserID else { return }

        lastAuthorizationRequestUserID = currentUserID
        do {
            _ = try await requestAuthorizationAndRegister()
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
            debugLog("FCM token received: \(token)")
            await saveToken(token)
        } catch {
            debugLog("FCM token refresh failed: \(error)")
        }
        #else
        debugLog("FirebaseMessaging is not linked; remote push token upload is inactive.")
        #endif
    }

    private func saveToken(_ token: String?) async {
        guard let token = token?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else { return }

        currentToken = token

        guard let userID = currentUserID else { return }

        let tokenKey = "\(userID):\(token)"
        guard lastSavedTokenKey != tokenKey else {
            debugLog("FCM token already uploaded for user \(userID); skipping duplicate upload.")
            return
        }

        do {
            try await repository.saveCurrentDeviceToken(userID: userID, token: token)
            lastSavedTokenKey = tokenKey
            debugLog("FCM token uploaded for user \(userID)")
        } catch {
            debugLog("FCM token save failed: \(error)")
        }
    }

    private func registerForRemoteNotificationsIfNeeded() {
        guard !hasRequestedRemoteRegistration else { return }
        hasRequestedRemoteRegistration = true
        UIApplication.shared.registerForRemoteNotifications()
    }

    private func debugLog(_ message: String) {
        #if DEBUG
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
