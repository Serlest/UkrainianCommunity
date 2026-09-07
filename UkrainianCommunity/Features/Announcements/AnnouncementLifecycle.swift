import SwiftUI
import UIKit
import Combine
import UserNotifications
import FirebaseCore
private import FirebaseInstallations

@MainActor
final class AnnouncementPushBridge: ObservableObject {
    static let shared = AnnouncementPushBridge()
    @Published var pendingID: String?
    private var repository: (any AnnouncementRepository)?
    private var identity: String?
    private var generation = 0
    var installationSecret: String {
        let key = "announcements.installationSecret"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let value = UUID().uuidString + UUID().uuidString
        UserDefaults.standard.set(value, forKey: key); return value
    }
    func configure(repository: any AnnouncementRepository, identity: String) async {
        guard repository is CloudAnnouncementRepository else { return }
        self.repository = repository
        if self.identity != identity {
            generation += 1
            self.identity = identity
            _ = try? await repository.call("registerAnnouncementDevice", AnnouncementRequest(operation: "disable", secret: installationSecret))
        }
        guard identity != "unavailable" else { return }
        await registerIfAllowed()
    }
    func registerIfAllowed() async {
        guard let repository, FirebaseApp.app() != nil, identity != "unavailable" else { return }
        let version = generation
        if identity == "guest" && !UserDefaults.standard.bool(forKey: "announcements.guestPushEnabled") {
            _ = try? await repository.call("registerAnnouncementDevice", AnnouncementRequest(operation: "disable", secret: installationSecret))
            return
        }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard version == generation else { return }
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else {
            _ = try? await repository.call("registerAnnouncementDevice", AnnouncementRequest(operation: "disable", secret: installationSecret)); return
        }
        UIApplication.shared.registerForRemoteNotifications()
    }
    func registrationReady() async {
        guard let repository, FirebaseApp.app() != nil, identity != "unavailable" else { return }
        let version = generation
        if identity == "guest" && !UserDefaults.standard.bool(forKey: "announcements.guestPushEnabled") { return }
        do {
            let fid = try await Installations.installations().installationID()
            guard generation == version else { return }
            _ = try await repository.call("registerAnnouncementDevice", AnnouncementRequest(language: AppLanguage.stored.rawValue, secret: installationSecret, fid: fid))
        } catch { /* Registration is retried on the next foreground activation. No message is lost from the in-app feed. */ }
    }
    func receive(_ data: [AnyHashable: Any]) async -> Bool {
        await receive(id: data["announcementId"] as? String, challenge: data["announcementChallenge"] as? String)
    }
    func receive(id: String?, challenge: String?) async -> Bool {
        if let challenge {
            if let repository { _ = try? await repository.call("registerAnnouncementDevice", AnnouncementRequest(operation: "confirm", secret: installationSecret, challenge: challenge)) }
            return true
        }
        if let id { pendingID = id; return true }
        return false
    }
    func disableGuestPush() async {
        UserDefaults.standard.set(false, forKey: "announcements.guestPushEnabled")
        if let repository { _ = try? await repository.call("registerAnnouncementDevice", AnnouncementRequest(operation: "disable", secret: installationSecret)) }
    }
    func requestPermission() async {
        UserDefaults.standard.set(true, forKey: "announcements.guestPushEnabled")
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        await registerIfAllowed()
    }
}

struct AnnouncementLifecycle: ViewModifier {
    @ObservedObject var coordinator: AnnouncementCoordinator
    let userID: String?
    let available: Bool
    let ready: Bool
    let feedback: (UserAnnouncement) -> Void
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var push = AnnouncementPushBridge.shared
    private var identity: String { available ? userID ?? "guest" : "unavailable" }
    func body(content: Content) -> some View {
        content
            .onChange(of: identity, initial: true) { _, _ in coordinator.configure(userID: userID, available: available) }
            .task(id: identity) {
                coordinator.configure(userID: userID, available: available)
                await push.configure(repository: coordinator.repository, identity: identity)
                await reload()
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { coordinator.background(); return }
                coordinator.foreground()
                await push.registerIfAllowed()
                while !Task.isCancelled {
                    await reload()
                    do { try await Task.sleep(for: .seconds(60)) } catch { return }
                }
            }
            .onChange(of: ready) { _, value in if value { present() } else { coordinator.active = nil } }
            .onChange(of: push.pendingID) { _, _ in Task { await reload() } }
            .sheet(item: $coordinator.active) { item in
                AnnouncementPopup(item: item, coordinator: coordinator) { item in
                    // Allow the modal dismissal to finish before routing to feedback/auth.
                    Task { try? await Task.sleep(for: .milliseconds(400)); feedback(item) }
                }
            }
    }
    private func reload() async {
        await coordinator.refresh()
        guard !Task.isCancelled else { return }
        if let id = push.pendingID, ready, canPresentModal {
            push.pendingID = nil
            if let item = coordinator.items.first(where: { $0.id == id && $0.active(at: coordinator.now) }) { coordinator.active = item; return }
        }
        present()
    }
    private func present() { coordinator.presentIfPossible(ready && scenePhase == .active && canPresentModal) }
    private var canPresentModal: Bool {
        !UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            .filter(\.isKeyWindow).contains { $0.rootViewController?.presentedViewController != nil }
    }
}
