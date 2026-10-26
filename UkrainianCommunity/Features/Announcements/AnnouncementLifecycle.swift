import SwiftUI
import UIKit
import Combine
import UserNotifications
import FirebaseCore
import FirebaseAuth
private import FirebaseInstallations

@MainActor
final class AnnouncementPushBridge: ObservableObject {
    static let shared = AnnouncementPushBridge()
    @Published private(set) var deliveryRevision = 0
    private var intent = AnnouncementPushIntent()
    private var repository: (any AnnouncementRepository)?
    private var identity: String?
    private var generation = 0
    private var isSigningOut = false
    var canPresentNotification: Bool {
        identity != nil && identity != "unavailable" && !isSigningOut
    }
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
            intent.configure(userID: identity == "unavailable" ? nil : identity)
            _ = try? await repository.call("registerAnnouncementDevice", AnnouncementRequest(operation: "disable", secret: installationSecret))
        }
        guard identity != "unavailable" else { return }
        await registerIfAllowed()
    }
    func prepareForSignOut() async {
        isSigningOut = true
        generation += 1
        guard let repository else { return }
        _ = try? await repository.call("registerAnnouncementDevice", AnnouncementRequest(operation: "disable", secret: installationSecret))
    }
    func completeSignOut() {
        generation += 1
        isSigningOut = false
        identity = "unavailable"
        intent.clear()
        repository = nil
    }
    func resumeAfterFailedSignOut() async {
        isSigningOut = false
        await registerIfAllowed()
    }
    func registerIfAllowed() async {
        guard let repository, FirebaseApp.app() != nil, identity != "unavailable", !isSigningOut else { return }
        let version = generation
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard version == generation else { return }
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else {
            _ = try? await repository.call("registerAnnouncementDevice", AnnouncementRequest(operation: "disable", secret: installationSecret)); return
        }
        UIApplication.shared.registerForRemoteNotifications()
    }
    func registrationReady() async {
        guard let repository, FirebaseApp.app() != nil, identity != "unavailable", !isSigningOut else { return }
        let version = generation
        do {
            let fid = try await Installations.installations().installationID()
            guard generation == version else { return }
            _ = try await repository.call("registerAnnouncementDevice", AnnouncementRequest(language: AppLanguage.stored.rawValue, secret: installationSecret, fid: fid))
        } catch { /* Registration is retried on the next foreground activation. No message is lost from the in-app feed. */ }
    }
    func receive(_ data: [AnyHashable: Any], userInitiated: Bool = false) async -> Bool {
        await receive(id: data["announcementId"] as? String, challenge: data["announcementChallenge"] as? String, userInitiated: userInitiated)
    }
    func receive(id: String?, challenge: String?, userInitiated: Bool = false) async -> Bool {
        if isSigningOut { return id != nil || challenge != nil }
        if let challenge {
            if let repository { _ = try? await repository.call("registerAnnouncementDevice", AnnouncementRequest(operation: "confirm", secret: installationSecret, challenge: challenge)) }
            return true
        }
        if let id {
            let authenticatedID = FirebaseApp.app() == nil ? nil : Auth.auth().currentUser?.uid
            intent.receive(id: id, userID: authenticatedID, userInitiated: userInitiated)
            deliveryRevision += 1
            return true
        }
        return false
    }
    func consumeIntent(userID: String) -> String? { intent.consume(userID: userID) }
}

struct AnnouncementLifecycle: ViewModifier {
    @ObservedObject var coordinator: AnnouncementCoordinator
    let userID: String?
    let available: Bool
    let ready: Bool
    let feedback: (UserAnnouncement) -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasEnteredBackground = false
    @ObservedObject private var push = AnnouncementPushBridge.shared
    private var identity: String {
        guard available, let userID else { return "unavailable" }
        return userID
    }
    func body(content: Content) -> some View {
        content
            .onChange(of: identity, initial: true) { _, _ in coordinator.configure(userID: userID, available: available) }
            .task(id: identity) {
                coordinator.configure(userID: userID, available: available)
                await push.configure(repository: coordinator.repository, identity: identity)
                await reload()
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                if hasEnteredBackground {
                    hasEnteredBackground = false
                    coordinator.foreground()
                    await push.registerIfAllowed()
                    await coordinator.refreshIfStale()
                }
                present()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(60)) } catch { return }
                    await reloadIfStale()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    hasEnteredBackground = true
                    coordinator.background()
                }
            }
            .onChange(of: ready) { _, value in
                if value { Task { await reload() } } else { coordinator.active = nil }
            }
            .onChange(of: push.deliveryRevision) { _, _ in Task { await reload() } }
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
        present()
    }
    private func reloadIfStale() async {
        await coordinator.refreshIfStale()
        guard !Task.isCancelled else { return }
        present()
    }
    private func present() {
        guard ready, scenePhase == .active, canPresentModal else { return }
        if let userID, let id = push.consumeIntent(userID: userID),
           let item = coordinator.items.first(where: { $0.id == id && $0.active(at: coordinator.now) }) {
            coordinator.active = item; return
        }
        coordinator.presentIfPossible(true)
    }
    private var canPresentModal: Bool {
        !UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            .filter(\.isKeyWindow).contains { $0.rootViewController?.presentedViewController != nil }
    }
}
