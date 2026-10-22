import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct SystemLogDeliveryQueueTests {
    private func draft(_ uid: String = "account-a") -> SystemLogDraft {
        SystemLogDraft(category: .diagnostics, severity: .warning, eventType: .technicalError,
                       actorUserId: uid, summary: "Network failure", technicalMessage: "bearer private-token",
                       metadata: ["token": "must-not-persist", "failureStage": "fetchResponse"])
    }

    @Test func offlineFailurePersistsRedactedEnvelopeAndRetriesAfterRestart() async throws {
        let suite = "journal-test-\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var clock = Date()
        let queue = SystemLogDeliveryQueue(defaults: defaults, now: { clock }, principal: { "account-a" }, automaticallyDelivers: false) { _ in
            throw NSError(domain: NSURLErrorDomain, code: -1009)
        }
        try queue.enqueue(draft())
        let id = try #require(queue.pending.first?.id)
        await queue.flush()
        #expect(queue.pending.count == 1)
        #expect(queue.pending[0].attempts == 1)
        #expect(queue.pending[0].draft.metadata["token"] == "[redacted]")
        #expect(queue.pending[0].draft.technicalMessage == "[redacted]")
        clock = clock.addingTimeInterval(100)
        var sent: [SystemLogDeliveryQueue.Envelope] = []
        let restored = SystemLogDeliveryQueue(defaults: defaults, now: { clock }, principal: { "account-a" }, automaticallyDelivers: false) { sent.append($0) }
        await restored.flush()
        #expect(sent.map(\.id) == [id]); #expect(restored.pending.isEmpty)
    }

    @Test func accountSwitchNeverReattributesAndAnonymousFailureIsNotAssignedToFutureLogin() async throws {
        let suite = "journal-test-\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var uid: String? = nil
        var sent: [String] = []
        let queue = SystemLogDeliveryQueue(defaults: defaults, principal: { uid }, automaticallyDelivers: false) { sent.append($0.principalID) }
        var anonymous = draft(); anonymous.actorUserId = nil
        try queue.enqueue(anonymous); #expect(queue.pending.isEmpty)
        uid = "account-a"; try queue.enqueue(draft())
        uid = "account-b"; await queue.flush(); #expect(sent.isEmpty); #expect(queue.pending.count == 1)
        uid = "account-a"; await queue.flush(); #expect(sent == ["account-a"])
    }

    @Test func queueIsBoundedAndExpiresUndeliverableRecords() throws {
        let suite = "journal-test-\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var clock = Date()
        let queue = SystemLogDeliveryQueue(defaults: defaults, now: { clock }, principal: { "account-a" }, automaticallyDelivers: false) { _ in }
        for _ in 0..<205 { try queue.enqueue(draft()) }
        #expect(queue.pending.count == 200)
        clock = clock.addingTimeInterval(49 * 3600)
        let restored = SystemLogDeliveryQueue(defaults: defaults, now: { clock }, principal: { "account-a" }, automaticallyDelivers: false) { _ in }
        #expect(restored.pending.isEmpty)
    }
}
