import FirebaseAuth
import FirebaseCore
import FirebaseFunctions
import Foundation
import UIKit

/// Redacted, account-bound diagnostics survive a lost connection or process restart.
/// Bounded retention limits local storage; privileged operations remain subject to server checks.
@MainActor
final class SystemLogDeliveryQueue {
    static let shared = SystemLogDeliveryQueue()
    struct Envelope: Codable, Equatable {
        let id: String
        let occurredAt: Date
        let principalID: String
        let draft: SystemLogDraft
        var attempts: Int = 0
        var nextAttemptAt: Date = .distantPast
    }
    typealias Transport = (Envelope) async throws -> Void
    private(set) var pending: [Envelope]
    private let defaults: UserDefaults
    private let storageKey: String
    private let principal: () -> String?
    private let now: () -> Date
    private let transport: Transport
    private var isDelivering = false
    private var retryTask: Task<Void, Never>?
    private var authListener: AuthStateDidChangeListenerHandle?
    private var foregroundObserver: NSObjectProtocol?
    private let automaticallyDelivers: Bool

    init(defaults: UserDefaults = .standard, storageKey: String = "systemLog.outbox.v1",
         now: @escaping () -> Date = Date.init,
         principal: @escaping () -> String? = { FirebaseApp.app() == nil ? nil : Auth.auth().currentUser?.uid },
         automaticallyDelivers: Bool = true,
         transport: Transport? = nil) {
        self.defaults = defaults; self.storageKey = storageKey; self.now = now
        self.principal = principal; self.automaticallyDelivers = automaticallyDelivers
        self.transport = transport ?? { envelope in
            _ = try await FirestoreSystemLogRepository().createLog(from: envelope.draft, eventID: envelope.id, occurredAt: envelope.occurredAt)
        }
        pending = defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode([Envelope].self, from: $0) } ?? []
        prune(); persist()
        if automaticallyDelivers {
            if FirebaseApp.app() != nil {
                authListener = Auth.auth().addStateDidChangeListener { [weak self] _, _ in
                    Task { @MainActor in self?.resume() }
                }
            }
            foregroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.resume() }
            }
            resume()
        }
    }

    func enqueue(_ original: SystemLogDraft) throws {
        // Anonymous failures must never be attributed to a later signed-in user.
        guard let uid = original.actorUserId ?? principal(), !uid.isEmpty else { return }
        var draft = SystemLogRedactionPolicy.default.redactedDraft(from: original)
        draft.actorUserId = uid
        if draft.correlationId == nil { draft.correlationId = UUID().uuidString }
        if draft.category != .diagnostics {
            draft.metadata["occurredAt"] = ISO8601DateFormatter().string(from: now())
        }
        prune()
        // Preserve the newest bounded diagnostic evidence rather than growing without limit.
        if pending.count >= 200 { pending.removeFirst(pending.count - 199) }
        let occurredAt = Date(timeIntervalSince1970: (now().timeIntervalSince1970 * 1000).rounded() / 1000)
        pending.append(Envelope(id: UUID().uuidString, occurredAt: occurredAt, principalID: uid, draft: draft))
        try save()
        if automaticallyDelivers { resume() }
    }

    func resume() {
        retryTask?.cancel()
        retryTask = Task { [weak self] in await self?.flush() }
    }

    func flush() async {
        guard !isDelivering else { return }
        isDelivering = true
        defer { isDelivering = false; scheduleRetry() }
        prune(); persist()
        while !Task.isCancelled, let uid = principal(),
              let index = pending.firstIndex(where: { $0.principalID == uid && $0.nextAttemptAt <= now() }) {
            let envelope = pending[index]
            do {
                // The server also fences the principal; no callback can reassign the actor.
                guard principal() == envelope.principalID else { break }
                try await transport(envelope)
                pending.removeAll { $0.id == envelope.id }
            } catch {
                guard let current = pending.firstIndex(where: { $0.id == envelope.id }) else { continue }
                let ns = error as NSError
                if ns.domain == FunctionsErrorDomain && [FunctionsErrorCode.invalidArgument.rawValue, FunctionsErrorCode.outOfRange.rawValue, FunctionsErrorCode.notFound.rawValue].contains(ns.code) {
                    pending.remove(at: current)
                } else {
                    pending[current].attempts += 1
                    let delay = ns.domain == FunctionsErrorDomain && ns.code == FunctionsErrorCode.resourceExhausted.rawValue
                        ? 900.0 : min(900, 5 * pow(2, Double(min(pending[current].attempts, 8))))
                    pending[current].nextAttemptAt = now().addingTimeInterval(delay)
                    persist()
                    break
                }
            }
            persist()
        }
    }

    private func prune() { pending.removeAll { now().timeIntervalSince($0.occurredAt) >= 48 * 3600 || $0.occurredAt > now().addingTimeInterval(300) } }
    private func save() throws { defaults.set(try JSONEncoder().encode(pending), forKey: storageKey) }
    private func persist() { try? save() }
    private func scheduleRetry() {
        guard automaticallyDelivers, let uid = principal(), let date = pending.filter({ $0.principalID == uid }).map(\.nextAttemptAt).min() else { return }
        retryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(1, date.timeIntervalSince(self?.now() ?? Date())))) } catch { return }
            await self?.flush()
        }
    }
}
