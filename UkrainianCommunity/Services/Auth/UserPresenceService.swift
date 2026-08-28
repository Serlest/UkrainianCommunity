import Foundation
import FirebaseAuth
import FirebaseFunctions
import UIKit

struct UserPresenceUpdate: Codable, Equatable {
    let userId: String
    let sessionId: String
    let sequence: Int
    let active: Bool
}

struct ManagedUserPresenceResponse: Codable {
    let targetUserId: String
    let lastSeenAt: Double?
    let onlineUntil: Double?
    let serverTime: Double
}

struct ManagedUserPresenceSnapshot {
    let lastSeenAt: Date?
    private let onlineDeadline: ContinuousClock.Instant

    init(response: ManagedUserPresenceResponse, requestStartedAt: ContinuousClock.Instant) {
        lastSeenAt = response.lastSeenAt.map { Date(timeIntervalSince1970: $0 / 1_000) }
        // Anchor expiry to monotonic local time, conservatively including request latency.
        // A wrong phone clock must not keep someone online or erase their activity date.
        let remaining = min(180, max(0, ((response.onlineUntil ?? response.serverTime) - response.serverTime) / 1_000))
        onlineDeadline = requestStartedAt.advanced(by: .seconds(remaining))
    }

    func isOnline(at instant: ContinuousClock.Instant = .now) -> Bool {
        instant < onlineDeadline
    }
}

@MainActor
enum UserPresenceAPI {
    private struct Acknowledgement: Decodable { let accepted: Bool }
    private struct ReadRequest: Encodable { let targetUserId: String }

    static func send(_ update: UserPresenceUpdate) async throws {
        // Never let a queued task write presence for a newly selected account.
        guard Auth.auth().currentUser?.uid == update.userId else { return }
        var callable: Callable<UserPresenceUpdate, Acknowledgement> = Functions.functions(region: "europe-west3")
            .httpsCallable("updateUserPresence")
        callable.timeoutInterval = 15
        // No persistent offline queue and no background retry loop for presence.
        _ = try await callable.call(update)
    }

    static func load(userID: String) async throws -> ManagedUserPresenceSnapshot {
        let started = ContinuousClock.now
        var callable: Callable<ReadRequest, ManagedUserPresenceResponse> = Functions.functions(region: "europe-west3")
            .httpsCallable("getManagedUserPresence")
        callable.timeoutInterval = 15
        let response = try await callable.call(ReadRequest(targetUserId: userID))
        guard response.targetUserId == userID else { throw URLError(.badServerResponse) }
        return ManagedUserPresenceSnapshot(response: response, requestStartedAt: started)
    }
}

@MainActor
final class UserPresenceService {
    typealias Sender = (UserPresenceUpdate) async throws -> Void
    private let send: Sender
    private let interval: Duration
    private var userID: String?
    private var sessionID = UUID().uuidString
    private var sequence = 0
    private var active = false
    private var heartbeatTask: Task<Void, Never>?

    init(interval: Duration = .seconds(90), send: @escaping Sender = UserPresenceAPI.send) {
        self.interval = interval
        self.send = send
    }

    func update(userID nextUserID: String?, isActive: Bool) {
        let nextActive = nextUserID != nil && isActive
        guard nextUserID != userID || nextActive != active else { return }
        heartbeatTask?.cancel()
        heartbeatTask = nil
        let wasActive = active
        let sameUser = nextUserID == userID
        if nextUserID != userID {
            if active { publish(active: false) }
            userID = nextUserID
            sessionID = UUID().uuidString
            sequence = 0
        }
        active = nextActive
        if nextActive || (sameUser && wasActive) { publish(active: nextActive) }
        guard nextActive else { return }
        let interval = interval
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: interval) } catch { return }
                guard !Task.isCancelled, let self, self.active else { return }
                self.publish(active: true)
            }
        }
    }

    private func publish(active: Bool) {
        guard let userID else { return }
        sequence += 1
        let update = UserPresenceUpdate(userId: userID, sessionId: sessionID, sequence: sequence, active: active)
        let send = send
        Task {
            let backgroundTask = active ? UIBackgroundTaskIdentifier.invalid
                : UIApplication.shared.beginBackgroundTask(withName: "Presence offline")
            defer {
                if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
            }
            // Transient failures are expected; the server lease expires without a successful heartbeat.
            // Do not flood the technical/security journal with periodic connectivity errors.
            try? await send(update)
        }
    }
}
