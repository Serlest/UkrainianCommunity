import Foundation
import Combine
import FirebaseFunctions

@MainActor
final class AnnouncementCoordinator: ObservableObject {
    private var activeSnapshotRevision = 0
    private var refreshTask: Task<Void, Never>?
    @Published var items: [UserAnnouncement] = []
    @Published var active: UserAnnouncement?
    @Published var requestedFeedback: UserAnnouncement?
    @Published var error: String?
    @Published var isLoading = false
    @Published private(set) var isHistoryLoading = false
    @Published private(set) var historyCursor: String?
    @Published private(set) var pendingActions: Set<String> = []
    private var historyFailedMore = false
    private var historyItems: [UserAnnouncement] = []
    private var activeItems: [UserAnnouncement] = []
    private var historyGeneration = 0
    let repository: any AnnouncementRepository
    private let defaults: UserDefaults
    private var userID: String?
    private var identity = "unconfigured"
    private var generation = 0
    var sessionVersion: Int { generation }
    private var policy = AnnouncementPresentationPolicy()
    private var serverOffset = 0.0
    private var lastLoadedAt: Date?

    init(repository: any AnnouncementRepository, defaults: UserDefaults = .standard) {
        self.repository = repository; self.defaults = defaults
    }
    func configure(userID: String?, available: Bool) {
        let accountID: String?
        if available, let id = userID?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            accountID = id
        } else {
            accountID = nil
        }
        let next = accountID ?? "unavailable"
        guard next != identity else { return }
        refreshTask?.cancel(); refreshTask = nil
        generation += 1; historyGeneration += 1; historyItems = []; activeItems = []; historyCursor = nil; isHistoryLoading = false; historyFailedMore = false; identity = next; self.userID = accountID
        active = nil; requestedFeedback = nil; pendingActions = []; items = []; error = nil; isLoading = false; policy = AnnouncementPresentationPolicy(); lastLoadedAt = nil
    }
    func background() { policy.background(at: Date()); active = nil }
    func foreground() { policy.foreground(at: Date()) }
    func refresh() async {
        guard !Task.isCancelled else { return }
        if let refreshTask { await refreshTask.value; return }
        let version = generation
        let task = Task { await loadActiveFeed() }
        refreshTask = task
        await task.value
        if generation == version { refreshTask = nil }
    }
    private func loadActiveFeed() async {
        guard !isLoading, identity != "unconfigured", identity != "unavailable" else { return }
        let version = generation
        isLoading = true
        defer { if generation == version { isLoading = false } }
        do {
            try? await flushPending()
            guard version == generation, !Task.isCancelled else { return }
            var result: [UserAnnouncement] = [], cursor: String?
            repeat {
                let response = try await repository.call("getAnnouncements", AnnouncementRequest(feedMode: "active", cursor: cursor))
                guard version == generation, !Task.isCancelled else { return }
                result += response.items ?? []; cursor = response.cursor
                if let now = response.serverNow { serverOffset = now - Date().timeIntervalSince1970 * 1000 }
            } while cursor != nil
            activeItems = result.filter { $0.schemaVersion == 1 }
            activeSnapshotRevision += 1
            let currentIDs = Set(activeItems.map(\.id))
            historyItems.removeAll { $0.active(at: now) && !currentIDs.contains($0.id) }
            for item in activeItems { if let index = historyItems.firstIndex(where: { $0.id == item.id }) { historyItems[index] = item } }
            mergeItems()
            if let active, !items.contains(where: { $0.id == active.id && $0.active(at: now) && $0.acknowledgedAt == nil }) { self.active = nil }
            error = nil; lastLoadedAt = Date()
        } catch {
            guard generation == version, !Task.isCancelled else { return }
            self.error = AnnouncementStrings.error
            active = nil; lastLoadedAt = nil
        }
    }
    func loadHistory(reset: Bool = false) async {
        guard identity != "unconfigured", identity != "unavailable" else { return }
        guard !isHistoryLoading else { return }
        if !reset && historyCursor == nil { return }
        historyGeneration += 1; let requestID = historyGeneration; let accountVersion = generation
        isHistoryLoading = true
        defer { if historyGeneration == requestID { isHistoryLoading = false } }
        do {
            let cursor = reset ? nil : historyCursor
            var activeRevision = activeSnapshotRevision
            var response = try await repository.call("getAnnouncements", AnnouncementRequest(feedMode: "history", cursor: cursor))
            if activeRevision != activeSnapshotRevision {
                guard generation == accountVersion, historyGeneration == requestID, !Task.isCancelled else { return }
                activeRevision = activeSnapshotRevision
                response = try await repository.call("getAnnouncements", AnnouncementRequest(feedMode: "history", cursor: cursor))
                guard activeRevision == activeSnapshotRevision else { throw AnnouncementCommandError.missingResponse }
            }
            guard generation == accountVersion, historyGeneration == requestID, !Task.isCancelled else { return }
            if let serverNow = response.serverNow { serverOffset = serverNow - Date().timeIntervalSince1970 * 1000 }
            let page = response.items ?? []
            let updates = Dictionary(page.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            activeItems = activeItems.compactMap { current in
                guard let updated = updates[current.id] else { return current }
                return updated.active(at: now) ? updated : nil
            }
            historyItems = (reset ? [] : historyItems).filter { old in !page.contains { $0.id == old.id } } + page
            historyCursor = response.cursor; error = nil; historyFailedMore = false
            mergeItems()
        } catch {
            guard generation == accountVersion, historyGeneration == requestID, !Task.isCancelled else { return }
            historyFailedMore = !reset
            self.error = AnnouncementErrorPresentation.message(error)
        }
    }
    func retryHistory() async { await loadHistory(reset: !historyFailedMore) }
    private func mergeItems() {
        // An explicit history read may contain the latest cancellation/receipt.
        var byID = Dictionary(activeItems.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for item in historyItems { byID[item.id] = item }
        items = byID.values.filter { $0.schemaVersion == 1 && ($0.status != "cancelled" || $0.presentedAt != nil || stored($0.id, "presented")) }
            .sorted { $0.startsAt == $1.startsAt ? $0.id < $1.id : $0.startsAt > $1.startsAt }
    }
    func refreshIfStale() async {
        guard lastLoadedAt.map({ Date().timeIntervalSince($0) < 60 }) != true else { return }
        await refresh()
    }
    var now: Double { Date().timeIntervalSince1970 * 1000 + serverOffset }
    func presentIfPossible(_ ready: Bool) {
        guard ready, active == nil, policy.seenThisSession.isEmpty, let lastLoadedAt, Date().timeIntervalSince(lastLoadedAt) < 120 else { return }
        active = activeItems.first {
            policy.eligible($0, now: now, locallyPresented: stored($0.id, "presented"), locallyAcknowledged: stored($0.id, "acknowledged"))
        }
    }
    func didPresent(_ item: UserAnnouncement) async {
        guard !Task.isCancelled else { return }
        policy.shown(item.id)
        await mark(item, event: "presented")
    }
    func close(_ item: UserAnnouncement, acknowledge: Bool) async {
        active = nil
        if acknowledge { await mark(item, event: "acknowledged") }
    }
    @discardableResult func mark(_ item: UserAnnouncement, event: String) async -> Bool {
        guard let userID, identity == userID, !Task.isCancelled else { return false }
        let action = item.id + "::" + event, version = generation
        guard pendingActions.insert(action).inserted else { return false }
        defer { if generation == version { pendingActions.remove(action) } }
        let key = receiptKey(item.id, event)
        defaults.set(true, forKey: key)
        defaults.set(true, forKey: key + ".pending")
        do {
            _ = try await repository.call("acknowledgeAnnouncement", AnnouncementRequest(id: item.id, event: event))
            guard generation == version else { return false }
            defaults.removeObject(forKey: key + ".pending")
        } catch { if generation == version { self.error = AnnouncementStrings.syncPending } }
        return generation == version && identity == userID
    }
    func isProcessing(_ item: UserAnnouncement) -> Bool {
        pendingActions.contains { $0.hasPrefix(item.id + "::") }
    }
    private func flushPending() async throws {
        guard let userID, identity == userID else { return }
        let prefix = "announcements.receipt.\(identity)."
        let version = generation
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) && key.hasSuffix(".pending") {
            let suffix = String(key.dropFirst(prefix.count).dropLast(".pending".count))
            guard let separator = suffix.lastIndex(of: ".") else { continue }
            let id = String(suffix[..<separator]), event = String(suffix[suffix.index(after: separator)...])
            do {
                _ = try await repository.call("acknowledgeAnnouncement", AnnouncementRequest(id: id, event: event))
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
