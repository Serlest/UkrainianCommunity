import Foundation
import Combine
import FirebaseFunctions

@MainActor
final class AnnouncementCoordinator: ObservableObject {
    @Published var items: [UserAnnouncement] = []
    @Published var active: UserAnnouncement?
    @Published var requestedFeedback: UserAnnouncement?
    @Published var error: String?
    @Published var isLoading = false
    let repository: any AnnouncementRepository
    private let defaults: UserDefaults
    private var userID: String?
    private var identity = "unconfigured"
    private var generation = 0
    private var policy = AnnouncementPresentationPolicy()
    private var serverOffset = 0.0
    private var lastLoadedAt: Date?

    init(repository: any AnnouncementRepository, defaults: UserDefaults = .standard) {
        self.repository = repository; self.defaults = defaults
    }
    func configure(userID: String?, available: Bool) {
        let next = available ? userID ?? "guest" : "unavailable"
        guard next != identity else { return }
        generation += 1; identity = next; self.userID = userID
        active = nil; items = []; error = nil; isLoading = false; policy = AnnouncementPresentationPolicy(); lastLoadedAt = nil
    }
    func background() { policy.background(at: Date()); active = nil }
    func foreground() { policy.foreground(at: Date()) }
    func refresh() async {
        guard !isLoading, identity != "unconfigured", identity != "unavailable" else { return }
        let version = generation
        isLoading = true
        defer { if generation == version { isLoading = false } }
        do {
            try? await flushPending()
            var result: [UserAnnouncement] = [], cursor: String?
            repeat {
                let response = try await repository.call("getAnnouncements", AnnouncementRequest(cursor: cursor))
                guard version == generation, !Task.isCancelled else { return }
                result += response.items ?? []; cursor = response.cursor
                if let now = response.serverNow { serverOffset = now - Date().timeIntervalSince1970 * 1000 }
            } while cursor != nil
            items = result.filter { $0.schemaVersion == 1 && ($0.status != "cancelled" || $0.presentedAt != nil || stored($0.id, "presented")) }.sorted { $0.startsAt > $1.startsAt }
            if let active, !items.contains(where: { $0.id == active.id && $0.active(at: now) && $0.acknowledgedAt == nil }) { self.active = nil }
            error = nil; lastLoadedAt = Date()
        } catch {
            guard generation == version, !Task.isCancelled else { return }
            self.error = AnnouncementStrings.error
            active = nil; lastLoadedAt = nil
        }
    }
    var now: Double { Date().timeIntervalSince1970 * 1000 + serverOffset }
    func presentIfPossible(_ ready: Bool) {
        guard ready, active == nil, policy.seenThisSession.isEmpty, let lastLoadedAt, Date().timeIntervalSince(lastLoadedAt) < 120 else { return }
        active = items.first {
            policy.eligible($0, now: now, locallyPresented: stored($0.id, "presented"), locallyAcknowledged: stored($0.id, "acknowledged"))
        }
    }
    func didPresent(_ item: UserAnnouncement) async {
        policy.shown(item.id)
        await mark(item, event: "presented")
    }
    func close(_ item: UserAnnouncement, acknowledge: Bool) async {
        active = nil
        if acknowledge { await mark(item, event: "acknowledged") }
    }
    func mark(_ item: UserAnnouncement, event: String) async {
        let key = receiptKey(item.id, event)
        defaults.set(true, forKey: key)
        defaults.set(true, forKey: key + ".pending")
        let version = generation
        do {
            _ = try await repository.call("acknowledgeAnnouncement", AnnouncementRequest(id: item.id, event: event, secret: userID == nil ? AnnouncementPushBridge.shared.installationSecret : nil))
            guard generation == version else { return }
            defaults.removeObject(forKey: key + ".pending")
        } catch { if generation == version { self.error = AnnouncementStrings.syncPending } }
    }
    private func flushPending() async throws {
        let prefix = "announcements.receipt.\(identity)."
        let version = generation
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) && key.hasSuffix(".pending") {
            let suffix = String(key.dropFirst(prefix.count).dropLast(".pending".count))
            guard let separator = suffix.lastIndex(of: ".") else { continue }
            let id = String(suffix[..<separator]), event = String(suffix[suffix.index(after: separator)...])
            do {
                _ = try await repository.call("acknowledgeAnnouncement", AnnouncementRequest(id: id, event: event, secret: userID == nil ? AnnouncementPushBridge.shared.installationSecret : nil))
            } catch {
                let code = FunctionsErrorCode(rawValue: (error as NSError).code)
                if ![.permissionDenied, .notFound].contains(code) { throw error }
            }
            guard version == generation else { return }
            defaults.removeObject(forKey: key)
        }
    }
    func isAcknowledged(_ item: UserAnnouncement) -> Bool { item.acknowledgedAt != nil || stored(item.id, "acknowledged") }
    private func receiptKey(_ id: String, _ event: String) -> String { "announcements.receipt.\(identity).\(id).\(event)" }
    private func stored(_ id: String, _ event: String) -> Bool { defaults.bool(forKey: receiptKey(id, event)) }
}
